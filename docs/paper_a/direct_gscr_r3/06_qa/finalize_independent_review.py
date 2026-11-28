"""Final independent R3 evidence review; read/hash/check only, no solver."""
import datetime,hashlib,json,pathlib,subprocess
R=pathlib.Path('E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01');Q=R/'06_qa';P=R.parent/'SCI_GOLD_AC_DIRECT_02_LOCAL_20261127_02';S='ebaffb57feb3a27f2d7d87b745930664f625f935';BASE='a2cadc4391a3cac1ae06f9f7fc0ea88a62ef4f7e'
inputs={};models=[]
def sha(p):return hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
def read(p):return json.loads(pathlib.Path(p).read_text(encoding='utf-8-sig'))
def bind(p):
    p=pathlib.Path(p);inputs[str(p)]={'sha256':sha(p),'bytes':p.stat().st_size};return read(p)
def git(*a):return subprocess.check_output(['git',*a],text=True).strip()
assert git('rev-parse','HEAD')==S and not git('status','--porcelain','--untracked-files=no')
native=bind(Q/'INDEPENDENT_NATIVE_RUNTIME_SUMMARY.json');assert native['status']=='NATIVE_FROZEN_QA_PASS_PENDING_FINAL_REVIEW' and len(native['completed'])==9 and all(x['returncode']==0 for x in native['completed'])
mps=bind(Q/'INDEPENDENT_MPS_ROUNDTRIP_SUMMARY.json');assert mps['status']=='PASS_ALL_THREE_FROZEN_GUROBI_MPS_ROUNDTRIPS' and len(mps['completed'])==3 and all(x['returncode']==0 for x in mps['completed'])
index=bind(Q/'FROZEN_INDEX_WORKTREE_SUPPLEMENT.json');assert len(index['snapshots'])==11 and all(x['observed_clean'] and x['head']==S for x in index['snapshots'])
bridge=bind(R/'05_scientific_results/SOC_WR_NATIVE_BRIDGE_CERTIFICATE_TRANSFER.json');assert bridge['status']=='PASS' and bridge['source_commit']==S and bridge['actual_new_voltage_products']==8736 and bridge['existing_voltage_planes_checked']=={'BASE':8736,'G2':8736}
assert bind(Q/'NATIVE_BRIDGE_INVENTORY_SUPPLEMENT.json')['status']=='PASS'
for form in ('LPAC','SOC-WR','QCRM'):
    for method,backends,section in [('G0',('mosek',),'01_native_g0'),('G3',('gurobi','mosek'),'02_native_g3')]:
        for backend in backends:
            name=f'{method}_{form}_{backend}_frozen';folder=R/section/f'{form}_{backend}_frozen'
            receipt=bind(R/'04_reproducibility'/f'{name}_BUILD_RECEIPT.json')
            assert receipt['source_commit']==receipt['source_commit_after']==S and receipt['exit_code']==0 and not receipt['tracked_dirty_before'] and not receipt['tracked_dirty_after'] and receipt['optimization_performed'] is False
            profile=bind(folder/'profile.json');assert profile['discrete_after_relaxation']==0 and profile['strength_method']==method and profile['case']['case_sha256']=='66885c9b5d27b21ac1000cf16e8da5d886b7ab50085783957907cebef8a41d3b'
            assert not any((folder/x).exists() for x in ('outcome.json','primal.csv','native_primal.npy'))
            audit=bind(Q/f'independent_{name}.json');assert audit['status']=='PASS'
            if method=='G0':
                assert audit['blocks']==168 and audit['positions']==118104 and audit['dimensions']=={'37':168}
                assert audit['verifier_sha256']==sha(pathlib.Path('audit/r3_independent_native_verify.py'))
                assert audit['input_sha256']==sha(folder/'native_psd_readback.json') and audit['expected_psd_sha256']==sha(folder/'expected_psd.json') and audit['native_task_sha256']==sha(folder/'native.task.gz')
            else:
                assert audit['native_cones']==8736 and audit['q_endpoints']==17472 and audit['all_doubled_fixed_tails_match_full_M_ledger'] and audit['all_q_budget_incidences_exactly_once']
                v=bind(folder/'g3_actual_native_verdict.json');assert v['status']=='PASS' and v['native_node_rows_exact']==6216 and v['native_q_nonnegative_bounds']==17472
                assert v['exporter_source_sha256']==sha(pathlib.Path('scripts/paper_a/G3NativeReadback.jl'))
                assert v['raw_readback_sha256']==audit['raw_readback_sha256']==sha(folder/'g3_actual_native_readback.json')
                assert v['persisted_native_model_sha256']==audit['native_model_sha256']==sha(folder/v['persisted_native_model'])
                if backend=='gurobi':
                    transport=bind(Q/f'independent_{name}_MPS_ROUNDTRIP.json');assert transport['status']=='PASS' and transport['optimization_called'] is False and transport['mps_sha256']==v['persisted_native_model_sha256']
            delta=bind(R/'05_scientific_results'/f'{method}_{form}_{backend}_FROZEN_SOURCE_DELTA.json')
            assert all(x['coefficient_differences']==0 for x in delta['metrics'].values()) and delta['metrics']['M']['exactly_equal_expressions']==118104
            for e in delta['inputs'].values():assert sha(e['path'])==e['sha256']
            models.append({'method':method,'formulation':form,'backend':backend,'status':'PASS'})
