# Copilot Instructions

This repository implements FlexPlan/PowerModels-style block expansion and full-network gSCR/ESCR security constraints.

When suggesting or reviewing code:

1. Preserve the equations in `docs/block_expansion/` and `docs/uc_gscr_block/`.
2. Use the full non-reduced network.
3. Do not introduce reduced-network variables.
4. Do not introduce data-driven linearization.
5. The operational block variable is `na`.
6. Device type is data: `gfl` or `gfm`.
7. Use \(B^0\), the real full-network susceptance matrix.
8. The LP/MILP gSCR constraint is:
   `gscr_sigma0_gershgorin_margin[n] + sum(b_block[k] * na[k,t] for gfm at n) >= g_min * sum(P^{block}[i] * na[i,t] for gfl at n)`.
9. The global gSCR constraint is an SDP/LMI:
   `B_t - g_min*S_t >= 0` in PSD sense.
10. Start with `relax=true`; keep `relax=false` ready for integer follow-up.
11. Use PowerModels multiple dispatch. Do not hard-code DCP assumptions in generic functions.
12. Cases without block fields must remain backward compatible.
13. Every implementation PR must include tests.
14. Every new function must have a docstring.
