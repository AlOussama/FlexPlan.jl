---
document_type: paper_a_ap3_implementation_and_acceptance_contract
date: 2026-10-20
status: documented_ready_for_autonomous_worker_not_executed
implementation_baseline: e992edc88d39fa0eb2d72e2490e157441223f568
ap3_documentation_source: 8180afb3ea482e66a8c114db9b7fb4a90b1d3325
producer_numeric_anchor: 3b8fdb01d931225edc5f8fe1e2c200d0da288a09
paper_scientific_freeze: 672a61c95525bf1d7a03cf745a754a15a23ce78b
scoped_parametric_inputs_ready: true
ap3_formulations_executed: false
empirical_data_valid: false
A3_closed: false
AP4_ready: false
---

# Paper A — AP3 Autonomous Implementation and Acceptance Contract

**Dieses Dokument ist eine ausführbare Implementation-/Abnahme-Spezifikation, kein behauptetes AP3-Implementierungsergebnis.** AP3 übernimmt auf einer zukünftigen *eigenen* Implementierungsbranch aus einem geprüften Consumer-Code-Stand die exakten regionalen G0-/G3-Modelle **und** die bereits vom Owner für den technischen AP3-Umfang erweiterte Formulierungsfamilie, alle Vergleichsmetriken und unabhängiges Postprocessing. Keine getrennten Mikrotask-Branches, keine Umgestaltung von AP1/AP2.

## 0. Wissenschaftliche Priorität, verwendbare Daten und Quellenhierarchie

1. **Mathematisch autoritativ:** vollständige C2A-Dissertation v3 auf `research-map/main@e8118425adc335a99e85120d943763305f211315`, Theoreme und Gegenbeispiele des wissenschaftlichen Mathematik-Freeze `2c2fce769b2ed6ffd4f1ced60c0798776acccc93`; Paper-A-Auswahl/Definitionen am eingefrorenen `paper/c2a-system-strength-expansion-planning-v1@672a61c95525bf1d7a03cf745a754a15a23ce78b` und A2F-Traceability.
2. **AP3-A0 Mathematik bereits dokumentiert, jetzt in dieser Doku-Branch bytegleich übernommen:** [ap3_a0_full_mathematics_gap_analysis.md](ap3_a0_full_mathematics_gap_analysis.md). Die historische Aussagen darin zu Strang-B-Ausführungsstand gelten nur für seinen Schreibzeitpunkt.
3. **AP3 Owner Scope erweitert:** [ap3_a0_comprehensive_formulations_metrics_postprocessing_scope.md](ap3_a0_comprehensive_formulations_metrics_postprocessing_scope.md) — spätere verpflichtende technische Vorgabe, supersediert ältere **engere Implementierungs**-Scope-Abschnitte in A0, nicht die eingefrorenen Beweise oder Paper-Claims. **G2, M1, M2, E2/WN, LOCAL sowie alle unabhängigen Postprocessing-Metriken/Skripte sind nicht mehr beiläufig optional.**
4. **Aktuell verwendbare Code- und Eingabebasis:** `FlexPlan.jl/integration/paper-a-parameter-qualification-v1@e992edc88d39fa0eb2d72e2490e157441223f568`; `PyPSA2MatpowerX/implementation/paper-a-ap1-data-contract-v1@b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c`; numerische Dateien unveränderlich aus Producer `3b8fdb01d931225edc5f8fe1e2c200d0da288a09`.
5. **Wissenschaftlicher konsolidierter AP3-A0-Handoff:** `research-map/docs/paper-a-ap3-a0-consolidation-2026-10-20`, `docs/reports/C2_constraints/C2A_voltage_stability/paper_a/implementation_audit/2026-10-20__paper-a-ap3-a0-consolidated-freeze-and-equation-to-code-gap.md`; Owner/Gate-Ledger im `traceability`-Teil derselben Branch. Eine neue Aufgabe benutzt diese aktuellen Cross-Repo-SHAs statt nur die alte AP2-Basis `725de2e...`.

