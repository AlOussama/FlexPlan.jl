# Paper A — A3.6-B1/OPT: Independent MISOCP Reliability and Global Integer Certification

> **Datum 20.10.2026 | Vollständiger, eigenständiger lokaler Makroauftrag | Sprache: Deutsch**
>
> **Verwendung:** NEUER, vom AP3-Implementierer sowie A3.5-MATH/SCIENCE/FINAL/EXEC-Auditor unabhängiger lokaler Codex-/Julia-Worker mit tatsächlichem Terminal-, Worktree-, Julia/JuMP/MOI- und Solverzugang.
>
> **Nicht** im bisherigen AP3-Implementierungschat ausführen. **Nicht** in einem reinen GitHub-Web-Review-Chat ausführen. **Nicht** Wissenschaftsowner-Ratifizierung simulieren.
>
> **Kernziel:** Ausschließlich die nach A3.5-EXEC offengebliebenen zusammenhängenden technischen Gates schließen oder mit belastbarer, reproduzierbarer Evidenz weiter eingrenzen: (B1) native G3-MISOCP-/Pajarito-OA-/Konus-/LP-Zuverlässigkeit und (OPT) neun globale gemischt-ganzzahlige Kostenunter- und -obergrenzen mit korrekter Objective-Koordinate und zertifizierbarer Fehlerschranke. Bereits unabhängig abgenommene P001–P010-Fälle und 124-Metrik-/8-CLI-Regressionspakete dürfen als gepinnte Vorleistung wiederverwendet werden; wiederhole nur Betroffenes und erforderliche Schutzregressionen.
>
> Arbeite autonom und ohne Mikroschritt-Rückfragen. Erzeuge keine fiktive Lizenz, keine fiktiven Zertifikate, keine unbegründeten „numerical tolerance“ PASS. Keine A3-/AP4-Studienfreigabe.

## 0. Rolle, Unabhängigkeit, zulässige Schlussurteile

Du bist **A3.6-B1/OPT — Independent Mixed-Integer Conic Reliability & Optimality Auditor**, mit Expertise in Julia/JuMP/MathOptInterface, Pajarito und OA, RSOC/SOCP/SDP, Numerik und Kondition, Dualität, integer branch-and-bound, globalen Bounds, objektiven affinen Transformationen, M-Matrix/PSD/Schur und PowerModels-Planungsökonomie.

Vier separate Aussagen sind zu unterscheiden:

1. **G3-Satzkorrektheit:** G0⇔vollständiges G3 auf symmetrischer PSD-Z-Matrixklasse ist bereits mathematisch bedingt bestätigt, **nicht** Thema einer neuen Theoremdebatte.
2. **JuMP/MOI-Modellkorrektheit:** A3.5-EXEC akzeptiert die Gleichung-zu-Code-Übereinstimmung für registrierte Fälle; jede Änderung am Modell muss erneut fallbezogen validiert werden.
3. **Solverzuverlässigkeit:** Reicht ein reproduzierbarer nativer Konus-/MIP-/OA-Pfad aus, um zulässige Punkte nicht fälschlich auszuschließen und Ergebnisse einschließlich Status robust zu klassifizieren?
4. **Globale Integeroptimalität:** Ist für jedes Problem ein logisch gültiges und bei der erforderlichen Präzision nachgewiesenes Intervall \(L_{\rm cert}\le C^\star\le U_{\rm cert}\) verfügbar, mit vollständig qualifizierten primal/dual- bzw. externen Fehlergrenzen?

Numerische solverseitige „Optimal“- oder „INFEASIBLE“-Meldungen, Relaxationswerte, kleine Residuen und \(|UB-LB|\ll C\) sind **keine** alleinigen rigorosen globalen Zertifikate.

Falls du substantielle Produktionscode-/Solverformulierungskorrekturen selbst implementierst, bewahre einen getrennten, von deinem Fix unabhängigen Pre-fix-Befund und liefere eine an einen zweiten unabhängig beauftragten Worker gerichtete Nachprüfung. Du darfst eigene Korrekturen nicht final selbst als unabhängige Closure signieren. Nur Metadaten-/Testhilfen ohne mathematische Modellwirkung entsprechend deklarieren.

