## Objective with candidate storage

"""
    objective_min_cost_storage(pm)

Builds the single-model storage objective with investment and operation terms.

This objective minimizes the sum of existing FlexPlan investment costs plus
generation operation cost and UC/gSCR block terms: the investment contribution
`sum(cost_inv_per_mw * p_block_max * (n_block - n0))` and the startup/shutdown
contribution
`sum(startup_cost_per_mw * su_block + shutdown_cost_per_mw * sd_block)`.
Argument `pm` is one PowerModels model with all network snapshots.
Investment coefficients are used in their internal data base. Startup/shutdown
per-MW coefficients are not yet scaled by `p_block_max` or `operation_weight`;
that unit correction is deferred to the objective-units branch. This helper is
formulation-independent and mutates only the JuMP objective.
"""
function objective_min_cost_storage(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)
    # Investment cost
    for n in nw_ids(pm; hour=1)
        JuMP.add_to_expression!(cost, calc_convdc_ne_cost(pm,n))
        JuMP.add_to_expression!(cost, calc_ne_branch_cost(pm,n))
        JuMP.add_to_expression!(cost, calc_branchdc_ne_cost(pm,n))
        JuMP.add_to_expression!(cost, calc_ne_storage_cost(pm,n))
    end
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(pm))
    # Operation cost
    for n in nw_ids(pm)
        JuMP.add_to_expression!(cost, calc_gen_cost(pm,n))
    end
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(pm))
    JuMP.@objective(pm.model, Min, cost)
end

"""
    objective_min_cost_storage(t_pm, d_pm)

Builds the combined transmission-distribution storage objective.

The objective sums transmission and distribution investment/operation costs and
adds UC/gSCR block terms once per model:
`sum(cost_inv_per_mw * p_block_max * (n_block - n0))` and
`sum(startup_cost_per_mw * su_block + shutdown_cost_per_mw * sd_block)`.
Arguments `t_pm` and `d_pm` are coupled PowerModels instances sharing one JuMP
model. Coefficients are read in internal base and block-cost coefficients are
objective-level. This helper is formulation-independent and mutates only the
JuMP objective.
"""
function objective_min_cost_storage(t_pm::_PM.AbstractPowerModel, d_pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)
    # Transmission investment cost
    for n in nw_ids(t_pm; hour=1)
        JuMP.add_to_expression!(cost, calc_convdc_ne_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_ne_branch_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_branchdc_ne_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_ne_storage_cost(t_pm,n))
    end
    # Transmission operation cost
    for n in nw_ids(t_pm)
        JuMP.add_to_expression!(cost, calc_gen_cost(t_pm,n))
    end
    # Distribution investment cost
    for n in nw_ids(d_pm; hour=1)
        # Note: distribution networks do not have DC components (modeling decision)
        JuMP.add_to_expression!(cost, calc_ne_branch_cost(d_pm,n))
        JuMP.add_to_expression!(cost, calc_ne_storage_cost(d_pm,n))
    end
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(t_pm))
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(d_pm))
    # Distribution operation cost
    for n in nw_ids(d_pm)
        JuMP.add_to_expression!(cost, calc_gen_cost(d_pm,n))
    end
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(t_pm))
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(d_pm))
    JuMP.@objective(t_pm.model, Min, cost) # Note: t_pm.model == d_pm.model
end


## Objective with candidate storage and flexible demand

"""
    objective_min_cost_flex(pm; investment=true, operation=true)

Builds the single-model flexible-demand objective.

When `investment` is true, this includes existing FlexPlan investment terms and
the UC/gSCR block term `sum(cost_inv_per_mw * p_block_max * (n_block - n0))`
once for the whole optimization model. When `operation` is true, it adds
generation/load operation costs and block startup/shutdown cost
`sum(startup_cost_per_mw * su_block + shutdown_cost_per_mw * sd_block)`.
Startup/shutdown per-MW coefficients are not yet scaled by `p_block_max` or
`operation_weight`; that unit correction is deferred to the objective-units
branch. This helper is formulation-independent and mutates only the JuMP
objective.
"""
function objective_min_cost_flex(pm::_PM.AbstractPowerModel; investment=true, operation=true)
    cost = JuMP.AffExpr(0.0)
    # Investment cost
    if investment
        for n in nw_ids(pm; hour=1)
            JuMP.add_to_expression!(cost, calc_convdc_ne_cost(pm,n))
            JuMP.add_to_expression!(cost, calc_ne_branch_cost(pm,n))
            JuMP.add_to_expression!(cost, calc_branchdc_ne_cost(pm,n))
            JuMP.add_to_expression!(cost, calc_ne_storage_cost(pm,n))
            JuMP.add_to_expression!(cost, calc_load_investment_cost(pm,n))
        end
        JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(pm))
    end
    # Operation cost
    if operation
        for n in nw_ids(pm)
            JuMP.add_to_expression!(cost, calc_gen_cost(pm,n))
            JuMP.add_to_expression!(cost, calc_load_operation_cost(pm,n))
        end
        JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(pm))
    end
    JuMP.@objective(pm.model, Min, cost)
