"""Independent exact checks, separate from the submitted verifier/recovery code.

No solver tolerance is used. Lower bounds follow directly from weak duality:
c'x+c0 >= c0+sum(y*b)+sum(min(r_i*l_i,r_i*u_i)).
Only endpoints established by the stored original-row inferences are used.
"""
from pathlib import Path
from fractions import Fraction as F
from collections import Counter, defaultdict
from itertools import combinations
import hashlib, json, sys
W=Path(sys.argv[1]); R=Path(sys.argv[2]); P=R/'prior'
def load(p): return json.loads(p.read_text(encoding='utf-8'))
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def aff(f):
    if f['type']=='Variable': return {f['name']:F(1)},F(0)
    assert f['type']=='ScalarAffineFunction'
    a=defaultdict(F)
    for t in f['terms']: a[t['variable']]+=F(t['coefficient'])
    return {k:v for k,v in a.items() if v},F(f['constant'])
def evaluate(f,x):
    if f['type']=='VectorAffineFunction':
        a=list(map(F,f['constants']))
        for t in f['terms']: a[t['output_index']-1]+=F(t['scalar_term']['coefficient'])*x[t['scalar_term']['variable']]
        return a
    a,b=aff(f); return b+sum((c*x[n] for n,c in a.items()),F(0))
def determinant(a):
    if not a: return F(1)
    return sum(((-1)**j*a[0][j]*determinant([[row[k] for k in range(len(a)) if k!=j] for row in a[1:]]) for j in range(len(a))),F(0))
def primal(m,x):
    assert len({v['name'] for v in m['variables']})==len(m['variables'])
    assert {v['name'] for v in m['variables']}<=set(x)
    counts=Counter(); minors=0
    for ci,row in enumerate(m['constraints']):
        s=row['set']; t=s['type']; v=evaluate(row['function'],x); counts[t]+=1
        if t=='Integer': good=v.denominator==1
        elif t=='ZeroOne': good=v in (0,1)
        elif t=='EqualTo': good=v==F(s['value'])
        elif t=='LessThan': good=v<=F(s['upper'])
        elif t=='GreaterThan': good=v>=F(s['lower'])
        elif t=='Interval': good=F(s['lower'])<=v<=F(s['upper'])
        elif t=='RotatedSecondOrderCone': good=v[0]>=0 and v[1]>=0 and 2*v[0]*v[1]>=sum(z*z for z in v[2:])
        elif t=='PositiveSemidefiniteConeTriangle':
            n=s['side_dimension']; assert n<=5
            a=[[F(0) for _ in range(n)] for _ in range(n)]; k=0
            for j in range(n):
                for i in range(j+1): a[i][j]=a[j][i]=v[k]; k+=1
            good=True
            for size in range(1,n+1):
                for subset in combinations(range(n),size):
                    minors+=1; good=good and determinant([[a[i][j] for j in subset] for i in subset])>=0
        else: raise ValueError(t)
        assert good,(ci,t)
    return {'constraints':dict(counts),'principal_minors':minors}
def key(a,l,u): return (tuple(sorted((n,str(v)) for n,v in a.items() if v)),None if l is None else str(l),None if u is None else str(u))
def model_rows(m):
    out=Counter()
    for r in m['constraints']:
        s=r['set']; t=s['type']
        if t in ('Integer','ZeroOne','RotatedSecondOrderCone','PositiveSemidefiniteConeTriangle'): continue
        a,c=aff(r['function']); l=s.get('value',s.get('lower')); u=s.get('value',s.get('upper'))
        out[key(a,None if l is None else F(l)-c,None if u is None else F(u)-c)]+=1
    return out
