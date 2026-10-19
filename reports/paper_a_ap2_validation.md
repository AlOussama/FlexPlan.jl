# Paper A AP2 — Validierungsbericht

Stand: 2026-10-19. Spezifikation: `SPECIFICATION_READY`. Gesamturteil: **AP2_partial**. Der finale Producer wird tatsächlich durch Parser, Modell und Solver konsumiert: drei explizite synthetische LP-Relaxierungen sind optimal, die drei Integer-Fälle nachvollziehbar infeasible. Reale Studienfälle bleiben fachlich gesperrt. Abschnitt 7 dokumentiert den endgültigen, durch das vollständige Nutzer-Addendum erweiterten Stand; frühere strikte Gesamt-Sperren bleiben dort als Verlauf erhalten.

## 1. Exakte Autorität und Erhaltung

| Gegenstand | SHA |
|---|---|
| Science-Freeze, research-map, read-only | `672a61c95525bf1d7a03cf745a754a15a23ce78b` |
| Integrationsaudit, research-map, read-only | `8b78fc2d0aa22012ce75b70c0cff08d7336ebe75` |
| FlexPlan master, erneut fetched | `991d0e99627b9bd57b3df476c66141ae6bb5163d` |
| AP2 Remote-Einstieg | `a80c3514dd08b21caa0388918099d5771c42c426` |
| AP2 Implementierungscommit | `71faeffb30d947c48f2b61339bdcb55f8d2c80c3` |
| AP1 im Auftrag genannter Stand | `00b259da66f084e00d53c5dc1be4d23de145fdc1` |
| AP1 beim ersten Fetch / ausgeführter Producer-Code | `991c34445f602df14592fdd0f51b5e67d3ddd782` |
| AP1 nach Integrationsaddendum, veröffentlichte sechs Varianten | `32ff4525dc576af52c16298cb35ebd98f02cf8b2` |

Finale Fetch-/Publikationsbelege stehen in `ap2_macro/provenance.json` und im Abschlussbericht. Kein Reset, Force-Push, Merge, neuer Feature-Branch oder PR. AP1 und research-map wurden ausschließlich gelesen/fetched. Der ursprüngliche Audit-Checkout hatte ungetrackte `Manifest-v1.10.toml`/`audit/`-Evidenz. Vor dem Branchwechsel wurden alle Dateien inventarisiert, kopiert und per SHA256 geprüft; Sicherung unter `.git/ap2-preflight-20261019`. Das Addendum erhielt zusätzlich `.git/ap2-addendum-checkpoint` einschließlich Binärdiff und ungetrackter AP2-Dateien. Alte Auditdateien bleiben unpubliziert erhalten.

## 2. Tatsächlicher Modellpfad und Wiederverwendung

Der zuvor isolierte Prototyp ist jetzt über `src/FlexPlan.jl`, `ref_add_uc_gscr_block!`, bestehende Template-Auflösung und `build_uc_gscr_block_integration` angebunden. AP1-JSON wird versioniert gelesen und einmalig normiert; historische Schema-v2-/No-block-Pfade bleiben erhalten. Quellenklasse und Convertermodus sind getrennt, SYN hat eine eigene Referenzmap. Die bestehende exakte Device-Override-Priorität bleibt bestehen; fehlende Templates bleiben Fehler.

AP2 konstruiert Y(+), L=-Im(Y), B0=Lrr-Lre*(Lee\\Ler) unabhängig aus physikalischen Primitiven. Online-Quellen kommen erst danach auf die Diagonale. Native MVA-Reaktanzen werden rechnerisch auf Blockbasis umgerechnet und mit exportierten Referenzwerten geprüft. Nichtunitäre Multiplikatoren gehen in Stärke und GFL-Online-Nennleistung ein. `a_conn` begrenzt Online-Blöcke; `a_res` begrenzt erneuerbaren Dispatch. G1 verwendet dieselben tatsächlich im Builder erzeugten affinen B/S/M-Ausdrücke. Das Betriebsnetz erhält getrennte DCP-Winkel-/Ohm-/Grenzgleichungen; Kandidatenspeicher geht in die Busbilanz ein.

