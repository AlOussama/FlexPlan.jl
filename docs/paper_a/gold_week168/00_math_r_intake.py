"""Independent SHA and git-object verification of ORCH Gate 0; no production imports."""
import hashlib,json,subprocess,sys
from pathlib import Path
R=Path(__file__).parent; E=R.parent
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
src=R/'00_INPUT_AND_RUNTIME_INTAKE.json';d=json.loads(src.read_bytes());m=Path(d['repos']['science']['local_path'])
def git(p,*args):return subprocess.check_output(['git','-C',str(p),*args])
checks=[]
for a in d['governance']:
 ref=a['ref']+':'+a['path'];data=git(m,'show',ref)
 assert a['sha256']==hashlib.sha256(data).hexdigest() and len(data)==a['bytes']
 assert a['blob']==hashlib.sha1(b'blob '+str(len(data)).encode()+b'\x00'+data).hexdigest()
 checks.append({'git':ref,'sha256':a['sha256']})
for a in [*d['archive_objects'],d['Q4']['file'],d['runtime']['lockfile'],d['storage']['checked_write']]:
 p=E/a['relative_path'] if 'relative_path' in a else Path(a['path'])
 assert sha(p)==a['sha256'] and p.stat().st_size==a['bytes'],p;checks.append({'path':str(p),'sha256':a['sha256']})
heads={}
for k,v in d['repos'].items():
 path=Path(v['local_path']);assert git(path,'cat-file','-t',v['head']).strip()==b'commit'
 heads[k]={'intake':v['head'],'now':git(path,'rev-parse','HEAD').strip().decode(),'current_diff_sha256':hashlib.sha256(git(path,'diff')).hexdigest(),'current_status':git(path,'status','--short','--branch').decode().splitlines()}
assert heads['producer']['current_diff_sha256']==d['Q4']['git_diff_sha256']
g2=[v for v in d['core'] if v['case_id'].startswith('G2')]
assert len(g2)==2 and len(d['core'])==14
report=dict(reviewer='/root/math_r',source_sha256=sha(src),reviewer_code_sha256=sha(Path(__file__)),checks=checks,repos=heads,core_cases=[v['case_id'] for v in d['core']],G2=g2,verdict='PASS_SECOND_INDEPENDENT_INTAKE_HASHCHECK',command=[sys.executable,str(Path(__file__))],exit=0)
out=R/'00_INDEPENDENT_INTAKE_HASHCHECK.json';out.write_text(json.dumps(report,indent=2),encoding='utf-8');print(len(checks),sha(out))

