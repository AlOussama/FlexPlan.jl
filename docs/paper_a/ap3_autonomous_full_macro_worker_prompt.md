# Paper A — AP3 Autonomous Macro Worker: Complete Formulations, Certificates, Metrics and Post-Processing

**Execution mandate:** ONE autonomous end-to-end AP3 implementation and validation pass. **Status: authorized for local execution; no AP3 work is claimed executed by this prompt.**

**Owner scope decision (2026-10-20):** Implement **all mathematically/physically meaningful formulation candidates** from the full C2A mathematical corpus, not only G0/G1/G3; implement **all applicable evaluation metrics and executable independent post-processing scripts**. Select a technically sensible internal execution order without recurring approval/microtask loops. Distinguish *an optimization constraint*, *an exact post-solve diagnostic*, *a sufficient certificate* and *a conditional, possibly noncertifying approximation*. Do not silently exclude a candidate because it is absent from a shortened journal-paper manuscript.

## 0. Your role, authority, and operational style

Act as a senior power-systems and numerical optimization engineer/researcher with expert command of:

- Positive-sequence nodal admittance, network islands, references/grounding, regional Kron/Schur reduction, fixed versus online source equivalents.
- Generalized eigenvalues and singular pencils, symmetric Z-/M-matrices, inverse positivity, exact/singular generalized Schur complements, closed scaled diagonally dominant (SDD) cones, PSD LMIs, (rotated) SOC, MIP/MISDP/MISOCP.
- JuMP/MOI/PowerModels/FlexPlan in Julia, optimization templates, UC, storage, physical units, annualized/overnight investments, time/event weights and numerical verification.
- Independent reproducible measurement: eigen/inertia, impedance and MIIF burdens, formulation conservatism, economic and spatial investment consequences, solver capability/performance.

**Work autonomously in one coherent macro iteration**. Decide internal function names, source organization, solver packages, order of grouped implementation, synthetic fixtures, numerical tolerance strategy, testing/debug cycles and number of cohesive commits. When a compiler, optimizer, numerical certificate, or CLI test fails, investigate and correct it **within the same run**. Do not ask the owner to approve each implementation step. Preserve and extend the existing consumer; do not create a new mathematical or data preparation engine.

**Do not reduce this mandate to “implement G0/G3 then hand back a TODO list”.** Meaningful existing G2, M1, M2, local/MIIF/ESCR/MSCR metrics and bounded inverse-approximation machinery are part of AP3. Genuine physical/model-domain impossibility or absent solvers can justify a precisely diagnosed, separately gated limitation, not silent omission or fabricated success.

## 1. Repository ownership, branches, pinned evidence, and concurrency

### 1.1 Writable code repository: FlexPlan.jl ONLY by default

`https://github.com/AlOussama/FlexPlan.jl`

There are TWO verified lines of work based on the same AP2 integration commit:

| Evidence | Branch / exact commit | Meaning |
|---|---|---|
| AP2 tested code | `implementation/paper-a-ap2-regional-optimization-v1@725de2e6c1cea21f63902474f72ec614b2358356` | 5987 repository tests; 153 AP2 tests; 51 producer checks; affine B/S/M and G1 |
| AP3-A0 docs | same branch after documentation @ `8180afb3ea482e66a8c114db9b7fb4a90b1d3325` | complete full-mathematics GAP and expanded candidate/metric/CLI specification, **no AP3 implementation** |
| **Strang-B qualified consumer** | `integration/paper-a-parameter-qualification-v1@e992edc88d39fa0eb2d72e2490e157441223f568` | AP2-derived consumer code, parameter-scope validation and tested 9 parametric MILP+LP scenarios |

**Recommended single AP3 implementation branch:** `implementation/paper-a-ap3-all-formulations-v1`, based on **verified Strang-B consumer code `e992edc88...`**, because it already consumes the new parametrically qualified inputs. If the branch already exists, inspect all unique history and retain it, never reset. Do **not** edit the two AP2/Strang-B source branches directly. Import or cherry-pick the **documentation-only** AP3-A0 commits/files from the AP2 documentation branch into the AP3 branch, verifying their exact content. Both branches descend from the same `725de2e...`, but have separate changes; do not blindly merge unrelated histories or overwrite the newer Strang-B consumer. Record the actual ancestry and precise applied diff. If the remote moved, fetch/compare and reconcile non-destructively.

**Science authority, READ ONLY:**

`https://github.com/AlOussama/research-map`

