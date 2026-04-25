# Block variables for UC/gSCR expansion (Task 02)
#
# Implements the installed block variable n (shared across time-snapshots) and
# the active/online block variable na (per snapshot), following:
#   docs/block_expansion/mathematical_formulation.md §1–3.

"""
    variable_block_installed(pm; nw, relax, report)

Add the installed block variable n_k for each gen device k that carries block fields.

Bounds (equation 2 in the formulation):
    n_k^0 ≤ n_k ≤ n_k^{max}

The variable is created only in the first time snapshot
(`first_id(pm, nw, :hour, :scenario)`) and aliased in subsequent snapshots so
that it is shared across the multinetwork horizon.

Key: `:n_block`

`relax=true`  → continuous variable (LP).
`relax=false` → integer variable (MILP).
"""
function variable_block_installed(pm::_PM.AbstractPowerModel;
                                   nw::Int = _PM.nw_id_default,
                                   relax::Bool = true,
                                   report::Bool = true)
    first_n = first_id(pm, nw, :hour, :scenario)

    if nw == first_n
        block_ids = _ids_with_block_fields(pm, nw)

        if !relax
            n_blk = _PM.var(pm, nw)[:n_block] = JuMP.@variable(pm.model,
                [k in block_ids], base_name = "$(nw)_n_block",
                integer = true,
                lower_bound = _PM.ref(pm, nw, :gen, k, "n0"),
                upper_bound = _PM.ref(pm, nw, :gen, k, "nmax"),
            )
        else
            n_blk = _PM.var(pm, nw)[:n_block] = JuMP.@variable(pm.model,
                [k in block_ids], base_name = "$(nw)_n_block",
                lower_bound = _PM.ref(pm, nw, :gen, k, "n0"),
                upper_bound = _PM.ref(pm, nw, :gen, k, "nmax"),
            )
        end
    else
        # alias: share variable from the first snapshot
        n_blk = _PM.var(pm, nw)[:n_block] = _PM.var(pm, first_n)[:n_block]
    end

    if report
        _PM.sol_component_value(pm, nw, :gen, :n_block,
            collect(keys(_PM.var(pm, nw)[:n_block])), n_blk)
    end
end

"""
    variable_block_active(pm; nw, relax, report)

Add the active/online block variable na_{k,t} for each gen device k that
carries block fields, for network snapshot t = nw.

Bounds (equation 3 in the formulation):
    0 ≤ na_{k,t} ≤ n_k

The variable is per-snapshot and bounded above by the (shared) installed
variable n_block from the same scenario.

Key: `:na_block`

`relax=true`  → continuous variable (LP).
`relax=false` → integer variable (MILP).
"""
function variable_block_active(pm::_PM.AbstractPowerModel;
                                nw::Int = _PM.nw_id_default,
                                relax::Bool = true,
                                report::Bool = true)
    block_ids = _ids_with_block_fields(pm, nw)
    n_blk     = _PM.var(pm, nw, :n_block)

    if !relax
        na_blk = _PM.var(pm, nw)[:na_block] = JuMP.@variable(pm.model,
            [k in block_ids], base_name = "$(nw)_na_block",
            integer = true,
            lower_bound = 0,
        )
    else
        na_blk = _PM.var(pm, nw)[:na_block] = JuMP.@variable(pm.model,
            [k in block_ids], base_name = "$(nw)_na_block",
            lower_bound = 0.0,
        )
    end

    # na_{k,t} ≤ n_k  (implemented as constraint to allow n_block to be variable)
    for k in block_ids
        JuMP.@constraint(pm.model, na_blk[k] <= n_blk[k])
    end

    if report
        _PM.sol_component_value(pm, nw, :gen, :na_block, block_ids, na_blk)
    end
end

"""
    _ids_with_block_fields(pm, nw) -> Vector{Int}

Return the ids of gen entries in network `nw` that carry the block expansion
fields `"n0"` and `"nmax"`. Returns an empty vector if none exist, preserving
backward compatibility for cases without block fields.
"""
function _ids_with_block_fields(pm::_PM.AbstractPowerModel, nw::Int)
    return [k for (k, gen) in _PM.ref(pm, nw, :gen)
            if haskey(gen, "n0") && haskey(gen, "nmax")]
end
