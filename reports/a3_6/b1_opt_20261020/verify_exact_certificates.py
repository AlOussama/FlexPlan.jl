"""Separate exact verifier for LP bound derivations, primal points and inclusion."""
from pathlib import Path
from fractions import Fraction as Q
from collections import Counter
import json,sys,itertools,hashlib,copy
R=Path(sys.argv[1]);results=[];tests=0
def load(p):return json.loads(p.read_text())
def check(v,msg):
    global tests
    tests+=1
    if not v:raise AssertionError(msg)
def affine(f):
    if f['type']=='Variable':return {f['name']:Q(1)},Q(0)
    assert f['type']=='ScalarAffineFunction'
    d=Counter()
    for t in f['terms']:d[t['variable']]+=Q(t['coefficient'])
    return {n:v for n,v in d.items() if v},Q(f['constant'])
def val(f,x):
    a,c=affine(f);return c+sum((a[n]*x[n] for n in a),Q(0))
def det(a):
    a=[r.copy() for r in a];result=Q(1)
    for i in range(len(a)):
        pivot=next((k for k in range(i,len(a)) if a[k][i]),None)
        if pivot is None:return Q(0)
        if pivot!=i:a[i],a[pivot]=a[pivot],a[i];result=-result
        p=a[i][i];result*=p
        for k in range(i+1,len(a)):
            z=a[k][i]/p
            for j in range(i+1,len(a)):a[k][j]-=z*a[i][j]
    return result
def point_check(m,x):
    failed=[]
    for ci,c in enumerate(m['constraints']):
        f=c['function'];s=c['set'];typ=s['type']
        if f['type'] in ['Variable','ScalarAffineFunction']:
            v=val(f,x)
            if typ=='EqualTo':ok=v==Q(s['value'])
            elif typ=='GreaterThan':ok=v>=Q(s['lower'])
            elif typ=='LessThan':ok=v<=Q(s['upper'])
            elif typ=='Interval':ok=Q(s['lower'])<=v<=Q(s['upper'])
            elif typ=='Integer':ok=v.denominator==1
            elif typ=='ZeroOne':ok=v in [0,1]
            else:raise ValueError(typ)
        else:
            assert f['type']=='VectorAffineFunction'
            vs=list(map(Q,f['constants']))
            for t in f['terms']:vs[t['output_index']-1]+=Q(t['scalar_term']['coefficient'])*x[t['scalar_term']['variable']]
            if typ=='RotatedSecondOrderCone':ok=vs[0]>=0 and vs[1]>=0 and 2*vs[0]*vs[1]>=sum((v*v for v in vs[2:]),Q(0))
            elif typ=='PositiveSemidefiniteConeTriangle':
                n=s['side_dimension'];a=[[Q(0)]*n for _ in range(n)];idx=0
                for j in range(n):
                    for i in range(j+1):a[i][j]=a[j][i]=vs[idx];idx+=1
                ok=all(det([[a[i][j] for j in sub] for i in sub])>=0 for k in range(1,n+1) for sub in itertools.combinations(range(n),k))
            else:raise ValueError(typ)
        if not ok:failed.append(ci)
    return failed
def rowkey(a,l,u):return (tuple(sorted((str(i),str(v)) for i,v in a.items() if v)),None if l is None else str(l),None if u is None else str(u))
def modelrows(m):
    rows=Counter()
    for c in m['constraints']:
        f=c['function'];s=c['set'];t=s['type']
        if t in ['Integer','ZeroOne','RotatedSecondOrderCone','PositiveSemidefiniteConeTriangle']:continue
        a,k=affine(f);l=s.get('value',s.get('lower'));u=s.get('value',s.get('upper'))
        rows[rowkey(a,None if l is None else Q(l)-k,None if u is None else Q(u)-k)]+=1
    return rows
