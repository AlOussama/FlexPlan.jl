# FlexPlan UC/gSCR Block-Expansion Project Package v2

This package prepares a clean, reviewed implementation of block-based generator/storage expansion and full-network gSCR/ESCR security constraints in a FlexPlan/PowerModels-style Julia codebase.

## Main decisions

1. Implementation base: FlexPlan / PowerModels architecture.
2. CbaOPF is used only as a conceptual reference for inertia conventions, not as the implementation base.
3. The full original network is used. No Kron-reduced network is introduced.
4. The operational commitment variable is \(n_{a,k,t}\), the number of active/online blocks of device \(k\) at time/network \(t\).
5. Grid control mode is physical interface data: `grid_control_mode = "gfl"` or `grid_control_mode = "gfm"`.
6. First implementation uses `relax = true`, so \(n\) and \(n_a\) are continuous.
7. Integer block commitment is a follow-up through `relax = false`.
8. Two gSCR variants are documented:
   - global full-network SDP/LMI;
   - linear Gershgorin sufficient condition.
9. Every new function must have a docstring.
10. Every generated code change must be reviewed, tested, and traceable to a documented equation.

## Start

Read:

```text
docs/project_start/START_HERE.md
docs/tests/flexplan_test_data_plan.md
docs/review_workflow/documentation_quality_requirements.md
```

Then start Codex with:

```text
codex_tasks/01_reference_extension.md
```
