"""Compare rounded prose, directed bounds and plotted data series with F2. No solver."""
from pathlib import Path
from decimal import Decimal as D, ROUND_FLOOR, ROUND_CEILING, ROUND_HALF_UP
import argparse,csv,hashlib,sys,json,re,importlib.util
import numpy as np
parser=argparse.ArgumentParser()
parser.add_argument('--paper',type=Path,required=True);parser.add_argument('--evidence',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
a=parser.parse_args();paper=a.paper
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def tbl(n):
 with (a.evidence/n).open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
points={r['row_id']:r for r in tbl('02_FINAL_WEEK168_RESULT_MATRIX.csv')};bs={r['row_id']:r for r in tbl('02_OBJECTIVE_AND_SOLVER_BOUNDS.csv')}
def p(m,q,t):return points[f'WK08-{q}-{m}-{t}']
def b(m,q,t):return bs[f'WK08-{q}-{m}-{t}']
checks=[]
def verify(key,v,exp):
 if isinstance(exp,np.ndarray):ok=np.allclose(v,exp,rtol=1e-14,atol=1e-14); v=np.asarray(v).tolist();exp=exp.tolist()
 else:ok=v==exp
 if not ok:raise AssertionError((key,v,exp))
 checks.append(dict(subject=key,expected=exp))
def near(x,places,rounding=ROUND_HALF_UP):
 return str(D(str(x)).quantize(D(1).scaleb(-places),rounding=rounding))
def money(row,key):return D(row[key+'_EUR2025'])
def tokens(n):return (paper/n).read_text(encoding='utf8')
result=tokens('04_results.tex')
def line(text,substring):return next(t for t in text.splitlines() if substring in t)
def numbers(s):return re.findall(r'(?<![A-Za-z])\b\d+(?:,\d{3})*(?:\.\d+)?\b',s)
g=p('G2',70,'MILP'); billion=D(10**9);million=D(10**6)
lo=money(b('G1',70,'MILP'),'numeric_lb')-money(b('BASE',70,'MILP'),'numeric_ub');hi=money(b('G1',70,'MILP'),'numeric_ub')-money(b('BASE',70,'MILP'),'numeric_lb')
ab=tokens('04_result_abstract.tex');con=tokens('04_result_conclusion.tex')
for term in [near(lo/billion,2,ROUND_FLOOR),near(hi/billion,2,ROUND_CEILING),g['G1_failed_hours']]:verify('abstract printed '+term,term in numbers(ab),True)
diff=(money(b('G1',70,'MILP'),'numeric_ub')-money(b('G2',70,'MILP'),'numeric_ub'))/million
for term in [near(diff,1),g['G1_failed_hours'],'168']:verify('conclusion printed '+term,term in numbers(con),True)
cs=line(result,'annualized capital');vals=[near(money(g,'CAPEX')/billion,3),near(money(g,'raw_week_OPEX')/million,2),near(money(g,'annualized_week_OPEX')/billion,3),near(D(g['actual_RE_share_pct']),3)]
verify('70% G2 cost and quota prose',[i for i in numbers(cs) if '.' in i],vals)
els=line(result,'battery additions are');pairs=re.findall(r'(\d+\.\d+)/(\d+\.\d+) GW \((BASE|G1|G2)\)',els)
verify('portfolio prose pair count',len(pairs),6)
for i,(first,second,m) in enumerate(pairs):
 cols=['GFL_BESS','GFM_BESS'] if i<3 else ['wind','PV']
 for calc,col in zip([first,second],cols):
  val=D(p(m,70,'MILP')[col+'_added_MW'])/1000
  verify(f'{m} {col} prose rounding',abs(D(calc)-val)<=D('.005'),True)
ev=line(result,'concurrent positive');verify('thermal overlap counts',re.findall(r'They have (\d+) and (\d+)',ev)[0],(p('BASE',50,'MILP')['SU_SD_positive_overlaps'],p('BASE',60,'MILP')['SU_SD_positive_overlaps']))
for q in (50,60):
 price=p('BASE',q,'MILP')['avoidable_overlap_week_EUR2025'];verify(f'{q}% weekly reducible event charge',f'{D(price):,.2f}' in ev,True)
verify('G2 M0 defined/failed, inactive G1 failed',re.search(r'G1 test in (\d+) hours and M0 in (\d+) of (\d+)',result).groups(),(g['G1_failed_hours'],g['M0_failed_hours'],g['M0_defined_hours']))
verify('G2 active fails',re.search(r'active scaled certificate fails in (\d+)',result).group(1),g['G2_failed_hours'])
verify('BASE eligible source rows',[r['row_id'] for r in points.values() if r['model']=='BASE' and int(r['M0_defined_hours'])>0],['WK08-50-BASE-LP'])
verify('BASE defined/failed prose',re.search(r'\((\d+) of 168\); (\d+) fail',result).groups(),(p('BASE',50,'LP')['M0_defined_hours'],p('BASE',50,'LP')['M0_failed_hours']))
spec=importlib.util.spec_from_file_location('paper_plot',paper/'04_build_results.py');gen=importlib.util.module_from_spec(spec);spec.loader.exec_module(gen)
models={(x['model'],int(x['quota_pct']),x['integrality']):x for x in points.values()};bounds={(x['model'],int(x['quota_pct']),x['integrality']):x for x in bs.values()}
PANEL=[('BASE',50),('G1',50),('BASE',60),('G1',60),('BASE',70),('G1',70),('G2',70)]
pdf_inputs={}
def capture(fig,name):
 if name=='04_fig_cost.pdf':
  for ax,q in zip(fig.axes,(50,60,70),strict=True):
   names=[m for m,quota in PANEL if q==quota];verify(f'quota {q} x labels',[t.get_text() for t in ax.get_xticklabels()],names)
   for i,m in enumerate(names):
    lo,hi,lp=[float(b(m,q,t)[col])/1e9 for t,col in [('MILP','numeric_lb_EUR2025'),('MILP','numeric_ub_EUR2025'),('LP','numeric_lb_EUR2025')]]
    for k,exp in enumerate(([lo,hi],[lo],[hi],[lp])):verify(f'{m}/{q} cost artist {k}',ax.lines[i*4+k].get_ydata(),np.array(exp))
 elif name=='04_fig_portfolio.pdf':
  for ax,keys in zip(fig.axes,[['GFL_BESS','GFM_BESS'],['wind','PV']],strict=True):
   for key,container in zip(keys,ax.containers,strict=True):verify('GW bars '+key,[bar.get_width() for bar in container.patches],np.array([float(p(m,q,'MILP')[key+'_added_MW'])/1000 for m,q in PANEL]))
 elif name=='04_fig_diagnostics.pdf':
  ax=fig.axes[0];arr=np.ma.asarray(ax.images[0].get_array());txt={tuple(t.get_position()):t.get_text() for t in ax.texts}
  for i,(m,q,t) in enumerate([(m,q,t) for m,q in PANEL for t in ('LP','MILP')]):
   r=p(m,q,t)
   for j,k in enumerate(['G1','G2','G0','M0']):
    f=int(r[k+'_failed_hours']);d=int(r[k+'_defined_hours']);label=str(f) if j<3 else f'{f}/{d}' if d else 'n/a'
    verify(f'{m} {q} {t} {k} cell annotation',txt[j,i],label)
    if d:verify(f'{m} {q} {t} {k} cell color value',int(arr[i,j]),f)
    else:verify(f'{m} {q} {t} {k} masked',bool(np.ma.getmaskarray(arr)[i,j]),True)
 else:raise ValueError(name)
 pdf_inputs[name]=sha(paper/name);gen.plt.close(fig)
gen.save=capture;gen.plot_style();gen.plot_intervals(models,bounds);gen.plot_portfolios(models);gen.plot_diagnostics(models)
out=dict(reviewer='/root DATA-R',source_sha256={f:sha(paper/f) for f in ('04_results.tex','04_result_abstract.tex','04_result_conclusion.tex','04_build_results.py')},code_sha256=sha(Path(__file__)),checked_figure_pdf_sha256=pdf_inputs,checks=checks,exit=0)
a.output.write_text(json.dumps(out,indent=2)+'\n',encoding='utf8');print(len(checks),'independent quantitative prose/artist checks')
