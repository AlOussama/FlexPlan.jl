"""Reviewer command recorder. Outputs must be fresh and outside the checkout."""
from pathlib import Path
import datetime, json, os, subprocess, sys
W=Path(__file__).resolve().parents[3]
R=Path('D:/Downloads/A37_B1_REAUDIT_20261023')
PY=sys.executable
def run(name,args):
    log=R/(name+'.log')
    assert not log.exists(), log
    start=datetime.datetime.now(datetime.timezone.utc).isoformat()
    with log.open('w',encoding='utf-8') as stream:
        p=subprocess.run(list(map(str,args)),cwd=W,stdout=stream,stderr=subprocess.STDOUT,
                         env=dict(os.environ,JULIA_NUM_THREADS='1'))
    record=dict(name=name,args=list(map(str,args)),cwd=str(W),start_utc=start,
                end_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),exitcode=p.returncode)
    (R/(name+'.command.json')).write_text(json.dumps(record,indent=2))
    print(name,p.returncode,flush=True)
    return p.returncode
def jl(name,script,*args):
    return run(name,['julia','+1.10.11','--startup-file=no','--project='+str(W),script,*args])
if __name__=='__main__':
    mode=sys.argv[1]; V=R/'validation'; A=W/'reports/a3_6/reaudit_20261021'
    if mode in ('regression','exact'):
        run(mode,[PY,A/'run_suite.py',W,V,mode])
    elif mode=='matrix':
        jl('matrix',W/'scripts/paper_a/qualify_native_g3.jl',W,R/'matrix',V/'prior')
        run('submitted_oracle',[PY,W/'scripts/paper_a/verify_native_g3.py',R/'matrix',V/'prior'])
    elif mode=='guards': jl('native_guards',W/'test/paper_a_native_g3_solver.jl')
    elif mode=='exports':
        jl('fresh_models',W/'reports/a3_6/b1_opt_20261020/model_inclusion.jl',W,V/'fresh_models')
        jl('fresh_objectives',W/'reports/a3_6/b1_opt_20261020/objective_snapshots.jl',W,V/'fresh_objective_snapshots',V/'prior')
        run('compare_fresh',[PY,A/'compare_fresh.py',W,V])
    else: raise ValueError(mode)
