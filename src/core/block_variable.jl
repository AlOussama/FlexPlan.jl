"""
    variable_uc_gscr_block(pm; nw=nw_id_default, relax=false, report=true)

Creates UC/gSCR installed/active/startup/shutdown block variables for
network `nw`.

This adds installed block counts `n_block[k]` satisfying
`n0[k] <= n_block[k] <= nmax[k]`, active block counts `na_block[k,t]`
satisfying `0 <= na_block[k,t]`, startup counts `su_block[k,t]`, shutdown
counts `sd_block[k,t]`, and the linking/transition constraints:
`na_block[k,t] <= n_block[k]`,
`na_block[k,t] - na_block[k,t-1] = su_block[k,t] - sd_block[k,t]` for
`t > 1`, and
`na_block[k,1] - na0[k] = su_block[k,1] - sd_block[k,1]` for the first
snapshot. When min-up/down fields are enabled, it also adds truncated-window
count constraints for minimum up/down time.

The argument `relax` selects continuous variables when `true` and integer
variables when `false`; `report` controls solution reporting on the original
device tables under `n_block`, `na_block`, `su_block`, and `sd_block`.
Block counts are dimensionless. This helper is formulation-independent and
mutates the JuMP model plus PowerModels variable, constraint, and solution-
report dictionaries.
"""
function variable_uc_gscr_block(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, relax::Bool=false, report::Bool=true)
    variable_installed_blocks(pm; nw, relax, report)
    variable_active_blocks(pm; nw, relax, report)
    variable_block_startup_shutdown_counts(pm; nw, relax, report)
    constraint_active_blocks_le_installed(pm; nw)
    constraint_block_count_transitions(pm; nw)
    constraint_block_minimum_up_down_times(pm; nw)
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
variables when `false`; `report` controls solution reporting on the original
device tables under `n_block`. Block counts are dimensionless. When network
`nw` has no UC/gSCR block reference data, the function follows the local
no-op convention and returns `nothing`. This function is formulation-
independent and mutates the JuMP model plus PowerModels variable and
solution-report dictionaries.
"""
function variable_installed_blocks(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, relax::Bool=false, report::Bool=true)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    first_nw = first(nw_id for nw_id in nw_ids(pm) if _has_uc_gscr_block_ref(pm, nw_id))

    if nw != first_nw
        if !haskey(_PM.var(pm, first_nw), :n_block)
            variable_installed_blocks(pm; nw=first_nw, relax, report=false)
        end
        n_block = _PM.var(pm, nw)[:n_block] = _PM.var(pm, first_nw)[:n_block]
        report && _report_uc_gscr_block_variable(pm, nw, :n_block, n_block)
        return n_block
    end

    if haskey(_PM.var(pm, nw), :n_block)
        n_block = _PM.var(pm, nw)[:n_block]
        report && _report_uc_gscr_block_variable(pm, nw, :n_block, n_block)
        return n_block
    end

    device_keys = _uc_gscr_block_device_keys(pm, nw)
    if relax
        n_block = _PM.var(pm, nw)[:n_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_n_block",
            lower_bound = _PM.ref(pm, nw, device_key[1], device_key[2], "n0"),
            upper_bound = _PM.ref(pm, nw, device_key[1], device_key[2], "nmax"),
            start = _PM.ref(pm, nw, device_key[1], device_key[2], "n0")
        )
    else
        n_block = _PM.var(pm, nw)[:n_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_n_block",
            integer = true,
            lower_bound = _PM.ref(pm, nw, device_key[1], device_key[2], "n0"),
            upper_bound = _PM.ref(pm, nw, device_key[1], device_key[2], "nmax"),
            start = _PM.ref(pm, nw, device_key[1], device_key[2], "n0")
        )
    end

    report && _report_uc_gscr_block_variable(pm, nw, :n_block, n_block)
    return n_block
end

"""
    variable_active_blocks(pm; nw=nw_id_default, relax=false, report=true)

Creates the active UC/gSCR block variable `na_block` for network `nw`.

For each UC/gSCR block device `k` and snapshot `t == nw`, this implements
the lower bound `0 <= na_block[k,t]`. The upper relation
`na_block[k,t] <= n_block[k]` is added by
`constraint_active_blocks_le_installed`.

