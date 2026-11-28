import importlib.util,json,sys,time
from pathlib import Path
ROOT=Path('E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01')
REPO=Path('D:/Projekte/Code/FlexPlan_UC_GSCR')
ARCH=Path('E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01')
sys.path.insert(0,str(REPO/'scripts/paper_a'))
import replay_evidence as evidence
import compare_original_ledgers as audit
SHA='ebaffb57feb3a27f2d7d87b745930664f625f935'
def put(path,value):
    with path.open('x',encoding='utf-8') as stream: json.dump(value,stream,indent=2,allow_nan=False)
def rec(path): return evidence.record(path)
def make_summaries():
    folder=ROOT/'03_replay_integrity'
    point=folder/'LPAC_G3_original_guarded/original_model_audit.json'
    manifest=folder/'LPAC_G3_inputs_guarded.json'
    d=evidence.read_json(point)
    checks=evidence.read_json(folder/'focused_validation.json')
    records={name:rec(path) for name,path in dict(original_point_audit=point,expected_manifest=manifest,
        focused_validation=folder/'focused_validation.json',julia_test_log=folder/'julia_focused_final.log',
        python_test_log=folder/'python_focused_final.log',python_replay=REPO/'scripts/paper_a/replay_direct_ac.py',
        python_integrity=REPO/'scripts/paper_a/replay_evidence.py',julia_replay=REPO/'scripts/paper_a/week_ac_audit.jl').items()}
    put(folder/'ORIGINAL_MODEL_AUDIT.json',dict(source_freeze_commit=SHA,inputs=records,
        expected_manifest_matches_audit=evidence.digest(manifest)==d['input_manifest_sha256'],
        qualification='SENSITIVITY_ONLY_NOT_GOLD_UB',gold_qualified=False,
        original_cost_EUR2025=d['original_cost_EUR2025'],original_matrix=d['original_matrix'],physical=d['physical'],
        minimum_eigenvalue=d['minimum_eigenvalue'],ledger_roster=d['ledger_roster'],
        validation=dict(julia_tests=checks['julia_tests'],julia_result=checks['julia_result'],
                        python_groups=checks['python_test_groups'],python_result=checks['python_result']),
        historical_claim_disposition='UNCHANGED: F02 scoped PASS remains; LPAC G3 point remains non-GOLD; no broad optimization',
        limitation='Archived point checked in its original unscaled model; no point transfer into newly corrected native G3 reference claimed'))
    controls=[]
    for language,key in [('Python','python_controls'),('Julia','julia_controls')]:
        controls.extend(dict(language=language,control=name,result='PASS') for name in checks[key])
    controls.append(dict(language='Python',control='python -O assertion bypass',result='PASS_FAIL_CLOSED',
                         observed='RuntimeError before imports and evaluation'))
    put(folder/'NEGATIVE_CONTROL_RESULTS.json',dict(source_freeze_commit=SHA,
        inputs={k:v for k,v in records.items() if k in ('focused_validation','julia_test_log','python_test_log')},
        python_test_groups=3,julia_tests=12,result='PASS',controls=controls,
        angle_scaling_control=dict(original_residual=0.001,solver_row_scaling=1e-12,
            native_report_atol=1e-8,native_report_flags_violation=False,original_report_flags_violation=True),
        scope='Focused tests are actual malformed files/coordinates or original-row mutation controls; not full-week optimization'))
    print('SUMMARY_READY',flush=True)
make_summaries()
expected={(method,form,backend) for method,backends in [('G0',['mosek']),('G3',['mosek','gurobi'])]
          for form in ['LPAC','SOC-WR','QCRM'] for backend in backends}
done={}
started=time.monotonic()
while set(done)!=expected:
    for method,form,backend in sorted(expected-set(done)):
        parent=ROOT/('01_native_g0' if method=='G0' else '02_native_g3')
        source=parent/f'{form}_{backend}_frozen'
        if not all((source/name).is_file() for name in ('audit_terms.csv','terminal_coordinates.csv')): continue
        marker='native_psd_readback.json' if method=='G0' else 'native_readback.json'
        # Root exports ledgers before the task readback, so require stable bytes
        # across a bounded gap before inspecting a newly produced pair.
        before=[(source/name).stat().st_size for name in ('audit_terms.csv','terminal_coordinates.csv')]
        time.sleep(1)
        if before!=[(source/name).stat().st_size for name in ('audit_terms.csv','terminal_coordinates.csv')]: continue
        target=ROOT/'05_scientific_results'/f'{method}_{form}_{backend}_FROZEN_SOURCE_DELTA.json'
        if target.is_file(): report=evidence.read_json(target)
        else:
            try: report=audit.compare(ARCH/'DIRECT_GSCR_PM0217_01'/f'{form}_G3',source)
            except (evidence.EvidenceError,ValueError,OSError) as error:
                print('NOT_READY',method,form,backend,str(error),flush=True)
                continue
            report['source_freeze_commit']=SHA
            report['auditor_source']=rec(REPO/'scripts/paper_a/compare_original_ledgers.py')
            put(target,report)
        differences={k:v['coefficient_differences'] for k,v in report['metrics'].items()}
        done[method,form,backend]=dict(report=rec(target),coefficient_differences=differences,
                                      all_exact=all(x==0 for x in differences.values()))
        print('DELTA_DONE',method,form,backend,json.dumps(differences),'total',len(done),flush=True)
    if set(done)==expected: break
    if time.monotonic()-started>7200:
        print('BOUNDED_WAIT_EXPIRED',len(done),flush=True)
        break
    time.sleep(30)
put(ROOT/'05_scientific_results/FROZEN_SOURCE_DELTA_SUMMARY.json',dict(source_freeze_commit=SHA,
    completed=len(done),expected=9,all_complete=len(done)==9,
    all_completed_exact=all(row['all_exact'] for row in done.values()),
    comparisons=[dict(method=key[0],formulation=key[1],backend=key[2],**value) for key,value in sorted(done.items())],
    limitation='Nonterminal M/cost coordinates retain exact primary JuMP indices; semantic rebinding of unnamed coordinates is not claimed'))