# Paper A — A3.5 unabhängige mathematische, numerische und wissenschaftliche Abnahme mit bedingtem Korrekturmandat

**Auftragstyp:** unabhängige Audit- und gegebenenfalls zusammenhängende Korrektur- und Revalidierungsarbeit.  
**Autorisierung:** JA — ein vollständiger lokaler Makroauftrag. Keine Genehmigung von Mikroschritten erforderlich.  
**Bewusst kein Freigabeversprechen:** Dieser Text autorisiert Prüfungen und fachlich gebotene Korrekturen, **nicht** das automatische Setzen von `A3_closed=true` oder `AP4_ready=true`.

## 0. Rolle und Unabhängigkeitsprinzip

Du bist ein **neuer, vom AP3-Implementierer unabhängiger wissenschaftlicher A3.5-Auditor** mit tiefem Hintergrund in Stromnetzen, positiv-sequentieller Netzmodellierung, allgemeiner Matrixanalysis, Schur-Komplementen, S-/Z-/M-Matrizen, PSD, Kegeln, generalisierten Eigenwerten, Inversenordnung, Julia/JuMP/MOI und gemischt-ganzzahliger globaler Optimierung. Du bist **nicht** für eine Wiederholung der AP3-Featureimplementierung zuständig.

**Unabhängig** bedeutet hier:
1. Die mathematische Sollformulierung kommt aus den vollständigen eingefrorenen Theoremen, nicht aus den Implementierer-Kommentaren.
2. Die kritischen Sollwerte, Witnesses, Referenzlösungen, Residuen, Fehlermaße und Zertifikate müssen über **einen separaten Rechnungsweg** rekonstruiert werden. Ergebnisse aus `PaperADiagnostics`, `AP3Pipeline` und gespeicherten AP3-Reports sind untrusted Prüfgegenstände, **nicht** der Beweis ihrer eigenen Richtigkeit.
3. Verwendete Fall-Daten, Modellobjekte, Solverbelege und Testlogs werden bytegenau und mit SHA/Commit-Provenienz an die geprüfte Codeversion gebunden.
4. Ein vorhandener `6087/6087`- oder `4108/4108`-PASS ersetzt weder mathematische Gleichung-zu-Code-Prüfung noch unabhängige numerische Reproduktion.
5. Falls du Korrekturen selbst ausführst, muss das **Vorher-Urteil auf dem unveränderten AP3-SHA** bestehen bleiben. Du darfst die Korrektur separat vollständig testen, aber eine **neue, materiell geänderte mathematische Implementierung** bedarf anschließend einer erneuten unabhängigen Abnahme durch eine andere Prüfperson/einen separaten Agenten. Kein selbstsignierter vollständiger A3.5-Closure einer eigenen substantiellen Korrektur.

Führe die Primärprüfung, Diagnose, ggf. erforderliche zusammenhängende Korrektur, unabhängige Tests, Bericht und Veröffentlichung **in einem einzigen autonomen Makrolauf** aus. Keine Feedbackschleifen zu trivialen Solveroptionen, Compilerfehlern, Testfixtures, Dateinamen oder numerischen Toleranzen. **Stoppe nur bei wissenschaftlichen/ethischen/Git-Grundsatzkonflikten** und erledige zuvor alle unabhängigen Teilaufgaben.

## 1. Exact immutable review target, branch safety, evidence authority

### Writable repository: ausschließlich FlexPlan.jl auf einer eigenen Review/Korrekturbranch

- Repository: `https://github.com/AlOussama/FlexPlan.jl`
- **Unveränderlicher geprüfter AP3-Commit:** `485b637cc1998a327206c5929434bd26c6f0be16`
- Ursprüngliche Implementierungsbranch: `implementation/paper-a-ap3-all-formulations-v1` — **nicht beschreiben**.
- **Bereits für diesen Auftrag angelegte unabhängige Arbeitsbranch:** `review/paper-a-a3-5-independent-acceptance-v1`, initial exakt von `485b637cc...` abgezweigt. Sie darf für neue Auditdateien und nötige Korrekturen fortgeschrieben werden; kein Force Push, kein Rebase fremder Geschichte, kein Auto-Merge/PR.
- Baseline AP2: `725de2e6c1cea21f63902474f72ec614b2358356`
- Strang-B geprüfter Consumer: `e992edc88d39fa0eb2d72e2490e157441223f568`
- Producer-Numerik: `AlOussama/PyPSA2MatpowerX@3b8fdb01d931225edc5f8fe1e2c200d0da288a09`
- AP1 ursprünglicher Code: `32ff4525dc576af52c16298cb35ebd98f02cf8b2`
- Parameterregister-SHA256: `a249f7a96d202798c6ff5778c1fa1571eba59a3717bac5d25b150d2a6c41bce9`
- Szenario-TOML-SHA256: `be9d9d9aa90e9790fc7c3554bc1107777a5ba743f4f95d8f675acd9bfeb1e75a`
- Wissenschaftliche Referenz: `AlOussama/research-map/main@e8118425adc335a99e85120d943763305f211315`
- Gefrorener mathematischer Inhalt: `2c2fce769b2ed6ffd4f1ced60c0798776acccc93`
- Paper-A-Scopespezifikation: `672a61c95525bf1d7a03cf745a754a15a23ce78b`
- Strang-B-Wissenschaftsvorbehalt: `research-map@a6c19790bb009b5956475a6368a23e339a82dab7`