The argument `relax` selects continuous variables when `true` and integer
variables when `false`; `report` controls solution reporting on the original
device tables under `na_block`. Active block counts are dimensionless and
snapshot-specific. When network `nw` has no UC/gSCR block reference data, the
function follows the local no-op convention and returns `nothing`. This
function is formulation-independent and mutates the JuMP model plus
PowerModels variable and solution-report dictionaries.
"""
function variable_active_blocks(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, relax::Bool=false, report::Bool=true)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.var(pm, nw), :na_block)
        na_block = _PM.var(pm, nw)[:na_block]
        report && _report_uc_gscr_block_variable(pm, nw, :na_block, na_block)
        return na_block
    end

    device_keys = _uc_gscr_block_device_keys(pm, nw)
    if relax
        na_block = _PM.var(pm, nw)[:na_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_na_block",
            lower_bound = 0.0,
            start = _PM.ref(pm, nw, device_key[1], device_key[2], "n0")
        )
    else
        na_block = _PM.var(pm, nw)[:na_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_na_block",
            integer = true,
            lower_bound = 0.0,
            start = _PM.ref(pm, nw, device_key[1], device_key[2], "n0")
        )
    end

    report && _report_uc_gscr_block_variable(pm, nw, :na_block, na_block)
    return na_block
end

"""
    variable_block_startup_shutdown_counts(pm; nw=nw_id_default, relax=false, report=true)

Creates startup/shutdown UC/gSCR block count variables for network `nw`.

For each UC/gSCR block device `k` and snapshot `t == nw`, this creates
`su_block[k,t]` and `sd_block[k,t]` with `0 <= su_block[k,t]` and
`0 <= sd_block[k,t]`. The inter-snapshot transition equations are added by
`constraint_block_count_transitions`.

