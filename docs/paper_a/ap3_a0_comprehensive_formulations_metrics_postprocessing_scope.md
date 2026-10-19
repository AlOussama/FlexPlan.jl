---
title: "Paper A — AP3 complete formulation and postprocessing scope"
date: 2026-10-20
status: owner_scope_decision
implementation_status: not_started
parent: docs/paper_a/ap3_a0_full_mathematics_gap_analysis.md
ap2_code_baseline: 725de2e6c1cea21f63902474f72ec614b2358356
science_basis: complete_C2A_dissertation_v3_and_frozen_T-C2A-001_to_028
---

# AP3-A0 — Vollständiger Kandidaten-, Bewertungsmetriken- und Post-Processing-Vertrag

## 0. Eigentümerentscheidung und Verbindlichkeit

**Owner-Entscheidung:** In AP3 sind **alle mathematisch und rechnerisch sinnvollen, früher entwickelten System-Stärke-Kandidaten** zu implementieren, nicht nur der bisherige G0/G1/G3-Kern. **Alle zugehörigen Bewertungsmetriken und die ausführbaren Skripte für unabhängige Post-Processing-Auswertungen** gehören gleichrangig zum verpflichtenden AP3-Lieferumfang.

Die frühere AP3-A0-Scope-Aussage „G2/M1/M2 optional“ ist hiermit für die **Implementierungsplanung** supersediert; weder die mathematischen Theoreme noch der Paper-A-Publikationsscope werden dadurch rückwirkend geändert.

„Implementierung“ wird wissenschaftlich korrekt nach Funktionstyp unterschieden:
- tatsächliche auswählbare Optimierungsformulierung, sofern mathematisch und solvertechnisch unterstützt;
- exakte, numerisch rekonstruierte Nachbewertungsmetrik (auch wenn sie nicht konvex als Optimization-Constraint erzwingbar ist);
- mathematisch gültiges hinreichendes Zertifikat mit allen Voraussetzungen;
- bedingte Approximation **nur** mit bewiesenem Gültigkeitsbereich, Trust Region und einseitiger Fehlerschranke; andernfalls ausschließlich eindeutig als nicht zertifizierend gekennzeichnete Research-Diagnostik;
- physikalisch alternative Metrik-/Exposure-Definition mit eigener Semantik, Nenner- und Datenvalidierung.

Ein Worker darf keinen Kandidaten allein deshalb ignorieren, weil er später nicht im Haupttext des Journals erscheint. Wo ein Kandidat tatsächlich keine zulässige mathematische oder physikalische Domäne besitzt oder ein Solver nicht verfügbar ist, muss er separat mit einem nachvollziehbaren Grund und einem lauffähigen unabhängigen Diagnose-/Referenzpfad geführt werden.

## 1. Wissenschaftliche Quellen und Kontrollgrenzen

**Mathematische Hauptquelle:** C2A-Dissertationsfassung v3 auf research-map/main@e8118425adc335a99e85120d943763305f211315, §§17–26, §§41–44, §§50–52 und Appendices B–F; eingefrorene Theoreme T-C2A-001–028 und der wissenschaftliche Freeze 2c2fce769b2ed6ffd4f1ced60c0798776acccc93.

**Historischer Ideen- und Kandidatenfundus:** ausführliche Projektformulierung „ESCR gSCR MSCR Comparison“ mit G0/G1/G2/G3/M0/M1/M2, lokalen ESCR-/MSCR-/MIIF-Metriken und optionaler Woodbury-/Neumann-beschränkter MSCR-Approximation E2. Historische Formeln sind gegen eingefrorene Theoreme zu prüfen, **nicht automatisch** als neue wissenschaftlich freigegebene Aussagen zu übernehmen.