**Am Start:** `fetch`, `ls-remote`, Branch-/Worktree-Status und Merge-Base aller tatsächlich verwendeten Quellen prüfen. Original-AP3-Arbeitsbaum und alle vorgefundenen Dirty-/untracked Dateien erhalten; auf eigenem sauberem Checkout/Worktree arbeiten. Sollte die Auditbranch bereits vom vorbereitenden Doku-Commit vorgerückt sein, nicht zurücksetzen. Jede spätere Änderung gegenüber dem fixierten Target sauber als Audit-/Korrekturdelta festhalten. Producer und research-map **nur lesen**. Der gemeinsame mathematische Freeze darf weder wegen Tests noch wegen Solverproblemen geändert werden.

## 2. Autoritative Quellen lesen — Theorie vor Code

### Vollständige Mathematik, nicht bloß Paper-Manuskript
- `research-map/docs/reports/C2_constraints/C2A_voltage_stability/scientific_report/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md`, **Part V §§17–26, Part VII §§41–44, Part VIII §§50–52, Anhänge B–F**.
- `.../external_review/freeze/2026-08-02__c2a-scientific-formulation-freeze.md`.
- `.../synthesis/2026-07-30__synthesis__c2a-track-a-adjudicated-proofs-and-counterexamples.md`.
- `.../implementation_audit/2026-07-30__c2a-project-predicate-audit.md`: P-C2A-001 bis -010; historische `not_verified` nicht ungeprüft auf heutigen Code übertragen.
- `.../publication_planning/2026-08-09__paper-a-development-plan-freeze.md` und `.../publication_planning/2026-10-15__paper-a-multirepo-execution-freeze-v2.md`: vier Experimentfamilien und X01–X12.

**Fachliche Kandidaten und Grenzen:** G0, G1, fixed G2(r), exakte G3/Closed-SDD, exakte M0-Nachbewertung, M1 geordnete M-Matrix-Untergrenze, M2 Interaktionsgewichte, LOCAL und Woodbury/Neumann/E2. Aussagen T-C2A-001–028 einschließlich Schur-Range, singulär/reduzibel, G0 nicht⇒M0, G1/G2-Unvergleichbarkeit, T018–020 und T025–028. Historische `ESCR gSCR MSCR Comparison`-Materialien nur als zusätzliche Kandidaten-/Konventionsquelle, nicht gegen Theoremfreeze.

### Implementierung und Evidenz
- `reports/paper_a_ap3_validation.md`, `reports/paper_a_ap3_status.yaml`, `docs/paper_a/ap3_to_a3_5_handoff.md`, `reports/paper_a_ap3_publication.md`.
- `docs/paper_a/ap3_formulation_candidate_registry.md`, `docs/paper_a/ap3_evaluation_metric_registry.md`, `docs/paper_a/ap3_implementation_architecture.md`, `docs/paper_a/ap3_postprocessing_user_guide.md`.
- `src/core/paper_a_formulations.jl`, `src/core/paper_a_diagnostics.jl`, AP2 `paper_a_regional.jl`, `paper_a_integration.jl`, `block_template.jl`, `ref_extension.jl`, `objective.jl`, `src/prob/uc_gscr_block_integration.jl`, Strang-B `paper_a_qualification.jl`.
- `scripts/paper_a/AP3Pipeline.jl`, `scripts/paper_a/ap3.jl`, `test/paper_a_ap3.jl`, `test/runtests.jl`, CLI-/Evidenztests.
- `reports/ap3_runs/20261020_macro/` einschließlich `accepted_suite`, `enumeration_final`, `integer_bound_audit.json`, `integrated_integer_enumeration.json`, `integer_recheck_diagnostics.json`, `matrices_final`, `metrics_final`, `certificates_final`, `comparisons_final`, `planning_final`, `benchmarks_final`, `export_final/evidence_index.json`, `blocker_register.json`, `paper_a_ap3_cli_execution_manifest.json` (letztere ggf. in `reports/` suchen).
- Manifest-/Quellhash-Dateien und Git-veröffentlichte ZIP-Archive der großen Metriken. ZIPs für die unabhängige Byte-/Datenprüfung extrahieren, aber den älteren Evidenzindex nicht überschreiben.

