"""
    variable_uc_gscr_block(pm; nw=nw_id_default, relax=false, report=true)

Creates the UC/gSCR installed and active block variables for network `nw`.

This adds installed block counts `n_block[k]` satisfying
`n0[k] <= n_block[k] <= nmax[k]`, active block counts `na_block[k,t]`
satisfying `0 <= na_block[k,t]`, and the linking constraint
`na_block[k,t] <= n_block[k]`. The installed count is shared across all
network snapshots; the active count is specific to `nw`.

The argument `relax` selects continuous variables when `true` and integer
variables when `false`. Block counts are dimensionless. This helper is
formulation-independent and mutates the JuMP model plus PowerModels variable
and constraint dictionaries.
"""
function variable_uc_gscr_block(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, relax::Bool=false, report::Bool=true)
    variable_installed_blocks(pm; nw, relax, report)
    variable_active_blocks(pm; nw, relax, report)
    constraint_active_blocks_le_installed(pm; nw)
end

"""
    variable_installed_blocks(pm; nw=nw_id_default, relax=false, report=true)

Creates the installed UC/gSCR block variable `n_block`.

For each UC/gSCR block device `k`, this implements the bound
`n_k^0 <= n_block[k] <= n_k^max` using `n0` and `nmax` from the reference
extension. The variable is shared across all network snapshots by creating it
on the first network id and aliasing the same container into later network
refs.

The argument `relax` selects continuous variables when `true` and integer
variables when `false`. Block counts are dimensionless. When `report=true`,
each `n_block[k]` variable ref is written into the PowerModels solution dict
under the device component table so downstream solution processors can extract
solved values. This function is formulation-independent and mutates the JuMP
model plus PowerModels variable and solution dictionaries.
"""
function variable_installed_blocks(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, relax::Bool=false, report::Bool=true)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    first_nw = first(nw_id for nw_id in nw_ids(pm) if _has_uc_gscr_block_ref(pm, nw_id))
    device_keys = _uc_gscr_block_device_keys(pm, nw)

    if nw == first_nw
        if haskey(_PM.var(pm, nw), :n_block)
            return
        end
        if relax
            _PM.var(pm, nw)[:n_block] = JuMP.@variable(pm.model,
                [device_key in device_keys], base_name="$(nw)_n_block",
                lower_bound = _PM.ref(pm, nw, device_key[1], device_key[2], "n0"),
                upper_bound = _PM.ref(pm, nw, device_key[1], device_key[2], "nmax"),
                start = _PM.ref(pm, nw, device_key[1], device_key[2], "n0")
            )
        else
            _PM.var(pm, nw)[:n_block] = JuMP.@variable(pm.model,
                [device_key in device_keys], base_name="$(nw)_n_block",
                integer = true,
                lower_bound = _PM.ref(pm, nw, device_key[1], device_key[2], "n0"),
                upper_bound = _PM.ref(pm, nw, device_key[1], device_key[2], "nmax"),
                start = _PM.ref(pm, nw, device_key[1], device_key[2], "n0")
            )
        end
    else
        if !haskey(_PM.var(pm, first_nw), :n_block)
            variable_installed_blocks(pm; nw=first_nw, relax, report=false)
        end
        _PM.var(pm, nw)[:n_block] = _PM.var(pm, first_nw)[:n_block]
    end

    if report
        n_block = _PM.var(pm, nw)[:n_block]
        for (table_sym, id) in device_keys
            _PM.sol(pm, nw, table_sym, id)[:n_block] = n_block[(table_sym, id)]
        end
    end
end

