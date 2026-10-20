# Paper A — A3.5-EXEC: unabhängiger ausführbarer Abschlussbericht

Datum: 20.10.2026. **Abschlussstatus: `blocked_by_solver_or_data`.** Die geprüften Gleichungen sind für die registrierten numerischen Fälle nachvollzogen; vollständige wissenschaftliche A3-/AP4-Freigabe ist nicht erteilt.

## 1. Autorität, SHA und Unabhängigkeit

Verbindlicher Makroauftrag: FlexPlan `50f88d5d30194afbbd188c96e3eab795b7a7de49`. Unverändertes AP3-Prüfziel: **`485b637cc1998a327206c5929434bd26c6f0be16`**. Der gemeldete Revieweingang `29192398bc7819a533b1e436c7f176b8dadb56e4` ist direkter Parent des tatsächlichen Reviewheads; hinzu kam ausschließlich der Makroauftrag. Keine stille Baselinesubstitution. Neuer sauberer detached Worktree `D:\Projekte\Code\FlexPlan_A35_EXEC_BASELINE`. Die bereits vorhandenen AP2-/AP3-/Strang-B-Arbeitsverzeichnisse einschließlich untracked `audit/` blieben erhalten.

Wissenschaft: research-map/main `e8118425adc335a99e85120d943763305f211315`, Ursprungsfreeze `2c2fce769b2ed6ffd4f1ced60c0798776acccc93`, Paper-A-Scope `672a61c95525bf1d7a03cf745a754a15a23ce78b`, SCIENCE/FINAL `2badb9a90a8d3c1d4a33accee640b295de1e33a1`. Das vorgeschlagene Amendment am Commit `5ceb19a6faf4e7c7e797a737ed5b449f9e2db609`, Blob `fba4802ecabade61a752833a71106a5bda4ce78f`, bleibt **nicht ratifiziert**. Acht bytegenaue Quellensnapshots und ihre Git-/SHA256-Identitäten stehen in `science_source_manifest.json`.

Producer: `b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c`, numerische Daten exakt aus Git-Archiv von `3b8fdb01d931225edc5f8fe1e2c200d0da288a09`. Producer und research-map wurden nur gelesen; Fetch änderte ausschließlich lokale Git-Objekt-/Remotereferenzdaten. Originale Wissenschaft, Producerdaten, historische Outputs und Original-AP3-Branch wurden nicht geändert.

## 2. Specification Gate, Wiederverwendung und Änderung

`SPECIFICATION_READY`: Gleichungen, Domänen, Pflichtgegenfälle, Prüfgrenzen und Freigaberechte sind durch den Makroauftrag bestimmt. Produktionsaufbau, AP1-Import, AP2 affine Matrizen, UC/Storage, Ziele, Solveradapter und CLI wurden wiederverwendet. Die neue unabhängige Referenzberechnung verwendet keine `PaperADiagnostics`-/`AP3Pipeline`-Berechnungen als Oracle. Diese Routinen dienen ausschließlich zum Bau des echten Prüfobjekts oder als Vergleichsziel.

`pre_fix_original_adjudication.md` wurde vor der Produktionskorrektur geschrieben. EXEC-UNIT-001 bestätigt drei falsche Exporteinheiten. Kontrollierte einzige Fixbranch: `fix/paper-a-a3-5-executable-closure-v1`, Parent `50f88d5d30194afbbd188c96e3eab795b7a7de49`, Codekorrektur **`e1e075626b38b478faf57efe62e557fc94753f00`**. Diff in Produktionscode: zwei neue Zuordnungszeilen in `metric_unit`; drei IDs korrigiert. Keine Gleichung, zulässige Menge, Solverstrategie, Datenannahme oder Zielfunktion wurde geändert. Eine zweite personell unabhängige mathematische Abnahme eigener substanzieller Codeänderungen ist daher hier nicht ausgelöst. Die allgemeine Freigabe bleibt aus anderen Gründen false.

## 3. Tatsächlich ausgeführte Validierung

Julia **1.10.11**, Manifestformat 2.0. `Pkg.instantiate()` war erfolgreich; getrackte Project-/Manifestdateien und Baselinesourcen blieben bytegleich. Versionen aller Pakete stehen in `environment.log` und den Laufprovenienzen. CPU/Threads/BLAS in `runtime_capabilities.json`. Unabhängige Pythonumgebung: SymPy 1.14.0, NumPy 2.5.4, isoliert im Scratchbereich.