end

"""
    objective_min_cost_flex(t_pm, d_pm)

Builds the combined transmission-distribution flexible-demand objective.

The objective sums transmission and distribution investment/operation terms and
adds UC/gSCR block terms once per model:
`sum(cost_inv_per_mw * p_block_max * (n_block - n0))` and
`sum(startup_cost_per_mw * su_block + shutdown_cost_per_mw * sd_block)`.
Inputs `t_pm` and `d_pm` share one JuMP model. Coefficients use their internal
base and block-cost coefficients are objective-level. This helper is
formulation-independent and mutates only the JuMP objective.
"""
function objective_min_cost_flex(t_pm::_PM.AbstractPowerModel, d_pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)
    # Transmission investment cost
    for n in nw_ids(t_pm; hour=1)
        JuMP.add_to_expression!(cost, calc_convdc_ne_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_ne_branch_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_branchdc_ne_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_ne_storage_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_load_investment_cost(t_pm,n))
    end
    # Transmission operation cost
    for n in nw_ids(t_pm)
        JuMP.add_to_expression!(cost, calc_gen_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_load_operation_cost(t_pm,n))
    end
    # Distribution investment cost
    for n in nw_ids(d_pm; hour=1)
        # Note: distribution networks do not have DC components (modeling decision)
        JuMP.add_to_expression!(cost, calc_ne_branch_cost(d_pm,n))
        JuMP.add_to_expression!(cost, calc_ne_storage_cost(d_pm,n))
        JuMP.add_to_expression!(cost, calc_load_investment_cost(d_pm,n))
    end
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(t_pm))
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(d_pm))
    # Distribution operation cost
    for n in nw_ids(d_pm)
        JuMP.add_to_expression!(cost, calc_gen_cost(d_pm,n))
        JuMP.add_to_expression!(cost, calc_load_operation_cost(d_pm,n))
    end
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(t_pm))
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(d_pm))
    JuMP.@objective(t_pm.model, Min, cost) # Note: t_pm.model == d_pm.model
end


## Stochastic objective with candidate storage and flexible demand

"""
    objective_stoch_flex(pm; investment=true, operation=true)

Builds the single-model stochastic flexible-demand objective.

Investment terms are added on canonical investment snapshots and include one
UC/gSCR block term `sum(cost_inv_per_mw * p_block_max * (n_block - n0))` for
the whole optimization model when `investment` is true. Operation terms are
probability-weighted by scenario when `operation` is true and include block
startup/shutdown cost
`sum(startup_cost_per_mw * su_block + shutdown_cost_per_mw * sd_block)`.
Coefficients use their internal base and block-cost coefficients are
objective-level. This helper is formulation-independent and mutates only the
JuMP objective.
"""
function objective_stoch_flex(pm::_PM.AbstractPowerModel; investment=true, operation=true)
    cost = JuMP.AffExpr(0.0)
    # Investment cost
    if investment
        for n in nw_ids(pm; hour=1, scenario=1)
            JuMP.add_to_expression!(cost, calc_convdc_ne_cost(pm,n))
            JuMP.add_to_expression!(cost, calc_ne_branch_cost(pm,n))
            JuMP.add_to_expression!(cost, calc_branchdc_ne_cost(pm,n))
            JuMP.add_to_expression!(cost, calc_ne_storage_cost(pm,n))
            JuMP.add_to_expression!(cost, calc_load_investment_cost(pm,n))
        end
        JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(pm))
    end
    # Operation cost
    if operation
        for (s, scenario) in dim_prop(pm, :scenario)
            scenario_probability = scenario["probability"]
            for n in nw_ids(pm; scenario=s)
                JuMP.add_to_expression!(cost, scenario_probability, calc_gen_cost(pm,n))
                JuMP.add_to_expression!(cost, scenario_probability, calc_load_operation_cost(pm,n))
            end
        end
        JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(pm))
    end
    JuMP.@objective(pm.model, Min, cost)
