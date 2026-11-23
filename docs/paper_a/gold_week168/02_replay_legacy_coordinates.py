from pathlib import Path
import csv,datetime,hashlib,json,os
out=Path(os.environ.get('PAPER_A_F2_OUTPUT_ROOT',Path(__file__).resolve().parent));base=Path(os.environ.get('PAPER_A_F2_INPUT_ROOT',Path(__file__).resolve().parent.parent));src=base/'TECH_FULL37_FIVE_WEEKS_RE50_20261115_01/run_common.jl'
def sha(p):
 with p.open('rb') as h:return hashlib.file_digest(h,'sha256').hexdigest()
def rows(p):
 with p.open(encoding='utf-8-sig',newline='') as h:yield from csv.DictReader(h)
def read(p):return json.loads(p.read_bytes())
part=src.read_text(encoding='utf-8-sig').splitlines()[178:189];assert 'get!(capital,name)' in part[0] and any('@variable' in v and 'new_gen_pu' in v for v in part)
res={}
for family in ['with_gscr','without_gscr']:
 f=base/'TECH_FULL37_KW08_RE50_GFM_FROZEN_E_20261118_01'/family/'relaxed_crossover';later=base/'TECH_FULL37_KW08_RE60_70_FROZEN_E_20261118_01/quota_60/relaxed'/family/'relaxed_crossover'
 key=lambda a:(a['snapshot'],a['container'],a['coordinate'])
 caps={};early={}
 for a in rows(f/'variable_coordinates.csv'):
  i=int(a['variable_index']);early[key(a)]=i
  if a['container']=='renewable_capacity':caps[a['coordinate']]=i
 assert len(caps)==74 and len(set(early.values()))==298963
 own={(str(t),'renewable_dispatch',k):idx+t for k,idx in caps.items() for t in range(1,169)}
 assert set(own.values()).isdisjoint(early.values()) and set(early.values())|set(own.values())==set(range(1,311396))
 full={key(x):int(x['variable_index']) for x in rows(later/'variable_coordinates.csv')}
 assert full==early|own
 point={int(x['variable_index']):float(x['value']) for x in rows(f/'full_primal.csv')};seen=set();mx=0.
 for a in rows(f/'period_1/dispatch.csv'):
  if a['new'].lower()!='true':continue
  t=1+int((datetime.datetime.fromisoformat(a['ts'])-datetime.datetime(2013,2,18)).total_seconds()/3600)
  k=(str(t),'renewable_dispatch',a['name']);assert k in own and k not in seen;seen.add(k);mx=max(mx,abs(100*point[own[k]]-float(a['gen_MW'])))
 assert len(seen)==12432 and mx<1e-7
 res[family]=dict(originally_labelled=len(set(early.values())),recovered_count=len(seen),formula='i(dispatch[name,t])=i(its own exported capacity[name])+t',later_full_key_and_index_equality=True,max_dispatch_delta_MW=mx,source_sha256={str(x):sha(x) for x in [f/'variable_coordinates.csv',f/'full_primal.csv',later/'variable_coordinates.csv',f/'period_1/dispatch.csv',f/'run_summary.json']})
q=out/'02_RE50_LP_COORDINATE_PROOF.json'
q.write_text(json.dumps(dict(reviewer='/root/qa_r',original_source=str(src),source_sha256=sha(src),source_lines=[179,189],source_excerpt=part,replay_sha256=sha(Path(__file__)),rows=res),indent=2)+'\n')
print(sha(q),[x['max_dispatch_delta_MW'] for x in res.values()])
