"""Package only new replay outputs; preserve originals and exclude local runtimes."""
from pathlib import Path
import hashlib,json,shutil,sys,zipfile,subprocess
R=Path(sys.argv[1]);O=Path(sys.argv[2]);B=Path(sys.argv[3])
def h(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def dump(p,x):Path(p).write_text(json.dumps(x,indent=2),encoding='utf-8')
if sys.argv[4]=='prepare_cli_payload':
    P=R/'cli_payload';P.mkdir(exist_ok=False)
    for d in ['suite','matrices','metrics','certificates','comparisons','planning','benchmarks']:shutil.copytree(R/d,P/d)
    print('CLI payload ready');sys.exit()
if sys.argv[4]=='verify':
    expected={'A.connection_violation':'count_or_index','B.G3_edges_complete':'boolean','B.G3_valid':'boolean'}
    a=load(R/'metrics/metrics.json')['metrics'];b=load(R/'metrics_unit_fix/metrics.json')['metrics'];assert len(a)==len(b)
    changes=0
    for x,y in zip(a,b):
        xx=dict(x);yy=dict(y);xx.pop('AP3_SHA');yy.pop('AP3_SHA')
        if x['metric_id'] in expected:
            assert y['unit']==expected[x['metric_id']];xx['unit']=expected[x['metric_id']];changes+=1
        assert xx==yy,(x['case_id'],x['metric_id'])
    dump(R/'fixed_metric_export_comparison.json',dict(original_records=len(a),fixed_records=len(b),changed_unit_records=changes,changed_ids=expected,all_other_values_statuses_bases_and_units_identical=True,provenance_AP3_SHA_changed=True))
    idx=load(R/'export/evidence_index.json')['files'];checks=[]
    for x in idx:
        p=R/'cli_payload'/x['path'].replace('\\','/');checks.append(dict(path=x['path'],match=p.stat().st_size==x['bytes'] and h(p)==x['sha256']))
    assert all(x['match'] for x in checks)
    dump(R/'fresh_export_hash_verification.json',dict(count=len(checks),matched=sum(x['match'] for x in checks),entries=checks))
    print('fixed unit export and fresh evidence hashes verified');sys.exit()
if sys.argv[4]!='package':raise ValueError(sys.argv[4])
O.mkdir(exist_ok=True)
# Direct reviewable artifacts plus a lossless archive with complete new run outputs.
direct=['oracle_results.json','independent_exact_integer_enumeration.json','independent_matrices_B_p_S_M_Zp_G3.json','independent_objective_audit.json','integer_global_bounds_and_objective_audit.json','independent_metric_results.json','raw_reconstruction_summary.json','authority_git_inventory.json','input_sha256_manifest.json','science_source_manifest.json','historical_index_verification.json','archive_verification.json','execution.json','negative_cli_results.json','fixed_metric_export_comparison.json','fresh_export_hash_verification.json','b1_exact_native_result.json','b1_bridged_full_witness_check.json']
direct+=['additional_execution.json','independent_linear_certificate_results.json']
for name in direct:shutil.copyfile(R/name,O/name)
shutil.copyfile(R/'moi_final03/independent_moi_results.json',O/'independent_moi_results.json');shutil.copyfile(R/'moi_final03/runtime_capabilities.json',O/'runtime_capabilities.json')
scripts=['execute_replay.ps1','prepare_evidence.py','verify_inventory.py','snapshot_science.py','finalize_replay.ps1','verify_and_package.py']
for name in scripts:shutil.copyfile(R/name,O/name)
files=set()
for d in ['suite','matrices','metrics','certificates','comparisons','planning','benchmarks','metrics_unit_fix','integer_final','integer_best','moi_final03','science_source_snapshots','export','validation/reports']:
    files.update(p for p in (R/d).rglob('*') if p.is_file())
for p in R.iterdir():
    if p.is_file() and p.name!='packaging.log' and p.suffix in ['.log','.json','.cbf','.ps1','.py']:files.add(p)
dest=O/'artifacts';dest.mkdir(exist_ok=True);archive=dest/'executable_replay_evidence.zip'
manifest=[]
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as z:
    for p in sorted(files):
        rel=p.relative_to(R).as_posix();digest=h(p);z.write(p,rel);manifest.append(dict(path=rel,bytes=p.stat().st_size,sha256=digest))
assert archive.stat().st_size<95_000_000,'archive above conservative GitHub limit; split without dropping evidence'
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for e in manifest:
        with z.open(e['path']) as src:assert hashlib.file_digest(src,'sha256').hexdigest()==e['sha256']
dump(O/'reproduction_manifest.json',dict(original_ap3_sha='485b637cc1998a327206c5929434bd26c6f0be16',metadata_fix_code_sha='e1e075626b38b478faf57efe62e557fc94753f00',archive=dict(path='artifacts/'+archive.name,sha256=h(archive),bytes=archive.stat().st_size,entries=len(manifest),all_entries_sha256_verified=True),entries=manifest,baseline_root=str(B),run_root=str(R),command_manifest='execution.json',note='Original source inputs referenced by pinned git commits and input_sha256_manifest. Runtime binaries and previous historical output trees are not duplicated.'))
print('published archive bytes',archive.stat().st_size,'entries',len(manifest))
