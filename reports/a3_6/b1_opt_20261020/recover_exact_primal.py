"""Attempt rational primal recovery; accept only exact constraint checks.

Active-row selection uses the floating seed. The acceptance test uses exact
binary rational model coefficients and no feasibility tolerance.
"""
from pathlib import Path
from fractions import Fraction as Q
import json,sys,hashlib,itertools,time
R=Path(sys.argv[1]);I=R/'model_inclusion';O=R/'exact_primals';O.mkdir(exist_ok=True)
def load(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def affine(f):
    if f['type']=='Variable':return {f['name']:Q(1)},Q(0)
    assert f['type']=='ScalarAffineFunction',f['type']
    a={}
    for t in f['terms']:a[t['variable']]=a.get(t['variable'],Q(0))+Q(t['coefficient'])
    return {i:v for i,v in a.items() if v},Q(f['constant'])
def vector(f):
    if f['type']=='VectorOfVariables':return [({n:Q(1)},Q(0)) for n in f['variables']]
    assert f['type']=='VectorAffineFunction',f['type']
    a=[{} for _ in f['constants']]
    for t in f['terms']:
        d=a[t['output_index']-1];tt=t['scalar_term'];n=tt['variable'];d[n]=d.get(n,Q(0))+Q(tt['coefficient'])
    return list(zip(a,map(Q,f['constants'])))
def ev(a,c,x):return c+sum((v*x[i] for i,v in a.items()),Q(0))
def psd(v,n):
    M=[[Q(0) for _ in range(n)] for _ in range(n)];k=0
    for j in range(n):
        for i in range(j+1):M[i][j]=M[j][i]=v[k];k+=1
    # Exact symmetric elimination. Positive pivots imply positive definiteness;
    # a zero pivot is allowed only with a zero remaining offdiagonal row.
    pivots=[]
    for i in range(n):
        p=M[i][i];pivots.append(p)
        if p<0:return False,pivots
        if p==0:
            if any(M[i][j] for j in range(i+1,n)):return False,pivots
            continue
        for j in range(i+1,n):
            for k in range(j,n):M[j][k]-=M[i][j]*M[i][k]/p;M[k][j]=M[j][k]
    return True,pivots
def verify(m,x):
    failures=[];cones=[];counts={}
    for ci,c in enumerate(m['constraints']):
        f=c['function'];s=c['set'];typ=s['type'];counts[typ]=counts.get(typ,0)+1
        if f['type'] in ['Variable','ScalarAffineFunction']:
            v=ev(*affine(f),x)
            if typ=='EqualTo':ok=v==Q(s['value'])
            elif typ=='GreaterThan':ok=v>=Q(s['lower'])
            elif typ=='LessThan':ok=v<=Q(s['upper'])
            elif typ=='Interval':ok=Q(s['lower'])<=v<=Q(s['upper'])
            elif typ=='Integer':ok=v.denominator==1
            elif typ=='ZeroOne':ok=v in [0,1]
            else:raise ValueError(typ)
        else:
            v=[ev(a,b,x) for a,b in vector(f)]
            if typ=='RotatedSecondOrderCone':
                gap=2*v[0]*v[1]-sum((z*z for z in v[2:]),Q(0));ok=v[0]>=0 and v[1]>=0 and gap>=0
                cones.append({'type':typ,'product_margin':str(gap),'product_margin_float':float(gap)})
            elif typ=='PositiveSemidefiniteConeTriangle':
                ok,p=psd(v,s['side_dimension']);cones.append({'type':typ,'ldl_pivots':[str(t) for t in p]})
            elif typ=='Nonnegatives':ok=all(z>=0 for z in v)
            elif typ=='Zeros':ok=not any(v)
            else:raise ValueError(typ)
        if not ok:failures.append({'constraint':ci,'set':typ,'value':str(v)})
    return {'passed':not failures,'counts':counts,'failures':failures,'cones':cones}
def recover(m,seed,tol):
    mandatory=[];active=[];integers=set()
    for c in m['constraints']:
        f=c['function'];s=c['set'];typ=s['type']
        if f['type'] not in ['Variable','ScalarAffineFunction']:continue
        a,k=affine(f)
        if typ in ['Integer','ZeroOne']:
            assert len(a)==1;name=next(iter(a));mandatory.append(({name:Q(1)},Q(round(seed[name]))));integers.add(name)
        elif typ=='EqualTo':mandatory.append((a,Q(s['value'])-k))
        else:
            val=float(ev(a,k,seed))
            for rhs in [s.get('lower'),s.get('upper')]:
                if rhs is not None and abs(val-rhs)<tol:active.append((a,Q(rhs)-k))
    piv={};inconsistent=0
    # Singletons first remove fixed integers and exact zero variables.
    for a0,b0 in sorted(mandatory+active,key=lambda r:len(r[0])):
        a=a0.copy();b=b0
        while a:
            common=next((i for i in a if i in piv),None)
            if common is None:break
            coeff=a.pop(common);pa,pb=piv[common];b-=coeff*pb
            for j,v in pa.items():
                z=a.get(j,Q(0))-coeff*v
                if z:a[j]=z
                elif j in a:del a[j]
        if not a:
            if b:inconsistent+=1
            continue
        # Prefer a well-scaled pivot but acceptance remains exact.
        i=max(a,key=lambda i:abs(float(a[i])));v=a.pop(i)
        piv[i]=({j:z/v for j,z in a.items()},b/v)
    if inconsistent:return None,{'inconsistent_active_rows':inconsistent,'pivots':len(piv)}
    x={i:Q(v) for i,v in seed.items()}
    for i,(a,b) in reversed(list(piv.items())):x[i]=b-sum((v*x[j] for j,v in a.items()),Q(0))
    return x,{'pivots':len(piv),'integer_variables':len(integers),'free_variables':len(x)-len(piv)}
summary=[]
for p in sorted(I.glob('*_G3.mof.json')):
    case=p.name.removesuffix('_G3.mof.json');m=load(p)
    wp=R/'input/integer_best'/f'full_witness_{case}_G3.json';w=load(wp)
    assert len(m['variables'])==len(w['all_variables'])
    seed={m['variables'][v['index']-1]['name']:Q(v['value']) for v in w['all_variables']};attempts=[];success=None
    for tol in [1e-7,1e-9,1e-11,0.]:
        x,meta=recover(m,seed,tol)
        if x is not None:
            check=verify(m,x);meta.update(failed_constraints=len(check['failures']))
            if check['passed']:success=(x,check);attempts.append({'selection_tolerance':tol,**meta});break
            meta['first_failures']=check['failures'][:5]
        attempts.append({'selection_tolerance':tol,**meta})
    row={'case_id':case,'model_sha256':sha(p),'seed_sha256':sha(wp),'attempts':attempts,'rigorous_UB_for_serialized_G3':success is not None}
    if success:
        x,check=success;row['G3_verification']=check
        g0=load(I/f'{case}_G0.mof.json');row['G0_verification']=verify(g0,x)
        c=ev(*affine(m['objective']['function']),x);row['objective_exact']=str(c);row['objective']=float(c)
        point={i:str(v) for i,v in x.items()};(O/f'{case}_point.json').write_text(json.dumps(point))
        row['point_sha256']=sha(O/f'{case}_point.json')
    (O/f'{case}_result.json').write_text(json.dumps(row,indent=2));summary.append(row)
    (O/'summary.json').write_text(json.dumps(summary,indent=2));print(case,'exact primal',success is not None,attempts,flush=True)