- Comprehensive dissertation C2A v3 on `main@e8118425adc335a99e85120d943763305f211315`:
  `docs/reports/C2_constraints/C2A_voltage_stability/scientific_report/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md`, especially **Part V §§17–26, Part VII §§41–44, Part VIII §§50–52 and appendices B–F**.
- Frozen theorem scientific content `2c2fce769b2ed6ffd4f1ced60c0798776acccc93`, formal freeze `external_review/freeze/2026-08-02__c2a-scientific-formulation-freeze.md`.
- Adjudicated proofs/counterexamples `synthesis/2026-07-30__synthesis__c2a-track-a-adjudicated-proofs-and-counterexamples.md`.
- Paper-specific scope freeze `paper/c2a-system-strength-expansion-planning-v1@672a61c95525bf1d7a03cf745a754a15a23ce78b`.
- Original A3-A4 commitments `publication_planning/2026-08-09__paper-a-development-plan-freeze.md` and `publication_planning/2026-10-15__paper-a-multirepo-execution-freeze-v2.md`.
- Strang-B science decision note on `codex/paper-a-strang-b-parameter-qualification@a6c19790bb009b5956475a6368a23e339a82dab7`. It is **conditional**, not empirical approval.

**Producer and qualified scenario data, READ ONLY:**

`https://github.com/AlOussama/PyPSA2MatpowerX`

- Original AP1 tested producer `32ff4525dc576af52c16298cb35ebd98f02cf8b2`.
- Strang-B producer numeric anchor `3b8fdb01d931225edc5f8fe1e2c200d0da288a09`, later documentation handoff branch HEAD observed `b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c`.
- Registered parametric data: `data/paper_a_study/parameter_registry.csv` SHA256 `a249f7a96d202798c6ff5778c1fa1571eba59a3717bac5d25b150d2a6c41bce9`, `study_scenarios.toml` SHA256 `be9d9d9aa90e9790fc7c3554bc1107777a5ba743f4f95d8f675acd9bfeb1e75a`.
- Contract `docs/paper_a/parameter_qualification/cross_repository_handoff.md`, machine gates `reports/paper_a_data_qualification_status.yaml`.

**Already executed Strang-B evidence:** 4162/4162 producer, 5987/5987 consumer, 153/153 AP2, 51/51 pinned producer, 291/291 qualified parametric acceptance, 54/54 network audit, **9/9 MILP OPTIMAL and 9/9 LP OPTIMAL** in registered scenarios. These were reported by Strang B, **not rerun by you yet**. Parametric input-contract readiness `true`; `empirical_study_ready=false`, `theorem_domain_valid=false`, `AP3_math_ready=false`, `A3_closed=false`, `AP4_ready=false`. The three historical producer synthetic Integer-INFEASIBLE cases remain negative regressions. Do **not** confuse mathematically qualified/declared parametric scenarios with measured real-network data.

**Cross-branch rule:** AP3 edits one AP3 branch and its worktree. Do not write into concurrent AP1/Strang-B branch, research-map, shared non-committed worktrees or `main/master`. The standard default is no PR, no automatic merge, no force push or deletion. Any essential producer/science defect is documented as a precise owner/Strang-B handoff rather than fixed by changing frozen science. Preserve historical manifests, audit logs and dirty files.

## 2. Mandatory source reading and acceptance of A0

Before changing implementation code, read in order:

1. `docs/paper_a/ap3_a0_full_mathematics_gap_analysis.md` (AP3-A0 mathematics/code-map).
2. `docs/paper_a/ap3_a0_comprehensive_formulations_metrics_postprocessing_scope.md` (owner-expanded complete list; **takes precedence** over older “G2/M1/M2 optional” text).
3. AP2 `docs/paper_a/ap2_to_ap3_handoff.md`, `docs/paper_a/ap1_ap2_compatibility_matrix.md`, `reports/paper_a_ap2_status.yaml`, `reports/paper_a_ap2_validation.md`.
4. New Strang-B consumer `docs/paper_a/parameter_qualification_annex.md`, `src/core/paper_a_qualification.jl`, `test/run_paper_a_parameter_acceptance.jl`, the nine solved scenario records and hash manifests.
5. The **full dissertation** (not just the paper): frozen theorems T-C2A-001–028, singular/reducible counterexamples, Schur-range conditions, exact implication/non-implication graph, planning restrictions.
6. Earlier detailed research formulation `ESCR gSCR MSCR Comparison` if available in local attached material or research-map: historical G0/G1/G2/G3/M0/M1/M2/E2 candidates, explicit G1/G2 incomparability, M1 minimum-strength requirement, MIIF conventions and trustworthy Woodbury/Neumann remainder. Treat historical ideas as **candidates**, adjudicate any contradiction against the frozen theorem set.
7. Current real source functions, tests and actual Project/Manifest:
   - `src/core/paper_a_regional.jl`, `paper_a_integration.jl`, `block_template.jl`, `ref_extension.jl`, `constraint_template.jl`, `constraint.jl`, `objective.jl`;
   - `src/prob/uc_gscr_block_integration.jl`, `src/io/parse.jl`, `src/io/scale.jl`, `src/FlexPlan.jl`;
   - `test/paper_a_regional.jl`, `test/paper_a_integration.jl`, `test/run_paper_a_ap1_acceptance.jl`, AP2/Strang-B acceptance scripts, entire `test/runtests.jl`.

