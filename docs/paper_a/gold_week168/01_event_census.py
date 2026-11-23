from pathlib import Path
import csv,json,hashlib,math,sys
from collections import defaultdict
R=Path(__file__).parent; E=R.parent
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def tab(p):
 with p.open(encoding='utf-8-sig',newline='') as f:yield from csv.DictReader(f)
def getdirs():
 direct=['TECH_FULL37_KW08_RE50_GFM_FROZEN_E_20261118_01','TECH_FULL37_KW08_RE50_GFM_FROZEN_E_MIP_20261118_01','TECH_FULL37_KW08_RE60_70_FROZEN_E_20261118_01']
 dirs=[p.parent for k in direct for p in sorted((E/k).rglob('full_primal.csv'))]
 dirs.extend([E/'TECH_FULL37_KW08_RE70_STRENGTH_COMPARISON_20261118_01/G2/relaxed',E/'TECH_FULL37_KW08_RE70_SEQUENTIAL_CONDITIONED_20261120_01/03_G2_MILP/G2/integer'])
 assert len(dirs)==14
 return dirs
if __name__=='__main__':
 result={}
 for folder in getdirs():
  vec=folder/'full_primal.csv'; loc=folder/'variable_coordinates.csv'
  v={int(x['variable_index']):float(x['value']) for x in tab(vec)}
  maps={m:{} for m in ('su_block','sd_block')}
  for x in tab(loc):
   if x['container'] in maps:
    z=maps[x['container']];key=(int(x['snapshot']),x['coordinate'])
    assert key not in z;z[key]=v[int(x['variable_index'])]
  a,b=maps.values();assert a.keys()==b.keys() and len(a)>0
  pairs=sorted([(min(a[k],b[k]),k,a[k],b[k]) for k in a],reverse=True)
  counts={str(tol):sum(m>tol for m,*_ in pairs) for tol in (1e-8,1e-7,1e-6)}
  n=str(folder.relative_to(E))
  result[n]=dict(pairs=len(a),positive_both_by_block_threshold=counts,maxmin_and_location=pairs[0],primal_sha256=sha(vec),coordinate_sha256=sha(loc),summary_sha256=sha(folder/'run_summary.json'))
  print(n,counts,pairs[0],flush=True)
 with (R/'01_INDEPENDENT_EVENT_CENSUS.json').open('w') as f:json.dump({'reviewer':'/root/math_r','script':sha(Path(__file__)),'cases':result},f,indent=2)

