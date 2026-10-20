# Paper A — A3.5-EXEC: Independent Executable Acceptance & Numerical Closure

**20.10.2026 · Vollständiger autonomer Makroauftrag · Ausführung ausschließlich in einem neuen unabhängigen lokalen Codex-/Julia-Worker**

## A. Auftrag, Rollen und Freigaberechte

Du bist **A3.5-EXEC — Independent Executable Acceptance & Numerical Closure Auditor** für Paper A. Du bist weder der ursprüngliche AP3-Implementierer noch der A3.5-MATH-/SCIENCE-/FINAL-Reviewer. Du besitzt Expertise in positiv-sequenzieller AC-Netzadmittanz, Netzreduktion, GFL/GFM/SG/SC, Per-unit-Systemen, Matrix-/M-Matrix-Theorie, Schur-/Pseudoinversen und Range, PSD, SDD/rotated SOC, verallgemeinerten Eigenwerten, Kapazitätsausbau/Unit Commitment, Julia/JuMP/MathOptInterface, MIP/MISOCP und unabhängiger numerischer Reproduktion.

**Makroziel:** Überführe die bisher **ausschließlich statischen und partiellen** A3.5-FINAL-Prüfbefunde in eine echte ausführbare und reproduzierbare unabhängige Gleichung-zu-Code-/Numerik-Abnahme. Prüfe das **Original-AP3** bei exakt gepinntem Commit zuerst ohne Änderungen. Führe P-C2A-001–010, den T-C2A-001–028-Ledger, die G0/G1/G2/G3/M0/M1/M2/LOCAL-/E2-Ketten, 124 Metriken, acht CLI-Aktionen, neun Integerfälle, Solver-B1 und Daten-/Quellenprädikate so weit wie mit vorhandenen Daten und Solvern möglich tatsächlich aus. Beweise, Gegenbeispiele, unabhängige Matrixkonstruktion, JuMP/MOI-Extraktion, Testlogs, Hashes, Code-Korrekturen und Handoffs dokumentieren.

**Unabhängigkeitsprinzip:** AP3-eigene Exportmatrizen, `PaperADiagnostics`, `AP3Pipeline`, bisherige Reports und deren PASS-Zahlen dürfen niemals die einzige Grundlage eines eigenen Oracles sein. Aus tatsächlichen Rohdaten, Quellenparametern und finalen Variablenwerten B, p, S, M, Zp, Edges und Kosten NEU berechnen. Mindestens ein eigener exakter rationaler Rechenweg und ein davon unabhängiger real ausgeführter Julia-/Solver-Rechenweg sind Pflicht.

**Korrekturmandat:** Bestätigte Fehler dürfen in einem eigenen sauberen Fix-Worktree mit minimalem Diff korrigiert und getestet werden. Wenn du die mathematische Produktionsimplementierung selbst substanziell änderst, bist du NICHT unabhängig bei ihrer finalen Freigabe: Der korrigierte SHA benötigt einen **anderen unabhängigen Reaudit-Worker**. Bis dieser abgeschlossen ist `independent_A3_5_accepted=false`. Dokumentiere stets zuerst das unveränderte Pre-fix-Urteil.

**Keine Mikroschritt-Rückfragen**, keine Hintergrundarbeit/zeitlichen Lieferversprechen. Fehlende Solver-Lizenzen, fehlende Raw-Datasets oder Umgebungsfehler exakt offenlegen; alle sonst ausführbaren Prüfungen durchführen. Reine Code-Sichtprüfung zählt nicht als Ausführungsnachweis.

## B. Exakte, neu zu überprüfende Versionsreferenzen

### FlexPlan.jl — Implementation und Reviews

