"""Independent publication spot check, original portfolio vectors and independent G2 costs."""
from pathlib import Path
import os,csv,re,math,hashlib,json,mmap,sys
from collections import defaultdict
from importlib.util import spec_from_file_location,module_from_spec
R=Path(__file__).parent; E=R.parent; spec=spec_from_file_location('f1',R/'01_event_census.py');mod=module_from_spec(spec);spec.loader.exec_module(mod)
sha,tab=mod.sha,mod.tab
case=E/'TECH_FULL37_KW08_RE70_STRENGTH_COMPARISON_20261118_01/CASES/G2/case.json'
pr=Path('D:/Projekte/Code/pypsatomatpowerx/data/elec_s_37_csv/generators.csv')
price=E/'DEV01_20261109_01/public-cost/paper_a_2040_cost_bridge_candidate.csv'
physical=json.loads((R/'01_PHYSICAL_DOMAIN_AND_EVENT_REPLAY.json').read_bytes())
def case_hours():
 with case.open('rb') as f, mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as raw:
  pos=raw.find(b'"nw":{')+6
  for _ in range(168):
   h=re.match(rb'"(\d+)":',raw[pos:pos+20]);t=int(h[1]);pos+=h.end()
   v,sz=json.JSONDecoder().raw_decode(raw[pos:pos+2**21].decode('latin1'));pos+=sz+1;yield t,v
prices={row['technology']:row for row in tab(price)}
assets={row['name']:row for row in tab(pr)}
roster={};meta={};loads=[]
for t,sn in case_hours():
 if t==1:
  roster={(tabname,k):v for tabname in ('gen','storage','ne_storage') for k,v in sn[tabname].items() if 'p_block_max_MW' in v}
 loads.extend(x['pd']*100 for x in sn['load'].values())
 meta[t]=({k:(v['marginal_cost'],v['carrier']) for k,v in sn['gen'].items()}, {k:v['marginal_cost'] for k,v in sn['storage'].items()})
def check(folder):
 phys=physical['cases'][str(folder.relative_to(E))]
 summary=json.loads((folder/'run_summary.json').read_bytes()); native=summary['native_solver_attributes']
 q=int(summary['quota_pct']);m=phys['method'];integer='integer' in folder.name; id=f"WK08-{q}-{m}-"+('MILP' if integer else 'LP')
 v={int(x['variable_index']):float(x['value']) for x in tab(folder/'full_primal.csv')}
 agg=defaultdict(list);core=m=='G2' and integer
 pat=re.compile(r':(gen|storage|ne_storage),\s*(\d+)')
 for x in tab(folder/'variable_coordinates.csv'):
  t=int(x['snapshot']);name=x['container'];key=x['coordinate'];val=v[int(x['variable_index'])]
  if name=='renewable_capacity':
   car=assets[key]['carrier'];agg[car].append(val);agg['capex'].append(val*float(prices[car]['cost_inv_per_mw']))
  elif name=='n_block' and t==1:
   device=roster[pat.search(key).groups()];add=(val-device['n0'])*device['p_block_max_MW']
   agg['capex'].append(add*device['cost_inv_per_mw'])
   if device['carrier'].lower()=='battery':agg['GFL_BESS'].append(add)
   if device['carrier'].lower()=='bess-gfm':agg['GFM_BESS'].append(add)
  elif core:
   if name in ('su_block','sd_block'):
    dev=roster[pat.search(key).groups()];agg['event'].append(dev['p_block_max_MW']*dev['startup_cost_per_mw' if name=='su_block' else 'shutdown_cost_per_mw']*val)
   elif name=='renewable_dispatch':
    car=assets[key]['carrier'];agg['generation'].append(100*val*float(prices[car]['marginal_cost_EUR_per_MWh']));agg['re'].append(100*val)
   elif name=='pg':
    k=re.search(r'\d+',key).group();c,car=meta[t][0][k];agg['generation'].append(100*val*c)
    if car in ('solar','offwind-ac','offwind-dc','onwind'):agg['re'].append(100*val)
   elif name=='sd':
    k=re.search(r'\d+',key).group();agg['storage'].append(100*val*meta[t][1][k])
 sums={k:math.fsum(a) for k,a in agg.items()}
 assert abs(sums['capex']-summary['annualized_capex_EUR2025'])<0.10
 scalar=summary.get('native_objective_cost_divisor',1)
 lb=native['ObjBound']*scalar; ub=native['ObjVal']*scalar
 assert abs(lb-summary['best_bound_EUR2025'])<0.10 and abs(ub-summary['objective_EUR2025'])<0.10
 rec=dict(case_id=id,original_primal_sha256=sha(folder/'full_primal.csv'),coordinate_sha256=sha(folder/'variable_coordinates.csv'),native_summary_sha256=sha(folder/'run_summary.json'),solver_LB=lb,raw_native_primal=ub,case_time_cost_divisor=scalar,incumbent_gap_or_LP_gap=summary.get('relative_gap'),raw_MW_and_EUR=sums,original_columns=len(v))
 if core:
  o=math.fsum(sums[k] for k in ('generation','storage','event'));J=sums['capex']+8760/168*o
  assert abs(J-ub)<0.10 and abs(sums['re']-summary['wind_pv_MWh'])<1e-5 and abs(math.fsum(loads)-summary['load_MWh'])<1e-5
  rec.update(replayed_J=J,replayed_load=math.fsum(loads),raw_week_opex=o,absolute_EUR_error=abs(J-ub))
 print(id,flush=True)
 return rec
cases={s['case_id']:s for s in map(check,mod.getdirs())}
out={'reviewer':'/root/math_r in F4-R role','independent_code_sha256':sha(Path(__file__)),'command':[sys.executable,str(Path(__file__))],'input_sha256':{str(p):sha(p) for p in [case,pr,price]},'original_cases':cases,'exit':0}
(R/'05_ORIGINAL_PUBLICATION_SAMPLES.json').write_text(json.dumps(out,indent=2),encoding='utf8')

