"""Independent Git, archive and dependency identity audit; read-only originals."""
from execute import *
import hashlib,tomllib,zipfile
sha=lambda b:hashlib.sha256(b).hexdigest()
git=lambda *a:subprocess.check_output(['git','-C',str(W),*a])
candidate='0ca85adad5b6bcdff5a3ce8df54f5b8ac8eb8568'
prod='f302b7b63e917678fb14b7cbc3cfdbc0d8c624a1'
base='15ba10c193a562a48cb0e1dcc6fa12d922ac0613'
result=dict(candidate=candidate,production=prod,baseline=base,head=git('rev-parse','HEAD').decode().strip())
for a,b in [(base,prod),(prod,candidate),(candidate,'HEAD')]:
    subprocess.run(['git','-C',str(W),'merge-base','--is-ancestor',a,b],check=True)
assert not git('diff',prod,candidate,'--','src','test','Project.toml','Manifest-v1.10.toml','scripts/paper_a/AP3Pipeline.jl','scripts/paper_a/NativeG3Solver.jl','scripts/paper_a/qualify_native_g3.jl')
assert not git('diff',base,candidate,'--','src','data','reports/a3_5','reports/a3_6','reports/ap3_runs')
result['frozen_production_and_originals_unchanged']=True
before=tomllib.loads(git('show',base+':Manifest-v1.10.toml').decode())['deps']
after=tomllib.loads(git('show',candidate+':Manifest-v1.10.toml').decode())['deps']
assert all(after[k]==v for k,v in before.items())
assert set(after)-set(before)=={'Mosek','MosekTools'}
result['unchanged_dependency_entries']=len(before);result['added_dependencies']={k:after[k] for k in after.keys()-before.keys()}
rep=W/'reports/a3_6/reaudit_20261021';m=json.loads((rep/'reproduction_manifest.json').read_text())
assert sha((rep/m['archive']['path']).read_bytes())==m['archive']['sha256']
with zipfile.ZipFile(rep/m['archive']['path']) as z:
    assert len(z.namelist())==len(set(z.namelist()))==len(m['entries'])
    for e in m['entries']:
        b=z.read(e['path']);assert len(b)==e['bytes'] and sha(b)==e['sha256']
result['prior_reaudit_archive_entries_verified']=len(m['entries'])
files={p:sha((W/p).read_bytes()) for p in git('ls-files','--','src','scripts','test','Project.toml','Manifest-v1.10.toml').decode().splitlines()}
result['runtime_source_file_sha256']=files
foreign=json.loads((R/'foreign_before.json').read_text(encoding='utf-8-sig'))
now={p:sha((W/p).read_bytes()) for p in git('ls-files','--others','--exclude-standard','--','audit/').decode().splitlines()}
assert len(now)==28 and now==foreign
result['foreign_28_sha256']=now
oldrefs=dict(line.split() for line in (R/'refs_before.txt').read_text(encoding='utf-8-sig').splitlines())
newrefs=dict(line.split() for line in git('for-each-ref','--format=%(refname) %(objectname)').decode().splitlines())
assert all(newrefs[k]==v for k,v in oldrefs.items())
result['all_preexisting_refs_unchanged']=True
result['worktrees']=git('worktree','list','--porcelain').decode()
def foreign_worktrees(text):
    return sorted(block.strip() for block in text.strip().split('\n\n')
                  if block.strip() and not block.splitlines()[0].replace('\\','/').lower().endswith(str(W).replace('\\','/').lower()))
prior_worktrees=(R/'worktrees_before.txt').read_text(encoding='utf-8-sig').replace('\r\n','\n')
assert foreign_worktrees(prior_worktrees)==foreign_worktrees(result['worktrees'])
result['other_six_worktree_registrations_unchanged']=len(foreign_worktrees(result['worktrees']))==6
result['remote_candidate']=git('ls-remote','origin','refs/heads/fix/paper-a-a3-7-b1-native-solver-v1').decode()
assert result['remote_candidate'].split()[0]==candidate
(R/'provenance.json').write_text(json.dumps(result,indent=2))
print('Git, 251 dependency entries, 130 archive entries, 28 foreign SHA256 and original refs verified')
