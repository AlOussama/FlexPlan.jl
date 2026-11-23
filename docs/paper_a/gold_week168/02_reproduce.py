from pathlib import Path
import json,csv,os,sys,traceback,hashlib
sys.dont_write_bytecode=True
import importlib.util
code_root=Path(__file__).resolve().parent
out=Path(os.environ.get('PAPER_A_F2_OUTPUT_ROOT',code_root));out.mkdir(parents=True,exist_ok=True)
root=Path(os.environ.get('PAPER_A_F2_INPUT_ROOT',code_root.parent))
sp=importlib.util.spec_from_file_location('case_replay',code_root/'02_original_case.py');reader=importlib.util.module_from_spec(sp);sp.loader.exec_module(reader)
def sha(q):
 with q.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def read(q):return json.loads(q.read_bytes())
def paths():
 hist=root/'TECH_FULL37_840H_RE50_GFM_FROZEN_E_20261117_01/AP2_SOURCE_VARIANTS/week_8/derived_case.json'
 for quota in [50,60,70]:
  for variant,folder in [('BASE','without_gscr'),('G1','with_gscr')]:
   for mode,sub in [('LP','relaxed_crossover'),('MILP','integer')]:
    if quota==50: base=root/('TECH_FULL37_KW08_RE50_GFM_FROZEN_E_'+('MIP_' if mode=='MILP' else '')+'20261118_01')
    else:base=root/'TECH_FULL37_KW08_RE60_70_FROZEN_E_20261118_01'/f'quota_{quota}'/('relaxed' if mode=='LP' else 'integer')
    yield (quota,variant,mode,base/folder/sub,hist)
 p=root/'TECH_FULL37_KW08_RE70_STRENGTH_COMPARISON_20261118_01'
 for mode,f in [('LP',p/'G2/relaxed'),('MILP',root/'TECH_FULL37_KW08_RE70_SEQUENTIAL_CONDITIONED_20261120_01/03_G2_MILP/G2/integer')]:
  yield 70,'G2',mode,f,p/'CASES/G2/case.json'
part=out/'02_final_rows';part.mkdir(exist_ok=True)
if __name__=='__main__':
 failed=False
 for q,m,mode,f,c in paths():
  rowid=f'WK08-{q}-{m}-{mode}';target=part/(rowid+'.json')
  if len(sys.argv)>1 and rowid not in sys.argv[1:]:continue
  if target.exists():continue
  try:
   v=reader.run(f,c,m,'relaxed' if mode=='LP' else 'integer')
   v['row_id']=rowid;v['folder']=str(f);v['summary_sha256']=sha(f/'run_summary.json');v['solver_log_sha256']=sha(f/'gurobi.log')
   with target.open('x') as h:json.dump(v,h,allow_nan=False,indent=2);h.write('\n')
   print(rowid,v['failed'],v['simultaneous_positive_SU_SD'],sha(target),flush=True)
  except Exception:traceback.print_exc();failed=True
 sys.exit(int(failed))