Die AP3-Ergebnisse sind **unabhängig zu verifizieren**: 6087/6087 Vollregression, 4108/4108 Evidenztests; 124 Metrik-IDs, 68861 Datensätze, 687 Snapshot-Rekonstruktionen; acht CLI-Aktionen; neun Integer-Referenzintervalle, max. gemeldeter relativer Gap 1.0567e-9; maximaler B/S/M-Residual 3.41e-13; G0/G3 kontinuierliche maximale relative Kostendifferenz 2.915e-7. Das sind **Claims des Implementierers**, kein vorweggenommenes Prüfergebnis. Eine verfügbare numerische Python-Rationalreferenz ist nur ein unabhängiger Stichprobenbeleg.

## 3. Unabhängiges Abnahmeprogramm — fachliche Prüfungen

### A. Beweiskette, Matrixprädikate, Schur und Physik

Für jedes relevante eingefrorene Claim T001–T028 eine `theorem_id -> assumptions -> formula -> code/file/line -> independent test -> verdict`-Zeile, mit exakten Commitreferenzen. Keine mathematischen Beziehungen aus Codekommentaren als bewiesen deklarieren.

Spezielle Pflichtprüfungen:

1. **Physischer Stempel:** Independentes \(Y^{(+)}=G+jB^{phys}\), \(L=-\Im Y^{(+)}\), passives \(B^0=L_{rr}-L_{re}L_{ee}^{-1}L_{er}\), feste Shunts/Quellen genau einmal, MVA/native-Reaktanz und mu-Basen. **Kein künstliches Slack-Grounding** und keine eliminierte schaltbare Stärke. Schur-Invertierbarkeit und Schur-PSD-Äquivalenz ausdrücklich unterscheiden.
2. **Affines Online-Modell:** Aus ursprünglichen Producer-Parametern und tatsächlichen installierten/online/dispatch Variablen **selbstständig** \(B_t\), \(S_t\), \(M_t=B_t-\alpha S_t\) und Zeilen ausdrücken. Eine Kontrolle aus den vom AP3-Modellexport kopierten `affine`-Matrizen allein ist nicht unabhängig. Festnetz/AC-island, Bezugsebene, Klassen SYN/GFM/GFL/SC, offdiag und Diagonalabbildung prüfen.
3. **Domain:** \(M=M^\top\), offdiagonal \(\le0\), PSD/PD/Nullität/Inertia, positive/singuläre Inseln, \(\mathcal B^{-1}\ge0\) nur wenn definiert und nachgewiesen, Non-Z-Ablehnung, eigenspace-Multiplizität und Kondition. Prüfungen **pro gelöstem Zustand**, keine universelle Positivdefinitheit ohne mathematische Garantie.
4. **Singuläre Exposition:** Vollraum-G0 ist definiert bei \(S\succeq0\). Für \(S_{zz}=0\), \(B_{zz}\succ0\): gewöhnlicher Schur. Bei \(B_{zz}\succeq0\) singulär zusätzlich Range \((I-B_{zz}B_{zz}^\dagger)B_{za}=0\) und generalisierter Schur. Negative \(B_{zz}\) und `S=0` separat. Keine \(\epsilon\)-Regularisierung.
5. **G1/G2:** \(M1\ge0\) und \(Mr\ge0,\ r>0\) fest. Beide Gegenbeispiele der G1/G2-Unvergleichbarkeit, feste r-Provenienz, keine von optimierten Variablen abhängige lineare r-Wahl.
6. **G0/G3:** Kante \(i<j\) genau einmal und **signiertes** \(m_{ij}\); zwei orientierte q, \([q_{ij},q_{ji},\sqrt2m_{ij}]\in Q_r^3\); \(m_{ii}-\sum_jq_{ij}\ge0\); vollständige Reconstruction und Nullzeilen. T-C2A-018–020 auf dem gültigen symmetrischen Z-Bereich einschließlich singulärer/reduzierbarer Grenzen; G0/G3 **nicht** auf Nicht-Z-PSD übertragen.
7. **M0:** \(y=B\backslash p\), \(B\succ0\), inverse-positive Klasse und \(\alpha>0\). Lokale \(\rho_i^{diag}\) und \(\rho_i^{Zp}\) getrennt. \(G0\not\Rightarrow M0\) und local-not⇒G0 anhand unabhängiger Rationalfälle.
8. **M1:** Bmin selbst symmetrische nonsingular M-Matrix, gültige Quellenminima tatsächlich **im Modell erzwungen**, offdiag identische physische Stempel, elementweise \(B\ge Bmin\), inverse Ordnung \(0\le B^{-1}\le Bmin^{-1}\), zulässige matrix-/normbasierte Rundung. Kein Ersatz für eine **nicht** bewiesene universelle Diagonal-Margin-Untergrenze.
9. **M2:** \(W\ge0\), \(W_{ii}=1\), vorher fixierter MIIF-/Neighbor-Scope; bedingtes M2⇒G1⇒M0 nur mit den theorematischen Zusatzannahmen. Sparse W „leichter erfüllbar“ ist keine empirische Genauigkeitsgarantie.
10. **E2/Woodbury/Neumann:** tatsächliches algebraisches Restglied, Residual, Norm und \(\rho(A^{-1}\Delta)\); wenn \(\|E\|\ge1\) oder Trust Region fehlt, **kein einseitiges Sicherheitszertifikat**. Unter keinen Umständen unkontrollierte Taylor-Reihe zu einer sicheren MILP-Bedingung erklären.

