import pathlib, subprocess, json, datetime, shutil
R=pathlib.Path(__file__).parent; B=pathlib.Path('D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE'); F=pathlib.Path('D:/Projekte/Code/FlexPlan_A35_EXEC_REVIEW')
records=[]
def run(id,args,cwd=B):
    command=['julia','+1.10.11','--startup-file=no','--project='+str(cwd),*map(str,args)]
    row={'id':id,'command':command,'cwd':str(cwd),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    with (R/(id+'.log')).open('w',encoding='utf-8') as f: p=subprocess.run(command,cwd=cwd,stdout=f,stderr=subprocess.STDOUT)
    row.update(exit_code=p.returncode,ended_utc=datetime.datetime.now(datetime.timezone.utc).isoformat());records.append(row)
    (R/'execution_initial.json').write_text(json.dumps(records,indent=2));print(id,p.returncode,flush=True)
run('environment',['-e','using Pkg,LinearAlgebra,JuMP,HiGHS,Clarabel,Pajarito; Pkg.instantiate(); Pkg.status(); println(VERSION); println(Sys.CPU_NAME); println(Threads.nthreads()); println(BLAS.get_config()); println(BLAS.get_num_threads()); println(pathof(Pajarito));'])
for target,base in [('original_01',B),('original_02',B),('metadata_01',F)]:
    d=R/target;(d/'integer_final').mkdir(exist_ok=True)
    source=R/'input/integer_final/full_witness_reference_24snap_G3.json'
    if not source.exists(): raise FileNotFoundError(source)
    shutil.copy2(source,d/'integer_final'/source.name)
    run(target+'_native_before',[R/'tools/b1_exact_native_repro.jl',base,d],base)
    run(target+'_transfer',[R/'tools/b1_transfer_full_witness.jl',d],base)
    # The second solve uses exactly the same directory to enable the prescribed bridge check.
    # Preserve the first outputs before the original script writes its next files.
    first=d/'before';first.mkdir()
    for p in d.glob('*.*'): shutil.copy2(p,first/p.name)
    run(target+'_native_after',[R/'tools/b1_exact_native_repro.jl',base,d],base)
run('fixed_nine_fresh',[R/'tools/independent_integer_b1_audit.jl',B,R/'integer_fresh','fixed_only_best_historical_seed'])
run('jump_moi_regression',[R/'tools/independent_jump_moi_audit.jl',R/'tests'])
run('domain_regression',[R/'tools/independent_domain_mutations.jl',R,B])
