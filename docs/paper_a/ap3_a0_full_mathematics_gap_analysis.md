---
title: "Paper A — AP3-A0 Detailed Mathematical and Implementation Gap Analysis"
date: 2026-10-20
status: specification_ready_implementation_not_started
scope: "G0, G3, independent generalized spectral / M0 diagnostics, project predicates"
scientific_basis: "full C2A dissertation v3 + frozen theorem / counterexample register; Paper A manuscript only for scope"
flexplan_ap2_baseline: "725de2e6c1cea21f63902474f72ec614b2358356"
producer_ap1_baseline: "32ff4525dc576af52c16298cb35ebd98f02cf8b2"
research_map_main_observed: "e8118425adc335a99e85120d943763305f211315"
scientific_formulation_freeze: "2c2fce769b2ed6ffd4f1ced60c0798776acccc93"
paper_scope_freeze: "672a61c95525bf1d7a03cf745a754a15a23ce78b"
execution_verified_by_this_report: false
---

# AP3-A0 — Mathematics-first gap analysis and implementation specification

## 0. Verdict and evidence standard

**Verdict: `AP3_A0_specification_ready`; `AP3_not_implemented`; `AP3_not_numerically_certified`.** The AP2 implementation already supplies a validated *synthetic-scope* positive-sequence Schur/reference/affine-JuMP B/S/M interface and G1. The missing AP3 work is **not** another regional-network importer: it is direct G0 conic/PSD optimization, complete G3 edge-wise rotated-SOC optimization, independent generalized-eigenvalue/Schur/inverse-burden diagnostics, global and post-solve domain predicates, independent numerical cross-verification and conic/MIP solver qualification.

This assessment is source/code inspection plus elementary independent NumPy examples; it **does not claim** any new Julia/solver run or AP3 implementation PASS. AP1's 4142 tests, final producer CI successful, and AP2's 5987 / 153 / 51 tests are existing recorded evidence, not re-executed here. AP1 real physical/economic study data remain unverified. AP2's separate 3 LP-OPTIMAL vs 3 Integer-INFEASIBLE producer synthetic cases remain distinct.

### 0.1 Evidence hierarchy: comprehensive mathematics, not an abbreviated manuscript

**Mathematical primary exposition:**

`AlOussama/research-map` at observed `main@e8118425adc335a99e85120d943763305f211315`:

`docs/reports/C2_constraints/C2A_voltage_stability/scientific_report/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md`

Especially Part V §§17–26, Part VII §§41–44, Part VIII §§50–52, Appendices B–F. This comprehensive chapter preserves 40 theorem IDs with proof assumptions, implication directions, counterexamples, singular and reducible cases. Its frontmatter deliberately states `implementation_verified=false`, `numerical_validation_complete=false` and `scientific_closure=not_adjudicated_by_writer`; do not confuse comprehensive rewriting with Track-C validation.

**Theorem adjudication and scientific freeze:**
- `.../external_review/freeze/2026-08-02__c2a-scientific-formulation-freeze.md`: `frozen_scientific_content_commit=2c2fce769b2ed6ffd4f1ced60c0798776acccc93`, approved *scientific mathematical content*, not implementation.
- `.../synthesis/2026-07-30__synthesis__c2a-track-a-adjudicated-proofs-and-counterexamples.md`.
- `.../implementation_audit/2026-07-30__c2a-project-predicate-audit.md`: predicates P-C2A-001–010, historically unverified at its original audit baseline (these historical states are re-evaluated narrowly below against AP2, **not** adopted unchanged).
- `.../publication_planning/2026-10-15__paper-a-multirepo-execution-freeze-v2.md`: required A3.3/A3.4/A3.5 sequence and X10–X12.
- Paper A planning/manuscript `paper/c2a-system-strength-expansion-planning-v1@672a61c...` used **only** to delimit which comprehensive theorems are in Paper A, the selection of online-nameplate GFL exposure, and the fixed regional/topology/alpha assumptions. Manuscript compression is **not** used to replace the full proofs.

**Implementation evidence pinned:**
- `AlOussama/FlexPlan.jl` AP2 `725de2e6c1cea21f63902474f72ec614b2358356`; `docs/paper_a/ap2_to_ap3_handoff.md`, `reports/paper_a_ap2_status.yaml`, `reports/paper_a_ap2_validation.md`.
- `AlOussama/PyPSA2MatpowerX` AP1 `32ff4525dc576af52c16298cb35ebd98f02cf8b2`; scientific input schema `scientific_physical_data/1.0`.
- Strang B default-qualification macro subsequently published on producer `b30faaa7fa1708028ff83e08e926476f47170b1e`; **no assumption its work has executed**. AP3 implementation must pin the actual data/contract SHAs at execution and not overwrite parallel Strang-B files.

## 1. Frozen mathematical objects and assumptions