**Unabhängige Rational-Orakelpflicht** unter anderem:
\[
B=\begin{bmatrix}1&-1/2\\-1/2&1\end{bmatrix},
p=(1/4,2/3)^\top,\alpha=1,
M=\begin{bmatrix}3/4&-1/2\\-1/2&1/3\end{bmatrix},
\]
mit \(\sigma(M)=\{0,13/12\}\), \(M1=(1/4,-1/6)\), \(B^{-1}p=(7/9,19/18)\), G3 q=(3/4,1/3), G0/G3 wahr, G1/M0 falsch. Ein unabhängiger SymPy-Check vor diesem Auftrag bestätigte diese **rationalen Identitäten**. Die unabhängige Julia-Auditimplementierung darf sie nicht aus AP3-Fixture-Exports übernehmen.

### B. Numerische globale Optimierung, Solver und B1

**Hauptblocker B1:** Pajarito/HiGHS/Clarabel meldete bei nativer G3-MISOCP-Ausführung teils `INFEASIBLE`, obwohl alternative Methoden zulässige Punkte liefern. **Nicht ungeprüft „Solverbug“ diagnostizieren**. Alle Ebenen untersuchen:
- identische Ausgangs-Casebytes, Registry-/Szenario-SHA, Alpha/Exposure, Rounding, Integer-Domain, Quelleninventar, P+E-Kosten, Energiebilanzen und Ereignisgewichte;
- tatsächlich identische MOI/JuMP-Constraints/Index-/Kantenstruktur vor Solver-Bridge und **nach** Bridging, Modellequivalenz bei kontinuierlichem/Integer-/Integer-fixiertem Modell, keine verlorene SOC-Kante, falsch implementierte Rotated-SOC-Skalierung oder veränderte Schranken;
- Pajarito Outer Approximation/Conic separation, Schnittvalidität, numerische lineare Unterprobleme, Warmstarts, Toleranz, Objective Scaling, Hub der MIP-/Conic-Dualzertifikate, Iteration/Timeout; alternative unabhängige Conic- und MIP-Solver mit tatsächlich festgestellter Lizenz/MOI-Unterstützung;
- für einen **konkreten** von Pajarito als `INFEASIBLE` zurückgegebenen Fall, unabhängigen vollständigen Kandidaten-Witness (alle Block-/Powerflow-/Storage-/UC-/Zeit-/SOC-Variablen), positiven Constraint-/SOC-Check und funktionierenden integerfixierten kontinuierlichen SOCP nachweisen; nur dann handelt es sich um einen tatsächlich widersprüchlichen Solverbefund;
- reproduzierbaren Minimalfall erzeugen und nach Möglichkeit den numerischen Fehler im Modell/Bridging/Skalierungsweg **innerhalb dieses Makroauftrags** korrigieren. Bei extern nicht korrigierbarem Solverbefund den bisherigen `numerical_inconclusive`-Guard behalten, niemals global jedes genuine infeasible Integer-SOC-Problem als inconclusive umdeuten; begrenzte nachvollziehbare Bedingung formulieren.

