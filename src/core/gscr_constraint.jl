# Formulation-specific gSCR Gershgorin constraint (Task 04)
#
# Each method states which formulation family it targets.

"""
    constraint_gscr_gershgorin_sufficient(pm::AbstractPowerModel, n, n_bus,
                                          sigma0, g_min, gfl_ids, gfm_ids,
                                          b_block, p_block)

Implements the LP/MILP-compatible per-bus Gershgorin sufficient condition for all
formulations (formulation-independent: uses only na_block variables).

Equation (gscr_global_lmi_and_gershgorin.md §6):

    σ_n^{0,G}
    + Σ_{k ∈ gfm_ids} b_k^{block} * na_{k,t}
    ≥ g_min * Σ_{i ∈ gfl_ids} P_i^{block} * na_{i,t}

Arguments:
- `n`       : multinetwork id (time snapshot)
- `n_bus`   : bus id
- `sigma0`  : precomputed σ_n^{0,G} (scalar Float64)
- `g_min`   : global minimum gSCR threshold (scalar Float64)
- `gfl_ids` : collection of GFL device ids connected to bus n_bus
- `gfm_ids` : collection of GFM device ids connected to bus n_bus
- `b_block` : Dict k => b_k^{block} for GFM devices
- `p_block` : Dict i => P_i^{block,max} for GFL devices

Empty sums are explicitly handled (buses with only GFL, only GFM, or neither).

Targets: any `AbstractPowerModel`.
"""
function constraint_gscr_gershgorin_sufficient(pm::_PM.AbstractPowerModel,
                                               n::Int, n_bus::Int,
                                               sigma0::Real, g_min::Real,
                                               gfl_ids, gfm_ids,
                                               b_block::Dict, p_block::Dict)
    na = _PM.var(pm, n, :na_block)

    gfm_sum = isempty(gfm_ids) ? 0.0 :
              sum(b_block[k] * na[k] for k in gfm_ids)

    gfl_sum = isempty(gfl_ids) ? 0.0 :
              sum(p_block[i] * na[i] for i in gfl_ids)

    JuMP.@constraint(pm.model, sigma0 + gfm_sum >= g_min * gfl_sum)
end
