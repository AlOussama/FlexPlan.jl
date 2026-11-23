import csv,hashlib,json,sys,datetime,math
from pathlib import Path
def digest(p):
 with p.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def rows(p):
 with p.open(encoding='utf-8-sig',newline='') as f:yield from csv.DictReader(f)
def main(base):
 results={}
 for variant in ['with_gscr','without_gscr']:
  folder=base/'TECH_FULL37_KW08_RE50_GFM_FROZEN_E_20261118_01'/variant/'relaxed_crossover'
  later=base/'TECH_FULL37_KW08_RE60_70_FROZEN_E_20261118_01/quota_60/relaxed'/variant/'relaxed_crossover/variable_coordinates.csv'
  coord=folder/'variable_coordinates.csv'; point=folder/'full_primal.csv'; saved=folder/'period_1/dispatch.csv'
  caps={v['coordinate']:int(v['variable_index']) for v in rows(coord) if v['container']=='renewable_capacity'}
  nxt={(v['coordinate'],int(v['snapshot'])):int(v['variable_index']) for v in rows(later) if v['container']=='renewable_dispatch'}
  x={int(v['variable_index']):float(v['value']) for v in rows(point)}
  ref={(v['name'],round((datetime.datetime.fromisoformat(v['ts'])-datetime.datetime(2013,2,18)).total_seconds()/3600)+1):float(v['gen_MW']) for v in rows(saved) if v['new'].lower()=='true'}
  assert len(caps)==74 and len(ref)==len(nxt)==12432
  inferred={(n,t):i+t for n,i in caps.items() for t in range(1,169)}
  assert inferred==nxt and set(inferred)==set(ref)
  errs=[abs(100*x[i]-ref[k]) for k,i in inferred.items()];assert max(errs)<1e-8
  results[variant]={'new_dispatch_columns':len(inferred),'named_capacity_columns':len(caps),'authoring_order':'First hour of the single modeled week; a new named capacity column immediately precedes 168 chronological project dispatch columns. Explicit named independent cross-read of every project, timestamp, and MW.','base_MVA':100,'max_original_vs_named_dispatch_MW':max(errs),'files':{str(p.relative_to(base)):digest(p) for p in [coord,point,saved,later]}}
 return results
if __name__=='__main__':print(json.dumps(main(Path(sys.argv[1])),indent=2))