**Neun Referenzintervalle:** `reports/ap3_runs/20261020_macro/integer_bound_audit.json` unabhängig prüfen:
- Die veröffentlichte Objektivobergrenze muss zu einem originalmodell-feasiblen **vollständigen** Integer-Witness samt Constraint-/Cone-/Cost-Residual gehören.
- Eine Solver-Objective-`bound` ist nicht automatisch global gültig. MOI-Solverstatus, korrekte minimierende Boundrichtung, Dual/OA-Zulässigkeit, vollständige Integer-Suchraumbedingungen, Solverstatus, Skalenfaktor, verschobene affinen Offset-Anteile und Base/Weighting neu herleiten. Keine Kombination von Fällen mit ungleichen Hashes oder ungleichen physikalischen/Numerikannahmen.
- Wenn die Untergrenze numerisch oberhalb der unabhängig rekonstruierten Obergrenze liegt, das als **Toleranz-/Konsistenzproblem** gesondert melden und nicht formal „Rigorous Interval“ behaupten.
- Eigene kleine, **vollständig enumerierte** 2-/3-Bus- und ggf. wenige echte Integer-Entscheidungen als Goldstandard rechnen. In umfangreicheren Fällen `numerically_supported_bound` von mathematisch streng zertifiziertem globalem Optimum unterscheiden.
- Für G0/G3 gleiche **zulässige Menge und Zielkosten** unter Z-Matrix-Voraussetzungen; Solverpraktikabilität ist getrennt von mathematischer Äquivalenz. G1/G2/M1/M2 nicht mit G0 als gleicher physikalischer Sicherheitsbegriff vergleichen, falls eine andere Targetmetrik verwendet wird.
- Die im AP3-Bericht verwendete unabhängige Kostenabweichung bis **0,01534 Währungseinheiten** und Prüftoleranz **1 Einheit** prüfen: auf absoluten Zielwert, relative Genauigkeit, Optimallitätsgap und wirtschaftliche Aussagen beziehen; Toleranzen nicht allein durch Großzahlen rechtfertigen.
- `Objective`-Rebasing, inkrementelle positive Variablen und deren konstante Terme beweisbar objektiv-/feasible-set-neutral halten. Erhaltene `INFEASIBLE`-, `ITERATION_LIMIT`-, `OPTIMAL`- und `numerical_inconclusive`-Rohdaten nie nachträglich umetikettieren.

### C. Alle 124 Metriken und acht ausführbare CLI-Aktionen

Rekonstruiere einen **externen, code-unabhängigen Erwartungswertkatalog** aus den vollständigen Definitionen, nicht durch Kopieren von `metric_registry.json`. Prüfe für alle **124 IDs** Formel, Basis, Einheit, Domain, Bezugsebene, Status/Null, tatsächliche Werte in mindestens einem analytischen Fixture und einem reproduzierten Szenario, soweit mathematisch definiert. Rechne jedenfalls unabhängig:
- B/S/M, Eigen-/Schur-/Netzsignaturen; G1/G2 Slacks, G3 q/edge/diagonal budgets und certificate witness;
- finite generalized gamma, S=0, S singular + range condition, lokale rho/1/Zii, \(Zp\), M0/M1/M2, MIIF-Denominator und full/sparse W;
- Woodbury/Neumann actual error, remainder and bound im-/außerhalb Trust Region;
- CAPEX/Overnight/Annuität, OPEX/No-load, Storage/Energie, Startup/Shutdown pro Block-/Ereignis, dispatch/event hours, regional new MW/MVA/MWh, Investment-/Versorgungseffekte und Constraintresiduen;
- Solver Gap/Bound/Termination, laufbezogene CPU-/Compilation-/Walltime und speicherbezogene Einheiten. Peak-RSS darf nicht mit allokierten Bytes verwechselt werden;
- `S^{nom}`, `S^{on}`, `S^{op}` und `S^I` mit ihren **verschiedenen** physikalischen Bedeutungen; externe SCR/ESCR/MSCR/gSCR ohne Fault-/Voltage-/Rating-Definition bleibt `not_comparable`, nicht „gemessen“.

