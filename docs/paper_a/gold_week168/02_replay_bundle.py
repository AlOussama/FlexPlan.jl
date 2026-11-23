"""Reproduce all 14 KW8 core rows and four reference checks into a fresh output directory."""
import argparse,hashlib,json,os,subprocess,sys
from pathlib import Path
code=Path(__file__).resolve().parent
cli=argparse.ArgumentParser(description=__doc__);cli.add_argument('--input-root',type=Path,required=True);cli.add_argument('--producer-root',type=Path,required=True);cli.add_argument('--output-root',type=Path,required=True);cli.add_argument('--intake',type=Path,default=code/'00_INPUT_AND_RUNTIME_INTAKE.json')
a=cli.parse_args();dest=a.output_root.resolve();dest.mkdir(parents=True,exist_ok=True)
if list(dest.iterdir()):raise SystemExit('Use an empty or new --output-root to preserve existing evidence.')
def sha(p):
 with p.open('rb') as h:return hashlib.file_digest(h,'sha256').hexdigest()
env=dict(os.environ,PAPER_A_F2_INPUT_ROOT=str(a.input_root.resolve()),PAPER_A_F2_PRODUCER_ROOT=str(a.producer_root.resolve()),PAPER_A_F2_OUTPUT_ROOT=str(dest),PAPER_A_F2_INTAKE=str(a.intake.resolve()),OPENBLAS_NUM_THREADS='1',PYTHONDONTWRITEBYTECODE='1',PYTHONUNBUFFERED='1')
steps=[('02_reproduce.py','02_replay_final.log'),('02_replay_original_rows.py','02_original_rows.log'),('02_replay_legacy_coordinates.py','02_re50_coordinates.log'),('02_freeze.py','02_freeze.log')]
stages=[]
for prog,log in steps:
 args=[sys.executable,str(code/prog)]
 with (dest/log).open('x',encoding='utf8',newline='\n') as f:
  with subprocess.Popen(args,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8',errors='replace') as proc:
   for line in proc.stdout:f.write(line);f.flush();print(line.rstrip(),flush=True)
   rc=proc.wait()
 stages.append(dict(command=args,script_sha256=sha(code/prog),exit=rc,log=log,log_sha256=sha(dest/log)))
 if rc:break
out=dict(stages=stages,entry_sha256=sha(Path(__file__)),entry_argv=[sys.executable,*sys.argv],exit=rc)
with (dest/'02_REPLAY_COMMAND_RECEIPT.json').open('x') as h:json.dump(out,h,indent=2);h.write('\n')
sys.exit(rc)

