"""Package completed independent runs; never infer solver success from exit 0."""
from pathlib import Path
from collections import Counter
import csv, hashlib, json, re, sys, zipfile
W=Path(sys.argv[1]).resolve(); R=Path(sys.argv[2]).resolve(); A=W/'reports/a3_6/reaudit_20261021'
def load(p): return json.loads(p.read_text(encoding='utf-8'))
def save(p,x): p.write_text(json.dumps(x,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
execution=[]
for name,count in [('exact',4),('regression',4),('solver',5),('remaining_filter',1)]:
    rows=load(R/f'execution_{name}.json'); assert len(rows)==count
    if name=='solver' and rows[-1]['exit_code']!=0:
        assert all(r['exit_code']==0 for r in rows[:-1]) and rows[-1]['id']=='fresh_export_comparison'
        retry=load(R/'execution_comparison_retry.json'); assert len(retry)==1 and retry[0]['exit_code']==0
        rows=rows+retry
    else: assert all(r['exit_code']==0 for r in rows)
    execution.extend(rows)
checks={'full_regression':('FlexPlan',6087),'saved_evidence':('AP3 saved input solution independent CLI evidence',4108),'moi_guards':('Independent actual JuMP/MOI cones',42),'domain_mutations':('Independent raw-domain adversarial probes',16),'minimal_filter':('Independent HiGHS filter and actual production factories',12)}
for log,(label,count) in checks.items():
    assert re.search(re.escape(label)+r'\s*\|\s*'+str(count)+r'\s+'+str(count)+r'\b',(R/(log+'.log')).read_text(encoding='utf-8')),log
exact=load(R/'independent_certificates.json'); assert exact['cases_verified']==9
fresh=load(R/'fresh_export_comparison.json'); assert len(fresh['fresh_exports'])==45
matrix=load(R/'fresh_stress/results.json'); assert len(matrix)==45
statuses=Counter(r['stats']['termination'] for r in matrix)
expected=load(R/'prior/fix_stress_matrix/results.json')
ids=lambda r:(r['case_id'],r['formulation'],r['mode'])
old={ids(r):r['stats']['termination'] for r in expected}
matches=all(r['stats']['termination']==old[ids(r)] for r in matrix)
assert all(r['stats']['termination']=='OPTIMAL' for r in matrix if r['formulation']=='G3' and r['mode']=='production_costscale')
failed=[r for r in matrix if r['stats']['termination']!='OPTIMAL']
save(A/'execution_manifest.json',execution)
save(A/'integrity_results.json',load(R/'integrity.json'))
save(A/'final_preservation.json',load(R/'final_preservation.json'))
save(A/'fresh_export_comparison.json',fresh)
save(A/'independent_certificate_results.json',exact)
save(A/'b1_stage_evidence.json',{'fresh_actual_factory_and_OA_runs':load(R/'solver_review.json'),'constructed_below_threshold_counterexample':load(R/'remaining_filter.json'),'frozen_original_OA_coefficient_filter':exact['frozen_oa_filter'],'stress_statuses':dict(statuses),'stress_status_identity_with_input':matches,'nonoptimal_stress_rows':failed,'native_global_cut_certificate':'NOT_CERTIFIED','complete_MIP_node_dual_proof':'NOT_AVAILABLE'})
ledger=load(W/'reports/a3_6/b1_opt_20261020/integer_9cases_bounds.json'); case_info={e['case_id']:e for e in ledger}
bounds=[]
for r in exact['cases']:
    e=case_info[r['case_id']]; b=r['lp_bounds_raw_currency']
    bounds.append({'case_id':r['case_id'],'raw_case_sha256':e['raw_case_sha256'],**b,'LB_currency_outward':e['LB_currency_outward'],'UB_currency_outward':e['UB_currency_outward'],'rigorous_LB':True,'rigorous_UB':True,'scope':'normalized binary rational G0/G3 constraints and declared exact raw-currency objective','lower_origin':'BASE LP inclusion + exact weak duality and proven residual endpoint correction','upper_origin':'exact integer point, all linear/RSOC/PSD constraints checked independently','global_integer_optimality_proved':False,'historical_signed_numerical_gap':e['historical_signed_gap']})
save(A/'integer_9cases_bounds.json',bounds)
with (A/'integer_9cases_proof_ledger.csv').open('w',newline='',encoding='utf-8') as f:
    keys=['case_id','raw_case_sha256','LB_exact','UB_exact','width_exact','width','rigorous_LB','rigorous_UB','global_integer_optimality_proved']; writer=csv.DictWriter(f,keys,extrasaction='ignore',lineterminator='\n'); writer.writeheader(); writer.writerows(bounds)
with (A/'b1_solver_reliability_matrix.csv').open('w',newline='',encoding='utf-8') as f:
    keys=['case_id','formulation','mode','factor','termination','primal_status','dual_status','objective_solver_scaling','objective','bound','max_violation','solve_wall_s','status_matches_previous']; writer=csv.DictWriter(f,keys,lineterminator='\n'); writer.writeheader()
    for r in matrix:
        row={k:r.get(k) for k in keys}; row.update({k:r['stats'].get(k) for k in keys if k in r['stats']}); row['status_matches_previous']=r['stats']['termination']==old[ids(r)]; writer.writerow(row)
gates='''original_ap3_sha: 485b637cc1998a327206c5929434bd26c6f0be16
a3_5_exec_input_sha: 4d9f346c5fca80e00fd01d96c39a2bac91776ac0
metadata_fix_sha: e1e075626b38b478faf57efe62e557fc94753f00
macro_authority_sha: e49b64216f82eefda77d6997ed68ed2d12c8ae78
production_correction_sha: 910d44122a37d9ed2cca06940740b46706c73d40
reviewed_evidence_sha: 1147873bf553667aec5cd7eb0e9c6f7e471b370c
specification_status: SPECIFICATION_READY
production_correction_independent_reaudit: accepted_for_demonstrated_local_coefficient_filter_failure
production_code_changed_by_reviewer: false
B1_coefficient_filter_cause_reproduced: true
B1_repaired: false
native_G3_MISOCP: numerical_inconclusive
global_OA_cut_certificate_available: false
complete_integer_tree_certificate_available: false
integer_bounds_proved: true
integer_bounds_proved_scope: normalized_binary_rational_models_and_declared_exact_raw_currency_objective
rigorous_normalized_intervals: 9
integer_optimality_proved: false
required_precision_qualified_nine: false
integer_globality: case_specific_partial
a3_6_b1_opt_verdict: partially_closed
proposed_science_amendment_blob: fba4802ecabade61a752833a71106a5bda4ce78f
science_amendment_approved: false
owner_ratification: pending
implementation_equation_match: accepted_for_registered_cases
independent_A3_5_accepted: false
A3_closed: false
AP4_ready: false
empirical_study_ready: false
'''
(A/'release_gates.yaml').write_text(gates,encoding='utf-8',newline='\n')
table='\n'.join(f"| {e['case_id']} | {e['LB_currency_outward']!r} | {e['UB_currency_outward']!r} | {e['width']:.10g} |" for e in bounds)
status_text=', '.join(f'{n} × {s}' for s,n in sorted(statuses.items()))
report=f'''# Paper A — A3.6-REAUDIT: unabhängige Abnahme des Solverfixes und der Integerintervalle

21.10.2026. **Gesamturteil: `partially_closed`.** Der Produktionsfix ist für den nachgewiesenen lokalen Koeffizientenfilterfehler unabhängig abgenommen. Alle neun rationalen Kostenintervalle sind in ihrer ausdrücklich normalisierten Domain gültig. Die robuste native G3-MISOCP-Zuverlässigkeit und die enge globale Integeroptimalität bleiben offen. `B1_repaired=false`, `A3_closed=false`, `AP4_ready=false`, `empirical_study_ready=false`.

## 1. Auftrag, Identität und Unabhängigkeit

Dies ist ein neuer lokaler Prüfworker mit separatem Worktree und neu ausgeführten Prüfungen. Er implementiert keinen Produktionsfix. Eingefrorene Originale, fremde Branches und historische Archive bleiben unverändert. Veröffentlicht wird ausschließlich additiv auf `codex/a3-6-independent-reaudit-20261021`, ab exakt `1147873bf553667aec5cd7eb0e9c6f7e471b370c`. Keine PR und kein Merge.

| Referenz | Exakter Commit | Funktion im Audit |
|---|---|---|
| Original-AP3 | `485b637cc1998a327206c5929434bd26c6f0be16` | unveränderte native Negativ-Baseline |
| Metadatenfix | `e1e075626b38b478faf57efe62e557fc94753f00` | zwei zusätzliche Einheit-Zuordnungszeilen; keine Modelländerung |
| EXEC-Evidenz | `4d9f346c5fca80e00fd01d96c39a2bac91776ac0` | unveränderlicher Input mit 381 Archiveinträgen |
| Makroauftrag | `e49b64216f82eefda77d6997ed68ed2d12c8ae78` | ausschließlich zusätzliche Auftragsdatei gegenüber EXEC |
| Produktionsfix | `910d44122a37d9ed2cca06940740b46706c73d40` | zusätzliche HiGHS-OA-Option `small_matrix_value=1e-12` |
| A3.6-Evidenz | `1147873bf553667aec5cd7eb0e9c6f7e471b370c` | hier unabhängig geprüfter vollständiger Evidenzstand |

Die Ancestry-Reihenfolge lautet Original → Metadatenfix → EXEC → Makroauftrag → Produktionsfix → Evidenz. Zwischen Produktionsfix und Evidenz sind `src`, `scripts`, `test`, Project und Manifest identisch. Der Solverfix ändert eine Option und zwei Kommentarzeilen; seine übrige Commitänderung ist der vorher erstellte Pre-fix-Bericht. Metadatenfix, Solverfix und Evidenzpublikation werden deshalb nicht als dieselbe Änderung bewertet.

`SPECIFICATION_READY`. Wiederverwendet werden die unveränderte AP3-Pipeline, die vorhandene Stressmatrix, die MOI-/Domänentests und der nach Quelltextprüfung erneut ausgeführte exakte Verifikator. Zusätzlich prüft `independent_check.py` Primalpunkte, alle PSD-Hauptminoren, LP-Inklusion, Zielfunktionsidentität, jede Bound-Inferenz, Multiplikatorrichtung und Residualkorrektur mit einer separaten Implementierung. Die Rohkostenrekonstruktion verwendet das gelesene vorhandene Kostenprogramm; ihre exakten Koeffizienten werden erneut mit den Zertifikaten verglichen. Vorherige PASS-Flags ersetzen keine neuen Prüfungen. Es entsteht keine neue wissenschaftliche Formulierung.

## 2. SHA- und Evidenzintegrität

Frisch verifiziert: A3.6-ZIP **7.308.953 Bytes**, SHA256 `ca15ee8a3cd73eefe9c75b00896ec4f4cdb71f12e23d6fc55a0916e35417482c`, **406/406** Entries; EXEC-ZIP **24.237.795 Bytes**, SHA256 `0ec9969de7c8659bc50d82664556c09515080beb1bcd1e937bb9cc7b8d925993`, **381/381** Entries. Entrymenge, Eindeutigkeit, Größe und Hash wurden geprüft.

Weitere frisch bestandene Identitätsprüfungen: 55 publizierte Dateihashes, {fresh['publication_git_blobs_verified']} publizierte Git-Blobs, zusätzlich sämtliche {len(fresh['complete_pinned_report_tree'])} Dateien des gepinnten A3.6-Berichtsbaums einschließlich der Manifest-/Receiptdateien gegen ihre Git-Inhalte, 520 ursprüngliche Inputdateien, acht gepinnte Wissenschaftsblobs, 14 historische ZIPs mit CRC-Prüfung und 1.060 historische Indexeinträge sowie {fresh['source_runtime_files_verified']} Quelltext-/Manifest-/Runtime-Dateien. Die aus dem tatsächlichen Produktionscode frisch erzeugten **27 BASE/G0/G3-Modelle und 18 Objective-Snapshots** stimmen inhaltlich mit den zertifizierten Eingängen überein; die einzelnen Bytehashes stehen im Vergleichsmanifest.

Insbesondere wurde das native 24-Snapshot-Defaultmodell identisch neu aufgebaut. Sein Originalhash ist `fcd52695238591d6c6019385d64e4407e1ea480849ca4125e1191b992581ab07`. Ein vollständiger rationaler Punkt erfüllt erneut alle Originalconstraints einschließlich 1.353 Integerrestriktionen und der Objective-Increment-Gleichungen. Die 3.680 Variablen enthalten 23 exakt ergänzte Increments. Dies beweist Feasibility der serialisierten binären rationalen Modellkoeffizienten, keine ungerundete physikalische Feasibility.

Der historische Publikationsreceipt bindet seine 56 Blobnachweise ausdrücklich an `8d982224c407145a42bd800ec95f1a4840187eae`; sie wurden gegen genau diesen Commit verifiziert. Der Nachfolger `1147873...` ergänzt Receipt und Inventare. Seine gesamte Dateimenge wird zusätzlich separat geprüft. Ein erster Vergleich gegen den falschen Nachfolger wurde als Werkzeug-Fehlversuch mit Exit 1 erhalten und danach nur diese Vergleichsstufe erfolgreich wiederholt; es liegt keine unaufgeklärte Änderung der Eingangsarchive vor.

Die geprüften Wissenschafts- und Producer-Remote-Referenzen stehen weiterhin auf ihren vorgegebenen SHAs. Der lokale research-map-Checkout hat einen anderen HEAD; er wurde nicht als Ersatz für gepinnte Wissenschaftsblobs verwendet. Einzelheiten: `auxiliary_refs.json`. Die Prüfung eines Amendment-Blobs ist keine Owner-Ratifizierung.

## 3. B1: Ursache, tatsächlicher Fix und verbleibende Grenze

Der frische minimale HiGHS-MIP reproduziert bei `mip_feasibility_tolerance=1e-8` den Verlust der drei Koeffizienten `4.5830185178677806e-11`, `4.5830185178677806e-11`, `1.3046247794859574e-10`. Der Defaultfilter entfernt sie und lässt die unzulässige Zeile `0 ≥ 3.025002202302713e-8` zurück. Ein exakter rationaler Zeuge der ursprünglichen Zeile wird arithmetisch geprüft. Defaultfilter: `INFEASIBLE`; Option `1e-12`: `OPTIMAL`; exakt geprüfte positive Skalierung mit `2^33`: `OPTIMAL`.

Der unveränderte eingefrorene originale OA-MIP ergibt frisch ebenfalls `INFEASIBLE` mit Defaultfilter und `OPTIMAL` mit der zusätzlichen Option. Im eingefrorenen Modell verlieren bei `1e-9` zwei Zeilen insgesamt sechs Koeffizienten; bei `1e-12` wird dort kein Koeffizient entfernt. Das lokal kausale Ursachenglied ist damit unabhängig bestätigt.

Die tatsächliche originale Factory auf dem originalen nativen serialisierten 24-Snapshot-Modell meldet frisch `INFEASIBLE/NO_SOLUTION`. Die tatsächliche korrigierte Factory endet auf demselben Modell mit `ITERATION_LIMIT/NO_SOLUTION`. Die archivierten mehrfachen Native→Transfer→Native-Reproduktionen und Bridging-/Root-Belege wurden vollständig hashgeprüft; diese frühere gesamte Sequenz wird hier nicht als neu ausgeführt behauptet. Neu sind die separaten nativen Factoryläufe, der OA-Replay, der exakte vollständige Originalpunkt und der identische Modellneuaufbau.

Die neue 45-Läufe-Stressmatrix umfasst alle neun registrierten Fälle, G3 mit BASE-LP-Kostendivisor, halbem und doppeltem Divisor, die vorhandene engere Feasibility-Variante und G0 mit Primärdivisor. Dazu werden neun BASE-LPs tatsächlich gelöst. Ergebnis: **{status_text}**. Statusidentität mit der ursprünglichen Stressmatrix: **{'ja' if matches else 'nein'}**. Alle neun primär kostenskalierten G3-Läufe sind numerisch `OPTIMAL`. Der Fall `reference_24snap/G3/double_costscale` bleibt `ITERATION_LIMIT`; ein numerischer Solve ersetzt kein rationales Integeroptimalitätszertifikat.

Ein zusätzlicher neuer Gegenfall prüft die Restgrenze ausdrücklich: Koeffizient `1.2740476362167553e-13`, RHS `3.025002202302713e-8`, exakter zulässiger Punkt `1198326830450234359808/5047022658654771`. Auch der korrigierte Filter entfernt diesen Koeffizienten und meldet `INFEASIBLE`. Das ist ein konstruierter Schwellengegenfall, kein zusätzlicher Fehler einer registrierten Instanz. Er widerlegt eine allgemeine Zuverlässigkeitsfreigabe des endlichen Schwellenwerts. Ein weiterer proportional verkleinerter Minimalfall löst numerisch, obwohl die kleine Zeile unterhalb der Feasibility-Toleranz liegt; auch dies wird nicht als exakte Feasibility gewertet.

**Abnahme Produktionsfix: `ACCEPTED_SCOPED`** für die konkret nachgewiesene lokale False-Infeasibility-Ursache, ohne Änderung der Modellgleichungen, Integrality, Kosten, Feasibility-Toleranzen oder Statuslogik durch diesen Reviewer. **B1: weiterhin `numerical_inconclusive`, `B1_repaired=false`.** Globale Gültigkeit sämtlicher neu erzeugter OA-Cuts, vollständige MIP-Nodeabdeckung und abgesicherte Node-/Dualbeweise sind nicht zertifiziert. Die Daten der vorhandenen OA-/MIP-Läufe reichen dafür nicht aus. Eine neue native kommerzielle Solverqualifikation wurde hier nicht ausgeführt. Die frische MOI-Schutzsuite meldet bei der Gurobi-Initialisierung erneut Error 10009, Lizenzablauf 12.10.2026 (`moi_guards/runtime_capabilities.json` im neuen ZIP). MOSEK wurde hier nicht erneut angesprochen; dessen historischer Lizenzfehler ist kein aktueller Lizenzstatus.

## 4. OPT: unabhängiges Urteil über alle neun Kostenintervalle

Die Intervalle gelten für **exakt als binäre rationale Zahlen interpretierte normalisierte G0-/G3-Constraints** und die ausdrücklich aus Raw-Kosteneingängen mit exakten Produkten rekonstruierte Währungsfunktion. Für jeden Fall ist die BASE-LP-Zeilenmultimenge Teil der G0-/G3-Zeilenmultimenge. Objective und Case-SHA sind identisch zu den jeweils geprüften Objekten. Dadurch gilt die Relaxationsinklusion in der richtigen Richtung.

Die separaten exakten Prüfungen bestehen für 18 vollständige G0/G3-Primalprüfungen, **1.581 PSD-Hauptminoren**, 18 LP-LB-Zertifikate und **27.300 einzelne Bound-Inferenzen**. Alle Integerwerte, linearen Zeilen und RSOC-Produkte werden ohne Feasibility-Toleranz geprüft. Die tatsächliche LP-Objective wird zusätzlich mit der Modell-Objective bzw. der frisch rekonstruierten Rohkostenfunktion verglichen. Veränderte Integerpunkte und manipulierte LB-Summen werden zurückgewiesen. Auch der vorhandene separate Verifikator besteht erneut **171/171** Prüfungen.

Für die Untergrenze werden vorzeichenrichtige LP-Multiplikatoren und der exakte Stationaritätsrest `r=c-Aᵀy` benutzt. Jeder erforderliche endliche Variablenendpoint wird ausschließlich aus Originalzeilen bewiesen. Schwache Dualität liefert exakt `L=c0+Σ(yᵢbᵢ)+Σ min(rⱼlⱼ,rⱼuⱼ)`; einseitig unbeschränkte Variablen sind nur bei passender Restrichtung zulässig. Die vollständigen zulässigen Integerpunkte liefern separat exakte UBs. Fixed-Integer-SOCP-Werte und native numerische MIP-Bounds werden nicht als globale Integer-LBs eingesetzt.

Die folgende Tabelle zeigt die gespeicherten nach außen gerundeten Float64-Anzeigen. **Maßgeblich sind die exakten Brüche in `integer_9cases_bounds.json`**, nicht die Dezimalanzeige.

| Fall | LB, Anzeige | UB, Anzeige | exakte Breite, dezimal angezeigt |
|---|---:|---:|---:|
{table}

**Abnahme Intervalle: `ACCEPTED` im genannten Geltungsbereich.** `integer_bounds_proved=true`, `integer_globality=case_specific_partial`, `integer_optimality_proved=false`. Die breiten Lücken bei connectivity, event_price und reference_24snap verhindern eine enge globale Abnahme. Auch schmale Intervalle belegen ohne akzeptiertes Präzisionskriterium keine exakte Optimumsgleichheit. Die alte 81-Zuweisungen-Enumeration wird auf keinen dieser Fälle übertragen. Historische acht negative numerische UB−LB-Abstände bleiben unverändert erhalten; ihre Interpretation als rigorose globale Intervalle wird nicht akzeptiert.

## 5. Objective-Koordinate und Transformationsgrenze

Die vorhandene Rebase führt für ausgewählte `c>0`, `l>0` die Variable `z=x-l` ein; über exakten Zahlen bleibt `c*x=c*z+c*l`. Der Code dividiert danach die **gesamte** affine Zielfunktion inklusive Konstante durch den positiven Divisor `s`. Nominal gilt `F=C/s`, `C=sF`; es wird kein Offset stillschweigend entfernt.

Die 18 tatsächlichen Float64-Exporte wurden jedoch exakt eliminiert und getrennt verglichen: `s*F_serialized(x,z(x)) = C_emitted(x)+delta(x)`. Alle gespeicherten rationalen Delta-Koeffizienten und Konstanten stimmen mit der unabhängigen Nachrechnung überein. Der größte Betrag an den geprüften exakten Punkten ist rund `1.5003892765882408e-6` Währungseinheiten. Dieser Punktwert ist keine globale Fehlerschranke. Ein rigoroser Solver-LB müsste zusätzlich um `max(delta)` korrigiert werden; für einen UB wäre `min(delta)` nötig. Die hier akzeptierten Kostenintervalle umgehen diese ungeprüfte native Boundübertragung durch direkte exakte Kosten- und LP-Dualauswertung.

Dispatch berücksichtigt `baseMVA`, Dauer, repräsentative Wiederholungen und Szenariowahrscheinlichkeit. Start/Stop verwendet Ereignisgewichte ohne zusätzlichen Dauerfaktor. Investition wird einmal mit dem registrierten Periodenfaktor und Initialbestandsabzug gezählt. 24×3 h sind 72 h. Storage-Kostenbasis und reale Preis-/Datenqualifikation werden dadurch nicht wissenschaftlich freigegeben.

## 6. Neu ausgeführte Regression und Reproduktionsgrenzen

| Frische Prüfung | Ergebnis |
|---|---:|
| vollständige Julia-Regression auf Produktionscode identisch zu 910d441 | 6087/6087, Exit 0 |
| gespeicherte AP3-Evidenz, in eigener Kopie entpackt | 4108/4108, Exit 0 |
| tatsächliche JuMP/MOI-Kegel-/Domänenschutzsuite | 42/42, Exit 0 |
| Raw-Domänenmutationen | 16/16, Exit 0 |
| neue tatsächliche Filter-/Factory-/OA-Tests | 12/12, Exit 0 |
| zusätzliche Schwellenrestgrenze | drei Assertions, Exit 0 |
| vorhandener exakter Zertifikatsverifikator | 171/171, Exit 0 |
| separater exakter Reviewer-Verifikator | neun Fälle einschließlich beider Kostenkoordinaten, PASS |
| frische Solvermatrix | 45 Läufe; Status siehe Abschnitt 3 |
| frische Modell-/Objective-Exporte | 27+18, identisch zu den geprüften Eingängen |

Julia 1.10.11, JuMP 1.31.1, MOI 1.51.2, Pajarito 0.8.3, HiGHS.jl 1.24.1, native HiGHS 1.15.1, Clarabel 0.11.1; ein Julia-Thread, sechs BLAS-Threads. Das gepinnte Julia-Environment wurde ohne `Pkg.update` instanziiert. Es gab keine Dependencyänderung. Zwei unabhängige Prüfprozesse liefen zeitweise parallel; Laufzeiten sind deshalb keine Performancebenchmarkwerte. Die Argumentarrays, UTC-Zeitstempel, Exitcodes, vollständigen Rohlogs und Paketstände sind gespeichert.

124-Metrik-/8-CLI-Abnahme, frühere Gleichung-zu-Code- und Wissenschaftsbelege werden im ursprünglichen Geltungsbereich aus der gepinnten EXEC-Evidenz übernommen; sie werden nicht als hier vollständig neu gerechnet ausgegeben. Dieser Reviewer ändert weder Ausgabe-/Export-/Boundcode noch die Produktionskonfiguration. Erwartete negative Testmeldungen, nichtoptimale Solverstatus und Werkzeug-Fehlversuche werden erhalten (`attempts.md`).

## 7. Getrennte Abnahme und verbleibender Folgeauftrag

1. **Produktionskorrektur:** unabhängig und eng begrenzt akzeptiert. Für die unveränderte Option ist kein erneuter Reaudit einer Eigenkorrektur dieses Reviewers erforderlich, weil er keinen Produktionscode geändert hat. Eine spätere Cut-/Scaling-/Solverkorrektur benötigt eine eigene Spezifikation und unabhängige Prüfung.
2. **Neun Intervalle:** exakt gültig in der erklärten normalisierten Domain; keine Aussage über ungerundete physische Eingangsgleichungen oder akzeptierte wissenschaftliche Präzision.
3. **B1 offen:** Default- und Doppeldivisorpfad mit `ITERATION_LIMIT`, endliche Filtergrenze, kein vollständiges globales Cut-/Nodezertifikat. Nächste fachlich zu spezifizierende Arbeit: separat geprüfte Cut-Normalisierung/Skalierung oder tatsächlich verfügbare native MISOCP-Alternative. Keine bloße Lockerung der Feasibility-Toleranz und keine Statusumschreibung.
4. **OPT offen:** stärkere nachweisbar globale Integer-LBs insbesondere für connectivity, event_price und reference_24snap, durch vollständig prüfbare B&B-Nodebounds, ein gleichwertiges exaktes Zertifikat oder tatsächlich vollständige fallbezogene Enumeration. Das akzeptierte Präzisionskriterium muss vom Verantwortlichen vorgegeben werden.
5. **Owner-/Datengates offen:** Ownerentscheidung ausschließlich zum Amendment-Blob `fba4802ecabade61a752833a71106a5bda4ce78f`; reale Quellen-/Passivinventare, Source-Accounting, Erdungsbezug, Preis-/Kostenjahr, Storage-P/E-Basis und zeitliche Repräsentativität separat qualifizieren. `independent_A3_5_accepted=false`, keine Studienfreigabe.

Lesereihenfolge: dieser Bericht → `release_gates.yaml` → `b1_stage_evidence.json` und Solvermatrix → Intervall-Ledger und exakte Ergebnisse → Integritäts-/Exportvergleiche → Ausführungs-/Reproduktionsmanifest → rohe Logs im neuen Archiv. `reproduce.md` beschreibt die Befehle. Das neue Manifest sichert Archiv und einzelne Entries; die ursprünglichen zwei Archive bleiben unveränderte gepinnte Inputs. Der Publikationsnachweis wird nach dem ersten Push additiv als separater Receipt festgehalten, ohne einen selbstreferenzierenden Commit-SHA zu behaupten.
'''
(A/'independent_reaudit_report.md').write_text(report,encoding='utf-8',newline='\n')

# Package only new evidence. The prior archives and copied test/data fixtures
# remain pinned inputs and are not duplicated or rewritten in this publication.
files=[p for p in R.iterdir() if p.is_file() and p.suffix in ('.log','.json')]
for folder in ['fresh_stress','fresh_models','fresh_objective_snapshots','moi_guards']:
    files.extend(p for p in (R/folder).rglob('*') if p.is_file())
files=sorted(set(files)); entries=[]; archive=A/'reaudit_evidence.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in files:
        rel=p.relative_to(R).as_posix(); z.write(p,rel); entries.append({'path':rel,'bytes':p.stat().st_size,'sha256':sha(p)})
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None and len(z.namelist())==len(entries)
    for e in entries:
        b=z.read(e['path']); assert len(b)==e['bytes'] and hashlib.sha256(b).hexdigest()==e['sha256']
manifest={'basis_sha':'1147873bf553667aec5cd7eb0e9c6f7e471b370c','production_code_sha':'910d44122a37d9ed2cca06940740b46706c73d40','archive':{'path':archive.name,'bytes':archive.stat().st_size,'sha256':sha(archive),'entries':len(entries)},'entries':entries,'input_archives':{'a36':load(R/'integrity.json')['a36_archive'],'exec':load(R/'integrity.json')['exec_archive']},'excluded':'unmodified prior archives and copied original test/data fixtures; pinned and hash-verified separately','scripts_and_outputs':[]}
for p in sorted(A.iterdir()):
    if p.is_file() and p.name not in ['reproduction_manifest.json','publication_receipt.json']:
        manifest['scripts_and_outputs'].append({'path':p.name,'bytes':p.stat().st_size,'sha256':sha(p)})
save(A/'reproduction_manifest.json',manifest)
print('Completed independent review:',dict(statuses),'same statuses:',matches,'archive',len(entries),'entries',archive.stat().st_size,'bytes',sha(archive))
