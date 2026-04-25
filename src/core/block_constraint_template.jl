# Constraint templates for block dispatch and storage (Task 03)
#
# Implements:
#   constraint_installed_block_bounds
#   constraint_block_active_power_dispatch
#   constraint_block_reactive_power_dispatch
#   constraint_storage_block_energy_capacity
#
# Following docs/block_expansion/mathematical_formulation.md §5–7.

"""
    constraint_block_active_power_dispatch(pm, k; nw)

Template for active-power dispatch bounds scaled by the active block count.

Equation (formulation §5):
    p_k^{block,min} * na_{k,t} ≤ p_{k,t} ≤ p_k^{block,max} * na_{k,t}

Dispatches to a formulation-specific method.
"""
function constraint_block_active_power_dispatch(pm::_PM.AbstractPowerModel, k::Int;
                                                nw::Int = _PM.nw_id_default)
    gen = _PM.ref(pm, nw, :gen, k)
    p_min = gen["p_block_min"]
    p_max = gen["p_block_max"]
    constraint_block_active_power_dispatch(pm, nw, k, p_min, p_max)
end

"""
    constraint_block_reactive_power_dispatch(pm, k; nw)

Template for reactive-power dispatch bounds scaled by the active block count.

Equation (formulation §6):
    q_k^{block,min} * na_{k,t} ≤ q_{k,t} ≤ q_k^{block,max} * na_{k,t}

For active-power-only formulations, no constraint is added (no-op method).
Dispatches to a formulation-specific method.
"""
function constraint_block_reactive_power_dispatch(pm::_PM.AbstractPowerModel, k::Int;
                                                   nw::Int = _PM.nw_id_default)
    gen = _PM.ref(pm, nw, :gen, k)
    q_min = gen["q_block_min"]
    q_max = gen["q_block_max"]
    constraint_block_reactive_power_dispatch(pm, nw, k, q_min, q_max)
end

"""
    constraint_storage_block_energy_capacity(pm, k; nw)

Template for block storage energy capacity.

Equation (formulation §7):
    0 ≤ e_{k,t} ≤ n_k * e_k^{block}

Energy capacity scales with the installed block count n_k, not the active count.
Dispatches to a formulation-specific method.
"""
function constraint_storage_block_energy_capacity(pm::_PM.AbstractPowerModel, k::Int;
                                                   nw::Int = _PM.nw_id_default)
    gen = _PM.ref(pm, nw, :gen, k)
    e_block = gen["e_block"]
    constraint_storage_block_energy_capacity(pm, nw, k, e_block)
end