### 1.1 Physical network and online exposure (reused from AP2)

On retained regional nodes \(r\), with **fixed/passive** eliminated nodes \(e\):

\[
Y^{(+)}=G+jB^{phys},\quad L=-\Im Y^{(+)},\quad
\mathcal B^0=L_{rr}-L_{re}L_{ee}^{-1}L_{er}.
\]

For empty \(e\): \(\mathcal B^0=L_{rr}\). A Schur reduction needs nonsingular \(L_{ee}\), and cannot eliminate decision-dependent source equivalents. For the selected static source-behind-reactance and fixed-topology domain,

\[
b_k^{blk}=\frac{S_k^{blk}}{S_{base}x_k^{src}},\quad
b_{i,t}^{src}=b_i^{fix}+\sum_{k\in \mathrm{SYN,GFM,SC}_i}\mu_k^{str}b_k^{blk}n_{k,t}^{on},
\]
\[
\mathcal B_t=\mathcal B^0+\operatorname{diag}(b_t^{src}),\qquad
p_{i,t}^{fl}=\sum_{k\in GFL_i}\mu_k^{fl}\frac{\bar P_k^{blk}}{S_{base}}n_{k,t}^{on},
\quad S_t=\operatorname{diag}(p_t^{fl}),
\]
\[
M_t(\alpha)=\mathcal B_t-\alpha S_t.
\]

Sources already included in fixed Y must not be added again. Online GFL nameplate does not track instantaneous dispatch/renewable resource output. AP2 handles these math expressions for its accepted scope; real-source provenance is **not** approved by mathematical code tests.

### 1.2 G0: exact full-space PSD, not just a generalized eigenvalue scalar

**T-C2A-005/006; §19:** For fixed \(\alpha\ge0\),

\[
\boxed{G0_t:\;M_t(\alpha)\succeq0}.
\]

With \(S_t\succ0\), \(\gamma_t=\lambda_{\min}(S_t^{-1/2}\mathcal B_tS_t^{-1/2})\), and \(G0\iff \gamma_t\ge\alpha\). With \(S_t\succeq0\) singular, the **full-space PSD constraint is still well defined**. For positive-exposure set \(a\) and zero-exposure set \(z\), partition:

\[
M=\begin{bmatrix}B_{aa}-\alpha S_a&B_{az}\\ B_{za}&B_{zz}\end{bmatrix}.
\]

If \(B_{zz}\succ0\), T-C2A-004 gives
\[
M\succeq0\iff B_{aa}-B_{az}B_{zz}^{-1}B_{za}-\alpha S_a\succeq0.
\]
If \(B_{zz}\succeq0\) is **singular**, the generalized PSD Schur equivalence additionally requires
\[
(I-B_{zz}B_{zz}^\dagger)B_{za}=0,\quad
B_{aa}-B_{az}B_{zz}^\dagger B_{za}-\alpha S_a\succeq0.
\]
No naive deletion of zero-exposure nodes, no unconditional pseudoinverse and no \(\varepsilon\)-exposure. With entirely zero \(S\), the LMI \(\mathcal B\succeq0\) remains meaningful while a finite generalized-eigenvalue threshold scalar has no positive-exposure denominator and must be reported as `not_defined_no_exposure`, not a fake number. Singular/indefinite blocks require explicit range/eigen checks; generalized Schur is a **diagnostic/reduction**, not a license to replace the full-space G0 optimization with a changing-variable Schur inverse.

**Optimization class:** affine \(M(x)\) on fixed retained space with fixed \(\alpha\) -> SDP continuous, MISDP with integer decisions. A mixed-integer SDP is **not** solvable by assuming the existing HiGHS MILP backend understands PSD cones. A continuous conic G0 benchmark with fixed/relaxed block variables is the mandatory reference; rigorously certified small integer G0 requires an actually supported MISDP method or exhaustive finite assignment with continuous PSD subproblems and documented completeness.

### 1.3 G1 and G2: comparison, not mistaken equality

**T-C2A-011 to 015; §21.** For symmetric Z-matrix \(M=M^\top\), \(m_{ij}\le0\) off diagonal:

\[
G1:\quad M\mathbf1\ge0 \quad\Longrightarrow\quad M\succeq0.
\]

The proof is the nonnegative sum \(\sum_{\{i,j\}}|m_{ij}|(x_i-x_j)^2+\sum_i(m_{ii}-\sum_{j\ne i}|m_{ij}|)x_i^2\). On a branch Laplacian its row contribution cancels; **G1 can lose credit for network transfers**. A fixed \(r\in\mathbb R^n_{++}\) defines \(G2(r):Mr\ge0\Rightarrow G0\), with \(G2(\mathbf1)=G1\). Arbitrary fixed G1 vs G2 are **incomparable** (T-C2A-015); do not promise G2 monotonically improves G1. Optimizing r jointly is generally bilinear. **AP3 must reuse AP2 G1**; fixed G2 is an optional auxiliary comparison only if justified by Paper-A scope.