end

"""
    objective_stoch_flex(t_pm, d_pm)

Builds the combined transmission-distribution stochastic objective.

The objective includes investment terms on canonical snapshots, scenario-
weighted operation terms, and UC/gSCR block terms once per model:
`sum(cost_inv_per_mw * p_block_max * (n_block - n0))` and
`sum(startup_cost_per_mw * su_block + shutdown_cost_per_mw * sd_block)`.
Inputs `t_pm` and `d_pm` share one JuMP model. Coefficients use their internal
base and block-cost coefficients are objective-level. This helper is
formulation-independent and mutates only the JuMP objective.
"""
function objective_stoch_flex(t_pm::_PM.AbstractPowerModel, d_pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)
    # Transmission investment cost
    for n in nw_ids(t_pm; hour=1, scenario=1)
        JuMP.add_to_expression!(cost, calc_convdc_ne_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_ne_branch_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_branchdc_ne_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_ne_storage_cost(t_pm,n))
        JuMP.add_to_expression!(cost, calc_load_investment_cost(t_pm,n))
    end
    # Transmission operation cost
    for (s, scenario) in dim_prop(t_pm, :scenario)
        scenario_probability = scenario["probability"]
        for n in nw_ids(t_pm; scenario=s)
            JuMP.add_to_expression!(cost, scenario_probability, calc_gen_cost(t_pm,n))
            JuMP.add_to_expression!(cost, scenario_probability, calc_load_operation_cost(t_pm,n))
        end
    end
    # Distribution investment cost
    for n in nw_ids(d_pm; hour=1, scenario=1)
        # Note: distribution networks do not have DC components (modeling decision)
        JuMP.add_to_expression!(cost, calc_ne_branch_cost(d_pm,n))
        JuMP.add_to_expression!(cost, calc_ne_storage_cost(d_pm,n))
        JuMP.add_to_expression!(cost, calc_load_investment_cost(d_pm,n))
    end
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(t_pm))
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_investment_cost(d_pm))
    # Distribution operation cost
    for (s, scenario) in dim_prop(d_pm, :scenario)
        scenario_probability = scenario["probability"]
        for n in nw_ids(d_pm; scenario=s)
            JuMP.add_to_expression!(cost, scenario_probability, calc_gen_cost(d_pm,n))
            JuMP.add_to_expression!(cost, scenario_probability, calc_load_operation_cost(d_pm,n))
        end
    end
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(t_pm))
    JuMP.add_to_expression!(cost, calc_uc_gscr_block_startup_shutdown_cost(d_pm))
    JuMP.@objective(t_pm.model, Min, cost) # Note: t_pm.model == d_pm.model
end


## Auxiliary functions

"""
    calc_uc_gscr_block_investment_cost(pm)

Builds the UC/gSCR block-investment objective contribution once per model.

Implements:
`sum_k cost_inv_per_mw[k] * p_block_max[k] * (n_block[k] - n0[k])`
using compound keys `(table_name, device_id)` over `gen`, `storage`, and
`ne_storage`. Required fields `cost_inv_per_mw` and `p_block_max` are validated
with explicit error reporting; no silent defaults are inferred. If no UC/gSCR
block reference data or no `n_block` variable exists, this returns zero. Units
follow internal model base for `p_block_max` and objective-level coefficient
for `cost_inv_per_mw`. This helper is formulation-independent and mutates no
model state.
"""
function calc_uc_gscr_block_investment_cost(pm::_PM.AbstractPowerModel)
    first_nw = _uc_gscr_first_block_nw(pm)
    if isnothing(first_nw)
        return JuMP.AffExpr(0.0)
    end

    if !haskey(_PM.var(pm, first_nw), :n_block)
        return JuMP.AffExpr(0.0)
    end

    device_keys = _uc_gscr_block_device_keys(pm, first_nw)
    _validate_uc_gscr_block_objective_fields(pm, first_nw, device_keys)

    n_block = _PM.var(pm, first_nw, :n_block)
    cost = JuMP.AffExpr(0.0)
    for device_key in device_keys
        device = _PM.ref(pm, first_nw, device_key[1], device_key[2])
        coeff = device["cost_inv_per_mw"] * device["p_block_max"]
        JuMP.add_to_expression!(cost, coeff, n_block[device_key])
        JuMP.add_to_expression!(cost, -coeff * device["n0"])
    end
    return cost
end