**Publikations- und Evidenzrahmen:** research-map „2026-08-09__paper-a-development-plan-freeze.md“ verlangt numerischen Vergleich der ganzen Formulierungsfamilie und vier Experimentfamilien (Geometrie/Fidelity, wirtschaftliche Auswirkungen, Skalierbarkeit, Robustheit/Modellsemantik). Der „2026-10-15__paper-a-multirepo-execution-freeze-v2.md“ war als erste Kernimplementierung enger; die hier dokumentierte Entscheidung erweitert den AP3-Code-/Metrikscope, ohne die Proof- oder Daten-Gates zu schwächen.

**Codebasis:** FlexPlan AP2@725de2e6c1cea21f63902474f72ec614b2358356 und AP3-A0@cf2127f9ec4eeb4b7b40c6f898434939283ade27, AP1@32ff4525dc576af52c16298cb35ebd98f02cf8b2. AP3 verwendet das vorhandene gemeinsame affine B/S/M, G1, Block-UC, Speicher und Kosten. Die parallele Strang-B-Datenqualifikation bleibt unabhängig; reale Studiendaten ohne Quell-/Kosten-Evidenz bleiben unfreigegeben.

## 2. Vollständiges Formulierungs-Kandidatenregister

Seien B_t=B0+diag(b_src,t), p_t=p_fl,on,t, S_t=diag(p_t), M_t=B_t-alpha*S_t mit **festem alpha>=0**. G0/G1/G2/G3 erfordern die deklarierte reelle symmetrische Z-Matrix-Domäne, soweit jeweils theorematisch notwendig.

| Kandidat | Modell/Zertifikat | Exaktheit / Konservativität | AP3-Verpflichtung |
|---|---|---|---|
| BASE | Kein Stärkeconstraint | Kontrollfall | Bestehenden NoGSCR-Solve und Postprocess erhalten |
| **G0** | M_t >= 0 im Loewner-Sinn | Spektral exakte Referenz unter Modellannahmen | Echte PSD-/SDP-Constraints, unabhängige Eigenwertprüfung, kontinuierlicher SDP-Benchmark und kleiner ganzzahliger Referenzpfad mit tatsächlichem MISDP-Solver oder vollständig zertifizierter Enumeration |
| **G1** | M_t 1 >= 0 | Hinreichend für G0; kann konservativ sein | AP2-Baseline wiederverwenden, unabhängige Zeilenslacks und abgelehnte G0-zulässige Fälle auswerten |
| **G2(r)** | M_t r >= 0, r>0 **offline fixiert** | Hinreichend für G0; G1 und beliebige G2(r) sind nicht immer vergleichbar | Auswählbare LP/MILP-Formulierung, mehrere vorher spezifizierte r-Strategien; kein ex-post Tunen an optimaler Lösung und keine bilineare variable Skalierung als LP deklarieren |
| **G3** | vollständige paarweise Kanten-PSD/rotierte SOC + Diagonalbudgets | G3=>G0; für symmetrische PSD Z-Matrizen und vollständige Kanten-/Restdarstellung G3<=>G0, auch singulär/reduzibel | SOCP/MISOCP-Modell mit q_ij und q_ji auf jeder tatsächlichen ungerichteten Kante, signierten m_ij und unabhängiger Rekonstruktion |
| **M0** | y=B_t^-1 p_t <= alpha^-1 1 | Exakte eigenständige inverse Netzbelastungsbedingung, nicht aus G0 allgemein ableitbar | **Exakte Post-Solve-Metrik verpflichtend**. Zusätzlich kleinen wohldefinierten direkten NLP-/bilinearen oder diskret-enumerierten Enforcement-Benchmark bereitstellen, soweit mathematisch/solvertechnisch realisierbar; fehlenden Solver ehrlich als Capability-Gate kennzeichnen |
| **M1** | Zub p_t <= alpha^-1 1 mit Zub=(Bmin)^-1 | Unter nachgewiesener geordneter nonsingular M-Matrix und tatsächlich **erzwungener** Mindeststärke hinreichend für M0 | Echte feste-Inverse-LP/MILP-Formulierung; B>=Bmin, inverse Ordnung, Grenz-/Schranken-Residuen und erforderliche Min-Quelle prüfen |
| **M2** | B_t 1 >= alpha W p_t, W>=0, diag(W)=1 | MIIF-/Interaktionsgewichtetes lineares Zertifikat, M2=>G1 und bedingt M0 unter eingefrorenen Voraussetzungen | Als LP/MILP aktivierbar; volles und begründet sparsifiziertes, vorher fixiertes W; MIIF-Provenienz und Scopetests |
| **E2 / WN** | Woodbury-/Neumann-/Taylor basierte Schätzung mit **zertifizierter** einseitiger Restmarge | Nur bedingt sicher; ohne abgesicherte Schranke ausdrücklich **nicht zertifizierend** | Exakte Inverse-Update-Routinen, Norm-/Konvergenz-/Trunkations- und Restgliedprüfung; nur bei nachgewiesenem Trust-Region-/Marge-Gate als bedingtes LP/MILP, ansonsten ausführbare explorative Diagnose |
| **LOCAL** | Rang-1-PSD/Diagonallast-Tests | Lokale Kriterien, keine unbewiesene globale Implikation | Auf jedem zulässigen Zustand als Post-Solve-Zertifikat/Metrik auswerten; bei sinnvoller linearisierbarer beschränkter Form optionaler klar getrennt benannter Benchmark |
| **G2-fixed variants / M2-sparse variants** | Mehrere r bzw. W Strategien | Keine universelle Ordnung außer den bewiesenen Teilbeziehungen | Als explizite registrierte Vergleichsvarianten, nicht versteckt in optionalen Flags |

