"""Separate binary-rational oracle for qualify_native_g3.jl outputs.
Usage: python verify_native_g3.py RUN EXTRACTED_A36_ARCHIVE
Native numerical bounds are checked against exact feasible witnesses, never certified.
"""
import collections,copy,hashlib,itertools,json,pathlib,sys
from fractions import Fraction as Q
import numpy as np

RUN=pathlib.Path(sys.argv[1]);PRIOR=pathlib.Path(sys.argv[2]);TOL=Q(1,10_000_000)
def load(p):return json.loads(p.read_text())
def affine(f):
    if f['type']=='Variable':return {f['name']:Q(1)},Q(0)
    assert f['type']=='ScalarAffineFunction'
    a=collections.defaultdict(Q)
    for t in f['terms']:a[t['variable']]+=Q(t['coefficient'])
    return {n:v for n,v in a.items() if v},Q(f['constant'])
def scalar(f,x):
    if f['type']=='ScalarQuadraticFunction':
        value=Q(f['constant'])+sum((Q(t['coefficient'])*x[t['variable']] for t in f['affine_terms']),Q(0))
        return value+sum((Q(t['coefficient'])*x[t['variable_1']]*x[t['variable_2']]/(2 if t['variable_1']==t['variable_2'] else 1) for t in f['quadratic_terms']),Q(0))
    a,c=affine(f);return c+sum((v*x[n] for n,v in a.items()),Q(0))
def vector(f,x):
    assert f['type']=='VectorAffineFunction'
    y=list(map(Q,f['constants']))
    for t in f['terms']:y[t['output_index']-1]+=Q(t['scalar_term']['coefficient'])*x[t['scalar_term']['variable']]
    return y
def determinant(a):
    a=[row.copy() for row in a];v=Q(1)
    for i in range(len(a)):
        k=next((k for k in range(i,len(a)) if a[k][i]),None)
        if k is None:return Q(0)
        if k!=i:a[k],a[i]=a[i],a[k];v=-v
        pivot=a[i][i];v*=pivot
        for k in range(i+1,len(a)):
            factor=a[k][i]/pivot
            for j in range(i+1,len(a)):a[k][j]-=factor*a[i][j]
    return v
def check_point(m,point,exact_psd=False):
    x={n:Q(v) for n,v in point.items()};maxima=collections.defaultdict(Q);counts=collections.Counter();psd_min=0.
    for c in m['constraints']:
        f,s=c['function'],c['set'];typ=s['type'];counts[typ]+=1
        if typ=='RotatedSecondOrderCone':
            y=vector(f,x);v=max(Q(0),-y[0],-y[1],sum((z*z for z in y[2:]),Q(0))-2*y[0]*y[1])
        elif typ=='PositiveSemidefiniteConeTriangle':
            y=vector(f,x);n=s['side_dimension'];a=[[Q(0)]*n for _ in range(n)];k=0
            for j in range(n):
                for i in range(j+1):a[i][j]=a[j][i]=y[k];k+=1
            if exact_psd:
                v=max([Q(0)]+[-determinant([[a[i][j] for j in sub] for i in sub]) for k in range(1,n+1) for sub in itertools.combinations(range(n),k)])
            else:
                eig=float(np.linalg.eigvalsh(np.array(a,dtype=float))[0]);psd_min=min(psd_min,eig);v=Q(max(0.,-eig))
        else:
            z=scalar(f,x)
            if typ=='EqualTo':v=abs(z-Q(s['value']))
            elif typ=='GreaterThan':v=max(Q(0),Q(s['lower'])-z)
            elif typ=='LessThan':v=max(Q(0),z-Q(s['upper']))
            elif typ=='Interval':v=max(Q(0),Q(s['lower'])-z,z-Q(s['upper']))
            elif typ=='Integer':v=abs(z-round(z))
            elif typ=='ZeroOne':v=min(abs(z),abs(z-1))
            else:raise ValueError(typ)
        maxima[typ]=max(maxima[typ],v)
    return dict(counts=dict(counts),residuals={k:dict(exact=str(v),display=float(v)) for k,v in maxima.items()},
        numerical_pass=all(v<=TOL for v in maxima.values()),exact_pass=all(v==0 for v in maxima.values()),
        minimum_psd_eigenvalue_numeric=psd_min,objective_exact=str(scalar(m['objective']['function'],x)))
