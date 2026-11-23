"""Restamp all physical islands and replay B/S/M from original indexed points and primitive data."""
import csv,json,math,sys,os,mmap,re,hashlib
from pathlib import Path
from fractions import Fraction
from collections import defaultdict
from datetime import datetime,timedelta
os.environ['OPENBLAS_NUM_THREADS']='1';os.environ['MKL_NUM_THREADS']='1'
import numpy as np
from importlib.util import spec_from_file_location,module_from_spec
R=Path(__file__).parent;E=R.parent
spec=spec_from_file_location('census',R/'01_event_census.py');imported=module_from_spec(spec);spec.loader.exec_module(imported)
sha,tab=imported.sha,imported.tab
droot=Path('D:/Projekte/Code/pypsatomatpowerx/data/elec_s_37_csv')
assets=E/'TECH_FULL37_KW08_RE70_STRENGTH_COMPARISON_20261118_01/CASES'
base=E/'TECH_FULL37_840H_RE50_GFM_FROZEN_E_20261117_01/AP2_SOURCE_VARIANTS/week_8/derived_case.json'
files=[base,assets/'G2/case.json',assets/'G3/case.json',droot/'generators.csv',droot/'generators-p_max_pu.csv',droot/'snapshots.csv']
hashes=[sha(p) for p in files]
assert hashes[:3]==['c03dfc3cd78d68e0aeb8fb6875a3875e71db5d2c2efd8d680ba1904f95a79cfe','c154322ea868313405ac7be70c541ad87839bbb070ac2fa556f18c1d2547e2d5','1ceb274ab48bf2e4f90783fa881d394c79fb216d311c6bde197c6fe77dbbb15d']
assert hashes[3:]==['20441d5bd67103b90838e728affa0da332e5112dcce532c8119eb5e50116abb8','45336cff93e75ffc9a1a5aae2bc3e8ad8f7054b2f8bcb267d25607c73cc45f46','1dbf7e7d9522f6e43223b21a9e3a4a9a1c9314ef4866897a632c26512d95ddd4']
dec=json.JSONDecoder()
def sections(p):
 with p.open('rb') as f, mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as m:
  def field(k):
   needle=('"'+k+'":').encode();i=m.find(needle)
   assert i>=0
   return dec.raw_decode(m[i+len(needle):i+len(needle)+2**21].decode('latin1'))[0]
  net=field('paper_a_network'); stamps=field('snapshot_ids'); ext=field('full37_specification')
  reg=net['physical_ac_bus_order']; n=len(reg); idx={k:i for i,k in enumerate(reg)}
  assert reg==net['retained_physical_buses'] and not net['eliminated_physical_buses'] and not net['elimination_performed']
  assert not net['fixed_sources_in_network'] and not net['fixed_strength_by_region_pu'] and not net['fixed_shunts']
  Y=np.zeros((n,n),complex); adj={k:set() for k in reg}
  for x in net['branch_primitives']:
   if not x['status']:continue
   a,b=x['bus0'],x['bus1'];i,j=idx[a],idx[b];adj[a].add(b);adj[b].add(a)
   z=x['v_base_kv']**2/100; y=z/complex(x['r_phys'],x['x_phys']);h=1j*x['b_siemens']*z/2
   Y[i,i]+=y+h;Y[j,j]+=y+h;Y[i,j]-=y;Y[j,i]-=y
  islands=[];pending=set(reg)
  while pending:
   group={min(pending)};walk=list(group)
   while walk:
    for k in adj[walk.pop()]-group:group.add(k);walk.append(k)
   pending-=group;islands.append(sorted(group))
  assert sorted(islands)==sorted(map(sorted,net['network_islands']))
  assert all(set(group)&set(net['reference_buses']) for group in islands)
  L=-Y.imag; off=L.copy();np.fill_diagonal(off,0)
  assert np.array_equal(Y,Y.T) and np.max(off)<=0
  res=max(np.max(abs(Y.real-net['Y_positive_real_pu'])),np.max(abs(Y.imag-net['Y_positive_imag_pu'])),np.max(abs(L-net['B0_reference_pu'])),np.max(abs(L-net['L_neg_imag_Y_pu'])))
  assert res<1e-9
  aa={};sources={};coef={};ts={};pkeys={};status=set();classcount=defaultdict(int);maxstamp=0
  pos=m.find(b'"nw":{')+6
  for _ in range(168):
   hdr=re.match(rb'"(\d+)":',m[pos:pos+20]);assert hdr
   t=int(hdr[1]);pos+=hdr.end();sn,nchar=dec.raw_decode(m[pos:pos+2**21].decode('latin1'));pos+=nchar+1
   assert datetime.fromisoformat(stamps[str(t)])==datetime(2013,2,18)+timedelta(hours=t-1) and sn['time_elapsed']==1 and sn['baseMVA']==100 and sn['g_min']==1
   for tabname in ('gen','storage','ne_storage'):
    for k,v in sn[tabname].items():
     if 'p_block_max_MW' not in v:continue
     key=(tabname,k);rg=v['region_id'];j=idx[rg];g=v['source_class'];u=v.get('mu_fl',0)
     co=v['p_block_max_MW']*u/100 if g=='GFL' else 0.;st=0.
     if g in ('GFM','SYN') and v['mu_str']!=0:
      assert not v['fixed_strength_already_in_network']
      z=complex(v.get('r_src',0) if g=='GFM' else 0,v['x_src'])
      st=(v['native_source_MVA']/100)*(-1/z).imag
      if 'native_source_kv_referred' in v: st*=(sn['bus'][str(v['gen_bus'] if tabname=='gen' else v['storage_bus'])]['base_kv']/v['native_source_kv_referred'])**2
      maxstamp=max(maxstamp,abs(st-v['b_block']));st*=v['mu_str']
     if g=='GFL':assert v['b_block']==0
     if t==1:classcount[g]+=1
     event=(v.get('startup_cost_per_mw',0)+v.get('shutdown_cost_per_mw',0))*v['p_block_max_MW']
     data=(j,co,st,event,v['name'],g)
     if key in coef:assert data==coef[key]
     else:coef[key]=data
  assert maxstamp<1e-9
  return reg,L,coef,np.array(ext['g2_r']),dict(islands=islands,eliminated=[],retained=reg,physical_branches=len(net['branch_primitives']),edges=np.count_nonzero(np.triu(off,1)).item() if hasattr(np.count_nonzero(np.triu(off,1)),'item') else int(np.count_nonzero(np.triu(off,1))),Y_L_B0_max_error=float(res),B0_min_eigen=float(np.linalg.eigvalsh(L)[0]),source_stamp_error_pu=float(maxstamp),classes=dict(classcount),domain_flags=net['passive_domain_issues'])