Write a short evidence-based **change-impact map** (existing functions reused vs new functions) before code changes. This may be included in the final implementation doc; no separate approval cycle.

## 3. Invariant shared mathematical input and domain

For retained regions \(\mathcal R\), passive eliminated physical nodes \(e\), fixed threshold \(\alpha\ge0\):

\[
Y^{(+)}=G+jB^{phys},\quad L=-\Im Y^{(+)},\quad
B^0=L_{rr}-L_{re}L_{ee}^{-1}L_{er},
\]
\[
b_{i,t}^{src}=b_i^{fix}+\sum_{k\in\mathrm{SYN,GFM,SC}_i}
\mu_k^{str}\frac{S_k^{blk}}{S_{base}x_k^{src}}n_{k,t}^{on},
\quad B_t=B^0+\operatorname{diag}(b_t^{src}),
\]
\[
p_{i,t}^{fl}=\sum_{k\in GFL_i}\mu_k^{fl}\frac{P_k^{blk}}{S_{base}}n_{k,t}^{on},
\quad S_t=\operatorname{diag}(p_t^{fl}),\quad M_t=B_t-\alpha S_t.
\]

Actual `x_src` must be converted from its declared native MVA base to block/system base; never deduce measured x from legacy b=5. SYN is a synchronous physical class, not converter-GFM. A source embedded in Y is not added twice; technical `a_conn` is distinct from renewable resource `a_res`. GFL exposure is **online nameplate**, not actual dispatched MW; stay on common \(S_{base}\). No unsupported transformer/tap topology correction or artificial slack grounding.

**Use the SAME AP2 `B`, `S_diag`, `M` affine JuMP objects** for each optimization family. Producer `B0_reference` is diagnostic only. Source/region mapping order, compound `(table,id)` keys, time/scenario indices, installed/online/integer semantics, cost scaling, storage physics, terminal policy and operational flow model remain identical across formulations.

Project predicates P-C2A-001…010 must be evaluated with explicit, case-scoped evidence: symmetry, offdiagonal sign, PSD/PD/zero modes, inverse positivity, exact G1 rows, affine diagonal source additions, nonnegative exposure/common base, complete G3 edges/diagonal residues, singular exposure, independent post-solve reconstruction.

**Distinguish domain classes:** For a symmetric Z-matrix \(M\), G1/G2 are sufficient; on the *complete symmetric PSD Z-matrix* class G3 iff G0 if signed edges and diagonal residuals are exhaustive. For M0/inverse inequalities additionally verify \(B_t\succ0\) and inverse-positive assumptions as needed. PD must **not** be imposed on a legitimate singular G3/PSD boundary solely for numerical convenience.

## 4. Implement the ENTIRE formulation family (using existing architecture)

Select formulations explicitly through existing `AbstractGSCRFormulation` / `UCGSCRBlockTemplate` and a small extension thereof; preserve `NoGSCR`, `GershgorinGSCR` G1 and historical schema-v2 behavior. Never add policy objects to source JSON.

