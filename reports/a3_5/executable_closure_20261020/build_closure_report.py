"""Build additive German adjudication and ledgers from executed audit evidence."""
from pathlib import Path
import csv,hashlib,json,sys,collections
R=Path(sys.argv[1]);B=Path(sys.argv[2]);O=Path(__file__).parent
ORIGINAL='485b637cc1998a327206c5929434bd26c6f0be16';FIX='e1e075626b38b478faf57efe62e557fc94753f00';REVIEW='50f88d5d30194afbbd188c96e3eab795b7a7de49';SCI='e8118425adc335a99e85120d943763305f211315'
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(n,s):(O/n).write_text(s,encoding='utf-8')
def js(n,x):write(n,json.dumps(x,indent=2))
def h(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def code(file,needle):
    line=next(i for i,l in enumerate((B/file).read_text(encoding='utf-8').splitlines(),1) if needle in l)
    return f'{file}:{line}@{ORIGINAL}'
def csvout(name,rows):
    with (O/name).open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
raws={p.parent.name:h(p) for p in (R/'suite').glob('*/case.json')}
matrix=load(R/'raw_reconstruction_summary.json');metrics=load(R/'independent_metric_results.json');integer=load(R/'integer_global_bounds_and_objective_audit.json');execution=load(R/'execution.json');native=load(R/'b1_exact_native_result.json');bridge=load(R/'b1_bridged_full_witness_check.json');fullw=load(R/'b1_exact_full_witness_verification.json');runs=load(R/'suite/runs.json')['runs'];counts=collections.Counter(x['status'] for x in runs)
assert len(runs)==162 and len(integer)==9 and not metrics['failures']
assert all(r['registry_coverage'] and r['metric_ids']==124 for r in metrics['roundtrips'])
assert len(load(R/'benchmarks/benchmark.json')['records'])==8
assert all(x['exit_code']==0 for x in execution)
src={
 'P001':code('src/core/paper_a_regional.jl','function network_reference'),
 'P002':code('src/core/paper_a_regional.jl','function symmetric_z'),
 'P003':code('src/core/paper_a_regional.jl','function reduced_strength'),
 'P004':code('src/core/paper_a_diagnostics.jl','Z=B\\Matrix'),
 'P005':code('src/core/paper_a_integration.jl','function _paper_a_g1!'),
 'P006':code('src/core/paper_a_integration.jl','function _paper_a_online_expressions!'),
 'P007':code('src/core/paper_a_regional.jl','function online_exposure'),
 'P008':code('src/core/paper_a_formulations.jl','elseif f isa ExactEdgeSOCGSCR'),
 'P009':code('src/core/paper_a_diagnostics.jl','function finite_spectrum'),
 'P010':code('scripts/paper_a/AP3Pipeline.jl','function metric_unit')}
preds=[
 ('Y positive sequence; L=-Im(Y); B0=Lrr-Lre solve(Lee,Ler); B=B^T','unit-tap reciprocal lines; phase taps rejected','raw registered Y/B plus complex-tap independent stamp','tap/phase/transformer/duplicate/reference mutations','verified_for_registered_numeric_cases; physical_inventory_unqualified'),
 ('Bij<=0 and Mij<=0 for i!=j','symmetric Z class; SPD alone insufficient','all reconstructed offdiagonals','SPD [[1,4/5],[4/5,1]] and asymmetric mutation','verified_for_registered_numeric_cases'),
 ('Lee>0 for ordinary PSD equivalence; Lee>=0 plus Range for generalized Schur','algebraic inverse is not PSD proof; slack is not grounding','positive passive Laplacian Schur; per-state spectra','indefinite Schur-positive matrix and failed Range','verified_for_registered_numeric_cases; universal_domain_not_certified'),
 ('B=B^T>0; Z=B^-1>=0','inverse-positive matrix before M0/M1 reasoning','per-state numpy inverse signs; exact M1 inverse order','non-Z SPD inverse-negative exact counterexample','verified_for_registered_numeric_cases'),
 ('G1: M*1>=0; G2: M*r>=0, fixed r>0','same buses/time/scenario/alpha/base','all raw row sums; G2(1)=G1; generated linear constraints','both fixed-G2 nonimplications and index/support checks','verified_for_registered_numeric_cases'),
 ('B=B0+diag(bfix+sum(mu_str*bblock*n_on))','fixed topology/retained sources/exogenous coefficients/common bases','new raw native-MVA/reactance source stamp','fixed inner voltage versus free zero-current inner node','algebra_verified_for_registered_cases; physical_sources_unqualified'),
 ('p_i=sum_GFL(mu_fl*Pblock_MW/Sbase*n_on); S=diag(p)>=0','online nameplate, connection versus resource, one conversion','raw GFL class and bus mapping; bounds and no epsilon support','negative exposure; installed/online/dispatch/current separated','verified_for_registered_numeric_cases; current_capability_missing'),
 ('RSOC(qij,qji,sqrt(2)*mij); M=sum(edge PSD)+diag(d), d>=0','one signed edge per nonzero i<j; symmetric Z exactness domain','actual MOI cones; every generated edge; 18 fresh fixed solves','missing/duplicate edge, wrong sqrt2, missing residue, lost sign; non-Z PSD','equation_verified_for_registered_cases; native_solver_unqualified'),
 ('Bzz>=0; (I-Bzz*pinv(Bzz))*Bza=0; support Schur without epsilon','finite GEV only on valid zero block/range; S=0 undefined gamma','ordinary/singular valid support and all-zero exposure','diag(2,-1) pencil finite 2 but Rayleigh inf=-infinity; range failure','verified_for_registered_numeric_cases_and_boundary_fixtures'),
 ('rebuild Y,B0,B,p,S,M,Zp,G3,costs from raw data and decisions','independent Python from immutable raw data; runtime export consistency distinct','all 124 metric IDs and CSV/JSON; 9 full witnesses; 8 actual CLI actions','3 original wrong units corrected; negative CLI guards; failures preserved','accepted_for_registered_numeric_cases_after_metadata_fix; full_release_blocked')]
ledger=[]
for i,(eq,domain,pos,neg,status) in enumerate(preds,1):
    pid=f'P{i:03d}'
    ledger.append(dict(id=f'P-C2A-{i:03d}',exact_expected_equation=eq,theorem_domain=domain,original_sha=ORIGINAL,code_file_line=src[pid],raw_fixture_sha256=json.dumps(raws,sort_keys=True),own_reference_oracle_sha256=h(O/'independent_reference_oracle.py'),positive_case=pos,adversarial_case=neg,reconstructable_numeric_outputs='oracle_results.json; independent_matrices_B_p_S_M_Zp_G3.json; independent_moi_results.json; independent_metric_results.json; integer_global_bounds_and_objective_audit.json',residual=f'raw model max={matrix["maximum_model_matrix_difference"]}; exact rational residual=0',tolerance='rational exact; matrix/constraint 1e-7 with recorded scaling; currency residual separately recorded',validity_domain=domain,actual_result=status,confidence='high for executed numerical domain; no universal physical/source claim',status=status,fix_owner='EXEC-UNIT-001 metadata only' if i==10 else 'none; external physical/source owner where stated'))
csvout('predicate_P001_P010_evidence_ledger.csv',ledger)
theorems=[
 ('ordinary elimination / PSD Schur','C invertible: Schur algebra; PSD equivalence needs C>0','17.1','P003','invertible_not_PD_Schur; domain_mutations','valid_under_domain; no universal PD gate in reduced_strength'),
 ('parallel sum','D-D(N+D)^-1D=(N^-1+D^-1)^-1','17.3',None,'parallel_sum','theorem_only_not_encoded'),
 ('historical sign duality','original source-symbol mapping unavailable','17.3',None,'source_boundary; primary source qualification','historical_mapping_unresolved; theorem_only_not_encoded'),
 ('zero-exposure elimination','Baa-Baz*Bzz^-1*Bza or pinv plus Range','17.4','P009','valid/invalid singular support MOI tests','verified_for_registered_cases'),
 ('positive exposure GEV / G0','lambda_min(S^-1/2 B S^-1/2)>=alpha iff B-alpha*S>=0','19','P008','positive analytic PSD; new_positive','verified_for_registered_cases'),
 ('singular exposure GEV','PSD zero block plus Range; no gamma for S=0','19','P009','singular_exposure_negative_zero_block; range mutation','verified_for_registered_cases; amendment not ratified'),
 ('local rank-one equivalence','1/(Zii*pi)>=alpha iff B-alpha*pi*ei*ei^T>=0','20','P004','LOCAL_not_G0; all local rank-one metrics','verified_for_registered_cases'),
 ('G0 implies LOCAL','B-alpha*S>=0 implies each rank-one condition','20','P004','G0_not_M0; rank-one fixture','valid_under_domain; metric implementation checked'),
 ('M0 implies LOCAL','Z>=0,p>=0: Zp>=diag(Z)*p','20','P004','M0_not_G1; inverse-positive fixture','valid_under_domain; metric implementation checked'),
 ('G0 does not imply M0','B=[[1,-1/2],[-1/2,1]], p=(1/4,2/3)','20','P004','G0_not_M0: Zp=(7/9,19/18)','exact_counterexample_recomputed'),
 ('G1 implies G0','M*1>=0 for symmetric Z matrix','21','P005','G1/G2 cases; exact toy enumeration','verified_for_registered_cases'),
 ('G1 implies M0','B*1>=alpha*p; multiply by Z>=0','21','P005','raw row/inverse metrics; exact toy','valid_under_inverse_positive_domain'),
 ('fixed G2 implies G0','M*r>=0, fixed r>0','21','P005','both fixed G2 counterexamples','verified_for_registered_cases'),
 ('G2(1)=G1','M*r with r=1','21','P005','full regression and fresh identity formulation','verified_for_registered_cases'),
 ('G1 versus arbitrary G2 incomparable','two 2x2 fixed-r counterexamples','21','P005','G1_not_G2; G2_not_G1','exact_counterexamples_recomputed'),
 ('fixed G2 witness lies in closed SDD','qij=-mij*rj/ri; diagonal budget=(Mr)i/ri','22','P008','positive scaling / edge decomposition fixtures','valid_under_domain; executable witness checked'),
 ('G3 implies G0','sum embedded edge PSD plus nonnegative diagonal','22','P008','actual MOI products/budgets/reconstruction','verified_for_registered_cases'),
 ('closed SDD for singular/reducible PSD Z','block positive scaling including positive null vector and isolated zero rows','22','P008','laplacian_zero_row; singular_reducible_zero','valid_under_stated_theorem; boundary execution passed'),
 ('complete project G3','each nonzero signed i<j once plus all residuals','22','P008','edge mutations and actual MOI extraction','verified_for_registered_cases'),
 ('G0 iff G3 conditional','symmetric Z and complete closed SDD representation','22','P008','non_Z_PSD rejected; 9 G0/G3 fixed case pairs','equations_verified; solver_global_optima_not_universally_certified'),
 ('M1 inverse ordering','B>=Bmin ordered nonsingular M matrices implies Z<=inv(Bmin)','23','P004','M1_order; enforced minimum original tests','verified_for_registered_cases_and_positive_fixture'),
 ('M1 implies M0','inv(Bmin)*p<=1/alpha plus enforced B>=Bmin','23','P004','positive M1 fixture; rejected unenforced minimum','valid_under_domain; nine infeasible M1 cases not M0 rejection'),
 ('M2 implies G1','W>=0,diag(W)=1,p>=0 implies Wp>=p','23','P005','independent Wp and row metric checks','verified_for_registered_cases'),
 ('M2 implies G1 implies M0','combine row inequality and inverse positivity','23','P005','exact toy cost ordering and raw metrics','valid_under_domain; proposed extension to G0 remains nonnormative'),
 ('Woodbury identity','inv(A+UCV)=inv(A)-inv(A)U inv(inv(C)+V inv(A)U)V inv(A)','24','P004','Woodbury_Neumann_exact','identity_recomputed; exploratory_not_planning_constraint'),
 ('unbounded first-order inverse not safe','no global one-sided guarantee without error domain','24','P004','uncontrolled_inverse_false_acceptance','counterexample_recomputed; theorem_only_safety_exclusion'),
 ('Neumann convergence','rho(inv(A)*Delta)<1; induced norm<1 sufficient','24','P004','Woodbury_Neumann_exact; outside_Neumann_norm_region','verified_examples_and_domain_exclusion'),
 ('finite Neumann remainder','R=(-E)^(m+1)*(I+E)^-1*inv(A); norm bound q^(m+1)/(1-q)*norm(inv(A))','24','P004','exact rational remainder plus actual metric errors/bounds','exact_identity_and_registered_values_verified; no one-sided certificate')]
theoremrows=[]
science_lines=(R/'science_source_snapshots/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md').read_text(encoding='utf-8').splitlines()
for i,(title,eq,sec,pred,oracle,status) in enumerate(theorems,1):
    theoremrows.append(dict(id=f'T-C2A-{i:03d}',theorem=title,expected_equation=eq,primary_source=f'scientific_report/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md section {sec}@{SCI}',domain='primary theorem assumptions retained; see theorem and predicate ledger',code_file_line='theorem_only_not_encoded' if pred is None else src[pred],positive_negative_oracle=oracle,implementation_deviation='none confirmed in registered mathematical domain; source physical qualification separate',theorem_status=status,release_decision='scoped numerical evidence; no science owner ratification or general solver release'))
    if i>=25:theoremrows[-1]['code_file_line']=code('src/core/paper_a_diagnostics.jl','function inverse_updates')
    if i==5:theoremrows[-1]['code_file_line']=code('src/core/paper_a_formulations.jl','if f isa ExactPSDGSCR')
    if i in (21,22):theoremrows[-1]['code_file_line']=code('src/core/paper_a_formulations.jl','elseif f isa InverseBoundGSCR')
    sl=next(k for k,l in enumerate(science_lines,1) if k>250 and f'T-C2A-{i:03d}' in l)
    theoremrows[-1]['primary_source']=f'docs/reports/C2_constraints/C2A_voltage_stability/scientific_report/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md:{sl}@{SCI}; section {sec}'
csvout('theorem_T001_T028_equation_to_code_ledger.csv',theoremrows)
gates=f'''original_ap3_sha: {ORIGINAL}
existing_review_sha_claimed: 29192398bc7819a533b1e436c7f176b8dadb56e4
existing_review_sha_at_start: {REVIEW}
metadata_fix_code_sha: {FIX}
proposed_science_amendment_blob: fba4802ecabade61a752833a71106a5bda4ce78f
scientific_release_adjudication: approve_for_owner_ratification
owner_ratification: pending
science_amendment_approved: false
implementation_equation_match: accepted_for_registered_cases
independent_numerical_replay: partial
native_G3_MISOCP: numerical_inconclusive
integer_globality: partial
integer_bound_consistency: numerical_tolerance_crossings_no_rigorous_interval
corrected_code_independent_reaudit: not_applicable
correction_scope: three_export_units_only_no_mathematical_change
independent_implementation_adjudication: accepted_for_registered_cases
independent_A3_5_accepted: false
A3_closed: false
AP4_ready: false
empirical_study_ready: false
executable_closure_verdict: blocked_by_solver_or_data
'''
write('release_gates.yaml',gates)
write('unresolved_blockers.yaml',f'''original_ap3_sha: {ORIGINAL}
blockers:
  - id: B1
    severity: blocking
    status: reproduced_solver_path_false_infeasibility
    evidence: b1_exact_native_result.json; b1_exact_full_witness_verification.json; b1_bridged_full_witness_check.json
    owner: numerical_solver_qualification
  - id: INTEGER_GLOBALITY
    severity: blocking
    status: nine_feasible_case_pairs_verified_but_no_independent_rigorous_global_dual_certificate; eight_historical_LB_claims_exceed_new_feasible_UB_by_small_numerical_amount
  - id: PHYSICAL_SOURCE_AND_PASSIVE_INVENTORY
    severity: blocking
    status: real_physics_unverified; strict_network_gate_rejects_registered_parametric_inputs
    missing: fixed_shunt_inventory; baseline_source_accounting; grounding_reference; OEM_source_filter_current_limit_validation
  - id: EMPIRICAL_COST_TIME_DATA
    severity: blocking
    status: conditional_parametric_illustration_only_not_annual_representative
  - id: OWNER_RATIFICATION
    severity: blocking
    status: exact_amendment_owner_ratification_pending
resolved:
  - id: EXEC-UNIT-001
    severity: minor
    status: corrected_and_reexport_validated
    code_sha: {FIX}
nonproduction_runtime_limits:
  - Clarabel_constant_singular_PSD_chordal_index_error_attempt01; independent_boundary_replay_disables_chordal_decomposition
  - Gurobi_license_expired_2026-10-12
  - MOSEK_license_expired_1001
''')
js('baseline_vs_optional_fix_git_manifest.json',dict(original_ap3_sha=ORIGINAL,claimed_review_sha='29192398bc7819a533b1e436c7f176b8dadb56e4',actual_review_start_sha=REVIEW,review_advancement='one additive macro prompt only',fix_code_sha=FIX,fix_parent=REVIEW,branch='fix/paper-a-a3-5-executable-closure-v1',production_change=['scripts/paper_a/AP3Pipeline.jl: metric_unit; exactly three unit mappings'],scientific_or_feasible_set_change=False,substantial_math_fix=False,second_independent_acceptance_triggered=False,protected_repositories_read_only=['research-map','PyPSA2MatpowerX'],baseline_detached_worktree=str(B)))
integer_table='\n'.join(f'| {x["case_id"]} | {x["original_reference_lower_claim"]:.8f} | {x["feasible_cost_upper"]:.8f} | {x["signed_reference_gap"]:.8g} | {x["G0_G3_fixed_cost_difference"]:.5g} |' for x in integer)
exec_table='\n'.join(f'| {x["id"]} | {x["exit_code"]} | {x["started_utc"]} | {x["ended_utc"]} |' for x in execution)
metric_table='\n'.join(f'| {x["label"]} | {x["metric_ids"]} | {x["records"]} | {x["csv_roundtrip"]} |' for x in metrics['roundtrips'])
write('g3_native_misocp_and_edge_completeness.md',f'''# G3: Gleichung und native Runtime getrennt

Original: `{ORIGINAL}`. Im exakten nativen Repro wird die originale `AP3Pipeline.solve!` ohne mathematischen Patch verwendet; ein Optimize-Hook schaltet ausschließlich die Protokollierung ein.

Pajarito-Termination: **{native['termination']}**, Primalstatus `{native['primal_status']}`. Der frische vollständige Witness erfüllt dagegen dasselbe serialisierte Integer-Modell einschließlich ursprünglicher Bounds, Integerrestriktionen und sämtlicher Objective-Rebase-Gleichungen mit maximaler Verletzung **{fullw['max_violation_including_integer_and_rebase_constraints']:.12g}**. Zusätzlich wurde der Punkt durch die tatsächliche MOI-Optimizer-Indexabbildung in Pajaritos Daten nach Bridging übertragen: lineare Gleichungen **{bridge['linear_equality_residual']:.12g}**, maximaler Kegelabstand **{bridge['maximum_bridged_cone_distance']:.12g}**. Native Infeasibilität ist damit für genau diesen Fall widerlegt.

Die tatsächlichen MOI-RSOC-Vektoren wurden ausgelesen: `(qij,qji,sqrt(2)*mij)`, beide q nichtnegativ, jede ungerichtete Nichtnullkante einmal, sämtliche Knotenbudgets. Die neue analytische MOI-Suite besteht 42/42; auch singuläre/reduzible Nullzeilen und Nicht-Z-PSD sind enthalten. Fehlende/duplizierte Kante, falscher Faktor, Verlust des Offdiagonalzeichens und fehlender Residualterm sind separate Mutationen.

Die Grenze liegt im numerischen OA-/MIP-/Conic-Solverpfad. Eine allgemeine Fehlerzuweisung an eine einzelne Bibliothek oder einen bestimmten Cut ist nicht abschließend bewiesen. `b1_generated_OA_model.mof.json`, `b1_bridged_conic_relaxation.mof.json` und vollständige Logs sind erhalten. Eine Variante mit geänderter positiver Objective-Skalierung liefert OPTIMAL mit vollständigem Primalcheck; andere geringfügig abweichende OA-Toleranzen liefern ITERATION_LIMIT. Das ist Sensitivitätsnachweis, keine allgemeine Reparatur oder Solverqualifikation.

Gurobi-Test: Error 10009, Lizenzablauf 2026-10-12. MOSEK 11.0.29 liest den echten CBF-Integer-Kegel-Export (1353 Integer), endet aber mit 1001/MSK_RES_ERR_LICENSE_EXPIRED. Beide Versuche sind tatsächlich ausgeführt und protokolliert. Native Zuverlässigkeit bleibt `numerical_inconclusive`.
''')
write('metrics_124_cli_8_replay.md',f'''# Metriken und CLI-Replay

| Datenstrom | IDs | JSON-Zeilen | geprüfte CSV-Zeilen |
|---|---:|---:|---:|
{metric_table}

Alle 124 IDs haben einen separaten Eintrag im `independent_metric_results.json`. Für mathematische/physische/wirtschaftliche Größen werden Rohdaten und Entscheidungen in Python/NumPy neu ausgewertet. G3-q aus tatsächlich gelösten Modellen sind Witness-Daten, deren Kegelprodukte, signierte Rekonstruktion und Restbudgets unabhängig geprüft werden. Eigenvektoren werden über ihren Unterraum statt ihr Vorzeichen verglichen. Laufzeit-/Solverattribute sind Exportkonsistenzchecks; keine unabhängig erneute Messung historischer Zeiten. Ein Metrik-Wert mit Status unzulässig, undefiniert oder fehlend wird nicht in einen PASS der physikalischen Domäne umgedeutet.

Die acht echten CLI-Aktionen sind `run_formulation_suite`, `reconstruct_strength_matrices`, `evaluate_strength_metrics`, `verify_certificates`, `compare_formulations`, `assess_planning_results`, `benchmark_conic_scaling`, `export_paper_a_evidence`. Frische Ausgabepfade, tatsächliche Argumente und Prozesscodes stehen in `execution.json` und im Reproduktionsmanifest. Exit 0 der Suite bedeutet nicht, dass jeder Solverlauf optimal ist: {dict(counts)}.

Die Exportkorrektur betrifft ausschließlich die Einheit von `A.connection_violation`, `B.G3_edges_complete`, `B.G3_valid`. 4/4 fokussierte Tests bestanden. Der erneute vollständige Metrikexport am Fix-SHA wird zeilenweise gegen den Originalexport geprüft; einzig diese Einheiten und die provenance-bedingte AP3_SHA dürfen sich ändern. Originale bleiben erhalten. Alle negativen CLI-Prozesse (unbekannte Aktion, fehlende Eingabe, bestehender Output) müssen ungleich 0 enden.
''')
write('independent_executable_closure_report.md',f'''# Paper A — A3.5-EXEC: unabhängiger ausführbarer Abschlussbericht

Datum: 20.10.2026. **Abschlussstatus: `blocked_by_solver_or_data`.** Die geprüften Gleichungen sind für die registrierten numerischen Fälle nachvollzogen; vollständige wissenschaftliche A3-/AP4-Freigabe ist nicht erteilt.

## 1. Autorität, SHA und Unabhängigkeit

Verbindlicher Makroauftrag: FlexPlan `{REVIEW}`. Unverändertes AP3-Prüfziel: **`{ORIGINAL}`**. Der gemeldete Revieweingang `29192398bc7819a533b1e436c7f176b8dadb56e4` ist direkter Parent des tatsächlichen Reviewheads; hinzu kam ausschließlich der Makroauftrag. Keine stille Baselinesubstitution. Neuer sauberer detached Worktree `{B}`. Die bereits vorhandenen AP2-/AP3-/Strang-B-Arbeitsverzeichnisse einschließlich untracked `audit/` blieben erhalten.

Wissenschaft: research-map/main `{SCI}`, Ursprungsfreeze `2c2fce769b2ed6ffd4f1ced60c0798776acccc93`, Paper-A-Scope `672a61c95525bf1d7a03cf745a754a15a23ce78b`, SCIENCE/FINAL `2badb9a90a8d3c1d4a33accee640b295de1e33a1`. Das vorgeschlagene Amendment am Commit `5ceb19a6faf4e7c7e797a737ed5b449f9e2db609`, Blob `fba4802ecabade61a752833a71106a5bda4ce78f`, bleibt **nicht ratifiziert**. Acht bytegenaue Quellensnapshots und ihre Git-/SHA256-Identitäten stehen in `science_source_manifest.json`.

Producer: `b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c`, numerische Daten exakt aus Git-Archiv von `3b8fdb01d931225edc5f8fe1e2c200d0da288a09`. Producer und research-map wurden nur gelesen; Fetch änderte ausschließlich lokale Git-Objekt-/Remotereferenzdaten. Originale Wissenschaft, Producerdaten, historische Outputs und Original-AP3-Branch wurden nicht geändert.

## 2. Specification Gate, Wiederverwendung und Änderung

`SPECIFICATION_READY`: Gleichungen, Domänen, Pflichtgegenfälle, Prüfgrenzen und Freigaberechte sind durch den Makroauftrag bestimmt. Produktionsaufbau, AP1-Import, AP2 affine Matrizen, UC/Storage, Ziele, Solveradapter und CLI wurden wiederverwendet. Die neue unabhängige Referenzberechnung verwendet keine `PaperADiagnostics`-/`AP3Pipeline`-Berechnungen als Oracle. Diese Routinen dienen ausschließlich zum Bau des echten Prüfobjekts oder als Vergleichsziel.

`pre_fix_original_adjudication.md` wurde vor der Produktionskorrektur geschrieben. EXEC-UNIT-001 bestätigt drei falsche Exporteinheiten. Kontrollierte einzige Fixbranch: `fix/paper-a-a3-5-executable-closure-v1`, Parent `{REVIEW}`, Codekorrektur **`{FIX}`**. Diff in Produktionscode: zwei neue Zuordnungszeilen in `metric_unit`; drei IDs korrigiert. Keine Gleichung, zulässige Menge, Solverstrategie, Datenannahme oder Zielfunktion wurde geändert. Eine zweite personell unabhängige mathematische Abnahme eigener substanzieller Codeänderungen ist daher hier nicht ausgelöst. Die allgemeine Freigabe bleibt aus anderen Gründen false.

## 3. Tatsächlich ausgeführte Validierung

Julia **1.10.11**, Manifestformat 2.0. `Pkg.instantiate()` war erfolgreich; getrackte Project-/Manifestdateien und Baselinesourcen blieben bytegleich. Versionen aller Pakete stehen in `environment.log` und den Laufprovenienzen. CPU/Threads/BLAS in `runtime_capabilities.json`. Unabhängige Pythonumgebung: SymPy 1.14.0, NumPy 2.5.4, isoliert im Scratchbereich.

* Vollregression unveränderter Produktionscode: **6087/6087**, Exit 0. Bytegleiche Testkopie im Scratchverzeichnis verhindert Überschreiben historischer Reports.
* Gespeicherte Originalevidenz: **4108/4108**, Exit 0; vorab verlustfrei extrahierte Metrikarchive.
* Neue eigenständige MOI-/Grenz-/Mutationssuite: **42/42**; zusätzliche rohe Domänenmutationen: **16/16**.
* Zusätzlicher unabhängiger Koeffizientenvergleich tatsächlicher G1/G2/M1/M2-Constraints: **34/34**.
* Drei Einheitenkorrekturen: **4/4** fokussierte Tests; vollständiger Exportvergleich separat.
* Frische Formulierungssuite: **{len(runs)} Läufe**, tatsächliche Statusverteilung **{dict(counts)}**. Keine früheren PASS-Zahlen übernommen.
* 8 Größen-/Formulierungsbenchmarks für G0/G3, Größen 2/4/8/16; tatsächliche Ergebnisse in `benchmark.json`.
* AP1-Synthetic-3/6/24-, Parameter-/Netz- und negative historische Producerprüfungen sind durch echte Prozesse bzw. die Vollsuite erfasst; Prozessliste unten.
* Zusätzliche explizite AP1-/Parameter-/Netzprüfungen: **51/51**, **291/291**, **54/54**.

| Prozess | Exit | Start UTC | Ende UTC |
|---|---:|---|---|
{exec_table}

Alle eigenen Fehlversuche bleiben protokolliert. Insbesondere: ein zunächst falsch verwendeter JuMP-`has_values`-Check im Prüfskript wurde durch `primal_status==FEASIBLE_POINT` ersetzt; Infeasibilitätszertifikate sind keine zulässigen Punkte. Ein Clarabel-Chordal-Indexfehler auf einer konstanten singulären PSD-Matrix ist erhalten; die eigenständige Grenzwiederholung deaktiviert dafür die Chordal-Zerlegung. Die Produktionsbaseline wurde dabei nicht gepatcht. Ausdrücklich kein PASS für fehlgeschlagene Versuche.

## 4. Unabhängige Mathematik und P001–P010

Die neuen exakten Rechnungen benutzen rationale Hauptminoren, Inversen und Schur-/Woodbury-Identitäten; die getrennten Julia-Läufe erzeugen tatsächliche JuMP/MOI-Modelle. Das Rationalorakel bestätigt unter anderem:

* G0⇏M0: `B=[[1,-1/2],[-1/2,1]]`, `p=(1/4,2/3)`, `Zp=(7/9,19/18)`, PSD-Randfall.
* M0⇏G1: `B=[[2,-1],[-1,2]]`, `p=(11/10,1/20)`, `Zp=(3/4,2/5)`, erste Zeile negativ.
* SPD ohne Inverspositivität: `B=[[1,4/5],[4/5,1]]`, `p=(1,1)`, `Zp=(5/9,5/9)`, aber `B-S` indefinit.
* LOCAL⇏G0; beide G1/fixed-G2-Nichtimplikationen; Nicht-Z-PSD ist kein G3-Äquivalenzfall.
* Schur positiv bei indefiniter Gesamtmatrix; Pseudoinverse ohne Range falsch; singuläre passive Laplaceklasse und isolierte Nullzeile.
* `B=diag(2,-1), S=diag(1,0)`: formaler endlicher Eigenwert 2, Rayleigh-Infimum −∞. `S=0`: kein endliches gamma; G0 bleibt Matrixprüfung.
* Quelle mit festem internem Phasor ergibt terminal `Bnet+b`; freier Nullstrom-Innenknoten ergibt nach Schur `Bnet`.
* Nichtkommutative Parallel-Summenidentität, M1-Inversenordnung, exaktes Woodbury, endlicher Neumannrest samt Normgrenze und ungültiger Trust-Region-Außenfall.
* Neuer positiver Rationalfall `B=[[17/5,-2/5],[-2/5,11/5]], p=(3/10,7/20)`. Zusätzlich vollständige **81-Zuweisungen-Rationalenumeration** eines neuen Zweiregionenfalls mit exakter Kostenordnung. Das ist ein eigener kleiner globaler Nachweis, keine Zertifizierung der neun Producerfälle.

Alle zehn P-Zeilen enthalten getrennte Sollgleichung, Domäne, Code `file:line@sha`, Rohdaten-/Oraclehashes, positive/negative Fälle, Residuen und Entscheidung. Alle 28 T-IDs besitzen echte eigene Zeilen im Theoremlog. T002 wird algebraisch getestet, ist aber kein gesonderter Produktionsalgorithmus. T003-Historienmapping bleibt ausdrücklich ungelöst. Theoremgültigkeit, konkrete Ausführung und Normstatus werden nicht gleichgesetzt.

Unabhängige gesamte Rekonstruktion: **{matrix['snapshots']} Zustände**, **{matrix['solutions']} Lösungen**, maximale Modellmatrixabweichung **{matrix['maximum_model_matrix_difference']:.12g}**. Keine künstliche Slack-Erdung, keine Epsilon-Exposition. Transformatoren/komplexe Taps werden separat gestempelt und die nicht unterstützten Produktionsfälle tatsächlich abgewiesen. Die registrierten Producerdaten führen weiterhin `fixed_shunt_inventory_unverified`, `baseline_source_accounting_unverified`, `grounding_reference_unverified`: der strikte Netzaufruf weist diese Eingaben ab; nur der deklarierte parametrische Diagnosepfad erlaubt sie. Das beschränkt die physische Abnahme.

Die vorgeschlagene Kette M2⇒G1⇒M0⇒G0 und G0⇔G3 wird nur auf gleicher symmetrischer inverspositiver bzw. vollständiger Z-Domäne verwendet. M0⇒G0 ist als bedingter mathematischer Satz geprüft; damit wird das Amendment nicht normativ aktiviert. Kein M1-INFEASIBLE⇒M0-INFEASIBLE und keine allgemeine M1/G1-Kostenordnung.

## 5. Native G3 und B1

Der unveränderte exakte Solvepfad liefert für `reference_24snap` **{native['termination']}**. Derselbe serialisierte Original-MISOCP besitzt den vollständig überprüften Witness mit maximaler Constraint-Verletzung **{fullw['max_violation_including_integer_and_rebase_constraints']:.12g}** einschließlich Integerbedingungen und Rebase-Gleichungen. Nach tatsächlichem Bridging beträgt der größte Kegelabstand **{bridge['maximum_bridged_cone_distance']:.12g}**. Damit ist für diese Instanz der Infeasibilitätsbefund des Solverpfades falsch; ein Modell-Infeasibilitätsbeweis liegt nicht vor.

Rohlogs und erzeugte native/OA-/Relaxationsmodelle sind erhalten. Die konkrete interne Ursache innerhalb OA-Schnitten, LP-Numerik und Conic-Integration ist nicht abschließend isoliert. Eine positive Objective-Skalierungsvariante löst den Fall numerisch, begründet aber keine generelle Qualifikation oder automatische Produktionsänderung. Gurobi ist installiert, scheitert jedoch tatsächlich an Error 10009 (Lizenzablauf 2026-10-12); MOSEK 11.0.29 liest das echte Integer-CBF, scheitert an 1001/LICENSE_EXPIRED. `native_G3_MISOCP=numerical_inconclusive` bleibt offen.

## 6. Neun Integerreferenzen und Geldkoordinaten

Alle neun Fälle wurden mit vollständig rekonstruierten Integerzuweisungen in neuen G0- und G3-Modellen kontinuierlich nachgelöst. Alle Constraints, UC-/Storage-/Powerflow-Variablen und Integer-/Domainbounds sind geprüft, Kosten aus Rohpreisen, Dauer und Ereignisgewichten neu berechnet. Zur Auswahl der Zuweisungen wurden die früheren billigsten Witnessdateien nur als Seeds verwendet; deren SHA und sämtliche neue Prüfungen sind verzeichnet. Frühere PASS-Flags wurden nicht übernommen.

Die Tabelle zeigt den historischen **Solver-Untergrenzenanspruch** und die frisch unabhängig nachgerechnete zulässige Obergrenze. Die Differenz bleibt vorzeichenbehaftet; negative numerische Abstände werden nicht durch Absolutbetrag in formale Intervalle verwandelt. **In acht der neun Fälle liegt der historische Untergrenzenanspruch geringfügig über der neuen zulässigen Obergrenze, maximal rund 0.00025504 Währungseinheiten.** Dies ist eine gesonderte Toleranz-/Konsistenzabweichung; ihre Ursache wird nicht ohne weiteren Nachweis ausschließlich Rundung zugeschrieben. Der Anspruch ist ohne eigenständigen belastbaren globalen Dual-/OA-Nachweis **kein mathematisch rigoroses Zertifikat**.

| Fall | historische LB-Behauptung | neue feasible UB | UB−LB | G0/G3 Fixkosten-Differenz |
|---|---:|---:|---:|---:|
{integer_table}

Weitere BASE-LP-Untergrenzen und Kostenkomponenten stehen im JSON. Ein LP-Relaxationsbound ist fallbezogen ein numerischer unterer Bound, kein Ersatz für vollständige Integerenumeration. Die neun großen Suchräume wurden nicht vollständig enumeriert. `integer_globality=partial`. Alle Boundwerte werden in ursprünglicher Geldkoordinate ausgewiesen; positive Skalierung wird rückgerechnet, konstanter Investitionsoffset und zusätzliche Increment-Gleichungen sind explizit geprüft. Größte unabhängig gefundene Objektivabweichung über alle archivierten/frischen ausgewerteten Lösungen: **{matrix['maximum_objective_difference']:.12g}** Währungseinheiten. Diese Residualzahl ist von einem Optimalitätsgap zu unterscheiden.

## 7. Metriken, CLI, Chronologie, Daten

| Datenstrom | IDs | JSON-Zeilen | CSV-Rundlauf |
|---|---:|---:|---:|
{metric_table}

Für alle IDs sind Formel-/Wert-/Null-/Basiskontrollen dokumentiert. Bei Laufzeit-/Solverdaten bedeutet dies attributtreuen Export; tatsächliche CPUzeiten historischer Läufe sind nicht erneut unabhängig messbar. Dualexporte sind zusätzlich an den neuen analytischen MOI-Fällen auf Kegelmitgliedschaft und Komplementarität geprüft; für historische Solves ohne vollständige Dualvektoren bleibt die unabhängige globale Dualprüfung eingeschränkt. Der vollständige Fixexport unterscheidet sich nur in den drei Einheiten und dem Versionsfeld.

Alle acht CLI-Aktionen werden in neuen Pfaden real ausgeführt, einschließlich Export mit SHA-Nachprüfung. Ungültige Aktion, fehlender Input und vorhandener Output werden negativ getestet. Nichtoptimale Solverstatus bleiben sichtbar. Einheiten von Kegelprodukten (`pu_admittance_squared`), Blockcounts und Währung werden unterschieden.

Producer-3/6/24-Snapshotdaten waren verfügbar. 24×3 h = **72 Stunden**. Energiegewicht `delta_t*representative_repetitions*scenario_probability` und Ereignisgewicht `event_repetitions*scenario_probability` werden getrennt nachgerechnet. CAPEX wird genau mit deklarierter Jahres-/Horizontfraktion angewandt; Storage-P+E-Preise bleiben ihre deklarierte parametrische Referenz, keine durch diesen Audit validierten OEM-/Studienkosten. `a_conn` und `a_res` bleiben getrennt. Installed-, online-nameplate-, Net-Dispatch- und Current-Capability-Exposition werden nicht vertauscht. Fehlendes S_I und externe Fault-/SCR-Normen bleiben explizit fehlend/nicht vergleichbar. Keine Jahresrepräsentativität der kurzen Beispielzeiträume.

## 8. Evidenzintegrität, Reproduktion und Übergabe

**14/14 historische ZIPs** vollständig auf CRC und enthaltene SHA256 geprüft; **1060/1060** Einträge des historischen Evidenzindex stimmen in Hash und Größe (fehlende entpackte Originaldateien werden durch die bytegleichen ZIP-Einträge verifiziert). Keine Stichprobenaussage. Rohdaten-, Quellen-, Code-, Paket-/Manifest-, Log- und neue Outputhashes bilden die Reproduktionskette. Große neue Metrik-/MOI-/Witnessdateien sind verlustfrei archiviert; Archiv- und enthaltene Rohhashes stehen im Reproduktionsmanifest. Keine historischen Archive überschrieben.

Lesereihenfolge: dieser Bericht → `release_gates.yaml` → P-/T-Ledger → `g3_native_misocp_and_edge_completeness.md` → neun Integerfälle → `metrics_124_cli_8_replay.md` → Manifest und ausführbare Oracles. Artefakte sind Ergebnisdaten, keine zusätzlichen fachlichen Autoritäten.

Nachgelagerter unabhängiger Prüfer: Original `{ORIGINAL}` und Metadatenfix `{FIX}` getrennt auschecken; SHA-Manifeste verifizieren; Oracles und genau protokollierte Prozesse wiederholen. Für B1 zuerst `b1_exact_native_repro.jl`, `b1_transfer_full_witness.jl` und die Bridgingprüfung ausführen, danach mit tatsächlich lizenzierter nativer MISOCP-Alternative oder isolierter nachgewiesener Solverreparatur neu qualifizieren. Wissenschaftsowner muss das exakte Amendment separat ratifizieren; Datenowner muss Quellen-/Passivinventar, Zeit-/Kosten-/Studienrepräsentativität qualifizieren. Erst dann können weitergehende Gates neu bewertet werden.

## 9. Abschließende getrennte Entscheidung

Mathematik/Gleichung-zu-Code: **accepted_for_registered_cases**, mit klaren Domänen und historischen ungelösten Quellenbezügen. Original-Metrikexport: drei bestätigte kleine Einheitenfehler, korrigiert. Numerischer Replay: vollständig ausgeführt; Regression und Metrikvergleich bestanden, Solver-/Globalitätsabnahme **partial**. Native G3: **numerical_inconclusive**, falsche Infeasibilität konkret nachgewiesen. Neun Integerfälle: vollständige neue zulässige Witnesspaare und numerische Bounds, **keine rigorose allgemeine Globalitätszertifizierung**. Physik-/Empiriedaten: **unqualified/conditional**.

`science_amendment_approved=false`; `independent_A3_5_accepted=false`; `A3_closed=false`; `AP4_ready=false`; `empirical_study_ready=false`.

**Einziger Schlussstatus: `executable_closure_verdict: blocked_by_solver_or_data`.** Keine PR, kein Merge, Reset, Rebase, Force-Push oder Änderung fremder Branches. Der finale Remotehead wird nach Veröffentlichung gesondert per `git ls-remote` verifiziert.
''')
print('ledgers and report generated')
