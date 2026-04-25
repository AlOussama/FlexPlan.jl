# Formulation-specific block dispatch and storage constraints (Task 03)
#
# Each method states which formulation family it targets.

# ── Active-power dispatch ──────────────────────────────────────────────────────

"""
    constraint_block_active_power_dispatch(pm::AbstractPowerModel, n, k, p_min, p_max)

Implements active-power dispatch bounds for all formulations:

    p_k^{block,min} * na_{k,t} ≤ p_{k,t} ≤ p_k^{block,max} * na_{k,t}

Targets: any `AbstractPowerModel` (formulation-independent active-power bound).
"""
function constraint_block_active_power_dispatch(pm::_PM.AbstractPowerModel,
                                                n::Int, k::Int,
                                                p_min::Real, p_max::Real)
    pg   = _PM.var(pm, n, :pg, k)
    na   = _PM.var(pm, n, :na_block, k)
    JuMP.@constraint(pm.model, pg >= p_min * na)
    JuMP.@constraint(pm.model, pg <= p_max * na)
end

# ── Reactive-power dispatch ────────────────────────────────────────────────────

"""
    constraint_block_reactive_power_dispatch(pm::AbstractPowerModel, n, k, q_min, q_max)

Implements reactive-power dispatch bounds for AC (full-power) formulations:

    q_k^{block,min} * na_{k,t} ≤ q_{k,t} ≤ q_k^{block,max} * na_{k,t}

Targets: `AbstractPowerModel` (AC and related formulations with reactive power).
"""
function constraint_block_reactive_power_dispatch(pm::_PM.AbstractPowerModel,
                                                   n::Int, k::Int,
                                                   q_min::Real, q_max::Real)
    qg  = _PM.var(pm, n, :qg, k)
    na  = _PM.var(pm, n, :na_block, k)
    JuMP.@constraint(pm.model, qg >= q_min * na)
    JuMP.@constraint(pm.model, qg <= q_max * na)
end

"""
    constraint_block_reactive_power_dispatch(pm::AbstractActivePowerModel, n, k, q_min, q_max)

No-op for active-power-only formulations (DC, LP).

Targets: `AbstractActivePowerModel` (DCP and related).
"""
function constraint_block_reactive_power_dispatch(pm::_PM.AbstractActivePowerModel,
                                                   n::Int, k::Int,
                                                   q_min::Real, q_max::Real)
    # no reactive power variable in active-power-only formulations
    return nothing
end

# ── Storage energy capacity ────────────────────────────────────────────────────

"""
    constraint_storage_block_energy_capacity(pm::AbstractPowerModel, n, k, e_block)

Implements the block storage energy capacity constraint for all formulations:

    0 ≤ e_{k,t} ≤ n_k * e_k^{block}

Energy capacity scales with the installed block count n_k (not the active count).
The storage energy variable is `:se` (existing FlexPlan/PowerModels convention).

Targets: any `AbstractPowerModel`.
"""
function constraint_storage_block_energy_capacity(pm::_PM.AbstractPowerModel,
                                                   n::Int, k::Int,
                                                   e_block::Real)
    se  = _PM.var(pm, n, :se, k)
    nk  = _PM.var(pm, n, :n_block, k)
    JuMP.@constraint(pm.model, se >= 0)
    JuMP.@constraint(pm.model, se <= e_block * nk)
end