def dual_check(inp,cert):
    assert hashlib.sha256(json.dumps(inp).encode()).hexdigest() # ensure input is serializable
    ids={v['index']:v['name'] for v in inp['variables']};bounds={i:[None,None] for i in ids};rows=[]
    for r in inp['rows']:
        a={t['index']:Q(t['coefficient']) for t in r['terms'] if t['coefficient']}
        l=None if r['lower'] is None else Q(r['lower'])-Q(r['constant']);u=None if r['upper'] is None else Q(r['upper'])-Q(r['constant']);rows.append((a,l,u))
    for key,proof in cert['bound_provenance'].items():
        i,endpoint=map(int,key.split(':'));a,l,u=rows[proof['row']];rhs=u if proof['direction']=='upper' else l
        assert rhs is not None
        other=Q(0)
        for j,aj in a.items():
            if j==i:continue
            k=(0 if aj>0 else 1) if proof['direction']=='upper' else (1 if aj>0 else 0)
            assert bounds[j][k] is not None
            other+=aj*bounds[j][k]
        actual=(rhs-other)/a[i];expected_endpoint=1 if (proof['direction']=='upper')==(a[i]>0) else 0
        assert endpoint==expected_endpoint and actual==Q(proof['value']) and bounds[i][endpoint] is None
        bounds[i][endpoint]=actual
    for i,b in bounds.items():
        assert b==[None if v is None else Q(v) for v in cert['finite_variable_bounds'][str(i)]]
        assert b[0] is None or b[1] is None or b[0]<=b[1]
    residual={i:Q(0) for i in ids}
    for t in inp['objective']['terms']:residual[t['index']]+=Q(t['coefficient'])
    z=Q(inp['objective']['constant'])
    assert len(cert['exact_row_multipliers'])==len(rows)
    for (a,l,u),ys in zip(rows,cert['exact_row_multipliers']):
        y=Q(ys)
        if not y:continue
        assert (l is not None if y>0 else u is not None)
        z+=y*(l if y>0 else u)
        for i,v in a.items():residual[i]-=y*v
    correction=Q(0)
    for i,v in residual.items():
        assert v==Q(cert['exact_stationarity_residuals'].get(str(i),'0'))
        if v:
            b=bounds[i][0 if v>0 else 1];assert b is not None;correction+=v*b
    assert z==Q(cert['dual_value_exact']) and correction==Q(cert['residual_correction_exact'])
    assert z+correction==Q(cert['certified_LB_exact'])
    return z+correction
for p in sorted((R/'model_inclusion').glob('*_BASE.mof.json')):
    case=p.name.removesuffix('_BASE.mof.json');base=load(p);br=modelrows(base)
    for fid in ['G0','G3']:
        m=load(p.with_name(f'{case}_{fid}.mof.json'));rr=modelrows(m)
        check(not(br-rr),f'{case} BASE inclusion in {fid}')
        check(affine(base['objective']['function'])==affine(m['objective']['function']),f'{case} common emitted objective')
        x={n:Q(v) for n,v in load(R/'exact_primals'/f'{case}_point.json').items()}
        check(not point_check(m,x),f'{case} exact primal {fid}')
        bad=x.copy();name=next(n for n in x if '_n_block[' in n);bad[name]+=Q(1,2)
        check(bool(point_check(m,bad)),f'{case} integer mutation rejected {fid}')
    row={'case_id':case,'inclusion_verified':True,'G0_and_G3_exact_primal_verified':True}
    for folder in ['lp_bounds','lp_bounds_raw_currency']:
        inp=load(R/folder/f'{case}_dual_input.json');cert=load(R/folder/f'{case}_exact_LB.json')
        check(hashlib.sha256((R/folder/f'{case}_dual_input.json').read_bytes()).hexdigest()==cert['input_sha256'],f'{case} input hash')
        bound=dual_check(inp,cert);check(True,f'{case} exact dual proof')
        # Check that each dual row belongs to the common LP model, including multiplicity.
        byidx={v['index']:v['name'] for v in inp['variables']};ir=Counter()
        for r in inp['rows']:
            a={byidx[t['index']]:Q(t['coefficient']) for t in r['terms']};l=r['lower'];u=r['upper'];k=Q(r['constant'])
            ir[rowkey(a,None if l is None else Q(l)-k,None if u is None else Q(u)-k)]+=1
        check(ir==br,f'{case} LP row identity')
        if folder=='lp_bounds':ub=Q(load(R/'exact_primals'/f'{case}_result.json')['objective_exact'])
        else:
            mapping=load(R/folder/f'{case}_objective_mapping.json');ub=Q(mapping['rigorous_raw_currency_UB_exact'])
            objective=Q(inp['objective']['constant'])+sum((Q(t['coefficient'])*x[byidx[t['index']]] for t in inp['objective']['terms']),Q(0))
            check(objective==ub,f'{case} raw currency upper bound')
        check(bound<=ub,f'{case} signed exact interval')
        bad=copy.deepcopy(cert);bad['certified_LB_exact']=str(bound+1)
        try:dual_check(inp,bad)
        except AssertionError:check(True,f'{case} altered LB rejected')
        else:check(False,f'{case} altered LB accepted')
        row[folder]={'LB_exact':str(bound),'UB_exact':str(ub),'LB':float(bound),'UB':float(ub),'signed_gap_exact':str(ub-bound),'signed_gap':float(ub-bound)}
    results.append(row);print(case,'verified gaps',row['lp_bounds']['signed_gap'],row['lp_bounds_raw_currency']['signed_gap'],flush=True)
(R/'exact_certificate_verification.json').write_text(json.dumps({'tests_passed':tests,'cases':results,'exact_arithmetic':'fractions.Fraction; PSD checked by all principal minors independently of the recovery LDL check'},indent=2))
print('Exact certificate verification',tests,'passed')