A, B=sections(files[0]),sections(files[1]);assert A[0]==B[0] and np.array_equal(A[1],B[1]) and A[2]==B[2]
areas={x['name']:x['bus'] for x in tab(files[3])}
avail=list(v for i,v in enumerate(tab(files[4])) if 1152<=i<1320);assert len(avail)==168
def test(folder):
 method='G2' if folder.parent.name=='G2' else 'BASE' if 'without_gscr' in folder.parts else 'G1'
 regs,L,dev,r,meta=B if method=='G2' else A
 H=168;n=len(regs); b=np.zeros((H,n));p=np.zeros((H,n));pn=np.zeros_like(p);gfl=np.zeros_like(p)
 raw={int(x['variable_index']):float(x['value']) for x in tab(folder/'full_primal.csv')}
 counts={k:{} for k in ('na_block','paper_a_strength_blocks','su_block','sd_block')};proj={}
 key_re=re.compile(r':(gen|ne_storage|storage),\s*(\d+)')
 for x in tab(folder/'variable_coordinates.csv'):
  name=x['container'];val=raw[int(x['variable_index'])]
  if name=='renewable_capacity':proj[x['coordinate']]=val
  elif name in counts:
   key=key_re.search(x['coordinate']).groups();t=int(x['snapshot'])-1
   counts[name][t,key]=val
 assert len(proj)==74 and len(counts['na_block'])==353*168
 for k,v in proj.items():
  j=regs.index(areas[k]);pn[:,j]+=[min(1,float(row[k]))*v/100 for row in avail]
 for (t,key),v in counts['na_block'].items():
  j,ec,st,ev,name,cls=dev[key];gfl[t,j]+=ec*v
  b[t,j]+=st*counts['paper_a_strength_blocks'].get((t,key),v)
 p=pn+gfl
 simultaneous=[]
 for (t,key),su in counts['su_block'].items():
  sd=counts['sd_block'][t,key];q=min(su,sd)
  if q>1e-6: simultaneous.append(dict(hour=t+1,key=key,name=dev[key][4],su=su,sd=sd,cancellable=q,avoidable_weekly_event_EUR=q*dev[key][3]))
 summary=json.loads((folder/'run_summary.json').read_bytes());cash=sum(v['avoidable_weekly_event_EUR'] for v in simultaneous)
 row=L.sum(axis=1)[None,:]+b-p;g2=(L@r)[None,:]+(b-p)*r
 err=None
 if (folder/'g1_all_bus_hours.csv').is_file():
  err=max(abs(row[int(x['snapshot'])-1,regs.index(x['region'])]-float(x['slack_pu'])) for x in tab(folder/'g1_all_bus_hours.csv'))
  assert err<1e-7,(folder,err)
 eig=[];m0=[];g0=[];inverse=[];ivres=[];alloff=[]
 for t in range(H):
  G=L+np.diag(b[t]);eig.append(np.linalg.eigvalsh(G)[0]);g0.append(np.linalg.eigvalsh(G-np.diag(p[t]))[0])
  if eig[-1]>1e-8:
   Z=np.linalg.solve(G,np.eye(n));inverse.append(np.min(Z));ivres.append(np.max(abs(G@Z-np.eye(n))));m0.append(float(np.max(Z@p[t]-1)))
  else:m0.append(None)
 if method=='G2' or method=='G1':
  assert min(eig)>0 and min(inverse)>=-1e-10
  active=g2 if method=='G2' else row
  assert active.min()>=-1e-6,(folder,float(active.min()))
 return dict(method=method,physical_G1_export_error_pu=err,original_columns=len(raw),hours=168,regions=n,min_B_eigen_pu=min(eig),max_B_eigen_min_pu=max(eig),B_PD_hours=sum(x>1e-8 for x in eig),inverse_most_negative=min(inverse,default=None),inverse_worst_residual=max(ivres,default=None),minimum_new_available_pu=float(pn.min()),maximum_new_available_pu=float(pn.max()),minimum_composite_pu=float(p.min()),G0_negative_hours=sum(x< -1e-6 for x in g0),G1_negative_hours=int((row.min(axis=1)<-1e-6).sum()),G2_negative_hours=int((g2.min(axis=1)<-1e-6).sum()),M0_negative_hours_on_valid_domain=sum(x is not None and x>1e-6 for x in m0),M0_undefined_hours=sum(x is None for x in m0),simultaneous=simultaneous,avoidable_raw_weekly_EUR=cash,avoidable_annualized_EUR=cash*8760/168,archive_summary_sha256=sha(folder/'run_summary.json'))
out={}
for f in imported.getdirs():
 key=str(f.relative_to(E));out[key]=test(f);print(key,out[key]['simultaneous'],out[key]['min_B_eigen_pu'],flush=True)
r={'reviewer':'/root/math_r','execution':[sys.executable,str(Path(__file__))],'script_sha256':sha(Path(__file__)),'input_sha256':dict(zip(map(str,files),hashes)),'BASE_G1':A[-1],'G2':B[-1],'cases':out,'exit':0}
def convert(x):
 return x.item() if isinstance(x,np.generic) else str(x)
(R/'01_PHYSICAL_DOMAIN_AND_EVENT_REPLAY.json').write_text(json.dumps(r,indent=2,default=convert),encoding='utf8')