Erhalten und gezielt erweitert: Blockvariablen, UC-Start-/Stop-Anzahlen und `na0`, P/Q/E-Grenzen, Speichereffizienzen und physische Zeitbilanz, Terminalpolicies, CAPEX-Annuität/FOM. AP1 verwendet standardmäßig Integer-Blöcke, explizit relaxierbar. Bei `BlockFixedInstalled` sind binäre technische Trennzustände möglich; fraktionale Verfügbarkeit mit dieser Policy wird klar zurückgewiesen. Eine Participation-Policy erhält die unveränderte fraktionale Ungleichung.

`scale_paper_a_costs!` und der opt-in-Zweig in `scale_data!` verwenden getrennte Dispatch-/Eventgewichte. Investitionen zählen einmal pro realem MW-Block. Bereits annualisiertes CAPEX erhält keine zweite Annuität. Overnight-CAPEX verwendet den vorhandenen Annuitäts-/FOM-Zweig genau einmal. Ein zweiter Skalierungsaufruf ist ein Fehler. SOC integriert nur physische Stunden.

Exakte PA-/X-Gleichung↔Funktionszuordnung: [Implementierungsdokument](../docs/paper_a/ap2_regional_optimization_implementation.md). Nicht implementiert: G0/G3/M0, Spektrum, Screening, TNEP, dynamische Controller, SC ohne dedizierte MVA/Mvar-/Kostenrepräsentation.

## 3. Ausgeführte Umgebung und Befehle

Consumer: Julia **1.10.11**, FlexPlan **0.4.1**, JuMP **1.31.1**, PowerModels **0.21.4**, PowerModelsACDC **0.9.4**, HiGHS.jl **1.24.1**, HiGHS-Backend **1.15.1**, JSON **0.21.4**, InfrastructureModels **0.7.9**. Vollständiger Manifest-/CPU-/BLAS-Beleg: `ap2_macro/final_environment.log`; reproduzierbarer Lock: `Manifest-v1.10.toml`.

Der vorgefundene Julia-1.10-Lock wurde zunächst ohne Paketupgrade instanziiert. Der erste Importversuch mit dem alten isolierten Depot scheiterte an nicht vorhandenen Paketen; das Log bleibt erhalten. Der erste Gesamtlauf zeigte anschließend einen echten Logger-API-Fehler zwischen PowerModels 0.21.6 und PowerModelsACDC. Ein zunächst versuchtes Preserve-all-Downgrade nur von PowerModels war mit JSON 1.6.1 unvereinbar. Der dokumentierte zweite Versuch änderte ausschließlich PowerModels 0.21.6→0.21.4 und JSON 1.6.1→0.21.4 sowie dessen nicht mehr benötigten StructUtils-Eintrag. Keine fremde Paketquelle wurde editiert. `Project.toml` erhielt nur die notwendige Standardbibliothek LinearAlgebra; die bestehenden Compat-Bereiche blieben unverändert.

Arbeitsverzeichnis: `D:\Projekte\Code\FlexPlan_UC_GSCR`. Verwendetes Binary:
`C:\Users\User\.julia\juliaup\julia-1.10.11+0.x64.w64.mingw32\bin\julia.exe`.

```powershell
$JuliaAP2 = 'C:\Users\User\.julia\juliaup\julia-1.10.11+0.x64.w64.mingw32\bin\julia.exe'
& $JuliaAP2 --startup-file=no --project=. test/paper_a_environment.jl
$env:PAPER_A_AP2_EVIDENCE = "$PWD\reports\ap2_macro\synthetic_results.json"
& $JuliaAP2 --startup-file=no --project=. test/run_paper_a_ap2.jl
$env:PYPSA_FLEXPLAN_BLOCK_GSCR_ROOT = 'D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr'
& $JuliaAP2 --startup-file=no --project=. test/runtests.jl
& $JuliaAP2 --startup-file=no --project=. test/paper_a_producer_gate.jl '.git/ap2-producer-32ff452/data' reports/ap2_macro/producer_gate_pinned.json
```

Der letzte Befehl nutzt die aus dem exakten AP1-Publikations-SHA per `git archive` ausgelesenen Daten. Diese Kopie wurde ausschließlich im FlexPlan-Git-Metadatenverzeichnis angelegt. Das Skript erzeugt bei fehlender fachlicher Evidenz ausdrücklich BLOCKED/NOT_EXECUTED, keinen angeblichen erfolgreichen Solve.

