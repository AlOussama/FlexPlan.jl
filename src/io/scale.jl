"""
    scale_data!(data; <keyword arguments>)

Scale lifetime and cost data.

See `_scale_time_data!`, `_scale_operational_cost_data!` and `_scale_investment_cost_data!`.

# Arguments
- `data`: a single-network data dictionary.
- `number_of_hours`: number of optimization periods (default: `dim_length(data, :hour)`).
- `year_scale_factor`: how many years a representative year should represent (default: `dim_meta(data, :year, "scale_factor")`).
- `number_of_years`: number of representative years (default: `dim_length(data, :year)`).
- `year_idx`: id of the representative year (default: `1`).
- `cost_scale_factor`: scale factor for all costs (default: `1.0`).
- `uc_gscr_block_capex_basis`: UC/gSCR block CAPEX basis override. Use
  `:from_data`, `:overnight_per_mw`, or `:annualized_per_mw_year`.
"""
function scale_data!(
        data::Dict{String,Any};
        number_of_hours::Int = haskey(data, "dim") ? dim_length(data, :hour) : 1,
        year_scale_factor::Int = haskey(data, "dim") ? dim_meta(data, :year, "scale_factor") : 1,
        number_of_years::Int = haskey(data, "dim") ? dim_length(data, :year) : 1,
        year_idx::Int = 1,
        cost_scale_factor::Real = 1.0,
        uc_gscr_block_capex_basis::Symbol = :from_data,
    )
    if _IM.ismultinetwork(data)
        Memento.error(_LOGGER, "`scale_data!` can only be applied to single-network data dictionaries.")
    end
    _scale_uc_gscr_block_investment_cost_data!(data, year_scale_factor, cost_scale_factor, uc_gscr_block_capex_basis)
    _scale_time_data!(data, year_scale_factor)
    _scale_operational_cost_data!(data, number_of_hours, year_scale_factor, cost_scale_factor)
    _scale_investment_cost_data!(data, number_of_years, year_idx, cost_scale_factor) # Must be called after `_scale_time_data!`
end

"""
    _scale_time_data!(data, year_scale_factor)

Scale lifetime data from years to periods of `year_scale_factor` years.

After applying this function, the step between consecutive years takes the value 1: in this
way it is easier to write the constraints that link variables belonging to different years.
"""
function _scale_time_data!(data, year_scale_factor)
    rescale = x -> x ÷ year_scale_factor
    for component in ("ne_branch", "branchdc_ne", "ne_storage", "convdc_ne", "load")
        for (key, val) in get(data, component, Dict{String,Any}())
            if !haskey(val, "lifetime")
                if component == "load"
                    continue # "lifetime" field is not used in OPF
                else
                    Memento.error(_LOGGER, "Missing `lifetime` key in `$component` $key.")
                end
            end
            if val["lifetime"] % year_scale_factor != 0
                Memento.error(_LOGGER, "Lifetime of $component $key ($(val["lifetime"])) must be a multiple of the year scale factor ($year_scale_factor).")
            end
            _PM._apply_func!(val, "lifetime", rescale)
        end
    end
end