"""
    calc_uc_gscr_block_startup_shutdown_cost(pm)

Builds the UC/gSCR startup/shutdown block-cost contribution across snapshots.

Implements:
`sum_{k,t} startup_cost_per_mw[k] * su_block[k,t] + shutdown_cost_per_mw[k] * sd_block[k,t]`
using compound keys `(table_name, device_id)` over `gen`, `storage`, and
`ne_storage`. This expression is accumulated over all network snapshots where
the UC/gSCR block reference extension and `su_block`/`sd_block` variables are
present. Required fields `startup_cost_per_mw` and `shutdown_cost_per_mw` are
taken explicitly from device data; no silent defaults are inferred.

If no UC/gSCR block reference data or no startup/shutdown variables exist,
this returns zero. This helper is formulation-independent and mutates no model
state.
"""
function calc_uc_gscr_block_startup_shutdown_cost(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)
    for nw in nw_ids(pm)
        if !_has_uc_gscr_block_ref(pm, nw)
            continue
        end
        if !haskey(_PM.var(pm, nw), :su_block) || !haskey(_PM.var(pm, nw), :sd_block)
            continue
        end

        su_block = _PM.var(pm, nw, :su_block)
        sd_block = _PM.var(pm, nw, :sd_block)
        for device_key in _uc_gscr_block_device_keys(pm, nw)
            # TODO(feature/block-objective-units-and-weights): scale these
            # per-MW coefficients by p_block_max and operation_weight when
            # formulation-specific startup/shutdown objectives are refactored.
            startup_coeff = _PM.ref(pm, nw, device_key[1], device_key[2], "startup_cost_per_mw")
            shutdown_coeff = _PM.ref(pm, nw, device_key[1], device_key[2], "shutdown_cost_per_mw")
            JuMP.add_to_expression!(cost, startup_coeff, su_block[device_key])
            JuMP.add_to_expression!(cost, shutdown_coeff, sd_block[device_key])
        end
    end
    return cost
end

"""
    _uc_gscr_first_block_nw(pm)

Returns the first network id in `pm` that carries UC/gSCR block references.

This helper searches for a network containing both `:gfl_devices` and
`:gfm_devices` reference maps and returns `nothing` when no block data exists.
It is formulation-independent and mutates no model state.
"""
function _uc_gscr_first_block_nw(pm::_PM.AbstractPowerModel)
    for nw in nw_ids(pm)
        if haskey(_PM.ref(pm, nw), :gfl_devices) && haskey(_PM.ref(pm, nw), :gfm_devices)
            return nw
        end
    end
    return nothing
end

"""
    _validate_uc_gscr_block_objective_fields(pm, nw, device_keys)

Validates objective-required UC/gSCR block fields on `device_keys`.

For each compound key in `device_keys`, this checks presence of
`cost_inv_per_mw` and `p_block_max`, logs an explicit missing-field report, and
raises a hard validation error when any are missing. No fallback values are
inferred. This helper is formulation-independent and mutates no model state.
"""
function _validate_uc_gscr_block_objective_fields(pm::_PM.AbstractPowerModel, nw::Int, device_keys)
    missing_report = Dict{Tuple{Symbol,Any},Vector{String}}()
    required_fields = ("cost_inv_per_mw", "p_block_max")

    for device_key in device_keys
        device = _PM.ref(pm, nw, device_key[1], device_key[2])
        missing_fields = String[field for field in required_fields if !haskey(device, field)]
        if !isempty(missing_fields)
            missing_report[device_key] = missing_fields
        end
    end

    for ((table_name, device_id), missing_fields) in missing_report
        Memento.warn(
            _LOGGER,
            "$(uppercase(string(table_name))) device $(device_id) is missing UC/gSCR block objective fields: $(join(missing_fields, ", ")).",
        )
    end

    if !isempty(missing_report)
        device_summaries = String[
            "$(uppercase(string(table_name))) $(device_id): $(join(missing_fields, ", "))"
            for ((table_name, device_id), missing_fields) in missing_report
        ]
        Memento.error(
            _LOGGER,
            "UC/gSCR block objective validation failed due to missing required fields. " *
            "Missing-field report: " * join(device_summaries, " | ") * ". " *
            "The objective term uses cost_inv_per_mw * p_block_max * (n_block - n0) and applies no silent defaults.",
        )
    end

    return nothing
end

