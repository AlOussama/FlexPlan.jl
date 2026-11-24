"""Check the publication inputs against independent F2 receipts and native log headers. No solve."""
import argparse,csv,hashlib,json,re
from decimal import Decimal as D, ROUND_FLOOR,ROUND_CEILING
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
for key in ('paper','evidence','archive','g3-map','output'):parser.add_argument('--'+key,type=Path,required=True)
a=parser.parse_args()
def digest(f):
 with f.open('rb') as h:return hashlib.file_digest(h,'sha256').hexdigest()
def obj(f):return json.loads(f.read_bytes())
def table(f):
 with f.open(encoding='utf-8-sig',newline='') as h:return list(csv.DictReader(h))
def data(n):return (a.paper/n).read_text(encoding='utf-8-sig')
def end(x,lower,digits):
 return format(x.quantize(D(1).scaleb(-digits),rounding=ROUND_FLOOR if lower else ROUND_CEILING),'f')
def iter_values(o,key=''):
 if isinstance(o,dict):
  for k,v in o.items():yield from iter_values(v,key+'/'+k)
 elif isinstance(o,list):
  for i,v in enumerate(o):yield from iter_values(v,key+'/'+str(i))
 else:yield key,o
def num(v):return D(str(v))
auth=obj(a.evidence/'02_INDEPENDENT_ACCEPTANCE.json')
events=[];computed={};numeric=[];all_sources={}
def ck(key,condition,detail):
 if not condition:raise ValueError((key,detail))
 numeric.append(dict(assertion=key,checked=detail))
points=table(a.paper/'04_reviewed_points.csv')
bounds={r['row_id']:r for r in table(a.paper/'04_reviewed_bounds.csv')}
for f,ref in [('04_reviewed_points.csv','02_FINAL_WEEK168_RESULT_MATRIX.csv'),('04_reviewed_bounds.csv','02_OBJECTIVE_AND_SOLVER_BOUNDS.csv'),('04_additional_methods.csv','03_QUALIFIED_REAL_METHOD_RESULTS.csv')]:
 ck(f,digest(a.paper/f)==digest(a.evidence/ref),digest(a.evidence/ref))
for r in points:
 key=r['row_id'];b=bounds[key];rr=auth['case_receipts'][key];p=a.evidence/rr['relative_path'];raw=obj(p)
 ck(key+':F2_receipt',rr['sha256']==digest(p)==r['original_replay_sha256'],rr['sha256'])
 log=Path(raw['folder'])/'gurobi.log';version=re.findall(r'Gurobi Optimizer version ([0-9.]+)',log.read_text(errors='replace'))
 ck(key+':native_version',version==[r['solver_version']] and digest(log)==raw['solver_log_sha256'],dict(version=version[0],native_log_sha256=digest(log)))
 for orig,col in {'CAPEX':'CAPEX_EUR2025','RE':'actual_RE_MWh','load':'actual_load_MWh','OPEX_gen':'raw_week_dispatch_OPEX_EUR2025','OPEX_event':'raw_week_startup_shutdown_OPEX_EUR2025','OPEX_storage':'raw_week_storage_OPEX_EUR2025','raw_week_OPEX':'raw_week_OPEX_EUR2025','annualized_week_OPEX':'annualized_week_OPEX_EUR2025','annualized_total':'annualized_total_EUR2025','renewable_share_pct':'actual_RE_share_pct'}.items():
  ck(key+':'+col,num(raw['cost_replay'][orig])==D(r[col]),r[col])
 for col,v in raw['portfolio_MW'].items():ck(key+':'+col,num(v)==D(r[col]),r[col])
 for family,fields in raw['margins'].items():
  for k in ['failed_hours','defined_hours']:ck(key+':'+family+'_'+k,int(r[family+'_'+k])==fields[k],fields[k])
 for col in ['G1','G2','G0','M0']:
  ck(key+':hours_'+col,int(r[col+'_defined_hours'])+int(r[col+'_undefined_hours'])==168,[r[col+'_defined_hours'],r[col+'_undefined_hours']])
 cap,op,tot=[D(r[k]) for k in ['CAPEX_EUR2025','raw_week_OPEX_EUR2025','annualized_total_EUR2025']]
 ck(key+':annual_coordinate',abs(cap+op*D(8760)/168-tot)<D('0.001'),str(tot))
 ck(key+':native_UB',D(b['numeric_ub_EUR2025'])==tot and D(b['numeric_lb_EUR2025'])<=tot,[b['numeric_lb_EUR2025'],str(tot)])
 e=int(r['SU_SD_positive_overlaps']);ck(key+':events',e==raw['simultaneous_positive_SU_SD'],[e,r['avoidable_overlap_week_EUR2025']])
 if e:events.append((key,e,r['avoidable_overlap_week_EUR2025']))
 computed[key]={'portfolio_GW':{k:str(num(v)/1000) for k,v in raw['portfolio_MW'].items()},'margins':raw['margins'],'quota_pct':r['actual_RE_share_pct'],'cost':raw['cost_replay'],'version':version[0],'gap_pct':str(D(b['relative_gap_fraction'])*100)}
