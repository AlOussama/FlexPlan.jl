from pathlib import Path
from fractions import Fraction as Q
from collections import Counter
import json,sys,csv,hashlib,zipfile,shutil,subprocess,math,datetime
R=Path(sys.argv[1]);F=Path(sys.argv[2]);A=F/'reports/a3_6/b1_opt_20261020';A.mkdir(parents=True,exist_ok=True)
BASE=Path('D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE');OLD=Path('D:/Projekte/Code/FlexPlan_A35_EXEC_REVIEW/reports/a3_5/executable_closure_20261020')
CODE='910d44122a37d9ed2cca06940740b46706c73d40'
def load(p):return json.loads(p.read_text())
def save(n,v): (A/n).write_text(json.dumps(v,indent=2,ensure_ascii=False),encoding='utf-8')
def md(n,s):(A/n).write_text(s,encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git','-C',str(F),*args],text=True).strip()
initial=load(R/'execution_initial.json');validation=load(R/'execution_fix_validation.json')
assert len(initial)==13 and all(x['exit_code']==0 for x in initial)
assert len(validation)==4 and all(x['exit_code']==0 for x in validation)
assert '6087' in (R/'fix_full_regression.log').read_text() and '4108' in (R/'fix_saved_evidence.log').read_text()
matrix=load(R/'solver_matrix/results.json');stress=load(R/'fix_stress_matrix/results.json');assert len(matrix)==54 and len(stress)==45
proof=load(R/'exact_certificate_verification.json');assert len(proof['cases'])==9 and proof['tests_passed']==171
transforms=load(R/'objective_transform_audit.json');assert len(transforms)==18
fresh=load(R/'integer_fresh/independent_integer_fixed_checks.json');assert len(fresh)==9
historical=load(OLD/'integer_global_bounds_and_objective_audit.json')
costmaps=load(R/'lp_bounds_raw_currency/objective_mappings.json')
filterproof=load(R/'oa_coefficient_filter_forensics.json');minimal=load(R/'tests_new/results.json')
native=[]
for name in ['original_01','original_02','metadata_01']:
    d=R/name
    for phase,dd in [('before',d/'before'),('after',d)]:
        native.append({'run':name,'phase':phase,'model_sha256':sha(dd/'b1_exact_native.mof.json'),'stats':load(dd/'b1_exact_native_result.json')})
    assert load(d/'b1_bridged_full_witness_check.json')['maximum_bridged_cone_distance']<1e-7
assert all(x['model_sha256']=='fcd52695238591d6c6019385d64e4407e1ea480849ca4125e1191b992581ab07' for x in native)
assert all(x['stats']['termination']=='INFEASIBLE' for x in native)
save('b1_original_vs_bridged_vs_oa_stage_evidence.json',{'original_native_repetitions':native,'original_full_witness':{k:v for k,v in load(R/'original_01/b1_exact_full_witness_verification.json').items() if k!='point'},'bridge_check':load(R/'original_01/b1_bridged_full_witness_check.json'),'oa_stage':load(R/'experiments/stages/stage_before.json'),'frozen_oa_runs':load(R/'experiments/stages/frozen_oa_results.json'),'frozen_variants':load(R/'experiments/frozen_variants/results.json'),'coefficient_ingestion_counterexample':filterproof,'minimal_counterexample':minimal['minimal_counterexample_results'],'exact_feasibility_scope':'exact binary rational serialized coefficients; independent rational primal and G0/G3 checks in exact_certificate_verification.json','invalid_trial':'stage_diagnosis integer_fixed_presolve_on used duplicate anonymous names, hence not evidence; index-based fixed_integers_by_index is the valid replacement','IIS_limitation':'MathOptIIS conflict copy is one row and loses the integer trigger; reduced LP alone was feasible to its LP tolerance. The explicit integer-dummy counterexample reproduces the MIP failure.'})
rows=[]
for stage,records in [('pre_fix_registered',matrix),('post_fix_stress',stress)]:
    for x in records:
        s=x['stats'];rows.append({'stage':stage,'case_id':x['case_id'],'formulation':x['formulation'],'configuration':x['mode'],'termination':s['termination'],'primal_status':s['primal_status'],'dual_status':s['dual_status'],'objective_currency_numerical':s.get('objective'),'bound_currency_numerical':s.get('bound'),'positive_objective_divisor':s.get('objective_solver_scaling'),'max_constraint_violation':x.get('max_violation'),'rigorous_solver_bound':False,'repetitions':1,'Julia':'1.10.11','Pajarito':minimal['packages']['Pajarito'],'HiGHS_package':minimal['packages']['HiGHS'],'HiGHS_library':'1.15.1','Clarabel':minimal['packages']['Clarabel'],'settings_source':'registered_solver_matrix.jl' if stage.startswith('pre') else 'fix_stress_matrix.jl'})
for n in native:
    s=n['stats'];rows.append({'stage':'original_native_byte_identical','case_id':'reference_24snap','formulation':'G3','configuration':n['run']+'_'+n['phase'],'termination':s['termination'],'primal_status':s['primal_status'],'dual_status':s['dual_status'],'positive_objective_divisor':s['objective_solver_scaling'],'rigorous_solver_bound':False,'repetitions':1,'Julia':'1.10.11','settings_source':'b1_exact_native_repro.jl and original AP3Pipeline.pajarito_optimizer'})
cols=list(dict.fromkeys(k for r in rows for k in r))
with (A/'b1_solver_reliability_matrix.csv').open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,cols);w.writeheader();w.writerows(rows)
ledger=[];bounds=[]
for p in proof['cases']:
    case=p['case_id'];old=next(x for x in historical if x['case_id']==case);m=next(x for x in costmaps if x['case_id']==case);b=p['lp_bounds_raw_currency'];point=R/'exact_primals'/f'{case}_point.json'
    row={'case_id':case,'raw_case_sha256':m['raw_case_sha256'],'LB_currency_outward':math.nextafter(float(Q(b['LB_exact'])),-math.inf),'UB_currency_outward':math.nextafter(float(Q(b['UB_exact'])),math.inf),'signed_interval_width':b['signed_gap'],'historical_LB_claim':old['original_reference_lower_claim'],'historical_numerical_UB':old['feasible_cost_upper'],'historical_signed_gap':old['signed_reference_gap'],'rigorous_LB':True,'rigorous_UB':True,'global_integer_optimality_proved':False,'full_integer_enumeration':False,'scope':'normalized binary rational MOI constraints; exact binary rational raw-currency objective','lower_origin':'BASE LP relaxation + exact weak-duality certificate','upper_origin':'recovered exact integer point passing G0 and G3 separately','epsilon_LB':'not_used','epsilon_UB':'not_used','point_sha256':sha(point),'certificate_file':f'verified_primal_dual_witnesses.zip:lp_bounds_raw_currency/{case}_exact_LB.json','status':'valid_exact_interval_precision_not_qualified'}
    ledger.append(row);bounds.append({**row,'LB_exact':b['LB_exact'],'UB_exact':b['UB_exact'],'signed_interval_width_exact':b['signed_gap_exact'],'serialized_objective_interval':p['lp_bounds'],'historical_evidence_retained':old,'objective_mapping':m,'feasible_primal_verified':True,'dual_bound_numerically_supported':True,'rigorous_interval_established_for_normalized_model':True,'valid_optimality_interval_at_required_precision_not_established':True,'G0_G3_integer_optima_equality_claimed':False})