**Besonders prüfen:** dimensionskonsistente numerische Toleranzen (SOC-Produkt = p.u.², Eigenwerte = p.u., MIP Gap = dimensionslos, Geldkosten = Währung), irrtümliche Ersetzung eines `undefined` durch 0, reine Symmetrieprüfung ohne Z-Voraussetzung, fein skaliertes \(b_{ij}\), Singulärgrenzen und Eigenraum-Multiplizität.

Die acht tatsächlich ausführbaren **AP3-CLI-Operationen** unabhängig mit **frischem Outputroot** ausführen: `run_formulation_suite`, `reconstruct_strength_matrices`, `evaluate_strength_metrics`, `verify_certificates`, `compare_formulations`, `assess_planning_results`, `benchmark_conic_scaling`, `export_paper_a_evidence`. Keine AP3-Evidenzdateien in situ überschreiben. Aus ihren unabhängigen Ergebnissen 100%-ID-Abdeckung, CSV/JSON-Kompatibilität, SHA-Validität, Kosten-/Constraint-Summen und robuste Nicht-Erfolgszustände prüfen. Ein bloßer Replay der originalen Outputs reicht nicht: mindestens ein **neu gebautes Negativfixture** und ein kleines positives Szenario unabhängig erzeugen.

### D. Reproduzierbarkeit und Baselines

Frischer sauberer Julia-1.10.11-Project-/Manifest-Checkout oder exakt dokumentierter kompatibler Runtime; vollständige Pkg-Versionen und Artifacts. Alle 14 großen Metrics-ZIPs und den 1.5-GB-Rohdatenindex ohne stillen Datenverlust überprüfen. Falls Speicher-/Zeitgrenzen praktische Vollbyteprüfung verhindern, Teile als `not_verified` mit Stichprobenmethode ausweisen. **Keine Repro behaupten ohne tatsächlich ausgeführten Prozess**.

AP2/Strang-B und AP3-Replay: historische (AP2 5987, Strang-B 291+54+51) sowie neuer AP3 Vollsuite 6087/6087 und 4108/4108 nicht allein aus Reports kopieren, sondern nach Codeänderungen frisch ausführen. Negative 3 Producer-Integer-INFEASIBLE-Fälle unverändert prüfen. Falls keine Julia-Umgebung/Conic-Lizenz, alle statischen und eigenständigen Rationaltests durchführen und verbleibende Gaps unverified lassen, nicht zu einem 0-Fehler-PASS umetikettieren.

## 4. Maschinenlesbarer Befund- und Korrekturprozess

### Phase I — strikt unabhängiger unveränderlicher AP3-Baselineaudit
- Erstelle `reports/a3_5/initial_review_of_485b637.md` und `reports/a3_5/initial_findings.yaml` **vor jeder Codekorrektur**. Jede Finding-ID erhält `severity=blocking|major|minor|informational`, Datei/Funktion/Zeile, Theorem-ID, konkrete unabhängige Gegenrechnung, betroffenen Gate, erwarteten korrekten Zustand, gesicherten Repro-Befehl und Vorschlag.
- Ein unveränderlicher SHA des ursprünglichen Target-Commits bleibt in jedem Findingsheet. Trenne bestätigte Fehler von Solver-/Beweisschwierigkeiten und bloßen Verbesserungsvorschlägen.
- Prüfe mindestens T-C2A-001–028, P-C2A-001–010, Kandidaten BASE/G0/G1/G2/G3/M0/M1/M2/LOCAL/E2 und alle Metric-/CLI-Familien. Existieren keine Blocker, darf ein **unabhängiges Urteil über genau `485b637...`** erstellt werden, sofern sämtliche strikten Abnahmetests tatsächlich liefen.

### Phase II — falls nötig autonome Korrektur auf DIESER Reviewbranch
- Korrigiere **nur** durch bestätigte Befunde begründete Quellcode-/Test-/Report-Mängel, mit kohärentem Fix, gezielten Negativtests und vollständiger Regression. Kein stiller Physics-/Theorem-/Daten-„Fix“ zur Erzeugung günstigerer Solves.
- Keine neue unabhängige Feature-/Reviewbranch pro Fehler und keine Mikroschritt-Rückfrage. Logge jede Korrektur als `A3.5-FIX-ID` mit Vorher-/Nachher-Formel, exakten Files/Commits, Regression und Kosten der Änderung.
- Falls der Fehler eindeutig aus **fremdem** Julia-/MOI-/Solver-Backend stammt, ein minimales reproduzierbares Experiment und eine wissenschaftlich korrekte umgehende Methode liefern; keine ungetestete globale Assertion „Solverbug“.
- Wenn Korrekturen die mathematische Feasible Set oder Zertifikatsbedeutung ändern, bleibt `independent_A3_5_accepted=false`, bis ein **anderer** Prüfer den finalen Korrektur-HEAD erneut akzeptiert. Eigenständige numerische Regression nach einer Korrektur ist sehr wertvoll, aber nicht erneut *personell unabhängig*.