## 4. Tests und numerische Ergebnisse

| Ausführung | Ergebnis | Beleg |
|---|---|---|
| Prototyp-/Integrationsversuch 01 | 27 bestanden, 4 Fehler; fehlende Root-Base im neuen Multinetwork-Fixture, behoben | `ap2_attempt01.log` |
| Integrationsversuch 02 | 121 bestanden, 2 fehlgeschlagen; Ressourcenbindung und unzulässige exakte Floating-Point-Nullerwartung korrigiert | `ap2_attempt02.log` |
| Integrationsversuch 03 | 123/123 | `ap2_attempt03.log` |
| Erweiterter Versuch 04 | 144/144 | `ap2_attempt04.log` |
| Finaler AP2-Testtarget | **145/145**, Exit 0 | `ap2_final.log` |
| Historischer unveränderter Acceptance-Erstlauf | FAILED: JSON 1.6 gibt Object statt des verlangten Dict zurück; expliziter dicttype korrigiert | `historical_acceptance01.log` |
| Gesamtlauf 01 | 5968 bestanden, 1 fehlgeschlagen, 1 Fehler; zu früh geladener Builder und Logger-Paketfehler; beide behoben | `full_suite01.log` |
| Gesamtlauf vor vollständigem Nachtrag | **5979/5979**, Exit 0 | `full_suite_final.log` |

Die relevanten Assertions bleiben aktiv. Negative Tests erzeugen erwartete Fehlermeldungen; die eigentlichen Test-Summaries und Prozess-Enden entscheiden den Status. Der sachlich falsche ursprüngliche Singularitätstest wurde korrigiert: `Lee=[1]` ist invertierbar; ein wirklich singuläres `Lee=[0]` wird getrennt verworfen.

Testfamilien: Marker/Parser/v2, physische 2-/3-Bus-Y und tatsächliche Elimination/No-Elimination, Shunts, Inseln und fehlende Referenz-/Grounding-Evidenz, tap/phase und Basisfehler, symmetrische Z-Domäne, native MVA, mu≠1, SYN/GFL/GFM an gleicher Region, Fixed-source-Accounting, positive G1-Investition, Integer/Relaxierung/fraktionale Verfügbarkeit, technische Trennung vs Ressourcennull, fehlendes Template, BESS-GFM in storage, Kandidatenspeicherbilanz, 3h SOC mit beiden Effizienzen, Start 1→4 / Stop 5→2, unterschiedliche Dispatch/Event/Probability-Faktoren, 24×3h-Jahresrepräsentation, MW/pu, overnight/annualized und Double-scaling-Guard.

Für die bedingte 72h-Jahresrepräsentation mit Wahrscheinlichkeit 1 wird nach tatsächlichem `scale_data!` pro Snapshot Dispatchgewicht 365 und Eventgewicht 121,6666667 geprüft. Die drei gezählten Starts/Stops werden mit physischem Block-MW und Eventgewicht bewertet. Kein Event erhält zusätzlich den Faktor Δt.

| g_min | Neue SYN-Blöcke | Investition | Dispatch | Events | Zielfunktion |
|---:|---:|---:|---:|---:|---:|
| 0,1 | 0 | 0 | 600 | 0 | 600 |
| 4,0 | 2 | 500 | 1170 | 200 | 1870,0000000000005 |

Beide MILPs: **OPTIMAL**, Primal **FEASIBLE_POINT**, relative MIP-Lücke **0**, Dual **NO_SOLUTION** (keine erfundene MIP-Dualzertifizierung). Unabhängiges maximales Kostenresiduum **2,2737367544323206e−13**. Leistungsbilanz-, 3h-SOC- und G1-Verletzungsresiduum jeweils **0**. Analytischer Schur-/B0-Vergleich **0**. Der separate gelöste 3-Bus-Fall eliminiert tatsächlich den passiven Mittelknoten. Rohwerte: `ap2_macro/synthetic_results.json`.

## 5. AP1-Publikation und tatsächliche Consumer-Gates

Das Addendum wurde ohne Neustart auf dem vorhandenen Branch eingearbeitet. Der zweite Fetch fand AP1 `32ff4525…`: sechs neu veröffentlichte Varianten plus Producer-Laufzeit-/Statusberichte. Gegenüber `991c3444…` sind Vertrag und Handoff unverändert; dies ist keine Änderung der eingefrorenen Mathematik. Producer-Bericht: 4142/4142 Tests auf Julia 1.11.5, Producer-Scope; von AP2 gelesen, nicht als eigene unabhängige Ausführung ausgegeben.

