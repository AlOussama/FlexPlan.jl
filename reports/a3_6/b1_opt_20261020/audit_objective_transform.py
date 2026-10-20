from pathlib import Path
from fractions import Fraction as Q
import json,sys,math
R=Path(sys.argv[1]);out=[]
def load(p):return json.loads(p.read_text())
def aff(f):
    if f['type']=='Variable':return {f['name']:Q(1)},Q(0)
    a={}
    for t in f['terms']:a[t['variable']]=a.get(t['variable'],Q(0))+Q(t['coefficient'])
    return a,Q(f['constant'])
for p in sorted((R/'objective_snapshots').glob('*.mof.json')):
    case,mode=p.name.removesuffix('.mof.json').rsplit('_',1)
    if mode=='conditioned':case=case.removesuffix('_cost');mode='cost_conditioned'
    orig=load(R/'model_inclusion'/f'{case}_G3.mof.json');native=load(p)
    ca,c0=aff(orig['objective']['function']);origvars={v['name'] for v in orig['variables']}
    if mode=='default':
        scale=next(x['stats']['objective_solver_scaling'] for x in load(R/'solver_matrix/results.json') if x['case_id']==case and x['formulation']=='G3' and x['mode']=='original')
    else:scale=load(R/'lp_bounds'/f'{case}_dual_input.json')['stats']['objective']
    a,c=aff(native['objective']['function']);a={n:v*Q(scale) for n,v in a.items()};c*=Q(scale)
    substitutions={}
    for row in native['constraints']:
        if row['set']['type']!='EqualTo' or row['function']['type'] not in ['Variable','ScalarAffineFunction']:continue
        aa,cc=aff(row['function']);unknown=[n for n in aa if n not in origvars]
        if len(unknown)!=1:continue
        n=unknown[0];coef=aa.pop(n)
        substitutions[n]=({v:-k/coef for v,k in aa.items()},(Q(row['set']['value'])-cc)/coef)
    for n in list(a):
        if n in origvars:continue
        v=a.pop(n);sa,sc=substitutions[n];c+=v*sc
        for k,z in sa.items():a[k]=a.get(k,Q(0))+v*z
    delta={n:a.get(n,Q(0))-ca.get(n,Q(0)) for n in set(a)|set(ca)};delta={n:v for n,v in delta.items() if v};delta0=c-c0
    x={n:Q(v) for n,v in load(R/'exact_primals'/f'{case}_point.json').items()}
    dv=delta0+sum((v*x[n] for n,v in delta.items()),Q(0))
    inp=load(R/'lp_bounds_raw_currency'/f'{case}_dual_input.json');lb=load(R/'lp_bounds_raw_currency'/f'{case}_exact_LB.json')
    byidx={v['index']:v['name'] for v in inp['variables']};b={byidx[int(i)]:[None if z is None else Q(z) for z in pair] for i,pair in lb['finite_variable_bounds'].items()}
    fixed_delta=delta0;free={}
    for n,v in delta.items():
        if n in b and b[n][0] is not None and b[n][0]==b[n][1]:fixed_delta+=v*b[n][0]
        else:free[n]=v
    out.append({'case_id':case,'mode':mode,'scale':scale,'scale_exact':str(Q(scale)),'original_emitted_constant':str(c0),'solver_emitted_constant':str(Q(native['objective']['function'].get('constant',0))),'increment_equalities':len(substitutions),'exact_currency_delta_constant':str(delta0),'exact_currency_delta_coefficients':{n:str(v) for n,v in delta.items()},'delta_constant_after_proven_fixed_variables':str(fixed_delta),'free_delta_coefficients':{n:str(v) for n,v in free.items()},'delta_at_exact_primal':str(dv),'delta_at_exact_primal_float':float(dv),'actual_identity':'scale * F_solver(x,increment(x)) = C_emitted(x) + delta(x)','rigorous_native_bound_transfer_claimed':False,'reason':'No validated OA/tree bound; nonzero actual affine delta must also be bounded before transferring a certified solver interval.'})
(R/'objective_transform_audit.json').write_text(json.dumps(out,indent=2))
for r in out:print(r['case_id'],r['mode'],'scale',r['scale'],'currency delta at exact primal',r['delta_at_exact_primal_float'])