function calc_gen_cost(pm::_PM.AbstractPowerModel, n::Int)
    cost = JuMP.AffExpr(0.0)
    for (i,g) in _PM.ref(pm, n, :gen)
        if length(g["cost"]) ≥ 2
            JuMP.add_to_expression!(cost, g["cost"][end-1], _PM.var(pm,n,:pg,i))
        end
    end
    if get(pm.setting, "add_co2_cost", false)
        co2_emission_cost = pm.ref[:it][_PM.pm_it_sym][:co2_emission_cost]
        for (i,g) in _PM.ref(pm, n, :dgen)
            JuMP.add_to_expression!(cost, g["emission_factor"]*co2_emission_cost, _PM.var(pm,n,:pg,i))
        end
    end
    for (i,g) in _PM.ref(pm, n, :ndgen)
        JuMP.add_to_expression!(cost, g["cost_curt"], _PM.var(pm,n,:pgcurt,i))
    end
    return cost
end

function calc_convdc_ne_cost(pm::_PM.AbstractPowerModel, n::Int)
    add_co2_cost = get(pm.setting, "add_co2_cost", false)
    cost = JuMP.AffExpr(0.0)
    for (i,conv) in get(_PM.ref(pm,n), :convdc_ne, Dict())
        conv_cost = conv["cost"]
        if add_co2_cost
            conv_cost += conv["co2_cost"]
        end
        JuMP.add_to_expression!(cost, conv_cost, _PM.var(pm,n,:conv_ne_investment,i))
    end
    return cost
end

function calc_ne_branch_cost(pm::_PM.AbstractPowerModel, n::Int)
    add_co2_cost = get(pm.setting, "add_co2_cost", false)
    cost = JuMP.AffExpr(0.0)
    for (i,branch) in get(_PM.ref(pm,n), :ne_branch, Dict())
        branch_cost = branch["construction_cost"]
        if add_co2_cost
            branch_cost += branch["co2_cost"]
        end
        JuMP.add_to_expression!(cost, branch_cost, _PM.var(pm,n,:branch_ne_investment,i))
    end
    return cost
end

function calc_branchdc_ne_cost(pm::_PM.AbstractPowerModel, n::Int)
    add_co2_cost = get(pm.setting, "add_co2_cost", false)
    cost = JuMP.AffExpr(0.0)
    for (i,branch) in get(_PM.ref(pm,n), :branchdc_ne, Dict())
        branch_cost = branch["cost"]
        if add_co2_cost
            branch_cost += branch["co2_cost"]
        end
        JuMP.add_to_expression!(cost, branch_cost, _PM.var(pm,n,:branchdc_ne_investment,i))
    end
    return cost
end

function calc_ne_storage_cost(pm::_PM.AbstractPowerModel, n::Int)
    add_co2_cost = get(pm.setting, "add_co2_cost", false)
    cost = JuMP.AffExpr(0.0)
    for (i,storage) in get(_PM.ref(pm,n), :ne_storage, Dict())
        storage_cost = storage["eq_cost"] + storage["inst_cost"]
        if add_co2_cost
            storage_cost += storage["co2_cost"]
        end
        JuMP.add_to_expression!(cost, storage_cost, _PM.var(pm,n,:z_strg_ne_investment,i))
    end
    return cost
end

function calc_load_operation_cost(pm::_PM.AbstractPowerModel, n::Int)
    cost = JuMP.AffExpr(0.0)
    for (i,l) in _PM.ref(pm, n, :flex_load)
        JuMP.add_to_expression!(cost, 0.5*l["cost_shift"], _PM.var(pm,n,:pshift_up,i)) # Splitting into half and half allows for better cost attribution when running single-period problems or problems with no integral constraints.
        JuMP.add_to_expression!(cost, 0.5*l["cost_shift"], _PM.var(pm,n,:pshift_down,i))
        JuMP.add_to_expression!(cost, l["cost_red"], _PM.var(pm,n,:pred,i))
        JuMP.add_to_expression!(cost, l["cost_curt"], _PM.var(pm,n,:pcurt,i))
    end
    for (i,l) in _PM.ref(pm, n, :fixed_load)
        JuMP.add_to_expression!(cost, l["cost_curt"], _PM.var(pm,n,:pcurt,i))
    end
    return cost
end

function calc_load_investment_cost(pm::_PM.AbstractPowerModel, n::Int)
    add_co2_cost = get(pm.setting, "add_co2_cost", false)
    cost = JuMP.AffExpr(0.0)
    for (i,l) in _PM.ref(pm, n, :flex_load)
        load_cost = l["cost_inv"]
        if add_co2_cost
            load_cost += l["co2_cost"]
        end
        JuMP.add_to_expression!(cost, load_cost, _PM.var(pm,n,:z_flex_investment,i))
    end
    return cost
end