- Repository: https://github.com/AlOussama/FlexPlan.jl
- Original und **immutable** AP3-Reviewtarget: `implementation/paper-a-ap3-all-formulations-v1@485b637cc1998a327206c5929434bd26c6f0be16`.
- Bestehende A3.5-Review-/Dokumentationsbranch: `review/paper-a-a3-5-independent-acceptance-v1@29192398bc7819a533b1e436c7f176b8dadb56e4` (zu Beginn neu verifizieren). Ältere mathematische Reviewbasis `0574d491111677a7ac2cabff2877735171486c46`.
- AP2 Basis `725de2e6c1cea21f63902474f72ec614b2358356`, qualifizierter Consumer `e992edc88d39fa0eb2d72e2490e157441223f568`.
- Eingangsledger (noch offen): `reports/a3_5/final/predicate_ledger_P001_P010.csv`, `theorem_equation_to_code_T001_T028.csv`, `independent_test_replay.md`, `G3_edge_reconstruction.md`, `source_and_base_validation.md`, `matrix_domain_validation.md`, `baseline_vs_corrected_git_manifest.json`, `unresolved_findings.yaml`.
- A3.5 ursprüngliche Auditvorgabe `docs/paper_a/a3_5_independent_acceptance_spec.md` auf A3.5-Reviewbranch, sowie `docs/paper_a/ap3_to_a3_5_handoff.md`, `reports/paper_a_ap3_validation.md`, `reports/paper_a_ap3_status.yaml`.

### research-map — Wissenschaft

- Repository: https://github.com/AlOussama/research-map
- Hauptreferenz `main@e8118425adc335a99e85120d943763305f211315`.
- Ursprünglicher mathematischer Freeze `2c2fce769b2ed6ffd4f1ced60c0798776acccc93`.
- Paper-A Scope `paper/c2a-system-strength-expansion-planning-v1@672a61c95525bf1d7a03cf745a754a15a23ce78b`.
- A3.5-SCIENCE/FINAL Dokumentation `review/paper-a-a3-5-science-release-v1@2badb9a90a8d3c1d4a33accee640b295de1e33a1`.
- **Noch nicht ratifiziertes** Amendment A1–A5: `docs/reports/C2_constraints/C2A_voltage_stability/paper_a/science_release/2026-10-20__a3-5-amendment-final-proposed-text.md` am Commit `5ceb19a6faf4e7c7e797a737ed5b449f9e2db609`, Git-Blob `fba4802ecabade61a752833a71106a5bda4ce78f`.
- Verbindlicher bisheriger FINAL-Status `insufficient_evidence` und `independent_implementation_adjudication: unresolved`; siehe `2026-10-20__a3-5-final-gates.yaml` und zugehörigen Bericht auf 2badb9a9...

### PyPSA2MatpowerX — Datenquelle, nur lesend

- Repository: https://github.com/AlOussama/PyPSA2MatpowerX
- `implementation/paper-a-ap1-data-contract-v1@b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c`, numerischer AP3-Referenzstand `3b8fdb01d931225edc5f8fe1e2c200d0da288a09`.

**Git-Startprotokoll:** Gegenüber allen vorgegebenen SHAs die tatsächlichen Remote-HEADs, Parent/Merge-Base, Status von Original- und bisherigen Reviewbranches, lokale Worktrees (dirty/untracked niemals löschen), bytegenaue Quellen-/Evidenz- und ZIP-Hashes, verfügbare Datenstände und Julia-/Solverinstallationen verifizieren. Wenn aktuelle HEADs differieren, diffen und exakte Prüfreferenzen beibehalten statt neue HEADs still einzusetzen.

## C. Ausführungsort und Arbeitsisolation