**Parameter Qualification Annex:** `paper_a_strang_b_v1` / `paper_a_parameter_qualification/1.0`, Register-Bytehash `a249f7a96d202798c6ff5778c1fa1571eba59a3717bac5d25b150d2a6c41bce9`, Szenario-Bytehash `be9d9d9aa90e9790fc7c3554bc1107777a5ba743f4f95d8f675acd9bfeb1e75a`. Aktuelle Strang-B-Evidenz: 8739 Zeilen, 9 Szenarien, 9 optimierte MILPs + 9 LPs, 291/291 zusätzliche Consumer- und 54/54 Netzprüfungen, 5987/5987 Regression, 153/153 AP2. Diese Zahlen sind **historische Testergebnisse**, keine AP3-Prüfung. `parametric_case_ready=true`, `ap3_input_contract_ready=true` gelten **nur für den registrierten parametrischen Scope**, `empirical_study_ready=false`, `theorem_domain_valid=false` für empirische Evidenz. B/S/M-Mathematik darf unabhängig auf synthetischen exakten Domänen geprüft werden.

## 1. Bestehende AP2-Pfade unverändert weiterverwenden

| Semantik | Realer Source-Pfad und Funktion | AP3 verwendet |
|---|---|---|
| physisches AC-Y/L, passive Schur B0, Inseln | `src/core/paper_a_regional.jl:network_reference`, `reduced_strength`; `src/core/ref_extension.jl:ref_add_uc_gscr_block!` | `ref[:paper_a_regional]`: stable region order, `Y,L,B0,b_fix,islands,S_base_MVA`, Domain-/Residual-Felder |
| Quelle/Sbase/x/MVA und Fixed-vs-online | `src/core/paper_a_regional.jl:validate_source`, `source_b_block` | Keine neue Quelle vor Schur, keine doppelte Quellstärke; `SYN != converter GFM` |
| Gerätedaten, feste μ, Exposition | `src/core/paper_a_integration.jl:_paper_a_add_reference!` | `ref[:paper_a_coefficients]` über kollisionsfreie Compound-Keys `(table,id)` mit `(region,strength,exposure)` |
| identische online-Matrixausdrücke | `src/core/paper_a_integration.jl:_paper_a_online_expressions!` | `pm.ext[:paper_a_online][nw]` mit `regions,b_src,p_fl,S_diag,B,M`; **zentrale Single Source for Optimization** |
| vorhandenes G1 | `src/core/paper_a_integration.jl:_paper_a_g1!` | als unveränderte Vergleichsbaseline; neue unabhängige Zeilenslack-Rechnung |
| Formulierungs-Dispatch | `src/core/block_template.jl:AbstractGSCRFormulation`, `NoGSCR`, `GershgorinGSCR`, `UCGSCRBlockTemplate`, `_validate_uc_gscr_block_gscr_formulation_supported` | neue explizite Formulierungstypen und Capability-Gates, **niemals** unregistrierte automatische G1-Fallbacks |
| integrierter Builder | `src/prob/uc_gscr_block_integration.jl:build_uc_gscr_block_integration` | bestehende n/na, UC/SOC, Operation/Pricing sowie aktiver/überregionaler Leistungsfluss |
| Kosten und Gewichte | `src/core/objective.jl`, `src/core/paper_a_integration.jl:scale_paper_a_costs!` | **identische** Anlage-/Betriebs-/Event-Zielfunktion für exakte Formulierungsvergleiche |
| Strang-B-Registrierung | `src/core/paper_a_qualification.jl:register_paper_a_parameters!`, `_paper_a_validate_registered!` | parametric_study explizit, Hash/Scenario Scope fail-closed; empirisches `unverified` nicht fälschlich hochstufen |
| bestehende Prüfungen | `test/run_paper_a_ap2.jl`, `test/run_paper_a_ap1_acceptance.jl`, `test/run_paper_a_parameter_acceptance.jl`, `test/run_paper_a_parameter_network_audit.jl` | unverändert erhalten; neue gezielte AP3-Suites additiv |

Der AP3-Worker hat alle Änderungen am Consumer-HEAD seit dieser Dokumentation zu prüfen, bevor er einen neuen Implementierungsbranch erstellt. **Keinen Doku-Branch zu einer numerischen Produktionsbranch erklären**; die Dokumente werden anhand exakter SHAs gelesen, der Ausgangscode bleibt der neu geprüfte AP2+Strang-B-Stand. Falls Concurrent-Branches fortgeschritten sind, nur verifizierte sinnvolle Änderungen selektiv übernehmen.

## 2. Verbindliche Mathematik und Zuverlässigkeitsbedingungen

### 2.1 Feste Netzwerk-/Planungssemantik

Für retained r und passive eliminated e:

\[
L=-\Im(Y^{(+)}),\quad B^0=L_{rr}-L_{re}L_{ee}^{-1}L_{er},\quad
B_t=B^0+\mathrm{diag}(b_t^{src}),\quad
S_t=\mathrm{diag}(p_t^{fl}),\quad M_t(\alpha)=B_t-\alpha S_t.
\]