"""
    _scale_operational_cost_data!(data, number_of_hours, year_scale_factor, cost_scale_factor)

Scale hourly costs to the planning horizon.

Scale hourly costs so that the sum of the costs over all optimization periods
(`number_of_hours` hours) represents the cost over the entire planning horizon
(`year_scale_factor` years). In this way it is possible to perform the optimization using a
reduced number of hours and still obtain a cost that approximates the cost that would be
obtained if 8760 hours were used for each year.
"""
function _scale_operational_cost_data!(data, number_of_hours, year_scale_factor, cost_scale_factor)
    rescale = x -> (8760*year_scale_factor / number_of_hours) * cost_scale_factor * x # scale hourly costs to the planning horizon
    for (g, gen) in data["gen"]
        _PM._apply_func!(gen, "cost", rescale)
        _PM._apply_func!(gen, "cost_curt", rescale)
        _scale_uc_gscr_block_operational_cost_fields!(gen, rescale)
    end
    for strg in values(get(data, "storage", Dict{String,Any}()))
        _scale_uc_gscr_block_operational_cost_fields!(strg, rescale)
    end
    for strg in values(get(data, "ne_storage", Dict{String,Any}()))
        _scale_uc_gscr_block_operational_cost_fields!(strg, rescale)
    end
    for (l, load) in data["load"]
        _PM._apply_func!(load, "cost_shift", rescale) # Compensation for demand shifting
        _PM._apply_func!(load, "cost_curt", rescale)  # Compensation for load curtailment (i.e. involuntary demand reduction)
        _PM._apply_func!(load, "cost_red", rescale)   # Compensation for not consumed energy (i.e. voluntary demand reduction)
    end
    _PM._apply_func!(data, "co2_emission_cost", rescale)
end

function _scale_uc_gscr_block_operational_cost_fields!(device::Dict{String,<:Any}, rescale::Function)
    if !_is_uc_gscr_block_device(device)
        return device
    end
    _PM._apply_func!(device, "startup_cost_per_mw", rescale)
    _PM._apply_func!(device, "shutdown_cost_per_mw", rescale)
    return device
end

function _is_uc_gscr_block_device(device::Dict{String,<:Any})
    return haskey(device, "grid_control_mode") ||
           haskey(device, "n0") ||
           haskey(device, "nmax") ||
           haskey(device, "na0") ||
           haskey(device, "p_block_max") ||
           haskey(device, "startup_cost_per_mw") ||
           haskey(device, "shutdown_cost_per_mw")
end

function _is_expandable_uc_gscr_block_device(device::Dict{String,<:Any})
    if !_is_uc_gscr_block_device(device) || !haskey(device, "n0") || !haskey(device, "nmax")
        return false
    end
    return device["nmax"] > device["n0"]
end

function _has_expandable_uc_gscr_block_investment(data::Dict{String,Any})
    for table_name in ("gen", "storage", "ne_storage")
        for device in values(get(data, table_name, Dict{String,Any}()))
            if _is_expandable_uc_gscr_block_device(device) && haskey(device, "cost_inv_per_mw")
                return true
            end
        end
    end
    return false
end

const _UC_GSCR_BLOCK_CAPEX_BASES = (:overnight_per_mw, :annualized_per_mw_year)

function _uc_gscr_block_capex_basis(data::Dict{String,Any}, keyword_basis::Symbol)
    if !(keyword_basis in (:from_data, _UC_GSCR_BLOCK_CAPEX_BASES...))
        Memento.error(_LOGGER, "Unsupported UC/gSCR block CAPEX basis keyword `$(keyword_basis)`. Expected :from_data, :overnight_per_mw, or :annualized_per_mw_year.")
    end
    if !_has_expandable_uc_gscr_block_investment(data)
        return nothing
    end

    metadata_basis = nothing
    if haskey(data, "uc_gscr_block_cost_convention")
        convention = data["uc_gscr_block_cost_convention"]
        if !(convention isa Dict)
            Memento.error(_LOGGER, "UC/gSCR block cost convention must be a Dict with key `capex_basis`.")
        end
        if !haskey(convention, "capex_basis")
            Memento.error(_LOGGER, "UC/gSCR block cost convention is missing `capex_basis`.")
        end
        metadata_basis = Symbol(convention["capex_basis"])
        if !(metadata_basis in _UC_GSCR_BLOCK_CAPEX_BASES)
            Memento.error(_LOGGER, "Unsupported UC/gSCR block CAPEX basis `$(convention["capex_basis"])`. Expected \"overnight_per_mw\" or \"annualized_per_mw_year\".")
        end
    end

    if keyword_basis == :from_data
        if isnothing(metadata_basis)
            Memento.error(_LOGGER, "Missing UC/gSCR block CAPEX basis. Set data[\"uc_gscr_block_cost_convention\"][\"capex_basis\"] to \"overnight_per_mw\" or \"annualized_per_mw_year\", or pass uc_gscr_block_capex_basis explicitly to scale_data!.")
        end
        return metadata_basis
    end

    if !isnothing(metadata_basis) && keyword_basis != metadata_basis
        Memento.error(_LOGGER, "UC/gSCR block CAPEX basis conflict: metadata declares `$(metadata_basis)` but scale_data! was called with `$(keyword_basis)`. Do not silently override cost convention metadata.")
    end
    return keyword_basis