* Vollregression unveränderter Produktionscode: **6087/6087**, Exit 0. Bytegleiche Testkopie im Scratchverzeichnis verhindert Überschreiben historischer Reports.
* Gespeicherte Originalevidenz: **4108/4108**, Exit 0; vorab verlustfrei extrahierte Metrikarchive.
* Neue eigenständige MOI-/Grenz-/Mutationssuite: **42/42**; zusätzliche rohe Domänenmutationen: **16/16**.
* Zusätzlicher unabhängiger Koeffizientenvergleich tatsächlicher G1/G2/M1/M2-Constraints: **34/34**.
* Drei Einheitenkorrekturen: **4/4** fokussierte Tests; vollständiger Exportvergleich separat.
* Frische Formulierungssuite: **162 Läufe**, tatsächliche Statusverteilung **{'optimal': 108, 'infeasible': 36, 'numerical_inconclusive': 18}**. Keine früheren PASS-Zahlen übernommen.
* 8 Größen-/Formulierungsbenchmarks für G0/G3, Größen 2/4/8/16; tatsächliche Ergebnisse in `benchmark.json`.
* AP1-Synthetic-3/6/24-, Parameter-/Netz- und negative historische Producerprüfungen sind durch echte Prozesse bzw. die Vollsuite erfasst; Prozessliste unten.
* Zusätzliche explizite AP1-/Parameter-/Netzprüfungen: **51/51**, **291/291**, **54/54**.

| Prozess | Exit | Start UTC | Ende UTC |
|---|---:|---|---|
| full_regression | 0 | 2026-10-20T13:21:13.0078169Z | 2026-10-20T13:29:25.5624536Z |
| saved_evidence | 0 | 2026-10-20T13:29:25.6304683Z | 2026-10-20T13:30:23.461549Z |
| make_config | 0 | 2026-10-20T13:30:23.4681834Z | 2026-10-20T13:30:26.1883604Z |
| cli_suite | 0 | 2026-10-20T13:30:26.1923605Z | 2026-10-20T13:48:54.389936Z |
| cli_matrices | 0 | 2026-10-20T13:48:54.393717Z | 2026-10-20T13:49:34.111827Z |
| cli_metrics | 0 | 2026-10-20T13:49:34.1156636Z | 2026-10-20T13:50:48.0088397Z |
| cli_certificates | 0 | 2026-10-20T13:50:48.0129121Z | 2026-10-20T13:51:33.8329633Z |
| cli_comparisons | 0 | 2026-10-20T13:51:33.8355966Z | 2026-10-20T13:52:36.3277173Z |
| cli_planning | 0 | 2026-10-20T13:52:36.3325029Z | 2026-10-20T13:53:00.8246229Z |
| cli_benchmarks | 0 | 2026-10-20T13:53:00.828555Z | 2026-10-20T13:53:48.246209Z |
| ap1_acceptance | 0 | 2026-10-20T13:53:48.2542751Z | 2026-10-20T13:55:00.2092548Z |
| parameter_acceptance | 0 | 2026-10-20T13:55:00.2134709Z | 2026-10-20T13:57:59.4899861Z |
| network_audit | 0 | 2026-10-20T13:57:59.4932729Z | 2026-10-20T13:58:37.6930346Z |
| cli_export | 0 | 2026-10-20T13:57:14.8536715Z | 2026-10-20T13:57:49.8162345Z |

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

Unabhängige gesamte Rekonstruktion: **1299 Zustände**, **232 Lösungen**, maximale Modellmatrixabweichung **3.41060513165e-13**. Keine künstliche Slack-Erdung, keine Epsilon-Exposition. Transformatoren/komplexe Taps werden separat gestempelt und die nicht unterstützten Produktionsfälle tatsächlich abgewiesen. Die registrierten Producerdaten führen weiterhin `fixed_shunt_inventory_unverified`, `baseline_source_accounting_unverified`, `grounding_reference_unverified`: der strikte Netzaufruf weist diese Eingaben ab; nur der deklarierte parametrische Diagnosepfad erlaubt sie. Das beschränkt die physische Abnahme.

Die vorgeschlagene Kette M2⇒G1⇒M0⇒G0 und G0⇔G3 wird nur auf gleicher symmetrischer inverspositiver bzw. vollständiger Z-Domäne verwendet. M0⇒G0 ist als bedingter mathematischer Satz geprüft; damit wird das Amendment nicht normativ aktiviert. Kein M1-INFEASIBLE⇒M0-INFEASIBLE und keine allgemeine M1/G1-Kostenordnung.

## 5. Native G3 und B1

Der unveränderte exakte Solvepfad liefert für `reference_24snap` **INFEASIBLE**. Derselbe serialisierte Original-MISOCP besitzt den vollständig überprüften Witness mit maximaler Constraint-Verletzung **7.5153490016e-12** einschließlich Integerbedingungen und Rebase-Gleichungen. Nach tatsächlichem Bridging beträgt der größte Kegelabstand **8.83513342703e-11**. Damit ist für diese Instanz der Infeasibilitätsbefund des Solverpfades falsch; ein Modell-Infeasibilitätsbeweis liegt nicht vor.

