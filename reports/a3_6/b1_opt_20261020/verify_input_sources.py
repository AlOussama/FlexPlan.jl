from pathlib import Path
import json,hashlib,subprocess,zipfile
R=Path(__file__).parent;B=Path('D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE');H=B/'reports/ap3_runs/20261020_macro'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((R/'input/input_sha256_manifest.json').read_text());inputs=[]
for e in manifest:
    p=Path(e['path']);actual=sha(p) if p.is_file() else None
    inputs.append({**e,'actual_sha256':actual,'match':actual==e['sha256']})
assert all(x['match'] for x in inputs)
science=[]
for e in json.loads((R/'input/science_source_manifest.json').read_text()):
    data=subprocess.check_output(['git','-C','D:/Projekte/research-map','show',e['commit']+':'+e['path']])
    actual=hashlib.sha256(data).hexdigest();blob=subprocess.check_output(['git','hash-object','--stdin'],input=data).decode().strip()
    science.append({**e,'actual_sha256':actual,'actual_blob':blob,'match':actual==e['sha256'] and blob==e['blob']})
assert all(x['match'] for x in science)
archive_entries={};archives=[]
for p in H.rglob('*.zip'):
    with zipfile.ZipFile(p) as z:
        assert z.testzip() is None
        for n in z.namelist():
            if n.endswith('/'):continue
            data=z.read(n);archive_entries[(p.parent/Path(n)).relative_to(H).as_posix()]=(hashlib.sha256(data).hexdigest(),len(data))
    archives.append({'path':str(p),'sha256':sha(p)})
index=json.loads((H/'export_final/evidence_index.json').read_text())['files'];verified=[]
for e in index:
    rel=e['path'].replace('\\','/');p=H/rel
    actual=(sha(p),p.stat().st_size) if p.is_file() else archive_entries.get(rel)
    verified.append({**e,'actual':actual,'match':actual is not None and actual==(e['sha256'],e['bytes'])})
assert all(x['match'] for x in verified)
(R/'input_source_and_historical_verification.json').write_text(json.dumps({'original_input_files':inputs,'science_sources':science,'historical_archives':archives,'historical_index':verified,'input_files_matched':len(inputs),'science_sources_matched':len(science),'historical_entries_matched':len(verified),'historical_archives_matched':len(archives)},indent=2))
print('Input files',len(inputs),'science snapshots',len(science),'original indexed files',len(verified),'historical archives',len(archives),'verified')
