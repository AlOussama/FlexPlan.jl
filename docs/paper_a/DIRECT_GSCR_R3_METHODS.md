# Direct gSCR R3 implementation and evidence contract

R3 is the owner's `DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3` continuation of the
independent R2 review at base `a2cadc4391a3cac1ae06f9f7fc0ea88a62ef4f7e`.
It authorizes the specific implementation repairs below, new model builds and
native exports without weekly optimization, small fixtures, and publication.
The archived cases, points, certificates and R1/R2 evidence remain immutable.

## Exact finite native strength transmission

The new weekly G0 MOSEK route removes the default `SetDotScalingBridge`.
An unscaled symmetric matrix variable Y is constrained PSD and linked to each
original affine M entry by scalar equalities. This avoids a rounded sqrt(2)
svec transformation. `NativeStrengthReference.jl` writes a native task, reopens
that file and reads the actual bar dimensions, bar-A triplets, complete scalar
linking rows and bounds. It checks the absence of bar terms in AFE rows and in
the objective. The independent verifier compares all original affine terms and
constants as exact binary rational numbers: offdiagonal trace coefficients
are doubled. Every hour has all 703 upper triangle entries, giving 118104
entries across 168 blocks of order 37 for each network formulation. A newly
qualified transmission does not prove identity of a missing historical task.

G3 uses the standard SOC `[q1+q2,q1-q2,2*Mij]`, with q1,q2 nonnegative and the
original node budgets. Its determinant identity is
`(q1+q2)^2-(q1-q2)^2-(2*Mij)^2 = 4*(q1*q2-Mij^2)`.
Only exact binary coefficients ±1 and 2 occur. Native affine slack equalities
retain the fixed last coordinate; it is not squared into a rounded constant.
`G3NativeReadback.jl` checks the actual Gurobi linear rows, bounds and unit
diagonal quadratic rows, or actual MOSEK ACC/domain/AFE coordinates and bounds.
The algebraic theorem for fixed symmetric Z edges is reused from the accepted
method; R3 does not replace or re-prove that theorem.

## Replay integrity and original constraints

Python replay requires an explicit input manifest frozen in a separate step
before evaluation. It binds the primal, native model, mapping, every matrix
and physical ledger, case, evaluator and external physical inputs. Missing,
changed, duplicate, incomplete or nonfinite inputs fail closed. Replay writes
to a fresh output directory and checks the manifest again after evaluation.
The Julia replay entry point likewise requires an explicit manifest and a
separate output directory.

Before solver transformations, the Julia audit freezes the original constraint
roster and preserves each changed or deleted original function and set.
`native_solver_audit.json` reports the transferred solver model;
`original_model_audit.json` evaluates all original rows, including original
unscaled angles and deleted QCRM currents. A solver-only or in-place scaled
audit never issues GOLD acceptance. Every numerical point claim also requires
the bound original native and physical replay evidence.

## Scientific scope

Historical exact lower-bound certificates and F02's actual outer-LP/QCRM
projection proof are reused unchanged. Targeted deltas bind the new model to
those inputs. Numerically qualified points are not rigorously exact feasible
upper bounds. In particular the LPAC G0 witness retains its numerical PSD
tolerance qualification (hour 108 approximately -2.237e-10). The old LPAC G3
point remains `SENSITIVITY_ONLY — NOT_GOLD_UB` unless a separate full original
GOLD audit passes. No integer-optimality, exact AC-feasibility or dynamical
stability claim follows from this continuous scenario study.

## Reproduction

Use Julia 1.11.5 with the committed Julia 1.11 manifest. Set E: output and
depot/temp paths explicitly. `scripts/paper_a/run_r3_native_references.ps1`
builds and exports the three G0 and six G3 weekly reference models without
calling `optimize!`. Use a fresh E: output root. The bundle's runtime manifest
and reproduction commands bind actual versions, commands, source hashes,
parameters and all evidence paths. Large native files remain on E:; compact
verdicts and the final handoff are published in the development branch.