### Phase III — neue unabhängige Numerik + Abschluss-/Handoff
- Erzeuge Prüfwerkzeuge unter `test/a3_5_independent/` oder `scripts/a3_5_independent/` mit unabhängiger algebraischer Rekonstruktion und mindestens einem **getrennten** Test-Oracle, z.B. exakte Rational-/BigFloat-Matrizen, Python/SymPy/SciPy oder eigenständige Julia `LinearAlgebra`-Funktionen. Nicht den AP3-Diagnostics-Algorithmus importieren und erneut als „unabhängig“ ausgeben.
- Vorher fixierten AP3 Target-HEAD und gegebenenfalls neuen Reviewkorrektur-HEAD in **separaten** Protokollen prüfen. JSON/YAML/CSV-Artefakte mit SHA256 und Reproduktionsbefehlen erzeugen.
- Ergebnis `A3_5_accepted_scoped` nur bei unabhängiger Vollabnahme **des unveränderten geprüften Commits**; nach materiellen Korrekturen `A3_5_corrections_applied_pending_independent_rereview` (obwohl technische Tests grün sein können). Ein abgelehnter echter Theorem-/Codefall ist `A3_5_rejected` mit eindeutiger Erklärung, nicht `partial` ohne konkreten Befund.
- Eine weiterhin problematische native G3-MISOCP-Runtime darf als **isolierte Capability-Einschränkung** akzeptiert werden, wenn und nur wenn mathematischer Code korrekt, vollständige unabhängige Referenz-/Conic-Solves tatsächlich gültig und das eingeschränkte Solver-Gate transparent als `native_MISOCP_qualified=false` belassen wird. Falls uneingeschränkte native MISOCP für die anstehende Publikationsbehauptung notwendig ist, ist diese Behauptung weiter blockiert.
- Empirische Daten-/Quelle-/Kosten-/Jahres-/Fault-/Stromfähigkeitsgates bleiben unverändert extern; ohne nachgewiesene Evidenz **niemals** `empirical_data_approved=true`, `AP4_ready=true` oder `A3_closed=true` setzen. Eine fachlich begrenzte mathematische AP3-Freigabe ist von echter Paper-A-Studiendatenfreigabe zu trennen.

## 5. Verbindliche Artefakte und Kennzahlen

Auf der eigenständigen Reviewbranch in `AlOussama/FlexPlan.jl`:
- `docs/paper_a/a3_5_independent_acceptance_spec.md` (dieses Mandat).
- `reports/a3_5/initial_review_of_485b637.md`: eigener wissenschaftlicher Report über unveränderten Baselinecommit.
- `reports/a3_5/theorem_and_equation_traceability.csv`: T001–028, fachliche Gleichungs-/Beweisbedingungen, Code-Test-Referenz, überprüfter Zustand.
- `reports/a3_5/project_predicate_adjudication.csv`: P001–010, Test, Domain, verbleibende Universal-/Empiriegrenzen.
- `reports/a3_5/initial_findings.yaml` und ggf. `correction_register.md` mit Änderungen und re-test evidence.
- `reports/a3_5/solver_b1_independent_analysis.md`: native MISOCP-Minimalrepro, Bridge/Modell/Operator-/Skalierungsprobe, Zeuge oder nicht bewiesene Infeasibilität; ggf. unabhängige numerisch gültige Alternative.
- `reports/a3_5/independent_integer_bounds.csv`: alle neun Case-Hashes, untere/obere Schranke, Boundherkunft, duale Gültigkeit, Rundungsmaß, Währungsbasis/offset, Worst Gap, `numerical_reference` vs rigorous.
- `reports/a3_5/metric_and_cli_acceptance.csv`: alle 124 Metriken, alle acht Aktionen und negative/undefined-/Szenarioscope-Nachweise.
- `reports/a3_5/independent_validation.md`, `reports/a3_5/status.yaml`, `reports/a3_5/reproduction.md`, `reports/a3_5/evidence_manifest.json`.
- Falls Codekorrekturen: echte Quellpatches + neue gruppierte Tests + Nachherprotokoll unter `reports/a3_5/corrected_head_review.md` und eine **vollständige Übergabe an anderen unabhängigen Reviewer**. Keine Wiederholung einer zuvor bereits gefrorenen Berichtdatei durch neue Findings ohne nachvollziehbare Versionsidentität.