**Unbedingt mathematisch beachten:** Für G3 muss pro Kante eine 2x2-PSD-Matrix [qij,mij;mij,qji]>=0 und pro Knoten mii-sum(qij)>=0 entstehen. Im MOI-Rotated-SOC gilt [qij,qji,sqrt(2)*mij] in Qr3. Jede strukturell nichtverschwindende ungerichtete Kante genau einmal. Isolierte Nullzeilen, singuläre Laplace-Blöcke, reduzierbare Netze und singuläres S sind Testfälle, keine Gründe für künstliches epsilon.

Für M1 ist die Mindestquellenstärke explizit Teil des Modells, nicht nur des Berichts. Für M2 dürfen MIIF-Gewichte mit ihren physikalischen Provenienzen nicht als identisch mit exaktem M0 oder einer externen MSCR-Norm ausgegeben werden. Neumann T-C2A-028 liefert zunächst **eine Normfehlergrenze**, nicht automatisch eine sichere komponentenweise Schranke. G0 ⇒ M0 ist falsch; Fixed G1/G2 sind nicht generell ineinander enthalten.

## 3. Sämtliche Paper-A-Bewertungsmetriken — verbindlicher Metric Registry

Jede Metrik erhält ID, Formel, Scope (Bus/Region/Kante/Snapshot/Szenario/Portfolio), Einheit, Basis, Annahmen, erforderliche Daten, Codepfad, unabhängige Berechnung, mathematische Quelle und einen maschinenlesbaren Status. Zulässige Zustände: valid / undefined / not_applicable / blocked_missing_data / domain_invalid / solver_inconclusive / not_executed. **Fehlende und singuläre Werte nicht als null oder erfundene Unendlichkeit ausgeben.**