## 1. Gepinnte Revisionsidentität — vor jeder Änderung remote und lokal erneut verifizieren

**Primärrepo:** https://github.com/AlOussama/FlexPlan.jl

- Ursprüngliches unverändertes AP3: `implementation/paper-a-ap3-all-formulations-v1@485b637cc1998a327206c5929434bd26c6f0be16`. Keine Änderungen, kein direktes Commit dort.
- A3.5-EXEC-Vorabschluss: `fix/paper-a-a3-5-executable-closure-v1@4d9f346c5fca80e00fd01d96c39a2bac91776ac0`. **Dieser SHA ist die unveränderliche Eingangsevidenz**, selbst wenn die bestehende Branch später nur durch additive Auftragsdokumentation vorrückt.
- Einheiten-Metadatenfix: `e1e075626b38b478faf57efe62e557fc94753f00`, genau zwei neue Einheit-Zuordnungszeilen in `scripts/paper_a/AP3Pipeline.jl`. Mathematik unverändert. Vergleiche Original- und Fix-Variante bewusst bei Outputmetadaten.
- Frühere A3.5-Review: `review/paper-a-a3-5-independent-acceptance-v1@50f88d5d30194afbbd188c96e3eab795b7a7de49` zum zuletzt beobachteten Zeitpunkt; frühere SCIENCE/MATH-Belege auf dieser Historie.
- Vorherige voll dokumentierte A3.5-EXEC-Tests: 6087/6087 Original Julia-Regression, 4108/4108 Original-Evidenz, 42/42 neue Julia/JuMP/MOI, 16/16 Domainmutationen, 34/34 Constraint-Koeffizientenprüfungen, 51/51 + 291/291 + 54/54 Producer-/Qualifikationstests, 124 Metrik-IDs, 8 CLI-Aktionen, 1299 Zustände/232 Lösungen unabhängig rekonstruiert. Dies sind Quellenbefunde, **nicht** hier erneut erbrachte Resultate.
- Native G3-Ergebnis: `numerical_inconclusive`, Integer `partial`, Gleichung zu Code `accepted_for_registered_cases`.

**Autoritative Wissenschaft:** https://github.com/AlOussama/research-map

- Ursprünglicher Freeze `2c2fce769b2ed6ffd4f1ced60c0798776acccc93`; Dissertation `main@e8118425adc335a99e85120d943763305f211315`.
- Paper-A-Scope `672a61c95525bf1d7a03cf745a754a15a23ce78b`.
- A3.5-SCIENCE/FINAL `review/paper-a-a3-5-science-release-v1@2badb9a90a8d3c1d4a33accee640b295de1e33a1`.
- Wissenschaftlich vorgeschlagenes, **nicht** Owner-ratifiziertes Amendment A1–A5: `2026-10-20__a3-5-amendment-final-proposed-text.md` auf `research-map@5ceb19a6faf4e7c7e797a737ed5b449f9e2db609`, Blob `fba4802ecabade61a752833a71106a5bda4ce78f`. Owner-Ratifizierung bleibt ein anderer Strang.

**Datenproducer, read-only:** https://github.com/AlOussama/PyPSA2MatpowerX

- `implementation/paper-a-ap1-data-contract-v1@b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c`.
- In numerischer AP3-Reproduktion verwendete Producer-Artefakte `3b8fdb01d931225edc5f8fe1e2c200d0da288a09`. Genaue Rawdata-Hashes im A3.5-EXEC-Manifest nachlesen.

**Pflicht zu Beginn:** `git ls-remote`, `git status --porcelain=v1`, `git worktree list`, `git rev-parse`, Parent/Merge-Base und sämtliche beteiligten Snapshot-Hashes nachprüfen. Falls Branch-HEAD inzwischen anders, diffen, niemals den exakten Prüfreferenz-SHA still ersetzen. Geschützte Dirty-/Untracked-Files, existierende BASE/FIX/RUN-Worktrees und historische Archive erhalten. Neue Arbeitsverzeichnisse sauber isolieren.

## 2. Maßgebliche Evidenz lesen und anhand von SHA sichern

Lies in dieser Reihenfolge vom exakten `FlexPlan.jl@4d9f346c...`:

1. `reports/a3_5/executable_closure_20261020/independent_executable_closure_report.md`.
2. `release_gates.yaml` und `reproduction_manifest.json`.
3. `reproduce.md`, `g3_native_misocp_and_edge_completeness.md`, `integer_global_bounds_and_objective_audit.json`.
4. `predicate_P001_P010_evidence_ledger.csv`, `theorem_T001_T028_equation_to_code_ledger.csv`, `metrics_124_cli_8_replay.md` soweit vorhanden.
5. ZIP `reports/a3_5/executable_closure_20261020/artifacts/executable_replay_evidence.zip`, **24,237,795 Bytes**, SHA256 `0ec9969de7c8659bc50d82664556c09515080beb1bcd1e937bb9cc7b8d925993`; 381 manifestierte SHA256-Entries. ZIP wenn nicht im Checkout vorhanden anhand des Git-Objekts korrekt beziehen. Alle verwendeten Entries inkl. Hash in deinem Eingangsmanifest aufführen.
6. Frühere AP3-Worker-Reports und acht CLI-Registrys **nur als Vergleichsevidenz**, nicht als neue Optimierungsbeweise.

**Relevante vorhandene ZIP-Entries** (tatsächliche Pfade im Manifest verifizieren):
- `b1_exact_native.mof.json`, `b1_exact_native_result.json`, `b1_exact_native.log`.
- `b1_bridged_conic_relaxation.mof.json`, `b1_bridged_full_witness_check.json`, `b1_exact_full_witness_verification.json`.
- `b1_generated_OA_model.mof.json`, native-/bridged-/OA-Logs und `b1_transfer.log`.
- Für alle neun Fälle: `integer_best/fixed_<case>_G0.mof.json`, `..._G3.mof.json`, `integer_best/full_witness_<case>_G0/G3.json`, erzeugte Bounds-/Cost-Diagnostiken.
- `execute_replay.ps1`, `execution.json`, `input_sha256_manifest.json`, ggf. `additional_execution.json`.

Beachte: Windows-basierte frühere Pfade `D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE`, `..._REVIEW`, `..._RUN` sind **historische Provenienz**, keine Gewissheit über deinen lokalen Dateisystemstand. Verwende neue isolierte Worktrees, außer ein sauberer existierender Checkout und eine saubere separate Scratch-Umgebung sind nachgewiesen.

Wenn Evidenzarchive fehlen, nicht durch Annahmen ersetzen. Sicherbare Inputs erneut reproduzieren und `not_available` für fehlende Dateien deklarieren.

## 3. Ausgangsfall B1 — exakt zu reproduzierender Widerspruch

Originaler Pajarito/HiGHS/Clarabel-Pfad meldet für `reference_24snap` am **serialisierten ursprünglichen Integer-MISOCP** `INFEASIBLE` und `NO_SOLUTION`. Gleichzeitig wurde ein vollständiger neuer Zeuge für ebendieses Modell bis zu folgenden Werten geprüft:

- höchste berichtete Originalconstraint-Verletzung: `7.5153490016e-12`.
- nach tatsächlicher MOI-Variablenbrücke größter RSOC-Konuskegelabstand: `8.83513342703e-11`.
- größter linearer Residual: `4.26325641456e-14`.
- `reference_24snap` enthält **1353 Integerrestriktionen** im exportierten Fall.
- Eine positive Objective-Skalierungsvariante liefert numerisch `OPTIMAL`, kleine Änderungen mancher OA-Toleranzen führen dagegen zu `ITERATION_LIMIT`: Indiz für numerische Pfadabhängigkeit, **keine** generelle Reparatur.
- Gurobi zuvor Error 10009, Lizenzablauf 2026-10-12; MOSEK 11.0.29 vorher MSK_RES_ERR_LICENSE_EXPIRED/1001. Keine aktuell gültige kommerzielle Lizenz unterstellen.

**Verbindliche Unterscheidung:** Ein Zeugnis mit Float64-Residual \(\sim10^{-11}\) widerlegt die Solver-Behauptung im numerischen Akzeptanzsinn der angegebenen Toleranz, nicht von sich aus die exakte mathematische Nichtzulässigkeit einer beliebigen Instanz. Prüfe Kegelinnenseite/Boundary, Integernähe, Modellequality, Scaling, Reader/Writer-Rundung und Modellidentität. Ohne formal exakte rationale oder abgesicherte Validierung keine Formulierung „streng bewiesene exakte Feasibility“ verwenden.