| ID | Exact implemented role and requirements |
|---|---|
| **BASE** | No strength constraint; full independent metrics still evaluated. |
| **G0** | True affine PSD LMI \(M_t\succeq0\) per required snapshot. Use actual PSD cone, not elementwise >=. Continuous SDP baseline with qualified solver; for tiny integer models either verified native MISDP or **complete** finite integer enumeration with fixed-assignment continuous SDP and a completeness certificate. Unknown MIP capability ≠ solved integer optimum. |
| **G1** | Reuse AP2 \(M_t\mathbf1\ge0\); independent row residual. Keep existing G1 investment behavior and negative regression. |
| **G2(r)** | Actually selectable fixed-positive-\(r\) LP/MILP, \(M_tr\ge0\). Support several **pre-registered offline** `r` strategies and provenance; \(r=\mathbf1\) must reproduce G1. Arbitrary fixed G1 vs G2(r) can be incomparable. Optimizing \(r\) jointly with decisions is generally **bilinear**, never label it linear. |
| **G3** | Complete undirected structural edge \(\{i,j\}\) once; \(q_{ij},q_{ji}\ge0\); \(\begin{bmatrix}q_{ij}&m_{ij}\\m_{ij}&q_{ji}\end{bmatrix}\succeq0\); \(m_{ii}-\sum_jq_{ij}\ge0\). MOI rotated SOC uses `[qij,qji,sqrt(2)*mij]` because `2tu >= ||x||²`. Preserve signed offdiagonal, isolated zero rows, reducible/singular Laplacian points and exact matrix reconstruction; continuous SOCP and qualified MISOCP/integer reference. |
| **M0** | Exactly \(y=B_t^{-1}p_t^{fl}\le\alpha^{-1}\mathbf1\) **as independent post-solve criterion** for \(\alpha>0\), \(B_t\succ0\) and applicable inverse-positive class. Provide a bounded tiny direct-enforcement benchmark via capable bilinear/NLP solver or full discrete enumeration if genuinely supported; if not, mark this extra enforcement `not_supported` with mathematical/solver reason. The exact M0 *metric* may not be omitted. **G0 does not imply M0.** |
| **M1** | Valid fixed inverse upper-bound \(Z^{ub}=(B^{min})^{-1}\) and \((Z^{ub}p_t)_i\le\alpha^{-1}\). Enforce in the actual model \(B_t\ge B^{min}\) in the declared ordered nonsingular M-matrix construction; verify \(0\le B_t^{-1}\le Z^{ub}\) componentwise for solved states. Do not assert an unproved universal Gershgorin↔inverse bound. |
| **M2** | Actual \(B_t\mathbf1\ge\alpha Wp_t\) (equivalently the consistent full G1-strength margin with weighted exposure), \(W\ge0\), \(\operatorname{diag}W=\mathbf1\). Implement full and pre-registered sparse/neighbor weights, map explicit MIIF source/base, track differences from M1 and exact M0. Under frozen assumptions M2⇒G1 and conditionally ⇒M0; sparse easier-to-satisfy ≠ universally more accurate/safe for real MSCR. |
| **LOCAL** | Diagonal/local rank-one PSD and impedance-based ESCR/rho diagnostics, correctly domain-gated; if practical linear/single-bus constraint variant is justified, expose separately without claiming G0 equivalence. |
| **E2/Woodbury/Neumann** | Implement **exact** Woodbury and controlled Neumann/Taylor post-solve routines, convergence radius, finite remainder/norm error (T-C2A-025–028). If a **provably one-sided** safety margin and enforced trust region can be derived, add an explicitly conditional selectable approximation. Otherwise a working `exploratory_noncertifying` diagnostic and negative tests are mandatory; no fake globally safe MILP. |

Do not drop M1/M2/G2 because G3 is exact: their **LP/MILP cost, conservatism and spatial consequences** are central research comparisons. G0/G3 objective equality is expected under *verified* same matrix-domain and same planning formulation, but solver inaccuracies/multiple optima must be accounted for.

**Preserve publication science:** Fixed-exposure \(S^{on}\) is Paper-A baseline. \(S^{nom}\), \(S^{op}\), \(S^I\) are physically different definitions, not interchangeable “conservative approximations.” Optional TNEP/topology/contingency/AC-CPF/dynamics/EMT are **not** a license for AP3 to expand into a new research programme.

## 5. Required solver plan — freedom without unsupported claims

Use actually available local, compatible Julia packages and solver licenses. Check MOI support and run tiny capability proofs for LP/MILP, PSD/SDP, SOC/SOCP, MISOCP, optional MISDP/NLP. **HiGHS is not a PSD/SOC solver.** Choose available appropriate conic backends; prefer a reproducible open-source continuous SDP/SOCP path if practical. Integrate optional licensed MISOCP if actually available, or use a fully enumerated *small* integer portfolio as exact reference; never report LP relaxation as an integer solve.

Record Julia/Project/Manifest, package/optimizer backend versions, solver options, MOI bridge use, primal/dual status, gap/bounds and cone residuals. Record explicit `solver_unavailable`, `solver_unsupported`, `numerical_inconclusive`, `infeasible` and `not_executed` states.

