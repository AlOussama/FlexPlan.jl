# G3-NUMERIC-01: bounded equivalent conditioning

Authority: S-GOV-G3-NUMERIC-01, starting consumer
`a36414fbefba6dc3e414d0c63f3de450df274885`. The frozen 168-hour KW8/70% case
is `1ceb274ab48bf2e4f90783fa881d394c79fb216d311c6bde197c6fe77dbbb15d`,
profile `7e043c288061a828e5ab69fddcc5055b7d2afd7b16545b63d78ba097c53880ff`.
The frozen-E proxy, physical bounds, UC, quota, CAPEX and 8760/168 OPEX
weighting remain unchanged. Gurobi is the selected solver.

## Numerical contract

The original model remains the acceptance model. An optional solver copy uses
`x_j = 2^d_j y_j` and positive row factors `2^r_i`. All 111,401 original
discrete coordinates have `d_j=0`, also when solving the continuous relaxation.
For other bounded columns, `d=clamp(ceil(log2(max(1,|finite bounds|)/128)),0,7)`.
Unbounded G3-q columns use their fixed original edge-cone constant instead of
a candidate value. No candidate is used as a start or as a capacity bound.

Affine rows use `r=clamp(-round(log2(max|A_ij 2^d_j|)),-6,20)`; zero rows use
zero. Each original RSOC receives a single common positive factor, selected
using the maximum transformed coefficient and fixed constant. Variable bounds
are divided by their column factor. These operations preserve the real
feasible set and the original integer lattice. Every Float64 coefficient,
constant, finite bound and RHS is checked by inverse `ldexp`; stored JuMP
constraint functions and sets are compared against the checked construction.
Unsupported functions, offset endpoints, underflow and overflow fail closed.

The actual original RSOC constant is the stored Float64 `sqrt(2)*M_ij`.
Replacing its square with an idealized `2*M_ij^2` is deliberately avoided.
The existing exact RSOC-to-quadratic MOI bridge and proved nonnegative native
endpoint bounds are reused. Objective division remains exactly 8192.

The result projection performs no native solve. It returns actual solver
statuses, objective and bound, with every primal variable mapped back to x.
Dual status is unavailable. The existing `NativeG3Solver.primal_check`, AP3
extraction and original constraints are unchanged. Original tolerance remains
1e-7. Native row tolerance can amplify by 64 and bound error by 128; cone
polynomial error has a squared scaling factor. Only the actual original-point
check and independent reviewers can accept a candidate.

Enable only with `PAPER_A_G3_EQUIVALENT_CONDITIONING=1`. Existing G1/G2 and
unconditioned routes retain their existing behavior. The existing case can be
read in place through `PAPER_A_STRENGTH_EXISTING_CASE_DIR`; it is not rewritten.

## Evidence and execution boundary

E-only output root:
`E:/ResearchResults/FlexPlan_UC_GSCR/G3_NUMERIC_01_EQUIVALENT_CONDITIONING_20261120_01`.
It contains all original/scaled constraints, column maps, actual native CSR
and quadratic model, known-reference values and unchanged original residuals.

The complete original replay reproduces exactly 4,278 and 61,616 violations
over 1e-6 at the two rejected points. At 1e-7 the counts are 20,430 and 114,191.
The accepted G2 point with its existing G3 witness passes all 8,736 original
cone polynomials (maximum violation 1.819e-11). Its complete rebuilt G3 model
has one quota-row Float64 residual of 3.72529e-7, within its original G2
1e-6 acceptance scope, exceeding the stricter G3 1e-7 check. This is retained
as evidence, not silently relabelled a full strict G3 PASS or repaired.

Exactly one newly conditioned Fullcase SOCP solve is authorized after the
analytical, symbolic and actual-native mapping reviews. MISOCP requires an
independent positive SOCP original-point gate. A negative result ends this
bounded numerical recovery; no general parameter sweeps follow.

## Actual attempt and technical routing correction

The single actual native call under `773d16df2ece04c01c90781fdfcd6089ef8382de`
submitted the original model. A noninteractive Julia top-level `try` created
a local `conditioned_copy`, leaving the outer binding `nothing`. The profile
therefore described the correct transformed copy, while the solve branch
selected the untransformed model. The explicit scope warning and native old
matrix ranges/fingerprint independently confirm this integration defect.
The initial reviewer admission is revoked for the actual submission. Algebraic
equivalence proofs and the analytical scaling tests retain their own scopes.

Gurobi finished its unscaled solve after 190.375 s with suboptimal termination.
The exact task worker was terminated after that native finish, interrupting
the remaining candidate export. The saved full primal is retained; its
coordinate file is empty and the final run summary/completion marker is absent.
No accepted G3 costs or bounds are derived from this incomplete, misrouted run.

The source repair explicitly assigns the global copy, rejects a missing copy
before publishing a ready profile, and checks solver-model identity and actual
coefficient range immediately before optimization. A noninteractive test
executes the actual runner's `try` and preopt guard blocks, including missing
copy, range mismatch and the original soft-scope regression. This closes a gap
left by the initial module-level tests.

One actual native Fullcase call is counted, zero qualified conditioned calls.
There is no hidden retry. Further fixed-week validation of the routing repair
is profile/native-attachment only, without `optimize!`. Numerical efficacy of
the conditioning remains untested. MISOCP remains blocked; a new numerical
attempt requires a new bounded attempt allocation.

Final receipt SHAs are recorded in the accompanying compact handoff index.
No new annual Full37, Gate J, F3, AC, dynamics or publication approval is implied.