with (A/'integer_9cases_proof_ledger.csv').open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,ledger[0].keys());w.writeheader();w.writerows(ledger)
save('integer_9cases_bounds.json',bounds)
save('exact_certificate_verification.json',proof)
save('native_exact_extension_verification.json',load(R/'native_exact_extension_verification.json'))
save('objective_transform_audit.json',transforms)
save('input_sha256_manifest.json',load(R/'input_verification.json'))
md('b1_root_cause_or_limitation.md',f'''# B1: belegtes Ursachenglied und verbleibende Grenze

Das native Originalmodell ist in sechs neuen Aufrufen bytegleich zum EXEC-Modell (`fcd52695238591d6c6019385d64e4407e1ea480849ca4125e1191b992581ab07`). Alle sechs Aufrufe liefern `INFEASIBLE`. Original und Metadatenfix sind hierbei identisch. Die Kegelrelaxation ist `OPTIMAL`. Der unabhängige rationale Primalpunkt erfüllt das serialisierte ursprüngliche G3-Modell und das separate G0-Modell exakt; das betrifft die normalisierten binären Koeffizienten, keine ungerundete physische Instanz.

Im erzeugten OA-Modell liegen zwei Zeilen vollständig unter HiGHS' Standard-Koeffizientenfilter `1e-9`. In der entscheidenden Zeile werden

`4.5830185178677806e-11*x3612 + 4.5830185178677806e-11*x3618 + 1.3046247794859574e-10*x3926 >= 3.025002202302713e-8`

alle Koeffizienten entfernt. Übrig bleibt `0 >= 3.025002202302713e-8`, gegenüber MIP-Feasibility `1e-8`. Der übertragene Originalzeuge erfüllt die unveränderte Zeile mit LHS `3.02627753631434e-8`. Das ist ein konkreter Verlust der zulässigen Menge durch Koeffizientenfilterung im OA/HiGHS-Übergang. Die Logs belegen die gelöschten Werte; reine Objective-Skalierung des bereits erzeugten OA-Modells behebt den Fehler nicht.

Der kleinste neue Gegenfall besitzt diese eine Zeile, drei nichtnegative kontinuierliche Variablen und einen Integer-Dummy in [0,1]. Er liefert mit Standardfilter `INFEASIBLE`, mit `small_matrix_value=1e-12` sowie mit exakt geprüfter Multiplikation der Zeile durch `2^33` jeweils `OPTIMAL`. Eine rationale zulässige Belegung ist x3=RHS/a3, x1=x2=z=0. Die Zweierpotenz-Skalierung ist ausschließlich Diagnose, kein Produktionspatch.

Produktionskorrektur `{CODE}`: eine HiGHS-OA-Option `small_matrix_value=1e-12` im vorhandenen Optimizer. Keine Lockerung der Feasibility-Toleranz. Die Korrektur behebt dieses belegte Ursachenglied. Der native Defaultpfad ohne explizite Kostenskalierung bleibt beim 24-Snapshot-Fall bei `ITERATION_LIMIT`. Die bereits vorhandene BASE-LP-Kostenskalierung ergibt für neun Fälle numerisch `OPTIMAL`; zusätzliche Stressfälle sind im CSV erfasst. Insbesondere bleibt `reference_24snap` bei doppeltem Kostendivisor `ITERATION_LIMIT`. Daher keine robuste native Gesamtqualifikation.

Root-conic-Feasibility, Bridging, eingefrorene OA-LP/MIP-Stufen, korrigierte indexbasierte Integerfixierung und sämtliche Originalconstraint-Residuengruppen sind getrennt archiviert. Die erste namensbasierte Integerfixierung war wegen anonymer OA-Variablen ungültig und ist als Fehlversuch erhalten. Die MathOptIIS-Konfliktkopie allein beweist ohne Integertrigger keine MIP-Infeasibilität.

Die globale exakte Gültigkeit aller floating-point-OA-Schnitte und eine vollständig validierte MIP-Baumuntergrenze sind nicht etabliert. Native OA-Bounds werden deshalb nicht als rigorose LBs eingesetzt. Die neuen rigorosen LBs stammen aus der separat inklusionsgeprüften BASE-LP-Relaxation. Gurobi Error 10009 und MOSEK 1001 wurden frisch reproduziert; alternative kommerzielle Zertifizierung ist durch die abgelaufenen Lizenzen blockiert.
''')
maxdelta=max(abs(x['delta_at_exact_primal_float']) for x in transforms)
md('objective_rebase_derivation.md',f'''# Kostenkoordinate und tatsächlich gespeicherte affine Transformation

Die identische ursprüngliche Minimierungszielfunktion von G0 und G3 besteht aus Investition `K_k*(n_inst-n0)`, Dispatch `baseMVA*pg*Preis*delta_t*representative_repetitions*scenario_probability`, Storage-Entladung analog, Start/Stop `P_block*Ereignispreis*event_repetitions*scenario_probability` sowie den deklarierten einmaligen Termen. 24 Snapshots à 3 h ergeben 72 h. Start/Stop-Ereignisgewichte enthalten keinen zusätzlichen Faktor delta_t. Storage-P/E-Kosten werden über die vorhandenen kombinierten, registrierten CAPEX-Felder übernommen; deren reale Quellenqualifikation wird nicht neu erteilt.

Der tatsächliche `solve!`-Code führt für c>0 und Untergrenze l>0 `z=x-l`, z>=0 ein und ersetzt `c*x` durch `c*z+c*l`. Über exakten reellen Zahlen bleibt C erhalten. Der positive Divisor s ist standardmäßig max(1,max|c_j|) über die vom Code ausgewählten Variablen; in der dokumentierten konditionierten Variante ist s die numerische BASE-LP-Kostenreferenz. Nominal gilt F=C/s und C=s*F. Ein Offset C0 wird nicht stillschweigend abgezogen. Für die allgemeine, hier nicht zusätzlich eingeführte Schreibweise F=s_pos*(C-C0) wäre C=C0+F/s_pos mit s_pos>0. Unter- und Obergrenzen werden in beiden Richtungen mit positivem Faktor transformiert.

Die tatsächlich gespeicherten Float64-Koeffizienten erfüllen die nominale Identität nicht notwendig exakt. `objective_snapshots.jl` erfasst ausschließlich den realen Transformationsaufbau vor dem Optimieren; sein erwarteter Snapshot-Abbruch ist kein Solverlauf und geht in keine Optimalstatistik ein. Nach exakter Elimination jeder Increment-Gleichung liefert `objective_transform_audit.json` für alle neun Fälle und beide Skalierungen:

`s*F_serialized(x,z(x)) = C_emitted(x) + delta0 + sum(delta_j*x_j)`.

Alle delta-Werte sind rationale Ableitungen der tatsächlichen Bits; es gibt keine erfundene Rundungsschranke. Der größte hier an einem exakten Primalpunkt ausgewertete Betrag ist {maxdelta:.12g} Währungseinheiten. Dieser Punktwert ist KEINE globale Fehlerschranke. Ein rigoroser Solver-LB L_F dürfte erst als `s*L_F-max(delta(x))`, ein rigoroser UB U_F als `s*U_F-min(delta(x))` auf C übertragen werden, wenn die jeweiligen globalen delta-Grenzen bewiesen sind. Bloße Multiplikation der numerischen Solvergrenze mit s oder ein relativer Pajarito-Gap genügt dafür nicht.

Die neue Zertifizierung vermeidet diesen Übergang: Sie prüft einerseits C_emitted direkt und berechnet andererseits eine eigene exakte affine Rohkostenfunktion aus den binären Raw-JSON-Werten und den deklarierten Produkten. Nicht expandierbare Assets können unterschiedliche CAPEX-Koeffizienten tragen; ihre Investition ist wegen n_inst=n0 auf der nachgewiesenen Domain exakt null. Diese Terme werden nicht als Milliarden-Kostenfehler interpretiert. Beide Kostenkoordinaten und ihre exakten Differenzen sind archiviert.

Für einen beliebigen zulässigen, vorzeichenrichtigen LP-Multiplikator y wird exakt `r=c-A' y` gebildet. Aus den ursprünglichen linearen Constraints bewiesene Variablenintervalle [l,u] liefern durch schwache Dualität `L=c0+sum(y_i*b_i)+sum(min(r_j*l_j,r_j*u_j))`. Einseitig unbeschränkte Variablen sind nur bei passender Residualrichtung erlaubt; UC-Transitionsmultiplikatoren werden exakt in ihr zulässiges Kostenintervall projiziert. Fehlende erforderliche Bounds würden die Zertifizierung stoppen. Das separate Prüfprogramm verifiziert jede Intervallinferenz, Dualrichtung, Stationaritätsrestkomponente und rationale Boundsumme erneut.

Rationale Primal-Recovery setzt Integerwerte exakt und löst die ausgewählten linearen Gleichungen exakt. Die Auswahl aktiver Zeilen benutzt Float-Seeds, die Annahmeprüfung keine Toleranz. Anschließend werden ALLE Originalconstraints geprüft: lineare Gleichungen/Ungleichungen, Bounds, Integrality, RSOC-Produkte sowie sämtliche G0-Hauptminoren. Zulässige Punkte sind nur nach diesen vollständigen Prüfungen rigorose UBs der deklarierten normalisierten Modelle.

Historische negative UB-LB-Abstände bleiben unverändert. Kein Betrag wird zum positiven Intervall umetikettiert und keine Differenz als epsilon ausgegeben. Die neuen nichtnegativen Intervallbreiten sind exakt abgeleitet; sie behaupten bei breiten Relaxationslücken keine Integeroptimalität.
''')
save('code_changes_and_regression_manifest.json',{'specification_status':'SPECIFICATION_READY','reuse':['AP3Pipeline.prepare/build/solve!/extract','serialized EXEC MOI models and seed witnesses','pinned independent JuMP/MOI and raw-domain regression tools','existing BASE-LP objective conditioning'],'new_components':['exact rational primal recovery','exact LP residual-bound certificates','separate principal-minor/dual/inclusion verifier','coefficient-ingestion forensics and minimal counterexample','stress and objective-transformation diagnostics'],'production_code_sha':CODE,'parent_sha':'e49b64216f82eefda77d6997ed68ed2d12c8ae78','production_diff':git('diff',CODE+'^',CODE,'--','scripts/paper_a/AP3Pipeline.jl'),'source_math_changed':False,'solver_configuration_changed':True,'additional_independent_reaudit_required':True,'self_signed_independent_closure':False,'validation':validation,'new_exact_verifier_tests':171,'new_julia_tests':18,'registered_pre_fix_runs':54,'post_fix_stress_runs':45,'metrics_124_and_cli_8':'pinned A3.5 evidence reused; output/export/metric/bound code unchanged; new solver results are separately reported','not_generalized':['unrounded physical data certification','all-MISOCP reliability','exact validity of every generated floating OA cut','complete MIP tree proof','owner ratification','real-data qualification']})
gates=f'''original_ap3_sha: 485b637cc1998a327206c5929434bd26c6f0be16
a3_5_exec_input_sha: 4d9f346c5fca80e00fd01d96c39a2bac91776ac0
metadata_fix_sha: e1e075626b38b478faf57efe62e557fc94753f00
macro_authority_sha: e49b64216f82eefda77d6997ed68ed2d12c8ae78
production_correction_sha: {CODE}
proposed_science_amendment_blob: fba4802ecabade61a752833a71106a5bda4ce78f
science_amendment_approved: false
owner_ratification: pending
implementation_equation_match: accepted_for_registered_cases
native_G3_MISOCP: numerical_inconclusive
integer_globality: case_specific_partial
a3_6_b1_opt_verdict: correction_ready_for_independent_reaudit
B1_repaired: false
B1_coefficient_filter_cause_reproduced: true
B1_local_solver_option_correction_tested: true
integer_bounds_proved: true
integer_bounds_proved_scope: normalized_binary_rational_models_and_declared_exact_raw_currency_objective
integer_optimality_proved: false
required_precision_qualified_nine: false
rigorous_normalized_intervals: 9
production_correction_independent_reaudit: pending
independent_A3_5_accepted: false
A3_closed: false
AP4_ready: false
empirical_study_ready: false
'''
md('release_gates.yaml',gates)
md('remaining_gates_handoff.md',f'''# Unabhängiger Folgeauftrag und verbleibende Gates

Du bist ein NEUER unabhängig beauftragter Solver-/Integerprüfer. Prüfe Original `485b637cc1998a327206c5929434bd26c6f0be16`, EXEC `4d9f346c5fca80e00fd01d96c39a2bac91776ac0`, Metadatenfix `e1e075626b38b478faf57efe62e557fc94753f00`, Makroauftrag `e49b64216f82eefda77d6997ed68ed2d12c8ae78` und den substanziellen Solveroptionsfix `{CODE}` getrennt. Der hier implementierende Auditor signiert seine eigene Korrektur nicht als unabhängig geschlossen.

Lesereihenfolge: Abschlussbericht → Pre-fix-Befund → Stufen-/Filterevidenz → neun Bound-Zeilen → Kostenableitung → Reproduktions-/SHA-Manifeste → rohe Logs und Programme im ZIP. Verifiziere alle Archiv-/Entryhashes, die exakten Primalpunkte, sämtliche PSD-Hauptminoren, alle LP-Bound-Inferenzen und die Relaxationsinklusion. Vergleiche zusätzlich die beiden tatsächlichen Float64-Objective-Transformationen pro Fall.

B1: Bestätige den Ein-Zeilen-Gegenfall und den Filterverlust im Original-OA. Prüfe die einzelne Option small_matrix_value=1e-12 auf tatsächlich geändertem Code. Neun primär kostenskalierten Fälle sind numerisch lösbar; der doppelte Divisor für reference_24snap bleibt ITERATION_LIMIT. Ohne explizite BASE-LP-Kostenskalierung ist der 24-Snapshot-Defaultpfad ebenfalls nicht zuverlässig. Für weitere Closure ist mindestens eine separat überprüfte Cut-Normalisierung/Skalierung oder eine tatsächlich verfügbare native MISOCP-Alternative nötig; keine bloße Erhöhung der Feasibility-Toleranz und keine Statusumschreibung. Prüfe insbesondere weiterhin gefilterte Koeffizienten unter 1e-12, globale Cut-Gültigkeit und vollständige MIP-Node-/Dualbeweise.

OPT: Die neun neuen Intervalle sind gültig auf der ausdrücklich normalisierten Domain, jedoch mit unterschiedlichen Breiten. Für connectivity_3snap, event_price_3snap und reference_24snap muss eine globale Integeruntergrenze wesentlich stärker als die BASE-LP-Relaxation werden. Notwendig wäre ein vollständig nachprüfbarer Branch-and-bound-Baum mit abgesicherten LP/Kegel-Nodebounds, ein dazu äquivalentes exaktes Zertifikat oder eine tatsächlich vollständige fallbezogene Enumeration. Fixed-integer-SOCP-Optima liefern dafür keinen globalen LB. Auch die sehr schmalen übrigen Intervalle begründen ohne akzeptiertes Präzisionskriterium keine exakte Optimalitätsgleichheit. Die alte 81-Zuweisungen-Enumeration wird nicht übertragen.

Wissenschaftsowner: ausschließlich exaktes Amendment-Blob fba4802ecabade61a752833a71106a5bda4ce78f ratifizieren oder zurückweisen; dieser technische Audit simuliert keine Ratifizierung. Datenowner: reale Quellen-/Passivinventare, Source-Accounting, Erdungsbezug, Kostenpreise/-jahr, Storage-P/E-Basis und zeitliche Repräsentativität qualifizieren. Alle anderen geprüften A3.5-Domänen-/Metrik-/CLI-Belege bleiben mit ihrer ursprünglichen Geltungsgrenze referenziert.

Bis zu den getrennten Abnahmen bleiben A3_closed=false, AP4_ready=false und empirical_study_ready=false. Keine PR, kein Merge, keine Änderung fremder oder historischer Branches.
''')
md('reaudit_prompt.md',(A/'remaining_gates_handoff.md').read_text())
statuscounts=lambda a:dict(Counter(x['stats']['termination'] for x in a))
table='\n'.join(f"| {r['case_id']} | {r['LB_currency_outward']:.9f} | {r['UB_currency_outward']:.9f} | {r['signed_interval_width']:.9g} | {r['historical_signed_gap']:.9g} |" for r in ledger)
md('independent_b1_opt_closure_report.md',f'''# Paper A — A3.6-B1/OPT: unabhängiger technischer Abschlussbericht

20.10.2026. **Einziger Schlussstatus: `correction_ready_for_independent_reaudit`.** Der konkrete native False-Infeasibility-Fehlpfad ist bis zu einer veränderten OA-Ungleichung isoliert und lokal korrigiert. Die robuste native G3-Zuverlässigkeit und die enge globale Integeroptimalität aller neun Fälle sind weiterhin offen. `A3_closed=false`, `AP4_ready=false`.

## 1. Auftrag, Identität und Unabhängigkeit

Autorität ist der verbindliche Makroauftrag `e49b64216f82eefda77d6997ed68ed2d12c8ae78`. Prüfziele bleiben unverändert Original AP3 `485b637cc1998a327206c5929434bd26c6f0be16`, EXEC-Eingang `4d9f346c5fca80e00fd01d96c39a2bac91776ac0` und Exportmetadatenfix `e1e075626b38b478faf57efe62e557fc94753f00`. Zwischen EXEC und Auftragshead liegt nur die neue Auftragsdatei. Branch-/Parent-/Merge-Base-/Remoteprüfungen stehen in der neuen Autoritätsprovenienz. Die Original-AP3-Branch bleibt am gepinnten SHA. Neue einzige Produktionsbranch: `fix/paper-a-a3-6-b1-opt-v1`, Parent e49b642; Korrekturcommit **`{CODE}`**. Ausgangs- und Evidenzcommit werden im Publikationsnachweis getrennt geführt.

Der Audit wurde im neuen Chat unabhängig von AP3-Implementierer und A3.5-EXEC-Auditor ausgeführt. Bestehende Programme und akzeptierte Gleichung-zu-Code-Belege wurden als Werkzeuge/Quellen verwendet; frühere PASS-Flags ersetzen keine neu ausgeführten Prüfungen. Eigene Produktionskorrektur löst ausdrücklich eine weitere personell unabhängige Abnahme aus. Diese steht aus.

research-map bleibt read-only: Freeze 2c2fce769b2ed6ffd4f1ced60c0798776acccc93, Dissertation e8118425adc335a99e85120d943763305f211315, Paper-A-Scope 672a61c95525bf1d7a03cf745a754a15a23ce78b, SCIENCE/FINAL 2badb9a90a8d3c1d4a33accee640b295de1e33a1, vorgeschlagenes Amendment 5ceb19a6faf4e7c7e797a737ed5b449f9e2db609 / Blob fba4802ecabade61a752833a71106a5bda4ce78f, nicht ratifiziert. Producer bleibt read-only: b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c, verwendete Datenhistorie 3b8fdb01d931225edc5f8fe1e2c200d0da288a09.

## 2. Specification Gate, Wiederverwendung und Diff

`SPECIFICATION_READY`: Fälle, Diagnosekette, Validierung, Grenzen und zulässige Terminalzustände sind vorgegeben. Wiederverwendet wurden AP3 prepare/build/solve!/extract, originale MOI-Exports, hashgesicherte Seedzeugen, BASE-LP-Kostenskalierung und die bestehenden tatsächlichen JuMP/MOI-/Domänentests. Neue Komponenten sind eng auf B1/OPT begrenzte Forensik, exakte Primal-Recovery, rationale LP-LB-Zertifikate und ein separater Verifikator.

Produktionsdiff: eine zusätzliche HiGHS-OA-Option `small_matrix_value=1e-12`, mit zwei erklärenden Kommentarzeilen. Keine neue Modellgleichung, Integer-Relaxation, Kostenannahme, Statusmanipulation oder Dependencyänderung. Alle Daten, historischen Archive, fremden Worktrees und untracked AP2-audit-Dateien bleiben erhalten. Keine PR, kein Merge, Rebase, Reset, Force-Push oder Branchlöschung.

## 3. Eingangsidentität und Reproduktion des Widerspruchs

Das EXEC-Archiv wurde vollständig erneut verifiziert: **24.237.795 Bytes**, SHA256 `0ec9969de7c8659bc50d82664556c09515080beb1bcd1e937bb9cc7b8d925993`, **381/381 Einträge** in Hash und Größe korrekt. Jeder verwendete Eingang ist im neuen Inputmanifest gebunden.

Die vorgeschriebene Folge Native → vollständiger Witness-Transfer → Native wurde zweimal am Original und einmal am unveränderten Metadatenfix ausgeführt. **6/6 native Solves: INFEASIBLE/NO_SOLUTION.** Alle sechs Modellbytehashes stimmen mit `fcd52695238591d6c6019385d64e4407e1ea480849ca4125e1191b992581ab07` überein. Das Modell enthält 1353 Integerrestriktionen. Höchste ursprüngliche Witnessverletzung `7.515349001601957e-12`; nach tatsächlichem Bridging Kegelabstand `8.835133427034015e-11`, Gleichungsresidual rund `4.263256414560601e-14`.

Über die Float64-Zeugen hinaus liegt jetzt ein rational rekonstruierter Punkt vor, der alle serialisierten Original-G3-Constraints exakt erfüllt. Dasselbe gilt separat für G0. Damit ist exakte Feasibility der ausdrücklich normalisierten binären Modellkoeffizienten belegt; eine solche Aussage wird nicht auf ungerundete physikalische Quelldaten übertragen.

## 4. Kausale B1-Kette und Korrekturgrenze

Source/JuMP/Bridging führen für den übertragenen Punkt zu konsistenten Modellen. Die kontinuierliche Root-Kegelrelaxation ist OPTIMAL. Der erzeugte OA-MIP wird durch HiGHS' Koeffizientenfilter verändert: In einer gültig erfüllten Zeile mit drei Koeffizienten zwischen 4.58e-11 und 1.30e-10 bleiben nach Filterung keine Variablenterme, aber RHS **3.025002202302713e-8** übrig. Bei MIP-Feasibility 1e-8 wird daraus Infeasibilität. Der neu erzeugte Ein-Zeilen-/Integer-Dummy-Gegenfall reproduziert genau diesen Mechanismus. Er löst mit erhaltenen Koeffizienten oder exakt geprüfter positiver Zweierpotenzskalierung.

Die neue Solveroption erhält diese kleinen Koeffizienten. Der eingefrorene Original-OA-MIP wird damit numerisch OPTIMAL. Dies ist ein belegter lokaler Konfigurationsfix. Er ist kein allgemeiner Beweis für jede erzeugte OA-Normale oder jeden MIP-Baum. Die Mindestschwelle 1e-12 ist weiterhin endlich; kleinere Koeffizienten können andere Fälle betreffen.

Neu ausgeführte, betroffene Ausgangsmatrix: **54 Läufe**, Statusverteilung `{statuscounts(matrix)}`. Neue Fix-/Stressmatrix: **45 Läufe**, Statusverteilung `{statuscounts(stress)}`. Die kostskalierten G3-Primärläufe und G0-Vergleichsläufe lösen numerisch; **reference_24snap bei doppeltem Divisor bleibt ITERATION_LIMIT**. Der Defaultpfad ohne explizite Kostenskalierung ist ebenfalls nicht durch den einzelnen Optionsfix geschlossen. `native_G3_MISOCP=numerical_inconclusive`, `B1_repaired=false`. Der Patch ist getrennt zur unabhängigen Nachprüfung bereit.

Gurobi wurde neu tatsächlich angesprochen: Error 10009, abgelaufene Lizenz 12.10.2026. MOSEK 11.0 liest das echte Integer-CBF und endet erneut mit 1001/LICENSE_EXPIRED; Exit -1. Keine Lizenz wurde verändert und keine alternative native Solverabnahme behauptet.

## 5. Neun globale Kostenintervalle und Beweisniveau

Alle neun Raw-Case-SHAs sind einzeln im Ledger enthalten. Die BASE-LP-Constraints sind als echte Relaxation der tatsächlichen G0-/G3-Modelle geprüft; die emittierten Objectives stimmen zwischen diesen Modellen exakt überein. Der neue Verifikator prüft alle vollständigen rationalen Integerzeugen, bei G3 die Kegelprodukte, bei G0 alle Hauptminoren. Er prüft unabhängig jede LP-Bound-Inferenz, Dualrichtung, Stationaritätsrestkorrektur und Boundsumme. **171/171 Prüfungen**, einschließlich negativer Zertifikats-/Integer-Mutationen. Es wurde keine wissenschaftliche Fehlertoleranz erfunden.

Die Tabelle verwendet die separat rekonstruierte ursprüngliche Rohwährungsfunktion auf der normalisierten Modelldomain. Anzeigeendpunkte sind Float64 nach außen gerundet; rationale Brüche im JSON sind maßgeblich. Gültige globale Intervalle bedeuten hier noch keine enge Integeroptimalitätszertifizierung.

| Fall | rigoroser LB | rigoroser UB | exakte Breite, dezimal angezeigt | historisches numerisches UB−LB |
|---|---:|---:|---:|---:|
{table}

Die früheren acht negativen numerischen Intervalle bleiben unverändert dokumentiert. Ihre Interpretation als rigorose globale Intervalle wird zurückgezogen. Daraus wird weder die exakte Ungültigkeit jeder historischen LB-Zahl noch eine pauschale Rundungserklärung abgeleitet. Neue rationale Punkte und direkte Kosten-/Dualauswertung stellen gültige Intervalle her. Kostenresiduen, Integernähe und tatsächlich gespeicherte Rebase-/Skalierungsabweichungen werden separat geführt.

`integer_bounds_proved=true` gilt ausschließlich für diese gültigen Intervalle auf der deklarierten normalisierten Domain. `integer_optimality_proved=false`: insbesondere Relaxationslücken von rund 9288,18 / 1880,32 / 117,23 verhindern die enge globale Abnahme von connectivity/event_price/reference_24snap. reference_6snap bleibt etwa 0,004322 breit. Auch kleinere Breiten beweisen keine exakte Optimumsgleichheit. Kein vollständiger MIP-Baum oder vollständige Enumeration aller neun Fälle wurde zertifiziert. G0/G3-Optimumsgleichheit wird nicht aus ähnlich günstigen Punkten abgeleitet. `integer_globality=case_specific_partial`.

## 6. Objective-Koordinate

Der reale Rebase behält nominal C und dividiert durch s>0. Der tatsächliche Float64-Export kann zusätzlich eine exakt aus den Bits rekonstruierte affine delta(x) enthalten. Diese Abweichung ist für alle neun Fälle und zwei Divisoren gesondert gespeichert. Ein Punktwert von delta wird nicht als globaler Fehlerbound benutzt. Deshalb werden native numerische OA-Bounds nicht durch bloße Multiplikation in rigorose Geldbounds verwandelt. Die Zertifikate prüfen die emittierte Kostenfunktion sowie die aus Rawdaten exakt rekonstruierte Rohwährungsfunktion jeweils direkt. Details, Vorzeichen und Rücktransformationen stehen in `objective_rebase_derivation.md`.

CAPEX-/Dispatch-/Storage-/Event-Komponenten und feste Offsets sind getrennt. 24×3 h=72 h. Physisches baseMVA, Ereigniswiederholungen und Dispatchstunden werden nicht vertauscht. Quellkostenjahre, Storage-P/E-Quellen und tatsächliche Studienrepräsentativität werden durch die arithmetische Prüfung nicht qualifiziert.

## 7. Tatsächlich ausgeführte Regression und Umgebung

Julia **1.10.11**, JuMP {minimal['packages']['JuMP']}, MOI {minimal['packages']['MathOptInterface']}, Pajarito {minimal['packages']['Pajarito']}, HiGHS.jl {minimal['packages']['HiGHS']} / native Bibliothek 1.15.1, Clarabel {minimal['packages']['Clarabel']}. Julia-Threads 1; BLAS-Threads {minimal['BLAS_threads']}. Die Runtime-, Manifest-, Source-, Solveroptions- und Dateihashes sind erfasst. Paketstände wurden nicht aktualisiert.

* Auf Korrekturcommit {CODE}: vollständige Regression **6087/6087**, gespeicherte Evidenz **4108/4108**, jeweils Exit 0.
* Tatsächliche JuMP/MOI-/RSOC-/Kanten-/Singulär-/Range-Schutzsuite: vor Fix **42/42**, nach Fix **42/42**; rohe Domänenmutationen jeweils **16/16**.
* Neue Koeffizientenfilter-/Skalierungs-/Vorzeichen-/Objective-Prüfungen **18/18**, Exit 0. Dazu minimaler tatsächlicher HiGHS-MIP-Gegenfall und frischer Gurobi-Lizenzversuch.
* Neuer separater rationaler Zertifikatsverifikator **171/171**, alle neun Fälle mit beiden G0-/G3-Primalprüfungen und beiden Kostenkoordinaten.
* Neue vollständige Fixed-integer-Witnesspaare **18**, dazu neun BASE-LP-Läufe; echte 3/6/24-Snapshot- und alle neun registrierten Fallgruppen sind in den beiden Solvermatrizen enthalten.
* Die 124-Metrik-/8-CLI-Abnahme wird unverändert aus dem gepinnten A3.5-EXEC-Archiv referenziert. Kein Metrik-, Export-, CLI- oder Bound-Ausgabecode wurde geändert. Diese früheren Tests werden ausdrücklich nicht als neue Läufe ausgegeben.

Alle eigenen fehlgeschlagenen Versuche, Lizenzfehler und nichtoptimalen Solverstatus sind erhalten. Der erste Exact-Recovery-Versuch scheiterte an doppelten exportierten q-Namen; die tatsächliche MOI-Indexzuordnung behebt die Prüfwerkzeugfrage. Eine erste Konfliktkopie wurde falsch als Objekt statt Tupel gelesen. Die namensbasierte Integerfixierung war ungültig; der korrigierte Indextest ist gesondert. Kein dieser Fehlversuche wird als PASS gezählt.

## 8. Reproduktion, Veröffentlichung und offene Gates

Rootvariablen: BASE=`D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE`, FIX=`D:/Projekte/Code/FlexPlan_A36_B1_OPT_FIX`, RUN=`D:/Projekte/Code/FlexPlan_A36_B1_OPT_RUN`. Die tatsächlichen Argumentarrays/Exitcodes stehen in den Ausführungsmanifesten. `reproduce.md` enthält die Reihenfolge und die Abgrenzung von Snapshotdiagnostik und echten Solves. Alle neuen Rohmodelle, Witness-/Dual-/Bounddateien, Programme und vollständigen Test-/Solverlogs liegen verlustfrei in `verified_primal_dual_witnesses.zip`. Reproduktionsmanifest und Entryhashes sichern jede Datei. Der finale Git-/Remote-/Blobnachweis wird nach Push zusätzlich festgehalten; selbstreferenzierende Commit-SHAs werden nicht in den eigenen Commit hinein behauptet.

Der bestehende bedingte Satz- und Gleichung-zu-Code-Status bleibt `accepted_for_registered_cases`; dieser Auftrag wiederholt keine vollständige Gleichung-zu-Code-Abnahme. Der Solverfix benötigt weitere unabhängige Abnahme, B1 benötigt belastbare Statusstabilität einschließlich des noch fehlschlagenden Skalierungsfalls, OPT stärkere global validierte Integeruntergrenzen. Wissenschaftsowner-Ratifizierung und reale Datenqualifikation bleiben getrennt. Siehe den eigenständig kopierbaren Folgeauftrag in `remaining_gates_handoff.md`.

**Getrennte Schlussentscheidung:** konkretes B1-Ursachenglied reproduziert und partiell korrigiert; robuste native Gesamtzuverlässigkeit offen. Neun gültige exakte normalisierte Kostenintervalle hergestellt; enge globale Integeroptimalität nicht für alle neun bewiesen. `science_amendment_approved=false`, `independent_A3_5_accepted=false`, `A3_closed=false`, `AP4_ready=false`, `empirical_study_ready=false`.
''')
md('reproduce.md',f'''# Reproduktion

Verwende neue isolierte BASE/FIX/RUN-Verzeichnisse. BASE exakt 485b637cc1998a327206c5929434bd26c6f0be16, FIX-Code exakt {CODE}, EXEC-Inputs exakt 4d9f346c5fca80e00fd01d96c39a2bac91776ac0. Bestehende Worktrees/Archive nicht überschreiben. Das vorausgesetzte EXEC-ZIP samt 381 Entryhashes steht in input_sha256_manifest.json; eigene neue ZIP-Entries stehen im Reproduktionsmanifest.

Alle Julia-Aufrufe verwenden `julia +1.10.11 --startup-file=no --project=BASE` bzw `--project=FIX`. Manifest-v1.10.toml unverändert instanziieren; kein Pkg.update. Python-Hauptprogramme benötigen nur die Standardbibliothek; die alten Kostenforensikfunktionen stammen aus dem gepinnten EXEC-Quelltext. Weitere ältere Oracles benötigen gegebenenfalls NumPy/SymPy aus ihrer eigenen dokumentierten Umgebung.

1. Autoritäts-/Status-/Remote-/Parent-/Merge-Base-Prüfungen gemäß authority_preflight.json. EXEC-ZIP vollständig gegen die gepinnten Manifestwerte prüfen und nach RUN/input extrahieren.
2. `run_initial.py` enthält die tatsächliche Folge: drei native Reproduktionspaare, jeweils Native → Transfer → Native, danach neun frische Fixed-Integer-Paare sowie ursprüngliche MOI-/Domainregression. Die Rootpfade sind absichtlich explizit; bei neuem Host die drei Rootkonstanten anpassen. Der Transfer benötigt bytegleich RUN/input/integer_final/full_witness_reference_24snap_G3.json, als Seed nach jeweiligem nativen Laufordner/integer_final kopiert.
3. Aus BASE: `stage_diagnosis.jl BASE RUN/experiments/stages RUN/input`, danach `frozen_oa_variants.jl RUN` und `reduce_oa_conflict.jl RUN`. Der erste namensbasierte Integerfixierungsversuch ist explizit ungültige historische Diagnose; die korrekte Ersatzprüfung steht in frozen_oa_variants.jl.
4. Aus BASE: `lp_bound_inputs.jl BASE RUN/lp_bounds`, `model_inclusion.jl BASE RUN/model_inclusion` und `registered_solver_matrix.jl BASE RUN/solver_matrix`.
5. Mit Python: `reference_certifier.py RUN/lp_bounds` → `recover_exact_primal.py RUN` → `raw_cost_objective.py RUN BASE` → `reference_certifier.py RUN/lp_bounds_raw_currency` → `verify_exact_certificates.py RUN`. Exakte Punkte/Bruckzahlen sind maßgeblich; keine Feasibility-Toleranz im Verifikator.
6. Aus FIX: `fix_stress_matrix.jl FIX RUN/fix_stress_matrix`; separate neue Ordner für Wiederholungen. `run_fix_validation.py` enthält die tatsächlich ausgeführte Voll-/Evidenz-/MOI-/Domainregression; die Testkopie liegt außerhalb des Checkouts, damit keine historischen Reports überschrieben werden. `independent_b1_opt_tests.jl RUN` prüft den minimalen Filtergegenfall, echte Solves und die Objective-Rücktransformation.
7. Aus FIX: `objective_snapshots.jl FIX RUN/objective_snapshots RUN`. Dies ist ausschließlich Transformationsinspektion; der gezielte Snapshot-Ausnahmeabbruch findet vor jedem Solve statt und wird nicht als Lauf/Status gezählt. Danach Python `audit_objective_transform.py RUN`.
8. `cost_and_cut_forensics.py RUN BASE EXEC_AUDIT`, `build_package.py RUN FIX`. Die Pythonwerkzeuge bewahren historische negative Gaps und unterscheiden numerische Solverbounds von exakten Zertifikaten. `verify_exact_certificates.py` kann unabhängig allein aus dem entpackten neuen ZIP ausgeführt werden, sobald die dort enthaltenen model_inclusion/lp_bounds/exact_primals-Dateien unter RUN liegen.

Die Original-CLI-/Metrikabnahme und zusätzliche vorliegende Wissenschaftsbelege bleiben ausschließlich gepinnte Vorleistung. Die Ausführungsmanifeste enthalten alle tatsächlich eingesetzten Prozesse; Dateizeitstempel werden, wo kein Prozesszeitprotokoll existierte, ausdrücklich nur als Dateiprovenienz verwendet. Solverstatus werden nicht aus Prozess-Exit 0 abgeleitet.
''')
for n in ['bootstrap.py','run_initial.py','stage_diagnosis.jl','frozen_oa_variants.jl','reduce_oa_conflict.jl','lp_bound_inputs.jl','reference_certifier.py','model_inclusion.jl','recover_exact_primal.py','verify_exact_certificates.py','verify_native_exact_extension.py','raw_cost_objective.py','cost_and_cut_forensics.py','registered_solver_matrix.jl','run_fix_validation.py','fix_stress_matrix.jl','independent_b1_opt_tests.jl','objective_snapshots.jl','audit_objective_transform.py','build_package.py']:
    shutil.copy2(R/n,A/n)
for n in ['execution_initial.json','execution_fix_validation.json','authority_preflight.json']:
    shutil.copy2(R/n,A/n)
print('Report and machine package prepared; archive finalization is separate')