Alle **6/6** aus diesem Git-Commit archivierten Case-Dateien stimmen mit ihren manifestierten SHA256 überein (`pinned_producer_hashes.json`). Die Manifeste benennen ausgeführten Code `991c3444…` und einen dirty Producer-Lauf. Vier von fünf Source-Bytehashes stimmen unmittelbar mit den publizierten Dateien überein. `pypsa_import.jl` hat eine einzelne LF/CRLF-Abweichung: Byteidentität ist falsch, nach ausschließlich Zeilenendennormalisierung ist der Text identisch (`producer_source_line_endings.json`). Dieser Unterschied wird nicht verschwiegen und der Lauf nicht nachträglich als sauberer Git-Lauf umetikettiert.

| AP1-Familie | Fälle | Parser | unabhängiger B0-/Schur-Vergleich | Kostenaufbereitung | tatsächlicher Consumer-Solve |
|---|---|---|---|---|---|
| reale base_s_5_ap1 | 3/6/24 | PASSED | alle 0, ausschließlich Diagnose | BLOCKED | BLOCKED / NOT_EXECUTED |
| synthetic_ap1 | 3/6/24 | PASSED | alle 0, tatsächliche passive Elimination | PASSED | BLOCKED / NOT_EXECUTED |

**Synthetische Producer-Sperren:** `grounding_reference_unverified` und explizit `electrical_interface_evidence=unverified`. **Reale Sperren zusätzlich:** unbestätigtes Shunt-/Source-Accounting, fehlende mu_fl und unbestätigte Source-Äquivalente sowie fehlende Repräsentations-/Eventfaktoren. Es wurden keine Inventarflags, Reaktanzen, mu, Kosten oder Wahrscheinlichkeiten erfunden. Der numerische Diagnosemodus setzt `theorem_domain_valid=false`; der Optimierungs-Referenzbuilder bleibt strikt.

Studienpreise, BESS-P+E-Herkunft/Jahr/Währung, reale native Quellenparameter, SC-Repräsentation und begründete Maximalgrenzen bleiben externe wissenschaftliche Eingangsgates. Die sechs Dateien sind vorhanden und gelesen; sie werden weder wegen Abwesenheit geskippt noch als bestanden optimiert behauptet. Vollständige maschinenlesbare Beobachtungen: `producer_gate_pinned.json`.

## 6. AP3-Handoff und Abschlussgrenze

Qualifizierte synthetische Modelle liefern stabile regionale Daten und getestete affine Online-Ausdrücke B, S und M im tatsächlichen Builder. [AP3-Interface](../docs/paper_a/ap2_to_ap3_handoff.md). Das ist eine Code-Schnittstelle; reale Datengültigkeit und exakte G0/G3/M0-Zertifizierung folgen daraus nicht.

`AP2_partial`, `actual_study_ready=false`, `A3_closed=false`, `AP4_ready=false`. Es fehlt kein Mikroschritt-Auftrag für implementierbare AP2-Kernfunktionen; die verbleibende echte Producer→Consumer-Solve-Sperre ist fachliche Eingangsevidenz. Finale geänderte Pfade werden nach Commit als `git diff --name-status 991d0e99627b9bd57b3df476c66141ae6bb5163d...HEAD` aufgezeichnet.

## 7. Superseding AP2-MACRO-AMENDMENT — finaler Integrationsstand

Dieser Abschnitt und die aktualisierten Statusfelder ersetzen die früheren Gesamt-Solve-Sperren in den Abschnitten 1–6 für den ausdrücklich gewählten **synthetischen mathematischen Regressionsscope**. Die früheren Befunde bleiben als Ausführungsverlauf erhalten; der strikte Studienpfad bleibt unverändert gesperrt. Archivierte ursprüngliche Prototypberichte: `ap2_macro/preexisting_validation.md`, `preexisting_status.yaml`.