Quelle und Exposure sind affines Abbild aus AP2-Onlineblöcken, feste \(\mu\), gemeinsame Sbase. Source-Stamps nach passiver Reduktion. \(S_t\succeq0\) darf singulär sein, auch \(S=0\). Ein operationales DC-Powerflow-B ist kein positives-Sequenz-Stärkemodell. Gültigkeitsvoraussetzungen statisch und nach einem Solve neu prüfen; kein `sqrt(abs(...))` oder stilles Symmetrisieren.

### 2.2 Zu implementierende Kandidaten (gemäß späterem Owner-Code-Scope)

| Kandidat | Wählbare Optimierung / Pflichtdiagnostik | mathematisches Kern-Gate |
|---|---|---|
| `BASE/NoGSCR` | vorhandenen Solve und unabhängige Baseline-Metriken | kein übernommener PSD-Nebenconstraint |
| `G0` | Vollmatrix-\(M_t\succeq0\) als echter PSD/MOI/JuMP-Kegel; kontinuierlicher SDP Benchmark; kleine Integer-G0 via nachweislich unterstütztes MISDP oder vollständige diskrete Enumeration | affine B/S/M, fixed alpha, voller Loewner-Kegel; eigene \(\lambda_{\min}(M)\)-Prüfung |
| `G1` | bestehende Gershgorin-Formulierung beibehalten; unabhängige `M*ones`-Slacks | suffizient bei symmetrischem Z; konservativ |
| `G2(r)` | \(M_tr\ge0\), **festes** \(r>0\) aus vorab deklarierter Strategie, mehrere r-Varianten | suffizient; G1/G2 kein universelles Ranking; variable r in gleichem Solve generell bilinear |
| `G3` | Für jedes vollständige und signierte ungerichtete Edge `i<j`: `qij>=0`,`qji>=0`; \([qij,qji,\sqrt2\,m_{ij}]\in\mathcal Q_r^3\); \(m_{ii}-\sum_{j\sim i}q_{ij}\ge0\) | **G0⇔G3 für symmetrische Z-Matrizen inkl. singulär/reduzibel/isoliert; G3⇒G0 auch allgemein; kein exaktes G3 außerhalb dieser Domäne behaupten** |
| `M0` | \(y=B_t\backslash p_t^{fl}\) als exakte M0-/MSCR-Post-Solve-Metrik; kleiner separater nichtkonvexer/diskret-enumerierter Enforcement-Test, sofern global belegbar | \(B_t\succ0\), nonsingular M class/inverse positivity, \(\alpha>0\). **G0⇒M0 ist falsch** |
| `M1` | `Bmin = B0+diag(bmin)`, `Zub = Bmin^{-1}`, lineares \(Z^{ub}p\le\alpha^{-1}\mathbf1\) **plus tatsächlich erzwungene** \(b_t^{src}\ge b^{min}\) | Bmin SPD-M, \(B_t^{-1}\le(B^{min})^{-1}\) entrywise, p≥0 |
| `M2` | \(B_t\mathbf1\ge\alpha Wp_t^{fl}\) bzw \(M_t\mathbf1\ge\alpha(W-I)p\) mit **vorab festem** \(W\ge0,W_{ii}=1\); full/neighbor-sparse W | gSCR-Zertifikat \(M2⇒G1⇒G0\), **kein automatisches M0**; externes MIIF-Kriterium getrennt |
| `E2/WN` | exakte Woodbury-Inverse-Updates, Neumann-Trunkation, Taylor-Approx und Trust-Region-/Restglied-Prüfung als **ausführbare Diagnostik**; bedingt zulässige einseitig abgesicherte MILP nur bei bewiesener Fehlergrenze | Normfehler-/Konvergenzradius nicht mit komponentenweiser Safety verwechseln; ohne Gate `non_certifying_research` |
| `LOCAL` | lokale Thevenin-Short-Circuit-/ESCR-/MSCR-/MIIF-/rank-one-Metriken und ausdrücklich getrennte `S_nom,S_on,S_op,S_I`-Exposurevarianten | Denominator/Zeitskala/Basis/Quelle klären; fehlende Werte als `undefined`/`not_comparable` |

### 2.3 G3 exactness, Matrix-Rand und numerischer Beweis