ck('version partition',sum(x['solver_version']=='12.0.3' for x in points)==13 and [x['row_id'] for x in points if x['solver_version']=='13.0.3']==['WK08-70-G2-MILP'],len(points))
matrix=data('04_results.tex')
published_table=re.findall(r'(?m)^(\d+)\\%\s*&\s*(BASE|G1|G2)\s*&\s*([\d.]+)\s*&\s*([\d.]+)\s*&\s*([\d.]+)\s*&\s*([\d.]+)',matrix)
ck('paired table row count',len(published_table)==7,len(published_table))
billion=D(10)**9
for q,m,lp,lb,ub,gap in published_table:
 s='WK08-'+q+'-'+m+'-';l=bounds[s+'LP'];b=bounds[s+'MILP']
 expected=[end(D(l['numeric_lb_EUR2025'])/billion,True,4),end(D(b['numeric_lb_EUR2025'])/billion,True,4),end(D(b['numeric_ub_EUR2025'])/billion,False,4)]
 ck(s+'printed endpoints',[lp,lb,ub]==expected,expected)
 ck(s+'printed gap',abs(D(gap)-D(b['relative_gap_fraction'])*100)<=D('0.0005'),gap)
prem=[]
for q in [50,60,70]:
 a0=bounds[f'WK08-{q}-BASE-MILP'];b=bounds[f'WK08-{q}-G1-MILP']
 lo=(D(b['numeric_lb_EUR2025'])-D(a0['numeric_ub_EUR2025']))/billion
 hi=(D(b['numeric_ub_EUR2025'])-D(a0['numeric_lb_EUR2025']))/billion
 ck(f'premium {q}',lo>0 and lo<hi,[str(lo),str(hi)])
 prem.append([str(lo),str(hi),end(lo,True,3),end(hi,False,3)])
 ck(f'narrative endpoints {q}',re.search(re.escape(end(lo,True,3))+r'\s*,\s*'+re.escape(end(hi,False,3)),matrix) is not None,prem[-1])
 bb=bounds['WK08-70-G2-MILP'];g=bounds['WK08-70-G1-MILP']
ck('G1/G2 intervals overlap',max(D(bb['numeric_lb_EUR2025']),D(g['numeric_lb_EUR2025']))<=min(D(bb['numeric_ub_EUR2025']),D(g['numeric_ub_EUR2025'])),str((D(g['numeric_ub_EUR2025'])-D(bb['numeric_ub_EUR2025']))/D('1e6')))
sources=obj(a.g3_map);g3=[]
for row in table(a.paper/'04_g3_attempts.csv'):
 p=a.archive/sources[row['evidence_sha256']];j=obj(p);ck(row['code']+':source',digest(p)==row['evidence_sha256'],digest(p))
 population=[(p,j)]
 for k,v in j.get('evidence',{}).items():
  dep=Path(k)
  if dep.suffix=='.json' and dep.is_file() and digest(dep)==v:population.append((dep,obj(dep)))
 if j.get('summary_sha256'):
  for dep in a.archive.glob('TECH_FULL37_KW08_RE70_*/**/run_summary.json'):
   if digest(dep)==j['summary_sha256']:population.append((dep,obj(dep)));break
 hit=[]
 for path,doc in population:
  hit.extend((str(path),digest(path),k) for k,v in iter_values(doc) if isinstance(v,(int,float)) and row['distance'] and float(row['distance'])==v)
 if row['distance']:ck(row['code']+':distance',bool(hit),hit)
 else:ck(row['code']+':absent_full_distance',row['code'].startswith('0754707') and j['disposition']=='NUMERICAL_REJECT',j['disposition'])
 g3.append(dict(row=row,original_locations=hit))
mt=table(a.paper/'04_additional_methods.csv')
ub=next(D(x['objective_EUR2025']) for x in mt if x['method']=='G3' and x['mode']=='integer_witness')
lb=next(D(x['qualified_numerical_bound_EUR2025']) for x in mt if x['method']=='M2' and x['mode']=='relaxed')
extensions=dict(witness_ub=str(ub),m2_lb=str(lb),separation_EUR=str(lb-ub),suggested_printed_UB=end(ub/billion,False,6),suggested_printed_LB=end(lb/billion,True,6))
from collections import Counter
result=dict(reviewer='/root (DATA-R, independent of PAPER-W)',script_sha256=digest(Path(__file__)),f2_receipt_sha256=digest(a.evidence/'02_INDEPENDENT_ACCEPTANCE.json'),f2_model_optimizations=0,checks=numeric,check_count=len(numeric),cost_bound_intervals=prem,events=events,per_case=computed,g3=g3,extensions=extensions,version_count=dict(Counter(x['solver_version'] for x in points)),scope='All aggregate inputs checked against archived receipts, native versions and numerical cells. The final separately executed T3 suite checks the corrected actual prose and figures.',exit=0)
a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(len(numeric),'checks;',len(points),'F2 points;',len(g3),'original G3 attempts;',extensions)