end

function _uc_gscr_block_device_lifetime(device::Dict{String,<:Any}, table_name::String, device_id)
    if haskey(device, "lifetime")
        return device["lifetime"]
    end
    Memento.error(
        _LOGGER,
        "Expandable UC/gSCR block device requires device-level lifetime. " *
        "$(table_name) $(device_id) is expandable and no case-level lifetime fallback is supported.",
    )
end

function _uc_gscr_block_discount_or_fom_assumption(data::Dict{String,Any}, device::Dict{String,<:Any}, field::String, table_name::String, device_id)
    if haskey(device, field)
        return device[field]
    end
    assumptions = get(data, "uc_gscr_block_cost_assumptions", Dict{String,Any}())
    if assumptions isa Dict && haskey(assumptions, field)
        return assumptions[field]
    end
    if field == "discount_rate"
        Memento.error(_LOGGER, "UC/gSCR block CAPEX annualization requires `discount_rate` for $(table_name) $(device_id); discount_rate must be set on the device or in uc_gscr_block_cost_assumptions.")
    elseif field == "fixed_om_percent"
        Memento.error(_LOGGER, "UC/gSCR block CAPEX annualization requires `fixed_om_percent` for $(table_name) $(device_id); fixed_om_percent must be set on the device or in uc_gscr_block_cost_assumptions.")
    end
    Memento.error(
        _LOGGER,
        "Missing UC/gSCR block CAPEX annualization field `$(field)` for $(table_name) $(device_id). " *
        "Set it on the device or in data[\"uc_gscr_block_cost_assumptions\"]; no hidden defaults are applied.",
    )
end

function _validate_uc_gscr_block_investment_cost(table_name::String, device_id, cost_inv_per_mw)
    if !(cost_inv_per_mw isa Real) || !isfinite(cost_inv_per_mw) || cost_inv_per_mw < 0
        Memento.error(_LOGGER, "$(table_name) $(device_id) has invalid `cost_inv_per_mw=$(cost_inv_per_mw)`. Expected a nonnegative finite numeric value.")
    end
    return nothing
end

function _validate_uc_gscr_block_annualization_inputs(table_name::String, device_id, cost_inv_per_mw, lifetime, discount_rate, fixed_om_percent)
    _validate_uc_gscr_block_investment_cost(table_name, device_id, cost_inv_per_mw)
    if !(lifetime isa Real) || !isfinite(lifetime) || lifetime <= 0
        Memento.error(_LOGGER, "$(table_name) $(device_id) has invalid UC/gSCR block CAPEX `lifetime=$(lifetime)`. Expected a positive finite numeric value.")
    end
    if !(discount_rate isa Real) || !isfinite(discount_rate) || discount_rate < 0
        Memento.error(_LOGGER, "$(table_name) $(device_id) has invalid UC/gSCR block CAPEX `discount_rate=$(discount_rate)`. Expected a nonnegative finite numeric value.")
    end
    if !(fixed_om_percent isa Real) || !isfinite(fixed_om_percent) || fixed_om_percent < 0
        Memento.error(_LOGGER, "$(table_name) $(device_id) has invalid UC/gSCR block CAPEX `fixed_om_percent=$(fixed_om_percent)`. Expected a nonnegative finite numeric value.")
    end
    return nothing