### A. Physikalische Modell-/Matrixrekonstruktion
- Y(+), L=-Im(Y), Schur-B0, B_t, p_fl,on, S_t, M_t und alle Netz-/Source-Stamps **unabhängig** aus AP1-Originaldaten, Region-Mapping und gelösten installed/online-Entscheidungen rekonstruieren.
- B0-/B-/S-/M-Vergleich gegen AP1-Diagnose und AP2-JuMP; Schur-Löseresiduum, Block-MVA-/Systembase-/native-x-/mu-Normalisierungsresiduen; fixed-in-Y vs endogene Quelle genau einmal; Anschluss a_conn getrennt von a_res; pro Zeitschritt.
- Symmetrie und maximale positive Nebendiagonale, Z-Matrix-Test, Matrixklasse PSD/PD/indefinite, Eigenwertinertia, Nullität, Kondition, Inseln/Erdung/Referenzen, source-/edge-/exposure-Inzidenzen, Fehler- und Domain-Status.

### B. Exakte spektrale und lineare gSCR-Kennzahlen
- gamma_GE als kleinster **endlicher** generalisierter Rayleigh-/Eigenwert von (B,S), bei S>0 über symmetrische Skalierung, bei Null-Exposition über exakten positiven-Support-Schur; singularer Eliminationsblock benötigt Pseudoinverse UND Range-Bedingung, kein epsilon und keine naive Löschung.
- min eigen(M), negative eigen counts, gamma_GE-alpha (nur wenn gamma definiert), G0 PSD residual/certificate; kritischer Expositions-/Eigenmodus und Lokalisierung (bei degenerierten Eigenräumen als Unterraum behandeln).
- G1-Zeilenslacks, G2 skalierte Zeilenslacks und bewiesene G1/G2-Unvergleichbarkeit, alle Regions- und Snapshot-Extrema, Bindungshäufigkeit, konservative G0-feasible Rejections.
- G3 qij/qji/Edge-Cone-Slacks, bilineare qij*qji-mij^2 Referenz, Node-Budget, signed-edge completeness, matrix reconstruction norm und G0-G3 cross-certificates.

### C. Impedanz, ESCR/MSCR, M0/M1/M2 und lokale Kennzahlen
Nur bei gültiger invertierbarer/positiv definiter Stärke-Matrix und jeweils erforderlicher Inversenpositivität:
- Z_ii über gezielte lineare Solves, Zp=B\p via Solve ohne unnötige explizite Gesamtinverse, Residuumsnorm, min inverse matrix entry, Konditionszahl, lokale equivalent short-circuit strength 1/Z_ii.
- local diagonal ratio rho_diag_i=1/(Z_ii*p_i) für p_i>0, multi-infeed burden psi_i=(Zp)_i, row-burden ratio rho_Zp_i=1/psi_i für positive burden, M0 slack alpha^-1-psi_i. Null-Exposure und psi=0 haben expliziten Status und dürfen nicht als erfundene Sicherheitsmessung erscheinen.
- MIIF_ij=Z_ij/Z_ii bei gültiger Modell-/Thevenin-Normalisierung; volles/neighbor-sparse W und Wp, M2 margin; Zub=(Bmin)^-1, Zub*p, tatsächliches Zp und inverse-order-check für M1; lokale rank-one PSD equivalence.
- Physikalische Konvention konventioneller SCR, ESCR, gSCR, MSCR **getrennt** von dem hier definierten mathematischen indexierten Matrixmaß dokumentieren: Quelle/Thevenin-Konvention, elektrische Kompensation, Nenner, Rating, Source/Fault-Time-Scale, externe Formeln. Unzureichend belegte externe Akronymvarianten als not_comparable/not_evaluated markieren statt falscher Gleichheit.

### D. Exact Woodbury / Neumann / Fehler- und Approximationsevaluierung
- Woodbury direct-vs-update inverse/linear-solve residual, low rank structure, Invertierbarkeit.
- E=A^-1 Delta: spectral radius, verwendete induzierte Norm, endliche Trunkationsordnung, tatsächlicher Trunkationsfehler, Remainder und obere Normschranke aus T028.
- Trust Region, einseitige Margin und erforderliche Fehlerkonversion explizit; Zahl fälschlich akzeptierter und konservativ abgelehnter Fälle als Diagnostik. Keine als sicher etikettierte unkontrollierte Linearisierung.

