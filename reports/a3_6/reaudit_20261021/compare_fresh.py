"""Bind the freshly built models/objective snapshots back to archived proofs."""
from pathlib import Path
import json,sys,hashlib,subprocess
W=Path(sys.argv[1]); R=Path(sys.argv[2]); P=R/'prior'
def load(p): return json.loads(p.read_text(encoding='utf-8'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
results=[]
for folder,old in [('fresh_models','model_inclusion'),('fresh_objective_snapshots','objective_snapshots')]:
    fresh=sorted((R/folder).glob('*.mof.json')); expected=sorted((P/old).glob('*.mof.json'))
    assert [p.name for p in fresh]==[p.name for p in expected]
    for p in fresh:
        q=P/old/p.name; assert load(p)==load(q),p.name
        results.append({'path':folder+'/'+p.name,'fresh_sha256':sha(p),'prior_sha256':sha(q),'semantic_identity':True,'byte_identity':sha(p)==sha(q)})
assert len(results)==45
runtime=[]
for e in load(P/'source_runtime_sha256_manifest.json'):
    p=Path(e['path']); assert p.stat().st_size==e['bytes'] and sha(p)==e['sha256'],p
    runtime.append(e)
publication=load(W/'reports/a3_6/b1_opt_20261020/publication_verification.json')
blobs=[]
for e in publication['artifact_files_verified_against_git_blobs']:
    b=subprocess.check_output(['git','-C',str(W),'show',publication['verified_evidence_commit']+':'+e['path']])
    assert len(b)==e['bytes'] and hashlib.sha256(b).hexdigest()==e['sha256']
    blob=subprocess.check_output(['git','-C',str(W),'rev-parse',publication['verified_evidence_commit']+':'+e['path']]).decode().strip(); assert blob==e['git_blob']
    blobs.append(e)
treefiles=subprocess.check_output(['git','-C',str(W),'ls-tree','-r','--name-only','1147873bf553667aec5cd7eb0e9c6f7e471b370c','--','reports/a3_6/b1_opt_20261020']).decode().splitlines()
complete=[]
for rel in treefiles:
    b=subprocess.check_output(['git','-C',str(W),'show','1147873bf553667aec5cd7eb0e9c6f7e471b370c:'+rel])
    assert (W/rel).read_bytes()==b
    complete.append({'path':rel,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
fresh_native=R/'fresh_objective_snapshots/reference_24snap_default.mof.json'
original_native=P/'original_01/b1_exact_native.mof.json'
assert load(fresh_native)==load(original_native)
out={'fresh_exports':results,'original_24snap_native_rebuilt_identically':True,'original_24snap_native_sha256':sha(original_native),'fresh_24snap_native_sha256':sha(fresh_native),'source_runtime_files_verified':len(runtime),'publication_git_blobs_verified':len(blobs),'publication_receipt_target_sha':publication['verified_evidence_commit'],'complete_pinned_report_tree':complete,'runtime_files':runtime}
(R/'fresh_export_comparison.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print('PASS: 27 fresh normalized models, 18 fresh actual objective snapshots,',len(runtime),'source/runtime files,',len(blobs),'Git blobs')
