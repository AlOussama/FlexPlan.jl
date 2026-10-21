"""Execute reviewed existing tools in fresh directories, preserving every log."""
from pathlib import Path
import datetime, json, shutil, subprocess, sys, zipfile
W=Path(sys.argv[1]).resolve(); R=Path(sys.argv[2]).resolve(); mode=sys.argv[3]
A=W/'reports/a3_6/b1_opt_20261020'; N=W/'reports/a3_6/reaudit_20261021'; P=R/'prior'
records=[]
def run(name,args):
    start=datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (R/(name+'.log')).open('w',encoding='utf-8') as out:
        proc=subprocess.run(list(map(str,args)),cwd=W,stdout=out,stderr=subprocess.STDOUT)
    records.append({'id':name,'args':list(map(str,args)),'cwd':str(W),'started_utc':start,'ended_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':proc.returncode})
    (R/('execution_'+mode+'.json')).write_text(json.dumps(records,indent=2),encoding='utf-8')
    print(name,proc.returncode,flush=True)
    return proc.returncode
def jl(name,script,*args): return run(name,['julia','+1.10.11','--startup-file=no','--project='+str(W),script,*args])
if mode=='exact':
    run('existing_exact_verifier',[sys.executable,A/'verify_exact_certificates.py',P])
    run('native_extension',[sys.executable,A/'verify_native_exact_extension.py',P])
    C=R/'cost_reconstruction'; C.mkdir()
    for folder in ['lp_bounds','exact_primals']: shutil.copytree(P/folder,C/folder)
    run('raw_objective_reconstruction',[sys.executable,A/'raw_cost_objective.py',C,W])
    run('independent_certificates',[sys.executable,N/'independent_check.py',W,R])
elif mode=='regression':
    V=R/'validation'; V.mkdir(); shutil.copytree(W/'test',V/'test')
    jl('full_regression',V/'test/runtests.jl')
    H=R/'historical'; shutil.copytree(W/'reports/ap3_runs/20261020_macro',H)
    for p in H.rglob('*.zip'):
        with zipfile.ZipFile(p) as z: z.extractall(p.parent)
    jl('saved_evidence',W/'test/run_paper_a_ap3_evidence.jl',H)
    jl('moi_guards',P/'tools/independent_jump_moi_audit.jl',R/'moi_guards')
    jl('domain_mutations',P/'tools/independent_domain_mutations.jl',R,W)
elif mode=='solver':
    jl('minimal_filter',N/'solver_review.jl',W,R)
    jl('stress_matrix',A/'fix_stress_matrix.jl',W,R/'fresh_stress')
    jl('fresh_model_exports',A/'model_inclusion.jl',W,R/'fresh_models')
    jl('fresh_objective_snapshots',A/'objective_snapshots.jl',W,R/'fresh_objective_snapshots',P)
    run('fresh_export_comparison',[sys.executable,N/'compare_fresh.py',W,R])
elif mode=='remaining_filter':
    jl('remaining_filter',N/'remaining_filter.jl',R/'remaining_filter.json')
elif mode=='comparison_retry':
    run('fresh_export_comparison_retry',[sys.executable,N/'compare_fresh.py',W,R])
else: raise ValueError(mode)
assert all(e['exit_code']==0 for e in records),records