def dual(inp,cert,base,objective):
    names={v['index']:v['name'] for v in inp['variables']}; assert len(names)==len(set(names.values()))
    rows=[]; identity=Counter()
    for r in inp['rows']:
        a=defaultdict(F)
        for t in r['terms']: a[t['index']]+=F(t['coefficient'])
        a={i:v for i,v in a.items() if v}; c=F(r['constant'])
        l=None if r['lower'] is None else F(r['lower'])-c; u=None if r['upper'] is None else F(r['upper'])-c
        rows.append((a,l,u)); identity[key({names[i]:v for i,v in a.items()},l,u)]+=1
    assert identity==base
    costs=defaultdict(F)
    for t in inp['objective']['terms']: costs[names[t['index']]]+=F(t['coefficient'])
    assert ({k:v for k,v in costs.items() if v},F(inp['objective']['constant']))==objective
    bounds={i:[None,None] for i in names}; pending=dict(cert['bound_provenance']); inferences=0
    while pending:
        progress=False
        for k,p in list(pending.items()):
            i,end=map(int,k.split(':')); a,l,u=rows[p['row']]; upper=p['direction']=='upper'; assert p['direction'] in ('upper','lower')
            rhs=u if upper else l; assert rhs is not None and i in a
            other=F(0); ready=True
            for j,c in a.items():
                if j==i: continue
                endpoint=(0 if c>0 else 1) if upper else (1 if c>0 else 0)
                if bounds[j][endpoint] is None: ready=False; break
                other+=c*bounds[j][endpoint]
            if not ready: continue
            assert end==(1 if upper==(a[i]>0) else 0)
            value=(rhs-other)/a[i]; assert value==F(p['value']) and bounds[i][end] is None
            bounds[i][end]=value; del pending[k]; progress=True; inferences+=1
        assert progress,'Cyclic or unsupported bound proof'
    for i,b in bounds.items():
        assert b==[None if z is None else F(z) for z in cert['finite_variable_bounds'][str(i)]]
        assert b[0] is None or b[1] is None or b[0]<=b[1]
    residual={i:costs[names[i]] for i in names}; z=F(inp['objective']['constant'])
    assert len(rows)==len(cert['exact_row_multipliers'])
    for (a,l,u),mult in zip(rows,cert['exact_row_multipliers']):
        y=F(mult)
        if not y: continue
        endpoint=l if y>0 else u; assert endpoint is not None
        z+=y*endpoint
        for i,c in a.items(): residual[i]-=y*c
    correction=F(0)
    for i,c in residual.items():
        assert c==F(cert['exact_stationarity_residuals'].get(str(i),'0'))
        if c:
            endpoint=bounds[i][0 if c>0 else 1]; assert endpoint is not None; correction+=c*endpoint
    assert z==F(cert['dual_value_exact']) and correction==F(cert['residual_correction_exact'])
    assert z+correction==F(cert['certified_LB_exact'])
    return z+correction,inferences

ledger=load(W/'reports/a3_6/b1_opt_20261020/integer_9cases_bounds.json'); assert len(ledger)==9
summary=[]
for entry in ledger:
    case=entry['case_id']; M={fid:load(P/'model_inclusion'/f'{case}_{fid}.mof.json') for fid in ['BASE','G0','G3']}
    x={n:F(v) for n,v in load(P/'exact_primals'/f'{case}_point.json').items()}
    br=model_rows(M['BASE']); obj=aff(M['BASE']['objective']['function'])
    report={'case_id':case,'primal':{}}
    for fid in ['G0','G3']:
        assert not(br-model_rows(M[fid])); assert aff(M[fid]['objective']['function'])==obj
        report['primal'][fid]=primal(M[fid],x)
        bad=x.copy(); n=next(r['function']['name'] for r in M[fid]['constraints'] if r['set']['type']=='Integer'); bad[n]+=F(1,2)
        try: primal(M[fid],bad)
        except AssertionError: pass
        else: raise AssertionError('Noninteger mutation accepted')
    for folder in ['lp_bounds','lp_bounds_raw_currency']:
        inp=load(P/folder/f'{case}_dual_input.json'); cert=load(P/folder/f'{case}_exact_LB.json')
        assert digest(P/folder/f'{case}_dual_input.json')==cert['input_sha256']
        assert cert['case_sha256']==inp['case_sha256']==entry['raw_case_sha256']
        if folder=='lp_bounds': target=obj
        else:
            # Reconstruct from raw case products with the reviewed original cost
            # routine, rather than trusting the stored raw-currency expression.
            fresh=load(R/'cost_reconstruction'/folder/f'{case}_dual_input.json')
            assert fresh['objective']==inp['objective']
            names={v['index']:v['name'] for v in fresh['variables']}
            target=({names[t['index']]:F(t['coefficient']) for t in fresh['objective']['terms']},F(fresh['objective']['constant']))
        lb,inferences=dual(inp,cert,br,target); ub=target[1]+sum((c*x[n] for n,c in target[0].items()),F(0))
        assert lb<=ub
        if folder=='lp_bounds':
            assert ub==F(load(P/'exact_primals'/f'{case}_result.json')['objective_exact'])
            assert lb==F(entry['serialized_objective_interval']['LB_exact']) and ub==F(entry['serialized_objective_interval']['UB_exact'])
        else:
            assert lb==F(entry['LB_exact']) and ub==F(entry['UB_exact']) and ub-lb==F(entry['signed_interval_width_exact'])
            assert F(entry['LB_currency_outward'])<=lb and F(entry['UB_currency_outward'])>=ub
        broken=dict(cert); broken['certified_LB_exact']=str(lb+1)
        try: dual(inp,broken,br,target)
        except AssertionError: pass
        else: raise AssertionError('False LB accepted')
        report[folder]={'LB_exact':str(lb),'UB_exact':str(ub),'width_exact':str(ub-lb),'width':float(ub-lb),'bound_inferences_verified':inferences}
    casefile=W/'reports/ap3_runs/20261020_macro/accepted_suite'/case/'case.json'; assert digest(casefile)==entry['raw_case_sha256']
    summary.append(report); print(case,'independent exact validation PASS',flush=True)

