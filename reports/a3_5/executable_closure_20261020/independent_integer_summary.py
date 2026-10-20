"""Recompute nine-case full-witness costs and matrices; do not promote solver bounds."""
from pathlib import Path
import json,sys,runpy,numpy as np
R=Path(sys.argv[1]);B=Path(sys.argv[2]);source=Path(__file__).with_name('independent_reference_oracle.py')
helpers=runpy.run_path(str(source));rebuild=helpers['rebuild'];economics=helpers['economics'];F=R/('integer_best' if (R/'integer_best/independent_integer_fixed_checks.json').exists() else 'integer_final')
records=json.loads((F/'independent_integer_fixed_checks.json').read_text());out=[]
for row in records:
    raw=json.loads((B/'reports/ap3_runs/20261020_macro/accepted_suite'/row['case_id']/'case.json').read_text());points=[]
    for p in row['points']:
        if 'point_file' not in p:continue
        w=json.loads((F/p['point_file']).read_text());sol=w['solution'];eco=economics(raw,sol);states=[rebuild(raw,s,t) for t,s in sol['snapshots'].items()]
        costdiff=abs(eco['total']-p['stats']['objective']);minpsd=min(min(s['eigM']) for s in states);products=[s['G3']['product_min'] for s in states if s['G3']]
        points.append(dict(formulation=p['formulation'],cost=eco['total'],cost_components=eco['components'],cost_residual=costdiff,operating_violations=eco['violations'],all_constraints=p['full_model_report'],min_eigen_M=minpsd,min_G3_product=min(products,default=None),matrix_difference=max(s['model_diff'] for s in states),fixed_integer_decisions=p['fixed_integer_decisions'],hours=eco['hours']))
    upper=min((p['cost'] for p in points),default=None);basebound=row['BASE_LP_lower_bound'].get('bound');claimed=[r.get('bound') for r in row['historical_integer_bound_claims'] if r.get('bound') is not None];cmax=max(claimed,default=None)
    mainclaim=next(r for r in json.loads((B/'reports/ap3_runs/20261020_macro/integer_bound_audit.json').read_text())['records'] if r['case_id']==row['case_id'])
    out.append(dict(case_id=row['case_id'],case_sha256=row['case_sha256'],points=points,feasible_cost_upper=upper,BASE_LP_numerical_lower_bound=basebound,LP_signed_gap=None if upper is None or basebound is None else upper-basebound,historical_native_max_claimed_bound=cmax,historical_bound_signed_distance=None if upper is None or cmax is None else upper-cmax,original_reference_lower_claim=mainclaim['shared_lower_bound'],original_reference_upper_claim=mainclaim['shared_G0_G3_upper_bound'],signed_reference_gap=None if upper is None else upper-mainclaim['shared_lower_bound'],globality='numerically_supported_bounds_only_not_rigorous_certificate',full_enumeration=False,G0_G3_fixed_cost_difference=None if len(points)!=2 else abs(points[0]['cost']-points[1]['cost'])))
(R/'integer_global_bounds_and_objective_audit.json').write_text(json.dumps(out,indent=2))
print('nine-case audit',len(out),'max all-constraint residual',max(p['all_constraints']['max_violation'] for r in out for p in r['points']))
