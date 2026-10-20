import json, hashlib, pathlib, zipfile, subprocess, datetime
B=pathlib.Path('D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE')
F=pathlib.Path('D:/Projekte/Code/FlexPlan_A35_EXEC_REVIEW')
R=pathlib.Path(__file__).parent
A=F/'reports/a3_5/executable_closure_20261020'
O=F/'reports/a3_6/b1_opt_20261020'
O.mkdir(parents=True,exist_ok=False)
def sha(b): return hashlib.sha256(b).hexdigest()
def save(p,v): p.write_text(json.dumps(v,indent=2),encoding='utf-8')
m=json.loads((A/'reproduction_manifest.json').read_text())
zpath=A/m['archive']['path']; zb=zpath.read_bytes()
assert len(zb)==24237795 and sha(zb)==m['archive']['sha256']
entries=[]
with zipfile.ZipFile(zpath) as z:
    for e in m['entries']:
        b=z.read(e['path']); assert sha(b)==e['sha256'] and len(b)==e['bytes'],e
        p=R/'input'/e['path'];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
        entries.append(e)
save(R/'input_verification.json',{'archive':m['archive'],'verified_entries':entries,'count':len(entries)})
for name in ['b1_exact_native_repro.jl','b1_transfer_full_witness.jl','independent_jump_moi_audit.jl','independent_domain_mutations.jl','independent_integer_b1_audit.jl']:
    p=R/'tools'/name;p.parent.mkdir(exist_ok=True);p.write_bytes((A/name).read_bytes())
for path in ['original_01','original_02','metadata_01','integer_fresh','tests','experiments']:(R/path).mkdir()
records=[]
def git(repo,*args):
    r=subprocess.run(['git','-C',str(repo),*args],capture_output=True,text=True)
    records.append({'repo':str(repo),'args':args,'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
for repo in [B,F,pathlib.Path('D:/Projekte/research-map')]:
    for args in [('status','--porcelain=v1'),('worktree','list','--porcelain'),('rev-parse','HEAD'),('remote','-v')]:git(repo,*args)
for ref in ['485b637cc1998a327206c5929434bd26c6f0be16','4d9f346c5fca80e00fd01d96c39a2bac91776ac0','e1e075626b38b478faf57efe62e557fc94753f00','e49b64216f82eefda77d6997ed68ed2d12c8ae78','50f88d5d30194afbbd188c96e3eab795b7a7de49']:
    git(B,'show','-s','--format=%H %P %s',ref)
    git(B,'merge-base','485b637cc1998a327206c5929434bd26c6f0be16',ref)
git(B,'ls-remote','origin','refs/heads/implementation/paper-a-ap3-all-formulations-v1','refs/heads/fix/paper-a-a3-5-executable-closure-v1','refs/heads/review/paper-a-a3-5-independent-acceptance-v1')
git(B,'ls-remote','https://github.com/AlOussama/PyPSA2MatpowerX.git','refs/heads/implementation/paper-a-ap1-data-contract-v1')
git(pathlib.Path('D:/Projekte/research-map'),'ls-remote','origin','refs/heads/main','refs/heads/review/paper-a-a3-5-science-release-v1')
git(pathlib.Path('D:/Projekte/research-map'),'cat-file','-t','fba4802ecabade61a752833a71106a5bda4ce78f')
save(R/'authority_preflight.json',records)
print('Verified',len(entries),'archive entries; scratch and audit directories created')