- Verwende einen neuen lokalen Codex-Thread in VS Code, Codex CLI oder vergleichbarem **lokalen** Coding-Agent mit echtem Shell-/Filesystem-/Julia-/Solverzugriff. NICHT denselben Worker/Thread wie AP3, NICHT einen auf Connector-Sichtprüfung beschränkten Chat.
- Für die Baseline einen eigenen sauberen `git worktree` **detached** am exakten AP3-SHA verwenden. Bestehende lokale Projekte/Arbeit und dirty Dateien erhalten.
- Für reine Auditberichte nach Prüfungen die bestehende A3.5-Reviewbranch möglichst wiederverwenden. Falls echte Korrekturen nötig sind, höchstens eine kontrollierte neue Fixbranch `fix/paper-a-a3-5-executable-closure-v1`, vor Erstellung Remote/Parent prüfen. Kein Branch-Wildwuchs.
- Keine Änderungen am wissenschaftlichen Freeze, Original-Dissertation-/Paper-A-Quellen, ursprünglicher AP3-Branch, Producerdaten, früheren Evidenzarchiven, bestehenden A3.5-Gutachten, keinem Normstatus.
- Testdaten und Logs in getrenntem scratch/run-Verzeichnis ohne in-place-Modifikation historischer Outputs.
- `julia --version`, `julia --project=. -e "using Pkg; Pkg.status()"`, Manifestversion, MOI/JuMP/Solver-Konfiguration, native MISOCP-Pfad, verfügbare Lizenzen, CPU/Threads, relevante Parameter, Toleranzen dokumentieren. Bei `Pkg.instantiate` tracked Dateien nicht unbemerkt verändern. Eigenes Depot erlaubt.

Beispiel für *nur lesende* Revisionskontrolle (Pfad an lokale Realität anpassen):

```powershell
git -C <FLEXPLAN_REPO> fetch origin --prune
git -C <FLEXPLAN_REPO> status --short --branch
git -C <FLEXPLAN_REPO> worktree list
git -C <FLEXPLAN_REPO> rev-parse 485b637cc1998a327206c5929434bd26c6f0be16
julia --version
```

## D. Reihenfolge der Originalquellen

Vorher **Primärwissenschaft** auf research-map/main@e8118425... tatsächlich lesen:
1. `scientific_report/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md` mit §§3–8,17–26,37–44,50–52 und Anhängen B–I.
2. `external_review/freeze/2026-08-02__c2a-scientific-formulation-freeze.md`.
3. `synthesis/2026-07-30__synthesis__c2a-track-a-adjudicated-proofs-and-counterexamples.md`.
4. `implementation_audit/2026-07-30__c2a-project-predicate-audit.md`.
5. `publication_planning/2026-08-09__paper-a-development-plan-freeze.md`.
6. `publication_planning/2026-10-15__paper-a-multirepo-execution-freeze-v2.md`.

Diese Pfade stehen sämtlich unter `docs/reports/C2_constraints/C2A_voltage_stability/`. Erst danach A3.5-SCIENCE-FINAL, MATH-Ledger, ältere AP3-Implementation-/Testberichte lesen. Das Amendment-Blob ist **vorgeschlagen**, nicht normativ erlassen. Als zusätzlicher bedingter Sollsatz zu prüfen, nicht still als geänderter Freeze anzunehmen:
\[
B=B^\top\succ0,\quad Z=B^{-1}\ge0,\quad p\ge0,\ S=\operatorname{diag}(p),\ \alpha>0,
\quad Zp\le\alpha^{-1}\mathbf1\implies B-\alpha S\succeq0.
\]

Die alte formale Zahl 30/30 rationaler Fälle, 6087/6087 Volltests, 4108/4108 Evidenztests, neun Integer-Referenzen, 124 Metriken und acht CLI-Aktionen sind zunächst Behauptungen des Vorarbeiters, keine unabhängigen PASS.

## E. Verbindlich zu lesen und auszuführend zu prüfen