"""
    variable_active_blocks(pm; nw=nw_id_default, relax=false, report=true)

Creates the active UC/gSCR block variable `na_block` for network `nw`.

For each UC/gSCR block device `k` and snapshot `t == nw`, this implements
the lower bound `0 <= na_block[k,t]`. The upper relation
`na_block[k,t] <= n_block[k]` is added by
`constraint_active_blocks_le_installed`.

The argument `relax` selects continuous variables when `true` and integer
variables when `false`. Active block counts are dimensionless and
snapshot-specific. When `report=true`, each `na_block[k,t]` variable ref is
written into the PowerModels solution dict under the device component table so
downstream solution processors can extract solved values. This function is
formulation-independent and mutates the JuMP model plus PowerModels variable
and solution dictionaries.
"""
function variable_active_blocks(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, relax::Bool=false, report::Bool=true)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.var(pm, nw), :na_block)
        return
    end

    device_keys = _uc_gscr_block_device_keys(pm, nw)
    if relax
        _PM.var(pm, nw)[:na_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_na_block",
            lower_bound = 0.0,
            start = _PM.ref(pm, nw, device_key[1], device_key[2], "n0")
        )
    else
        _PM.var(pm, nw)[:na_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_na_block",
            integer = true,
            lower_bound = 0.0,
            start = _PM.ref(pm, nw, device_key[1], device_key[2], "n0")
        )
    end

    if report
        na_block = _PM.var(pm, nw)[:na_block]
        for (table_sym, id) in device_keys
            _PM.sol(pm, nw, table_sym, id)[:na_block] = na_block[(table_sym, id)]
        end
    end
end

"""
    constraint_active_blocks_le_installed(pm; nw=nw_id_default)

Adds the active block linking constraint for network `nw`.

For each UC/gSCR block device `k`, this implements
`na_block[k,t] <= n_block[k]`, completing `0 <= n_{a,k,t} <= n_k`.
It reads `:n_block` and `:na_block` variables and the UC/gSCR block device
maps from the reference extension.

This constraint is formulation-independent and mutates the JuMP model plus
PowerModels constraint dictionaries. It is a no-op for networks without
UC/gSCR block data.
"""
function constraint_active_blocks_le_installed(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.con(pm, nw), :active_blocks_le_installed)
        return
    end

    n_block = _PM.var(pm, nw)[:n_block]
    na_block = _PM.var(pm, nw)[:na_block]
    constraints = _PM.con(pm, nw)[:active_blocks_le_installed] = Dict{Tuple{Symbol,Any},JuMP.ConstraintRef}()

    for device_key in _uc_gscr_block_device_keys(pm, nw)
        constraints[device_key] = JuMP.@constraint(pm.model, na_block[device_key] <= n_block[device_key])
    end

    return constraints
end

"""
    _uc_gscr_block_device_keys(pm, nw)

Returns deterministic UC/gSCR block device keys for network `nw`.

Device keys are `(table_name, device_id)` tuples collected from the
formulation-independent `:gfl_devices` and `:gfm_devices` reference maps.
The helper assumes `ref_add_uc_gscr_block!` has already populated those maps
when block data is present. It mutates no data or model state.
"""
function _uc_gscr_block_device_keys(pm::_PM.AbstractPowerModel, nw::Int)
    if !_has_uc_gscr_block_ref(pm, nw)
        return Tuple{Symbol,Any}[]
    end

    device_keys = collect(union(keys(_PM.ref(pm, nw, :gfl_devices)), keys(_PM.ref(pm, nw, :gfm_devices))))
    sort!(device_keys; by=device_key -> (string(device_key[1]), string(device_key[2])))
    return device_keys
end

"""
    _has_uc_gscr_block_ref(pm, nw)

Returns whether network `nw` has UC/gSCR block reference maps.

This helper preserves backward compatibility for cases without block fields:
variable and linking-constraint builders become no-ops when the reference
extension skipped the network. It is formulation-independent and mutates no
data or model state.
"""
function _has_uc_gscr_block_ref(pm::_PM.AbstractPowerModel, nw::Int)
    return haskey(_PM.ref(pm, nw), :gfl_devices) && haskey(_PM.ref(pm, nw), :gfm_devices)
end