Zugelassene Matrix für exakte Äquivalenz: reell, symmetrisch, \(m_{ij}\le0\) für \(i\ne j\). Ein vollständiger fester Graph über **alle** strukturell nichtverschwindenden Offdiagonalen. \(Q_{ij}=\begin{bmatrix}q_{ij}&m_{ij}\\m_{ij}&q_{ji}\end{bmatrix}\succeq0\) kann durch MOI rotated SOC \([q_{ij},q_{ji},\sqrt2 m_{ij}]\in\mathcal Q_r^3\) umgesetzt werden (MOI: \(2uv\ge\|w\|^2\)); alternativ standard SOC \(\|[2m_{ij},q_{ij}-q_{ji}]\|_2\le q_{ij}+q_{ji}\). **Falsches \(\sqrt2\)**, gerichtete Doppelzählung, Teilgraph, Symmetrisierung oder erzwungene q>ε verfälschen G3. Für isolierte Knoten lediglich \(m_{ii}\ge0\) und selbst singularer Zero-Row-Block ist erlaubt.

Beweisseitig `G3⇒G0`: Summe aller eingebetteten signierten \(Q_{ij}\) plus nichtnegative diagonal-remainder PSD-Matrizen reproduziert exakt M. `G0⇒G3` benötigt die Z-Klasse und die geschlossene SDD/M-Matrix-Struktur; der Grenzfall singular/irreduzibel ist **kein** Zulassungshindernis. Bei verifizierter G3-Solverlösung sollen Edge-Produkt-, RSOC-, Node-Rest-, \(\|M-M_{reconstructed}\|\)- und `eigmin(M)`-Residuen separat vorliegen. Test eines PSD **nicht-Z** ohne G3-Witness muss ablehnen/unterdeklarieren.

### 2.4 Generalisierte Spektraldiagnostik bei singulärer Exposition

Für \(a=\{i:p_i^{fl}>0\}\), \(z=\{i:p_i^{fl}=0\}\) gilt für G0 im Vollraum

\[
M=\begin{bmatrix}B_{aa}-\alpha S_a&B_{az}\\B_{za}&B_{zz}\end{bmatrix}\succeq0.
\]

Falls \(B_{zz}\succ0\): standard Schur \(B_{aa}-B_{az}B_{zz}^{-1}B_{za}-\alpha S_a\succeq0\). Bei \(B_{zz}\succeq0\) singulär: **zusätzlich** Range \((I-B_{zz}B_{zz}^{\dagger})B_{za}=0\) und generalized Schur PSD mit Pseudoinverse. Bei verletzter Range ist die Vollmatrix nicht PSD, selbst wenn die Pseudoinverse formal einen akzeptablen kleineren Block liefert. \(S=0\): G0 prüft weiterhin B PSD; finite generalized Rayleigh quotient ist `undefined_no_exposure`, keine künstliche \(\varepsilon\)-Exposition. Eigenwertmetriken nie mit `eigmin(M)` verwechseln (Thresholdmargin ≠ gSCR-Eigenwert).

### 2.5 Exact MSCR/M0 und Nichtimplikationen

Nur für belegt invertierbares \(B_t\) und benötigte inverse-positive Klasse: \(Z_t=B_t^{-1}\ge0\), \(\psi_t=Z_tp_t^{fl}\), \(MSCR_{i,t}=1/\psi_{i,t}\) bei positiver \(\psi_i\). Numerisch \(B_ty=p\) als Solve und unabhängigen Residual \(\|B_ty-p\|\) statt unnötig expliziter Inverse für jeden Snapshot. Kein M0-Wert bei \(B_t\) singulär, kein fiktives +∞ bei Null-Burden. ESCR bei \(p_i>0\) und \(Z_{ii}>0\) separat. Nicht aus G0/G3-Feasibility auf M0-Sicherheit schließen; M1 ist ein eigenes zertifizierendes Envelope unter starkeren Voraussetzungen. Externes konventionelles SCR/MSCR ggf. separat benennen, nicht ohne dieselbe Quelle-/Störungszeitskala mit mathematischer M0-Definition gleichsetzen.

## 3. Solver-Architektur und numerische Akzeptanz

**Alle Solver-Capabilities an tatsächlicher Julia-/MOI-Version prüfen**; Dokumentation der APIs allein oder bloßes `Project.toml` beweist keine lauffähige Lizenz.