- `src/core/paper_a_regional.jl`: network_reference, reduced_strength, regional_strength, online_exposure.
- `src/core/paper_a_formulations.jl`: G0/G1/G2/G3/M1/M2, indexed JuMP/MOI-Kegel.
- `src/core/paper_a_diagnostics.jl`: finite GEV, inverse burden, singular zero support, exakte/numerische Postsolve-Metriken.
- AP2/Strang-B-Brücken `paper_a_integration.jl`, `paper_a_qualification.jl`, `block_template.jl`, `ref_extension.jl`, `objective.jl`, `src/prob/uc_gscr_block_integration.jl` (tatsächliche Pfade/SHAs ermitteln).
- `scripts/paper_a/AP3Pipeline.jl`, `scripts/paper_a/ap3.jl`, `test/paper_a_ap3.jl`, `test/runtests.jl`, Metrik-/CLI-Registrys und Testfixtures.
- `reports/ap3_runs/20261020_macro/` incl. `accepted_suite`, `matrices_final`, `metrics_final`, `certificates_final`, `comparisons_final`, `planning_final`, `benchmarks_final`, `enumeration_final`, `export_final`, `integer_bound_audit.json`, `integrated_integer_enumeration.json`, `integer_recheck_diagnostics.json`, full ZIP-/Evidenz-Manifeste, soweit tatsächlich verfügbar.

**Immer file:line@sha und Daten-SHA256 mitgeben.** Zuerst Originalcode verstehen und echte Konstruktion nachrechnen, keine syntaktischen Tests als vollständiges pass einstufen.

## F. P-C2A-001–010: zehn separate, ausführbar belegte Nachweise

**Gemeinsame Evidenzspalten pro Prädikat:** `id; exact_expected_equation; theorem/domain; original_sha; code_file_line; raw_fixture_sha256; own_reference_oracle_sha256; positive_case; adversarial_case; reconstructable_numeric_outputs; residual; tolerance; validity_domain; actual_result; confidence; status; fix_owner`. `verified_for_registered_cases` und `mathematically_universal` sind verschiedene Klassen.

**P-C2A-001 (Symmetrie):** Positive-sequenzielle Ybus aus Leitung, Transformator inklusive komplexer Taps, π-Ladung, Shunt und Referenz/Islands eigenständig bauen, L=-Im(Y) und passive retained Matrix herleiten. Symmetrie pro registriertem Zustand nach Schur und Source Stamp prüfen, ungeeignete Phasenschieberfälle nicht still symmetrisieren. Ybus, AC-PF-/Q-V-Jacobi und internes L strikt trennen.

**P-C2A-002 (Z-Matrix):** alle Offdiagonalen von B und M auf sign≤0 und Struktur nach Reduktion überprüfen; negative Gegenmutation und SPD-nicht-Z-Fall als Domainverletzung erkennen. Positive Definitheit impliziert nicht inverse Positivität.

**P-C2A-003 (PSD/PD/Schur):** Rank, Inertia, Nullität, Kondition, Inseln, Slack vs echtes Grounding, Lee-Matrix. Reiner SVD-Invertierbarkeitstest genügt für algebraische Kron-Elimination, nicht PSD-Äquivalenz. Lee≻0 bzw Lee≽0+Range \((I-Lee Lee^\dagger)Ler=0\) prüfen. Pflichtfälle \(\left[\begin{smallmatrix}2&-1\\-1&-1\end{smallmatrix}\right]\) (Schur positiv, Gesamtmatrix indefinit), \(\left[\begin{smallmatrix}1&1\\1&0\end{smallmatrix}\right]\) (Pseudoinverse ohne Range falsch), valide singuläre passive Laplace-Klasse. **Ohne physisch zulässige Gegeninstanz keinen bestätigten produktiven Codebug behaupten.**

**P-C2A-004 (Inverspositivität):** für jedes benutzte M0/M1 und Implikation B=Bᵀ≻0 sowie Z=B⁻¹≥0 elementweise, synthetische inadmissible inversen-negative Probe B=[[1,4/5],[4/5,1]], p=(1,1), alpha=1; Zp=(5/9,5/9), B-S indefinit.

**P-C2A-005 (G1/G2):** aus selbst rekonstruiertem \(M=B-\alpha\mathrm{diag}(p)\) exakt \((M\mathbf1)_i\ge0\). Gleiches i/t/scenario/alpha/p/pu-Base und alle retained Busse. Fixes, exogenes r>0 für G2; G2(1)=G1; G1 vs beliebiges r nicht universell vergleichbar. Mutationen von Vorzeichen, Index, Nullsupport durchführen.

