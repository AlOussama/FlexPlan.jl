"""Check additive scope and preservation immediately before publication."""
from pathlib import Path
import hashlib,json,subprocess,sys
W=Path(sys.argv[1]); R=Path(sys.argv[2]); branch='codex/a3-6-independent-reaudit-20261021'
def git(*args): return subprocess.check_output(['git','-C',str(W),*args]).decode().strip()
assert git('branch','--show-current')==branch
old=json.loads((R/'integrity.json').read_text(encoding='utf-8'))
before={l.split()[1]:l.split()[0] for l in old['protected_refs_before'].splitlines()}
after={l.split()[1]:l.split()[0] for l in git('show-ref').splitlines()}
for ref,sha in before.items():
    if ref!='refs/heads/'+branch: assert after[ref]==sha,ref
for folder in ['src','scripts','test','Project.toml','Manifest-v1.10.toml','reports/a3_5','reports/a3_6/b1_opt_20261020']:
    assert not git('diff','1147873bf553667aec5cd7eb0e9c6f7e471b370c','--',folder),folder
changed=git('diff','--name-only','1147873bf553667aec5cd7eb0e9c6f7e471b370c').splitlines()
assert all(p.startswith('reports/a3_6/reaudit_20261021/') for p in changed)
states=[]
for repo,head in [('D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE','485b637cc1998a327206c5929434bd26c6f0be16'),('D:/Projekte/Code/FlexPlan_A36_B1_OPT_FIX','1147873bf553667aec5cd7eb0e9c6f7e471b370c')]:
    actual=subprocess.check_output(['git','-C',repo,'rev-parse','HEAD']).decode().strip(); assert actual==head
    state=subprocess.check_output(['git','-C',repo,'status','--porcelain']).decode(); assert state==''
    states.append({'path':repo,'HEAD':actual,'clean':True})
remote=git('ls-remote','origin','refs/heads/fix/paper-a-a3-6-b1-opt-v1','refs/heads/implementation/paper-a-ap3-all-formulations-v1')
assert remote==old['remote_before'].strip()
out={'branch':branch,'basis':'1147873bf553667aec5cd7eb0e9c6f7e471b370c','protected_refs_unchanged':True,'unchanged_protected_ref_count':len(before)-1,'original_and_fix_worktrees':states,'frozen_remote_refs':remote,'frozen_source_and_evidence_diff_empty':True,'scope':'only new reports/a3_6/reaudit_20261021 files may be committed'}
(R/'final_preservation.json').write_text(json.dumps(out,indent=2),encoding='utf-8'); print(json.dumps(out,indent=2))