Minimalstatus:

```yaml
review_target_sha: 485b637cc1998a327206c5929434bd26c6f0be16
review_branch: review/paper-a-a3-5-independent-acceptance-v1
review_verdict: pending | accepted_scoped | corrections_required | rejected | corrections_applied_pending_independent_rereview
science_theorems_T001_T028: unverified
project_predicates_P001_P010: unverified
G0_G3_exactness_on_Z_domain: unverified
M0_M1_M2_G1_G2_implications: unverified
native_G3_MISOCP_solver: unverified
integer_global_bounds: unverified
metrics_124_coverage_and_correctness: unverified
postprocessing_eight_cli_functions: unverified
ap1_ap2_strang_b_regression: unverified
empirical_study_ready: false
independent_A3_5_accepted: false
A3_closed: false
AP4_ready: false
```

## 6. Eigenständige Entscheidungsfreiheit, Stop-Kriterien, Abschlussbericht

Du darfst Methoden, numerische Kontrollsoftware, toleranzskalierte unabhängige Schwellen, Projektstruktur, Solverbenchmarks, Softwarefixes und sinnvolle negative Testfälle **innerhalb dieser mathematischen Ziele frei wählen**, ohne in Rückfrageschleifen zu gehen. Eine Quelle mit 1,5 GB Evidenz muss nicht ineffizient mehrfach geladen werden, wenn Hash-/Inhaltsvalidierung äquivalent nachgewiesen wird. Keine manuelle Sichtprüfung jedes CSV-Werts statt deterministischer statistischer/ganzheitlicher Tests.

Nur substanzielle Eskalationsfälle: veränderte gefrorene Mathematik/Proof, neue Physik oder zulässiger Parameter-Scope, Änderung wissenschaftlicher Claims, fremde Dirty-Git-Arbeit nicht sicher erhaltbar, Zugriffs-/Solvergrundproblem ohne überprüfbaren Ersatz. Selbst dann zuerst alle übrigen Teilbereiche abschließen und **einen** finalen Entscheidungs-/Blockerbericht liefern.

**Abschließende deutsche Antwort (ein Bericht):**
1. Exakte Review-Baseline, Branch- und SHAs, wissenschaftlicher Freeze, Produkt-/Paket-/Solver-/Evidenzhashes, Versionen und unberührte Repos.
2. Reviewverdict getrennt für Mathematik, Algorithmik, numerische Optimalität, Postprocessing, Real-Daten und native MISOCP-Capability.
3. Beweise/Domain/T-Theoreme, negative Rational-/singuläre Cases und P001–010 als **unabhängig nachgerechnete** Evidenz.
4. Alle neun Integer-Referenzen, G0/G3-Kreuzfeasibility, Währungsbound-/Gap-Rechnungen, bei B1 minimal reproduzierbare Fehlerursache und alternative tatsächlich getestete Solverstrategie.
5. 124 Metric-IDs, acht CLI-Prozesse, neue Residuen/Toleranzen und unabhängige End-to-End-Schema-/Hash-Ausgaben; tatsächliche Tests mit Prozess-Exit.
6. Alle Findings (bestätigt / ausgeschlossen / offen) mit Severity; ggf. zusammenhängender dokumentierter Korrektur-Commit und erneute Regression.
7. Finalen verifizierten Remote-HEAD der Reviewbranch und veränderte Pfade; keine Force-Pushes, keine PR/Auto-Merges.
8. `A3_closed`/`AP4_ready` bleiben false bis separater vollständiger unabhängiger und datengültiger Schlussfreigabe; bei eigenen Korrekturen erneuten unabhängigen Reviewer zwingend benennen.

**Ausführungsfreigabe:** JA — eigenständige A3.5-Prüfung des exakten AP3-Commits, autonome wissenschaftlich notwendige Korrekturen auf genau der Reviewbranch, vollständig unabhängige numerische Wiederholung und maschinenlesbarer Abschluss. Eine materielle eigene Korrektur kann nicht selbst als abschließend unabhängig abgenommen werden.