| Modellklasse | Mindestens zu prüfende Möglichkeit | Zulässige Evidenz |
|---|---|---|
| G1/G2/M1/M2, kontinuierlich oder mit Integer | bestehender HiGHS-Pfad | Tatsächlich LP/MILP OPTIMAL mit integer feasibility und Objective-Recheck |
| G0 kontinuierlich | MOI PSD triangle; lokal verfügbarer SDP-Solver wie SCS (tatsächlich gecheckt) | PSD-Kegelsupport, primal status, unabhängige Matrixeigenwerte, conic primal/dual residual |
| G3 kontinuierlich | MOI RotatedSecondOrderCone, SCS/Clarabel oder anderer **geprüfter** SOCP-Solver | RSOC-/Node-Reconstruction und gleiche Feasible-Set-/Objective-Grenze wie G0 |
| G3 integer | ein nachweisbar funktionierender MISOCP-Solver oder für kleinen bounded Fall vollständige Integerenumeration + SOCP | zertifizierte echte integer Lösung/Gap; LP relax ≠ MISOCP optimum |
| G0 integer | tatsächlich unterstützte MISDP-Methode oder vollständige diskrete Enumeration + SDP | mathematisch dokumentiertes globales Resultat für endliche kleine Kandidaten |
| M0 direkte Modellierung | kleiner konvex/nichtkonvex korrekt gegrenzter Spezialbenchmark wenn möglich | sonst `solver_not_supported`, exakte unabhängige Post-Solve-Diagnostik trotzdem Pflicht |
| E2/WN | nicht zertifizierend, es sei denn einseitiges Trust-Region-/Restglied-Gate bewiesen | Norm-/Remainder- und Sicherheitscheck getrennt |

HiGHS ist kein PSD/SOCP-Solver; Gurobi-Präsenz in Project.toml garantiert keine funktionierende Lizenz/PSD-Fähigkeit. SCS/Clarabel/Gurobi/Mosek/Pajarito sind **Kandidaten**, keine hier schon ausgeführten Qualifikationen. Experimentelle G0/G3/MISOCP-Äquivalenz ist nur mit denselben Cases, Kosten, alpha, Source-Parametern und tatsächlich erreichten Accuracy-/MIP-Gaps interpretierbar. Bloße Portfolio-Gleichheit nicht fordern, falls alternative Optima bestehen.

## 4. Unabhängiges Postprocessing: komplette Metric Registry und CLI

Pflicht: numerisches Postprocessing **unabhängig von constraint-Slacks** aus ursprünglichem physischen AP1-Case, ausgewählter Quelle, tatsächlich gelösten installed/online-Blöcken und sauberen linearen Solves neu rechnen. Jede Metrik erhält `metric_id`, Formel/ID/Theorem, Einheit/Basis, Region/Edge/Snapshot/Scenario, Domain/Gate, Toleranz und unabhängigen Residual; Status mindestens `valid | undefined | not_applicable | blocked_missing_data | domain_invalid | solver_inconclusive | not_executed`. Kein willkürliches NaN, +∞ oder Null als fehlende Messung.

### 4.1 Vollständige Metrikfamilien

| Gruppe / beispielhafte stabile IDs | Pflichtumfang | unabhängig zu validieren |
|---|---|---|
| `NET-*`, `SRC-*`, `EXP-*` | physisches Y(+), L, passive B0, b_fix und gelöste b_src, B/S/M, common-Sbase, native source x/Sblk, μ, Source-/Grid-/GFL-Taxonomie; Insel-/Grounding-/SYN-/GFM-/GFL-Inzidenz | B0/Schur/Source/Exposure/B/S/M-Reconstruction, offdiag-Symmetrie-/Matrixklasse, a_conn/a_res |
| `SPEC-*`, `G0-*`, `G1-*`, `G2-*`, `G3-*` | min eig(M), eigen-inertia, nullity, finite generalized gamma, critical mode, \(\gamma-\alpha\), G1/G2 row slacks, G3 q products/RSOC/node slacks/complete signed-edge reconstruction | PSD vs generalized eigen gesondert; full-space vs positive-exposure Schur; false rejection |
| `IMP-*`, `MSCR-*`, `ESCR-*`, `M0-*`, `M1-*`, `M2-*` | invertible B, `Zii`, inverse-positive check, y=B\p, \(\psi\), local diagonal ratio, finite MSCR, MIIF full/sparse, M1 Zub/Bmin, M2 Wp | edge/region ordering, \(By-p\), inverse order, `W≥0 diag=1`, denominator-gates |
| `INVUP-*`, `NEUMANN-*`, `E2-*` | Woodbury update, spectral radius/induced norm, finite truncation error, Neumann bound, Taylor linearization/trust region, false-safe and false-reject classification | remainder actual vs upper bound, separate componentwise certificate |
| `PLAN-*`, `COST-*`, `OPS-*`, `STORAGE-*` | n0/ninst/nonline, MW/MVA/MWh, GFM/SYN/GFL/SC class, CAPEX/FOM/P+E, running/event OPEX, cost-scaling, p/q balance, SOC/terminal, duration vs repetitions | independent objective identity, power balance and energy evolution |
| `CMP-*`, `PERF-*` | cost/portfolio/binding comparisons, G0/G3 cross-feasibility, G1/G2 conservatism, false rejects, strength/exposure incidence, CPU/compile/memory/model-size/solver-gap | compare identical cases/weights and valid statuses; unsupported runs not ranked |

