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
    witness=load(PRIOR/'exact_primals'/f"{row['case_id']}_{'native_point' if literal else 'point'}.json")
    w={n:Q(v) for n,v in witness.items()}
    for z,(x,offset) in mapping.items():w[z]=w[x]+offset
    exact=check_point(solver,w,exact_psd=True);assert exact['exact_pass']
    out['historical_exact_witness_still_feasible']=True
    stats=row['stats'];mult=Q(stats.get('objective_conditioning',{}).get('multiplier',1))
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