### 1.4 G3: complete signed edge-PSD/rotated-SOC, including boundary points

**T-C2A-016–020; §22.** Fixed undirected graph \(E_M=\{\{i,j\}: i<j,m_{ij}\neq0\}\). For each edge, take **both oriented endpoint variables** \(q_{ij},q_{ji}\ge0\):

\[
Q_{ij}=\begin{bmatrix}q_{ij}&m_{ij}\\m_{ij}&q_{ji}\end{bmatrix}\succeq0,\quad
d_i^{res}=m_{ii}-\sum_{j:\{i,j\}\in E_M}q_{ij}\ge0.
\]

Equivalently \(q_{ij}q_{ji}\ge m_{ij}^2\), \(q_{ij},q_{ji}\ge0\). Under JuMP/MOI's rotated convention \(2tu\ge\|x\|_2^2\), the three-vector constraint must use

\[
\boxed{[q_{ij},\,q_{ji},\,\sqrt2\,m_{ij}]\in \mathcal Q_r^3}.
\]

**Do not omit the square-root-of-two.** The SOC alternative \(\|[2m_{ij},q_{ij}-q_{ji}]\|_2\le q_{ij}+q_{ji}\) is equivalent. Every edge counted exactly once, off-diagonal **signed** \(m_{ij}\) preserved, node budget for each endpoint, isolated rows have \(m_{ii}\ge0\). For any symmetric \(M\), summing the edge blocks plus nonnegative diagonal residues proves \(G3\Rightarrow G0\) (T017).

The reverse is **not true for arbitrary PSD matrices**. For the complete symmetric Z-matrix domain (nonpositive off-diagonals), **including reducible matrices, singular irreducible M-matrix blocks, isolated zero rows and singular Laplacians**, T-C2A-018 shows every PSD matrix admits a positive diagonal scaling into weak diagonal dominance (closed SDD). Consequently the *complete* G3 projection equals G0 for the project class only if T019 implementation predicates hold (T020):

\[
\boxed{G3\iff G0\quad\text{only on the declared symmetric PSD Z-matrix domain with complete signed-edge/residual construction.}}
\]

No strict positivity of \(M\) may be required merely to make G3 convenient. Do not use approximate sparsification or remove nonzero edges without a proved numerical-error policy. Network sources alter only diagonals in the present AP2 model; hence the fixed graph can be derived from independently assembled \(\mathcal B^0\), not guessed from arbitrary current decision values. Candidate topology, changing offdiagonals, phase/tap asymmetry or new edges require a separate treatment, not silently accepted. Exact G3 under the fixed-affine topology model -> SOCP continuous, MISOCP with integer blocks, conditional on solver support.

**Key distinction:** G3 is sufficient in general; **exact** for the frozen symmetric Z-class when all predicates are met. Both statements must appear in results and tests.

### 1.5 M0 and other local metrics: independent diagnostics, not G0 synonyms

**T-C2A-007–010/021–028; §§20,23,24:**

\[
\mathcal B_t\succ0,\quad Z_t=\mathcal B_t^{-1}\ge0,\quad p_t^{fl}\ge0,\quad\alpha>0
\quad\Longrightarrow\quad
\boxed{M0:\;Z_tp_t^{fl}\le \alpha^{-1}\mathbf1}.
\]

Compute numerically via a **linear solve**, not an explicit inverse in production; separate invertibility, conditioning, inverse-positive class and zero-exposure semantics. If \(\mathcal B_t\) is singular/indefinite, `M0_not_defined` (or `domain_invalid`) rather than pseudoinverse substitution. Local diagonal ratios \(\rho_i^{diag}=1/(Z_{ii}p_i)\) and row-burden ratios \(\rho_i^{Zp}=1/(Zp)_i\) are distinct; define/flag zero denominators rather than reporting infinity as a measured system value.

**T-C2A-010 counterexample:** G0 does **not** imply M0. M0 may imply certain local tests under \(Z\ge0\), but not G0 automatically. Conditional G1 -> M0 (T012) requires inverse positivity. M1 requires a **genuinely enforced** nonsingular M-matrix lower bound and correctly ordered inverses. M2 requires nonnegative unit-diagonal interaction weights, then M2 -> G1 (T023), and only conditionally M0 (T024). These are important **proof/test/non-implication dependencies**, not a mandate to implement additional optimization approximations M1/M2 in Paper A. Woodbury is exact algebra under inverses and does not convexify decision dependence; finite Neumann truncation needs \(\rho(E)<1\) and a certified remainder (T025–028). No unsupported inverse linearization or post-hoc one-sided claim.