### E. Capacity expansion / Betrieb / Kosten
- Investierte Blöcke/MW/MVA/MWh über Carrier/Region/Klasse, initial/installed/online/dispatch, source-strength und GFL-Exposure, Grenzen und block rounding; Standortwahl und Differenzen.
- CAPEX (overnight vs annualisiert mit einheitlicher Basis), FOM, Produktion, non-load, Startup/Shutdown **pro Blockereignis**, Storage-Variable-Cost, Curtailment, getrennte Δt/Repetition/Event-Weights, Gesamtkosten und unabhängiges Objective-Reconstruction-Residual.
- Power-flow/nodal balance, branch limits, UC/installed-online/startup-shutdown, Storage SOC und Terminal-Residuals, Renewable a_res vs a_conn. Zeit-/Szenario-Aggregation explizit, niemals 72h stillschweigend als kalibriertes Jahr.
- Alternative Exposure: S_nom, S_on (Paper-A-Hauptscope), S_op, S_I nur mit expliziter physikalischer Semantik/Schwelle und tatsächlicher Datenzulässigkeit; keine Behauptung, alle sind Approximationen desselben Kriteriums.

### F. Formulierungsvergleich / Konservativität / Skalierbarkeit
- Für **identische Fälle, Parameter, Limits, Solver-Toleranzen und Objektivfunktionen**: Kostenanstieg absolut/relativ zu G0/G3, Portfolio-/Technologie-/Region-Mix-Differenzen, zusätzliche Stärke-/GFM-/SYN-/Speicherinvestition, zusätzliche Betriebs- und Eventkosten, Worst-Case Bottlenecks, marginal bindende Zeitpunkte.
- G0/G3 Cross-feasibility, objective agreement mit MIP/conic Gap, unterschiedliche gleich gute Portfolios, G1/G2 false rejection, G2 Unvergleichbarkeit, M0 separate Failure-Werte, M1/M2 Sufficient Certification. Nicht aus infeasible/unsupported Runs falsche Rankings machen.
- Variablen und Constraints nach linear/integer/PSD/SOC, Anzahl Kanten/Horizonte, solve/preprocessing/compilation walltime, memory soweit messbar, Solver/MOI-Capabilities, primal/dual cone feasibility, MIP gap, bound, nodes/iterations, Numerik/Toleranzen, deterministischer Seed und unabhängige Wiederholung.

**Abgrenzung:** Small-signal dynamics, full AC CPF und EMT gehören nicht als verpflichtende neue Modelle in AP3 (andere C2A-/Paper-B/C-Schicht). Diese Kennzahlen als out_of_paper_a_scope dokumentieren; keine fiktive Realwelt-Validierung. Vorhandene AC-PF-Validierungen können in der späteren AP4-Studie verlinkt werden.

## 4. Verpflichtende ausführbare Post-Processing-Skripte

Der AP3-Worker muss eine **tatsächlich ausführbare** modulare CLI-Auswertungskette liefern. Bestehende Tools und Tester sind wiederzuverwenden; eine einzige CLI mit eindeutigen Subcommands ist ebenso gültig wie getrennte Julia-Entrypoints. Mindestens diese 8 logischen Funktionen:

| Funktion | CLI/Modul (Beispiel) | Ausgaben |
|---|---|---|
| identische Kandidatensuite | scripts/paper_a/run_formulation_suite.jl | pro G0/G1/G2/G3/M1/M2/BASE und zulässigen M0/E2-Fällen Run-, Solver- und Solution-Manifeste; unsupported/infeasible ausdrücklich |
| unabhängige Netzrekonstruktion | scripts/paper_a/reconstruct_strength_matrices.jl | physische Y/L/B0/B/S/M Matrix-/Hash- und Residuen-Dateien |
| umfassende Metriken | scripts/paper_a/evaluate_strength_metrics.jl | long-form metrics.csv/json, Metrik-/Domain-Register, Bus/Region/Edge/Snapshot |
| unabhängige Zertifikate | scripts/paper_a/verify_certificates.jl | PSD/G3/SOC/G1/G2/M0/M1/M2/Domain- und Gegenbeispiel-Prädikate mit Residuen |
| Konservativitätsvergleich | scripts/paper_a/compare_formulations.jl | vergleichbare Scopes, Costs, Objective Gaps, Feasible Set Membership, False Reject, Spatial Differenzen |
| ökonomischer Recheck | scripts/paper_a/assess_planning_results.jl | CAPEX/OPEX/Event-/SOC-/Kapazitätsledger und regionale Investition |
| Solver-/Skalierungstest | scripts/paper_a/benchmark_conic_scaling.jl | Runtime, cones, variables, memory, gap, solver capabilities |
| Evidenzexport | scripts/paper_a/export_paper_a_evidence.jl | maschinenlesbarer Evidence Index, prüfbare Tabellen/Plots aus tatsächlichen Resultaten |

**Independence:** Nicht einfach die Werte der JuMP-Constraints oder Solver-Slacks zurückkopieren. Die Skripte müssen aus ursprünglichen physikalischen AP1-Parametern, tatsächlich gelösten Blockentscheidungen und einem unabhängigen Matrix-/LinearAlgebra-Algorithmus rechnen. Skripte lesen Roh-Solutions/Manifeste und funktionieren mit parametrischen synthetischen Tests ohne empirischen Datengate-Bypass.

Bei Abbruch/fehlendem Conic-Solver: status `not_supported`/`not_executed`, null-Metriken und Grund; keine falsche Zahl. CLI argumentiert relativ zu einem expliziten Repository-/Input-/Outputroot; keine hartcodierten privaten Pfade. Stabile Datenschemata, CSV/JSON-Parse-Tests und Konsistenz-Hashes sind Teil der Regression.

## 5. Datenverträge, Gates und Repository-Artefakte

Jeder Metrik-Datensatz enthält: `run_id,case_id,dataset_kind,parameter_registry_sha256,AP1_SHA,AP2_SHA,AP3_SHA,science_SHA,formulation_id,exposure_variant,snapshot_id,scenario_id,region_or_edge,metric_id,value_or_null,unit,base,validity_status,domain_predicates,equation_reference,independent_method,tolerance,residual,solver_status`.

Jeder Solver-Run enthält: Case-/Manifest-/Config-/Quellenhashes; installierte/running Blockanzahlen; identische alpha, G2-r, M2-W, M1 Bmin, ggf. E2-Baseline/Trust-Region; native und gemeinsame MVA-Basis; Kosten- und Repräsentativitätsgewichte; Julia/Pkg/Manifest und Solver MOI/Gap/Time; primal/dual/infeasibility evidence.

Zu produzieren:
- docs/paper_a/ap3_formulation_candidate_registry.md — Formulierung, Theorem, Scope, Implementierungsweg und Ergebnis pro Kandidat;
- docs/paper_a/ap3_evaluation_metric_registry.md — vollständige Gleichungs-/Unit-/Domain-/Postprocess-Zuordnung;
- reports/paper_a_ap3_status.yaml, reports/paper_a_ap3_validation.md mit separaten Gate-Feldern pro Kandidat/Metrik/Script;
- reports/ap3_runs/<run_id>/ mit manifests/solutions/matrices/metrics/certificates/comparisons/benchmarks/plots;
- docs/paper_a/ap3_to_a3_5_handoff.md — zwingender unabhängiger Reviewer-Handoff.

Gates separat: `formulation_G0/G1/G2/G3/M0/M1/M2/E2_status`, `domain_predicates_P001_to_P010`, `postprocessing_all_metrics_implemented`, `postprocessing_cli_executable`, `independent_matrix_reconstruction_valid`, `g0_g3_exactness_valid`, `solver_conic_capability`, `integer_optimum_certified`, `parametric_study_ready`, `empirical_data_valid`, `A3_closed=false`, `AP4_ready=false` bis unabhängiger Abschluss.