preserved=bind(R/'00_intake/ORIGINAL_INPUT_PRESERVATION.json');assert preserved['status']=='PASS' and preserved['checked_files']==1251 and preserved['unchanged_files']==1238 and not preserved['unexpected_changes'] and len(preserved['authorized_live_source_changes'])==13
for x in preserved['authorized_live_source_changes']:
    p=pathlib.Path(x['path']);assert sha(p)==x['new_sha256'] and x['recovered_original_sha256']==x['r2_sha256']
    relative=p.resolve().relative_to(pathlib.Path.cwd().resolve()).as_posix();blob=subprocess.check_output(['git','show',BASE+':'+relative])
    assert any(hashlib.sha256(b).hexdigest()==x['r2_sha256'] for b in (blob,blob.replace(b'\n',b'\r\n')))
replay=bind(R/'03_replay_integrity/ORIGINAL_MODEL_AUDIT.json');assert replay['gold_qualified'] is False and replay['qualification']=='SENSITIVITY_ONLY_NOT_GOLD_UB'
for x in replay['inputs'].values():assert sha(x['path'])==x['sha256']
assert bind(R/'03_replay_integrity/NEGATIVE_CONTROL_RESULTS.json')['result']=='PASS'
small=bind(R/'02_native_g3/SMALL_BACKEND_QUALIFICATION.json');assert small['status']=='PASS' and small['total_tests']==512 and small['frozen_source_commit']==S
runtime=bind(R/'04_reproducibility/JULIA_RUNTIME.json');assert runtime['julia_version']=='1.11.5' and runtime['gurobi_runtime_version']=='13.0.3' and runtime['mosek_runtime_version']==[11,2,6]
assert runtime['Manifest-v1.11.toml_sha256']==sha(pathlib.Path('Manifest-v1.11.toml'))
libs=bind(R/'04_reproducibility/SOLVER_LIBRARY_HASHES.json')
for x in libs:assert sha(x['path'])==x['sha256']
certs={'LPAC':('reused_lower_original_runtime/LPAC_G0/exact_dual_1.json','lower_original_EUR2025_annual_floor',127407323716),'SOC-WR':('reused_soc_stage_retry/SOC/g0_certified_lower_boxdiag_PM0217.json','original_cost_EUR_annual_equivalent_lower_floor',127395770699),'QCRM':('recovered_transfer/QCRM/g0_certified_lower_boxdiag_PM0217.json','G0_lower_EUR_annualized',127395770699)}
for form,(path,key,value) in certs.items():assert bind(P/path)[key]==value
for name in ('independent_replay_tests.log','independent_native_mutations_frozen.log'):
    p=Q/name;inputs[str(p)]={'sha256':sha(p),'bytes':p.stat().st_size}