### 4.2 Mindestens acht tatsächlich ausführbare logische CLI-Funktionen (dateinamen flexibel)

1. `run_formulation_suite`: BASE/G0/G1/G2/G3/M1/M2 und zulässige M0/E2-Referenzläufe.
2. `reconstruct_strength_matrices`: unabhängig Y+/L/B0/B/S/M und hash/verifizierte Koeffizienten.
3. `evaluate_strength_metrics`: Metric Registry/CSV+JSON mit exakten Nenner-/Exposure-/S-domain-Status.
4. `verify_certificates`: PSD, Zeilensummen, G3, M0/M1/M2, Matrixprädikate, Gegenbeispiele.
5. `compare_formulations`: identische Studienfälle, G0/G3 exakte Benchmarks vs hinreichende, kontextspezifische konservative Ablehnungen.
6. `assess_planning_results`: Investitionen, technologie-/regionale Entscheidungen, CAPEX/OPEX/Event/Curtailment, Speicher-/Balance-Residuen.
7. `benchmark_conic_scaling`: Modell-/Kegeldimensionen, Solver-Capability, Gap, Zeit/Memory, Nachrechnungen.
8. `export_paper_a_evidence`: stabile maschinenlesbare Manifeste, Prüf-IDs, Tabellen/Plots nur aus tatsächlichen Ergebnissen.

Eine CLI mit Subcommands ist zulässig. Jeder Skripteingang besitzt dokumentierte relativen Roots (keine privaten absoluten Pfade), Input-/Case-/Registry-/Scenario-/Source-/AP1-/AP2-/AP3-/Science-SHAs, Solverstatus und deterministisches Schema. Regressionen müssen ihre CLI-Argumente, JSON/CSV-Parser und Missing-/Domain-Verhalten testen. Wenn wegen Solver-Mangel eine Funktion nicht ausführbar ist, explizit `not_supported/not_executed`, statt „grün“.

## 5. Verbindlicher Test- und Abnahmekatalog

Tests zuerst als mathematisch handprüfbare **rationale** Zeugen erstellen; random/property tests zusätzlich, nicht anstelle davon. Keine tatsächlichen Julia- oder Conic-Test-PASS aus diesem Dokument ableiten.

| Test | Wahrheitswert und Abnahmepunkt |
|---|---|
| `MATH-01` | B=[[1,-1/2],[-1/2,1]], p=(1/4,2/3), alpha=1; M=[[3/4,-1/2],[-1/2,1/3]], eig=(0,13/12); G0 true/G3 q=(3/4,1/3) true/G1 false/M0 psi=(7/9,19/18) false |
| `MATH-02` | B gleich, p=(3/4,3/4), lokaler Diagonaltest trotz G0 eigmin=-1/4 nicht global gültig |
| `MATH-03` / `MATH-04` | r=(2,1), feste symmetrische Z-Matrizen belegen jeweils G1 true/G2 false und G2 true/G1 false |
| `MATH-05` | Singularer Laplace-Block [[1,-1],[-1,1]]: G0⇔G3 true, `M0` inverse undefined; zusätzlich isolierter Nullknoten |
| `MATH-06` | PSD nicht-Z: 3×3 all-ones, nicht alle PSD durch SDD-Edgebudget darstellbar |
| `MATH-07` | Pseudoinverse ohne Range-Check auf singulärem Schurblock erzeugt falsch positiven PSD-Test |
| `MATH-08` / `MATH-09` | S=diag(1,0), S=0, singuläres Bzz und reducible islands: finite generalized eigen status, full-space PSD, G3 boundary |
| `MATH-10` | 2/3-Bus Y, passive Schur, x_native/Sbase≠100, μ≠1, connected GFL with `a_res=0`, independent SYN/GFM |
| `MATH-11` | fixed-Z-M1 unter tatsächlich enforced bmin, inverse-order and energy/exposure nonnegativity |
| `MATH-12` | W full/sparse M2; test `M2⇒G1⇒G0`, *not* `M2⇒M0`; G2 predetermined r>0 |
| `MATH-13` | Woodbury/Neumann finite-order and trust-region negative/positive tests, Remainder vs bound |
| `SOLV-01` | identischer kontinuierlicher Referenzfall G0 SDP und G3 SOCP: vollständig übereinstimmende exakte zulässige Mengen im Z-Scope; Objective agreement bis nachgewiesene Toleranzen |
| `SOLV-02` | kleines *ganzzahliges* positives GFM/SYN-Investment: zertifiziertes MISOCP oder vollständige enumeration, mit LP vs integer status getrennt |
| `SOLV-03` | G1 vs G0/G3 mit nachweislicher Überkonservativität, einschließlich 200-MW-BESS-GFM-Referenz nur als parametrisch ausgewiesen |
| `REG-01` | alle bisherigen AP1/2/Strang-B-Testpfade beibehalten; 9 MILP und 9 LP Erfolg; alte 3 Producer-Integer-INFEASIBLE **bleiben** negative Regression |