## 2. Verified AP2 code surface and precise missing functionality

Inspected **actual** AP2 `725de2e...` files:

| Component | AP2 code evidence | Observed availability | AP3 delta |
|---|---|---|---|
| Parser, physical reference | `src/core/paper_a_regional.jl:network_reference`, `reduced_strength`; `src/core/ref_extension.jl:ref_add_uc_gscr_block!` | Independently constructs Y, L, passive B0; reference/inventory/island/Schur gates; synthetic tests | **Reuse**; prove/test all-state matrix predicates and report per-state spectral classes |
| Source/exposure incidence | `src/core/paper_a_integration.jl:_paper_a_add_reference!`; `_paper_a_online_expressions!` lines ~241–258 | `(table,id)` -> region, strength, exposure; affine `B`, `p_fl/S_diag`, `M`; fixed source protection | **Reuse same objects** for G0/G1/G3 and independent re-computation |
| G1 | `_paper_a_g1!` lines ~260–270; `constraint_gscr_gershgorin_sufficient` | Valid affine row-sum baseline on checked symmetric Z reference; non-unit mu, multiple technologies tested | No rewrite; add comparative exact slacks/eigenvalues |
| Formulation dispatch | `src/core/block_template.jl`: `AbstractGSCRFormulation`, `NoGSCR`, `GershgorinGSCR`; `UCGSCRBlockTemplate`; `_validate_uc_gscr_block_gscr_formulation_supported` | **Only NoGSCR or G1 is supported** | New explicit `ExactPSDGSCR` / `ExactEdgeSOCGSCR` (names illustrative) with correct validation and exposure policy; no default fallback |
| Builder | `src/prob/uc_gscr_block_integration.jl:build_uc_gscr_block_integration`; `_uc_gscr_block_requires_gscr_constraints` | Dispatch/block/economic + conditional G1 in an active-power DCP integrated builder | Route template-selected G0/G3 through same affine refs and existing bounds/objective; no duplicate UC/network constructors |
| Numerical objective | `src/core/objective.jl`, `src/core/paper_a_integration.jl:scale_paper_a_costs!` | Tested on synthetic integer/LP cases, distinct event and dispatch weights | Preserve **identical objective coefficients/weights** in G0/G1/G3 |
| Matrix domains | `src/core/paper_a_regional.jl:symmetric_z`, `network_reference` | Reference-level Z symmetry check and `passive_domain_issues`; `symmetric_z_valid` synthetically true | Predicate ledger for **assembled state**: symmetric, sign, PSD/PD/nullity, islands, inverse positivity, singular S, edge coverage |
| SDP/PSD optimizer | No G0 formulation class, cone builder or G0 suite in inspected AP2 code; Project deps include HiGHS and Gurobi, not a pinned SDP solver | **Missing** | Add continuous SDP benchmark; prove MOI PSD cone/solver capability at runtime |
| Edge-SOC optimization | No G3 formulation class, endpoint q, rotated SOC or node-budget builder | **Missing** | Complete fixed-edge catalogue, exact rotated SOC, residual/edge reconstruction |
| Generalized spectrum / M0 | AP2 `ap2_to_ap3_handoff.md` explicitly defers generalized eigenvalues/inverse-burden | **Missing** | New *independent post-solve* numerical module, hard domain gating and exact residuals |
| Validation | `test/paper_a_regional.jl`, `test/paper_a_integration.jl`, `test/run_paper_a_ap2.jl`, existing producer acceptance; current tests use HiGHS | B/S/M, G1, Schur, SOC/dispatch costs; AP2 reports 5987/5987 complete, 153/153 AP2, 51/51 producer | Add AP3 mathematical, conic, singular, negative and cross-objective tests, without erasing AP2 evidence |
| Real study data | Producer reports genuine source x/MVA/mu, cost/year/currency, shunt/grounding and event representativity unresolved | **Data-qualified real study blocked** | AP3 mathematical tests on controlled verified **synthetic** fixtures in parallel to Strang B; no real-study approval |

The AP2 `Project.toml` already has `Gurobi`, `HiGHS`, `JuMP`, `LinearAlgebra`, but this **does not** prove a working Gurobi license or that Gurobi accepts the chosen exact conic encoding. HiGHS is LP/MILP, **not** an SDP/SOC benchmark. Confirm candidate conic package compatibility with pinned Julia 1.10.11 and Manifest on the actual local worker.

## 3. Project-predicate gap re-evaluation (P-C2A-001–010)

Statuses below are **AP3-A0 source/code assessment**, not a new exhaustive runtime audit. `AP2_qualified` only reflects AP2's documented tested scope; never re-label the July 2026 original audit retroactively.

