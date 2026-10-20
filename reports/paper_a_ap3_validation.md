# Paper A — AP3: Implementierung und Worker-Validierung

**Ergebnis: AP3_partial; Specification Gate: SPECIFICATION_READY.** Alle angeforderten Formulierungsfamilien, anwendbaren Auswertungsalgorithmen und acht unabhängigen CLI-Aktionen sind umgesetzt und ausgeführt. Die offene technische Qualifikation betrifft den nativen Integer-Konussolver: Pajarito/HiGHS/Clarabel meldet teilweise fälschlich INFEASIBLE für zulässige G3-Fälle. Diese Meldungen werden konservativ als numerical_inconclusive behandelt. Vollständige kleine Enumeration und separate numerische Referenzintervalle für neun Integer-Szenarien sind erfolgreich. Dies ist Worker-Validierung, keine unabhängige A3.5-Abnahme.

Die Daten bleiben **conditional_owner_review_pending**, nicht empirisch freigegeben. Die ursprünglichen AP1-Gates werden nicht umgedeutet. **A3_closed=false; AP4_ready=false.** Statusdetails stehen in [paper_a_ap3_status.yaml](paper_a_ap3_status.yaml), die unabhängige Übergabe in [ap3_to_a3_5_handoff.md](../docs/paper_a/ap3_to_a3_5_handoff.md).

## 1. Autorität, Branch und Schutz bestehender Arbeit

