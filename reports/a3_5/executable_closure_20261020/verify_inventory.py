from pathlib import Path
import hashlib,json,subprocess,zipfile
R=Path('D:/Projekte/Code/FlexPlan_A35_EXEC_RUN');B=Path('D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE');H=B/'reports/ap3_runs/20261020_macro'
def h(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
entries=json.loads((H/'export_final/evidence_index.json').read_text())['files'];archives={};zinfo=[]
for z in H.rglob('*.zip'):
    with zipfile.ZipFile(z) as f:
        for n in f.namelist():
            if n.endswith('/'):continue
            with f.open(n) as src:d=hashlib.file_digest(src,'sha256').hexdigest()
            key=(z.parent/Path(n)).relative_to(H).as_posix();archives[key]=(d,f.getinfo(n).file_size)
            zinfo.append(dict(zip=str(z.relative_to(B)),entry=n,raw_sha256=d,raw_bytes=f.getinfo(n).file_size))
verified=[]
for e in entries:
    rel=e['path'].replace('\\','/');p=H/rel
    actual=(h(p),p.stat().st_size) if p.is_file() else archives.get(rel)
    verified.append(dict(path=rel,expected_sha256=e['sha256'],expected_bytes=e['bytes'],actual=actual,match=actual is not None and actual[0]==e['sha256'] and actual[1]==e['bytes'],source='file' if p.is_file() else 'lossless_zip_entry' if actual else 'missing'))
(R/'historical_index_verification.json').write_text(json.dumps(dict(entries=verified,archive_entries=zinfo,matched=sum(x['match'] for x in verified),count=len(verified)),indent=2))
repos=[('FlexPlan',B,['485b637cc1998a327206c5929434bd26c6f0be16','50f88d5d30194afbbd188c96e3eab795b7a7de49','29192398bc7819a533b1e436c7f176b8dadb56e4','0574d491111677a7ac2cabff2877735171486c46','725de2e6c1cea21f63902474f72ec614b2358356','e992edc88d39fa0eb2d72e2490e157441223f568']),('research-map',Path('D:/Projekte/research-map'),['e8118425adc335a99e85120d943763305f211315','2c2fce769b2ed6ffd4f1ced60c0798776acccc93','672a61c95525bf1d7a03cf745a754a15a23ce78b','2badb9a90a8d3c1d4a33accee640b295de1e33a1','5ceb19a6faf4e7c7e797a737ed5b449f9e2db609']),('producer',Path('D:/Projekte/Code/pypsatomatpowerx'),['b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c','3b8fdb01d931225edc5f8fe1e2c200d0da288a09'])]
def git(path,*args):
    p=subprocess.run(['git','-C',str(path),*args],capture_output=True);return dict(code=p.returncode,output=p.stdout.decode('utf-8',errors='replace').strip(),error=p.stderr.decode('utf-8',errors='replace').strip())
states=[]
for name,path,refs in repos:
    states.append(dict(repo=name,path=str(path),status=git(path,'status','--short','--branch'),worktrees=git(path,'worktree','list','--porcelain'),remote_heads=git(path,'ls-remote','origin','refs/heads/main','refs/heads/implementation/paper-a-ap1-data-contract-v1','refs/heads/implementation/paper-a-ap3-all-formulations-v1','refs/heads/review/paper-a-a3-5-independent-acceptance-v1','refs/heads/review/paper-a-a3-5-science-release-v1'),objects=[dict(sha=s,type=git(path,'cat-file','-t',s),parents=git(path,'show','-s','--format=%H %P',s),merge_base=git(path,'merge-base',refs[0],s)) for s in refs]))
(R/'authority_git_inventory.json').write_text(json.dumps(states,indent=2))
inputs=[]
for folder in [B/'src',B/'scripts/paper_a',B/'test',R/'producer_3b8/data/paper_a_study',R/'producer_3b8/data/paper_a_ap1_synthetic']:
    for p in folder.rglob('*'):
        if p.is_file():inputs.append(dict(path=str(p),sha256=h(p),bytes=p.stat().st_size))
for p in [B/'Project.toml',B/'Manifest-v1.10.toml',R/'producer_3b8.zip']:
    inputs.append(dict(path=str(p),sha256=h(p),bytes=p.stat().st_size))
(R/'input_sha256_manifest.json').write_text(json.dumps(inputs,indent=2))
print('historical entries',len(verified),'matched',sum(x['match'] for x in verified),'inputs',len(inputs))
