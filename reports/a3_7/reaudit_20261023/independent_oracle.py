"""New reviewer oracle: exact arithmetic, no submitted verifier imports or PASS inputs.

Recomputes every scalar/RSOC residual and objective, and substitutes native
quadratic graph coordinates symbolically before comparing cone polynomials.
PSD eigenvalues remain numerical; exact PSD witnesses use the A3.6 reviewer.
"""
from pathlib import Path
from fractions import Fraction as F
from collections import Counter, defaultdict
import json, math, sys
import numpy as np
R=Path(sys.argv[1]);P=R/'validation/prior';TOL=F(1,10**7)
load=lambda p:json.loads(p.read_text())
def aff(f):
    if f['type']=='Variable': return {f['name']:F(1)},F(0)
    assert f['type']=='ScalarAffineFunction'
    a=defaultdict(F)
    for t in f['terms']: a[t['variable']]+=F(t['coefficient'])
    return {k:v for k,v in a.items() if v},F(f['constant'])
def val(f,x):
    if f['type']=='VectorOfVariables': return [x[n] for n in f['variables']]
    if f['type']=='VectorAffineFunction':
        y=list(map(F,f['constants']))
        for t in f['terms']: y[t['output_index']-1]+=F(t['scalar_term']['coefficient'])*x[t['scalar_term']['variable']]
        return y
    if f['type']=='ScalarQuadraticFunction':
        return F(f['constant'])+sum((F(t['coefficient'])*x[t['variable']] for t in f['affine_terms']),F(0))+sum((
            F(t['coefficient'])*x[t['variable_1']]*x[t['variable_2']]/(2 if t['variable_1']==t['variable_2'] else 1)
            for t in f['quadratic_terms']),F(0))
    a,b=aff(f);return b+sum((v*x[n] for n,v in a.items()),F(0))
def point(m,raw):
    x={n:F(v) for n,v in raw.items()}; maxima=defaultdict(F); counts=Counter()
    assert {v['name'] for v in m['variables']}<=x.keys()
    for row in m['constraints']:
        s=row['set'];t=s['type'];v=val(row['function'],x);counts[t]+=1
        if t=='EqualTo': e=abs(v-F(s['value']))
        elif t=='LessThan': e=max(F(0),v-F(s['upper']))
        elif t=='GreaterThan': e=max(F(0),F(s['lower'])-v)
        elif t=='Interval':e=max(F(0),F(s['lower'])-v,v-F(s['upper']))
        elif t=='Integer':e=abs(v-round(v))
        elif t=='ZeroOne':e=min(abs(v),abs(v-1))
        elif t=='RotatedSecondOrderCone':e=max(F(0),-v[0],-v[1],sum(z*z for z in v[2:])-2*v[0]*v[1])
        elif t=='PositiveSemidefiniteConeTriangle':
            n=s['side_dimension'];a=np.zeros((n,n));k=0
            for j in range(n):
                for i in range(j+1):a[i,j]=a[j,i]=float(v[k]);k+=1
            e=F(max(0.,-float(np.linalg.eigvalsh(a)[0])))
        else:raise ValueError(t)
        maxima[t]=max(maxima[t],e)
    return dict(counts=dict(counts),residuals={k:str(v) for k,v in maxima.items()},
                passed=all(v<=TOL for v in maxima.values()),exact=all(v==0 for v in maxima.values()),
                objective=str(val(m['objective']['function'],x)))
def polynomial(a,b):
    out=defaultdict(F)
    for n,v in a.items():
        for k,w in b.items():out[tuple(sorted((n,k)))]+=v*w
    return out
def cone_poly(coords):
    q=defaultdict(F)
    for a in coords[2:]:
        for k,v in polynomial(a,a).items():q[k]+=v
    for k,v in polynomial(coords[0],coords[1]).items():q[k]-=2*v
    return tuple(sorted((k,str(v)) for k,v in q.items() if v))