Kegelnumerik: symmetrische `eigmin`-Abweichungen, Max-Schur-Residual, RSOC-Produkt/Norm, Node-Budget, Edge-Rekonstruktion, `B*y-p` und Kostensummen **mit festgelegten absoluten und relativen Toleranzen**; Solver-MIP-Gap, time limit, primal/dual feasible je nach Backend dokumentieren. Nicht jedes Modell muss integer-lösbar sein: Ein mathematisch inkonsistenter realer Datensatz bleibt blocked, negative Testfälle werden nicht durch physikalische Lockerung „repariert“. Mögliche Z-/M-Matrix-Defekte sind wissenschaftliche Evidenz, kein Anlass zur stillen Matrixsymmetrisierung.

## 6. Evidence and Gate Contract (maschinenlesbar umsetzen)

Jeder `run_id` erfasst mindestens:

```yaml
run_id: explicit_stable_id
scenario_id: pinned
dataset_kind: qualified_parametric_or_synthetic_regression
parameter_registry_id: paper_a_strang_b_v1
parameter_registry_sha256: a249f7a96d202798c6ff5778c1fa1571eba59a3717bac5d25b150d2a6c41bce9
scenario_config_sha256: be9d9d9aa90e9790fc7c3554bc1107777a5ba743f4f95d8f675acd9bfeb1e75a
producer_code_sha: actual
consumer_code_sha: actual
ap3_code_sha: actual
science_sha: 672a61c95525bf1d7a03cf745a754a15a23ce78b
formulation_id: G0_or_G1_or_G2_or_G3_or_M0_or_M1_or_M2_or_E2_or_BASE
exposure_variant: online_nameplate
model_domain_predicates: independent_P001_to_P010
solver_moi_support: checked_or_not_supported
solver_result: OPTIMAL_or_INFEASIBLE_or_UNKNOWN_or_NOT_EXECUTED
integer_certificate: exact_or_gap_qualified_or_not_applicable_or_unavailable
independent_metric_status: valid_or_domain_invalid_or_undefined_or_not_executed
empirical_data_valid: false
A3_closed: false
AP4_ready: false
```

Jede Metrikzeile hat stabile ID, `unit/base`, Region/Kante/Snapshot, `value_or_null`, `equation_reference`, `independent_algorithm`, `tolerance`, `residual`, `solver_status`, `domain_status`. Keine bloß kosmetische `status=PASS`-Auszeichnung ohne tatsächlich ausgeführte API/CLI-/Solverprüfung.

Getrennte maschinenlesbare Gates:
`formulation_G0/G1/G2/G3/M0/M1/M2/E2_status`, `predicates_P001-P010`, `g0_g3_exactness_valid`, `generalized_singular_exposure_handling`, `m0_exact_postprocessing`, `m1_fixed_z_valid`, `m2_miif_valid`, `e2_certification_scope`, `postprocessing_all_metrics_implemented`, `postprocessing_cli_executable`, `independent_matrix_reconstruction_valid`, `solver_conic_capability`, `integer_optimum_certified`, `parametric_study_ready`, `empirical_study_ready`, `A3_closed`, `AP4_ready`.

## 7. Architektur, Worktrees, Branch-/Schreibschutz und autonomer Makroabschluss

