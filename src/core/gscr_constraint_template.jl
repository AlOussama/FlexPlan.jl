# Constraint template for gSCR Gershgorin sufficient condition (Task 04)
#
# Implements constraint_gscr_gershgorin_sufficient following:
#   docs/uc_gscr_block/gscr_global_lmi_and_gershgorin.md §6.

"""
    constraint_gscr_gershgorin_sufficient(pm, n_bus; nw)

Template for the LP/MILP-compatible Gershgorin sufficient gSCR condition at bus n_bus.

Equation (gscr_global_lmi_and_gershgorin.md §6, expanded form):

    σ_n^{0,G}
    + Σ_{k: ϕ(k)=n, type(k)=gfm} b_k^{block} * na_{k,t}
    ≥ g_min * Σ_{i: ϕ(i)=n, type(i)=gfl} P_i^{block} * na_{i,t}

where:
    σ_n^{0,G}       = precomputed Gershgorin diagonal dominance margin from B^0
    b_k^{block}     = per-block GFM susceptance contribution
    P_i^{block}     = p_block_max of the GFL device (online capacity per block)
    g_min           = case-level global minimum gSCR threshold
    na_{k,t}        = active block variable at snapshot t

The constraint is applied for all buses n and snapshots t.
Empty sums are permitted (buses with no GFL or no GFM devices).

Dispatches to a formulation-specific method.
"""
function constraint_gscr_gershgorin_sufficient(pm::_PM.AbstractPowerModel, n_bus::Int;
                                               nw::Int = _PM.nw_id_default)
    nw_ref = _PM.ref(pm, nw)
    sigma0 = nw_ref[:gscr_sigma0_gershgorin_margin][n_bus]
    g_min  = nw_ref[:g_min]

    gfl_ids = nw_ref[:bus_gfl_devices][n_bus]
    gfm_ids = nw_ref[:bus_gfm_devices][n_bus]

    b_block = Dict(k => _PM.ref(pm, nw, :gen, k, "b_block") for k in gfm_ids)
    p_block = Dict(i => _PM.ref(pm, nw, :gen, i, "p_block_max") for i in gfl_ids)

    constraint_gscr_gershgorin_sufficient(pm, nw, n_bus, sigma0, g_min,
                                          gfl_ids, gfm_ids, b_block, p_block)
end