finalstate={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'head':git('rev-parse','HEAD'),'tracked_porcelain':git('status','--porcelain','--untracked-files=no'),'staged_diff':git('diff','--cached','--name-only'),'unstaged_diff':git('diff','--name-only')}
assert finalstate['head']==S and not finalstate['tracked_porcelain'] and not finalstate['staged_diff'] and not finalstate['unstaged_diff']
(Q/'FINAL_SOURCE_STATE.json').write_text(json.dumps(finalstate,indent=2)+'\n',encoding='utf-8');bind(Q/'FINAL_SOURCE_STATE.json')
report={'status':'PASS','source_commit':S,'reference_commit':BASE,'recommendation':'R3_TECHNICALLY_ACCEPTED_WITH_EXPLICIT_SCOPE_LIMITATIONS','reviewer_role':'Independent original-evidence, finite-coefficient and final QA reviewer','utc':finalstate['utc'],'material_findings':[],'production_files_modified_by_reviewer':[],'qa_only_authorship':True,'models':models,'new_G0':{'networks':3,'blocks':504,'complete_triangle_positions':354312,'exact_binary_rational_native_trace_readback':'PASS'},'new_G3':{'full_native_references':6,'cones_total':52416,'node_rows_total':37296,'q_bounds_total':104832,'actual_native_and_doubled_tail_checks':'PASS','saved_Gurobi_MPS_entire_constraint_model_roundtrips':3},'new_native_network_certificate_transfer':'PASS_EXPLICIT_FINITE_COEFFICIENT_MONOTONICITY_TO_PREVIOUSLY_ACCEPTED_PLANES','G3_lower_bound_evidence_class':'EXACT_FLOORED_LB_TRANSFERRED_FROM_R2_G0_VIA_ACCEPTED_G0_G3_PROJECTION_EQUIVALENCE','transferred_G3_LB_EUR2025':{k:v[2] for k,v in certs.items()},'new_native_solver_LB':None,'new_weekly_optimizations':0,'reviewer_optimizer_calls':0,'independent_tests':{'replay_integrity_groups':3,'native_exact_positive':1,'native_material_negatives':10,'result':'PASS'},'reviewed_previously_completed_small_tests':512,'preservation_review':{'immutable_inputs_reported_unchanged':1238,'immutable_bytes_reported_unchanged':6333591003,'authorized_live_source_original_hashes_independently_reconstructed':13,'scope':'Reviewed fresh root immutable-file hash audit; independently rehashed bound QA inputs and restored all13 original source byte hashes from pinned Git objects.'},'retained_limitations':['Historical native G0 identity remains UNVERIFIED; historical rounded G3 equivalence failure is not retroactively repaired.','All original point ceilings remain numerical tolerance qualifications, not rigorous exact feasible upper bounds; LPAC G0 hour108 retains approximately -2.237e-10 eigenvalue qualification.','Archived LPAC G3 point remains SENSITIVITY_ONLY / NOT_GOLD_UB; no accepted G3 GOLD ceiling or new primal is supplied.','Whole-native old/new network identity is not claimed. The actual SOC-WR RSOC bridge change is explicitly qualified by the recorded gamma<=1 implication into the accepted existing voltage Supporting-Planes.','QCRM full finite SOC-QCP nesting remains UNVERIFIED and is not used as a certificate premise; F02 remains closed.','DCP native coverage is small attachment qualification plus existing DCP/UC regressions, not a new168hour DCP native export.','The frozen launcher checks unstaged changes only; actual staged/unstaged cleanliness is supported by11 independent observations and the final snapshot.','No exact nonlinear AC feasibility, integer optimum or dynamic stability claim.','Publication/remote delivery sealing occurs after this scientific-source review and must bind final delivery HEAD separately without altering frozen production code.'],'inputs':inputs}
(Q/'INDEPENDENT_FINAL_REVIEW.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
md=f'''# Independent final review

**PASS — R3_TECHNICALLY_ACCEPTED_WITH_EXPLICIT_SCOPE_LIMITATIONS**

Scientific source freeze: `{S}`. Reference: `{BASE}`. No production implementation was authored or changed by this reviewer; only independent QA tools and evidence were authored.

All nine frozen native builds completed without weekly optimization or new primal outputs. The reviewer independently checked all three persisted/reopened G0 tasks: 504 order37 PSD blocks and354312 complete triangle positions, including every affine coefficient, constant and exact offdiagonal trace factor. Six G3 references passed actual native coefficient/domain checks and independent raw endpoint, bound, doubled-tail and node-incidence checks. All three saved Gurobi MPS files were reopened through the actual C API, with the entire constraint matrices, bounds, RHS, senses and quadratic terms matching binary64 exactly. No optimizer was called by this reviewer.

The newly identified SOC-WR network bridge delta was checked explicitly against the already accepted R2 Supporting-Plane recipe. All8736 actual new voltage products identify the same original primary voltage coordinates, with nonnegative factors and no wider primary bounds. Their exact factor is `gamma=2535301200456458353478625262249/2535301200456458802993406410752 < 1`. All8736 BASE and8736 G2 voltage planes satisfy the accepted exact direction-norm criterion. The same global RSOC bridge change is absent from the LPAC/QCRM inventories. This closes the concrete new-target applicability gate; it does not assert whole old/new native equality or full finite SOC-QCP nesting.

The accepted G0 floored lower certificates therefore transfer through the already accepted G0/G3 projection equivalence to corrected G3: LPAC127407323716, SOC-WR127395770699 and QCRM127395770699 EUR2025. Evidence class: `EXACT_FLOORED_LB_TRANSFERRED_FROM_R2_G0_VIA_ACCEPTED_G0_G3_PROJECTION_EQUIVALENCE`. These are certificate transfers, not newly computed native solver bounds. No new G3 GOLD upper bound is supplied. F02 is reused without re-proving its method.

Independent reruns passed three replay-integrity test groups and one exact native positive fixture with ten material mutation controls. The previously completed512 small native/regression tests were reviewed; they were not re-solved during final QA. Nine full source-delta audits retain zero coefficient differences. Historical preservation reports1238 immutable inputs unchanged; all13 authorized live-source original hashes were independently reconstructed from the pinned Git blobs with explicit LF/CRLF restoration. The index/worktree supplement contains11 clean observations, and the final source/index/worktree snapshot is clean at the frozen SHA.

No unresolved material implementation finding remains in this scope. Retained limitations are explicit: historical native G0 remains UNVERIFIED; historical rounded G3 failures remain historical failures; numerical point ceilings are not rigorous exact-feasibility upper bounds; LPAC G0 retains its approximately-2.237e-10 PSD tolerance qualification; archived LPAC G3 remains SENSITIVITY_ONLY / NOT_GOLD_UB. DCP native coverage is limited to small attachment qualification plus existing regressions. Continuous relaxed LPAC/SOC-WR/QCRM evidence supplies no exact nonlinear AC, integer-optimality or dynamic-stability claim.

The launcher itself checks only unstaged changes; the delivered actual runs additionally have independent staged/unstaged observations. Formal S-GOV acceptance and final publication/remote sealing remain reserved to their respective steps. The JSON companion binds the reviewed evidence by SHA256; later delivery commits must preserve the frozen production code.
'''
(Q/'INDEPENDENT_FINAL_REVIEW.md').write_text(md,encoding='utf-8');print('FINAL INDEPENDENT QA PASS; all9 native,3 MPS, target delta, source/index and provenance gates closed')
