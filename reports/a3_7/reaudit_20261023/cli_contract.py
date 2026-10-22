"""Fresh public CLI and metric-contract replay, including expected failures."""
from execute import *
C=R/'cli';C.mkdir()
src=W/'reports/ap3_runs/20261020_macro/accepted_suite/reference_3snap'
config=dict(AP1_SHA='3b8fdb01d931225edc5f8fe1e2c200d0da288a09',cases=[dict(id='reference_3snap',
    case=str(src/'case.json'),registry=str(src/'parameter_registry.csv'),scenarios=str(src/'study_scenarios.toml'))],
    relaxations=[True,False],formulations=['BASE','G0','G1','G2_identity','G2_degree','G3','M1','M2_full','M2_neighbor'],
    condition_on_baseline_LP=True,sizes=[2,4,8,16])
cfg=C/'config.json';cfg.write_text(json.dumps(config,indent=2))
actions=[('run_formulation_suite',cfg,C/'suite'),('reconstruct_strength_matrices',C/'suite',C/'matrices'),
    ('evaluate_strength_metrics',C/'matrices',C/'metrics'),('verify_certificates',C/'matrices',C/'certificates'),
    ('compare_formulations',C/'suite',C/'comparisons'),('assess_planning_results',C/'suite',C/'planning'),
    ('benchmark_conic_scaling',cfg,C/'benchmark'),('export_paper_a_evidence',C,R/'cli_export')]
for action,inp,out in actions:
    assert jl('cli_'+action,W/'scripts/paper_a/ap3.jl',action,inp,out)==0,action
for name,action,inp,out in [('unknown','unknown',cfg,C/'unused'),
    ('missing','run_formulation_suite',C/'missing.json',C/'unused'),('existing','run_formulation_suite',cfg,C/'suite')]:
    assert jl('cli_negative_'+name,W/'scripts/paper_a/ap3.jl',action,inp,out)==1,name
T=R/'submitted_tools/continuation'
assert run('metric_raw',[PY,T/'raw_metric_replay.py',C,W])==0
assert run('metric_values',[PY,W/'reports/a3_5/executable_closure_20261020/independent_metric_audit.py',C,W])==0
v=json.loads((C/'independent_metric_results.json').read_text())
assert not v['failures'] and v['roundtrips'][0]['metric_ids']==124 and v['roundtrips'][0]['registry_coverage']
print('CLI and 124 metric contract verified',flush=True)
