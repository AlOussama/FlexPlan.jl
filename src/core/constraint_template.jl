# Constraint templates relating to network components or quantities not introduced by FlexPlan


## Power balance

"Power balance including candidate storage"
function constraint_power_balance_acne_dcne_strg(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    bus = _PM.ref(pm, nw, :bus, i)
    bus_arcs = _PM.ref(pm, nw, :bus_arcs, i)
    bus_arcs_ne = _PM.ref(pm, nw, :ne_bus_arcs, i)
    bus_arcs_dc = _PM.ref(pm, nw, :bus_arcs_dc, i)
    bus_gens = _PM.ref(pm, nw, :bus_gens, i)
    bus_convs_ac = _PM.ref(pm, nw, :bus_convs_ac, i)
    bus_convs_ac_ne = _PM.ref(pm, nw, :bus_convs_ac_ne, i)
    bus_loads = _PM.ref(pm, nw, :bus_loads, i)
    bus_shunts = _PM.ref(pm, nw, :bus_shunts, i)
    bus_storage = _PM.ref(pm, nw, :bus_storage, i)
    bus_storage_ne = _PM.ref(pm, nw, :bus_storage_ne, i)

    pd = Dict(k => _PM.ref(pm, nw, :load, k, "pd") for k in bus_loads)
    qd = Dict(k => _PM.ref(pm, nw, :load, k, "qd") for k in bus_loads)

    gs = Dict(k => _PM.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
    bs = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)
    constraint_power_balance_acne_dcne_strg(pm, nw, i, bus_arcs, bus_arcs_ne, bus_arcs_dc, bus_gens, bus_convs_ac, bus_convs_ac_ne, bus_loads, bus_shunts, bus_storage, bus_storage_ne, pd, qd, gs, bs)
end

"Power balance (without DC equipment) including candidate storage"
function constraint_power_balance_acne_strg(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    bus = _PM.ref(pm, nw, :bus, i)
    bus_arcs = _PM.ref(pm, nw, :bus_arcs, i)
    bus_arcs_ne = _PM.ref(pm, nw, :ne_bus_arcs, i)
    bus_gens = _PM.ref(pm, nw, :bus_gens, i)
    bus_loads = _PM.ref(pm, nw, :bus_loads, i)
    bus_shunts = _PM.ref(pm, nw, :bus_shunts, i)
    bus_storage = _PM.ref(pm, nw, :bus_storage, i)
    bus_storage_ne = _PM.ref(pm, nw, :bus_storage_ne, i)

    pd = Dict(k => _PM.ref(pm, nw, :load, k, "pd") for k in bus_loads)
    qd = Dict(k => _PM.ref(pm, nw, :load, k, "qd") for k in bus_loads)

    gs = Dict(k => _PM.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
    bs = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)
    constraint_power_balance_acne_strg(pm, nw, i, bus_arcs, bus_arcs_ne, bus_gens, bus_loads, bus_shunts, bus_storage, bus_storage_ne, pd, qd, gs, bs)
end

"Power balance including candidate storage & flexible demand"
function constraint_power_balance_acne_dcne_flex(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    bus = _PM.ref(pm, nw, :bus, i)
    bus_arcs = _PM.ref(pm, nw, :bus_arcs, i)
    bus_arcs_ne = _PM.ref(pm, nw, :ne_bus_arcs, i)
    bus_arcs_dc = _PM.ref(pm, nw, :bus_arcs_dc, i)
    bus_gens = _PM.ref(pm, nw, :bus_gens, i)
    bus_convs_ac = _PM.ref(pm, nw, :bus_convs_ac, i)
    bus_convs_ac_ne = _PM.ref(pm, nw, :bus_convs_ac_ne, i)
    bus_loads = _PM.ref(pm, nw, :bus_loads, i)
    bus_shunts = _PM.ref(pm, nw, :bus_shunts, i)
    bus_storage = _PM.ref(pm, nw, :bus_storage, i)
    bus_storage_ne = _PM.ref(pm, nw, :bus_storage_ne, i)

    gs = Dict(k => _PM.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
    bs = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)
    constraint_power_balance_acne_dcne_flex(pm, nw, i, bus_arcs, bus_arcs_ne, bus_arcs_dc, bus_gens, bus_convs_ac, bus_convs_ac_ne, bus_loads, bus_shunts, bus_storage, bus_storage_ne, gs, bs)
end

"Power balance (without DC equipment) including candidate storage & flexible demand"
function constraint_power_balance_acne_flex(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    bus = _PM.ref(pm, nw, :bus, i)
    bus_arcs = _PM.ref(pm, nw, :bus_arcs, i)
    bus_arcs_ne = _PM.ref(pm, nw, :ne_bus_arcs, i)
    bus_gens = _PM.ref(pm, nw, :bus_gens, i)
    bus_loads = _PM.ref(pm, nw, :bus_loads, i)
    bus_shunts = _PM.ref(pm, nw, :bus_shunts, i)
    bus_storage = _PM.ref(pm, nw, :bus_storage, i)
    bus_storage_ne = _PM.ref(pm, nw, :bus_storage_ne, i)

    gs = Dict(k => _PM.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
    bs = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)
    constraint_power_balance_acne_flex(pm, nw, i, bus_arcs, bus_arcs_ne, bus_gens, bus_loads, bus_shunts, bus_storage, bus_storage_ne, gs, bs)
end


## AC candidate branches

"Activate a candidate AC branch depending on the investment decisions in the candidate's horizon."
function constraint_ne_branch_activation(pm::_PM.AbstractPowerModel, i::Int, prev_nws::Vector{Int}, nw::Int)
    investment_horizon = [nw]
    lifetime = _PM.ref(pm, nw, :ne_branch, i, "lifetime")
    for n in Iterators.reverse(prev_nws[max(end-lifetime+2,1):end])
        i in _PM.ids(pm, n, :ne_branch) ? push!(investment_horizon, n) : break
    end
    constraint_ne_branch_activation(pm, nw, i, investment_horizon)
end


## DC candidate branches

"Activate a candidate DC branch depending on the investment decisions in the candidate's horizon."
function constraint_ne_branchdc_activation(pm::_PM.AbstractPowerModel, i::Int, prev_nws::Vector{Int}, nw::Int)
    investment_horizon = [nw]
    lifetime = _PM.ref(pm, nw, :branchdc_ne, i, "lifetime")
    for n in Iterators.reverse(prev_nws[max(end-lifetime+2,1):end])
        i in _PM.ids(pm, n, :branchdc_ne) ? push!(investment_horizon, n) : break
    end
    constraint_ne_branchdc_activation(pm, nw, i, investment_horizon)
end


## Candidate converters

"Activate a candidate AC/DC converter depending on the investment decisions in the candidate's horizon."
function constraint_ne_converter_activation(pm::_PM.AbstractPowerModel, i::Int, prev_nws::Vector{Int}, nw::Int)
    investment_horizon = [nw]
    lifetime = _PM.ref(pm, nw, :convdc_ne, i, "lifetime")
    for n in Iterators.reverse(prev_nws[max(end-lifetime+2,1):end])
        i in _PM.ids(pm, n, :convdc_ne) ? push!(investment_horizon, n) : break
    end
    constraint_ne_converter_activation(pm, nw, i, investment_horizon)
end


## UC/gSCR block dispatch bounds

"""
    constraint_uc_gscr_block_dispatch(pm; nw=nw_id_default)

Adds the UC/gSCR block dispatch-bound equations on network `nw`:

`p_min_pu * p_block_max * na_block <= p <= p_max_pu * p_block_max * na_block`

`q_block_min * na_block <= q <= q_block_max * na_block`.

Active dispatch bounds apply only to block-annotated generators. Storage and
candidate storage active dispatch are governed by standard storage equations
plus block-scaled storage charge/discharge limits. Reactive dispatch bounds
remain applied to block-annotated devices where reactive variables exist.
This template is formulation-independent and a no-op when UC/gSCR block
references are absent.
"""
function constraint_uc_gscr_block_dispatch(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    constraint_uc_gscr_block_active_dispatch_bounds(pm; nw)
    constraint_uc_gscr_block_reactive_dispatch_bounds(pm; nw)
end

"""
    constraint_uc_gscr_block_active_dispatch_bounds(pm; nw=nw_id_default)

Adds the UC/gSCR active-power dispatch-bound equation on network `nw`:

`p_min_pu * p_block_max * na_block <= p <= p_max_pu * p_block_max * na_block`.

The bound is added only for block-annotated `gen` devices via the
formulation-specific implementation. `p_min_pu` defaults to `0.0` when
missing; `p_max_pu` defaults to `1.0` when missing. Deprecated `p_block_min`
is ignored in this active dispatch formulation.
This template is formulation-independent and a no-op when UC/gSCR block
references are absent.
"""
function constraint_uc_gscr_block_active_dispatch_bounds(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.con(pm, nw), :uc_gscr_block_active_dispatch_bounds)
        return _PM.con(pm, nw)[:uc_gscr_block_active_dispatch_bounds]
    end

    constraints = _PM.con(pm, nw)[:uc_gscr_block_active_dispatch_bounds] = Dict{Tuple{Symbol,Any},Tuple{JuMP.ConstraintRef,JuMP.ConstraintRef}}()

    for device_key in _uc_gscr_block_generator_device_keys(pm, nw)
        device = _PM.ref(pm, nw, device_key[1], device_key[2])
        p_min_pu = _uc_gscr_block_pu_value(device, "p_min_pu", nw; default=0.0)
        p_max_pu = _uc_gscr_block_pu_value(device, "p_max_pu", nw; default=1.0)
        constraints[device_key] = constraint_uc_gscr_block_active_dispatch_bounds(
            pm, nw, device_key, p_min_pu, p_max_pu, device["p_block_max"]
        )
    end

    return constraints
end

"""
    _uc_gscr_block_pu_value(device, field, nw; default)

Returns the per-snapshot per-unit scalar for a UC/gSCR block field.

Accepted field shapes are:
- scalar number,
- vector/tuple indexed by snapshot `nw`,
- dictionary keyed by `nw` (integer) or `string(nw)`.

If the field is missing or has an unsupported shape, `default` is returned.
This helper is used for `p_min_pu`/`p_max_pu` extraction so renewable
time-series profiles can be honored per snapshot.
"""
function _uc_gscr_block_pu_value(device::Dict{String,<:Any}, field::String, nw::Int; default::Float64)
    if !haskey(device, field)
        return default
    end

    value = device[field]
    if value isa Number
        return float(value)
    elseif value isa AbstractVector || value isa Tuple
        series = collect(value)
        if 1 <= nw <= length(series) && series[nw] isa Number
            return float(series[nw])
        else
            Memento.warn(
                _LOGGER,
                "UC/gSCR block field `$(field)` is a time series of length $(length(series)) " *
                "but snapshot index nw=$(nw) is out of range or non-numeric. " *
                "Using default $(default). Check that the time-series length matches the horizon.",
            )
            return default
        end
    elseif value isa AbstractDict
        if haskey(value, nw) && value[nw] isa Number
            return float(value[nw])
        elseif haskey(value, string(nw)) && value[string(nw)] isa Number
            return float(value[string(nw)])
        else
            Memento.warn(
                _LOGGER,
                "UC/gSCR block field `$(field)` is a Dict but snapshot key nw=$(nw) (or \"$(nw)\") " *
                "is missing or non-numeric. Using default $(default). " *
                "Check that all snapshot keys are present in the time-series Dict.",
            )
            return default
        end
    else
        Memento.warn(
            _LOGGER,
            "UC/gSCR block field `$(field)` has unsupported type $(typeof(value)). " *
            "Expected Number, Vector, Tuple, or Dict. Using default $(default).",
        )
        return default
    end
end

"""
    constraint_uc_gscr_block_reactive_dispatch_bounds(pm; nw=nw_id_default)

Adds the UC/gSCR reactive-power dispatch-bound equation on network `nw`:

`q_block_min * na_block <= q <= q_block_max * na_block`.

The bound is added for each block-annotated `gen`, `storage`, and
`ne_storage` device via the formulation-specific implementation. This
template is a no-op when UC/gSCR block references are absent.
"""
function constraint_uc_gscr_block_reactive_dispatch_bounds(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.con(pm, nw), :uc_gscr_block_reactive_dispatch_bounds)
        return _PM.con(pm, nw)[:uc_gscr_block_reactive_dispatch_bounds]
    end

    constraints = _PM.con(pm, nw)[:uc_gscr_block_reactive_dispatch_bounds] = Dict{Tuple{Symbol,Any},Tuple{JuMP.ConstraintRef,JuMP.ConstraintRef}}()

    for device_key in _uc_gscr_block_all_device_keys(pm, nw)
        device = _PM.ref(pm, nw, device_key[1], device_key[2])
        constraints[device_key] = constraint_uc_gscr_block_reactive_dispatch_bounds(
            pm, nw, device_key, device["q_block_min"], device["q_block_max"]
        )
    end

    return constraints
end

"""
    constraint_uc_gscr_block_reactive_dispatch_bounds(pm::AbstractActivePowerModel; nw=nw_id_default)

Active-power-only no-op hook for the UC/gSCR reactive dispatch equation:

`q_block_min * na_block <= q <= q_block_max * na_block`.

For active-power-only formulations, reactive variables are absent, so this
template intentionally adds no constraints and returns `nothing`.
"""
function constraint_uc_gscr_block_reactive_dispatch_bounds(pm::_PM.AbstractActivePowerModel; nw::Int=_PM.nw_id_default)
end


## UC/gSCR block storage bounds

"""
    constraint_uc_gscr_block_storage_bounds(pm; nw=nw_id_default)

Adds UC/gSCR storage block constraints on network `nw`:

`0 <= e <= e_block * n_block`

`sc <= p_block_max * na_block`

`sd <= p_block_max * na_block`.

This template applies only to `storage` and `ne_storage` devices with block
fields, using compound keys `(table_name, device_id)` to keep indexing
collision-free. In this codebase, `e/sc/sd` map to `se/sc/sd` for `storage`
and `se_ne/sc_ne/sd_ne` for `ne_storage`, and active storage capability is
scaled with block nameplate `p_block_max`.

This function is formulation-independent, calls formulation-specific methods,
and mutates the JuMP model plus PowerModels constraint dictionaries. It is a
no-op when UC/gSCR block references are absent.
"""
function constraint_uc_gscr_block_storage_bounds(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    constraint_uc_gscr_block_storage_energy_capacity(pm; nw)
    constraint_uc_gscr_block_storage_charge_discharge_bounds(pm; nw)
end

"""
    constraint_uc_gscr_block_storage_energy_capacity(pm; nw=nw_id_default)

Adds the UC/gSCR storage energy-capacity equation on network `nw`:

`0 <= e[k,t] <= n_block[k] * e_block[k]`.

The template iterates only over block-annotated `storage` and `ne_storage`
compound keys and calls the formulation-specific method
`constraint_uc_gscr_block_storage_energy_capacity(pm, nw, device_key, e_block)`.
It assumes `e_block` is present on those storage device records.

This function is formulation-independent and mutates the model constraint
dictionary. It is a no-op when UC/gSCR block references are absent.
"""
function constraint_uc_gscr_block_storage_energy_capacity(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.con(pm, nw), :uc_gscr_block_storage_energy_capacity)
        return _PM.con(pm, nw)[:uc_gscr_block_storage_energy_capacity]
    end

    constraints = _PM.con(pm, nw)[:uc_gscr_block_storage_energy_capacity] = Dict{Tuple{Symbol,Any},JuMP.ConstraintRef}()

    for device_key in _uc_gscr_block_storage_device_keys(pm, nw)
        device = _PM.ref(pm, nw, device_key[1], device_key[2])
        constraints[device_key] = constraint_uc_gscr_block_storage_energy_capacity(pm, nw, device_key, device["e_block"])
    end

    return constraints
end

"""
    constraint_uc_gscr_block_storage_charge_discharge_bounds(pm; nw=nw_id_default)

Adds UC/gSCR storage charge/discharge block-power equations on network `nw`:

`sc[k,t] <= p_block_max[k] * na_block[k,t]`

`sd[k,t] <= p_block_max[k] * na_block[k,t]`.

This template applies only to block-annotated `storage` and `ne_storage`
devices using compound keys.
It calls the formulation-specific method
`constraint_uc_gscr_block_storage_charge_discharge_bounds(pm, nw, device_key, p_block_max)`.

This function is formulation-independent and mutates the model constraint
dictionary. It is a no-op when UC/gSCR block references are absent.
"""
function constraint_uc_gscr_block_storage_charge_discharge_bounds(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.con(pm, nw), :uc_gscr_block_storage_charge_discharge_bounds)
        return _PM.con(pm, nw)[:uc_gscr_block_storage_charge_discharge_bounds]
    end

    constraints = _PM.con(pm, nw)[:uc_gscr_block_storage_charge_discharge_bounds] = Dict{Tuple{Symbol,Any},Tuple{JuMP.ConstraintRef,JuMP.ConstraintRef}}()

    for device_key in _uc_gscr_block_storage_device_keys(pm, nw)
        device = _PM.ref(pm, nw, device_key[1], device_key[2])
        constraints[device_key] = constraint_uc_gscr_block_storage_charge_discharge_bounds(
            pm, nw, device_key, device["p_block_max"]
        )
    end

    return constraints
end

"""
    _uc_gscr_block_storage_device_keys(pm, nw)

Returns deterministic UC/gSCR block storage compound keys for network `nw`.

Keys are filtered from `_uc_gscr_block_all_device_keys(pm, nw)` and include only
`(:storage, i)` and `(:ne_storage, i)`. This helper is formulation-independent
and mutates no data or model state.
"""
function _uc_gscr_block_storage_device_keys(pm::_PM.AbstractPowerModel, nw::Int)
    return [device_key for device_key in _uc_gscr_block_all_device_keys(pm, nw) if device_key[1] == :storage || device_key[1] == :ne_storage]
end

"""
    _uc_gscr_block_generator_device_keys(pm, nw)

Returns deterministic UC/gSCR block generator compound keys for network `nw`.

Keys are filtered from `_uc_gscr_block_all_device_keys(pm, nw)` and include only
`(:gen, i)` entries.
"""
function _uc_gscr_block_generator_device_keys(pm::_PM.AbstractPowerModel, nw::Int)
    return [device_key for device_key in _uc_gscr_block_all_device_keys(pm, nw) if device_key[1] == :gen]
end


## UC/gSCR Gershgorin sufficient condition

"""
    constraint_gscr_gershgorin_sufficient(pm; nw=nw_id_default)

Adds the linear Gershgorin sufficient gSCR/ESCR condition for every bus in
network snapshot `nw`:

`sigma0_G[n] + sum(b_block[k] * na_block[k,t] for GFM k at bus n) >=
g_min * sum(p_block_max[i] * na_block[i,t] for GFL i at bus n)`.

The template reads `:gscr_sigma0_gershgorin_margin`, `:bus_gfm_devices`,
`:bus_gfl_devices`, device `b_block`, device `p_block_max`, and global
`g_min` from the reference extension, then calls the formulation-specific
method for each bus. `b_block` is assumed to be in p.u. admittance base and
`p_block_max` in the active-power variable base. This LP/MILP-compatible
function is formulation-independent, is a no-op when UC/gSCR block references
are absent, and mutates only the model constraint dictionary.
"""
function constraint_gscr_gershgorin_sufficient(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.con(pm, nw), :gscr_gershgorin_sufficient)
        return _PM.con(pm, nw)[:gscr_gershgorin_sufficient]
    end

    g_min = _uc_gscr_g_min(pm, nw)
    constraints = _PM.con(pm, nw)[:gscr_gershgorin_sufficient] = Dict{Any,JuMP.ConstraintRef}()

    for bus_id in sort(collect(_PM.ids(pm, nw, :bus)))
        gfm_devices = _PM.ref(pm, nw, :bus_gfm_devices, bus_id)
        gfl_devices = _PM.ref(pm, nw, :bus_gfl_devices, bus_id)
        b_block = Dict(device_key => _PM.ref(pm, nw, device_key[1], device_key[2], "b_block") for device_key in gfm_devices)
        p_block_max = Dict(device_key => _PM.ref(pm, nw, device_key[1], device_key[2], "p_block_max") for device_key in gfl_devices)
        sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus_id)

        constraints[bus_id] = constraint_gscr_gershgorin_sufficient(
            pm, nw, bus_id, sigma0, g_min, gfm_devices, gfl_devices, b_block, p_block_max
        )
    end

    return constraints
end

"""
    _uc_gscr_g_min(pm, nw)

Returns the required global gSCR/ESCR threshold `g_min` for snapshot `nw`.

`g_min` is a case-level dimensionless scalar used in the Gershgorin condition.
This formulation-independent validation helper applies no default, raises an
explicit error if the field is missing or nonnumeric, and mutates no data or
model state.
"""
function _uc_gscr_g_min(pm::_PM.AbstractPowerModel, nw::Int)
    if !haskey(_PM.ref(pm, nw), :g_min)
        Memento.error(
            _LOGGER,
            "Network $(nw) is missing required global field `g_min`. " *
            "The gSCR Gershgorin constraint uses g_min as the minimum " *
            "strength threshold; no silent default is applied.",
        )
    end

    g_min = _PM.ref(pm, nw, :g_min)
    if !(g_min isa Real)
        Memento.error(_LOGGER, "Network $(nw) has invalid global field `g_min=$(g_min)`. Expected a numeric gSCR/ESCR threshold.")
    end
    return g_min
end
