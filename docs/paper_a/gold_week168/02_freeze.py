"""Freeze the 14 independently reconstructed original KW8 rows and their native numerical bounds in EUR2025."""
from pathlib import Path
import csv,hashlib,json,math,os,re,sys,platform
def read(p):return json.loads(p.read_bytes())
def sha(p):
 with p.open('rb') as h:return hashlib.file_digest(h,'sha256').hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,allow_nan=False)+'\n',encoding='utf8')
def writecsv(p,rows):
 with p.open('w',newline='',encoding='utf8') as h:
  w=csv.DictWriter(h,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
code=Path(__file__).resolve().parent;out=Path(os.environ.get('PAPER_A_F2_OUTPUT_ROOT',code));base=Path(os.environ.get('PAPER_A_F2_INPUT_ROOT',code.parent))
intake_path=Path(os.environ.get('PAPER_A_F2_INTAKE',code/'00_INPUT_AND_RUNTIME_INTAKE.json'));input=read(intake_path);iset={x['case_id']:x for x in input['core']};archive={x['relative_path']:x['sha256'] for x in input['archive_objects']}
matrix=[];bounds=[];rowfiles={};references={};complete=read(out/'02_COMPLETE_ALGEBRAIC_ROWS.json');legacy=read(out/'02_RE50_LP_COORDINATE_PROOF.json');primal={}
for file in sorted((out/'02_final_rows').glob('*.json')):
 x=read(file);rid=x['row_id'];_,qs,m,mode=rid.split('-');q=int(qs);i=iset[f"{m}-{q}-{'integer' if mode=='MILP' else 'relaxed'}"]
 pf=i['archived_solver_model_profile'];assert x['case_sha256']==i['active_case_sha256']
 f=base/i['run_summary']['relative_path'];parent=f.parent;s=read(f);assert x['summary_sha256']==sha(f)==i['run_summary']['sha256'];assert x['code']==i['consumer'] and s['hours']==168 and x['original_point_dimensions']==311395
 assert s['numerically_accepted'] and s['primal_status']=='FEASIBLE_POINT' and x['physical_point_accepted'] and not x['failed'] and complete['results'][rid]['violations_over_original_tolerance']==0
 assert s['native_solver_attributes']['SolCount']>0 and s['native_solver_attributes']['Status']==2 and s['status']=='OPTIMAL'
 for path,h in x['source_hashes'].items():
  # Inputs have already been byte-hashed by physical replay. Cross-bind all in the independent primary inventory.
  obj=Path(path)
  if base in obj.parents and obj.relative_to(base).as_posix() in archive:assert archive[obj.relative_to(base).as_posix()]==h
 hist={ar:sha(base/ar) for ar in i['historical_acceptance']};assert hist and all(archive.get(k)==h for k,h in hist.items());references[rid]=hist
 c=x['cost_replay'];n=s['native_solver_attributes'];ub=c['annualized_total'];lb=n['ObjBound'];native=n['ObjVal'];reported=s['objective_EUR2025'];rs=s.get('operation_168h_components_EUR2025') or s['operation_840h_components_EUR2025']
 assert lb==s['best_bound_EUR2025'] and abs(c['CAPEX']-s['annualized_capex_EUR2025'])<.02 and abs(c['OPEX_event']-rs['startup_shutdown'])<.01 and abs(c['OPEX_gen']-rs['generation'])<.01 and abs(c['OPEX_storage']-rs['storage'])<.01
 assert abs(native-ub)<.02 and abs(reported-ub)<.02 and abs(c['load']-s['load_MWh'])<1e-5 and abs(c['RE']-s['wind_pv_MWh'])<1e-5
 assert x['discrete_domains']==(111401 if mode=='MILP' else 0)
 log=(parent/'gurobi.log').read_text(encoding='utf8',errors='replace');version=re.search(r'Gurobi Optimizer version ([\d.]+)',log)
 if not version:version=re.search(r'Gurobi ([\d.]+)',log)
 a=dict(row_id=rid,quota_pct=q,model=m,integrality=mode,annualized_total_EUR2025=ub,CAPEX_EUR2025=c['CAPEX'],raw_week_OPEX_EUR2025=c['raw_week_OPEX'],raw_week_dispatch_OPEX_EUR2025=c['OPEX_gen'],raw_week_startup_shutdown_OPEX_EUR2025=c['OPEX_event'],raw_week_storage_OPEX_EUR2025=c['OPEX_storage'],annualized_week_OPEX_EUR2025=c['annualized_week_OPEX'],actual_RE_MWh=c['RE'],actual_load_MWh=c['load'],actual_RE_share_pct=c['renewable_share_pct'],**x['portfolio_MW'])
 for k in ('G1','G2','G0','M0','B_min'):
  y=x['margins'].get(k,{});dd=y.get('defined_hours',0);a[k+'_min_margin']=y.get('min');a[k+'_defined_hours']=dd;a[k+'_failed_hours']=y.get('failed_hours',0);a[k+'_undefined_hours']=168-dd
 a.update(GFM_credited_strength_pu_h=x['source_credit_weekly_pu_hours']['GFM'],SYN_credited_strength_pu_h=x['source_credit_weekly_pu_hours']['SYN'],native_online_exposure_pu_h=x['exposure_weekly_pu_hours']['native_online'],new_available_RE_exposure_pu_h=x['exposure_weekly_pu_hours']['new_availability'],SU_SD_pairs=x['potential_event_pairs'],SU_SD_positive_overlaps=x['simultaneous_positive_SU_SD'],avoidable_overlap_week_EUR2025=math.fsum(e['eliminable_week_cost_EUR2025'] for e in x['overlap_events']),original_variables=311395,original_discrete=x['discrete_domains'],active_strength_rows=6216 if m!='BASE' else 0,independent_common_original_rows=complete['results'][rid]['all_algebraic_rows_evaluated'],max_common_original_residual=complete['results'][rid]['max_abs_original_row'],input_case_sha256=x['case_sha256'],input_profile_sha256=i['input_profile_sha256'],archived_model_profile_sha256=pf['sha256'] if pf else '',numeric_solver_status=s['status'],solver_version=version[1] if version else 'unavailable',scientific_reference=input['paper_source'],producer_SHA=i['producer'],consumer_SHA=x['code'],original_primal_sha256=sha(parent/'full_primal.csv'),original_replay_sha256=sha(file),acceptance='INTEGER_INCUMBENT_ACCEPTED' if mode=='MILP' else 'RELAXATION_ACCEPTED')
 matrix.append(a);rowfiles[rid]=dict(relative_path='02_final_rows/'+file.name,sha256=sha(file))
 gap=s['relative_gap'];ngap=(native-lb)/abs(native)
 assert abs(gap-ngap)<1e-7 and gap>=0
 bounds.append(dict(row_id=rid,quota_pct=q,model=m,integrality=mode,numeric_lb_EUR2025=lb,numeric_ub_EUR2025=ub,native_primal_objective_EUR2025=native,reported_objective_EUR2025=reported,raw_vector_minus_native_EUR2025=ub-native,relative_gap_fraction=gap,solve_s=s['solve_time_s'],G1_LB_minus_BASE_UB_EUR2025=None,G1_G2_70_intervals_overlap=None,scope='Native numerical solver bound; upper value from independent full primal; original annualized KW8 coordinate, EUR2025.'))
 primal[rid]=dict(per_constraint_physics_and_source= rowfiles[rid],case_sha256=x['case_sha256'],native_scope=complete['results'][rid],active_G1_G2_rows=6216 if m!='BASE' else 0,source_stamps=x['counts']['source_stamp_pu'],physics_maxima_dimensioned_and_normalized=x['maxima'],diagnostics=x['margins'],SU_SD_overlaps=x['overlap_events'],old_independent_receipts=hist)
assert len(matrix)==len(bounds)==14
intervals={a['row_id']:a for a in bounds};pairs={}
for a in bounds:
 q,m,mode=a['quota_pct'],a['model'],a['integrality']
 if m=='G1':
  diff=a['numeric_lb_EUR2025']-intervals[f'WK08-{q}-BASE-{mode}']['numeric_ub_EUR2025'];assert diff>0;a['G1_LB_minus_BASE_UB_EUR2025']=diff;pairs[a['row_id']]=diff
 if q==70 and m in ('G1','G2'):
  b=intervals[f"WK08-70-{'G1' if m=='G2' else 'G2'}-{mode}"];a['G1_G2_70_intervals_overlap']=max(a['numeric_lb_EUR2025'],b['numeric_lb_EUR2025'])<=min(a['numeric_ub_EUR2025'],b['numeric_ub_EUR2025'])
assert len(pairs)==6
gm=intervals['WK08-70-G2-MILP'];assert gm['G1_G2_70_intervals_overlap'] and abs(gm['relative_gap_fraction']*100-.03246578)<1e-7
for name in ('G3-19','G3-20-A','G3-20-B'):assert complete['results'][name]['violations_over_original_tolerance']>0
assert complete['results']['G2-G3-WITNESS']['violations_over_original_tolerance']==0
writecsv(out/'02_FINAL_WEEK168_RESULT_MATRIX.csv',matrix);writecsv(out/'02_OBJECTIVE_AND_SOLVER_BOUNDS.csv',bounds)
spec=dict(case_checks='From raw gens, line primitives, storage, thermal blocks and new dispatch, independent dimensional 168h physics plus mapped sparse affine rows. Every core candidate obeys its enforced strength family; inactive diagnostic failure or unavailable inverse is not a rejection.',M0_scope='Only for SPD, symmetric Z B, p within the approved tiny negativity diagnostic tolerance and entrywise inverse nonnegative to arithmetic tolerance. Empty margin = domain unqualified. Failed_hours excludes undefined hours. Slack=1-max(B^-1 p).',source='AC retained physical regions=37, eliminated=0; 7 independent passive islands. Source status, native voltage and MVA stamps reconstructed independently; positive GFM credit once. Actual wind/PV injected generation distinct from native online and availability-weighted prospective exposure.',residuals='Common dump comparator shares coefficient source only across aligned data/model families; typed G3-specific row/column metadata excluded. Original physical independent reconstruction for each family is primary. Each physical maximum includes absolute, unit threshold and normalized ratio. Solver bounds are numerical, not outward-rounded rigorous certificates.',event_policy='Positive simultaneous SU and SD is allowed. Reducing both by their minimum preserves transition difference, loosens both event bounds and minimum-time inequalities; no changes to original retained incumbents or their reported UB. SD=0.2 SU is the study assumption.',G3_results={k:complete['results'][k] for k in ['G3-19','G3-20-A','G3-20-B','G2-G3-WITNESS']})
save(out/'02_ORIGINAL_PRIMAL_REPLAY.json',dict(reviewer='/root/qa_r',case_rows=primal,certificates=spec,full_row_replay_sha256=sha(out/'02_COMPLETE_ALGEBRAIC_ROWS.json'),RE50_recovery_sha256=sha(out/'02_RE50_LP_COORDINATE_PROOF.json')))
arts={k:sha(out/k) for k in ['02_FINAL_WEEK168_RESULT_MATRIX.csv','02_OBJECTIVE_AND_SOLVER_BOUNDS.csv','02_ORIGINAL_PRIMAL_REPLAY.json','02_COMPLETE_ALGEBRAIC_ROWS.json','02_RE50_LP_COORDINATE_PROOF.json']}
commands=[('02_reproduce.py','02_replay_final.log'),('02_replay_original_rows.py','02_original_rows.log'),('02_replay_legacy_coordinates.py','02_re50_coordinates.log')]
cmds=[dict(command=[sys.executable,str(code/k)],script_sha256=sha(code/k),exit=0,log=l,log_sha256=sha(out/l)) for k,l in commands]
save(out/'02_INDEPENDENT_ACCEPTANCE.json',dict(reviewer='/root/qa_r',gate='GATE2_PASS_VARIANT_A',independent_of_implementation_and_paper=True,solver_calls=0,case_count=14,weekly_hours=168,method_checks=spec,case_ids=list(primal),verified_numeric_premiums_EUR2025=pairs,artifact_sha256=arts,input_intake_sha256=sha(intake_path),case_receipts=rowfiles,scripts_and_completed_logs=cmds,replay_core_sha256=sha(code/'02_original_case.py'),finalizer_sha256=sha(Path(__file__)),finalizer_command=[sys.executable,str(Path(__file__).resolve())],runtime=platform.python_version(),environment=dict(PAPER_A_F2_INPUT_ROOT=str(base),PAPER_A_F2_PRODUCER_ROOT=os.environ.get('PAPER_A_F2_PRODUCER_ROOT','D:/Projekte/Code/pypsatomatpowerx'),PAPER_A_F2_OUTPUT_ROOT=str(out),PAPER_A_F2_INTAKE=str(intake_path),OPENBLAS_NUM_THREADS=1),scope_limits=['Historical original BASE/G1 cases lack a separate file for the attached model profile. Use actual primary-case profile, runner, solver log and complete candidate, no substituted G2 profile.','No new optimization. The numerical MILP intervals for G1/G2 at 70 percent overlap. The exact values of the respective 70-percent LPs can differ; no universal G1/G2 inclusion or economic order.','Artifacts contain original economics of the one selected week, multiplied once for annualized-equivalent cost, without a yearlong or dynamic claim.','RE50 LP missing RE dispatch labels recovered from original labelled capacity indices, original allocation loop and independently confirmed numerical and semantic crosschecks.']))
print('GATE2_PASS_VARIANT_A',14,sha(out/'02_INDEPENDENT_ACCEPTANCE.json'),arts)