Solver failure cannot be solved by reducing \(g_{\min}\), falsely changing integer bounds, inserting an artificial grounding term, disabling AP2 storage/economics, or claiming direct MISDP support. The worker has discretion to substitute equivalent correct backends/algorithmic paths and to put slow optional large cases behind reproducible explicit targets without concealing coverage.

## 6. All evaluation metrics — **implement executable algorithms**, not headings

For each metric register `metric_id`, exact formula, theorem/evidence, unit/common base, bus/region/edge/snapshot/scenario/portfolio scope, valid domain, expected output shape, independently executable algorithm, tolerance and status.

**(A) Physical/network matrix evidence**
- Independent raw-data assembly \(Y^{(+)},L,B^0,B_t,S_t,M_t\), native/common MVA, source reactance/strength, \(\mu^{str/fl}\), `a_conn`/`a_res`, fixed source and regional topology.
- Symmetry residual, positive offdiagonal violations, Z-/M-matrix class, \(\lambda_{\min}\), inertia/nullity/rank/condition, grounding/island/Schur-range checks, producer↔consumer↔reconstructor residuals and provenance.

**(B) G0/G1/G2/G3 / spectral**
- Smallest finite generalized eigenvalue \(\gamma^{GE}\) of `(B,S)`, minimum eigenvalue of \(M_t\), exact feasible/binding/violation status. Singular \(S\) requires positive-exposure support Schur or pseudoinverse **with projector/range condition**; \(S=0\) is `no_positive_exposure`, not a fabricated finite gamma. Report eigen/eigenspace residual and critical regional participation when mathematically meaningful.
- G1 row margins \(M\mathbf1\), G2 scaled margins \(Mr\), minimum/worst margins, binding locations/frequencies and conservatism rejection on G0-feasible points.
- G3 qij/qji, SOC product/cone residual, node budgets, signed-edge completeness, matrix reconstruction and G0/G3 cross-feasibility objective comparison.

**(C) Impedance/MIIF/ESCR/MSCR/M0/M1/M2/local**
- Exact \(y=B\backslash p\), linear solve residual; \(Z_{ii}\), reciprocal diagonal short-circuit strength, \(\min Z_{ij}\), inverse positivity and numerical condition, \(\rho_i^{diag}=1/(Z_{ii}p_i)\), \(\rho_i^{Zp}=1/(Zp)_i\) **only with valid denominators**.
- Exact M0 burden/slack, \(Z^{ub}p\), M1 inversion bound/inverse order, source minimum, M2 \(Wp\), full/sparse MIIF \(W_{ij}\), local rank-one PSD margins; binding buses and multiple infeasibility statuses.
- Conventional SCR/ESCR/MSCR/gSCR/MIIF **must** have source-specific definitions and physical denominators (Thevenin/short-circuit convention, voltage/ratings, base/time-scale). The mathematical \(Zp\) burden is not automatically a published fault-based MSCR. Where inadequate, `not_comparable`/`undefined` with explanation, not a silently invented value.

**(D) Update/approximation validation**
- Exact Woodbury direct-vs-updated solve residual, Neumann \(E=A^{-1}\Delta\), spectral radius/norm, finite truncation, actual error, T028 remainder/norm upper bound, trust region, componentwise safe margin where proved; false-certification count for noncertifying approximation.

**(E) Economics, dispatch and spatial planning**
- Independently reconstruct total objective, CAPEX annualized/overnight with period/basis, variable/no-load/production, per-MW-block startup/shutdown **event count** costs, storage operation, curtailment and FOM without double-scaling.
- \(n_0,n_{inst},n_{on},n_{\max}\), investments in blocks, MW/MVA/MWh by carrier/region/source class, source stiffness and GFL online exposure, SOC/UC/power-flow/branch/terminal residuals, binding regions and critical periods.
- Cross-formulation cost delta and relative gap with named denominator, additional investment and technology-/location-mix, false accept/false reject/true exact agreement **at the same objective, constraints and physical scope**, variation of \(g_{\min}\), source reactance/weights/costs and temporal assumptions.
- Preserve cases with multiple distinct optimal investments; objective equality is not proof of identical portfolios.

**(F) Solver/complexity/quality**
- Variables integer/continuous, constraints linear/PSD/SOC and edges/time states; compilation/preparation time versus solve time, wall time, memory if available, nodes/iterations, status, primal/dual bound, MIP/conic gap, feasibility/dual residual, reproducibility/environment/hashes.
- Non-executed or unsupported solves have null numeric metrics and specific status, not a zero solver time/cost.