| Predicate | Current code/evidence | AP3 obligation | Assessment |
|---|---|---|---|
| **P001** \(\mathcal B_t=\mathcal B_t^\top\) | AP2 Y/L/B0 symmetric Z checks for bounded supported primitives; online diagonal affine | Independent post-solve all-snapshot reconstruction and symmetry residual | **AP2 qualified; full-state audit open** |
| **P002** nonpositive offdiagonals | AP2 `symmetric_z` applied to B0; diagonal sources cannot alter offdiagonals | Check signed offdiagonal and edge sparsity for all selected states, negatives on phase/taps | **AP2 qualified for fixed topology; AP3 gate open** |
| **P003** PSD vs PD/reference | AP2 islands, slack/reference metadata, Schur nonsingularity; no universal eigen/inertia guarantee | Distinguish PSD, PD, singular Laplacian, no-grounding island, indefinite cases | **Open** |
| **P004** inverse-positive class | AP2 no independent \(Z=\mathcal B^{-1}\ge0\) certification | Verify nonsingular M-matrix/inverse sign and conditioning **only when M0 computed** | **Open** |
| **P005** actual G1 rows | AP2 `_paper_a_g1!` same online expressions; positive-threshold integer test | Independent exact row-slack comparison, do not change existing G1 semantics | **AP2 qualified; independent comparison open** |
| **P006** purely diagonal affine source strength | AP2 `_paper_a_online_expressions!`; independent source/exposure residual 0 on pinned synthetic LP | Check every solved state, fixed double-count guard, sensitivity and domain | **AP2 qualified on supported equivalent; real source evidence open** |
| **P007** nonnegative exposure/common base | AP2 physical normalization, mu and connection checks; `S_diag` affine | Confirm selected `S^{on}` vs nom/op/current and alpha/base/singular zero exposure | **AP2 qualified; AP3 domain gate open** |
| **P008** complete G3 | No edge PSD/SOC implementation | All edges exactly once, signed matrix entry, oriented q, nonnegative residual, construction/reconstruction and boundary tests | **Missing: blocking AP3** |
| **P009** zero-exposure generalized handling | AP2 can construct zero `p_fl`, but no exact spectral Schur/range evaluator | Full-space PSD and finite generalized spectrum; positive/singular zero subset, range check, all-zero exposure | **Missing: blocking AP3** |
| **P010** exact postprocessing/binding | AP2 G1/source/cost residuals only | Reconstruct exact \(B,S,M\), \(\lambda_{\min}\), G0/G3/G1, \(Zp\), dual/primal statuses and binding classification | **Missing: blocking AP3** |

**Gap status does not imply all-state theorem-domain approval for actual PyPSA network.** With \(b^{src}\ge0\), positive diagonal augmentation preserves *offdiagonal sign*, but **does not in general establish \(\mathcal B_t\succ0\)** on every feasible state, especially floating or disconnected islands. A reference slack bus is not an electrical ground.

## 4. Required AP3 implementation architecture

### 4.1 Shared matrix representation and contract

Keep AP2 data authority:
- `ref[:paper_a_regional]`: `Y,L,B0,b_fix,regions,retained,eliminated,islands,S_base_MVA,passive_domain_issues`.
- `ref[:paper_a_coefficients]`: compound asset keys -> `(region,strength,exposure)`.
- `pm.ext[:paper_a_online][nw]`: affine `B`, `S_diag`, `M`; `M` built with **one fixed numeric alpha**.

Provide a single internal matrix/edge accessor reused by formulations; never form a second physical susceptance from DCP branch `b`. One-based region order and common system base fixed. New formulations should not require changing input `device` objects to solver objects. The fixed edge catalogue uses \(i<j\) and nonzero **fixed** \(B0_{ij}\); enforce complete coverage with exact structural/threshold diagnostics, no false edge omission. No dynamic shunt/network edge additions except under a separately proved supported extension.

### 4.2 Concrete conic builders

**G0:** accept a symmetric *affine* expression matrix and add a single matrix-level PSDCone/MOI PSD triangle constraint per required snapshot; do not mistake elementwise `>=0` for Loewner PSD. Enforce fixed \(\alpha\ge0\), model/solver capability, complete B/S/M dimension checks, static topology and source-domain scope. For n=1, scalar nonnegativity is mathematically equivalent but retain exact output semantics. Affine integer decisions yield MISDP; continuous relaxation is separately labelled.

**G3:** construct one pair \(q_{ij,t},q_{ji,t}\) per undirected structural edge, force `q>=0`, impose `[qij,qji,sqrt(2)*mij] in RotatedSecondOrderCone()`, and for each node `mii-sum(qij for incident oriented endpoints)>=0`. Store edge pairs, edge constraints, node budgets and reconstruction slacks per snapshot. Do not use absolute-value-approximated signs or per-edge one-sided q. Verify \(\|M-\sum E^\top Q E-\operatorname{diag}(d^{res})\|\) from actual solved variables.

