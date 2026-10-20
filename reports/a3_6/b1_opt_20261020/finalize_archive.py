from pathlib import Path
import json,hashlib,zipfile,subprocess,csv,shutil,datetime
R=Path(__file__).parent;F=Path('D:/Projekte/Code/FlexPlan_A36_B1_OPT_FIX');A=F/'reports/a3_6/b1_opt_20261020';B=Path('D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,ensure_ascii=False),encoding='utf-8')
def git(repo,*args):
    p=subprocess.run(['git','-C',str(repo),*args],capture_output=True,text=True);return {'command':['git','-C',str(repo),*args],'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
assert json.loads((R/'input_source_and_historical_verification.json').read_text())['historical_entries_matched']==1060
extras=[]
specs=[('stage_diagnosis',['julia','+1.10.11','--startup-file=no','--project='+str(B),str(R/'stage_diagnosis.jl'),str(B),str(R/'experiments/stages'),str(R/'input')],0),('frozen_oa_variants',None,0),('lp_bound_inputs',None,0),('registered_solver_matrix',None,0),('reduce_oa_conflict',None,0),('model_inclusion',None,0),('fix_stress_matrix',None,0),('independent_b1_opt_tests',None,0),('objective_snapshots',None,0),('exact_primal_recovery_attempt01',None,1),('exact_primal_recovery_attempt02',None,0),('exact_primal_recovery_final',None,0),('exact_lower_bounds',None,0),('exact_lower_bounds_refined',None,0),('raw_cost_objective',None,0),('exact_raw_lower_bounds',None,0),('verify_exact_certificates_attempt01',None,0),('verify_native_exact_extension',None,0),('audit_objective_transform',None,0),('cost_and_cut_forensics',None,0),('verify_input_sources',None,0),('mosek_new_license',['C:/Program Files/Mosek/11.0/tools/platform/win64x86/bin/mosek.exe','-r','-d','MSK_IPAR_NUM_THREADS','1','-d','MSK_DPAR_MIO_MAX_TIME','120','-jsolo',str(R/'mosek_new_solution.json'),str(R/'input/native24.cbf')],-1)]
alias={'exact_primal_recovery_attempt01':'recover_exact_primal.py','exact_primal_recovery_attempt02':'recover_exact_primal.py','exact_primal_recovery_final':'recover_exact_primal.py','exact_lower_bounds':'reference_certifier.py','exact_lower_bounds_refined':'reference_certifier.py','exact_raw_lower_bounds':'reference_certifier.py','verify_exact_certificates_attempt01':'verify_exact_certificates.py'}
jargs={'frozen_oa_variants':[R],'lp_bound_inputs':[B,R/'lp_bounds'],'registered_solver_matrix':[B,R/'solver_matrix'],'reduce_oa_conflict':[R],'model_inclusion':[B,R/'model_inclusion'],'fix_stress_matrix':[F,R/'fix_stress_matrix'],'independent_b1_opt_tests':[R],'objective_snapshots':[F,R/'objective_snapshots',R]}
for id,cmd,exit_code in specs:
    p=R/(id+'.log');assert p.exists(),p
    if cmd is None:
        if id in jargs:
            project=F if id in ['fix_stress_matrix','independent_b1_opt_tests','objective_snapshots'] else B
            cmd=['julia','+1.10.11','--startup-file=no','--project='+str(project),str(R/(id+'.jl')),*map(str,jargs[id])]
        else:
            script=alias.get(id,id+'.py');args=[R]
            if id in ['exact_lower_bounds','exact_lower_bounds_refined']:args=[R/'lp_bounds']
            elif id=='exact_raw_lower_bounds':args=[R/'lp_bounds_raw_currency']
            elif id=='raw_cost_objective':args=[R,B]
            elif id=='cost_and_cut_forensics':args=[R,B,Path('D:/Projekte/Code/FlexPlan_A35_EXEC_REVIEW/reports/a3_5/executable_closure_20261020')]
            elif id=='verify_input_sources':args=[]
            cmd=['C:/Users/User/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',str(R/script),*map(str,args)]
    extras.append({'id':id,'command':cmd,'actual_process_exit':exit_code,'exit_evidence':'observed process completion from this audit; nested caught errors are separately retained','log':p.name,'log_sha256':sha(p),'file_created_utc':datetime.datetime.fromtimestamp(p.stat().st_ctime,datetime.timezone.utc).isoformat(),'file_modified_utc':datetime.datetime.fromtimestamp(p.stat().st_mtime,datetime.timezone.utc).isoformat(),'timestamps_are':'filesystem provenance only; not claimed exact process times'})
save(R/'execution_additional.json',extras);shutil.copy2(R/'execution_additional.json',A/'execution_additional.json')
stage=json.loads((A/'b1_original_vs_bridged_vs_oa_stage_evidence.json').read_text())
stage['stage_model_hashes']=[{'path':str(p.relative_to(R)).replace('\\','/'),'sha256':sha(p),'bytes':p.stat().st_size} for p in [R/'original_01/b1_exact_native.mof.json',R/'original_01/b1_bridged_conic_relaxation.mof.json',R/'original_01/b1_generated_OA_model.mof.json',R/'experiments/stages/oa_frozen.mof.json',R/'experiments/stages/relax_frozen.mof.json']]
stage['exact_original_native_verification']=json.loads((R/'native_exact_extension_verification.json').read_text())
save(A/'b1_original_vs_bridged_vs_oa_stage_evidence.json',stage)
shutil.copy2(R/'input_source_and_historical_verification.json',A/'input_source_and_historical_verification.json')
for p in [R/'verify_input_sources.py',Path(__file__)]:shutil.copy2(p,A/p.name)
states=[]
for repo in [B,F,Path('D:/Projekte/Code/FlexPlan_A35_EXEC_REVIEW'),Path('D:/Projekte/Code/FlexPlan_UC_GSCR'),Path('D:/Projekte/research-map'),Path('D:/Projekte/Code/pypsatomatpowerx')]:
    states.append({'repo':str(repo),'status':git(repo,'status','--porcelain=v1'),'head':git(repo,'rev-parse','HEAD'),'worktrees':git(repo,'worktree','list','--porcelain')})
save(R/'final_git_protected_state_before_publication.json',states);shutil.copy2(R/'final_git_protected_state_before_publication.json',A/'final_git_protected_state_before_publication.json')
sources=[]
for root in [B/'src',B/'scripts/paper_a',F/'src',F/'scripts/paper_a']:
    for p in sorted(root.rglob('*.jl')):sources.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size})
