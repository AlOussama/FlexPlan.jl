"""
    uc_gscr_block_integration(data, model_type, optimizer; template=nothing, kwargs...)

Solves a minimal AC-side UC/gSCR block integration model on a multinetwork.

The model wires together already-implemented UC/gSCR components: reference
extension, installed/active/startup/shutdown block variables, block dispatch
and storage bounds, optional template-selected Gershgorin sufficient gSCR
constraints, and block objective
terms:
`sum(cost_inv_per_mw * p_block_max * (n_block - n0))` and
`sum(operation_weight * p_block_max * (startup_cost_per_mw * su_block + shutdown_cost_per_mw * sd_block))`.

Arguments are the input `data`, a PowerModels `model_type`, and a JuMP
`optimizer`. Required dimensions are `:hour`, `:scenario`, and `:year`.
When `template` is supplied, the builder resolves and caches UC/gSCR block
formulation assignments before variables and constraints are created. Schema-v2
block-enabled cases must pass a template; omitting it is allowed only for cases
with no UC/gSCR block data. This function mutates only the instantiated
optimization model through
`solve_model`.
"""
function uc_gscr_block_integration(data::Dict{String,Any}, model_type::Type, optimizer; template=nothing, kwargs...)
    require_dim(data, :hour, :scenario, :year)
    build_method = isnothing(template) ? build_uc_gscr_block_integration : ((pm; build_kwargs...) -> build_uc_gscr_block_integration(pm; template, build_kwargs...))
    return _PM.solve_model(
        data,
        model_type,
        optimizer,
        build_method;
        ref_extensions=[ref_add_gen!, ref_add_storage!, ref_add_ne_storage!, ref_add_uc_gscr_block!],
        solution_processors=[_PM.sol_data_model!],
        multinetwork=true,
        kwargs...
    )
end

"""
    build_uc_gscr_block_integration(pm; objective=true, intertemporal_constraints=true, template=nothing)

Builds the minimal integrated UC/gSCR block model on one PowerModels instance.

Per snapshot, this builder creates existing generator/storage variables,
block-native candidate-storage variables, UC/gSCR block variables, block dispatch bounds,
storage block bounds, standard dcline variables/loss constraints, optional
template-selected Gershgorin sufficient gSCR constraints, and a standard bus-wise active-power
balance (`constraint_power_balance`) that includes AC branch terms and dcline
terms. Dcline active-power limits are enforced by the bounded
`variable_dcline_power` variables in active-power formulations. Across hours,
it applies existing storage state constraints with an explicit terminal-storage
policy gate.

When `template` is supplied, this builder validates template compatibility and
caches resolved formulation data in `pm.ext`; block variables, transition
constraints, fixed-installed constraints, and startup/shutdown objective terms
consume those cached sets. Without a template, block-enabled schema-v2 cases
raise an explicit error during block variable construction.

This builder is formulation-specific to active-power formulations in this
repository workflow and mutates the JuMP model plus PowerModels variable and
constraint dictionaries. It assumes fixed topology: no AC/DC line or
converter expansion components are introduced in this integrated path.
"""
function build_uc_gscr_block_integration(
    pm::_PM.AbstractActivePowerModel;
    objective::Bool=true,
    intertemporal_constraints::Bool=true,
    final_storage_policy::Symbol=:short_horizon_relaxed,
    relax_block_variables::Bool=true,
    template=nothing,
)
    if !isnothing(template)
        resolve_uc_gscr_block_template!(pm, template)
    end

    for n in nw_ids(pm)
        _PM.variable_branch_power(pm; nw=n)
        _PM.variable_gen_power(pm; nw=n)
        expression_gen_curtailment(pm; nw=n)
        _PM.variable_dcline_power(pm; nw=n)

        _PM.variable_storage_power(pm; nw=n)
        variable_absorbed_energy(pm; nw=n)
        if _has_uc_gscr_candidate_storage(pm, n)
            variable_storage_power_ne_block(pm; nw=n)
            variable_absorbed_energy_ne(pm; nw=n)
        end

        variable_uc_gscr_block(pm; nw=n, relax=relax_block_variables)
        _relax_standard_bounds_for_block_enabled_devices!(pm, n)
    end

    if objective
        objective_min_cost_uc_gscr_block_integration(pm)
    end

    for n in nw_ids(pm)
        for i in _PM.ids(pm, n, :dcline)
            _PM.constraint_dcline_power_losses(pm, i; nw=n)
        end
        constraint_uc_gscr_block_bus_active_balance(pm; nw=n)

        constraint_uc_gscr_block_dispatch(pm; nw=n)
        constraint_uc_gscr_block_storage_bounds(pm; nw=n)
        if _uc_gscr_block_requires_gscr_constraints(pm, n)
            constraint_gscr_gershgorin_sufficient(pm; nw=n)
        end

        for i in _PM.ids(pm, :storage, nw=n)
            if !_is_uc_gscr_block_enabled_device(pm, n, :storage, i)
                constraint_storage_excl_slack(pm, i, nw=n)
                _PM.constraint_storage_thermal_limit(pm, i, nw=n)
            end
            _PM.constraint_storage_losses(pm, i, nw=n)
        end
        if _has_uc_gscr_candidate_storage(pm, n)
            for i in _PM.ids(pm, :ne_storage, nw=n)
                constraint_storage_losses_ne(pm, i, nw=n)
                constraint_storage_bounds_ne_block(pm, i, nw=n)
            end
        end

        if intertemporal_constraints
            if is_first_id(pm, n, :hour)
                for i in _PM.ids(pm, :storage, nw=n)
                    constraint_storage_state(pm, i, nw=n)
                end
                for i in _PM.ids(pm, :storage_bounded_absorption, nw=n)
                    constraint_maximum_absorption(pm, i, nw=n)
                end
                if _has_uc_gscr_candidate_storage(pm, n)
                    for i in _PM.ids(pm, :ne_storage, nw=n)
                        constraint_storage_state_ne_block(pm, i, nw=n)
                    end
                    for i in _PM.ids(pm, :ne_storage_bounded_absorption, nw=n)
                        constraint_maximum_absorption_ne(pm, i, nw=n)
                    end
                end
            else
                _apply_uc_gscr_final_storage_policy!(pm, n, final_storage_policy)

                prev_n = prev_id(pm, n, :hour)
                for i in _PM.ids(pm, :storage, nw=n)
                    constraint_storage_state(pm, i, prev_n, n)
                end
                for i in _PM.ids(pm, :storage_bounded_absorption, nw=n)
                    constraint_maximum_absorption(pm, i, prev_n, n)
                end
                if _has_uc_gscr_candidate_storage(pm, n)
                    for i in _PM.ids(pm, :ne_storage, nw=n)
                        constraint_storage_state_ne_block(pm, i, prev_n, n)
                    end
                    for i in _PM.ids(pm, :ne_storage_bounded_absorption, nw=n)
                        constraint_maximum_absorption_ne(pm, i, prev_n, n)
                    end
                end
            end
        end
    end

    _record_uc_gscr_block_architecture_diagnostics!(pm; final_storage_policy)