**Shared template:** use existing `AbstractGSCRFormulation` dispatch and `UCGSCRBlockTemplate`. Reject unsupported solver type and offdomain inputs explicitly rather than silently reverting to G1 or a relaxed coefficient. Preserve optional `NoGSCR` baseline and existing `GershgorinGSCR`.

### 4.3 Solver and benchmark qualification

JuMP/MOI represents matrix-PSD and rotated SOC. The worker must **actually prove runtime MOI support** on pinned Julia, package and solver backends before reporting any solved AP3 case. Based on current JuMP documentation: Clarabel.jl and SCS.jl offer continuous SDP/SOCP; Gurobi and Mosek are potential MISOCP backends subject to license, version, MOI bridge and exact cone support; Pajarito is a potential decomposition method for mixed-integer conic models, also requiring verification. HiGHS retains G1 MILP and general LP/linear dispatch; **HiGHS cannot solve the new conic constraints directly**.

A qualified **minimal non-commercial path** is continuous G0 SDP and G3 SOCP using a locally verified conic solver, G1 LP/MILP with HiGHS, and complete enumeration of a demonstrably finite small discrete case with fixed-integer continuous subproblems if native MISOCP is unavailable; report enumeration complexity and global certificate. Do not call a relaxed G3 optimum an integer capacity-expansion optimum. If mixed-integer cone solver works, require its MIP gap and primal status; G0 direct MISDP may remain a small continuous reference, not an unsupported general solver claim.

**Official capability references:** https://jump.dev/JuMP.jl/stable/manual/constraints/ ; https://jump.dev/JuMP.jl/stable/installation/ ; https://jump.dev/JuMP.jl/stable/packages/Clarabel/ ; https://jump.dev/JuMP.jl/stable/packages/SCS/ .

### 4.4 Independent mathematical diagnostics

Write a **solver-independent** Julia module, distinct from the JuMP constraint construction, using extracted **solved numerical** blocks and the original producer/network parameters:

1. Reconstruct \(Y^{(+)},L,B0\) from branch/shunt stamps independent of AP2/JuMP affine cache where feasible; explicitly record case scope and producer hashes.
2. Compute \(\mathcal B_t=\mathcal B^0+\operatorname{diag}b_t^{src}\); \(S_t=\operatorname{diag}p_t^{fl}\), \(M_t=\mathcal B_t-\alpha S_t\) from physical coefficients and solved `na_block`.
3. Report \(\|B_t-B_t^\top\|\), offdiag violations, component/island structure, eigenvalues/inertia/nullity, smallest \(M\) eigenvalue, \(M\mathbf1\) and scaling witnesses if used. Distinguish model/solver tolerance from independent numerical tolerance.
4. If \(S\succ0\), generalized eigen via symmetric scaling. If singular, compute finite eigenvalues using exact support Schur with PD eliminated block; if singular eliminated block, explicitly check PSD, range projector residual and Moore–Penrose Schur, or report unsupported with full-space G0 still assessed. No arbitrary \(\varepsilon\) fill.
5. If \(\mathcal B\succ0\) and inverse-positive: solve \(\mathcal B y=p\), check residual `norm(B*y-p)`, `minimum(Z)` by solves where numerically appropriate, and evaluate M0 independently. For alpha zero or B singular, explicit `undefined` status.
6. For G3: verify q orientation/edge uniqueness/cone product and node residues, exact reconstruction and independent `eigmin(M)`; infeasible solver cases cannot be treated as feasible certificates.
7. Report objective terms, investment decisions, snapshots, solver primal/dual status, mixed-integer gap, conic primal/dual feasibility, and independent cross-formulation solution feasibility. Multiple optimal portfolios may differ: **compare objectives and feasible-set membership**, not identical block vectors unless uniqueness established.

## 5. Mandatory analytic numerical regression families

Frozen rational/symbolic fixtures, not only random tests:

| ID | Input | Exact required result / false converse |
|---|---|---|
| **MATH-01** | \(\mathcal B=\begin{bmatrix}1&-1/2\\-1/2&1\end{bmatrix}\), \(p=(1/4,2/3)\), \(\alpha=1\) | \(M=\begin{bmatrix}3/4&-1/2\\-1/2&1/3\end{bmatrix}\), eigs \(0,13/12\): **G0 true**, exact G3 witness \(q_{12}=3/4,q_{21}=1/3\), **G1 false** (`M*1=[1/4,-1/6]`), \(Zp=[7/9,19/18]\): **M0 false**. T-C2A-010 and T020 positive boundary |
| **MATH-02** | Same \(\mathcal B\), \(p=(3/4,3/4)\) | Local diagonal tests true but \(eigmin(M)=-1/4\), **G0 false** |
| **MATH-03** | \(M=\begin{bmatrix}1&-0.6\\-0.6&1\end{bmatrix},r=(2,1)\) | G1 true, fixed G2(r) false |
| **MATH-04** | \(M=\begin{bmatrix}0.4&-0.6\\-0.6&1.2\end{bmatrix},r=(2,1)\) | G2(r) true, G1 false, PSD and G3 feasible |
| **MATH-05** | \(M=\begin{bmatrix}1&-1\\-1&1\end{bmatrix}\), edge q=(1,1) | Singular Laplacian **G0=G3 true**, M0 inverse undefined. Test isolated zero row separately |
| **MATH-06** | \(M=\mathbf1\mathbf1^\top\in\mathbb R^{3\times3}\) | PSD but **non-Z**, not closed SDD; no complete q edge-budget representation (trace 3 insufficient for total 6 edge-diagonal lower bound). Must not assert G0=G3 outside Z domain |
| **MATH-07** | Generalized Schur \(C=[0],B=[1],A=[1]\) | Pseudoinverse-only reduced PSD would incorrectly pass; whole 2x2 matrix indefinite because **range condition fails** |
| **MATH-08** | \(S=\operatorname{diag}(1,0)\), \(B_{zz}\succ0\), plus singular \(B_{zz}=0\) variants | Full PSD vs regular Schur vs generalized Schur/range; all-zero exposure is a distinct diagnostic |
| **MATH-09** | two disconnected Z-matrix blocks plus isolated zero row | Complete G3 edge coverage and residual checks with reducible/singular matrices |
| **MATH-10** | two- and three-bus physical Y/Schur cases, unit vs non-100 base, source diagonal + non-unit mu, connected GFL idle/zero renewable output | Independent B/S/M and correct source-base/connection semantics |

An independent NumPy elementary check at preparation (NOT a Julia conic run) reproduced MATH-01 eigenvalues approximately `[2.8e-17,1.0833333333333335]`, row sums `[0.25,-0.16666666666666663]`, `Zp=[0.7777777777777777,1.0555555555555556]`; MATH-07 full matrix eigenvalues `[-0.6180339887,1.6180339887]`. These are **fixture checks**, not AP3 runtime acceptance.

**Integrated tests (distinct from rational math):**
- Continuous same-data G0 SDP, G3 SOCP, G1 LP; G0/G3 objective equality within computed accuracy and cross-feasibility on the frozen symmetric Z domain; G1 objective may be higher (minimization) or infeasible.
- For small *integer* portfolios: properly supported MISOCP or exhaustive discrete enumeration with certified continuous subproblems; G0 vs G3 objective comparison after accounting for true gap and multiple optima.
- Positive g_min with a true cost-bearing investment, and a network-transfer-dependent case where G1 conservatism appears.
- Negative wrong-sign, dropped-edge, wrong-\(\sqrt2\), zero-row, singular-`S`, singular-`B`, fixed-source double count, inverse-zero, wrong scaling, unsupported topology/tap and conic solver-incompatibility cases.
- Preserve all AP2/legacy tests including producer synthetic LP optimal/integer infeasible results. Do **not** weaken constraints to force those negative cases feasible.

## 6. AP3 boundaries and concurrency contracts

**Included as mandatory AP3 core:**
1. Mathematical domain/predicate evaluator P001–P010 for selected accepted cases.
2. G0 continuous exact LMI builder, G3 complete exact edge-SOC builder, existing G1 baseline preserved.
3. Independent G0 generalized spectral handling with singular exposure, exact M0 post-solve burden with domain guards and non-implication evidence.
4. Solver qualification, conic continuous and small integer/reference cross-feasibility, full result manifests.
5. Complete scientific-claim-to-code/test map and AP3→A3.5 independent audit handoff.

**Not automatically in AP3:** G2 optimized scaling, M1/M2 planning constraints, Woodbury/Neumann approximations beyond verification of existing frozen counterexamples, active network/TNEP buildout, full dynamic DAE/control, AC-CPF/EMT study, SC Mvar/MVA model, external real-source/cost qualification, paper manuscript rewriting. These are separate science/extension/Strang-B/AP4 subjects unless required for a focused **diagnostic**.

**Concurrent Strang B:** Separate parameter-scenario/evidence overlay. AP3 develops against qualified synthetic mathematical fixtures and the pinned AP2 SHA, **not** unfinished empirical gates. If Strang B modifies the FlexPlan consumer, integrate only a reviewed commit delta at a clear handoff point; no common concurrently-written worktree or branch. Version pin AP1 contract, AP2 implementation and exact scenario/hash in solver manifests.

## 7. Acceptance gates and unresolved engineering decisions