# Check the extended feasible point in the actual original serialized MISOCP.
native=load(P/'original_01/b1_exact_native.mof.json'); nx={n:F(v) for n,v in load(P/'exact_primals/reference_24snap_native_point.json').items()}
native_report=primal(native,nx)

# Both actual Float64 objective transformations are reconstructed separately.
transforms=[]
for archived in load(P/'objective_transform_audit.json'):
    case=archived['case_id']; mode=archived['mode']; scale=F(archived['scale'])
    m=load(P/'objective_snapshots'/f'{case}_{mode}.mof.json'); original=load(P/'model_inclusion'/f'{case}_G3.mof.json')
    names={v['name'] for v in original['variables']}; a,c=aff(m['objective']['function']); a={n:v*scale for n,v in a.items()}; c*=scale
    equations=[]
    for row in m['constraints']:
        if row['set']['type']=='EqualTo':
            co,k=aff(row['function']); equations.append((co,F(row['set']['value'])-k))
    for n in list(a):
        if n in names: continue
        candidates=[(co,b) for co,b in equations if n in co and set(co)-names=={n}]; assert len(candidates)==1
        co,b=candidates[0]; z=a.pop(n)/co[n]; c+=z*b
        for j,v in co.items():
            if j!=n: a[j]=a.get(j,F(0))-z*v
    ca,c0=aff(original['objective']['function']); delta={n:a.get(n,F(0))-ca.get(n,F(0)) for n in set(a)|set(ca)}; delta={n:v for n,v in delta.items() if v}
    assert c-c0==F(archived['exact_currency_delta_constant'])
    assert delta=={n:F(v) for n,v in archived['exact_currency_delta_coefficients'].items()}
    px={n:F(v) for n,v in load(P/'exact_primals'/f'{case}_point.json').items()}
    dv=c-c0+sum((v*px[n] for n,v in delta.items()),F(0)); assert dv==F(archived['delta_at_exact_primal'])
    transforms.append({'case_id':case,'mode':mode,'scale_exact':str(scale),'delta_at_point_exact':str(dv),'delta_terms':len(delta),'native_global_bound_certified':False})
assert len(transforms)==18

# Inspect the rows after coefficient filtering, without mistaking this witness
# check for a globally validated cut or a complete MIP tree certificate.
oa=load(P/'experiments/stages/oa_frozen.mof.json'); affected={}
for threshold in [1e-9,1e-12]:
    tiny=[]; emptied=[]
    for ci,row in enumerate(oa['constraints']):
        f=row['function']
        if f['type']=='VectorAffineFunction':
            byrow=defaultdict(list)
            for term in f['terms']: byrow[term['output_index']].append(F(term['scalar_term']['coefficient']))
            for ri,terms in byrow.items():
                dropped=[v for v in terms if 0<abs(v)<=F(threshold)]
                if dropped: tiny.append([ci,ri,len(dropped)])
                if dropped and len(dropped)==len([v for v in terms if v]): emptied.append([ci,ri,str(F(f['constants'][ri-1]))])
        elif f['type']=='ScalarAffineFunction':
            terms=[F(t['coefficient']) for t in f['terms'] if t['coefficient']]; dropped=[v for v in terms if abs(v)<=F(threshold)]
            if dropped: tiny.append([ci,0,len(dropped)])
            if dropped and len(terms)==len(dropped): emptied.append([ci,0,str(F(f['constant']))])
    affected[str(threshold)]={'affected_rows':tiny,'emptied_rows':emptied,'dropped_terms':sum(t[2] for t in tiny)}
out={'cases_verified':len(summary),'cases':summary,'original_native':native_report,'objective_transforms':transforms,'frozen_oa_filter':affected,'scope':'exact normalized constraints and declared raw-currency objective; no exact optimality or global OA/tree certificate'}
(R/'independent_certificates.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print('PASS: 9 cases, 18 primal checks, 18 LP certificates, 18 objective transforms; original native point checked')