### B1-A — Reproduktionsdisziplin

Auf reproduzierbar fixierter Basis:
1. Verifiziere Datei-/Modellbytehash des Originals und des Witness; Modellstruktur/MOI-Typen und Constraint-IDs nach Bridging und Presolve vergleichen.
2. Führe `b1_exact_native_repro.jl` → `b1_transfer_full_witness.jl` → `b1_exact_native_repro.jl` mit geeigneten Parametern gemäß `reproduce.md` aus. Ist das Script nur in ZIP, extrahiere bytegleich und verwende seine echten CLI-Argumente; keine erfundenen Befehle.
3. Pro Lauf alle Einstellungen, RandomSeeds, Threads, BLAS, MOI/JuMP/Pajarito/HiGHS/Clarabel, Solver- und Paketversionen, Plattform, Presolve, Scaling, Cut-Toleranzen, Status, unskalierte und skalierte Residuen und Modelle/Aktualisierungs-Hashes sichern.
4. Original `solve!` unverändert starten; ein Hook darf nur protokollieren. Einmalige/zufällige Fehlermeldungen durch kontrollierte Wiederholungen unter identischer Umgebung einordnen.

### B1-B — Lokalisierung des Ursachenglieds, kein voreiliger Schuldzuweisungs-Patch

Erstelle eine kausale Prüfmatrix über die gesamte Kette:
\[
\text{source data}\rightarrow\text{JuMP model}\rightarrow\text{MOI bridges}
\rightarrow\text{root conic/LP relaxation}\rightarrow\text{OA cuts}
\rightarrow\text{MIP nodes/presolve}\rightarrow\text{termination}.
\]

Verifiziere insbesondere:
- RSOC-Repräsentation: \((q_{ij},q_{ji},\sqrt2 m_{ij})\in\mathcal Q_r^3\), doppelte/fehlende Kanten, Restdiagonalen, Kegel-Normierung.
- Verlust/Änderung von Bounds, Koeffizienten, Variablenmapping, Integrality, Objective-Rebase oder Konstanttermen nach Bridging und MOF/CBF-Export.
- Root-relaxation mit/ohne Integer, fixierte Integer-Witness, alle continuous subproblems; identische mathematische Feasible Sets unter variiertem Scaling.
- Feasibility und Gültigkeit erzeugter OA-Schnitte relativ zur tatsächlichen RSOC-Geometrie; numerisch falsch abschneidende Cuts isolieren. Korrekte LP/MIP Dual-/Farkas-Zertifikate getrennt von Statusstrings.
- Unterschied zwischen conic subsolver `numerical_error`/`infeasible`/`unknown`, LP-Numerik, relative/absolute Toleranzen und OA-Abbruchlogik.
- Wenn möglich kleinsten strukturell identischen Gegenfall durch Reduktion der Zeit-/Block-/Kantenfamilien erzeugen, während der Solverwiderspruch reproduziert bleibt.
- Alternative korrekt initialisierte Solver-/Bridge-Kette probieren, soweit **tatsächlich** verfügbar und lizenziert; proprietäre Lizenzen nicht voraussetzen.

**B1-Abnahmetest:** Nicht allein `reference_24snap` einmal mit `OPTIMAL` rechnen; identische 3/6/24-Fälle, neun registrierte Fälle, G0/G3 relative Cost-/Matrixkonsistenz, belastbare Feasibility und Statusstabilität unter zulässigen Toleranz-/Scale-Varianten prüfen. Der Unterschied „solver reliable for registered cases“ vs „general MISOCP capability established“ ist im Verdict auszuweisen.

### B1-C — Reparaturstrategie