Einziger AP3-Branch: [implementation/paper-a-ap3-all-formulations-v1](https://github.com/AlOussama/FlexPlan.jl/tree/implementation/paper-a-ap3-all-formulations-v1). Ausgangspunkt ist exakt der qualifizierte Consumer e992edc88d39fa0eb2d72e2490e157441223f568; AP2 725de2e ist dessen Vorfahr. Die drei AP3-A0-Dokumente wurden aus dem reinen Dokumentationsfortschritt adf1a974741eb5393a91bef46e8274a68aac1c66 übernommen. Keine Strang-B-Implementierung wurde durch den älteren AP2-Stand ersetzt. Es gab keinen Master-Merge, Reset, Force-Push, PR oder Branchwechsel in fremden Worktrees.

| Autorität | Exakter Stand |
|---|---|
| AP2-Code | 725de2e6c1cea21f63902474f72ec614b2358356 |
| Strang-B-Consumer / AP3-Basis | e992edc88d39fa0eb2d72e2490e157441223f568 |
| AP1 ursprünglicher Producer | 32ff4525dc576af52c16298cb35ebd98f02cf8b2 |
| Strang-B-Numerik | 3b8fdb01d931225edc5f8fe1e2c200d0da288a09 |
| Producer-Dokumentationshead | b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c |
| C2A vollständige Dissertation | e8118425adc335a99e85120d943763305f211315 |
| Theorem-Freeze | 2c2fce769b2ed6ffd4f1ced60c0798776acccc93 |
| Paper-A-Scope | 672a61c95525bf1d7a03cf745a754a15a23ce78b |
| Qualifikationsentscheidung | a6c19790bb009b5956475a6368a23e339a82dab7 |
| Registry SHA256 | a249f7a96d202798c6ff5778c1fa1571eba59a3717bac5d25b150d2a6c41bce9 |
| Szenarien SHA256 | be9d9d9aa90e9790fc7c3554bc1107777a5ba743f4f95d8f675acd9bfeb1e75a |

D:\Projekte\Code\FlexPlan_UC_GSCR bleibt auf AP2 725de2e einschließlich seines vorhandenen untracked audit/-Verzeichnisses. D:\Projekte\Code\FlexPlan_StrangB bleibt auf e992edc. Ausschließlich D:\Projekte\Code\FlexPlan_AP3 wurde geändert. Producer und research-map wurden nur gelesen; Daten wurden aus einem exakten Git-Archiv außerhalb ihrer Worktrees bezogen. Worktree- und Autoritätsnachweise liegen in authority_and_preservation.json. Die finale Dateiliste und SHA256 stehen außerhalb des Laufverzeichnisses in paper_a_ap3_changed_files.txt und paper_a_ap3_file_manifest.csv; die unveränderlichen Laufdateien sind zusätzlich durch export_final/evidence_index.json indiziert. Die Publikationsnotiz benennt den überprüften Remote-Evidenzcommit; spätere reine Publikationsmetadaten werden getrennt ausgewiesen.

## 2. Wiederverwendung und tatsächlicher Implementierungsumfang

Wiederverwendet werden AP1-Import, qualifizierte Parameterprüfung, regionale Reihenfolge und Quellenbasis, AP2s gemeinsame affine B/S/M-Objekte, bestehende UC-, Speicher-, Netz- und Zielfunktionslogik sowie G1. Ein Dispatch-Aufruf im vorhandenen UCGSCR-Builder wählt die Formulierung. Neue Logik liegt in src/core/paper_a_formulations.jl, die unabhängige numerische Rekonstruktion in paper_a_diagnostics.jl und die Ablauf-/Exportschicht in scripts/paper_a/AP3Pipeline.jl. Es existiert kein zweiter Planungsmodellaufbau.

| Kandidat | Tatsächlich ausgeführt | Garantie und Grenzen |
|---|---|---|
| BASE | unverändertes Planungsmodell; 9 LP + 9 MILP optimal | keine Stärkebedingung |
| G0 | echte affine PSD-LMI; 9 kontinuierliche SDP optimal; 8/9 ausgewählte native Integerläufe optimal, einer inkonklusiv | T005/006; zusätzlich vollständige kleine Integer-SDP-Enumeration und neun globale numerische Referenzintervalle |
| G1 | bestehende AP2-Zeilensummen; 9 LP + 9 MILP optimal | T011; hinreichend auf verifizierter Z-Klasse |
| G2 | r=1 und vorab festes degree+1; Identität 9 LP + 9 MILP optimal, degree jeweils 9 infeasible | T013–016; positive feste Skalierung, keine allgemeine Dominanz, kein gemeinsam optimiertes bilineares r |
| G3 | vollständige vorzeichenbehaftete Kanten-RSOC und alle Knotenreste; 9 kontinuierliche SOCP optimal, 8/9 ausgewählte native Integerläufe optimal, einer inkonklusiv | T017–020; exakt zur PSD-Bedingung nur auf vollständiger symmetrischer Z-Klasse; native MISOCP-Zuverlässigkeit eingeschränkt |
| M0 | exakte direkte Inversenmetrik und vollständig enumerierter begrenzter 2-Regionen-Integerbenchmark | T007–010; PD, Inversenzeichen, alpha>0; kein allgemeiner NLP-Planer behauptet |
| M1 | echte LP/MILP-Bedingung mit erzwungenem B>=Bmin und neu berechnetem inv(Bmin) | T021/022; positive/rejektierte Fixtures bestanden; alle 9 LP + 9 MILP der vorregistrierten Studie infeasible, ohne nachträgliches Tuning |
| M2 | volle und Nachbar-MIIF-Gewichte, W>=0 und diag(W)=1; je 9 LP + 9 MILP optimal | T023/024; hinreichendes Screening, Nachbarvereinfachung ist keine reale MSCR-Genauigkeitsgarantie |
| LOCAL | sämtliche rank-one PSD-Tests, lokale Inversenverhältnisse separat | Matrixtest auch singulär definiert; lokale Zulässigkeit impliziert nicht G0 |
| E2/WN | exaktes Woodbury, endliche Neumann-Reihe, exakter Rest, Normgrenze und Fehlannahmentests | T025–028; exploratory_noncertifying, keine unbelegte einseitig sichere Planungsrestriktion |

M1-Mindestdiagonale und MIIF-Referenz sind vor dem Optimieren gespeicherte Zertifikatsparameter, keine künstliche physikalische Erdung. Passive M1-Nebendiagonalen werden nur innerhalb 1e-10 absolut/1e-12 relativ auf den gemeinsamen Modellstempel kanonisiert; die Inverse wird danach neu berechnet. Die G2/M1-Infeasibilität ist ein Ergebnis der festen Strategien, kein Anlass zum Ändern von Kapazitäten, Mindestleistung oder alpha.

## 3. Theorem → Code → Tests

| Mathematische Aussage | Implementierung | Ausgeführte Evidenz |
|---|---|---|
| T001–004: physischer Stempel, Quellenbasis, Schur | PaperADiagnostics.reconstruct; AP2-Import/Referenz | raw Y/L/B0, native MVA ungleich 100, Quellen einmal, Netztest 54/54, 687 unabhängige Zustände |
| T004–006: singulärer Support | finite_spectrum: PSD-Nullblock, Pseudoinverse und Range-Projektor | positiver/singulärer Nullblock, Range-Verletzung, negativer Nullblock, all-zero exposure; kein epsilon-S |
| T005 und T007–010 | G0, exaktes B\p und LOCAL | B=[1,-1/2;-1/2,1], p=(1/4,2/3): G0/G3 PASS, G1/M0 FAIL, Zp=(7/9,19/18); p=(3/4,3/4): LOCAL PASS, G0 FAIL |
| T011–016 | vorhandenes G1; FixedScalingGSCR | beide eingefrorenen G1/G2-Gegenbeispiele mit r=(2,1), Identität reproduziert G1 |
| T017–020 | ExactEdgeSOCGSCR und unabhängiges verify_g3 | fehlende/doppelte Kante und falsches sqrt(2) abgelehnt; singulärer Laplacian, reduzible Blöcke, isolierte Nullzeile; Nicht-Z-PSD ist kein G3-Äquivalenzfall |
| T021/022 | erzwungener Mindestmatrixbereich und inverse Ordnung | positives M1-Modell; uneingeschränkte falsche Mindestmatrix verworfen; Stempelrundung getestet |
| T023/024 | InteractionGSCR, feste volle/sparse W | negative Gewichte/falsche Diagonale abgelehnt, tatsächlicher Kostenunterschied getestet |
| T025–028 | inverse_updates | Woodbury-/Restresiduen, Fehler<=Normgrenze innerhalb Region, außerhalb Grenze null; falsche sichere Inverse-I-Abkürzung widerlegt |

Alle neuen Fälle sind in test/paper_a_ap3.jl und den dedizierten Evidenztests enthalten. Die integrierte Enumeration fixiert alle unabhängigen Integerentscheidungen des vorhandenen AP2-Fixtures: PV=1, BESS=1, SYN=0:4, online=installed, keine Ereignisvariablen. Je fünf SDP-/SOCP-Teilprobleme sind vollständig abgearbeitet und liefern dasselbe Optimum. Die getrennte 2-Regionen-Enumeration bearbeitet je 16 Zuweisungen für G0/G3/M0, insgesamt 48; Vollständigkeit ist explizit gespeichert.

## 4. Unabhängige Metriken und acht ausgeführte CLI-Aktionen

124 Registry-IDs, **68.861 Datensätze**, **687 Zeitpunkte** und **124 unabhängig wirtschaftlich geprüfte Lösungen** sind exportiert. Die vollständigen Formeln, Einheiten, Shapes, Scope, Theoremreferenzen und Toleranzen stehen in metrics_final/metric_registry.json und im [Metrikregister](../docs/paper_a/ap3_evaluation_metric_registry.md). metric_coverage.json führt jeden ID mit berechneten Werten und Null-/Domänenzuständen. Positives M1 und innerhalb/außerhalb der Neumann-Normregion liegen zusätzlich als gezielte Fixtures vor.

Physische Matrizen werden aus originalen Leitungs-/Shuntdaten und gelösten Blockentscheidungen neu gestempelt, nicht aus JuMPs B/M-Cache. Erst anschließend erfolgt der Vergleich. G3-q darf als Witness gelesen werden, aber Kanten, Produkte, Knotenreste und Rekonstruktion werden unabhängig geprüft. Eigenspaces und Multiplizität bleiben bei Entartung explizit. Inversen benötigen PD, Kondition<=1e12 und passende Vorzeichen. All-zero exposure und fehlende Nenner erhalten null mit konkretem Status.

CSV und JSON teilen die kanonischen Felder value_or_null, validity_status, equation_reference, independent_method, unit, base, domain_predicates, tolerance, residual und solver_status sowie vollständige Fall-/SHA-Provenienz. Horizontkosten und Ereignisse stehen einmal pro Lösung, nicht pro Snapshot. S_nom, S_on und abs(discharge-charge)-basierte S_op-Magnitude sind getrennte Versionen. S_I fehlt ohne Strom-/Spannungskonvention. Externe SCR/ESCR/MSCR/gSCR bleiben not_comparable_missing_source_fault_convention. Separater FOM ist aus dem gebündelten deklarierten Preis nicht identifizierbar. Nicht verfügbare Solverattribute und Peak-RSS sind null; allokierte Bytes werden separat gemessen.

Alle Befehle nutzen julia --startup-file=no --project=. scripts/paper_a/ap3.jl ACTION INPUT OUTPUT vom Repository-Stamm. Tatsächliche Argumente/Exitcodes: paper_a_ap3_cli_execution_manifest.json außerhalb des unveränderlichen Laufindex. OUTPUT war jeweils neu, Versuche blieben erhalten.

| Aktion | Tatsächliche Eingabe → Ausgabe unter ap3_runs/20261020_macro |
|---|---|
| run_formulation_suite | suite_config.json → suite_final; Folge-/Fixläufe → dokumentierte Teilordner; akzeptierte Auswahl → accepted_suite; zusätzlicher relativer Eingabereplay cli_replay_config.json → cli_replay_suite (BASE/G0/G3 jeweils optimal) |
| reconstruct_strength_matrices | accepted_suite → matrices_final und unabhängiger Wiederholungslauf matrices_replay |
| evaluate_strength_metrics | matrices_final → metrics_final |
| verify_certificates | matrices_final → certificates_final |
| compare_formulations | accepted_suite → comparisons_final, einschließlich separater Integer-Referenztabelle |
| assess_planning_results | accepted_suite → planning_final |
| benchmark_conic_scaling | cli_replay_config.json → benchmarks_final; Größen 2/4/8/16, jeweils G0/G3, 8/8 optimal; erster Funktionslauf separat erhalten |
| export_paper_a_evidence | gesamter Lauf → export_final mit Hashindex; letzter schreibender Laufbefehl |

Große metrics.json/metrics.csv werden verlustfrei als benachbarte ZIPs publiziert und lokal zusätzlich unkomprimiert erhalten. Archivinhalt und Rohdatei sind SHA256-identisch; Nachweis metric_archive_verification.json. Der Exportindex erfasst auch die rekonstruierbaren Rohdateien. Vor Replay in frischem Clone müssen ZIPs extrahiert werden. [Bedienungsanleitung](../docs/paper_a/ap3_postprocessing_user_guide.md) enthält relative Reproduktionsbefehle. Laufkonfigurationen mit ursprünglichen absoluten Pfaden sind Provenienz; kopierte Fallbytes und Lösungen genügen für Postprocessing ohne Producer-Checkout.

## 5. Solver, Versionen, tatsächlich ausgeführte Tests

Julia **1.10.11**, JuMP **1.31.1**, MOI **1.51.2**, HiGHS.jl **1.24.1** / Backend **1.15.1+1**, Clarabel **0.11.1**, Pajarito **0.8.3**, PowerModels **0.21.4**, PowerModelsACDC **0.9.4**, JSON **0.21.4**, CSV **0.10.16**. Project SHA256=23f90a015f17a094d017f3ea691bce44d0eb4f1d4db700ce6dead43d11a8a2c4; Manifest-v1.10 SHA256=b9eedeeafffcb54fffea110f84d137b7115171020c80566c57abd1107220ab40. Vollständige Paketversionen und Quellhashes sind in den jeweiligen provenance.json-Dateien enthalten; einzelne Läufe haben ausdrücklich verschiedene Quellstände und werden nicht als ein gemeinsamer historischer Prozess ausgegeben.

Tatsächliche Capability-Proben: HiGHS LP/MILP PASS, PSD/SOC und gemischte Konen unsupported; Clarabel LP/SDP/SOCP PASS, Integer unsupported; Pajarito-OA mit HiGHS/Clarabel kleine LP/MILP/SDP/SOCP/MISOCP/MISDP PASS. Dies bedeutet keine native MISDP-Unterstützung. Gurobi-Paket vorhanden, tatsächlicher MISOCP-Probelauf solver_unavailable: Error 10009, Lizenz abgelaufen am 2026-10-12. Optionales allgemeines M0-NLP wurde nicht ausgeführt; vollständige begrenzte Enumeration deckt den beauftragten Referenzpfad ab.

HiGHS: 1 Thread, Seed 20261020, mip_rel_gap=1e-8, Zeitlimit 120s; Clarabel: feasibility/absolute/relative gap 1e-10, max_iter=300 im Runner; Pajarito: iterative OA, rel/feas 1e-7, abs gap 1e-8, Zeitlimit 120s, Iterationslimit 100. Modellproben und Tests haben separat dokumentierte Toleranzen. JuMPs aktive MOI-Bridge-Konfiguration wird gespeichert. Laufzeiten enthalten je nach Erstaufruf Kompilierung; keine plattformunabhängige Speedup-Behauptung.

| Neuer Lauf | Ergebnis / Prozess-Exit | Log im Laufverzeichnis |
|---|---|---|
| vollständige historische Consumer-Suite plus AP3 | **6086/6086**, Exit 0, 5m00,6s | full_regression_frozen_final.log |
| AP2 | **153/153**, Exit 0 | ap2_final.log |
| qualifizierter parametrischer Consumer | **291/291**, Exit 0 | parametric_acceptance_final.log |
| physischer Netz-/Schur-Audit | **54/54**, Exit 0 | network_audit_final.log |
| gepinnter historischer Producer-Consumer-Test | **51/51**, Exit 0 | historical_producer_final.log |
| endgültige gespeicherte CLI-/Schema-/Residualprüfung | **4108/4108**, Exit 0 | evidence_acceptance_release_fixed.log |

Die alten 5987 Consumer- und 4162 Producer-Tests werden nicht als neue Läufe ausgegeben. Der neue Gesamtconsumerlauf enthält 99 AP3-Prüfungen zusätzlich zu den 5987 historischen Prüfungen. Producer 4162 bleibt übernommene Strang-B-Evidenz. Die drei alten Integer-INFEASIBLE und drei LP-OPTIMAL synthetischen Fälle sind frisch als negative/positive Regression bestätigt. Der Kernquellstand der Vollregression bleibt nachher unverändert; spätere Exportstatus-/Schema- und Plotänderungen werden durch tatsächliche CLI-/Evidenzläufe geprüft.

Fehlversuche sind erhalten: anfängliche Compile-/API-/Fixturefehler, mathematische Testkorrekturen, M1-Stempelrundung, gemischter laufender/geladener Quellstand in früheren Testprozessen, Pajarito-Konussolverversuche, per-Zeile-Git-SHA-Exportperformance, fehlende CSV-Nothing-Konversion und vorübergehend fehlender Not-applicable-Status für LP-Integrality. Die abschließende strengere Schemaerweiterung fand genau diesen LP-Statusfehler (4105 PASS/1 FAIL); nach Korrektur ist der neue Lauf bestanden. Frühere Logs werden nicht gelöscht oder als gültige Endresultate ausgegeben. Ordner mit before/attempt/smoke sind historische Versuche, keine autoritativen finalen Ausgaben.

## 6. Residuen und numerische Referenzqualität

| Unabhängige Prüfung | Schlechtester gespeicherter Wert |
|---|---:|
| B/S/M gegenüber affinem Modell | 3,410605131648481e-13 |
| B0 gegenüber Producer-Referenz | 1,1368683772161603e-13 |
| Quellenbasis / passiver Schurrest | 0 / 0 |
| a_conn-Verletzung | 1,879774598997735e-12 |
| B*(B\p)-p | 1,723066134218243e-13 |
| G3-Matrixrekonstruktion | 0 |
| kontinuierliche duale Kegelverletzung | 0 |
| skalierte Komplementarität | 1,5020270045042895e-9 |
| unabhängige Kostenabweichung | 0,015338363593471627 deklarierte Währung |
| Leistungsbilanz | 1,7107284813599136e-10 MW |
| SOC / terminaler Rest | 5,014338228752736e-10 / 3,822337043761258e-11 MWh |
| UC-Transition / Integerrest | 5,266898028821743e-13 / 3,694822225952521e-13 |
| Blockgrenzen / thermische Verletzung | 1,0203837774724889e-11 / 0 |

Matrixabgleich wird mit 1e-7 geprüft, Verbindungs-/Blockgrenzen mit 1e-5, Leistungs-/SOC-Reste mit 1e-3, unabhängige Währungskosten mit 1 Einheit. Spektral-/Zeilentoleranz=1e-7*max(1,||B||inf); Inversenvorzeichen/-ordnung entsprechend ||Z||inf, Konditionsgrenze 1e12. Die vergleichsweise große absolute Währungstoleranz ist getrennt von den publizierten Rohresten und relativen Optimierungsgaps. Degenerierte oder schlecht konditionierte Inversen werden nicht für gültig erklärt.

Maximale kontinuierliche G0/G3-Kostenabweichung: **2,9145552914810813e-7 relativ**. Unabhängige G0-/G3-Kreuzfeasibility ist geprüft. Identische Kosten erzwingen kein identisches Portfolio. Referenzintervalle der neun Integerprobleme werden aus kompatiblen globalen Solver-Untergrenzen und unabhängig geprüften zulässigen Punkten gebildet, identische Fallhashes vorausgesetzt. Schlechteste Originalwährungs-Gap **1,056684966470984e-9**, Prüftoleranz 1e-6. Die Methode beruht auf eingefrorener Z-Klassen-Projektion T018–020; keine Intervallarithmetik und keine unabhängige A3.5-Zertifizierung.

Pajaritos rohe relative Gap verwendet den Zielfunktionswert ohne affinen Offset. Der Runner berichtet deshalb Originalwährungswerte und berechnet deren Gap separat. Positive Kostenvariablen mit positiver Untergrenze können exakt als Inkremente plus unveränderter Konstante dargestellt werden. Positive Zielfunktionsskalierung, Quelle der verwendeten Bounds und rohe Gap bleiben nachvollziehbar. Native G3-INFEASIBLE-Meldungen werden trotz alternativer zulässiger Punkte nicht nachträglich als native OPTIMAL ausgegeben.

## 7. Neun parametrische Szenarien und Planungsaussagen

reference_3snap, reference_6snap, reference_24snap, bess_premium_3snap, connectivity_3snap, event_price_3snap, exposure_multiplier_3snap, source_reactance_3snap und threshold_3snap wurden mit den gepinnten Registry-/Szenariohashes bearbeitet. Die ausgewählte Suite umfasst 162 Einträge: **124 optimal, 36 infeasible, 2 numerical_inconclusive**. Beide Skalierungsgrade von G2/M1 bleiben ausdrücklich erhalten. Ergänzende Solver-, Dual-, Konditionierungs-, Inkrement- und Integerfixierungsläufe liegen separat und mit eigenem Quellhash vor.

Alle Formulierungsvergleiche verwenden dieselben S_on-, Alpha-, Zeit-, Kosten-, Speicher- und Integerdefinitionen. Andere physikalische Exposuredefinitionen werden nur als getrennte Sensitivitätsmetriken ausgegeben. G1-Kostenaufschlag über G0 im kontinuierlichen Teil: **0,0146184 % bis 1,0435754 %**; G2_identity entspricht G1. Die exakte Szenariotabelle steht in comparison_table.csv und parametric_comparison.md, alle absoluten Kosten und Portfoliodifferenzen in comparisons_final. plots_final/cost_conservatism.png/svg wurden aus diesen Zahlen erzeugt und visuell geprüft.

Beispiel reference_3snap, kontinuierlich: G1 baut 180,916 MW GFM in BE0 3 zu 9.523,247 Horizont-Investitionskosten; M2_full 367,889 MW zu 19.365,303; M2_neighbor 208,013 MW zu 10.949,630. G0/G3 benötigen hier keinen materiellen Neubau: winzige Solverreste um 0,00035/0,00057 MW GFM und geringfügig negative Nullrestwerte bleiben in den Rohdaten sichtbar. Dies belegt die konservative Standortwirkung der festen Screens auf diesem deklarierten Beispiel. Es ist keine Aussage über reale belgische Ausbaukosten oder empirisch notwendige Kapazität.

Die regionalen Quellen-/Exposure-Ledger, installierte/neue MW/MVA/MWh, Dispatch, Ereignisse, Speicherbetrieb, SOC, Curtailment, Impedanzen, MIIF und lokale/globalen Margen sind maschinenlesbar vorhanden. Ereignisse und Zeitgewichte werden unabhängig nachgerechnet; separate FOM bleibt unbekannt. Die 9/18/72-Stundenfenster und zeitanteilige annualisierte CAPEX sind illustrative Horizonte, keine kalibrierte Jahresstudie. Es wurde kein Mindestleistungsproblem durch Eingriff in die Daten gelöst. M1s feste inverse Obergrenze kann restriktiv sein; die tatsächliche Studie besitzt Quellenkandidaten in allen Regionen, daher ist deren Infeasibilität nicht pauschal mit einer fehlenden Quellenregion erklärt.

## 8. P-C2A-001–010: fallbezogene Worker-Matrix

Die folgenden PASS bewerten Prüfung und Implementierung im genannten Teilbereich. Sie erklären nicht jeden BASE-Zustand für zulässig und ersetzen keine historische Predicate-Freeze-/Ownerentscheidung. certificates_final enthält die konkreten Werte pro Zustand; negative mathematische Fixtures stehen in den Tests.

| Predicate | Workerstatus / Evidenz / Toleranz | Offene universelle oder empirische Aussage |
|---|---|---|
| P001 Symmetrie | PASS: unabhängiges B/B0 und Symmetrie; 1e-7 | keine allgemeine Netzdatenfreigabe |
| P002 Nebendiagonalzeichen | PASS: Z-Klasse explizit geprüft, Nicht-Z-Gegenbeispiel verworfen; 1e-7 skaliert | keine neue Äquivalenz außerhalb Z |
| P003 PSD/PD/Nullmoden | PASS: Eigen-/Inertia-/Nullity-Klassifikator und singuläre Fixtures | universelle PD über alle möglichen Zustände: NOT_EVALUATED |
| P004 Inversenpositivität | PASS: PD/Kondition/Vorzeichen-Gate und Gegenbeispiele; 1e-7*max(1,||Z||inf) | universelle Inversenannahme: NOT_EVALUATED |
| P005 exakte G1-Zeilen | PASS: M*1 unabhängig, Fehlablehnungen bewusst sichtbar; 1e-7 skaliert | BASE/G0 müssen G1 nicht erfüllen |
| P006 diagonale Quellen | PASS: native Basis und Rekonstruktion max 3,411e-13 | empirische Quellenwahrheit: NOT_EVALUATED |
| P007 Exposure/Basis | PASS: S_on>=0, gleiche Systembasis, a_conn, getrennte S-Varianten | S_I ohne Konvention blockiert |
| P008 vollständiges G3 | PASS: Kanten/RSOC/Knoten/Witness/negative Fixtures, Rekonstruktion 0 | native Integer-Solverqualifikation RESTRICTED, Blocker B1 |
| P009 singuläres Exposure | PASS: positive/PSD Nullblöcke, Range, all-zero und lokale Singulärfälle | kein epsilon-Ersatz, undefinierte Quotienten bleiben null |
| P010 unabhängige Nachrechnung | PASS: raw Netzwerk + Entscheidungen; identisches Replay-SHA; Kosten/SOC/Bilanzreste wie oben | keine unabhängige A3.5-Signatur |

## 9. Blocker, Grenzen und nächste unabhängige Entscheidung

Ein technischer Blocker ist in blocker_register.json zusammengeführt: **B1 native G3-MISOCP-Zuverlässigkeit**. Capability-Proben, Konditionierung, exakte Inkrementkoordinaten, Integerfixierung und projektionsgleiche G0-Bounds wurden tatsächlich ausprobiert. Sie liefern gültige Referenzen, beseitigen aber die native Falsch-Infeasibilität nicht. Ein belastbar qualifizierter alternativer Solver oder nachvollziehbarer numerischer Fix ist vor uneingeschränkter nativer MISOCP-Freigabe erforderlich.

Separate externe Gates sind empirische Daten-/Quellen-/Kostenqualifikation, Fehlerstrom-/Spannungskonventionen, repräsentative Studiengestaltung und unabhängiges Review. Sie sind keine fehlende Implementierung der zulässigen parametrischen Arbeit. Es wurden keine neuen Theoreme, kein unbewiesenes E2-Sicherheitszertifikat und keine vollständigen AC-CPF-/Dynamik-/EMT-/TNEP-Modelle erfunden. AP4 oder Publikationsreife ist nicht erreicht.

Die A3.5-Übergabe enthält die genaue Gleichung-Code-Test-Prüfliste einschließlich Originalwährungs-Bounds, singularer Range-Bedingung, G0/G3-Domäne, M1/M2 und Exportreplay. **A3_closed=false; AP4_ready=false.**