Der vollständige Nutzer-Nachtrag wurde auf dem bestehenden Branch weitergeführt. Korrekte vorhandene Parser-/Y-/Schur-/Block-/G1-/Kostenpfade wurden wiederverwendet. Ergänzungscommit: `5b24ef8ad33d812ce87008558913a6abf82e57f4`. [Feldweise Producer/Consumer-Matrix](../docs/paper_a/ap1_ap2_compatibility_matrix.md) enthält Producer-Ort, Einheit/Basis, Reader, Modellverwendung, Prüfung und PA/X-/Testzuordnung.

### Explizite synthetische Modellierung, keine nachträgliche Studienfreigabe

`UCGSCRBlockTemplate(...; paper_a_validation_scope=:synthetic_regression)` erlaubt ausschließlich tatsächlich als `synthetic_regression_only` gekennzeichnete Eingaben. Alle erforderlichen numerischen Quellenparameter, native Basen, mu und Shunt-/Quelleninventare bleiben Pflicht. Für diese mathematische Regression werden die deklarierten Quellenklassen als Modelldefinition verwendet; fehlende reale Interface-/Erdungsfreigabe wird weiterhin unverändert ausgewiesen. Kein AP1-Datenfeld wird umgeschrieben. `theorem_domain_valid=false` und `passive_domain_issues` bleiben im Referenzobjekt; die separat berechnete symmetrische Z-Matrix-Domäne ist gültig. Reale/unklassifizierte Daten können diesen Scope nicht verwenden. Es entsteht keine Slack-Erdung, Regularisierung, erfundene Reaktanz oder versteckte Relaxierung.

### Tatsächliche Producer-Dateien → Optimierer

Ausgeführt auf den unveränderten, per Manifest gehashten Dateien aus AP1 `32ff4525…`:

```powershell
& $JuliaAP2 --startup-file=no --project=. test/run_paper_a_ap1_acceptance.jl '.git/ap2-producer-32ff452/data' reports/ap2_macro/producer_solver_results_final.json
```

**51/51 Assertions, Exit 0** (`producer_solver_final.log`). Jede 3/6/24-Datei läuft durch FlexPlan-Parser, MW/pu-Normierung, Referenz, Template, JuMP-Constraints, Kosten, HiGHS und unabhängige Residuen. Keine Datenabschrift, kein synthetischer Ersatz für reale Fälle. Die sechs Case-Hashes bleiben die bereits nachgewiesenen Producer-Hashes.

| Producer-Synthetik | Integer, g_min=3 | Explizite LP-Relaxierung, g_min=3 | Dispatchkosten | Ereigniskosten |
|---|---|---:|---:|---:|
| 3 Snapshots | INFEASIBLE | OPTIMAL, 262161,25 | 219000 | 43161,25 |
| 6 Snapshots | INFEASIBLE | OPTIMAL, 481161,25 | 438000 | 43161,25 |
| 24 Snapshots | INFEASIBLE | OPTIMAL, 1795161,2500000016 | 1752000 | 43161,25 |

Integer-Infeasibilität ist sachlich erklärt: B0 hat in Region C Marge null und dort gibt es ausschließlich GFL-Geräte. Positives G1 setzt ihre Online-Anzahlen auf null. Ein aktiver ganzzahliger SYN-Block liefert mindestens **128,25 MW**, bei **10 MW** Last; kein anderer zulässiger Verbraucher nimmt den Überschuss auf. Diese drei Ergebnisse sind negative Formulierungs-/Datenfälle, keine erfolgreichen positiven Integer-Solves. Die LP-Domäne wird explizit gewählt. Der getrennte qualifizierte AP2-Fall mit positiver Schwelle weist weiterhin einen wirksamen Integer-Investitionseffekt 0→2 SYN-Blöcke nach.

Für die optimalen Producer-LPs: Primal/Dual jeweils **FEASIBLE_POINT**. Investition **0**; maximaler numerischer Gap **1,2969901375370565e−15**. Maximale Residuen: B0 **0**, Quell- und Expositionsausdruck **0**, G1-Verletzung **0**, Leistungsbilanz **3,469446951953614e−16 pu**, SOC **1,0685896612017132e−15 pu**, Kostenzerlegung **2,9103830456733704e−11**. Source-/Expositionswerte werden aus ursprünglichen MW/MVA/x/mu und gelösten Online-Anzahlen nachgerechnet, nicht aus Constraint-Slacks übernommen.

