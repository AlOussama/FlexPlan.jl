---
applyTo: "src/**/*.jl"
---

For Julia implementation files:

- Follow the mathematical formulation in `docs/block_expansion/` and `docs/uc_gscr_block/`.
- Use PowerModels/FlexPlan multiple dispatch.
- Do not hard-code DCP assumptions in generic functions.
- Every new function must have a docstring.
- Every constraint-template docstring must name the equation it implements.
- Every formulation-specific method must state which formulation family it targets.
- Do not introduce reduced-network variables.
- Do not introduce `Y_t` or `B_t` optimization variables for the LP/MILP gSCR constraint.
- Use `na` as the active/online block variable.
- Preserve backward compatibility for cases without block fields.