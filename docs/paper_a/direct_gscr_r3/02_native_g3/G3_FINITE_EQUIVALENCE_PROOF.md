# R3 AP2: finite-exact G3 attachment

Scope: correction of the finite implementation on pinned base a2cadc4391a3cac1ae06f9f7fc0ea88a62ef4f7e. The accepted real-arithmetic G0/G3 theorem is unchanged. This note concerns stored binary64 coefficients and actual native solver attachments.

For each retained fixed symmetric negative edge Mij, the source allocates nonnegative qij and qji and attaches the standard cone

    [qij+qji, qij-qji, 2*Mij] in SOC(3).

The exact coefficient identity is

    (qij+qji)^2 - (qij-qji)^2 - (2*Mij)^2
      = 4*(qij*qji - Mij^2).

All displayed arithmetic on coefficients uses only 0, +/-1 and multiplication by 2. The doubled edge must remain finite; overflow is rejected. There is no irrational rotation and no precomputed square of a rounded Mij. Node rows retain the original incident-q budgets. Explicit q>=0 bounds remain present. Zero edges are omitted by an exact zero test; isolated nodes retain their individual nonnegative diagonal budgets. This preserves the closed boundary and reducible cases in the previously accepted formulation.

Gurobi receives vector-slack equalities for all three cone coordinates, with the constant tail retained as a fixed affine coordinate, and an actual native quadratic row head^2-tail1^2-tail2^2>=0 with head>=0. `G3NativeReadback.jl` reads GRBgetconstrs, GRBgetqconstr, QCSense, QCRHS and actual LB/UB. It verifies the sign attached to each mapped coordinate, each exact affine equality, node rows and q bounds. Other AC quadratic rows are left untouched.

MOSEK receives an affine standard-SOC ACC. The readback queries the actual Task domain, ACC AFE indices, F rows, g, b, node rows and variable bounds. Each stored affine coordinate is compared exactly; g must be zero, and no bar variables may occur in the G3 task. This does not infer correctness from an MOI support declaration.

The readback exports native model bytes, complete actual native coefficients and a SHA-bound verdict without optimizing. Test solves are only the specified small native qualification and existing synthetic regressions. Numerical primal acceptance remains separate from the exact coefficient identity and is not an exact-feasibility certificate.

Focused fixtures cover regular and singular PSD boundaries, reducible and isolated components, exact feasible and near-infeasible allocations, negative endpoints, a deliberately faulty undoubled tail, and the historical rotation a=1592262918131443/2251799813685248 with 2*a^2<1. A native negative control perturbs the fixed-tail equality by one binary64 step and separately removes one q nonnegativity bound; the readback must reject both.

Validation logs: ../logs/g3_finite_tests_final.log and ../logs/g3_dcp_ap3_regression_final.log. Whole-week actual native readbacks and their scope are supplied by the parent bundle; small fixtures alone do not qualify all weekly AC models.

Final targeted validation: 152/152 focused tests and 360/360 existing DCP/AP3 and added-GFL regressions passed. Native q bounds must equal lower zero with no upper bound; Gurobi SOC head bounds likewise equal zero/+infinity. Wrong fixed-tail equality, relaxed or tightened q lower bounds, and capped q upper bounds are rejected by actual-native readback. The precise test counts and SHA bindings are in SMALL_BACKEND_QUALIFICATION.json.