Rohlogs und erzeugte native/OA-/Relaxationsmodelle sind erhalten. Die konkrete interne Ursache innerhalb OA-Schnitten, LP-Numerik und Conic-Integration ist nicht abschließend isoliert. Eine positive Objective-Skalierungsvariante löst den Fall numerisch, begründet aber keine generelle Qualifikation oder automatische Produktionsänderung. Gurobi ist installiert, scheitert jedoch tatsächlich an Error 10009 (Lizenzablauf 2026-10-12); MOSEK 11.0.29 liest das echte Integer-CBF, scheitert an 1001/LICENSE_EXPIRED. `native_G3_MISOCP=numerical_inconclusive` bleibt offen.

## 6. Neun Integerreferenzen und Geldkoordinaten

Alle neun Fälle wurden mit vollständig rekonstruierten Integerzuweisungen in neuen G0- und G3-Modellen kontinuierlich nachgelöst. Alle Constraints, UC-/Storage-/Powerflow-Variablen und Integer-/Domainbounds sind geprüft, Kosten aus Rohpreisen, Dauer und Ereignisgewichten neu berechnet. Zur Auswahl der Zuweisungen wurden die früheren billigsten Witnessdateien nur als Seeds verwendet; deren SHA und sämtliche neue Prüfungen sind verzeichnet. Frühere PASS-Flags wurden nicht übernommen.

Die Tabelle zeigt den historischen **Solver-Untergrenzenanspruch** und die frisch unabhängig nachgerechnete zulässige Obergrenze. Die Differenz bleibt vorzeichenbehaftet; negative numerische Abstände werden nicht durch Absolutbetrag in formale Intervalle verwandelt. **In acht der neun Fälle liegt der historische Untergrenzenanspruch geringfügig über der neuen zulässigen Obergrenze, maximal rund 0.00025504 Währungseinheiten.** Dies ist eine gesonderte Toleranz-/Konsistenzabweichung; ihre Ursache wird nicht ohne weiteren Nachweis ausschließlich Rundung zugeschrieben. Der Anspruch ist ohne eigenständigen belastbaren globalen Dual-/OA-Nachweis **kein mathematisch rigoroses Zertifikat**.

| Fall | historische LB-Behauptung | neue feasible UB | UB−LB | G0/G3 Fixkosten-Differenz |
|---|---:|---:|---:|---:|
| bess_premium_3snap | 2524596.12189921 | 2524596.12187864 | -2.0570587e-05 | 2.2094e-05 |
| connectivity_3snap | 2594530.97025797 | 2594530.97020251 | -5.5465847e-05 | 5.7159e-05 |
| event_price_3snap | 5608912.20245683 | 5608912.20220179 | -0.00025503617 | 0.00025581 |
| exposure_multiplier_3snap | 2524596.12189921 | 2524596.12187787 | -2.13366e-05 | 2.2862e-05 |
| reference_24snap | 14128094.08629125 | 14128094.08619229 | -9.8954886e-05 | 0.00010576 |
| reference_3snap | 2524596.12189921 | 2524596.12187864 | -2.0570587e-05 | 2.2095e-05 |
| reference_6snap | 4085284.71558798 | 4085284.71987637 | 0.0042883884 | 6.4245e-05 |
| source_reactance_3snap | 2524596.12189921 | 2524596.12181627 | -8.2936138e-05 | 8.4755e-05 |
| threshold_3snap | 2524596.12189921 | 2524596.12187844 | -2.0769425e-05 | 2.2301e-05 |

Weitere BASE-LP-Untergrenzen und Kostenkomponenten stehen im JSON. Ein LP-Relaxationsbound ist fallbezogen ein numerischer unterer Bound, kein Ersatz für vollständige Integerenumeration. Die neun großen Suchräume wurden nicht vollständig enumeriert. `integer_globality=partial`. Alle Boundwerte werden in ursprünglicher Geldkoordinate ausgewiesen; positive Skalierung wird rückgerechnet, konstanter Investitionsoffset und zusätzliche Increment-Gleichungen sind explizit geprüft. Größte unabhängig gefundene Objektivabweichung über alle archivierten/frischen ausgewerteten Lösungen: **0.0153383635916** Währungseinheiten. Diese Residualzahl ist von einem Optimalitätsgap zu unterscheiden.

## 7. Metriken, CLI, Chronologie, Daten

| Datenstrom | IDs | JSON-Zeilen | CSV-Rundlauf |
|---|---:|---:|---:|
| historical | 124 | 68861 | 68861 |
| fresh | 124 | 61272 | 61272 |