Nur wenn fehlerhaftes Modell-/Bridge-/Solververhalten durch reproduzierbaren Gegenfall belegt wurde:
- vorzugsweise Solverkonfiguration/Optionen und numerische scaling-/cut-/termination-Regeln korrigieren, **ohne** das G3-Mathematikziel oder die ganzzahlige zulässige Menge zu verändern;
- jede positive diagonale Skalierung/Reparametrisierung vollständig algebraisch und mit primal/dual Objective-/Constraint-Mapping auf Äquivalenz prüfen;
- alternative MISOCP-Implementierung nur bei tatsächlich verfügbarem Solver und unabhängig kontrollierter Interoperabilität einsetzen;
- nicht heimlich SOCP durch LP-G1 ersetzen, keine Integer-Relaxation als Original-MISOCP-Optimalität ausgeben und keine toleranzlose „return OPTIMAL“ Statusmanipulation;
- Änderungen erst als eigener Fix auf sauberer separater Branch; Pre-fix-Baseline und Reproduktionen unverändert behalten; erforderlicher unabhängiger Reaudit eines eigenen substantiellen Fixes verpflichtend.

## 4. OPT — neun gemischt-ganzzahlige Fälle und globale Bounds

Die neun konkreten Fälle (alle mit originalem Dataset-/Case-SHA und `G0`/`G3`-Witzen):

`bess_premium_3snap`, `connectivity_3snap`, `event_price_3snap`, `exposure_multiplier_3snap`, `reference_24snap`, `reference_3snap`, `reference_6snap`, `source_reactance_3snap`, `threshold_3snap`.

Im vorherigen A3.5-EXEC-Bericht stehen in **acht von neun** Fällen ursprüngliche LB-Claims oberhalb unabhängiger feasible UB; \(\min(UB-LB)\approx-0.000255036\) Währungseinheiten (`event_price_3snap`). `reference_6snap` hat ein positives \(UB-LB\approx+0.00428839\). Diese Beobachtung ist quantitativ klein, aber strikt nicht mit einem gültigen \([LB,UB]\) vereinbar, solange nicht zusätzliche **belegte** Fehlerschranken eingeführt oder ein Claim zurückgezogen wird.

### OPT-A — Gemeinsame Originalkostenkoordinate

Für jeden Fall getrennt:
1. Original-JSON/CSV/Producer-Parameter, `baseMVA`, `operation_weight`, `time_elapsed`, Szenariowahrscheinlichkeit, Start/Stop-Ereigniswiederholungen, Storage P+E/annualized CAPEX und einmaligen Investitionsoffset hashgesichert rekonstruieren. 24 × 3h = 72h, nicht 24h.
2. Mehrstufiges Originalmodell mit G0/G3, **identischem** \(B,p,S,\alpha\), einer identischen Minimierungszielfunktion \(C(x)\), Integer-Feasible-Set und Nebenbedingungen belegen. Kein Vergleich, falls Daten, Exposure oder Cost-Offset nicht identisch.
3. Objective-Rebase \(\widetilde C=s(C-C_0)\), \(s>0\), oder andere tatsächlich implementierte affine Transformation exakt herleiten, Rücktransformation \(C=C_0+\widetilde C/s\), Primal und Bound mit richtiger Transformationsrichtung. Keinen relativen Gap auf \(\widetilde C\) unbemerkt in einen absoluten Währungsgap umdeuten.
4. Rechne Originalwährungskosten aus Investition, Generation, Storage, Start/Stop und einmaligen Kosten selbst nach. Ausgewiesene Kostenresiduen als zulässige Unsicherheiten behandeln, nicht automatisch null setzen.

### OPT-B — Primalzeugnisse (Obergrenzen)

Für G0 und G3 jedes Case: Finales \(n^{inst},n^{avail},n^{on}\), UC/Storage/Dispatch, PF, gesamte \(B/S/M\) und Edge-Zeugen aus echten Outputs vollständig independent nachrechnen. Summiere und prüfe \(\max\) aller skalierten/unskalierten linearen, RSOC, Integer- und gleichungsbezogenen Verletzungen sowie objektive Kostenrekonstruktion.

Ein Float64-Witness mit zulässigen Solver-Toleranzen ist ein `numerically_feasible_UB`, NICHT automatisch ein rigoros gültiger oberer Bound der exakten Originalproblemstellung. Falls rigorose Upper-Bounds gefordert, benutze zulässiges Primal-Recovering mit analytischer/exakter/validierter Restabsicherung; gib sonst das Prädikat `rigorous_UB=false` an.

### OPT-C — Untergrenzen und globale Zertifikate