**Exposure variants:** S_nom, S_on, S_op, S_I as a separately versioned semantics/sensitivity register; the primary G0/G1/G2/G3 comparison always uses identical declared S_on. Static-voltage Jacobian/CPF and dynamics/EMT metrics belong outside this Paper-A AP3 core (cross-reference other C2A parts, do not fake or implement full new models).

## 7. Mandatory independent POST-PROCESSING implementation and scripts

Create a small reusable Julia processing library **separate from JuMP constraint assembly** and make it executable via **eight logical commands**. You may implement these as one CLI with subcommands or several well-scoped scripts; use existing scripts/modules when appropriate.

| Required executable action | Primary output / verification |
|---|---|
| `run_formulation_suite` | Same case, objective, source/exposure, alpha, time/blocks across BASE/G0/G1/G2/G3/M1/M2; valid M0/E2 references separately. Per-variant solution+solver+manifest; `unsupported`, `infeasible` preserved. |
| `reconstruct_strength_matrices` | From original network/parameters and selected solved installed/online decisions, independently rebuild Y/L/B0/B/S/M; matrix and numerical residual exports per snapshot. |
| `evaluate_strength_metrics` | G0/GE/PSD, G1/G2/G3, local rho, MIIF, ESCR/MSCR with proper definitions, M0/M1/M2, Woodbury/Neumann metrics; machine-readable long-form CSV/JSON. |
| `verify_certificates` | Domain and P-C2A-001…010, exact Eigen/Schur-range/PSD/RSOC/M1/M2/MIIF and false-implication checks, full negative/undefined statuses. |
| `compare_formulations` | Feasible-set fidelity and conservatism, cost/investment/location differences, G0/G3 agreement, G1/G2 incomparable cases, solver gaps and consistent plots/tables. |
| `assess_planning_results` | Independent investment, dispatch, startup/shutdown, BESS/SOC, time/event weights, power balance and spatial allocation reconciliation. |
| `benchmark_conic_scaling` | Reproducible solver capability/performance and complexity across controlled instance sizes, seed and versions. |
| `export_paper_a_evidence` | Consolidated tabular/graphical outputs derived from actual numbers, case and input hashes, versioned evidence index and human-readable report. |

**Independent means:** Do NOT simply query JuMP `value(M)` and recycle the solver's G1/G3 slacks as independent proof. Recompute from the **source network and independently reconstructed coefficients**, and compare results to JuMP values and input reference hashes. For conic certificate q variables from the solver are permitted as witnesses, but their reconstruction and PSD/SOC validation must be done independently.

**CLI requirements:** explicit case/input/output paths (no hardcoded private Windows paths), deterministic seed/selected scenario, clean output root, overwrite protection or identified run IDs, versioned machine-readable schemas, robust error/status return, source/input/parameter/solver provenance. Include a README showing actual execution commands. Missing data or a solver must yield a reportable non-success state, not a false PASS.

## 8. Registered test and demonstration matrix

Include **actual executed** grouped Julia tests, mathematical handcheck fixtures, negative tests, qualified Strang-B parametric integration, and full prior-regression after AP3 modifications.

### 8.1 Mathematical counterexamples (frozen theorem package)
- \(B=[1,-1/2;-1/2,1]\), \(p=(1/4,2/3)\), \(\alpha=1\): G0/G3 pass (singular boundary), G1 fails, M0 fails because \(B^{-1}p=[7/9,19/18]\).
- Same B, p=(3/4,3/4): all local diagonal tests pass but G0 fails.
- G1/G2 both incomparability counterexamples from T015 with r=(2,1).
- Singular Laplacian \(M=[1,-1;-1,1]\): G0/G3 pass and M0 inverse undefined; reducible blocks and isolated zero rows.
- Positive-semidefinite **non-Z** matrix: reject blanket G0⇔G3 statement; complete closed-SDD exactness requires domain.
- Singular exposure support, positive eliminated Bzz, singular Bzz with **range condition**, all-zero exposure.
- Independent source normalizations Sbase != 100, actual passive Schur, fixed sources exactly once, q orientation/sqrt2/edge omissions, nonnegative W diag 1, valid Bmin and inverse order.
- M1 counterexample if lower bound not actually enforced; M2 full/sparse valid/invalid W; E2 unbounded/noncertifying Taylor and Neumann outside convergence.
- Numeric cases with ill-conditioning and eigenvalue degeneracy; report *accuracy/inconclusive* rather than blanket pass.