Für alle IDs sind Formel-/Wert-/Null-/Basiskontrollen dokumentiert. Bei Laufzeit-/Solverdaten bedeutet dies attributtreuen Export; tatsächliche CPUzeiten historischer Läufe sind nicht erneut unabhängig messbar. Dualexporte sind zusätzlich an den neuen analytischen MOI-Fällen auf Kegelmitgliedschaft und Komplementarität geprüft; für historische Solves ohne vollständige Dualvektoren bleibt die unabhängige globale Dualprüfung eingeschränkt. Der vollständige Fixexport unterscheidet sich nur in den drei Einheiten und dem Versionsfeld.

Alle acht CLI-Aktionen werden in neuen Pfaden real ausgeführt, einschließlich Export mit SHA-Nachprüfung. Ungültige Aktion, fehlender Input und vorhandener Output werden negativ getestet. Nichtoptimale Solverstatus bleiben sichtbar. Einheiten von Kegelprodukten (`pu_admittance_squared`), Blockcounts und Währung werden unterschieden.

Producer-3/6/24-Snapshotdaten waren verfügbar. 24×3 h = **72 Stunden**. Energiegewicht `delta_t*representative_repetitions*scenario_probability` und Ereignisgewicht `event_repetitions*scenario_probability` werden getrennt nachgerechnet. CAPEX wird genau mit deklarierter Jahres-/Horizontfraktion angewandt; Storage-P+E-Preise bleiben ihre deklarierte parametrische Referenz, keine durch diesen Audit validierten OEM-/Studienkosten. `a_conn` und `a_res` bleiben getrennt. Installed-, online-nameplate-, Net-Dispatch- und Current-Capability-Exposition werden nicht vertauscht. Fehlendes S_I und externe Fault-/SCR-Normen bleiben explizit fehlend/nicht vergleichbar. Keine Jahresrepräsentativität der kurzen Beispielzeiträume.

## 8. Evidenzintegrität, Reproduktion und Übergabe

**14/14 historische ZIPs** vollständig auf CRC und enthaltene SHA256 geprüft; **1060/1060** Einträge des historischen Evidenzindex stimmen in Hash und Größe (fehlende entpackte Originaldateien werden durch die bytegleichen ZIP-Einträge verifiziert). Keine Stichprobenaussage. Rohdaten-, Quellen-, Code-, Paket-/Manifest-, Log- und neue Outputhashes bilden die Reproduktionskette. Große neue Metrik-/MOI-/Witnessdateien sind verlustfrei archiviert; Archiv- und enthaltene Rohhashes stehen im Reproduktionsmanifest. Keine historischen Archive überschrieben.

Lesereihenfolge: dieser Bericht → `release_gates.yaml` → P-/T-Ledger → `g3_native_misocp_and_edge_completeness.md` → neun Integerfälle → `metrics_124_cli_8_replay.md` → Manifest und ausführbare Oracles. Artefakte sind Ergebnisdaten, keine zusätzlichen fachlichen Autoritäten.

Nachgelagerter unabhängiger Prüfer: Original `485b637cc1998a327206c5929434bd26c6f0be16` und Metadatenfix `e1e075626b38b478faf57efe62e557fc94753f00` getrennt auschecken; SHA-Manifeste verifizieren; Oracles und genau protokollierte Prozesse wiederholen. Für B1 zuerst `b1_exact_native_repro.jl`, `b1_transfer_full_witness.jl` und die Bridgingprüfung ausführen, danach mit tatsächlich lizenzierter nativer MISOCP-Alternative oder isolierter nachgewiesener Solverreparatur neu qualifizieren. Wissenschaftsowner muss das exakte Amendment separat ratifizieren; Datenowner muss Quellen-/Passivinventar, Zeit-/Kosten-/Studienrepräsentativität qualifizieren. Erst dann können weitergehende Gates neu bewertet werden.

## 9. Abschließende getrennte Entscheidung

Mathematik/Gleichung-zu-Code: **accepted_for_registered_cases**, mit klaren Domänen und historischen ungelösten Quellenbezügen. Original-Metrikexport: drei bestätigte kleine Einheitenfehler, korrigiert. Numerischer Replay: vollständig ausgeführt; Regression und Metrikvergleich bestanden, Solver-/Globalitätsabnahme **partial**. Native G3: **numerical_inconclusive**, falsche Infeasibilität konkret nachgewiesen. Neun Integerfälle: vollständige neue zulässige Witnesspaare und numerische Bounds, **keine rigorose allgemeine Globalitätszertifizierung**. Physik-/Empiriedaten: **unqualified/conditional**.

`science_amendment_approved=false`; `independent_A3_5_accepted=false`; `A3_closed=false`; `AP4_ready=false`; `empirical_study_ready=false`.

**Einziger Schlussstatus: `executable_closure_verdict: blocked_by_solver_or_data`.** Keine PR, kein Merge, Reset, Rebase, Force-Push oder Änderung fremder Branches. Der finale Remotehead wird nach Veröffentlichung gesondert per `git ls-remote` verifiziert.
