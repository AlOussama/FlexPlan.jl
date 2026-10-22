"""Independent exact witness comparisons for raw solver diagnostics."""
from pathlib import Path
from fractions import Fraction as F
from collections import Counter,defaultdict
import ast,json,sys
import numpy as np
R=Path(sys.argv[1]);P=R/'validation/prior';TOL=F(1,10**7)
source=Path(__file__).with_name('independent_oracle.py')
tree=ast.parse(source.read_text());ns=dict(F=F,np=np,Counter=Counter,defaultdict=defaultdict,TOL=TOL)
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)],type_ignores=[]),str(source),'exec'),ns)
load=lambda p:json.loads(p.read_text());original=load(P/'original_01/b1_exact_native.mof.json')
w=load(P/'exact_primals/reference_24snap_native_point.json');wp=ns['point'](original,w)
assert wp['exact'];H=F(wp['objective']);out=[]
for solver in ['Gurobi','MOSEK']:
    d=R/'diagnostics'/('candidate_'+solver)
    for row in load(d/'results.json'):
        mode=row['mode']
        if mode=='small_integer_RSOC':
            assert row['termination']=='OPTIMAL' and row['primal']==[5.,1.]
            out.append(dict(solver=solver,mode=mode,solver_version=row['solver_version'],optimal_integer=5));continue
        m=load(d/(mode+'_solver_input.mof.json'));factor=F(row['objective_multiplier'])
        assert Counter(json.dumps(c,sort_keys=True) for c in m['constraints'])==Counter(json.dumps(c,sort_keys=True) for c in original['constraints'])
        a,b=ns['aff'](original['objective']['function']);c,e=ns['aff'](m['objective']['function'])
        assert {k:v*factor for k,v in a.items()}==c and b*factor==e
        bound=F(row['bound_original_coordinate_numerical_only']);excess=bound-H
        res=ns['point'](original,load(d/(mode+'_point.json')))
        out.append(dict(solver=solver,mode=mode,termination=row['termination'],
            exact_input_and_objective_identity=True,residuals=res,bound_excess=str(excess),
            bound_excess_display=float(excess),bound_contradiction=excess>0))
for row in load(R/'diagnostics/pajarito_gap_diagnosis/results.json'):
    res=ns['point'](original,load(R/'diagnostics/pajarito_gap_diagnosis'/(row['mode']+'_point.json')))
    ex=F(row['bound_numerical'])-H
    out.append(dict(solver='Pajarito',mode=row['mode'],termination=row['termination'],
                    residuals=res,bound_excess=str(ex),bound_excess_display=float(ex),bound_contradiction=ex>0))
double=load(R/'diagnostics/pajarito_double_gap/results.json')
assert double[0]['input_sha256']==double[1]['input_sha256']=='2f16ef548a55bf63e83f8400b9627875cf58f55e64c317357255a0d37f3549db'
assert double[0]['termination']=='ITERATION_LIMIT' and double[1]['termination']=='OPTIMAL'
a=double[0]['oa_options'];b=double[1]['oa_options'];assert set(b)-set(a)=={'mip_abs_gap'} and all(a[k]==b[k] for k in a)
out=dict(historical_exact_original_objective=str(H),historical_exact_primal=wp,raw_solves=out,double_gap_control=double)
(R/'diagnostic_comparisons.json').write_text(json.dumps(out,indent=2))
print(json.dumps([dict(solver=r['solver'],mode=r['mode'],excess=r.get('bound_excess_display')) for r in out['raw_solves']],indent=2))
