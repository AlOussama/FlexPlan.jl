from pathlib import Path
import csv,hashlib,json,sys,zipfile
O=Path(sys.argv[1])
def load(n):return json.loads((O/n).read_text(encoding='utf-8-sig'))
for n,count,prefix in [('predicate_P001_P010_evidence_ledger.csv',10,'P-C2A-'),('theorem_T001_T028_equation_to_code_ledger.csv',28,'T-C2A-')]:
    with (O/n).open(encoding='utf-8',newline='') as f:rows=list(csv.DictReader(f))
    assert len(rows)==count and {x['id'] for x in rows}=={prefix+f'{i:03d}' for i in range(1,count+1)}
m=load('independent_metric_results.json');assert not m['failures'];assert len(m['metrics'])==248
assert all(r['metric_ids']==124 and r['registry_coverage'] and r['records']==r['csv_roundtrip'] for r in m['roundtrips'])
assert len(load('integer_global_bounds_and_objective_audit.json'))==9
assert len(load('execution.json'))==14 and all(x['exit_code']==0 for x in load('execution.json'))
assert len(load('additional_execution.json'))==30
assert load('historical_index_verification.json')['matched']==1060
assert load('fresh_export_hash_verification.json')['matched']==171
assert load('fixed_metric_export_comparison.json')['changed_unit_records']==1836
gates=(O/'release_gates.yaml').read_text();assert 'executable_closure_verdict: blocked_by_solver_or_data' in gates
for field in ['science_amendment_approved','independent_A3_5_accepted','A3_closed','AP4_ready','empirical_study_ready']:assert f'{field}: false' in gates
r=load('reproduction_manifest.json');archive=O/r['archive']['path']
with archive.open('rb') as f:assert hashlib.file_digest(f,'sha256').hexdigest()==r['archive']['sha256']
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None and len(z.infolist())==r['archive']['entries']
    for entry in r['entries']:
        with z.open(entry['path']) as f:assert hashlib.file_digest(f,'sha256').hexdigest()==entry['sha256']
print('closure package validated: 10 predicates,28 theorems,124+124 metrics,9 integer cases,14 process records,all archive SHA256,all release gates false')