Prüfe **Methoden separat**:
- tatsächliche BASE-LP Relaxation des identischen Minimierungsmodells: Liegt \(\mathcal F_{\rm original}\subseteq \mathcal F_{\rm LP}\)? Sind Variablen, Kegel, Bounds, Objectives, Scales richtig? Dokumentiere wann Relaxation eine echte untere Schranke liefert und wann Solver-/Dualungenauigkeit das Ergebnis nur numerisch erscheinen lässt;
- sichere zulässige SOCP/SDP-Relaxationsdual-Lösungen unter korrekter Vorzeichenrichtung, dualen Kegeln, stationären Gleichungen, Konstanten und Offset prüfen; ein dual feasible point kann bei korrekter Vorzeichenkonvention mittels schwacher Dualität einen mathematisch gültigen LB liefern;
- tatsächlich generierte OA-Schnitte müssen global gültig für den originalen SOC-Kegel sein, nicht nur für das lokale Iterat. Prüfe Normalen, lineare Cut-RHS, konische Dualrichtungen und Fehler der Cut-Koeffizienten; invalid cuts können falsche LBs erzeugen;
- branch-and-bound MIP tree lower bound: Proof-Status und Node Coverage, Integrality, Cuts und Erhaltung der relaxierten zulässigen Menge, primal-dual Toleranzen und abgebrochene Knoten vollständig protokollieren;
- externe rational/exact/verifizierte Intervallarithmetik für kleine Modelle bzw. Teilprobleme nur verwenden, wenn deren Datennormalisierung exakt zum optimierten Original passt. Der ältere 81-Zuweisungen-Fall belegt **nur sich selbst**, nicht die neun Cases.

**Zertifikatgrenze:** Ein vorzeichenkonsistentes numerisches LB allein ist kein rigoroser Bound ohne Validierung seiner Herleitung. Bei positivem Gap gilt trotzdem nur ein numerischer Gap, wenn kein belegter globaler Bound vorliegt.

### OPT-D — Quantifizierte Fehlerbounds (nicht ad hoc)

Wenn \(LB_{\rm num}>UB_{\rm num}\):
- führe pro Eintrag eine **signierte** Gap-Tabelle, führe niemals \(|UB-LB|\) als angeblich positives Intervall.
- unterscheide Mess-/Reportprecision, tatsächlichen Float64 Rundungsfehler, abgesicherte LP-/Kegel-Dual-Feasibility, primal residual, Solverrelaxationen und Objective-Offset.
- Eine plausible Reparatur kann \(LB_{\rm cert}=LB_{\rm num}-\varepsilon_{LB}\), \(UB_{\rm cert}=UB_{\rm num}+\varepsilon_{UB}\) benutzen, **aber nur**, wenn \(\varepsilon_{LB},\varepsilon_{UB}\ge0\) aus bewiesenen Schranken/validierter Intervallarithmetik oder abgesicherten normbasierten Fehleranalysen hergeleitet sind, inklusive residual-to-value-Argument unter erforderlicher Regularität. Die reine Differenz \(LB_{\rm num}-UB_{\rm num}\) ist kein Fehlerbeweis.
- Falls ein globaler Bound-Claim nachweisbar unsound ist, ziehe ihn explizit zurück oder korrigiere den Algorithmus; alte historisch publizierte Zahlen niemals rückwirkend überschreiben.
- Wenn globale Integer-Zertifizierung aus Zeit-/Lizenz-/Solvergründen unmöglich ist, dokumentiere getrennt `feasible_primal_verified`, `dual_bound_numerically_supported`, `valid_interval_not_established`, samt Fall-SHA und minimal erforderlichem nachgelagerten Rechenverfahren.

**OPT-Abnahmekriterium je Case:** tatsächliche Grenzen in Originalgeldkoordinate; genaue Solver-/Rechenmethode; konsistente \(LB\le UB\) mit nachvollziehbarem rigorosen Geltungsbereich und gültiger toleranzbasierter Globalität (oder explizit nur numerisch); C*_G0=C*_G3 nur bei gleicher erklärter Domain und identischem Zielfunktionsmodell. Keine stillschweigende Generalisierung eines fallbezogenen Zertifikats.

## 5. Ganzheitliche Regression ohne A3.5-Wiederholung

Die neue Arbeit beschränkt sich auf B1/OPT, muss jedoch zwingend die betroffenen Schutzregressionen erneut **ausführen**:

- Original Witness `reference_24snap` und die bisherige unveränderte Pajarito-INFEASIBLE-Konfiguration als Negativ-Baseline;
- echte JuMP/MOI/RSOC-Kegel-/Bridging-Tests, Scaling- und Cut-Mutationen;
- 3/6/24-Snapshot-MISOCP/LP/SOCP Baselines, neun Integerfallpaare; wenn bestehende numerische 162-Lauf Suite unverändert weiterverwendbar, wenigstens die durch jede Änderung betroffenen Untergruppen sowie status-kritischen `numerical_inconclusive`-Fälle;
- vollständige Regressionssuite `6087/6087` und Evidenzsuite `4108/4108` auf tatsächlich geändertem Produktions-/Solvercode, sofern ein Fix das Laufverhalten materiell verändert;
- 124 Metrik-/acht CLI-Pfad-Abnahme nur sofern Codefix Ausgabe/Export/Bound-Logik beeinflusst. Andernfalls bestehende, manifestierte A3.5-EXEC-Belege unverändert referenzieren und Geltungsgrenze nennen;
- negative/zero-support/singuläre Z-/G3-/Range-Fälle weiterhin richtig klassifizieren; keine Toleranzänderung darf die mathematische Domain aufweichen;
- präzise Ausweisung aller neu ausgeführten Kommandos, Exitcodes, Solverstatus, Logs, Versions-/Hashidentitäten und tatsächlicher Testabdeckung.

## 6. Implementierungsmandat, Branch-Regel und Unabhängigkeit

1. **Zuerst Diagnose am unveränderten AP3**, dann am dokumentierten Export-Metadatenfix, jeweils pinned. Änderungen niemals vor der Pre-fix-Adjudikation ausführen.
2. Wissenschaftsrepo, Dissertation/Freeze, Producer-Repo und Original-AP3-Branch **nur lesen**. Kein Anpassungszwang der Theoreme an den Solver.
3. Vor Schreibarbeiten Branchstatus prüfen. Vermeide viele Branches: benutze nach Möglichkeit den bestehenden `fix/paper-a-a3-5-executable-closure-v1` **nur für neue Auditdokumentation**; wenn echte Solver-/Codeänderung nötig ist, erstelle **höchstens eine** dedizierte `fix/paper-a-a3-6-b1-opt-v1` von exakt verifiziertem Baseline-SHA. Keine parallelen Worker auf derselben Schreibbranch.
4. Schreibe sämtliche Logs/Experimente in einen eigenen Scratch-Runordner (nicht die 381 Einträge oder historischen ZIPs verändern); Hash- und Archivmanifest mit SHA256.
5. Keine Force-Pushes, Hard Resets bestehender Worktrees, Rebases, Branch-Löschungen, Auto-PR oder Merge. Keine Lizenz-/Sicherheitseinstellungen manipulieren.
6. Jeder substanzielle Eingriff in die Produktionsformulierung oder Solverintegration erzeugt einen ausdrücklich separaten unabhängigen Reaudit-Folgeauftrag; du kannst ihn vorbereiten, aber nicht selbst final signieren. Ein unveränderter Codepfad mit unabhängig reproduzierter, kompletter Evidenz kann dagegen im belegten Umfang unabhängig akzeptiert werden.

## 7. Ausgabe — verpflichtendes maschinenlesbares Closure-Paket

Arbeite in neuem, eindeutigen Artefaktverzeichnis `reports/a3_6/b1_opt_20261020/` (bei Konflikten Rev-Suffix) und veröffentliche soweit tatsächlich möglich:

1. `independent_b1_opt_closure_report.md` — deutscher Vollbericht mit Revisionsidentität, Ursachenanalyse, Testmatrix, abgeleiteten Schlussfolgerungen und Freigabegrenzen.
2. `b1_original_vs_bridged_vs_oa_stage_evidence.json` + `b1_root_cause_or_limitation.md`, exakte native/bridged/OA MOI-Hashes, Witness-/Cut-/Kegelresiduen, Problemstatus.
3. `b1_solver_reliability_matrix.csv`: Version, Parameter, Scaling, Stages, Case, Status, Feasibility, Dual-/Integerqualität, Reproduktionszahl, Ursache.
4. `integer_9cases_proof_ledger.csv` und `integer_9cases_bounds.json`: raw case SHA, primal/dual origins, LB/UB signed, Objective-Skalierung, Rundung/Fehlertoleranz, globales Zertifikat ja/nein.
5. `objective_rebase_derivation.md`: exakte algebraische Objective-Koordinate, Offset/Basis, positive Skalierung, Null-/Kosten-/Eventfälle, mathematischer Rücktransform.
6. `verified_primal_dual_witnesses/` bzw ZIP + Inhalts-/Archiv-SHA256: getrennter Fall-Witness, Cuts/Bounds, eigene Skripte, Logs.
7. `independent_b1_opt_tests.jl` und ggf. `reference_certifier.py` sowie Testausführungsmanifest.
8. `pre_fix_original_verdict.md`, `code_changes_and_regression_manifest.json`, Reaudit-Prompt sofern erforderlich.
9. `release_gates.yaml`, `reproduction_manifest.json`, `remaining_gates_handoff.md`.
10. Verzeichnisinventar und finalen Remote-HEAD-/Git-Blob-/SHA256-Nachweis.

Gib pro Problem genau **einen** technisch definierten Zustand aus:
- `native_G3_MISOCP: certified_for_registered_cases | numerically_repaired_not_independently_reaudited | numerical_inconclusive | failed | not_run`.
- `integer_globality: rigorously_certified_nine | numerically_certified_with_tolerances | case_specific_partial | unsound_previous_bounds | unresolved`.
- `a3_6_b1_opt_verdict: closed_on_unchanged_code | correction_ready_for_independent_reaudit | partially_closed | blocked_by_solver_or_license | contradictions_unresolved`.

Bewerte getrennt `B1_repaired` und `integer_bounds_proved`; ein Erfolg einer Teilkomponente darf die andere nicht kaschieren.

**Gate-Initialzustand** solange kein neues unabhängiges vollständiges Zertifikat und keine echte Owner-Ratifizierung vorliegen:

```yaml
original_ap3_sha: 485b637cc1998a327206c5929434bd26c6f0be16
a3_5_exec_input_sha: 4d9f346c5fca80e00fd01d96c39a2bac91776ac0
proposed_science_amendment_blob: fba4802ecabade61a752833a71106a5bda4ce78f
science_amendment_approved: false
owner_ratification: pending
implementation_equation_match: accepted_for_registered_cases
native_G3_MISOCP: numerical_inconclusive
integer_globality: case_specific_partial
independent_A3_5_accepted: false
A3_closed: false
AP4_ready: false
empirical_study_ready: false
```

**Explizite Verbote:** Keine pauschale `A3_closed=true`, `AP4_ready=true`, `empirical_study_ready=true`. Auch ein vollständig qualifizierter B1/OPT-Solver ersetzt keine reale Quellen-/Passivinventar-, Kosten-, Parameter-/Repräsentativitäts- oder Wissenschaftsowner-Ratifizierung.

## 8. Abschließender deutscher Handoff

Liefere einen einzigen ausführlichen deutschen Schlussbericht, aus dem ohne weiteren Chat hervorgeht:

- exakte Eingangs-/Ausgangs-SHAs, Arbeitsumgebung und Repro-Kommandos;
- der kleinste reproduzierbare B1-Fehlpfad, bestätigter/vermuteter Ursprung der falschen Infeasibilität, Fehlerbehandlung und nativer Status;
- gültige/ungültige globale LB-/UB-Prüfung aller neun Fälle mit Originalwährung und Beweisniveau;
- ob ein neuer Produktionscode-Fix stattfand und ob deshalb ein zweiter unabhängiger Worker erforderlich wird;
- was bereits aus A3.5-EXEC unverändert akzeptiert bleibt;
- welche Daten-/Physik-/Wissenschaftsowner-Gates parallel verbleiben;
- publizierte SHA-/Datei-/Zip-/Run-Manifeste, exakte Remote-HEAD-Prüfung nach Push.

**Kein Fehlschluss von Float-Toleranz auf mathematisches Beweiszertifikat; keine selbstsignierte unabhängige Freigabe eigener Modell-/Solverkorrektur; keine fiktive Solverlizenz oder automatische A4-Freigabe.**
