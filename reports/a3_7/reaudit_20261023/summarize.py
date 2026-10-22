from execute import *
from fractions import Fraction as F
from collections import Counter
a=json.loads((R/'reviewer_oracle.json').read_text())
b=json.loads((R/'matrix/independent_verification.json').read_text())['results']
assert len(a['results'])==len(b)==46
for x,y in zip(a['results'],b):
    assert x['mode']==y['mode'] and x['case_id']==y['case_id'] and x['formulation']==y['formulation']
    assert x['original']['residuals']=={k:v['exact'] for k,v in y['original_primal']['residuals'].items()}
    assert x['delta']==y['actual_objective_coordinate_delta']['coefficients']
    assert x['delta_constant']==y['actual_objective_coordinate_delta']['constant']
maxima={}
for x in a['results']:
    for k,v in x['original']['residuals'].items():maxima[k]=max(maxima.get(k,F(0)),F(v))
rows=json.loads((R/'matrix/results.json').read_text())
timings=[]
for x in rows:
    s=x['stats'];seed=s.get('primal_start_strategy',{})
    timings.append(dict(case_id=x['case_id'],mode=x['mode'],formulation=x['formulation'],
        final_s=s['solve_wall_s'],heuristic_s=seed.get('heuristic_wall_s',0),preparation_s=s.get('native_preparation_wall_s',0),
        measured_phase_sum_s=s['solve_wall_s']+seed.get('heuristic_wall_s',0)+s.get('native_preparation_wall_s',0),
        objective=s['objective'],bound=s['bound'],backend_objective=s.get('objective_backend'),backend_bound=s.get('bound_backend_numerical')))
out=dict(model_count=46,native_backend_count=37,exact_quadratic_count=a['quadratics'],
    original_residual_maxima={k:dict(exact=str(v),display=float(v)) for k,v in maxima.items()},
    independent_and_submitted_residuals_and_delta_agree=True,
    delta_nonzero_models=sum(bool(x['delta']) or F(x['delta_constant'])!=0 for x in a['results']),
    timings=timings,matrix_command=json.loads((R/'matrix.command.json').read_text()),
    max_final_s=max(x['final_s'] for x in timings),max_heuristic_s=max(x['heuristic_s'] for x in timings),
    max_preparation_s=max(x['preparation_s'] for x in timings))
(R/'review_summary.json').write_text(json.dumps(out,indent=2))
print(json.dumps({k:v for k,v in out.items() if k not in ('timings','matrix_command')},indent=2))
print('default/double',json.dumps([t for t in timings if t['case_id']=='reference_24snap' and t['mode'] in ('double_costscale','original_serialized_default')],indent=2))