The argument `relax` selects continuous variables when `true` and integer
variables when `false`; `report` controls solution reporting on the original
device tables under `su_block` and `sd_block`. Counts are dimensionless and
snapshot-specific. When network `nw` has no UC/gSCR block reference data, the
function follows the local no-op convention and returns `nothing`. This
function is formulation-independent and mutates the JuMP model plus
PowerModels variable and solution-report dictionaries.
"""
function variable_block_startup_shutdown_counts(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, relax::Bool=false, report::Bool=true)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.var(pm, nw), :su_block) && haskey(_PM.var(pm, nw), :sd_block)
        su_block = _PM.var(pm, nw)[:su_block]
        sd_block = _PM.var(pm, nw)[:sd_block]
        if report
            _report_uc_gscr_block_variable(pm, nw, :su_block, su_block)
            _report_uc_gscr_block_variable(pm, nw, :sd_block, sd_block)
        end
        return (su_block, sd_block)
    end

    device_keys = _uc_gscr_block_device_keys(pm, nw)
    if relax
        su_block = _PM.var(pm, nw)[:su_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_su_block",
            lower_bound = 0.0
        )
        sd_block = _PM.var(pm, nw)[:sd_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_sd_block",
            lower_bound = 0.0
        )
    else
        su_block = _PM.var(pm, nw)[:su_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_su_block",
            integer = true,
            lower_bound = 0.0
        )
        sd_block = _PM.var(pm, nw)[:sd_block] = JuMP.@variable(pm.model,
            [device_key in device_keys], base_name="$(nw)_sd_block",
            integer = true,
            lower_bound = 0.0
        )
    end

    if report
        _report_uc_gscr_block_variable(pm, nw, :su_block, su_block)
        _report_uc_gscr_block_variable(pm, nw, :sd_block, sd_block)
    end
    return (su_block, sd_block)
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
    constraint_block_count_transitions(pm; nw=nw_id_default)

Adds UC/gSCR active/startup/shutdown block transition equations for `nw`.

For each UC/gSCR block device `k`, this implements:
`na_block[k,t] - na_block[k,t-1] = su_block[k,t] - sd_block[k,t]` when `t`
is not the first snapshot in the `:hour` dimension, and
`na_block[k,1] - na0[k] = su_block[k,1] - sd_block[k,1]` on the first
snapshot.

The template reads block initial state `na0` from reference data and variables
`:na_block`, `:su_block`, and `:sd_block`. It is formulation-independent and
mutates the JuMP model plus PowerModels constraint dictionaries. It is a no-op
for networks without UC/gSCR block data.
"""
function constraint_block_count_transitions(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    if !_has_uc_gscr_block_ref(pm, nw)
        return
    end

    if haskey(_PM.con(pm, nw), :block_count_transitions)
        return _PM.con(pm, nw)[:block_count_transitions]
    end

    na_block = _PM.var(pm, nw, :na_block)
    su_block = _PM.var(pm, nw, :su_block)
    sd_block = _PM.var(pm, nw, :sd_block)
    constraints = _PM.con(pm, nw)[:block_count_transitions] = Dict{Tuple{Symbol,Any},JuMP.ConstraintRef}()

    if is_first_id(pm, nw, :hour)
        for device_key in _uc_gscr_block_device_keys(pm, nw)
            na0 = _PM.ref(pm, nw, device_key[1], device_key[2], "na0")
            constraints[device_key] = JuMP.@constraint(pm.model, na_block[device_key] - na0 == su_block[device_key] - sd_block[device_key])
        end
    else
        prev_nw = prev_id(pm, nw, :hour)
        na_prev = _PM.var(pm, prev_nw, :na_block)
        for device_key in _uc_gscr_block_device_keys(pm, nw)
            constraints[device_key] = JuMP.@constraint(pm.model, na_block[device_key] - na_prev[device_key] == su_block[device_key] - sd_block[device_key])
        end
    end

    return constraints
end

"""
    constraint_block_minimum_up_down_times(pm; nw=nw_id_default)

Adds UC/gSCR block minimum up/down-time count constraints for snapshot `nw`.

This wrapper adds both:
- minimum up-time:
  `sum(su_block[k,tau] for tau=max(1, t-min_up_block_time[k]+1):t) <= na_block[k,t]`
- minimum down-time:
  `sum(sd_block[k,tau] for tau=max(1, t-min_down_block_time[k]+1):t) <= n_block[k] - na_block[k,t]`.

The template is formulation-independent and mutates the JuMP model plus
PowerModels constraint dictionaries. It is a no-op when minimum up/down-time
is not enabled in the reference extension.
"""
function constraint_block_minimum_up_down_times(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    constraint_block_minimum_up_time(pm; nw)
    constraint_block_minimum_down_time(pm; nw)
end

"""
    constraint_block_minimum_up_time(pm; nw=nw_id_default)

Adds UC/gSCR minimum up-time count constraints for snapshot `nw`.

For each compound device key `k`, this enforces:
`sum(su_block[k,tau] for tau=max(1, t-min_up_block_time[k]+1):t) <= na_block[k,t]`,
using truncated windows near the first snapshot in the `:hour` dimension.
Counts are based on existing integer block-count variables and no binary
commitment variables are introduced. This function is formulation-independent,
mutates the JuMP model plus PowerModels constraint dictionaries, and is a
no-op when the feature is disabled.
"""
function constraint_block_minimum_up_time(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    if !_has_uc_gscr_block_ref(pm, nw) || !_uc_gscr_block_min_up_down_enabled(pm, nw)
        return
    end

    if haskey(_PM.con(pm, nw), :block_minimum_up_time)
        return _PM.con(pm, nw)[:block_minimum_up_time]
    end

    na_block = _PM.var(pm, nw, :na_block)
    constraints = _PM.con(pm, nw)[:block_minimum_up_time] = Dict{Tuple{Symbol,Any},JuMP.ConstraintRef}()

    for device_key in _uc_gscr_block_device_keys(pm, nw)
        min_up_block_time = _PM.ref(pm, nw, device_key[1], device_key[2], "min_up_block_time")
        window_nws = _uc_gscr_block_hour_window(pm, nw, min_up_block_time)
        su_window = sum(_PM.var(pm, window_nw, :su_block, device_key) for window_nw in window_nws)
        constraints[device_key] = JuMP.@constraint(pm.model, su_window <= na_block[device_key])
    end

    return constraints
end

"""
    constraint_block_minimum_down_time(pm; nw=nw_id_default)

Adds UC/gSCR minimum down-time count constraints for snapshot `nw`.

For each compound device key `k`, this enforces:
`sum(sd_block[k,tau] for tau=max(1, t-min_down_block_time[k]+1):t) <= n_block[k] - na_block[k,t]`,
using installed offline blocks `n_block - na_block` (not `n_block_max`) and
truncated windows near the first snapshot in the `:hour` dimension. Counts are
based on existing integer block-count variables and no binary commitment
variables are introduced. This function is formulation-independent, mutates
the JuMP model plus PowerModels constraint dictionaries, and is a no-op when
the feature is disabled.
"""
function constraint_block_minimum_down_time(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    if !_has_uc_gscr_block_ref(pm, nw) || !_uc_gscr_block_min_up_down_enabled(pm, nw)
        return
    end

    if haskey(_PM.con(pm, nw), :block_minimum_down_time)
        return _PM.con(pm, nw)[:block_minimum_down_time]
    end

    n_block = _PM.var(pm, nw, :n_block)
    na_block = _PM.var(pm, nw, :na_block)
    constraints = _PM.con(pm, nw)[:block_minimum_down_time] = Dict{Tuple{Symbol,Any},JuMP.ConstraintRef}()

    for device_key in _uc_gscr_block_device_keys(pm, nw)
        min_down_block_time = _PM.ref(pm, nw, device_key[1], device_key[2], "min_down_block_time")
        window_nws = _uc_gscr_block_hour_window(pm, nw, min_down_block_time)
        sd_window = sum(_PM.var(pm, window_nw, :sd_block, device_key) for window_nw in window_nws)
        constraints[device_key] = JuMP.@constraint(pm.model, sd_window <= n_block[device_key] - na_block[device_key])
    end

    return constraints
end

"""
    _uc_gscr_block_hour_window(pm, nw, window_length)

Returns the truncated backward hour window ending at snapshot `nw`.

The returned network ids correspond to
`tau=max(1, t-window_length+1), ..., t` in the local `:hour` ordering, without
introducing any pre-horizon history snapshots. When `window_length <= 0`, the
result is empty. This helper is formulation-independent and mutates no model
state.
"""
function _uc_gscr_block_hour_window(pm::_PM.AbstractPowerModel, nw::Int, window_length::Int)
    if window_length <= 0
        return Int[]
    end

    window_nws = Int[nw]
    cursor_nw = nw
    while length(window_nws) < window_length && !is_first_id(pm, cursor_nw, :hour)
        cursor_nw = prev_id(pm, cursor_nw, :hour)
        push!(window_nws, cursor_nw)
    end
    reverse!(window_nws)
    return window_nws
end

"""
    _uc_gscr_block_min_up_down_enabled(pm, nw)

Returns whether minimum up/down-time constraints are enabled for snapshot `nw`.

The flag is written by `ref_add_uc_gscr_block!` based on presence of
`min_up_block_time`/`min_down_block_time` in block-annotated devices.
This helper is formulation-independent and mutates no model state.
"""
function _uc_gscr_block_min_up_down_enabled(pm::_PM.AbstractPowerModel, nw::Int)
    return get(_PM.ref(pm, nw), :uc_gscr_block_min_up_down_enabled, false)
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
    _report_uc_gscr_block_variable(pm, nw, field_name, variables)

Adds solution reporting for one UC/gSCR block variable container.

The field `field_name` is one of `:n_block`, `:na_block`, `:su_block`, or
`:sd_block`, and `variables` is indexed by stable compound keys
`(table_name, device_id)`. Reporting is written back to the original
PowerModels/FlexPlan component tables (`gen`, `storage`, and `ne_storage`)
using the local `_PM.sol_component_value` style. This helper is
formulation-independent and mutates only the solution-report dictionary.
"""
function _report_uc_gscr_block_variable(pm::_PM.AbstractPowerModel, nw::Int, field_name::Symbol, variables)
    for table_name in (:gen, :storage, :ne_storage)
        table_ids = _uc_gscr_block_report_ids(pm, nw, table_name, field_name)
        if isempty(table_ids)
            continue
        end

        table_variables = Dict(device_id => variables[(table_name, device_id)] for device_id in table_ids)
        _PM.sol_component_value(pm, nw, table_name, field_name, table_ids, table_variables)
    end
end

"""
    _uc_gscr_block_report_ids(pm, nw, table_name, field_name)

Returns unreported UC/gSCR block device ids for one component table.

The ids are selected from the stable compound block keys `(table_name,
device_id)` and filtered to avoid duplicate solution-report fields when a
variable constructor is called more than once. This helper is formulation-
independent and mutates only empty solution dictionaries that PowerModels
creates while checking report state.
"""
function _uc_gscr_block_report_ids(pm::_PM.AbstractPowerModel, nw::Int, table_name::Symbol, field_name::Symbol)
    return [
        device_id
        for (device_table, device_id) in _uc_gscr_block_device_keys(pm, nw)
        if device_table == table_name && !haskey(_PM.sol(pm, nw, table_name, device_id), field_name)
    ]
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