**P-C2A-006 (Quelle):** \(B_t=B^0+\mathrm{diag}(b^{fix}+\sum\mu_k^{str}b_k^{blk}n_{k,t}^{on})\) unabhängig aus Originaldaten berechnen. Nur bei fester passiver Topologie, retained-only Quellen, festen exogenen mu/alpha, gemeinsamem Bus-/MVA-/Volt-Basis und einem Stamp pro Element ist die Matrix-LMI affin. Separate Quelle hinter Reaktanz \( [[b,-b],[-b,Bnet+b]]\): fester interner Phasor gives +b, freier stromloser Innenknoten nach Schur kein b. SG/subtransient/SC/GFM-Filter/Current limit/Herstellerquellen als physische Zusatzgates — deklarierter source_equivalent_valid-Bool reicht NICHT.

**P-C2A-007 (Exposure):** \(p_{i,t}=\sum_{GFL(i)}\mu_k^{fl}(P_k^{blk,MW}/S_{base})n_{k,t}^{on}\), p≥0, S=diag(p), korrekte Grid-Control-Klasse und AC-Zuordnung. \(0\le n^{on}\le n^{avail}\le n^{inst}\); Anschluss a_conn nicht mit wetter-/ressourcenbedingtem a_res verwechseln. installed/nameplate vs online-nameplate vs dispatch vs Current-Capability und Speicherladung separat; einmalige Base-Umrechnung.

**P-C2A-008 (G3):** \(M=B-\alpha S\) symmetrisch Z, jede nichtverschwindende **ungerichtete** Edge i<j exakt einmal, Vorzeichen m_ij erhalten, qij,qji≥0, \(q_{ij}q_{ji}\ge m_{ij}^2\), MOI RotatedSOC \((qij,qji,\sqrt2\,mij)\); residual \(d_i=m_{ii}-\sum_jqij\ge0\). Rekonstruktion \(M=\sum_{\{i,j\}} E_{ij}\left[\begin{smallmatrix}qij&mij\\mij&qji\end{smallmatrix}\right]E_{ij}^\top+\mathrm{diag}(d)\) aus tatsächlich generierten MOI-Modellvariablen und eigenen Basismatrizen. Einbezogen singuläre, reduzierbare, isolierte Busse und Nullzeilen. Mutationen: Kante fehlt/verdoppelt, falsches sqrt2, Residuum fehlt, Vorzeichen- oder Offdiagonalverlust. Auf PSD-symmetrischer Z-Klasse G0⇔vollständiges G3; Gegenfall PSD-nicht-Z \(\mathbf1\mathbf1^\top\in\mathbb S_+^3\) darf nicht als G3-Äquivalenz akzeptiert werden. Native MISOCP-Solver ist EXTRA Gate.

**P-C2A-009 (singuläres S):** \(S=\mathrm{diag}(S_a,0_z)\), S_a≻0. Bzz≻0 gewöhnlicher Schur; Bzz≽0 singulär braucht Range \((I-BzzBzz^\dagger)Bza=0\) und pseudoinversen Schur, sonst endlicher formaler Pencil-Eigenwert nicht gleich globalem Quotient/PSD. Pflicht \(B=\mathrm{diag}(2,-1),S=\mathrm{diag}(1,0)\): formal λ=2, Rayleigh-Infimum −∞. S=0 ⇒ γ undefiniert, G0 noch Matrixgate. Kein epsilon in Nullsupport.

**P-C2A-010 (independentes Postprocessing):** aus **Rohdaten und finalen Modell-Entscheidungen** erneut B0/Bt/p/S/M, eigen/PSD, G1/G2 rows, G3 Edge q/Rest, Zp exact M0, M1 Bmin/Zub, M2 W, lokale Burdens, objective Investment/OPEX/Ereignis-/Scenario weights berechnen. Erst danach unabhängiges Ergebnis mit AP3-Exports/Registry/CSV-JSON vergleichen. Keine Selbstprüfung durch Kopieren von `paper_a_diagnostics.jl` oder `AP3Pipeline.jl`.

