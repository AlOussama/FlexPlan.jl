# AP2 → AP3 scientific handoff — NOT READY
Date: 2026-10-19

AP3 must receive, for each snapshot, ordered retained-region metadata, independently assembled passive physical `B0_reg`, additive source-strength expressions `b_src(t)`, and GFL exposure vector `p_fl_on(t)`; form `Bt=B0_reg+diag(b_src(t))`, `St=diag(p_fl_on(t))`, `Mt=Bt-alpha*St`.

A standalone prototype of B0 Schur evaluation, online source diagonal accumulation and GFL exposure is in `src/core/paper_a_regional.jl`. It is NOT wired into FlexPlan, and AP3 must not treat it as a certified interface. Source-class provenance, physical-positive-sequence primitive Y assembly, grounding/connected islands, PSD/M-matrix predicates, and solver-owned symbolic expressions remain missing.

The exact G0 PSD, G3 edge-SOC, inverse M0 and finite generalized spectrum are AP3-owned and not implemented. In AP3, independently recompute `B0` against AP1 `B0_reference_pu` as a diagnostic, and verify theorem-domain assumptions without trusting G1-only feasibility.
