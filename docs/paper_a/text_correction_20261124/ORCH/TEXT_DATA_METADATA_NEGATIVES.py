"""Verify published technical erratum and adversarial G3 metadata on copies of the compact CSV only."""
import argparse,csv,json,hashlib,io,re,runpy,subprocess,tempfile
from pathlib import Path
from decimal import Decimal as D, ROUND_FLOOR, ROUND_CEILING
cli=argparse.ArgumentParser();cli.add_argument('--consumer',type=Path,required=True);cli.add_argument('--old',required=True);cli.add_argument('--new',required=True);cli.add_argument('--original-paper',type=Path,required=True);cli.add_argument('--paper',type=Path,required=True);cli.add_argument('--out',type=Path,required=True);cfg=cli.parse_args()
def gh(rev,path):return subprocess.check_output(['git','-C',str(cfg.consumer),'show',rev+':docs/paper_a/gold_week168/'+path])
def digest(b):return hashlib.sha256(b).hexdigest()
fn='PAPER_A_SINGLE_BUNDLE_F1_F4_CLOSEOUT_FINAL_HANDOFF.md'
old,new=[gh(rev,fn).decode('utf8') for rev in (cfg.old,cfg.new)]
assert '12.0.3 lieferte alle 14 Kernpunkte' in old and 'Gurobi 12.0.3 lieferte 13 Kernpunkte' in new and 'Gurobi 13.0.3' in new
bounds={row['row_id']:row for row in csv.DictReader(io.StringIO(gh(cfg.old,'02_OBJECTIVE_AND_SOLVER_BOUNDS.csv').decode('utf-8-sig')))}
def rows(s):return [[x.strip() for x in l.split('|')][1:-1] for l in s.splitlines() if '| LP |' in l or '| MILP |' in l]
audit=[]
for o,n in zip(rows(old),rows(new),strict=True):
 k='WK08-'+n[0].split()[0]+'-'+n[1]+'-'+n[2]
 for i,col,mode in [(5,'numeric_lb_EUR2025',ROUND_FLOOR),(6,'numeric_ub_EUR2025',ROUND_CEILING)]:
  exact=D(bounds[k][col])/D(10**9);expected=exact.quantize(D('.000001'),rounding=mode)
  assert D(n[i].replace(',','.'))==expected
  audit.append(dict(row_id=k,field=col,baseline=o[i],corrected=n[i],exact_billion=str(exact)))
assert len(audit)==28 and sum(x['baseline']!=x['corrected'] for x in audit)==13
mut=[]
for dirname in [cfg.original_paper,cfg.paper]:
 method=runpy.run_path(str(dirname/'04_g3_table.py'))['write_table']
 with (dirname/'04_g3_attempts.csv').open(encoding='utf-8-sig') as h:original=list(csv.DictReader(h))
 for short in (False,True):
  rowsg=[dict(row) for row in original]
  tar=next(row for row in rowsg if not row['distance'])
  tar['code']='0754707'+'0'*33 if short else '1234567'+'0'*33
  with tempfile.TemporaryDirectory(dir=cfg.out.parent) as d:
   path=Path(d)
   (path/'04_additional_methods.csv').write_bytes((dirname/'04_additional_methods.csv').read_bytes())
   with (path/'04_g3_attempts.csv').open('w',encoding='utf8',newline='') as fh:
    wr=csv.DictWriter(fh,fieldnames=list(tar));wr.writeheader();wr.writerows(rowsg)
   try:method(path);rejected=False
   except ValueError:rejected=True
   assert rejected==(dirname==cfg.paper),(dirname,short)
   mut.append(dict(generator_sha256=digest((dirname/'04_g3_table.py').read_bytes()),test='abbreviated revision collision' if short else 'unknown revision without numerical field',rejected=rejected))
out=dict(reviewer='/root DATA-R',old_commit=cfg.old,corrected_commit=cfg.new,old_sha256=digest(old.encode()),new_sha256=digest(new.encode()),solver_provenance_contradiction_fixed=True,display_cells=audit,baseline_inward_cells=13,corrected_inward_cells=0,negative_controls=mut,script_sha256=digest(Path(__file__).read_bytes()),exit=0)
cfg.out.write_text(json.dumps(out,indent=2)+'\n',encoding='utf8');print('28 endpoint checks; 2 known baseline false accepts, both rejected by corrected generator')