## 6. Verpflichtende mathematische und End-to-End-Tests

- Alle relevanten eingefrorenen analytischen Gegenbeispiele: G0 nicht⇒M0, local nicht⇒G0, G1/G2-Unvergleichbarkeit in beiden Richtungen, G3/G0 singulär/reduzibel/isolierte Nullzeile, singuläre Exposure-/generalized-Schur Range-Bedingung, falscher E2/Taylor-„Safety“-Claim.
- G3 jede strukturelle Kante einmal, zwei gerichtete q, sqrt(2)-RSOC, signed m_ij, nonnegative Diagonalrest, exakter Rekonstruktionsfehler, unsupported nicht-Z Input. Cross-solve G0/G3 gleiche Ziele im gleichen zulässigen Matrixscope; MIP-/SDP-/SOC-Solvergap tatsächlich qualifiziert.
- M1 Min-Source tatsächlich enforced, inverse upper-order; M2 W>=0, diag 1 und echte full/sparse Vergleichsfälle; G2 offline-fixiertes positives r und keine post-optimization Auswahl.
- Alle Metriken mit 2-/3-Bus handberechenbaren Fällen, p_i=0, S=0, B singular, alpha=0, inverse nichtpositiv, Inseln, Konditionsproblemen und Kanten/regionen-Sortierung.
- CLI-Schema-, JSON/CSV-, Hash-, Seed- und Summenprüfung; fehlende Dateien und Solverunsupported Fail-Closed; keine Null-für-Missing-Fallbacks.
- Nach Quellcodeänderungen vollständige AP2-/historische Regression einschließlich der bekannten 3 synthetischen Producer-LP-OPTIMAL und 3 Integer-INFEASIBLE Fälle. Keine Freigabe realer Studien ohne Strang-B-Evidenz.

## 7. Autonomie, Machbarkeit und Scope-Grenzen

Der Implementierungsworker darf Solver (z.B. bestätigten kontinuierlichen SDP/SOCP, einen verfügbaren MISOCP oder kleine vollständige Enumeration), Dateiarchitektur, Auswertungs-CLI, konkrete r-/W-Studienkonfigurationen, gruppierte Tests, Referenzfälle und nötige kleine AP2-Integration autonom bestimmen.

Die Ausführung sollte **in einem zusammenhängenden Makroauftrag** iterative Korrekturen, Optimierungs-/Diagnosecode und alle Skripte umfassen. Ein fehlender MISDP-Solver darf nicht zum Löschen von G0, G2, M1 oder der Postprocessing-Diagnostik führen; begrenzte Capability-Gates sind zulässig, müssen aber explizit berichtet werden. Ein wissenschaftlich unbewiesenes M0-NLP oder E2-Safety-Zertifikat darf ebenfalls nicht als bestanden etikettiert werden.

**Definition of Done:** Jeder sinnvolle Kandidat aus dem vollständig inventarisierten Quellenkorpus hat einen tatsächlichen Implementierungstyp, eindeutigen Source-/Test-/Scriptpfad und maschinenlesbaren Gate-Status. **Jede definierte Paper-A-Metrik** hat eine ausführbare, unabhängig validierte Berechnung und wird für alle mathematisch zulässigen gelösten Fälle reportiert. Die Auswertung kann selbstständig auf neue Inputfälle angewendet werden, ohne Formeln manuell in Berichte zu kopieren. Die historischen mathematischen und AP1/AP2-Resultate bleiben nachvollziehbar, aber A3/AP4 und reale empirische Gültigkeit werden nicht vorweggenommen.

**Das ist eine ausführliche AP3-Implementierungsvorgabe, keine Behauptung einer bereits erfolgten AP3-Code-/Solverausführung.**
