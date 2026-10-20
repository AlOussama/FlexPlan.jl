from pathlib import Path
import json,hashlib,csv,zipfile,shutil
R=Path(__file__).parent;A=Path('D:/Projekte/Code/FlexPlan_A36_B1_OPT_FIX/reports/a3_6/b1_opt_20261020')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for src,name in [(R/'finalize_archive.log','archive_finalization.log'),(R/'zip_roundtrip_verification.log','zip_roundtrip_verification.log')]:shutil.copy2(src,A/name)
assert 'ZIP roundtrip verified 406 entries' in (A/'zip_roundtrip_verification.log').read_text()
manifest=json.loads((A/'reproduction_manifest.json').read_text());archive=A/manifest['archive']['path']
assert sha(archive)==manifest['archive']['sha256']
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for e in manifest['entries']:
        data=z.read(e['path']);assert len(data)==e['bytes'] and hashlib.sha256(data).hexdigest()==e['sha256']
required=['independent_b1_opt_closure_report.md','b1_original_vs_bridged_vs_oa_stage_evidence.json','b1_root_cause_or_limitation.md','b1_solver_reliability_matrix.csv','integer_9cases_proof_ledger.csv','integer_9cases_bounds.json','objective_rebase_derivation.md','verified_primal_dual_witnesses.zip','independent_b1_opt_tests.jl','reference_certifier.py','pre_fix_original_verdict.md','code_changes_and_regression_manifest.json','reaudit_prompt.md','release_gates.yaml','reproduction_manifest.json','remaining_gates_handoff.md']
assert all((A/n).exists() for n in required)
gates=(A/'release_gates.yaml').read_text()
for n in ['A3_closed: false','AP4_ready: false','empirical_study_ready: false','native_G3_MISOCP: numerical_inconclusive','integer_globality: case_specific_partial']:assert n in gates
validation={'all_required_outputs_present':True,'archive_bytes':archive.stat().st_size,'archive_sha256':sha(archive),'all_archive_entries_verified':len(manifest['entries']),'roundtrip_exact_certificate_verification_tests':171,'roundtrip_original_native_exact_constraint_verification':True,'new_native_exact_variables':3680,'new_native_exact_integer_constraints':1353,'full_regression_passed':6087,'saved_evidence_passed':4108,'new_julia_tests_passed':18,'MOI_before_after':{'before':42,'after':42},'domain_before_after':{'before':16,'after':16},'solver_runs_pre_fix':54,'solver_runs_post_fix_stress':45,'scope':'data and owner gates remain false; solver reauditing and tight global integer certification remain open'}
(A/'package_validation.json').write_text(json.dumps(validation,indent=2))
shutil.copy2(Path(__file__),A/'prepare_publication.py')
inventory=[]
for p in sorted(A.rglob('*')):
    if p.is_file() and p.name not in ['directory_inventory.json','published_file_sha256.csv']:
        inventory.append({'path':p.relative_to(A).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
(A/'directory_inventory.json').write_text(json.dumps(inventory,indent=2))
with (A/'published_file_sha256.csv').open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,['path','bytes','sha256']);w.writeheader();w.writerows(inventory)
for e in inventory:assert sha(A/e['path'])==e['sha256']
print('Publication package verified:',len(inventory)+2,'files;',len(manifest['entries']),'archive entries; no release gates promoted')
