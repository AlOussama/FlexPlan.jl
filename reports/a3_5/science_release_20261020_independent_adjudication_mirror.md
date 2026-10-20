# Paper A — A3.5-SCIENCE scientific judgment mirror in FlexPlan.jl

**Classification:** non-normative, complete archival mirror of a scientific peer-review verdict. The single authoritative science owner is `AlOussama/research-map`. This file DOES NOT ratify or enact a new scientific freeze, does not accept AP3 implementation, and does not authorize AP4.

- **Provenance:** [SCIENCE adjudication at immutable research-map commit](https://github.com/AlOussama/research-map/blob/5ceb19a6faf4e7c7e797a737ed5b449f9e2db609/docs/reports/C2_constraints/C2A_voltage_stability/paper_a/science_release/2026-10-20__a3-5-science-adjudication.md).
- **Exact source Git blob SHA:** `f9dd0b8d2d295d7fdaa79572411635e1851e77d4`.
- **Proposed amendment text:** [exact source at same research-map commit](https://github.com/AlOussama/research-map/blob/5ceb19a6faf4e7c7e797a737ed5b449f9e2db609/docs/reports/C2_constraints/C2A_voltage_stability/paper_a/science_release/2026-10-20__a3-5-amendment-final-proposed-text.md), Git blob `fba4802ecabade61a752833a71106a5bda4ce78f`.
- **Scientific review publication:** `research-map:review/paper-a-a3-5-science-release-v1@5ceb19a6faf4e7c7e797a737ed5b449f9e2db609`; later additive handoff documents reach `80e1f7b7553706df12bd9fc6e41462d8ec2a00c4` without changing the adjudication.
- **Original audited AP3 target:** `FlexPlan.jl@485b637cc1998a327206c5929434bd26c6f0be16`.
- **Previous A3.5-MATH review target:** `FlexPlan.jl@0574d491111677a7ac2cabff2877735171486c46` (before this additive mirror).
- **Next coordinated macroauftrag:** [A3.5-FINAL combined ratification-readiness and implementation closure](https://github.com/AlOussama/research-map/blob/80e1f7b7553706df12bd9fc6e41462d8ec2a00c4/docs/reports/C2_constraints/C2A_voltage_stability/paper_a/science_release/2026-10-20__a3-5-final-combined-macro-prompt.md).
- **Scientific review verdict:** `approve_for_owner_ratification`, NOT `owner_ratified`.
- **Gates:** `science_amendment_approved=false`, `independent_A3_5_accepted=false`, `A3_closed=false`, `AP4_ready=false`, `empirical_study_ready=false`.

## Vollständige wissenschaftliche Entscheidung — originaler Quelltext

Der folgende Abschnitt gibt den ursprünglichen Forschungsbericht **inhaltlich unverändert** wieder. Provenienz- und Statushinweise stehen ausschließlich im Vorspann dieses FlexPlan-Spiegels.

---

# A3.5-SCIENCE — unabhängige wissenschaftliche Schlussadjudikation (2026-10-20)

## Revisionsidentität und Gesamturteil
scientific_release_adjudication: **approve_for_owner_ratification**, nur für die im Schwesterartefakt vollständig präzisierte PROPOSED Amendment-Version, nicht für unverifizierte physische/Software-Domänen. Keine normative Wirkung ohne explizite Owner-Ratifizierung.

Verifiziert: research-map/main e8118425adc335a99e85120d943763305f211315; Paper-A-Branch 672a61c95525bf1d7a03cf745a754a15a23ce78b; FlexPlan.jl A3.5-MATH 0574d491111677a7ac2cabff2877735171486c46 (gegen 0c58af3147881e951e34bcdb556cb47681b08e46 fünf ahead/null behind). Mathematischer Freeze: 2c2fce769b2ed6ffd4f1ced60c0798776acccc93. Ausgang AP3: 485b637cc1998a327206c5929434bd26c6f0be16.

## Quellenumfang
Primär gelesen: (1) 2026-08-09 integriertes Dissertationskapitel, (2) 2026-08-02 Scientific Formulation Freeze, (3) 2026-07-30 adjudicated proofs/counterexamples, (4) 2026-07-30 P-C2A-001–010-Audit, (5) 2026-08-09 Paper-A Development Plan Freeze, (6) 2026-10-15 Multi-Repository Execution Freeze v2, alle auf research-map/main oben. Danach sekundär auf FlexPlan-SHA: math_closure_repository_independent_adjudication, amendment_proposal, findings.yaml, theorem_ledger.csv (T001–028), source_boundary.md, status.yaml, evidence_manifest.json, oracle_results_summary.json. Die komplette lokale mathematische Auditdatei und ein vollständiges lokales ZIP waren nicht verfügbar; 30/30 gemeldete Fälle sind keine eigene Verifikation. Eigene exakte rationale SymPy-Proben, nicht das frühere Oracle-Skript, und zweiter algebraischer Beweisweg wurden durchgeführt.

## D1–D4 Entscheidungen
| Gegenstand | Urteil | Voraussetzungen und Korrektur |
|---|---|---|
| D1 A35-NEW-001 | approve_with_precise_corrections | M0=>G0 nur B symmetrisch PD, Z=B^-1 elementweise nichtnegativ, p≥0, alpha>0; S=0 zugelassen; inverse Richtung untersagt, Originär-Neuheit nicht behaupten |
| D2 T006 | approve_with_precise_corrections | bei singulärem S: Bzz PSD, Range, generalisierter Schur; formaler endlicher Pencil-Wert allein keine G0-Aussage |
| D3 Quelle hinter Reaktanz | approve_with_precise_corrections | fester innerer Quellenphasor nur im deklarierten Zeitbereich; sonst Planungsproxy, keine echte GFM-Fault-Äquivalenz |
| D4 PSD-Schur und Planung | approve_with_precise_corrections | Lee PD bzw PSD+Range, feste Reduktion, gleiche Exposition/Basen, vollständige G3-Kanten/P008 für Äquivalenz |

Diese Korrekturen sind im FINAL PROPOSED Amendment vollständig ausformuliert, deshalb Freigabe nur zur **Owner-Ratifizierung**.

## Findings-Entscheidungen
| Finding | Status/Schwere | Fachlicher Release und spätere Prüfung |
|---|---|---|
| A35-NEW-001 | confirmed/major | approve scoped; rational PSD/Inverse-Rekonstruktion |
| A35-MATH-002 | confirmed/major | approve bounded-source clause; echte Quellengültigkeit nachzuweisen |
| A35-MATH-003 | confirmed/major | approve T006-Korrektur; Zero-Support/Range Regression |
| A35-MATH-004 | confirmed/minor | approve Ausschluss externer Fault-Metrikäquivalenz |
| A35-MATH-005 | unresolved/informational | historische T003 Quellensymbolidentität defer, nicht blocking |
| A35-MATH-006 | conditional/major | approve Schur-Domänenwarnung; kein Codefehler nachgewiesen; Falltest Lee |
| A35-MATH-007 | conditional/major | approve G3-Mathematik, P008 und native MISOCP separat unverified |
| A35-MATH-008 | confirmed/major | approve keine Übertragung neun M1-INFEASIBLE auf M0 |
| A35-MATH-009 | unresolved/major | echte Fault/Current-Limit/Quellenbase-Validierung defer, Proxy zulässig |

## Beweise/Gegenbeispiele
D1: K=alpha ZS≥0 und K1=alpha Zp≤1 ergeben rho(K)≤1. Ähnlichkeit zu alpha B^(-1/2) S B^(-1/2) PSD liefert B-alpha S PSD. Unabhängig: C=S^(1/2) Z S^(1/2)≤diag(Zp)≤alpha^-1 I via 2xixj≤xi²+xj² nach Summengewichtung. Beide auch mit pi=0, reduzierbaren Fällen und S=0.
G0 nicht M0: B=[[1,-1/2],[-1/2,1]], p=(1/4,2/3), Zp=(7/9,19/18), Eigenwerte(B-S)=(0,13/12). M0 nicht G1: B=[[2,-1],[-1,2]], p=(11/10,1/20), Zp=(3/4,2/5), erste G1-Zeile negativ, det(B-S)=151/200. Ohne inverse positivity: B=[[1,4/5],[4/5,1]], p=(1,1), Zp=(5/9,5/9), Eigenwerte(B-S)=±4/5. Eigenständig zusätzlicher Fall: B=[[3,-1],[-1,3]], p=(2,1), Zp=(7/8,5/8), B-S=[[1,-1],[-1,2]] hat Eigenwerte (3±sqrt(5))/2 >0.
D2: B=diag(2,-1), S=diag(1,0): formaler Eigenwert 2, Rayleighquotient (1,t) gleich 2-t², inf=-∞. Pseudoinversen-Schur ohne Range: [[1,1],[1,0]] besitzt Schur 1, Gesamtmatrix indefinit. D4: L=[[2,-1],[-1,-1]], Lee=-1 invertierbar und Schur 3, L aber indefinit. D3: [[b,-b],[-b,Bnet+b]] hat terminales Bnet+b bei festgehaltenem inneren E, aber Bnet nach freiem Nullstrom-Schur. G3: vollständige ungerichtete signierte 2x2-PSD Kanten plus nichtnegative Diagonalreste rekonstruieren M; auf PSD-symmetrischer Z-Klasse sichert Perron-positiver Vektor blockweise die closed-SDD-Ableitung auch singulär/reduzibel/isoliert. Für PSD Nicht-Z-Matrix 11^T (3x3) gilt die G3-Rückrichtung nicht.

## Hierarchie, Physik und Daten
Unter gemeinsamen Voraussetzungen M2=>G1=>M0=>G0<=>G3, M1=>M0=>G0 nur bei erzwungenem Bmin; G2(r)=>G3=>G0, G2(1)=G1. G0 und M0 => LOCAL; Umkehrungen falsch; beliebiges festes G2 gegenüber G1 inkomparabel. Identisches Minimierungsmodell und definierte Optima: C*_G0=C*_G3<=C*_M0<=C*_G1<=C*_M2. Keine pauschale M1/G1-Kostenordnung. Keine IEC/CIGRE/IEEE-Fault/Converterstabilitätsäquivalenz; keine Code-/Daten-/Empirieabnahme.

## Literatur
Plemmons (1977) Linear Algebra Appl 18(2) 175–188 DOI 10.1016/0024-3795(77)90073-8; Berman/Plemmons Nonnegative Matrices in the Mathematical Sciences DOI 10.1137/1.9781611971262; Ahmadi/Majumdar DSOS/SDSOS (2019) DOI 10.1137/18M118935X. Exakter externer nummerierter Satz/equation_locator_not_verified. A35-NEW-001 ist neue explizite Ledger-Verknüpfung, kein nachgewiesener originärer M-Matrix-Satz.

## Getrennte Folgegates
1 Wissenschaftsowner-Beschluss und gegebenenfalls neuer normativer research-map-SHA; 2 P-C2A-001–010 unabhängige Gleichung-zu-Code/Lee-PD/Range/Sources/Bases; 3 vollständiges G3-RSOC sqrt(2)-Edge-Rekonstruktionsoracle; 4 native G3 MISOCP-B1, Integer-Gap/Globalität; 5 124 Metriken und acht CLI-Aktionen; 6 AP1/Strang-B echte Parameter, Kosten, Repräsentativität sowie SG/GFM/SC Fault/Current-Limit-Qualifikation; 7 erst danach A4.
Gates: science_amendment_approved=false, independent_A3_5_accepted=false, A3_closed=false, AP4_ready=false, empirical_study_ready=false.
