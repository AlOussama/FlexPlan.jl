"""Independent original coordinates replay for complete or interrupted SGOV145 exports."""
import ast,csv,hashlib,json,math,os,re,sys
from pathlib import Path
from collections import defaultdict,Counter
from fractions import Fraction
import numpy as np
root=Path(os.environ.get('PAPER_A_F2_INPUT_ROOT',Path(__file__).resolve().parent.parent))
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def read(p):return json.loads(p.read_bytes())
def csvrows(p):
 with p.open(encoding='utf-8-sig',newline='') as f:yield from csv.DictReader(f)
def run(folder,case,method,mode):
 summary=read(folder/'run_summary.json');casehash=sha(case);quota=summary['quota_pct'];early=quota==50 and mode=='relaxed';old=method!='G2'
 if old:
  actual=summary['derived_source_variants']['8'];assert casehash==actual['derived_AP2_case_sha256']
  code=summary['C_commit'];nvars=summary.get('model_variable_count',311395);ndisc=111401
 else:
  nativeprof=read(folder/'profile.json');assert nativeprof['criterion']==method and nativeprof['case_sha256']==casehash
  code=nativeprof['consumer_commit'];nvars=nativeprof['variables'];ndisc=nativeprof['original_discrete_count']
 raw=Path(os.environ.get('PAPER_A_F2_PRODUCER_ROOT','D:/Projekte/Code/pypsatomatpowerx'))/'data/elec_s_37_csv'
 bridge=root/'DEV01_20261109_01/public-cost/paper_a_2040_cost_bridge_candidate.csv'
 files=[case,folder/'full_primal.csv',folder/'variable_coordinates.csv',bridge,*[raw/x for x in ('generators.csv','generators-p_max_pu.csv','snapshots.csv','loads-p_set.csv')]]
 hashes={str(f):sha(f) for f in files}
 assert hashes[str(bridge)]=='ec344ecd4c191595b054f5d66474b82f8079069ee6fa2ef0c7e1223de436d8e5'
 assert hashes[str(raw/'generators-p_max_pu.csv')]=='45336cff93e75ffc9a1a5aae2bc3e8ad8f7054b2f8bcb267d25607c73cc45f46'
 price={x['technology']:x for x in csvrows(bridge)}
 vals={};bounds=0.;int_err=0.;discrete=0
 for x in csvrows(files[1]):
  i=int(x['variable_index']);v=float(x['value']);assert i not in vals and math.isfinite(v);vals[i]=v
  bounds=max(bounds,float(x['lower_bound'])-v,v-float(x['upper_bound']))
  if x.get('is_integer')=='true' or x.get('is_binary')=='true':discrete+=1;int_err=max(int_err,abs(v-round(v)))
 assert len(vals)==nvars and set(vals)==set(range(1,len(vals)+1))
 assert discrete==(ndisc if mode=='integer' else 0)
 coords={};seen=set()
 def parse(c,k):
  if c in ('renewable_capacity','renewable_dispatch'):return k
  if ':' in k:
   m=re.search(r':(gen|storage|ne_storage),\s*(\d+)',k);assert m;return (m[1],m[2])
  key=ast.literal_eval(k)
  while isinstance(key,tuple) and len(key)==1:key=key[0]
  return key
 for x in csvrows(files[2]):
  c=x['container'];k=(int(x['snapshot']),c,parse(c,x['coordinate']));i=int(x['variable_index'])
  assert i in vals and (k not in coords or coords[k]==vals[i]);coords[k]=vals[i];seen.add(i)
 recovered=0; recovery_error=0.; duplicate_ids=set()
 if seen!=set(vals):
  assert early and len(vals)-len(seen)==12432
  # Resolve old missing RE index labels with the later verified same-layout same-family model.
  cross=root/'TECH_FULL37_KW08_RE60_70_FROZEN_E_20261118_01/quota_60/relaxed'/folder.parent.name/'relaxed_crossover/variable_coordinates.csv'
  hashes[str(cross)]=sha(cross);separate=folder/'period_1/dispatch.csv';hashes[str(separate)]=sha(separate)
  from datetime import datetime
  separate_values={(1+int((datetime.fromisoformat(x['ts'])-datetime(2013,2,18)).total_seconds()/3600),x['name']):float(x['gen_MW']) for x in csvrows(separate) if x['new'].lower()=='true'}
  assert len(separate_values)==12432
  for row in csvrows(cross):
   c=row['container'];t=int(row['snapshot']);k=parse(c,row['coordinate']);i=int(row['variable_index'])
   if c=='renewable_dispatch':
    assert i not in seen and (t,c,k) not in coords
    error=abs(vals[i]*100-separate_values[t,k]);assert error<1e-7,(i,k,error);recovery_error=max(recovery_error,error);coords[t,c,k]=vals[i];seen.add(i);recovered+=1
   else:assert (t,c,k) in coords and coords[t,c,k]==vals[i]
 assert seen==set(vals)
 def v(t,c,k):return coords[t,c,k]
 caps={k:x for (t,c,k),x in coords.items() if t==0 and c=='renewable_capacity'}
 assert len(caps)==74
 groups=defaultdict(list)
 invs={}; 
 for x in csvrows(raw/'generators.csv'):
  name=x.get('name',x.get('')); 
  if name in caps: invs[name]=x
 assert set(invs)==set(caps)
 av={s:[] for s in caps}
 for i,row in enumerate(csvrows(raw/'generators-p_max_pu.csv')):
  if 1152<=i<1320:
   for name in caps:av[name].append(min(1.,float(row[name])))
 assert all(len(x)==168 for x in av.values())
 d=read(case);net=d['paper_a_network'];regions=net['retained_physical_buses'];idx={x:i for i,x in enumerate(regions)}
 assert len(regions)==37 and net['eliminated_physical_buses']==[] and not net['fixed_sources_in_network'] and not net['fixed_shunts']
 assert 'paper_a_segment_identity' not in d
 B0=np.zeros((37,37));base=d['baseMVA'];assert base==100
 for br in net['branch_primitives']:
  if br['status']!=1:continue
  j,k=idx[br['bus0']],idx[br['bus1']];z=br['v_base_kv']**2/base
  y=-1/complex(br['r_phys']/z,br['x_phys']/z);s=y.imag;h=br['b_siemens']*z/2
  B0[j,j]+=s-h;B0[k,k]+=s-h;B0[j,k]-=s;B0[k,j]-=s
 edges={(i+1,j+1) for i in range(37) for j in range(i+1,37) if B0[i,j]!=0};assert len(edges)==52
 hours=list(range(1,169));tot=defaultdict(list);worst={};rows=Counter()
 def see(name,val,t=0,key=''):
  assert math.isfinite(val)
  val=max(0.,float(val));rows[name]+=1
  if name not in worst or val>worst[name][0]:worst[name]=[val,t,str(key)]
 see('original_bound',bounds);see('integer_residual_blocks',int_err)
 portfolio=defaultdict(float);metric=defaultdict(list);event_overlaps=0;event_pairs=0;overlap_events=[];sun=[];native_exp=[];src_class=defaultdict(list);nsum=defaultdict(list)
 from datetime import datetime,timedelta
 snapshots=[(x.get('name') or x.get('snapshot') or next(iter(x.values()))) for x in csvrows(raw/'snapshots.csv')]
 assert all(datetime.fromisoformat(snapshots[1152+k])==datetime(2013,2,18)+timedelta(hours=k) for k in range(168))
 assert len(d['nw'])==168 and len(regions)==37
 for name,cap in caps.items():
  carrier=invs[name]['carrier'];cat='wind' if carrier in ('onwind','offwind-ac','offwind-dc') else 'PV' if carrier=='solar' else None;assert cat;portfolio[cat+'_added_MW']+=cap
  asset=invs[name];see('new_project_bounds_MW',max(-cap,cap+float(asset['p_nom'])-float(asset['p_nom_max'])),0,name)
  tot['CAPEX'].append(cap*float(price[asset['carrier']]['cost_inv_per_mw']))
 W=np.asarray(read(root/'M2_REGISTER.json')['W']) if method=='M2' else None
 for t in hours:
  sn=d['nw'][str(t)];assert sn['time_elapsed']==1 and sn['baseMVA']==100 and sn['g_min']==1
  bal=defaultdict(float);bal_model=defaultdict(float);b=np.zeros(37);p=np.zeros(37);bps=defaultdict(float)
  buses={x['name']:int(i) for i,x in sn['bus'].items()}
  contrib=defaultdict(float);newex=0.
  for i,x in sn['bus'].items():
   if x['bus_type']==3:see('ref_angle_rad',abs(v(t,'va',int(i))),t,i)
  for name,cap in caps.items():
   asset=invs[name];g=v(t,'renewable_dispatch',name)*base;avail=av[name][t-1];bus=asset['bus']
   p[idx[bus]]+=avail*cap/base;newex+=avail*cap/base;bal[buses[bus]]-=g;see('new_dispatch_envelope_MW',max(-g,g-avail*cap),t,name)
   tot['RE'].append(g);tot['OPEX_gen'].append(g*float(price[asset['carrier']]['marginal_cost_EUR_per_MWh']))
  for x in sn['load'].values():
   demand=base*x['pd'];bal[x['load_bus']]+=demand;tot['load'].append(demand)
  for i,x in sn['branch'].items():
   a,c=x['f_bus'],x['t_bus'];f=v(t,'p',(int(i),a,c))*base;ang=v(t,'va',a)-v(t,'va',c)
   series=(1/complex(x['br_r'],x['br_x'])).imag;see('DCP_Ohm_MW',abs(f+base*series*ang),t,i)
   see('DCP_angle_rad',max(x['angmin']-ang,ang-x['angmax']),t,i);see('branch_thermal_MW',abs(f)-x['rate_a']*base,t,i)
   bal[a]+=f;bal[c]-=f
  for i,x in sn['dcline'].items():
   a,c=x['f_bus'],x['t_bus'];f=v(t,'p_dc',(int(i),a,c))*base;rev=v(t,'p_dc',(int(i),c,a))*base
   assert x['loss0']==x['loss1']==0
   see('DC_loss_MW',abs(f+rev),t,i);see('DC_rating_MW',max(x['pminf']*base-f,f-x['pmaxf']*base,x['pmint']*base-rev,rev-x['pmaxt']*base),t,i);bal[a]+=f;bal[c]+=rev
  for tab in ('gen','storage','ne_storage'):
   for i,x in sn.get(tab,{}).items():
    key=(tab,i);j=int(i);P=x.get('p_block_max_MW');a=v(t,'na_block',key) if P is not None and (t,'na_block',key) in coords else None
    n=v(t,'n_block',key) if a is not None else None;credit=coords.get((t,'paper_a_strength_blocks',key),a)
    if a is not None:
     assert P>0
     see('install_online_blocks',max(x['n0']-n,n-x['nmax'],-a,a-x['a_conn']*n,abs(n-v(1,'n_block',key))),t,key)
     if t==1:
      c=x['carrier'];cat='GFL_BESS' if c=='battery' else 'GFM_BESS' if c=='BESS-GFM' else 'wind' if c in ('onwind','offwind-ac','offwind-dc') else 'PV' if c=='solar' else None
      if cat:
       portfolio[cat+'_baseline_MW']+=x['n0']*P
       portfolio[cat+'_added_MW']+=(n-x['n0'])*P
      tot['CAPEX'].append((n-x['n0'])*P*x['cost_inv_per_mw'])
      if x['nmax']>x['n0']:
       group='gas' if x['carrier'].lower() in ('ccgt','ocgt') else 'bess' if x['carrier'].lower() in ('battery','bess-gfm') else None
       assert group;groups[(x['region_id'],group)].append((n-x['n0'])*P)
     if (t,'paper_a_strength_blocks',key) in coords:see('credit_online_blocks',max(-credit,credit-a),t,key)
     pos=idx[x['region_id']]
     if x['source_class']=='GFL':p[pos]+=P/base*x['mu_fl']*a
     elif x['source_class'] in ('SYN','GFM'):
      assert not x['fixed_strength_already_in_network']
      r=x['r_src'] if x['source_class']=='GFM' else 0.;s=(-1/complex(r,x['x_src'])).imag*x['native_source_MVA']/base
      if 'native_source_kv_referred' in x:s*=(sn['bus'][str(x['gen_bus'] if tab=='gen' else x['storage_bus'])]['base_kv']/x['native_source_kv_referred'])**2
      see('source_stamp_pu',abs(s-x['b_block']),t,key);b[pos]+=s*x['mu_str']*credit;contrib[x['source_class']]+=s*x['mu_str']*credit
    if tab=='gen':
     g=v(t,'pg',j)*base;bal[x['gen_bus']]-=g
     tot['OPEX_gen'].append(g*x['marginal_cost'])
     if x['carrier'] in ('onwind','solar','offwind-ac','offwind-dc'):tot['RE'].append(g)
     if a is not None:
      lo=x.get('p_min_pu',0.);hi=x['a_res'] if x.get('source_class')=='GFL' or 'paper_a_carrier_uc' not in x else x.get('p_max_pu',1.)
      see('gen_power_MW',max(lo*P*a-g,g-hi*P*a),t,key)
     if 'paper_a_carrier_uc' in x:
      su=v(t,'su_block',key);sd=v(t,'sd_block',key);old=v(t-1,'na_block',key) if t>1 else x['na0']
      event_pairs+=1;event_overlaps+=int(su>1e-6 and sd>1e-6)
      if su>1e-6 and sd>1e-6:overlap_events.append(dict(hour=t,key=list(key),su=su,sd=sd,eliminable_blocks=min(su,sd),eliminable_week_cost_EUR2025=P*min(su,sd)*(x['startup_cost_per_mw']+x['shutdown_cost_per_mw'])))
      see('UC_transition_blocks',abs(a-old-su+sd),t,key)
      see('UC_start_stop_bounds_blocks',max(su-(n-old),sd-old,-su,-sd),t,key)
      for name,flag,limit in [('start','su_block',x['min_up_block_time']),('stop','sd_block',x['min_down_block_time'])]:
       see('UC_window_'+name+'_blocks',math.fsum(v(h,flag,key) for h in range(max(1,t-limit+1),t+1))-(a if name=='start' else n-a),t,key)
      tot['OPEX_event'].append((su*x['startup_cost_per_mw']+sd*x['shutdown_cost_per_mw'])*P)
    else:
     sc=v(t,'sc',j)*base;sd=v(t,'sd',j)*base;se=v(t,'se',j)*base;bal[x['storage_bus']]+=sc-sd;tot['OPEX_storage'].append(sd*x['marginal_cost'])
     assert x.get('r',0.)==0.
     bal_model[x['storage_bus']]+=v(t,'ps',j)*base-(sc-sd)
     see('storage_internal_power_MW',abs(v(t,'ps',j)*base-(sc-sd+x.get('p_loss',0.)*base)),t,key)
     if a is None:
      see('native_hydro_power_MW',max(-sc,-sd,sc-x['charge_rating']*base,sd-x['discharge_rating']*base),t,key)
     native=x.get('paper_a_storage_unit');cycles=native['cyclic_state_of_charge'] if native else x.get('paper_a_annual_cyclic',False)
     prev=v(t-1,'se',j)*base if t>1 else v(168,'se',j)*base if cycles else native['state_of_charge_initial_MWh'] if native else x['energy']*base
     eta_c=native['efficiency_store'] if native else x['charge_efficiency'];eta_d=native['efficiency_dispatch'] if native else x['discharge_efficiency'];loss=native['standing_loss'] if native else x.get('self_discharge_rate',0.)
     inflow=native['inflow_MW'] if native else x.get('stationary_energy_inflow',0.)*base;outflow=0. if native else x.get('stationary_energy_outflow',0.)*base;spill=coords.get((t,'paper_a_storage_spill',j),0.)*base
     see('spill_MW',max(-spill,spill-inflow),t,key);see('SOC_recurrence_MWh',abs(se-((1-loss)*prev+inflow-outflow-spill+eta_c*sc-sd/eta_d)),t,key)
     upper=native['max_hours']*native['p_nom_MW'] if a is None else x['e_block']*n*base
     see('SOC_rating_MWh',max(-se,se-upper),t,key)
     if a is not None:
      pump=coords.get((t,'paper_a_pump_blocks',key),a)
      if (t,'paper_a_pump_blocks',key) in coords:
       see('PHS_mode_blocks',credit+pump-a,t,key);see('PHS_minimum_turbine_MW',x['paper_a_full37_online']['strength_minimum_pu']*P*credit-sd,t,key)
      see('storage_power_MW',max(-sc,-sd,sc-(-native['p_min_pu'] if native else 1.)*P*pump,sd-(native['p_max_pu'] if native else 1.)*P*(credit if (t,'paper_a_pump_blocks',key) in coords else a)),t,key)
    selector=x.get('paper_a_full37_online',{})
    if selector.get('mode')=='SELECTIVE_SYN':
     gc=v(t,'paper_a_credited_power',key)*base;g=v(t,'pg',j)*base if tab=='gen' else sd
     maxpu=x['a_res'] if tab=='gen' else x['paper_a_storage_unit']['p_max_pu']
     see('selective_SYN_dispatch_MW',max(credit*P*selector['strength_minimum_pu']-gc,gc-credit*P*maxpu,gc-g,g-gc-(a-credit)*P*maxpu),t,key)
  for busno,netdef in bal.items():
   see('nodal_balance_MW',abs(netdef),t,busno);see('original_KCL_MW',abs(netdef+bal_model[busno]),t,busno)
  B=B0+np.diag(b);M=B-np.diag(p)
  sun.append(newex);native_exp.append(float(p.sum())-newex)
  for c in ('SYN','GFM'):src_class[c].append(contrib[c])
  r=np.asarray(d['paper_a_extension']['full37_specification']['g2_r']);assert (r>0).all() and len(r)==37
  g1=float((M@np.ones(37)).min());g2=float((M@r).min());metric['G1'].append(g1);metric['G2'].append(g2);metric['G0'].append(float(np.linalg.eigvalsh(M)[0]))
  eb=float(np.linalg.eigvalsh(B)[0]);metric['B_min'].append(eb)
  # Passive fixed Laplacian plus shunts is Z. Require actual SPD and inverse positivity for M0.
  if eb>1e-9 and np.max(B-np.diag(np.diag(B)))<=0 and p.min()>=-1e-8:
   inv=np.linalg.solve(B,np.eye(37))
   if inv.min()>=-1e-12:metric['M0'].append(float(1-(inv@p).max()))
  if method=='G1':see('G1_active_row_pu',-g1,t)
  see('exposure_nonnegative_pu',-min(p),t)
  if method=='G3':
   spent=np.zeros(37)
   for e in edges:
    q1=v(t,'G3_edge_q',(e,1));q2=v(t,'G3_edge_q',(e,2));i,j=e[0]-1,e[1]-1
    see('G3_q_nonnegative_pu',max(-q1,-q2),t,e);see('G3_exact_product_pu2',M[i,j]**2-q1*q2,t,e)
    see('G3_historical_polynomial_pu2',(math.sqrt(2.)*M[i,j])**2-2*q1*q2,t,e);spent[i]+=q1;spent[j]+=q2
   see('G3_node_budget_pu',max(spent-M.diagonal()),t)
  if method=='M2':see('M2_row_pu',max(W@p-B.sum(axis=1)),t)
  if method=='G2':see('G2_row_pu',-min(M@np.array(d['paper_a_extension']['full37_specification']['g2_r'])),t)
  if method in ('G0','G3'):
   lam=np.linalg.eigvalsh(M)[0]
   if abs(lam)<=2e-7:
    import mpmath as mp
    mp.mp.dps=55
    lam=min(float(mp.eigsy(mp.matrix([[mp.mpf(float(M[i,j])) for j in ids] for i in ids]),eigvals_only=True)[0]) for island in net['network_islands'] for ids in [[idx[vv] for vv in island]])
   see('G0_matrix_neg_eig_pu',-lam,t)
  if min(np.linalg.eigvalsh(B))>1e-9:
   inv=np.linalg.solve(B,np.eye(37));see('inverse_negative_diagnostic',max(0.,-inv.min()),t)
   if method=='M2':see('M2_certified_M0_burden',np.linalg.solve(B,p).max()-1,t)
 peaks=d['paper_a_extension']['expansion_policy']['peak_load_MW_by_bus']
 for (region,group),a in groups.items():see('joint_expansion_MW',math.fsum(a)-3*peaks[region],1,(region,group))
 sums={k:math.fsum(a) for k,a in tot.items()};cost=sum(sums[k] for k in ('OPEX_gen','OPEX_storage','OPEX_event'));sums.update(raw_week_OPEX=cost,annualized_week_OPEX=cost*8760/168,annualized_total=sums['CAPEX']+cost*8760/168,renewable_share_pct=100*sums['RE']/sums['load'])
 see('weekly_quota_MWh',quota/100*sums['load']-sums['RE'])
 for cat in ('wind','PV','GFL_BESS','GFM_BESS'):portfolio[cat+'_total_MW']=portfolio[cat+'_baseline_MW']+portfolio[cat+'_added_MW']
 tol=1e-7 if method in ('G0','G3') else 1e-6;maxima={k:{'abs':x[0],'t':x[1],'id':x[2],'dimensioned_threshold':tol*(100 if k.endswith(('_MWh','_MW')) else 1),'normalized_to_threshold':x[0]/(tol*(100 if k.endswith(('_MWh','_MW')) else 1))} for k,x in worst.items()}
 failed=[k for k,x in maxima.items() if x['normalized_to_threshold']>1]
 return dict(reviewer='/root/qa_r',method=method,quota_pct=quota,mode=mode,case_sha256=casehash,source_hashes=hashes,original_point_dimensions=len(vals),discrete_domains=discrete,counts=dict(rows),maxima=maxima,failed=failed,physical_point_accepted=not failed,cost_replay=sums,code=code,coordinate_recovery_count=recovered,coordinate_recovery_max_MW=recovery_error,portfolio_MW=dict(portfolio),margins={k:{'min':min(z) if z else None,'defined_hours':len(z),'failed_hours':sum(y < -1e-6 for y in z)} for k,z in metric.items()},source_credit_weekly_pu_hours={k:math.fsum(z) for k,z in src_class.items()},exposure_weekly_pu_hours={'native_online':math.fsum(native_exp),'new_availability':math.fsum(sun)},overlap_events=overlap_events,potential_event_pairs=event_pairs,simultaneous_positive_SU_SD=event_overlaps,units='original native coordinates; M0=1-max(B^-1p), G0=min eig(M), G1=min(M1), G2=min(Mr); diagnostics 1e-6; 100 MVA MW/MWh residual conversions',original_B0_network={'nodes':37,'edges':52,'islands':len(net['network_islands']),'eliminated':len(net['eliminated_physical_buses']),'fixed_shunts':len(net['fixed_shunts']),'active_GFM_source_counting':'each device credit enters one diagonal term once; no GFM in passive network'},oracle_sha256=sha(Path(__file__)))