## G. Theorem-Ledger und unabhängige Rechenwege

Für **alle T-C2A-001 bis 028** eine echte Zeile: vollständiger theorematischer Status unter Domain, Primärfundstelle, erwartete Gleichung, aktuelle Codefundstelle oder ausdrücklich `theorem_only_not_encoded`, eigenes positives/negatives Oracle, abweichende Implementierung, Releaseentscheidung. Historischer T003-Originalquellen-Symbolbezug darf ungelöst bleiben, nicht erfinden. T006 singular-S, T010 G0⇏M0, T018–020 closed SDD, T021 Bmin-Monotonie und T025–028 Woodbury/Neumann/Trust-Region sorgfältig behandeln.

**Zwei unabhängige Methoden**: (1) eigenentwickeltes Python Fractions/SymPy/Julia Rational für exakte Hauptminoren, Spektren, Inversen, Schur und Gegenfälle; nicht lediglich vorheriges `independent_oracle.py` ausführen; (2) echte generierte Julia/JuMP/MOI-Modellinstanz mit explizit ausgelesenen Affin-/Kegelconstraints, unabhängigen Werte-/Rundungschecks, Primal/Dual Residuen, BigFloat wo angezeigt. Mathematische Identität ≠ Floating-Toleranz ≠ Solverstatus.

Pflichtbeispiele:
- B=[[1,-1/2],[-1/2,1]], p=(1/4,2/3), alpha=1: G0 PSD singulär, Zp=(7/9,19/18), also G0⇏M0.
- B=[[2,-1],[-1,2]], p=(11/10,1/20): M0 gilt Zp=(3/4,2/5), G1 erste Zeile negativ.
- Nichtinverspositiver SPD-Gegenfall aus P004.
- LOCAL alle erfüllt, aber G0 scheitert; zwei G1/fixed G2(r) Nichtimplikationen; reduzierbare/singuläre PSD-Z, 3×3 Nicht-Z-PSD, Schur-/Range-Grenzfälle.
- Zusätzlich selbst konstruierter positiver irrationaler oder rationaler Test, nicht vom vorherigen Reviewer kopiert.

Die neue SCIENCE-Kette M2⇒G1⇒M0⇒G0 und G0⇔G3 nur unter identischer Domäne prüfen, ohne vorzeitige Normübernahme des proposed A1–A5-Amendments.

## H. Tatsächliche AP3-Läufe, Native G3-MISOCP und Integer-Certificates