def symbolic_backend(cached,native,rename):
    reverse={v:k for k,v in rename.items()};assert len(reverse)==len(rename)
    definitions={}
    for row in native['constraints']:
        if row['set']['type']!='EqualTo' or row['function']['type'] not in ('ScalarAffineFunction','Variable'):continue
        a,c=aff(row['function']);aux=set(a)-reverse.keys()
        if len(aux)==1:
            z=next(iter(aux));coef=a.pop(z)
            expr={reverse[k]:-v/coef for k,v in a.items()};expr['']=(F(row['set']['value'])-c)/coef
            definitions[z]={k:v for k,v in expr.items() if v}
    expected=[]
    for row in cached['constraints']:
        if row['set']['type']!='RotatedSecondOrderCone':continue
        f=row['function'];coords=[defaultdict(F) for _ in f['constants']]
        for i,c in enumerate(f['constants']):coords[i]['']=F(c)
        for t in f['terms']:coords[t['output_index']-1][t['scalar_term']['variable']]+=F(t['scalar_term']['coefficient'])
        expected.append(cone_poly(coords))
    observed=[]
    for row in native['constraints']:
        f=row['function']
        if f['type']!='ScalarQuadraticFunction':continue
        assert row['set']==dict(type='LessThan',upper=0.0)
        q=defaultdict(F)
        assert not f['affine_terms'] and F(f['constant'])==0
        for t in f['quadratic_terms']:
            u,v=t['variable_1'],t['variable_2'];c=F(t['coefficient'])/(2 if u==v else 1)
            for k,w in polynomial(definitions[u],definitions[v]).items():q[k]+=c*w
        observed.append(tuple(sorted((k,str(v)) for k,v in q.items() if v)))
    assert Counter(observed)==Counter(expected),'substituted quadratic polynomial multiset mismatch'
    ca,cc=aff(cached['objective']['function']);na,nc=aff(native['objective']['function'])
    assert cc==nc and ca=={reverse[k]:v for k,v in na.items()}
    assert cached['objective']['sense']==native['objective']['sense']=='min'
    return len(expected)
results=[]
for row in load(R/'matrix/results.json'):
    d=R/'matrix'/row['directory'];literal=row['mode']=='original_serialized_default'
    original=load(P/'original_01/b1_exact_native.mof.json') if literal else load(d/'original_model.mof.json')
    m=load(d/'solver_input.mof.json');x=load(d/'point.json');s=row['stats']
    r={k:row[k] for k in ('case_id','formulation','mode')}
    r['original']=point(original,x);r['emitted']=point(m,x)
    assert r['original']['passed'] and r['emitted']['passed']
    witness=load(P/'exact_primals'/f"{row['case_id']}_{'native_point' if literal else 'point'}.json")
    w={k:F(v) for k,v in witness.items()};old=set(w);links={}
    for c in m['constraints']:
        if c['set']['type']!='EqualTo':continue
        a,b=aff(c['function']);aux=set(a)-old
        if len(aux)==1:
            z=next(iter(aux));coef=a.pop(z)
            if set(a)<=old:
                w[z]=(F(c['set']['value'])-b-sum((v*w[k] for k,v in a.items()),F(0)))/coef
                links[z]=({k:-v/coef for k,v in a.items()},(F(c['set']['value'])-b)/coef)
    wp=point(m,w)
    if row['formulation']=='G3':assert wp['exact']
    a,b=aff(m['objective']['function'])
    for z,(terms,const) in links.items():
        v=a.pop(z,F(0));b+=v*const
        for k,c in terms.items():a[k]=a.get(k,F(0))+v*c
    oa,ob=aff(original['objective']['function'])
    div=F(s.get('objective_requested_divisor',s['objective_solver_scaling']));mul=F(s.get('objective_conditioning',{}).get('multiplier',1))
    delta={k:a.get(k,F(0))*div/mul-oa.get(k,F(0)) for k in a.keys()|oa.keys()}
    r['delta']={k:str(v) for k,v in delta.items() if v};r['delta_constant']=str(b*div/mul-ob)
    if row['formulation']=='G3':
        assert mul.denominator==1 and mul.numerator & (mul.numerator-1)==0
        assert all(a.get(k,F(0))==F(float(v)/float(div))*mul for k,v in oa.items())
        raw_a,raw_c=aff(m['objective']['function'])
        assert all(F(float(v/mul))==v/mul for v in [*raw_a.values(),raw_c])
        r['actual_power_two_multiplication_exact_including_constant']=True
    r['exact_witness_backend_objective']=wp['objective']
    if row['formulation']=='G3':
        r['bound_excess']=str(F(s['bound_backend_numerical'])-F(wp['objective']))
        assert F(r['bound_excess'])<=0
        native=load(d/'actual_backend.mof.json');mapping=load(d/'backend_variable_map.json')['cached_to_native']
        r['quadratics_substitution_matched']=symbolic_backend(m,native,mapping)
        r['backend_point']=point(native,load(d/'backend_point.json'));assert r['backend_point']['passed']
        seed=s['primal_start_strategy'];assert not seed['heuristic_bound_used']
        seedx=dict(zip([v['name'] for v in m['variables']],seed['values_in_original_variable_order']))
        r['seed_original']=point(original,seedx);assert r['seed_original']['passed']
    assert row['stats']['termination']=='OPTIMAL' and row['stats']['primal_status']=='FEASIBLE_POINT'
    results.append(r)
out=dict(results=results,tolerance=str(TOL),model_count=len(results),
    backend_count=sum('backend_point' in r for r in results),quadratics=sum(r.get('quadratics_substitution_matched',0) for r in results),
    rigorous_global_bound_certified=False)
(R/'reviewer_oracle.json').write_text(json.dumps(out,indent=2))
print('Independent reviewer:',out['model_count'],'points;',out['backend_count'],'backends;',out['quadratics'],'quadratics')