- AP3-Worker liest zuerst math freeze, beide übernommenen AP3-A0-Dokumente, diesen aktualisierten Vertrag, `research-map`-Gap und Strang-B-Handoff. Vor Editieren **aktuelle Remote-SHAs fetchen**, Änderungen seit gepinnter Basis untersuchen und integrieren, keinen Branch ohne Prüfung resetten.
- **Eine** AP3-Implementierungsbranch auf geprüftem AP2+Strang-B-Code (`e992edc...` sofern noch gültig; aktuelle Integrations-/Worktree-Historien prüfen). Dokumentationsbranches bleiben reine Dokumentation. Die ursprüngliche AP2-Branch `implementation/paper-a-ap2-regional-optimization-v1` hat zusätzlich zwei AP3-A0-Dokumente bis `8180afb3...`; diese wurden **bytegleich** übernommen. Nicht die branchübergreifenden Änderungen unkontrolliert zu einem Code-Freeze zusammenmischen.
- AP1-Parameterregister ist alleinige numerische Autorität. Keine Änderungen an AP1-Daten ohne separate qualifizierte Scenario-Hash-Version; kein blindes Mock-Price-Upgrading.
- Der Worker darf Module, genaue Solverwahl, sinnvolle Leistungsoptimierungen, CLI-Architektur, Formel-Registry, numerische Testgenerierung und notwendige kleine AP2-Integration eigenständig bestimmen. **Ein zusammenhängender Makroauftrag, interne Iterationsschleifen erlaubt**, kein Aufsplitten in neue Mikro-Featurebranches.
- Triftige Stop-Condition nur bei Konflikt mit frozen mathematical truth, Verlust fremder Git-Arbeit, Lizenz/Datenrechte-Problem oder einer neu zu treffenden wissenschaftlichen Owner-Entscheidung. Selbst dann alle übrigen unabhängigen Teilaufgaben abschließen und die verbleibenden Blocker konsolidiert melden.
- Keine AP3-Implementierung im Research-map-Freeze; keine AP4-Datengenerierung, kein globaler A3-Closure. Kein Force-Push, Branch-Löschen, automatischer PR/Merge nach main/master. Ein unabhängiger A3.5-Auditor ist später erforderlich.

## 8. Definition of Done und veröffentlichbare Nachweise

**`AP3_completed` für den vereinbarten technischen Scope** nur, wenn (a) jede Kandidatenformulierung eine tatsächliche Implementierungsklasse oder korrekt begründete Capability-/Domain-Blockierung besitzt; (b) alle zulässigen Metriken mit unabhängigen **ausführbaren** Skripten korrekt berechnet werden; (c) G0/G3 unter kompletter Z-Domäne inklusive Singular-/Isolationsrand rekonstruiert, verglichen und numerisch geprüft sind; (d) M0/M1/M2 und bedingte inverse Approx korrekt getrennt sind; (e) mindestens Continuous-Conic- und kleiner Integer-Referenzpfad tatsächlich läuft; (f) vollständige bisherige Regression und Strang-B-Datenintegrität erhalten bleiben; (g) machine-readable Status, Run-/Result-/Case-Hashes, Source-/Metrik-/Testzuordnung und ein **unabhängiger A3.5-Handoff** erstellt werden.

Wenn Solver-/Lizenzen/empirische Daten die vollständige Umsetzung verhindern, ist eine überprüfbare **`AP3_partial`** mit genau benannten Fähigkeiten und unerfüllten Gates zulässig; keine fiktive ganzzahlige Exaktheit, Kostenfreigabe oder externe Empirie behaupten. **A3-Abschluss und AP4-Freigabe gehören nicht zum AP3-Implementierungsworker.**

## 9. Dokumentations- und Review-Abnahme

Diese Doku-Branch ändert **ausschließlich** Markdown/YAML. Sie hat historische AP3-A0-Dokumente unverändert übernommen und den Strang-B-Consumer/Science-Stand ergänzt. Es gibt keine neuen Test- oder Solver-Resultate durch die Dokumentationsphase. Review der Genauigkeit erfolgt anhand der gepinnten Quellstände; endgültiger mathematischer/Software-Abschluss erst anhand der vom späteren Worker erzeugten Ausführungsevidenz.

Für die AP3-Ausführung ist dies der zentrale technische Vertrag; der [erweiterte Owner-Scope](ap3_a0_comprehensive_formulations_metrics_postprocessing_scope.md) bestimmt den verbindlichen Arbeitsumfang, die [Mathematik-first-Gap-Analyse](ap3_a0_full_mathematics_gap_analysis.md) ergänzt ausführliche Beweis-/Prädikatdetails, der `research-map`-Freeze stellt den wissenschaftlichen stabilen Bezug her.
