"""Complete archived JuMP rows, with the original affine, cone and bound operands."""
from pathlib import Path
import collections,csv,datetime,hashlib,importlib,json,math,os,sys
import numpy as np
from scipy.sparse import csr_matrix
sys.dont_write_bytecode=True
from importlib.util import spec_from_file_location,module_from_spec
code=Path(__file__).resolve().parent;out=Path(os.environ.get('PAPER_A_F2_OUTPUT_ROOT',code));base=Path(os.environ.get('PAPER_A_F2_INPUT_ROOT',code.parent))
sp=spec_from_file_location('batch',code/'02_reproduce.py');batch=module_from_spec(sp);sp.loader.exec_module(batch)
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def read(p):return json.loads(p.read_bytes())
def rows(p):
 with p.open(encoding='utf-8-sig',newline='') as f:yield from csv.DictReader(f)
gref=base/'TECH_FULL37_KW08_RE70_G3_GUROBI_DICT_20261120_02/G3/relaxed/variable_coordinates.csv'
d=base/'G3_NUMERIC_01_EQUIVALENT_CONDITIONING_20261120_01/ANALYSIS/original_and_scaled_constraints.jsonl'
assert sha(d)=='dfe21bd9f7ad4e771689d58c01711a7ab14be70bf15c5c97c9f5cc171f0a96fd'
key=lambda z:(z['snapshot'],z['container'],z['coordinate'])
ids={key(z):int(z['variable_index']) for z in rows(gref)};assert set(ids.values())==set(range(1,328868))
cases=[(f'WK08-{q}-{m}-{mode}',f,q) for q,m,mode,f,c in batch.paths()]
seq=base/'TECH_FULL37_KW08_RE70_SEQUENTIAL_CONDITIONED_20261120_01'
for k,f in [('G3-19',base/'TECH_FULL37_KW08_RE70_STRENGTH_COMPARISON_RESTART_20261119_01/G3/relaxed'),('G3-20-A',seq/'01_G3_SOCP/G3/relaxed'),('G3-20-B',seq/'02_G3_SOCP_BINARY_MILLION/G3/relaxed')]:cases.append((k,f,70))
cases.append(('G2-G3-WITNESS',seq/'03_G2_MILP/INDEPENDENT_REVIEW',70))
n=len(cases);X=np.zeros((328868,n));hashes={str(x):sha(x) for x in (gref,d)};mapper={};result={}
for j,(label,f,q) in enumerate(cases):
 if label=='G2-G3-WITNESS':
  v=f/'G2_MILP_plus_G3_witness_reference_original_values.csv';hashes[str(v)]=sha(v)
  seen=set()
  for z in rows(v):
   i=int(z['original_index']);assert i not in seen;X[i,j]=float(z['value']);seen.add(i)
  assert len(seen)==328867;continue
 vec=f/'full_primal.csv';coord=f/'variable_coordinates.csv';hashes[str(vec)]=sha(vec);hashes[str(coord)]=sha(coord);vs={int(z['variable_index']):float(z['value']) for z in rows(vec)}
 m={};rev={}
 def add(i,a):
  if i in m:assert m[i]==a
  else:assert a not in rev;m[i]=a;rev[a]=i
 for z in rows(coord):add(int(z['variable_index']),ids[key(z)])
 if len(m)!=len(vs):
  assert label in ('WK08-50-BASE-LP','WK08-50-G1-LP')
  c=base/'TECH_FULL37_KW08_RE60_70_FROZEN_E_20261118_01/quota_60/relaxed'/f.parent.name/'relaxed_crossover/variable_coordinates.csv';hashes[str(c)]=sha(c)
  for z in rows(c):add(int(z['variable_index']),ids[key(z)])
 assert set(m)==set(vs) and set(rev)==set(range(1,len(vs)+1))
 for i,a in m.items():X[a,j]=vs[i]
 mapper[label]={'bijective_map':len(m),'permuted_original_indices':sum(i!=a for i,a in m.items())}
 assert np.isfinite(X[:,j]).all()
N=14;maximum=np.zeros(n);mq=np.zeros(n);over=np.zeros(n,dtype=int);tested=np.zeros(n,dtype=int);mx_common=np.zeros(n);worst=[None]*n;type_stats=collections.Counter()
threshold=np.array([1e-6]*N+[1e-7]*(n-N))
by_type={};max_source=collections.defaultdict(int);allg=set();gtagged=set();qbounds=0;quota_seen=0
def track(v,mask,meta,tag):
 global maximum,over,tested,mx_common
 arr=np.maximum(v,0);arr=np.where(mask,arr,0.)
 over[:]+=np.sum(arr>threshold[None,:],axis=0);tested[:]+=np.sum(mask,axis=0)
 topl=arr.argmax(axis=0);peak=arr[topl,np.arange(n)]
 if tag=='common':mx_common=np.maximum(mx_common,peak)
 for j in np.flatnonzero(peak>maximum):worst[j]=meta[topl[j]]
 maximum[:]=np.maximum(maximum,peak);by_type[tag]=np.maximum(by_type.get(tag,np.zeros(n)),peak)