### 8.2 End-to-end planning and comparison
- Qualified nine Strang-B parametric scenarios at source numeric anchor, respecting scenario/registry hashes and `conditional_owner_review_pending`; use them as realistic **parametric** AP3 inputs, not empirically verified data. Existing 9/9 MIP and 9/9 LP optima provide source-level reference; any AP3 test run is new, separate evidence.
- Common-data BASE/G0/G1/G2/G3/M1/M2 comparative solve under compatible scopes; a meaningful network-transmission strength transfer case where G1 is conservative while G0/G3 are feasible.
- At least one **genuinely integer** planning case with cost-bearing source investment and a proven optimality/gap certificate for a conic formulation, using actual MISOCP or small complete enumeration. Separate any unsolved general MISDP case.
- Preserve original three producer-synthetic Integer-INFEASIBLE observations and three LP-OPTIMAL cases as negative/positive regression, respectively; do not change minimum-generation constraints to force feasibility.
- Native and alternate exposure/battery cost/time scenarios are separate physically qualified runs, **not** direct conservatism comparisons if the definition changes.
- Validate G0/G3 objective equality/cross-feasibility within correctly diagnosed solver tolerances and matrix domain, including possible multiple optima.

### 8.3 Mandatory metric/CLI regression
- Every metric registry ID appears in schema tests with at least one *valid computed* fixture where mathematically possible and an invalid/undefined case where applicable.
- Entire pipeline can re-run from saved model inputs+solution without needing hidden local state; raw status files and compared hashes must match, or differences are explained.
- CSV/JSON parse/schema, units/time normalization, no-event-doublecount, solver-unavailable/infeasible/undefined statuses, degenerate eigenvectors, denominator zero and missing external costs.
- Run the full historical consumer suite after code changes and record test counts, process exit codes, Julia/optimizer versions. Do not present the 5987 historical result as a new run.

## 9. Output artifacts and scientifically honest status

On the **single AP3 branch** create/update coherent artifacts, preferably within existing Paper-A paths:

1. `docs/paper_a/ap3_formulation_candidate_registry.md` — all candidates incl. equations, theorem IDs, guarantees, solver class, source->code->test, supported/not_supported/deferred scientific reasons.
2. `docs/paper_a/ap3_evaluation_metric_registry.md` — **every** metric with units/base/domain and executable reference.
3. `docs/paper_a/ap3_implementation_architecture.md` — shared B/S/M, formulation dispatch, conic layout, numerical independent module, qualified data integration, solver policy.
4. `docs/paper_a/ap3_postprocessing_user_guide.md` — exact CLI commands and example paths/repro, output schema.
5. `reports/paper_a_ap3_validation.md` — actual commands, solver and package versions, test results, eig/PSD/SOC/inverse/Schur/MIIF/numerical/economic residuals, rational counterexamples, solver capability and limitations.
6. `reports/paper_a_ap3_status.yaml` — machine-readable per-candidate / per-metric / per-script gates and `A3_closed=false`, `AP4_ready=false` unless **independent** later audit authorizes otherwise.
7. `reports/ap3_runs/<run_id>/` with immutable per-run case/registry hash, manifests, solutions, metrics, matrices, certificates, comparison, economics, solver benchmarks and generated tables/figures.
8. `docs/paper_a/ap3_to_a3_5_handoff.md` — independent equation-to-code review checklist, P001–P010 evidence, approved-scope limitations and precise follow-on requirements.
9. New grouped unit/negative/conic and end-to-end tests included in the normal or clearly documented dedicated test targets. Do not rewrite scientific freeze files to pass tests.

Recommended status fields include:

```
work_package: AP3
verdict: AP3_completed | AP3_partial | AP3_blocked
input_contract:
  ap1_sha: ...
  ap2_sha: ...
  strang_b_consumer_sha: ...
  producer_registry_sha256: ...
  scenario_sha256: ...
  science_sha: ...
candidate_status:
  G0: {code: ..., solver: ..., evidence: ...}
  G1: {code: ..., solver: ..., evidence: ...}
  G2: {code: ..., solver: ..., evidence: ...}
  G3: {code: ..., solver: ..., evidence: ...}
  M0: {postsolve: ..., optional_enforcement: ...}
  M1: {code: ..., theorem_domain: ..., evidence: ...}
  M2: {code: ..., weights: ..., evidence: ...}
  E2: {exact_updates: ..., bounded_certificate: ..., exploratory: ...}
metric_registry_complete: ...
postprocessing_all_commands_executable: ...
independent_reconstruction_passed: ...
project_predicates_P001_P010: ...
G0_G3_domain_exactness_verified: ...
parametric_study_input_ready: ...
empirical_data_approved: false
A3_closed: false
AP4_ready: false
```