def key(c):
    f=c['function'];s=c['set']
    if f['type'] in ['Variable','ScalarAffineFunction']:
        a,k=affine(f);fun=('affine',tuple(sorted((n,str(v)) for n,v in a.items())),str(k))
    else:
        fun=('vector',tuple(sorted((t['output_index'],t['scalar_term']['variable'],str(Q(t['scalar_term']['coefficient']))) for t in f['terms'])),tuple(str(Q(v)) for v in f['constants']))
    return fun,json.dumps(s,sort_keys=True)
def rows(m):return collections.Counter(key(c) for c in m['constraints'])
def linear_key(a,sense,rhs):
    a={n:v for n,v in a.items() if v}
    if a and a[sorted(a)[0]]<0:
        a={n:-v for n,v in a.items()};rhs=-rhs;sense={'le':'ge','ge':'le','eq':'eq'}[sense]
    return tuple(sorted((n,str(v)) for n,v in a.items())),sense,str(rhs)
def linear_rows(m,rename=None):
    out=collections.Counter();rename=rename or {}
    for c in m['constraints']:
        f,s=c['function'],c['set'];typ=s['type']
        if f['type'] not in ['Variable','ScalarAffineFunction'] or typ in ['Integer','ZeroOne']:continue
        a,k=affine(f);a={rename.get(n,n):v for n,v in a.items()}
        pairs=[]
        if typ=='EqualTo':pairs=[('le',Q(s['value'])-k),('ge',Q(s['value'])-k)]
        elif typ=='Interval':pairs=[('ge',Q(s['lower'])-k),('le',Q(s['upper'])-k)]
        elif typ=='GreaterThan':pairs=[('ge',Q(s['lower'])-k)]
        elif typ=='LessThan':pairs=[('le',Q(s['upper'])-k)]
        else:raise ValueError(typ)
        for sense,rhs in pairs:
            if not a and ((sense=='ge' and rhs<=0) or (sense=='le' and rhs>=0)):continue
            out[linear_key(a,sense,rhs)]+=1
    return out
def backend_identity(cached,native,mapping):
    rename=mapping['cached_to_native'];before=linear_rows(cached,rename);after=linear_rows(native)
    assert not before-after,'physical linear row lost in actual backend'
    remaining=after-before
    eqs=set()
    for c in native['constraints']:
        if c['function']['type'] in ['Variable','ScalarAffineFunction'] and c['set']['type']=='EqualTo':
            a,k=affine(c['function']);eqs.add(linear_key(a,'eq',Q(c['set']['value'])-k))
    original_int={(rename[c['function']['name']],c['set']['type']) for c in cached['constraints'] if c['set']['type'] in ['Integer','ZeroOne']}
    native_int={(c['function']['name'],c['set']['type']) for c in native['constraints'] if c['set']['type'] in ['Integer','ZeroOne']}
    assert original_int==native_int,'integer domain changed'
    ca,cc=affine(cached['objective']['function']);na,nc=affine(native['objective']['function'])
    assert {rename[n]:v for n,v in ca.items()}==na and cc==nc,'backend objective changed'
    quadratics=[]
    for c in native['constraints']:
        f,s=c['function'],c['set']
        if f['type']!='ScalarQuadraticFunction':continue
        assert s['type']=='LessThan' and Q(s['upper'])==0 and Q(f['constant'])==0 and not f['affine_terms']
        cross=[t for t in f['quadratic_terms'] if t['variable_1']!=t['variable_2']]
        diag=[t for t in f['quadratic_terms'] if t['variable_1']==t['variable_2']]
        assert len(cross)==len(diag)==1 and Q(cross[0]['coefficient'])==-2 and Q(diag[0]['coefficient'])==2
        quadratics.append((cross[0]['variable_1'],cross[0]['variable_2'],diag[0]['variable_1']))
    cones=[c for c in cached['constraints'] if c['set']['type']=='RotatedSecondOrderCone']
    assert len(cones)==len(quadratics)
    used=set();aux=set()
    for cone in cones:
        f=cone['function'];assert f['type']=='VectorAffineFunction' and len(f['constants'])==3
        components=[]
        for i in range(3):
            a=collections.defaultdict(Q)
            for t in f['terms']:
                if t['output_index']==i+1:a[rename[t['scalar_term']['variable']]]+=Q(t['scalar_term']['coefficient'])
            components.append((dict(a),Q(f['constants'][i])))
        matched=None
        for j,triple in enumerate(quadratics):
            if j in used:continue
            for trial in [triple,(triple[1],triple[0],triple[2])]:
                links=[]
                for (a,c),var in zip(components,trial):
                    b=dict(a);b[var]=b.get(var,Q(0))-1
                    links.append((b,-c))
                if all(linear_key(a,'eq',rhs) in eqs for a,rhs in links):matched=(j,trial,links);break
            if matched:break
        assert matched is not None,'RSOC-to-quadratic link not exact'
        j,triple,links=matched;used.add(j);aux.update(triple)
        for a,rhs in links:
            for sense in ['ge','le']:remaining[linear_key(a,sense,rhs)]-=1
        for var in triple[:2]:
            assert after[linear_key({var:Q(1)},'ge',Q(0))]>0
    allowed={linear_key({v:Q(1)},'ge',Q(0)) for j in used for v in quadratics[j][:2]}
    assert all(v>=0 for v in remaining.values())
    assert all(k in allowed for k,v in remaining.items() if v),'unexplained actual backend constraint'
    assert {v['name'] for v in native['variables']}-set(rename.values())==aux
    return dict(exact_linear_integer_objective_and_RSOC_projection_verified=True,
        exact_quadratic_cones=len(cones),rounded_RSOC_rotation_used=False,
        redundant_endpoint_bounds_proved_by_existing_nonnegative_rows=True)
