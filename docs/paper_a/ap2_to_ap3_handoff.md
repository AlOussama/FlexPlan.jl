# Paper A AP2 to AP3 interface

This is an interface handoff for qualified AP1 cases, not acceptance of AP3, G0/G3/M0, or a real study. Overall AP2 closure remains conditional on the external producer/data gates in the validation report.

`ref_add_uc_gscr_block!` creates for every AP1 snapshot:

- `ref[:paper_a_regional]`: named tuple with stable `ac_order`, `retained`, `eliminated`, `regions`, `bus_to_region`, independently assembled complex `Y`, real `L`, reduced `B0`, `b_fix`, AC `islands`, `schur_residual`, `B0_reference_residual`, and matrix-domain predicate `theorem_domain_valid`.
- `ref[:paper_a_coefficients]`: compound asset keys `(table,id)` mapped to `(region,strength,exposure)`. Region is a one-based index in retained order. Strength is `mu_str*b_block`; exposure is `mu_fl*P_block_MW/Sbase`, each applied to `na_block`. Fixed-in-Y sources have zero additional coefficient. Physical SYN devices have their own `:syn_devices` map.
- `ref[:paper_a_temporal]`: physical `delta_t_h`, effective `dispatch`, effective `event`, and `probability`; these weights do not enter storage state physics.

After the existing block variable builder, `pm.ext[:paper_a_online][nw]` contains:

| Field | Meaning |
|---|---|
| `regions` | Regional order, equal to reference retained order |
| `b_src` | Affine b_fix plus online source contributions |
| `p_fl` / `S_diag` | Affine common-base GFL online-nameplate exposure |
| `B` | Affine B0 plus source diagonal |
| `M` | Affine B-g_min*diag(p_fl), when a numeric threshold is supplied |

These are actual builder expressions, not post-hoc helper reconstructions. They exist for `NoGSCR` as well as G1; `M` is `nothing` without a declared threshold. AP3 must consume the same B/S/M for all its formulations and retain compound keys and explicit common base.

In the AP2 positive-threshold synthetic tests, expression values are compared with independent physical coefficient calculations. Actual nonempty passive elimination is exercised in a solved integrated model as well as an analytical 3-bus reference. `B0_reference_pu` is never the authoritative input; its difference is reported separately.

Reference failures are explicit exceptions, so an invalid case has no usable handoff object. Missing producer files/evidence are recorded by the external fixture gate with BLOCKED/NOT_EXECUTED status. Transformer conversion, dedicated SC treatment, unknown native bases, unverified grounding, fixed-source binding gaps and unsupported storage cost rules are not silently filled in.

The `theorem_domain_valid` reference field concerns the verified matrix/input domain only. It does not certify all feasible decision states or external source/economic validity. G1 is sufficient; AP2 supplies no exact G0 or G3 certificate, generalized eigenvalue, inverse-load metric or independent AP3 acceptance. `A3_closed=false`, `AP4_ready=false`.

## Final AP1 amendment validation

The regional reference also exposes common `S_base_MVA`, `symmetric_z_valid` and the unchanged producer `passive_domain_issues`. The model reference records `paper_a_validation_scope`. The final producer at `32ff4525…` is consumed by `test/run_paper_a_ap1_acceptance.jl`: actual 3/6/24 LP solves validate the affine B/S/M interface; the integer variants are explicitly reported infeasible. These executions use the template's explicit synthetic mathematical scope, not a real-study waiver. Its unresolved producer evidence stays visible and `theorem_domain_valid` stays false. Real fixtures are structurally imported and strictly refused for strength-study use until their source/economic gates are resolved. All six passive B0 comparisons are zero.