Do **not** mark a candidate solved merely because its data class and helper function were created. Separate `implemented`, `build_executed`, `solver_supported`, `numeric_verified`, `mathematically_certified`, `scope_restricted` and `not_executed`.

## 10. Autonomous run protocol, stop conditions and commit policy

**One macro pass with internal subphases (not external microtask tickets):**

A. Fetch/verify source branches and science SHA, preserve local dirty worktrees, map existing code/tests and qualification contracts. Establish the single AP3 work branch from verified **Strang-B consumer** and bring the AP3-A0 documentation without clobbering code.

B. Build a solver-independent physical/matrix/metric reconstruction library **early**, so it can serve as an oracle for every optimization family; implement metric registry and domain/primal certification.

C. Implement G0/G1/G2/G3 and M1/M2 as faithful template-selected optimization formulations; then M0 direct benchmark where solvable, Woodbury/Neumann/E2 safe-or-noncertifying machinery and all local/fault-family conditional metrics.

D. Build/execute the postprocessing CLI and complete same-case comparison/solver benchmark. Integrate nine qualified Strang-B scenarios, preserve old negative regressions, and run all applicable tests after fixes.

E. Commit coherent changes on the same AP3 branch, push, fetch exact final remote SHA, compare against pinned baseline, list all changed paths and hashes, publish summary and independent A3.5 handoff.

**Autonomous authority:** You may select package/solver libraries, source layout, numerical methods, test targets, scopes of enumerated small cases and internal iterations. No need to request confirmation for code compilation fixes, function organization, parser/metrics JSON layout, solver capability probes, small deterministic matrices, logical scientific subcase grouping or reasonable numeric tolerances with scale justification.

**Escalate only actual fundamental blockers**:
- A need to change the frozen mathematical statement/assumption, prove new equivalence, or choose a genuinely new empirical scientific claim.
- Missing owner approval for using actual historical/legacy parameters as *empirical measurements*, rather than declared parametric assumptions.
- Unsafe repo force/reset/uncommitted collaborator changes or inaccessible essential branch.
- Mathematical impossibility to construct a requested *certifying* approximation under its proposed hypotheses; report precise proof gap and implement noncertifying computation rather than claim certification.
- Tool/solver lack preventing a required proof **after** working fallback paths have been tried and documented. Finish independent implementations/tests first and report precise missing capability once.

If runtime constraints force a partial outcome, **finish the largest mathematically valid cohesive subset**, publish all evidence and a single blocker register. Never declare A3.5 or AP4 complete from AP3 alone.

## 11. Mandatory final worker report (German)

Provide **one** coherent report, not a stream of approval requests:

1. `AP3_completed / AP3_partial / AP3_blocked` with distinct code/formulation/metric/script/real-data scopes.
2. All repository/input/math/parameter and output remote SHAs, branch ancestry, exact changed file list and safe worktree preservation.
3. Mathematical candidate inventory: each G0/G1/G2/G3/M0/M1/M2/E2/LOCAL/BASE, theorem domain, actual implementation type and solver method/status. Distinguish exactness, sufficient and noncertifying approximation.
4. Proof-to-code-to-test mapping including singular Schur range, full G3 edge coverage/signed entries/residual, G0-not⇒M0 and fixed G1/G2 incomparability.
5. Full metrics registry and **actual eight CLI function execution evidence**, result schemas, command lines and relative input/output reproduction.
6. Actual Julia/Project/Manifest, conic/MIP/NLP solver capability and versions, all successful/failed/inconclusive tests and counts; numerical residuals, objective comparisons and gaps.
7. Parametric Strang-B study comparison with data SHA and scientifically proper **conditional** scope; genuine empirical blockers separately and unchanged.
8. Investor/economic, geographic, exposure, strength, MIIF and post-solve burdens by family, cross-feasibility and explicit unknown or undefined metrics.
9. Every project predicate P-C2A-001–010 with PASS/FAIL/NOT_EVALUATED + exact evidence and tolerance; all required updated documentation files and GitHub links.
10. Final `A3_closed=false`, `AP4_ready=false` and narrowly scoped independent A3.5 verification requirements. No unapproved merge/PR.

**Execution authorization:** YES — one self-contained AP3 worker run covering **all meaningful mathematical formulation candidates, all evaluation metrics and all executable independent post-processing workflows** on FlexPlan, using the qualified parametric Strang-B producer/consumer data and frozen full C2A mathematics. Only fundamental scientific/governance blockers require an owner decision.