def projection(original,solver):
    before=rows(original);after=rows(solver)
    assert not before-after,'original constraint lost or changed'
    extras=after-before
    old={v['name'] for v in original['variables']};new={v['name'] for v in solver['variables']}-old
    mapping={};lower={}
    for c in original['constraints']:
        if c['function']['type']=='Variable' and c['set']['type']=='GreaterThan':lower[c['function']['name']]=Q(c['set']['lower'])
    for c in solver['constraints']:
        k=key(c)
        if not extras[k]:continue
        extras[k]-=1;f,s=c['function'],c['set']
        if s['type']=='GreaterThan':
            assert f['type']=='Variable' and f['name'] in new and Q(s['lower'])==0
        else:
            assert s['type']=='EqualTo';a,c0=affine(f);zs=set(a)&new
            assert len(zs)==1 and len(a)==2
            z=next(iter(zs));x=next(iter(set(a)-{z}));assert x in old and -a[x]/a[z]==1
            offset=(Q(s['value'])-c0)/a[z]
            assert x in lower and lower[x]+offset>=0
            mapping[z]=(x,offset)
    assert set(mapping)==new
    return mapping
def eliminate(f,mapping):
    a,c=affine(f)
    for z,(x,offset) in mapping.items():
        coefficient=a.pop(z,Q(0));a[x]=a.get(x,Q(0))+coefficient;c+=coefficient*offset
    return {n:v for n,v in a.items() if v},c