end

"""
    objective_min_cost_uc_gscr_block_integration(pm)

Builds the minimal objective used by `build_uc_gscr_block_integration`.

The objective includes generation operating cost and UC/gSCR block terms:
`sum(cost_inv_per_mw * p_block_max * (n_block - n0))` and
`sum(operation_weight * p_block_max * (startup_cost_per_mw * su_block + shutdown_cost_per_mw * sd_block))`.
Block terms are each added once per model. The objective intentionally excludes
AC/DC line and converter investment terms to keep topology fixed in this
integrated path.

This helper is formulation-independent and mutates only the JuMP objective.
"""
function objective_min_cost_uc_gscr_block_integration(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)

    JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(pm))
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(pm))

    for n in nw_ids(pm)
        JuMP.add_to_expression!(cost, calc_gen_cost(pm, n))
    end

    JuMP.@objective(pm.model, Min, cost)
end

"""
    constraint_uc_gscr_block_bus_active_balance(pm; nw=nw_id_default)

Adds a bus-wise active-power balance for snapshot `nw` using PowerModels'
standard active-balance template:

`constraint_power_balance(pm, i; nw=nw)`, for each bus `i`.

This helper formulates no custom balance equation. It only loops over buses
and calls the standard PowerModels balance, which includes AC branch terms,
storage terms, generator terms, load terms, and dcline terms through
`bus_arcs_dc` with the PowerModels sign convention. It is formulation-specific
to active-power models and mutates only the JuMP model and PowerModels
constraint dictionaries.
"""
function constraint_uc_gscr_block_bus_active_balance(pm::_PM.AbstractActivePowerModel; nw::Int=_PM.nw_id_default)
    if haskey(_PM.con(pm, nw), :uc_gscr_block_bus_active_balance)
        return _PM.con(pm, nw)[:uc_gscr_block_bus_active_balance]
    end

    constraints = _PM.con(pm, nw)[:uc_gscr_block_bus_active_balance] = Dict{Int,Any}()
    for i in _PM.ids(pm, nw, :bus)
        _PM.constraint_power_balance(pm, i; nw=nw)
        constraints[i] = nothing
    end
    return constraints
