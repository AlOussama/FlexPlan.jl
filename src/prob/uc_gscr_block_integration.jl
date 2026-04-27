"""
    uc_gscr_block_integration(data, model_type, optimizer; kwargs...)

Solves a minimal AC-side UC/gSCR block integration model on a multinetwork.

The model wires together already-implemented UC/gSCR components: reference
extension, installed/active/startup/shutdown block variables, block dispatch
and storage bounds, Gershgorin sufficient gSCR constraints, and block objective
terms:
`sum(cost_inv_block * p_block_max * (n_block - n0))` and
`sum(startup_block_cost * su_block + shutdown_block_cost * sd_block)`.

Arguments are the input `data`, a PowerModels `model_type`, and a JuMP
`optimizer`. Required dimensions are `:hour`, `:scenario`, and `:year`.
This function is formulation-independent and mutates only the instantiated
optimization model through `solve_model`.
"""
function uc_gscr_block_integration(data::Dict{String,Any}, model_type::Type, optimizer; kwargs...)
    require_dim(data, :hour, :scenario, :year)
    return _PM.solve_model(
        data,
        model_type,
        optimizer,
        build_uc_gscr_block_integration;
        ref_extensions=[ref_add_gen!, ref_add_storage!, ref_add_ne_storage!, ref_add_uc_gscr_block!],
        solution_processors=[_PM.sol_data_model!],
        multinetwork=true,
        kwargs...
    )
end

"""
    build_uc_gscr_block_integration(pm; objective=true, intertemporal_constraints=true)

Builds the minimal integrated UC/gSCR block model on one PowerModels instance.

Per snapshot, this builder creates existing generator/storage variables,
candidate-storage variables, UC/gSCR block variables, block dispatch bounds,
storage block bounds, standard dcline variables/loss constraints, the
Gershgorin sufficient gSCR condition, and a standard bus-wise active-power
balance (`constraint_power_balance`) that includes AC branch terms and dcline
terms. Dcline active-power limits are enforced by the bounded
`variable_dcline_power` variables in active-power formulations. Across hours,
it applies existing storage state constraints and candidate-storage activation
coupling.

This builder is formulation-specific to active-power formulations in this
repository workflow and mutates the JuMP model plus PowerModels variable and
constraint dictionaries. It assumes fixed topology: no AC/DC line or
converter expansion components are introduced in this integrated path.
"""
function build_uc_gscr_block_integration(pm::_PM.AbstractActivePowerModel; objective::Bool=true, intertemporal_constraints::Bool=true)
    for n in nw_ids(pm)
        _PM.variable_branch_power(pm; nw=n)
        _PM.variable_gen_power(pm; nw=n)
        expression_gen_curtailment(pm; nw=n)
        _PM.variable_dcline_power(pm; nw=n)

        _PM.variable_storage_power(pm; nw=n)
        variable_absorbed_energy(pm; nw=n)
        if _has_uc_gscr_candidate_storage(pm, n)
            variable_storage_power_ne(pm; nw=n)
            variable_absorbed_energy_ne(pm; nw=n)
        end

        variable_uc_gscr_block(pm; nw=n, relax=true)
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
        constraint_gscr_gershgorin_sufficient(pm; nw=n)

        for i in _PM.ids(pm, :storage, nw=n)
            constraint_storage_excl_slack(pm, i, nw=n)
            _PM.constraint_storage_thermal_limit(pm, i, nw=n)
            _PM.constraint_storage_losses(pm, i, nw=n)
        end
        if _has_uc_gscr_candidate_storage(pm, n)
            for i in _PM.ids(pm, :ne_storage, nw=n)
                constraint_storage_excl_slack_ne(pm, i, nw=n)
                constraint_storage_thermal_limit_ne(pm, i, nw=n)
                constraint_storage_losses_ne(pm, i, nw=n)
                constraint_storage_bounds_ne(pm, i, nw=n)
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
                        constraint_storage_state_ne(pm, i, nw=n)
                    end
                    for i in _PM.ids(pm, :ne_storage_bounded_absorption, nw=n)
                        constraint_maximum_absorption_ne(pm, i, nw=n)
                    end
                end
            else
                if is_last_id(pm, n, :hour)
                    for i in _PM.ids(pm, :storage, nw=n)
                        constraint_storage_state_final(pm, i, nw=n)
                    end
                    if _has_uc_gscr_candidate_storage(pm, n)
                        for i in _PM.ids(pm, :ne_storage, nw=n)
                            constraint_storage_state_final_ne(pm, i, nw=n)
                        end
                    end
                end

                prev_n = prev_id(pm, n, :hour)
                for i in _PM.ids(pm, :storage, nw=n)
                    constraint_storage_state(pm, i, prev_n, n)
                end
                for i in _PM.ids(pm, :storage_bounded_absorption, nw=n)
                    constraint_maximum_absorption(pm, i, prev_n, n)
                end
                if _has_uc_gscr_candidate_storage(pm, n)
                    for i in _PM.ids(pm, :ne_storage, nw=n)
                        constraint_storage_state_ne(pm, i, prev_n, n)
                    end
                    for i in _PM.ids(pm, :ne_storage_bounded_absorption, nw=n)
                        constraint_maximum_absorption_ne(pm, i, prev_n, n)
                    end
                end
            end
        end

        if is_first_id(pm, n, :hour) && _has_uc_gscr_candidate_storage(pm, n)
            prev_nws = prev_ids(pm, n, :year)
            for i in _PM.ids(pm, :ne_storage; nw=n)
                constraint_ne_storage_activation(pm, i, prev_nws, n)
            end
        end
    end
end

"""
    objective_min_cost_uc_gscr_block_integration(pm)

Builds the minimal objective used by `build_uc_gscr_block_integration`.

The objective includes generation operating cost, candidate-storage investment
cost, and UC/gSCR block terms:
`sum(cost_inv_block * p_block_max * (n_block - n0))` and
`sum(startup_block_cost * su_block + shutdown_block_cost * sd_block)`.
Block terms are each added once per model. The objective intentionally excludes
AC/DC line and converter investment terms to keep topology fixed in this
integrated path.

This helper is formulation-independent and mutates only the JuMP objective.
"""
function objective_min_cost_uc_gscr_block_integration(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)

    for n in nw_ids(pm; hour=1)
        JuMP.add_to_expression!(cost, calc_ne_storage_cost(pm, n))
    end

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
