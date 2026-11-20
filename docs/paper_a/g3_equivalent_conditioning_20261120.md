# G3_NUMERIC_01_EQUIVALENT_CONDITIONING_FINAL_HANDOFF

**Endurteil:** tatsächlicher SOCP-Originalpunkt **NEGATIVE**, MISOCP
**NOT_EXECUTED**. Die äquivalente Konditionierung und der korrigierte
Übergabepfad sind bis zur tatsächlichen nativen Modellabbildung geprüft.
Ihre numerische Wirksamkeit wurde nicht erprobt: Der eine Solverstart ging
wegen des inzwischen behobenen Scope-Fehlers an das Originalmodell.

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

## Targeted numerical diagnosis

The two original rejected vectors have substantially different failing row
families. The first worst row is a reservoir SOC equality; the second worst
row is `n_active(gen207) <= n_inst(gen207)` in snapshot 12. Its error is in
block counts, not MW. The second vector also violates 243 G3 node budgets.
All 8,736 cone polynomials can hold while these other constraints fail.

| Coordinates or rows | Observed original magnitude / range |
|---|---:|
| New renewable capacity | Up to about 248,630 MW; bound about 1,650,943 MW |
| Reservoir SOC | Up to about 420,272 pu-h; bound about 838,600 pu-h |
| G3 q | About 0.046 to 2,732 |
| Block counts | Up to about 1,848; bound about 10,977 |
| Original nonzero affine coefficients | 8.419356e-8 to 3,031.803672 |
| Dyadically transformed affine coefficients | 6.735485e-7 to 47.371932 |

The original affine coefficient ratio is about 3.60e10; the transformed ratio
is about 7.03e7. Large reservoir levels relative to hourly changes and mixed
MW/pu/block coordinates are concrete conditioning concerns. They are not a
proved unique cause of barrier failure. The two earlier native models have
the same fingerprint despite different solver parameter experiments. Their
suboptimal termination occurred before the time limit; extra time alone is
not demonstrated to remedy the residuals.

The independent symbolic audit checks all 756,257 actual original constraints
and 1,617,411 terms. The actual native map contains 363,811 variables, 461,235
linear rows and 8,736 quadratic cones. Of its 34,944 auxiliary columns, 8,736
come from existing interval representations and 26,208 from cone vector
slacks. Endpoint nonnegativity, every quadratic sense, native objective
coefficients and objective constant were checked. The original fixed Float64
cone constants and all original discrete coordinate domains are preserved.

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

The implementation commit is `773d16df2ece04c01c90781fdfcd6089ef8382de`;
the routing repair is `4719e08c153d7b387840260dec0561ff6488da43`.
Both were pushed normally to `codex/paper-a-q5-digest-139`. The 43 analytical
assertions and 14 actual-runner scope/routing assertions pass. The deliberate
old-scope negative fixture produces a warning; it is not the repaired runner.

Independent full replay of the newly saved actual original vector reproduces
4,278 violations over 1e-6 and 20,430 over 1e-7, with maximum 1.944473e-4.
Its complete vector is byte-identical to the earlier rejected baseline.
Original physical failures therefore remain, including reservoir SOC error
about 0.0194447 MWh and nodal balance error about 0.0081721 MW. Native cone
polynomial feasibility does not override these failures. The final actual
SOCP original-point gate is **NEGATIVE**, SHA
`d0e70318d398ed7c859451d569311b999e56683ff19e51d60e504c468da2cfad`.

The resource monitor records 1,729 samples, peak private memory 4,301,619,200
bytes, maximum monitoring gap 0.266 s, and no resource guard. These measurements
cover the actual unscaled call and interrupted export; they do not establish
the resource fit of a conditioned optimization or a full year.

One actual native Fullcase call is counted, zero qualified conditioned calls.
There is no hidden retry. Further fixed-week validation of the routing repair
is profile/native-attachment only, without `optimize!`. Numerical efficacy of
the conditioning remains untested. MISOCP remains blocked; a new numerical
attempt requires a new bounded attempt allocation.

## Independently checked routing repair without a second solve

The repaired fixed-week profile is
`c8a34e36a72273228f2b64b27e6d7483bae4561f2dd241d02fff4dbad0554dce`;
the actual misrouted attempt profile is
`25dae3fa305aa348991de45ff1ebe5d18c3f79e85a2c82c5adaf09b19b0b1982`.
The input profile remains `7e043c288061a828e5ab69fddcc5055b7d2afd7b16545b63d78ba097c53880ff`.
The prepared in-memory model has the distinct derived profile
`f5bddb1817bcd31cff3cc7068685c7b2b35ffcc5cd97c680cfdfb22c04e8cb0c`;
it is not substituted for the frozen input identity.

The actual repaired runner selects the nonnull scaled model and rejects the
original model. Its complete native linear/quadratic/objective representation
is byte-identical to the independently qualified scaled representation:
SHA-256 `5dbbffef606cd987b383c20a080ca02ef462bebd67f1451058b0eed723a9f50b`.
Native status is `LOADED` (1), `SolCount=0`, runtime 0 and MOI
`OPTIMIZE_NOT_CALLED`; no optimization window exists. This is a native
attachment check, not a second numerical attempt or a feasible solution.

The independently reviewed mathematical repair receipt is
`bae3eda142f5bfe22b2a1fb4990889db6e29c85cd73f4d8e59a0e7b2543261ff`.
The compact index binds both independent repair reviews, the actual negative
point reviews, revoked admissions and all retained original evidence.

## Stop criterion and remaining scope

A missing/misrouted copy or differing actual coefficient profile blocks
optimization. A new SOCP point must pass the unchanged original maximum
constraint/cone-polynomial tolerance of 1e-7 plus independent mathematical and
physical QA. MISOCP requires both positive original-point reviews. No cost,
gap or bound is reported as a G3 result before that acceptance.

`G3-RUNNER-SCOPE` is closed by the source repair and actual no-solve native
mapping. `G3-NUMERIC-01` remains open because conditioned solver performance
has not been tested. The only continuation decision needed is an additional
bounded Fullcase attempt allocation. No physical limit, model assumption,
price, original data or feasibility-tolerance decision is requested.

All large artifacts remain on E:. The Producer is unchanged at
`becec6d63c0fbf2b8a160c41f87631f5270046b9`; its protected Q4 file/diff hashes
match the previous receipts. Historical failed attempts, inputs and reviewer
receipts remain intact. No additional worktree, backup, cleanup or deletion
was performed.

Final receipt SHAs are recorded in the
[compact handoff index](receipts/g3_equivalent_conditioning_final_handoff_20261120.json).
No new annual Full37, Gate J, F3, AC, dynamics or publication approval is implied.