end

function _uc_gscr_block_annuity(lifetime::Real, discount_rate::Real)
    if discount_rate == 0
        return 1 / lifetime
    end
    return discount_rate / (1 - (1 + discount_rate)^(-lifetime))
end

"""
    _scale_uc_gscr_block_investment_cost_data!(data, year_scale_factor, cost_scale_factor, uc_gscr_block_capex_basis)

Scales UC/gSCR block investment costs before standard FlexPlan lifetime scaling
mutates candidate lifetimes. The CAPEX basis must be explicit. In
`overnight_per_mw` mode, `cost_inv_per_mw` is annualized with device-level
`lifetime` and explicit discount/FOM values. In `annualized_per_mw_year` mode,
`cost_inv_per_mw` is already annualized per MW per year and is multiplied only
by `year_scale_factor` and `cost_scale_factor`.
"""
function _scale_uc_gscr_block_investment_cost_data!(data::Dict{String,Any}, year_scale_factor, cost_scale_factor, uc_gscr_block_capex_basis::Symbol)
    capex_basis = _uc_gscr_block_capex_basis(data, uc_gscr_block_capex_basis)
    if isnothing(capex_basis)
        return data
    end

    for table_name in ("gen", "storage", "ne_storage")
        for (device_id, device) in get(data, table_name, Dict{String,Any}())
            if !_is_expandable_uc_gscr_block_device(device) || !haskey(device, "cost_inv_per_mw")
                continue
            end
            cost_inv_per_mw = device["cost_inv_per_mw"]
            if capex_basis == :overnight_per_mw
                lifetime = _uc_gscr_block_device_lifetime(device, table_name, device_id)
                discount_rate = _uc_gscr_block_discount_or_fom_assumption(data, device, "discount_rate", table_name, device_id)
                fixed_om_percent = _uc_gscr_block_discount_or_fom_assumption(data, device, "fixed_om_percent", table_name, device_id)
                _validate_uc_gscr_block_annualization_inputs(table_name, device_id, cost_inv_per_mw, lifetime, discount_rate, fixed_om_percent)

                annualization = _uc_gscr_block_annuity(lifetime, discount_rate) + fixed_om_percent / 100
                device["cost_inv_per_mw"] = cost_inv_per_mw * annualization * year_scale_factor * cost_scale_factor
            else
                _validate_uc_gscr_block_investment_cost(table_name, device_id, cost_inv_per_mw)
                device["cost_inv_per_mw"] = cost_inv_per_mw * year_scale_factor * cost_scale_factor
            end
        end
    end
    return data
end

"""
    _scale_investment_cost_data!(data, number_of_years, year_idx, cost_scale_factor)

Correct investment costs considering the residual value at the end of the planning horizon.

Linear depreciation is assumed.

This function _must_ be called after `_scale_time_data!`.
"""
function _scale_investment_cost_data!(data, number_of_years, year_idx, cost_scale_factor)
    # Assumption: the `lifetime` parameter of investment candidates has already been scaled
    # using `_scale_time_data!`.
    remaining_years = number_of_years - year_idx + 1
    for (b, branch) in get(data, "ne_branch", Dict{String,Any}())
        rescale = x -> min(remaining_years/branch["lifetime"], 1.0) * cost_scale_factor * x
        _PM._apply_func!(branch, "construction_cost", rescale)
        _PM._apply_func!(branch, "co2_cost", rescale)
    end
    for (b, branch) in get(data, "branchdc_ne", Dict{String,Any}())
        rescale = x -> min(remaining_years/branch["lifetime"], 1.0) * cost_scale_factor * x
        _PM._apply_func!(branch, "cost", rescale)
        _PM._apply_func!(branch, "co2_cost", rescale)
    end
    for (c, conv) in get(data, "convdc_ne", Dict{String,Any}())
        rescale = x -> min(remaining_years/conv["lifetime"], 1.0) * cost_scale_factor * x
        _PM._apply_func!(conv, "cost", rescale)
        _PM._apply_func!(conv, "co2_cost", rescale)
    end
    for (s, strg) in get(data, "ne_storage", Dict{String,Any}())
        rescale = x -> min(remaining_years/strg["lifetime"], 1.0) * cost_scale_factor * x
        _PM._apply_func!(strg, "eq_cost", rescale)
        _PM._apply_func!(strg, "inst_cost", rescale)
        _PM._apply_func!(strg, "co2_cost", rescale)
    end
    for (l, load) in data["load"]
        rescale = x -> min(remaining_years/load["lifetime"], 1.0) * cost_scale_factor * x
        _PM._apply_func!(load, "cost_inv", rescale)
        _PM._apply_func!(load, "co2_cost", rescale)
    end