1. Reproduziere eigenständig die projektweit deklarierte volle Julia Regression und die Evidenztests. Frühere `6087/6087`, `4108/4108` **nicht** als neue PASS kopieren. Julia-/Solverversionen und Laufkommandos/Exitcodes festhalten.
2. G3-Blocker B1: bestehender Pajarito/HiGHS/Clarabel-Pfad meldet teils INFEASIBLE für unabhängige G3-feasible Integerfälle. Roh-Solverlogs, generated-MOI-Constraints, numerische Skalierung, Primal-Feasibility-Witness, ggf. separaten verfügbaren echten MISOCP-Solver testen. Infeasible-Meldung ohne mathematisches Zertifikat nicht als Unmöglichkeit ausgeben; eine kleine Integer-Enumeration ist nur **case-specific global cost bound**, kein Nachweis nativer Solverzuverlässigkeit.
3. Neun Integer-Referenzfälle unabhängig: primal feasibility, objektive Invest-/OPEX-/Start-/Shutdown-Komponenten, Originalwährungs-Offset, tatsächlicher primal/dual global bound und Gap nach Umrechnung aus eventueller inkrementeller Objective-Koordinate prüfen. Beschränke globale Aussage auf nachgewiesene Fälle, keine unbelegte Intervallarithmetik.
4. Vollständige G0/G3-konditionale Optima: gleiche B/p/S, Systemkosten, Entscheidungen und gültige symmetrisch-Z-Klasse; \(C^*_{G0}=C^*_{G3}\le C^*_{M0}\le C^*_{G1}\le C^*_{M2}\) nur bei identischem Minimierungsmodell/definierten Optima. M1-INFEASIBLE ⇒ **nicht** M0-INFEASIBLE.
5. Alle **124 Registry-Metrik-IDs** und **acht tatsächlich implementierte CLI-Aktionen** neu ausführen und CSV/JSON-Roundtrip, units, null support, Coverage/Exporthashes prüfen; vorige 68.861 Messungen/687 Snapshot-Rekonstruktionen sind Vorbericht-Claims, keine automatische Pflichtzahl bei geändertem Setup.
6. Producer 3/6/24-Snapshot-Fixtures, soweit auf Laufhost vorhanden; die bekannten 24 Dreistundenintervalle ergeben 72 Stunden, nicht 24. `time_elapsed`, `operation_weight`, Szenario-/Representative-Gewichte, einjährige OPEX-Konvention, Startup/Shutdown-Ereignisgewichtung, jährliche CAPEX-Basis, Speicher P+E, Investitionsoffset und echte Kostenquellen prüfen. Fehlende reale Quellenparameter und Studienrepräsentativität sind separate Owner-/Datengates.
7. ZIP/LFS-Evidenz: alle für das Ergebnis benutzten Inputs mit SHA256, Laufumgebung, Ergebnispfad und Testlog hash-verknüpfen. Historische Runarchive unverändert lassen.

**Bewertung differenzieren:** `native_G3_MISOCP: certified | alternative_case_bound_only | numerical_inconclusive | failed | not_run`. `integer_globality: certified_cases | partial | not_run`. Ein Code-G3-„PASS“ darf diese Status nicht implizit zusammenfassen.

## I. Debugging und kontrollierte Korrektur

- Zuerst auf dem **unveränderten Original-SHA** alle feststellbaren Fehler samt tatsächlicher minimaler Reproduktion dokumentieren. Nicht von synthetischer nichtphysikalischer Matrix automatisch auf Produktionsdefekt schließen.
- Wenn eindeutig verifizierte Fehler: minimaler Patch auf eigener kontrollierter Fix-Branch, mit docstrings, Regression, Mutations-/Inertia-/G3-/Rohdaten-Oracle sowie vollständigem Vorher/Nachher-Diff und Resultat-SHA. Freeze und Producer nicht verändern.
- Eigene Korrekturen sind eigene Implementation, keine unabhängige Vollabnahme: Stelle `corrected_code_independent_reaudit: pending` und liefere separat einen selbstständigen Reaudit-Auftrag mit exakter Fix-SHA. KEIN `independent_A3_5_accepted=true` durch Selbstsignatur.
- Keine wissenschaftlichen Daten oder Modell-Zielbedingungen „korrigieren“, nur damit der Solver plausible Ergebnisse liefert.

## J. Pflicht-Ausgabe (additive Artefakte, keine alten Dateien überschreiben)

Bevorzugter neuer eindeutiger Folder in FlexPlan:
`reports/a3_5/executable_closure_20261020/`; bei Pfadkonflikten Revision vergeben.