end

"""
    constraint_uc_gscr_block_system_active_balance(pm; nw=nw_id_default)

Backward-compatible alias to `constraint_uc_gscr_block_bus_active_balance`.
It creates any missing standard branch/dcline variables needed by the standard
PowerModels balance, but it does not add dcline setpoint constraints.
"""
function constraint_uc_gscr_block_system_active_balance(pm::_PM.AbstractActivePowerModel; nw::Int=_PM.nw_id_default)
    Memento.warn(_LOGGER, "constraint_uc_gscr_block_system_active_balance is deprecated; use constraint_uc_gscr_block_bus_active_balance.")
    if !haskey(_PM.var(pm, nw), :p)
        _PM.variable_branch_power(pm; nw=nw)
    end
    if !haskey(_PM.var(pm, nw), :p_dc) && !isempty(_PM.ids(pm, nw, :dcline))
        _PM.variable_dcline_power(pm; nw=nw)
        for i in _PM.ids(pm, nw, :dcline)
            _PM.constraint_dcline_power_losses(pm, i; nw=nw)
        end
    end
    return constraint_uc_gscr_block_bus_active_balance(pm; nw=nw)
end

"""
    _has_uc_gscr_candidate_storage(pm, nw)

Returns whether snapshot `nw` has candidate-storage reference data.

This helper gates optional candidate-storage variable and constraint blocks in
the fixed-topology UC/gSCR integration path. It is formulation-independent
and mutates no model or data state.
"""
function _has_uc_gscr_candidate_storage(pm::_PM.AbstractPowerModel, nw::Int)
    return haskey(_PM.ref(pm, nw), :ne_storage) && haskey(_PM.ref(pm, nw), :ne_storage_bounded_absorption)
end

function _is_uc_gscr_block_enabled_device(pm::_PM.AbstractPowerModel, nw::Int, table::Symbol, id)
    if !haskey(_PM.ref(pm, nw), :gfl_devices) || !haskey(_PM.ref(pm, nw), :gfm_devices)
        return false
    end
    device_key = (table, id)
    return haskey(_PM.ref(pm, nw, :gfl_devices), device_key) || haskey(_PM.ref(pm, nw, :gfm_devices), device_key)
end

function _relax_standard_bounds_for_block_enabled_devices!(pm::_PM.AbstractActivePowerModel, nw::Int)
    if !_has_uc_gscr_candidate_storage(pm, nw) && (!haskey(_PM.ref(pm, nw), :gen) || !haskey(_PM.ref(pm, nw), :storage))
        return
    end

    for i in _PM.ids(pm, :gen, nw=nw)
        if _is_uc_gscr_block_enabled_device(pm, nw, :gen, i)
            pg = _PM.var(pm, nw, :pg, i)
            JuMP.has_lower_bound(pg) && JuMP.delete_lower_bound(pg)
            JuMP.has_upper_bound(pg) && JuMP.delete_upper_bound(pg)
            if haskey(_PM.var(pm, nw), :qg)
                qg = _PM.var(pm, nw, :qg, i)
                JuMP.has_lower_bound(qg) && JuMP.delete_lower_bound(qg)
                JuMP.has_upper_bound(qg) && JuMP.delete_upper_bound(qg)
            end
        end
    end

    for i in _PM.ids(pm, :storage, nw=nw)
        if _is_uc_gscr_block_enabled_device(pm, nw, :storage, i)
            se = _PM.var(pm, nw, :se, i)
            sc = _PM.var(pm, nw, :sc, i)
            sd = _PM.var(pm, nw, :sd, i)
            JuMP.has_upper_bound(se) && JuMP.delete_upper_bound(se)
            JuMP.has_upper_bound(sc) && JuMP.delete_upper_bound(sc)
            JuMP.has_upper_bound(sd) && JuMP.delete_upper_bound(sd)
        end
    end
end

