import pathlib,subprocess,json,datetime,shutil
R=pathlib.Path(__file__).parent;F=pathlib.Path('D:/Projekte/Code/FlexPlan_A36_B1_OPT_FIX')
(R/'validation').mkdir(exist_ok=True);shutil.copytree(F/'test',R/'validation/test')
records=[]
def run(id,args):
    cmd=['julia','+1.10.11','--startup-file=no','--project='+str(F),*map(str,args)];start=datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (R/(id+'.log')).open('w',encoding='utf-8') as f:p=subprocess.run(cmd,cwd=F,stdout=f,stderr=subprocess.STDOUT)
    records.append({'id':id,'command':cmd,'cwd':str(F),'started_utc':start,'ended_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':p.returncode,'code_sha':'910d44122a37d9ed2cca06940740b46706c73d40'})
    (R/'execution_fix_validation.json').write_text(json.dumps(records,indent=2));print(id,p.returncode,flush=True)
run('fix_full_regression',[R/'validation/test/runtests.jl'])
run('fix_saved_evidence',[F/'test/run_paper_a_ap3_evidence.jl','D:/Projekte/Code/FlexPlan_A35_EXEC_RUN/historical_evidence'])
run('fix_jump_moi_regression',[R/'tools/independent_jump_moi_audit.jl',R/'tests_fix'])
run('fix_domain_regression',[R/'tools/independent_domain_mutations.jl',R,F])