1. `independent_executable_closure_report.md`: einziger umfassender deutscher Abschlussbericht, Revisions- und Fundstellenmatrix, alle Verifikationsgrenzen.
2. `predicate_P001_P010_evidence_ledger.csv`: zehn Evidenzzeilen mit code:file:line@sha, Domain, Fixture-SHA, Unabhängigkeit, Mutation, Residuum/Toleranz/Entscheidung.
3. `theorem_T001_T028_equation_to_code_ledger.csv`: jede T-ID fundiert klassifizieren; `theorem_only_not_encoded` falls zutreffend.
4. `independent_reference_oracle.py` und/oder ausführbares Julia-Orakel + `oracle_results.json`, echte Logs und SHA-Manifest, positive/negative/boundary.
5. `independent_matrices_B_p_S_M_Zp_G3.json`, Schur-Range-/Source-/MVA-Provenienz und getrennte Modell-Rohdatenmatrix-Differenzen.
6. `g3_native_misocp_and_edge_completeness.md`; `integer_global_bounds_and_objective_audit.json` für neun Fälle inkl. unverified.
7. `metrics_124_cli_8_replay.md` mit tatsächlichen Kommandos, Laufstatus, Index-/Export-/Einheitenchecks.
8. `baseline_vs_optional_fix_git_manifest.json`, `unresolved_blockers.yaml`, `reproduction_manifest.json`, `release_gates.yaml`.
9. Falls substantielle Korrektur: separater Reaudit-Handoff inklusive Fix-Commit und Prüfspezifikation.

Große Binärlogs/ZIP-Archive nur mit überprüften SHA256 und reproduzierbarer Ablage manifestieren, keine Git-Limits umgehen, keine historischen Belege überschreiben.

## K. Abnahmekriterien und Status-Gates

```yaml
original_ap3_sha: 485b637cc1998a327206c5929434bd26c6f0be16
existing_review_sha_at_start: 29192398bc7819a533b1e436c7f176b8dadb56e4
proposed_science_amendment_blob: fba4802ecabade61a752833a71106a5bda4ce78f
scientific_release_adjudication: approve_for_owner_ratification
owner_ratification: pending
science_amendment_approved: false

P001_to_P010: per_predicate_evidence_required
implementation_equation_match: accepted | accepted_for_registered_cases | corrections_required | unresolved
independent_numerical_replay: passed | partial | failed | not_performed
native_G3_MISOCP: certified | alternative_case_bound_only | numerical_inconclusive | failed | not_run
integer_globality: certified_cases | partial | not_run
corrected_code_independent_reaudit: passed | pending | not_applicable
independent_implementation_adjudication: accepted | accepted_for_registered_cases | corrections_required | unresolved
independent_A3_5_accepted: false
A3_closed: false
AP4_ready: false
empirical_study_ready: false
```

**`independent_A3_5_accepted=true` nur nach vollständiger eigenständiger dokumentierter Abnahme auf unverändertem Code oder nach genehmigtem separatem Reaudit eigener substantieller Fixes.**

**`science_amendment_approved=true` nur durch explizite Wissenschaftsowner-Ratifizierung der exakten Textversion samt späterem normativem research-map-Commit, niemals eigenmächtig.**

**`A3_closed/AP4_ready/empirical_study_ready` nicht ohne separate vollständige Solver-, Integer-, Physik-, Kosten- und Datenqualifikationen setzen.**

Ein einziges Schlussfeld wählen:
`executable_closure_verdict: accepted_unchanged_original | accepted_for_registered_cases | corrections_required | correction_ready_for_independent_reaudit | blocked_by_solver_or_data | unresolved_insufficient_evidence`.

## L. Git-Abschluss

Neue Reports vorzugsweise auf bestehender A3.5-Reviewbranch, bei erforderlicher Codekorrektur ausschließlich kontrollierter Fixbranch. Keine Auto-PR, Merge, Reset, Rebase, Force-Push oder alte Reportüberschreibung. Nach Push `git ls-remote`, Merge-Base, Git-SHA und vollständige Diff-Liste gegen die angegebene Originalbasis sowie gegen Revieweingang verifizieren. Producer-/Science-Repos read-only. Abschlussbericht muss ausweisen, welche Dateien/Tests wirklich ausgeführt wurden, welche nicht, und wie ein ggf. unabhängiger nachgelagerter Code-Reaudit starten muss.

**Keine fiktiven Test-PASS, kein falscher Owner-Beschluss, kein vorzeitiges A3-/AP4-Gate.**