| Gate | Exact pass condition | Present |
|---|---|---|
| `ap3_source_hierarchy_valid` | Full v3 mathematics + frozen theorem citations, not paper alone | **YES for specification** |
| `ap3_affine_interface_ready` | Identical B/S/M including Sbase, source and exposure maps | **AP2 qualified synthetically** |
| `ap3_g0_lmi_implemented` | Native/bridged PSD cone with independent eig checks and correct singular support | **NO** |
| `ap3_g3_closed_sdd_implemented` | Every structural edge, two q, \(\sqrt2\) RSOC, diagonal residual, full reconstruction | **NO** |
| `ap3_g0_g3_exactness_qualified` | Complete Z-domain with reducible/singular boundary and cross-feasibility/cost checks | **NO** |
| `ap3_m0_exact_postsolve` | B PD, inverse-positive verified, exact solve Zp, explicit undefined states | **NO** |
| `ap3_mixed_integer_solver_qualified` | Proven MOI MISOCP support or exhaustive tiny reference, recorded certificate/gap | **NO** |
| `ap3_domain_project_predicates_validated` | P001–P010 all required scoped checks; explicit negative rejection | **PARTIAL from AP2, not closed** |
| `ap3_existing_regression_preserved` | Re-run full code tests after AP3 changes | **Not yet re-executed** |
| `real_study_data_approved` | Strang-B scientific physical/economic/temporal source gates | **NO** |
| `A3_closed` / `AP4_ready` | Independent A3.5 closure of mathematical + code + data evidence | **NO / NO** |

**Engineering latitude for eventual AP3 worker:** Solver choice (open-source preferred for continuous verification), file/module organization, test fixture organization, faithful APIs and documentation can be resolved autonomously. The worker may use a tested mixed-integer conic backend or an auditable exact small reference enumeration; report honest capability limits rather than stop the mathematical core. **Escalate only** new/changed scientific claims, unsupported project-domain inputs requiring a scientific decision, unsafe Git changes or an irreconcilable solver licensing/availability requirement.

**Next deliverable after this AP3-A0:** one autonomous AP3 implementation macro prompt, grounded in this analysis, with a single implementation branch rooted at the pinned AP2 SHA and no AP4/Strang-B scope creep. Independent A3.5 verification remains separately owned.

## 8. References (exact paths / external APIs)

- Full mathematical chapter v3: `https://github.com/AlOussama/research-map/blob/e8118425adc335a99e85120d943763305f211315/docs/reports/C2_constraints/C2A_voltage_stability/scientific_report/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md`
- Scientific freeze: `https://github.com/AlOussama/research-map/blob/e8118425adc335a99e85120d943763305f211315/docs/reports/C2_constraints/C2A_voltage_stability/external_review/freeze/2026-08-02__c2a-scientific-formulation-freeze.md`
- Project predicates: `https://github.com/AlOussama/research-map/blob/e8118425adc335a99e85120d943763305f211315/docs/reports/C2_constraints/C2A_voltage_stability/implementation_audit/2026-07-30__c2a-project-predicate-audit.md`
- A3.3/A3.4/A3.5 required phases: `https://github.com/AlOussama/research-map/blob/e8118425adc335a99e85120d943763305f211315/docs/reports/C2_constraints/C2A_voltage_stability/publication_planning/2026-10-15__paper-a-multirepo-execution-freeze-v2.md`
- AP2: `https://github.com/AlOussama/FlexPlan.jl/tree/725de2e6c1cea21f63902474f72ec614b2358356`
- AP2 handoff: `https://github.com/AlOussama/FlexPlan.jl/blob/725de2e6c1cea21f63902474f72ec614b2358356/docs/paper_a/ap2_to_ap3_handoff.md`
- AP1: `https://github.com/AlOussama/PyPSA2MatpowerX/tree/32ff4525dc576af52c16298cb35ebd98f02cf8b2`
- JuMP PSD/RSOC APIs: `https://jump.dev/JuMP.jl/stable/manual/constraints/`
- Solver capability matrix: `https://jump.dev/JuMP.jl/stable/installation/`

**Integrity note:** The source dissertation and historical project-predicate audit were never rewritten by this AP3-A0 analysis. Any later state promotion must be scoped to exact executable AP3 SHA/test cases and distinct empirical parameter approval.

## AP3-A0 Scope Amendment — owner decision 2026-10-20

**SUPERSEDING IMPLEMENTATION SCOPE:** The narrower execution wording in this historical A0 gap analysis (especially its previously optional G2, M1/M2 and bounded inverse-approximation sections) has been **superseded** by [Comprehensive AP3 formulation, evaluation metrics and executable post-processing scope](ap3_a0_comprehensive_formulations_metrics_postprocessing_scope.md). All mathematically and computationally meaningful candidates must be implemented with their distinct guarantee classes; **all evaluation metrics and executable independent post-processing scripts are mandatory**. The original mathematics, theorems, counterexamples, source/code gaps and status observations in this A0 report remain unchanged. No solver/test/AP3 result is claimed by this documentation amendment.