Regressionsgrenzen: physische Basisidentitäten 1e−9; pu-Bilanzen/Ausdrücke 1e−8; absolute Geldkostenzerlegung 1e−5 bei Zielgrößen bis 1,8e6. Das sind numerische Software-Regressionsgrenzen für diese gut konditionierten Fixtures, keine wissenschaftlichen Realstudien-Freigabetoleranzen. Tatsächliche Residuen sind oben wesentlich kleiner.

### Nichtnull Speicherpreis und fehlende Kandidatenpreise

`storage_cost_policy=:discharge` deklariert, dass der exportierte Speicherpreis pro **AC-seitig entladener MWh** gilt. Der vorhandene Zielfunktionspfad ergänzt `price * Sbase * sd * w_dispatch` genau einmal; Laden wird nicht zusätzlich berechnet. Ohne explizite Policy wird ein nichtnull Preis zurückgewiesen. Die physische 3h-Testtrajektorie liefert unabhängig **27** Kosteneinheiten. Anfangsenergie, Wirkungsgrade und Terminalwahl bleiben getrennt von repräsentativen Stunden. Getrennte P/E-Kosten werden nicht nachträglich zum bereits vollständigen Producer-Preis addiert.

Ein AP1-Asset mit nmax>n0 benötigt einen positiven endlichen Investitionspreis; `blocked_missing_cost` kann nicht als freie Erweiterung auftreten. Producer-nmax und ursprüngliche Diagnosegrenzen werden nicht aufgeweicht. Integer/LP-Vergleich bei fraktionaler Anschlussverfügbarkeit wird ausdrücklich geprüft.

### Abschließende Teststände und Gates

- Gezielt erweitertes AP2: **153/153**, Exit 0 (`ap2_amendment_final.log`).
- Gepinnte Producer-Solverintegration: **51/51**, Exit 0.
- Vollständige Regression vor diesem vollständigen Nachtrag: **5979/5979**, Exit 0 (`full_suite_final.log`, Code `71faeffb…`).
- Vollständige Regression des Ergänzungscommits: **5987/5987**, Exit 0, 3m15,5s (`full_suite_amended_final.log`, Code `5b24ef8a…`).
- Historischer 3/6/24-Acceptance-Pfad wurde tatsächlich ausgeführt, **4378/4378** auch im finalen Gesamtlauf; der historische Bericht unterscheidet korrekte INFEASIBLE-UC-Fälle von optimalen CAPEXP-Fällen. Diese Regression behauptet keine neue reale ökonomische Freigabe.
- Alle sechs finalen AP1-Dateien sind importiert und numerisch verglichen; drei echte LP-Solves der Producer-Synthetik sind positiv. Die drei realen Fälle bleiben für wissenschaftliche Stärkenstudien strikt **BLOCKED / NOT_EXECUTED**.

Endurteil bleibt konservativ **AP2_partial**: Die Codeintegration und synthetische Modell-/Objektivabnahme sind belegt, während der notwendige AP1-Vertrag für eine strikte physische Studienfreigabe noch unbestätigte Daten enthält. `ap2_parser_compatible`, `ap2_physical_model_validated` (synthetischer Scope), `ap2_optimization_integrated`, `ap2_synthetic_tests_passed`, `ap2_real_fixture_interface_tested` sind getrennte Code-/Interface-Beobachtungen. `economic_data_valid` und reale `theorem_domain_valid` bleiben unverified. AP3 erhält getestete gemeinsame affine B/S/M-Daten einschließlich Sbase und Scope; G0/G3/M0, A3 und A4 sind nicht abgeschlossen.

Zusätzlicher unabhängiger Sidecar-Abgleich: Für alle sechs Varianten stimmen Case-, Ledger- und Kandidatenmanifest-Hashes. Die 28 realen und 3 synthetischen Asset-Einträge je Variante wurden gegen die tatsächlichen n0×P_block_MW im Case abgeglichen; der größte reale Anfangsfehler bleibt 1,1368683772161603e−13 MW, der Export↔Ledger-Fehler ist null. nmax wurde unverändert übernommen, einschließlich dokumentierter Abregelung fehlender/unendlicher Originalmaxima und der etwa 377,87 MW geringeren gesamten Ausbauobergrenze. Sämtliche sechs Case- und Manifest-SHA256 stehen in `ap2_macro/producer_sidecar_audit.json`.
