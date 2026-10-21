"""Read-only verification of pinned inputs; extracts only into a new run directory."""
from pathlib import Path
import csv, hashlib, json, subprocess, sys, zipfile

W=Path(sys.argv[1]).resolve(); R=Path(sys.argv[2]).resolve()
A=W/'reports/a3_6/b1_opt_20261020'
R.mkdir(parents=True,exist_ok=False)
def sha(b): return hashlib.sha256(b).hexdigest()
def git(*args): return subprocess.check_output(['git','-C',str(W),*args])
def load(p): return json.loads(p.read_text(encoding='utf-8'))
records={}
refs=['485b637cc1998a327206c5929434bd26c6f0be16','4d9f346c5fca80e00fd01d96c39a2bac91776ac0','e1e075626b38b478faf57efe62e557fc94753f00','e49b64216f82eefda77d6997ed68ed2d12c8ae78','910d44122a37d9ed2cca06940740b46706c73d40','1147873bf553667aec5cd7eb0e9c6f7e471b370c']
records['commits']=[git('show','-s','--format=%H %T %P',s).decode().strip() for s in refs]
ordered=[refs[i] for i in [0,2,1,3,4,5]]
for a,b in zip(ordered,ordered[1:]): subprocess.run(['git','-C',str(W),'merge-base','--is-ancestor',a,b],check=True)
records['ancestry_verified']=True
records['remote_before']=git('ls-remote','origin','refs/heads/fix/paper-a-a3-6-b1-opt-v1','refs/heads/implementation/paper-a-ap3-all-formulations-v1').decode()
records['protected_refs_before']=git('show-ref').decode()
records['source_diff']=git('diff',refs[0],refs[-1],'--','src','scripts','test','Project.toml','Manifest-v1.10.toml').decode()
assert git('diff',refs[4],refs[-1],'--','src','scripts','test','Project.toml','Manifest-v1.10.toml')==b''
published=list(csv.DictReader((A/'published_file_sha256.csv').open(encoding='utf-8')))
for e in published:
    b=(A/e['path']).read_bytes(); assert len(b)==int(e['bytes']) and sha(b)==e['sha256'],e['path']
records['published_files_verified']=len(published)
def archive(p,manifest,entries,dest):
    b=p.read_bytes(); assert sha(b)==manifest['sha256'] and len(b)==manifest['bytes']
    with zipfile.ZipFile(p) as z:
        names=z.namelist(); assert len(names)==len(set(names))==manifest['entries']==len(entries)
        assert set(names)=={e['path'] for e in entries}
        for e in entries:
            target=(dest/e['path']).resolve(); assert target.is_relative_to(dest.resolve())
            b=z.read(e['path']); assert sha(b)==e['sha256'] and len(b)==e['bytes'],e['path']
        z.extractall(dest)
    return {'sha256':sha(p.read_bytes()),'bytes':p.stat().st_size,'entries_verified':len(entries)}
m=load(A/'reproduction_manifest.json')
records['a36_archive']=archive(A/m['archive']['path'],m['archive'],m['entries'],R/'prior')
m=load(A/'input_sha256_manifest.json')
paths=[p for p in W.rglob('executable_replay_evidence.zip') if '/a3_5/' in p.as_posix()]
assert len(paths)==1,paths
records['exec_archive']=archive(paths[0],m['archive'],m['verified_entries'],R/'prior/input')
H=W/'reports/ap3_runs/20261020_macro'; archived={}; archives=[]
for p in H.rglob('*.zip'):
    with zipfile.ZipFile(p) as z:
        assert z.testzip() is None
        for n in z.namelist():
            if n.endswith('/'): continue
            b=z.read(n); archived[(p.parent/Path(n)).relative_to(H).as_posix()]=(sha(b),len(b))
    archives.append({'path':p.relative_to(W).as_posix(),'sha256':sha(p.read_bytes())})
index=load(H/'export_final/evidence_index.json')['files']
for e in index:
    rel=e['path'].replace('\\','/'); p=H/rel
    actual=(sha(p.read_bytes()),p.stat().st_size) if p.is_file() else archived.get(rel)
    assert actual==(e['sha256'],e['bytes']),rel
records['historical_archives']=archives; records['historical_index_verified']=len(index)
inputs=load(R/'prior/input/input_sha256_manifest.json')
for e in inputs:
    p=Path(e['path']); assert sha(p.read_bytes())==e['sha256'],p
records['original_input_files_verified']=len(inputs)
science=load(R/'prior/input/science_source_manifest.json')
for e in science:
    b=subprocess.check_output(['git','-C','D:/Projekte/research-map','show',e['commit']+':'+e['path']])
    assert sha(b)==e['sha256']
    assert subprocess.check_output(['git','hash-object','--stdin'],input=b).decode().strip()==e['blob']
records['science_blobs_verified']=len(science)
(R/'integrity.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in records.items() if k not in ['source_diff','protected_refs_before','commits','historical_archives']},indent=2))