def apply_batch(entries):
 if not entries:return
 ptr=[0];idx=[];coef=[];cons=[];lo=[];high=[];active=[];names=[];tags=[]
 for typ,i,f,s,tag in entries:
  idx.extend(int(k) for k,c in f['terms']);coef.extend(float(c) for k,c in f['terms']);ptr.append(len(idx));cons.append(f['constant']);names.append([typ,i]);tags.append(tag)
  sense=s['kind'];lo.append(s.get('lower',s.get('rhs',-np.inf)) if sense in ('ge','eq','interval') else -np.inf);high.append(s.get('upper',s.get('rhs',np.inf)) if sense in ('le','eq','interval') else np.inf);active.append([tag=='common']*N+[True]*(n-N))
 A=csr_matrix((coef,idx,ptr),shape=(len(cons),X.shape[0]));y=A@X+np.array(cons)[:,None];L=np.array(lo)[:,None];H=np.array(high)[:,None]
 for i,t in enumerate(tags):
  if t=='quota':
   active[i]=[True]*n
   # Preserve native RHS at 70%. Other shares use actual hourly demand, verified in physical replay.
   pass
 err=np.maximum(L-y,y-H)
 for i,t in enumerate(tags):
  if t=='quota':
   assert names[i][1]==69889
   for j,(label,_,q) in enumerate(cases):
    rhs=L[i,0] if q==70 else L[i,0]*q/70.
    # Numerical guard uses compensated sum for the 29,064 nonnegative dispatch terms.
    f=entries[i][2]; yy=math.fsum([float(f['constant'])]+[X[int(a),j]*float(v) for a,v in f['terms']]);err[i,j]=rhs-yy
 for t in set(tags):
  test=np.array([x==t for x in tags]);track(err[test,:],np.array(active)[test,:],[a for a,use in zip(names,test) if use],t)
buf=[]
with d.open() as inp:
 for ln in inp:
  item=json.loads(ln);s=item['original_set'];k=s['kind'];i=item['original_constraint_index'];f=item['original_function'];typ=item['original_type'];type_stats[k]+=1
  if k=='rsoc':
   v=np.array([sum((float(c)*X[int(a)] for a,c in fun['terms']),np.full(n,fun['constant'],dtype='float64')) for fun in f]);u,w,z=v;scalar=(u+w)/math.sqrt(2.);nn=np.hypot((u-w)/math.sqrt(2.),z)
   dst=np.where(nn<=scalar,0.,np.where(nn<=-scalar,np.hypot(scalar,nn),(nn-scalar)/math.sqrt(2.)));pol=np.maximum.reduce([np.zeros(n),-u,-w,z*z-2*u*w]);mq[N:]=np.maximum(mq[N:],pol[N:]);track(dst[None,:],np.array([[False]*N+[True]*(n-N)]),[[typ,i]],'G3_cone');continue
  isq=any(a>311395 for a,c in f['terms']);tag='common'
  if item['variable_bound'] and isq:tag='G3_q_bound';qbounds+=1
  elif not item['variable_bound'] and k=='ge' and 63673<=i<=69888:
   tag='G3_node';allg.add(i)
   if isq:gtagged.add(i)
  elif not item['variable_bound'] and k=='ge' and i==69889:tag='quota';assert len(f['terms'])==29064;quota_seen+=1
  else:assert not isq
  buf.append((typ,i,f,s,tag))
  if len(buf)==4000:apply_batch(buf);buf=[]
apply_batch(buf)
assert sum(type_stats.values())==756257 and type_stats['rsoc']==8736 and len(allg)==6216 and len(gtagged)==5712 and qbounds==17472 and quota_seen==1
for j,(label,f,q) in enumerate(cases):
 result[label]=dict(all_algebraic_rows_evaluated=int(tested[j]),max_abs_original_row=float(maximum[j]),exception_row=worst[j],violations_over_original_tolerance=int(over[j]),tolerance=float(threshold[j]),max_rsoc_polynomial=float(mq[j]) if j>=N else None,max_by_row_family={k:float(v[j]) for k,v in by_type.items() if j>=N or k in ['common','quota']},coordinate_binding=mapper.get(label,'archived full 328867-vector witness'),scope='Common native-model coefficient dump plus original quota; active G1/G2 mathematical rows and integrality separately tested from primary case.' if j<N else 'All 756257 native G3 row distances including bounds and cones.')
 print(label,result[label]['all_algebraic_rows_evaluated'],result[label]['max_abs_original_row'],result[label]['violations_over_original_tolerance'])
res=dict(reviewer='/root/qa_r',role='independent sparse original-row replay',source_hashes=hashes,case_ids=[v[0] for v in cases],results=result,script_sha256=sha(Path(__file__)),source_identity_from='Historical G3 dump; independent 1-1 physical coordinate remap, nonstrength rows determined by complete typed node span, q bounds and cone domains. 3 isolated bus rows per hour are included in G3 strength rows. Solver not called.',nonstrength_rows=int(tested[0]),total_g3_rows=int(tested[-1]))
p=out/'02_COMPLETE_ALGEBRAIC_ROWS.json';p.write_text(json.dumps(res,indent=2,allow_nan=False)+'\n')