end

"""
    _rescale_uc_gscr_block_fields_mva_base!(device, rescale)

Rescales UC/gSCR block fields during MVA-base conversion.

The mapping follows existing FlexPlan internal quantity classes:
- `p_block_min`, `p_block_max`, `q_block_min`, `q_block_max`, `e_block`,
  `s_block` scale as power/energy (`rescale`);
- `b_block` scales as per-unit admittance (`rescale`).

Fields such as `H` and `cost_inv_per_mw` are intentionally not scaled because
they do not depend on the MVA base convention. This helper mutates `device`.
"""
function _rescale_uc_gscr_block_fields_mva_base!(device::Dict{String,<:Any}, rescale::Function)
    _PM._apply_func!(device, "p_block_min", rescale)
    _PM._apply_func!(device, "p_block_max", rescale)
    _PM._apply_func!(device, "q_block_min", rescale)
    _PM._apply_func!(device, "q_block_max", rescale)
    _PM._apply_func!(device, "e_block", rescale)
    _PM._apply_func!(device, "s_block", rescale)
    _PM._apply_func!(device, "b_block", rescale)
    return device
end

"""
    convert_mva_base(data, mva_base)

Convert a data or solution Dict to a different per-unit system MVA base value.

`data` can be single-network or multinetwork, but must already be in p.u.

!!! danger
    In case of multinetworks, make sure that variables from different networks are not bound
    to the same value in memory (i.e., it must not happen that
    `data["nw"][n1][...][key] === data["nw"][n2][...][key]`), otherwise the conversion of
    those variables may be applied multiple times.
"""
function convert_mva_base!(data::Dict{String,<:Any}, mva_base::Real)
    if haskey(data, "nw")
        nws = data["nw"]
    else
        nws = Dict("0" => data)
    end

    for data_nw in values(nws)
        if data_nw["baseMVA"] ≠ mva_base
            mva_base_ratio = mva_base / data_nw["baseMVA"]

            rescale         = x -> x / mva_base_ratio
            rescale_inverse = x -> x * mva_base_ratio

            _PM._apply_func!(data_nw, "baseMVA", rescale_inverse)

            if haskey(data_nw, "bus")
                for (i, bus) in data_nw["bus"]
                    _PM._apply_func!(bus, "lam_kcl_i", rescale_inverse)
                    _PM._apply_func!(bus, "lam_kcl_r", rescale_inverse)
                end
            end

            for comp in ["branch", "ne_branch"]
                if haskey(data_nw, comp)
                    for (i, branch) in data_nw[comp]
                        _PM._apply_func!(branch, "b_fr", rescale)
                        _PM._apply_func!(branch, "b_to", rescale)
                        _PM._apply_func!(branch, "br_r", rescale_inverse)
                        _PM._apply_func!(branch, "br_x", rescale_inverse)
                        _PM._apply_func!(branch, "c_rating_a", rescale)
                        _PM._apply_func!(branch, "c_rating_b", rescale)
                        _PM._apply_func!(branch, "c_rating_c", rescale)
                        _PM._apply_func!(branch, "g_fr", rescale)
                        _PM._apply_func!(branch, "g_to", rescale)
                        _PM._apply_func!(branch, "rate_a", rescale)
                        _PM._apply_func!(branch, "rate_b", rescale)
                        _PM._apply_func!(branch, "rate_c", rescale)

                        _PM._apply_func!(branch, "mu_sm_fr", rescale_inverse)
                        _PM._apply_func!(branch, "mu_sm_to", rescale_inverse)
                        _PM._apply_func!(branch, "pf", rescale)
                        _PM._apply_func!(branch, "pt", rescale)
                        _PM._apply_func!(branch, "qf", rescale)
                        _PM._apply_func!(branch, "qt", rescale)
                    end
                end
            end

            if haskey(data_nw, "switch")
                for (i, switch) in data_nw["switch"]
                    _PM._apply_func!(switch, "current_rating", rescale)
                    _PM._apply_func!(switch, "psw", rescale)
                    _PM._apply_func!(switch, "qsw", rescale)
                    _PM._apply_func!(switch, "thermal_rating", rescale)
                end
            end

            for comp in ["busdc", "busdc_ne"]
                if haskey(data_nw, comp)
                    for (i, bus) in data_nw[comp]
                        _PM._apply_func!(bus, "Pdc", rescale)
                    end
                end
            end

            for comp in ["branchdc", "branchdc_ne"]
                if haskey(data_nw, comp)
                    for (i, branch) in data_nw[comp]
                        _PM._apply_func!(branch, "l", rescale_inverse)
                        _PM._apply_func!(branch, "r", rescale_inverse)
                        _PM._apply_func!(branch, "rateA", rescale)
                        _PM._apply_func!(branch, "rateB", rescale)
                        _PM._apply_func!(branch, "rateC", rescale)

                        _PM._apply_func!(branch, "pf", rescale)
                        _PM._apply_func!(branch, "pt", rescale)
                    end
                end
            end

            for comp in ["convdc", "convdc_ne"]
                if haskey(data_nw, comp)
                    for (i, conv) in data_nw[comp]
                        _PM._apply_func!(conv, "bf", rescale)
                        _PM._apply_func!(conv, "droop", rescale)
                        _PM._apply_func!(conv, "Imax", rescale)
                        _PM._apply_func!(conv, "LossA", rescale)
                        _PM._apply_func!(conv, "LossCinv", rescale_inverse)
                        _PM._apply_func!(conv, "LossCrec", rescale_inverse)
                        _PM._apply_func!(conv, "P_g", rescale)
                        _PM._apply_func!(conv, "Pacmax", rescale)
                        _PM._apply_func!(conv, "Pacmin", rescale)
                        _PM._apply_func!(conv, "Pacrated", rescale)
                        _PM._apply_func!(conv, "Pdcset", rescale)
                        _PM._apply_func!(conv, "Q_g", rescale)
                        _PM._apply_func!(conv, "Qacmax", rescale)
                        _PM._apply_func!(conv, "Qacmin", rescale)
                        _PM._apply_func!(conv, "Qacrated", rescale)
                        _PM._apply_func!(conv, "rc", rescale_inverse)
                        _PM._apply_func!(conv, "rtf", rescale_inverse)
                        _PM._apply_func!(conv, "xc", rescale_inverse)
                        _PM._apply_func!(conv, "xtf", rescale_inverse)

                        _PM._apply_func!(conv, "pconv", rescale)
                        _PM._apply_func!(conv, "pdc", rescale)
                        _PM._apply_func!(conv, "pgrid", rescale)
                        _PM._apply_func!(conv, "ppr_fr", rescale)
                        _PM._apply_func!(conv, "ptf_to", rescale)
                    end
                end
            end

            if haskey(data_nw, "gen")
                for (i, gen) in data_nw["gen"]
                    _PM._rescale_cost_model!(gen, mva_base_ratio)
                    _PM._apply_func!(gen, "cost_curt", rescale_inverse)
                    _PM._apply_func!(gen, "mbase", rescale_inverse)
                    _PM._apply_func!(gen, "pmax", rescale)
                    _PM._apply_func!(gen, "pmin", rescale)
                    _PM._apply_func!(gen, "qmax", rescale)
                    _PM._apply_func!(gen, "qmin", rescale)
                    _PM._apply_func!(gen, "ramp_10", rescale)
                    _PM._apply_func!(gen, "ramp_30", rescale)
                    _PM._apply_func!(gen, "ramp_agc", rescale)
                    _PM._apply_func!(gen, "ramp_q", rescale)

                    _PM._apply_func!(gen, "pg", rescale)
                    _PM._apply_func!(gen, "pgcurt", rescale)
                    _PM._apply_func!(gen, "qg", rescale)
                    _rescale_uc_gscr_block_fields_mva_base!(gen, rescale)
                end
            end

            for comp in ["storage", "ne_storage"]
                if haskey(data_nw, comp)
                    for (i, strg) in data_nw[comp]
                        _PM._apply_func!(strg, "charge_rating", rescale)
                        _PM._apply_func!(strg, "current_rating", rescale)
                        _PM._apply_func!(strg, "discharge_rating", rescale)
                        _PM._apply_func!(strg, "energy_rating", rescale)
                        _PM._apply_func!(strg, "energy", rescale)
                        _PM._apply_func!(strg, "p_loss", rescale)
                        _PM._apply_func!(strg, "q_loss", rescale)
                        _PM._apply_func!(strg, "qmax", rescale)
                        _PM._apply_func!(strg, "qmin", rescale)
                        _PM._apply_func!(strg, "r", rescale_inverse)
                        _PM._apply_func!(strg, "stationary_energy_inflow", rescale)
                        _PM._apply_func!(strg, "stationary_energy_outflow", rescale)
                        _PM._apply_func!(strg, "thermal_rating", rescale)
                        _PM._apply_func!(strg, "x", rescale_inverse)

                        _PM._apply_func!(strg, "ps", rescale_inverse)
                        _PM._apply_func!(strg, "qs", rescale_inverse)
                        _PM._apply_func!(strg, "qsc", rescale_inverse)
                        _PM._apply_func!(strg, "sc", rescale_inverse)
                        _PM._apply_func!(strg, "sd", rescale_inverse)
                        _PM._apply_func!(strg, "se", rescale_inverse)
                        _rescale_uc_gscr_block_fields_mva_base!(strg, rescale)
                    end
                end
            end

            if haskey(data_nw, "load")
                for (i, load) in data_nw["load"]
                    _PM._apply_func!(load, "cost_curt", rescale_inverse)
                    _PM._apply_func!(load, "cost_red", rescale_inverse)
                    _PM._apply_func!(load, "cost_shift", rescale_inverse)
                    _PM._apply_func!(load, "ed", rescale)
                    _PM._apply_func!(load, "pd", rescale)
                    _PM._apply_func!(load, "qd", rescale)

                    _PM._apply_func!(load, "pcurt", rescale)
                    _PM._apply_func!(load, "pflex", rescale)
                    _PM._apply_func!(load, "pred", rescale)
                    _PM._apply_func!(load, "pshift_down", rescale)
                    _PM._apply_func!(load, "pshift_up", rescale)
                end
            end

            if haskey(data_nw, "shunt")
                for (i, shunt) in data_nw["shunt"]
                    _PM._apply_func!(shunt, "bs", rescale)
                    _PM._apply_func!(shunt, "gs", rescale)
                end
            end

            if haskey(data_nw, "td_coupling")
                td_coupling = data_nw["td_coupling"]
                _PM._apply_func!(td_coupling, "p", rescale)
                _PM._apply_func!(td_coupling, "q", rescale)
            end
        end
    end
end