for repo in [B,F]:
    for name in ['Project.toml','Manifest-v1.10.toml']:
        p=repo/name;sources.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size})
for p in Path('C:/Users/User/.julia/packages/Pajarito/mhMdw/src').rglob('*.jl'):sources.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size})
save(R/'source_runtime_sha256_manifest.json',sources);shutil.copy2(R/'source_runtime_sha256_manifest.json',A/'source_runtime_sha256_manifest.json')
archive=A/'verified_primal_dual_witnesses.zip';entries=[]
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(R.rglob('*')):
        if not p.is_file():continue
        rel=p.relative_to(R)
        if rel.parts[0] in ['input','__pycache__'] or rel.parts[:2]==('validation','test'):continue
        data=p.read_bytes();name=rel.as_posix();z.writestr(name,data)
        entries.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist())==len(entries)
    for e in entries:assert hashlib.sha256(z.read(e['path'])).hexdigest()==e['sha256']
save(A/'reproduction_manifest.json',{'original_ap3_sha':'485b637cc1998a327206c5929434bd26c6f0be16','exec_input_sha':'4d9f346c5fca80e00fd01d96c39a2bac91776ac0','macro_authority_sha':'e49b64216f82eefda77d6997ed68ed2d12c8ae78','production_correction_sha':'910d44122a37d9ed2cca06940740b46706c73d40','archive':{'path':archive.name,'sha256':sha(archive),'bytes':archive.stat().st_size,'entries':len(entries),'all_entries_sha256_verified':True},'entries':entries,'command_manifests':['execution_initial.json','execution_fix_validation.json','execution_additional.json'],'previous_archive':'input_sha256_manifest.json','source_manifest':'source_runtime_sha256_manifest.json','excluded_unmodified_inputs':['381 prior EXEC entries separately bound by input_sha256_manifest','byte-identical regression test fixture copy; code/data pinned in original Git and input source verification'],'scope':'Exact certificates refer to normalized binary rational constraints and declared exact raw-currency objective; no complete global integer optimality claim.'})
inventory=[]
for p in sorted(A.rglob('*')):
    if p.is_file() and p.name not in ['published_file_sha256.csv','directory_inventory.json']:
        inventory.append({'path':p.relative_to(A).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
save(A/'directory_inventory.json',inventory)
with (A/'published_file_sha256.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,['path','bytes','sha256']);w.writeheader();w.writerows(inventory)
print('New archive',archive.stat().st_size,'bytes;',len(entries),'entries; SHA256',sha(archive));print('Published artifact files',len(inventory)+2)
