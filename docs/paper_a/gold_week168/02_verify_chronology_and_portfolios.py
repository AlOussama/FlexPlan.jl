from pathlib import Path
from datetime import datetime,timedelta
import hashlib,json,sys,math,csv,importlib.util,os
sys.dont_write_bytecode=True
out=Path(os.environ.get('PAPER_A_F2_OUTPUT_ROOT',Path(__file__).resolve().parent));base=Path(os.environ.get('PAPER_A_F2_INPUT_ROOT',Path(__file__).resolve().parent.parent));prod=Path(os.environ.get('PAPER_A_F2_PRODUCER_ROOT','D:/Projekte/Code/pypsatomatpowerx'))/'data/elec_s_37_csv'
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def read(p):return json.loads(p.read_bytes())
def rows(p):
 with p.open(encoding='utf-8-sig',newline='') as f:yield from csv.DictReader(f)
archive=base/'TECH_FULL37_KW08_RE70_STRENGTH_COMPARISON_20261118_01';src=archive/'INDEPENDENT_REVIEW/review_actual_case_bytes.py';sp=importlib.util.spec_from_file_location('stream',src);m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
expected=[datetime(2013,2,18)+timedelta(hours=i) for i in range(168)]
rr=list(rows(prod/'snapshots.csv'));raw=[datetime.fromisoformat(x.get('name') or x.get('snapshot') or next(iter(x.values()))) for x in rr[1152:1320]];assert raw==expected
cases=[]
for p in [base/'TECH_FULL37_840H_RE50_GFM_FROZEN_E_20261117_01/AP2_SOURCE_VARIANTS/week_8/derived_case.json',archive/'CASES/G2/case.json']:
 for k,d in m.Reader(p).items():
  if k==('snapshot_ids',):
   assert sorted(map(int,d))==list(range(1,169)) and [datetime.fromisoformat(d[str(i)]) for i in range(1,169)]==expected;break
 else:raise AssertionError('missing chronological labels')
 cases.append(sha(p))
facts={}
for p in sorted((out/'02_final_rows').glob('*.json')):
 x=read(p);f=Path(x['folder']);d=f/'dispatch.csv' if (f/'dispatch.csv').exists() else f/'period_1/dispatch.csv';br=f/'block_expansion.csv';re=f/'renewable_expansion.csv'
 windpv=[float(v['gen_MW']) for v in rows(d) if v['carrier'] in ('onwind','offwind-ac','offwind-dc','solar')];assert min(windpv)>=0 and abs(math.fsum(windpv)-x['cost_replay']['RE'])<1e-5
 vals={k:[] for k in ['wind','PV','GFM_BESS','GFL_BESS']}
 for v in rows(br):
  c=v['carrier'];cat='wind' if c in ('onwind','offwind-ac','offwind-dc') else 'PV' if c=='solar' else 'GFM_BESS' if c=='BESS-GFM' else 'GFL_BESS' if c=='battery' else None
  if cat:vals[cat].append(float(v['added_blocks'])*float(v['block_MW']))
 for v in rows(re):
  c=v['carrier'];assert c in ('onwind','solar');vals['wind' if c=='onwind' else 'PV'].append(float(v['added_MW']))
 delta={c:abs(math.fsum(v)-x['portfolio_MW'][c+'_added_MW']) for c,v in vals.items()}
 assert max(delta.values())<1e-6
 facts[x['row_id']]=dict(min_RE_dispatch_MW=min(windpv),positive_net_RE_delta_MWh=abs(math.fsum(windpv)-x['cost_replay']['RE']),max_portfolio_addition_delta_MW=max(delta.values()),absolute_exposure_negativity_pu=x['maxima']['exposure_nonnegative_pu']['abs'],source_hashes={str(y):sha(y) for y in [d,br,re]})
 assert facts[x['row_id']]['absolute_exposure_negativity_pu']==0
p=out/'02_CHRONOLOGY_AND_PORTFOLIO_CROSSCHECK.json';p.write_text(json.dumps(dict(reviewer='/root/qa_r',script_sha256=sha(Path(__file__)),input_snapshot_csv_sha256=sha(prod/'snapshots.csv'),case_shas=cases,chronology='All original case time indices 1..168 agree exactly with consecutive 2013-02-18 00:00 to 2013-02-24 23:00 and source snapshots [1152:1320].',rows=facts),indent=2)+'\n')
print(sha(p),max(x['max_portfolio_addition_delta_MW'] for x in facts.values()))