function _apply_uc_gscr_final_storage_policy!(pm::_PM.AbstractPowerModel, nw::Int, final_storage_policy::Symbol)
    if !is_last_id(pm, nw, :hour)
        return
    end

    if final_storage_policy == :strict
        for i in _PM.ids(pm, :storage, nw=nw)
            constraint_storage_state_final(pm, i, nw=nw)
        end
        if _has_uc_gscr_candidate_storage(pm, nw)
            for i in _PM.ids(pm, :ne_storage, nw=nw)
                constraint_storage_state_final_ne_block(pm, i, nw=nw)
            end
        end
    elseif final_storage_policy == :short_horizon_relaxed || final_storage_policy == :no_final
        return
    else
        Memento.error(_LOGGER, "Unsupported final_storage_policy=`$(final_storage_policy)` in build_uc_gscr_block_integration.")
    end
end

function _record_uc_gscr_block_architecture_diagnostics!(pm::_PM.AbstractPowerModel; final_storage_policy::Symbol)
    nw = first(nw_ids(pm))
    diagnostics = Dict{String,Any}()
    diagnostics["final_storage_policy"] = String(final_storage_policy)
    diagnostics["uses_standard_candidate_build_variables"] = haskey(_PM.var(pm, nw), :z_strg_ne) || haskey(_PM.var(pm, nw), :z_strg_ne_investment)
    diagnostics["uses_standard_candidate_activation_constraints"] = haskey(_PM.con(pm, nw), :ne_storage_activation)
    diagnostics["uses_standard_candidate_investment_cost"] = false

    ne_rows = Vector{Any}()
    for i in _PM.ids(pm, :ne_storage, nw=nw)
        device = _PM.ref(pm, nw, :ne_storage, i)
        block_enabled = _is_uc_gscr_block_enabled_device(pm, nw, :ne_storage, i)
        se_ne = _PM.var(pm, nw, :se_ne, i)
        sc_ne = _PM.var(pm, nw, :sc_ne, i)
        sd_ne = _PM.var(pm, nw, :sd_ne, i)
        push!(
            ne_rows,
            Dict(
                "id" => i,
                "block_enabled" => block_enabled,
                "energy_rating" => get(device, "energy_rating", missing),
                "charge_rating" => get(device, "charge_rating", missing),
                "discharge_rating" => get(device, "discharge_rating", missing),
                "e_block" => get(device, "e_block", missing),
                "p_block_max" => get(device, "p_block_max", missing),
                "n0" => get(device, "n0", missing),
                "nmax" => get(device, "nmax", missing),
                "na0" => get(device, "na0", missing),
                "se_ne_has_no_upper_bound" => !JuMP.has_upper_bound(se_ne),
                "sc_ne_has_no_upper_bound" => !JuMP.has_upper_bound(sc_ne),
                "sd_ne_has_no_upper_bound" => !JuMP.has_upper_bound(sd_ne),
                "z_strg_ne_used" => haskey(_PM.var(pm, nw), :z_strg_ne),
                "z_strg_ne_investment_used" => haskey(_PM.var(pm, nw), :z_strg_ne_investment),
                "block_envelopes_active" =>
                    haskey(_PM.con(pm, nw), :uc_gscr_block_storage_energy_capacity) &&
                    haskey(_PM.con(pm, nw), :uc_gscr_block_storage_charge_discharge_bounds),
            ),
        )
    end
    diagnostics["block_enabled_ne_storage_audit"] = ne_rows

    gen_rows = Vector{Any}()
    for i in _PM.ids(pm, :gen, nw=nw)
        device = _PM.ref(pm, nw, :gen, i)
        block_enabled = _is_uc_gscr_block_enabled_device(pm, nw, :gen, i)
        pg = _PM.var(pm, nw, :pg, i)
        push!(
            gen_rows,
            Dict(
                "id" => i,
                "block_enabled" => block_enabled,
                "pmax" => get(device, "pmax", missing),
                "qmax" => get(device, "qmax", missing),
                "p_block_max" => get(device, "p_block_max", missing),
                "p_min_pu" => get(device, "p_min_pu", missing),
                "p_max_pu" => get(device, "p_max_pu", missing),
                "pg_has_no_upper_bound" => !JuMP.has_upper_bound(pg),
                "block_dispatch_bounds_active" => haskey(_PM.con(pm, nw), :uc_gscr_block_active_dispatch_bounds),
            ),
        )
    end
    diagnostics["block_enabled_gen_audit"] = gen_rows

    diagnostics["objective_block_investment_included_once"] = true
    diagnostics["objective_block_startup_shutdown_included_once"] = true
    diagnostics["objective_standard_candidate_investment_excluded_for_block_builder"] = true

    pm.ext[:uc_gscr_block_architecture_diagnostics] = diagnostics
    return diagnostics
end