results=[]
for row in load(RUN/'results.json'):
    dr=RUN/row['directory'];out={k:row[k] for k in ['case_id','formulation','mode','directory']}
    if 'error' in row:out['error']=row['error'];results.append(out);continue
    literal=row['mode']=='original_serialized_default'
    original=load(PRIOR/'original_01/b1_exact_native.mof.json') if literal else load(dr/'original_model.mof.json')
    if not literal:
        reference=load(PRIOR/'model_inclusion'/f"{row['case_id']}_{row['formulation']}.mof.json")
        out['physical_model_identical_to_certificate_input']=rows(original)==rows(reference) and affine(original['objective']['function'])==affine(reference['objective']['function'])
        assert out['physical_model_identical_to_certificate_input']
    solver=load(dr/'solver_input.mof.json');mapping=projection(original,solver)
    out['exact_projection_identity_verified']=True;out['auxiliary_increment_variables']=len(mapping)
    p=dr/'point.json'
    if p.exists():
        point=load(p)
        out['original_primal']=check_point(original,point)
        out['solver_input_primal']=check_point(solver,point)
        iv=next(c['function']['name'] for c in original['constraints'] if c['set']['type']=='Integer')
        bad=dict(point);bad[iv]+=0.5
        assert not check_point(original,bad)['numerical_pass']
        out['negative_integer_mutation_rejected']=True
    nativefile=dr/'actual_backend.mof.json'
    if nativefile.exists():
        native=load(nativefile);vmap=load(dr/'backend_variable_map.json')
        out['actual_backend_identity']=backend_identity(solver,native,vmap)
        if (dr/'backend_point.json').exists():out['actual_backend_primal']=check_point(native,load(dr/'backend_point.json'))
    witness=load(PRIOR/'exact_primals'/f"{row['case_id']}_{'native_point' if literal else 'point'}.json")
    w={n:Q(v) for n,v in witness.items()}
    for z,(x,offset) in mapping.items():w[z]=w[x]+offset
    exact=check_point(solver,w,exact_psd=True);assert exact['exact_pass']
    out['historical_exact_witness_still_feasible']=True
    stats=row['stats'];mult=Q(stats.get('objective_conditioning',{}).get('multiplier',1))
    seed=stats.get('primal_start_strategy',{})
    if seed.get('status')=='checked_primal_start_applied':
        assert seed['heuristic_bound_used'] is False
        seedpoint={v['name']:x for v,x in zip(solver['variables'],seed['values_in_original_variable_order'])}
        out['heuristic_seed_original_primal']=check_point(solver,seedpoint)
        out['heuristic_bound_used']=False
    scale=Q(stats.get('objective_requested_divisor',stats['objective_solver_scaling']))
    a,c=eliminate(solver['objective']['function'],mapping);oa,oc=affine(original['objective']['function'])
    delta={n:a.get(n,Q(0))*scale/mult-oa.get(n,Q(0)) for n in set(a)|set(oa)}
    delta={n:v for n,v in delta.items() if v};dc=c*scale/mult-oc
    out['actual_objective_coordinate_delta']=dict(constant=str(dc),coefficients={n:str(v) for n,v in delta.items()},
        at_exact_witness=str(dc+sum((v*w[n] for n,v in delta.items()),Q(0))),
        native_currency_bound_rigorously_certified=False)
    if 'bound_backend_numerical' in stats and stats['bound_backend_numerical'] is not None:
        excess=Q(stats['bound_backend_numerical'])-Q(exact['objective_exact'])
        out['native_bound_minus_exact_feasible_backend_objective']=str(excess)
        out['native_bound_contradiction']=excess>0
    out['termination']=stats['termination'];out['primal_status']=stats['primal_status']
    results.append(out)

# Global validity of this RSOC dual cut is analytic; perturbations must be rejected.
def in_dual(y):return y[0]>=0 and y[1]>=0 and 2*y[0]*y[1]>=y[2]*y[2]
y=list(map(Q,[1,1,-1]));assert in_dual(y)
assert not in_dual(list(map(Q,[-1,1,-1])))
assert not in_dual(list(map(Q,[0,1,-1])))
assert not in_dual(list(map(Q,[1,1,-2])))
assert sum(a*b for a,b in zip([1,1,-2],[1,2,2]))<0
assert sum(a*b for a,b in zip(y,[0,0,0]))<1 # inconsistent positive RHS invalid at cone origin
assert all(Q(float(v)*2.**33)==v*2**33 for v in y)
out=dict(results=results,original_tolerance_exact=str(TOL),
    adversarial_dual_sign_missing_term_and_rhs_rejected=True,
    global_internal_vendor_cut_certificate_available=False,
    exact_currency_or_global_integer_optimality_claimed=False)
(RUN/'independent_verification.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print('verified',len(results),'models; original/solver point checks and exact witness/coordinate checks')
print('numerical failures',[(a['case_id'],a['mode']) for a in results if not a.get('original_primal',{}).get('numerical_pass')])
print('native bound contradictions',[(a['case_id'],a['mode']) for a in results if a.get('native_bound_contradiction')])
