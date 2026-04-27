import FlexPlan as _FP
import PowerModels as _PM
import InfrastructureModels as _IM
using JuMP
using Memento
using Test
import HiGHS
import JSON
import Dates
import Printf: @sprintf

Memento.setlevel!(Memento.getlogger(_IM), "error")
Memento.setlevel!(Memento.getlogger(_PM), "error")

const _ROOT = get(
    ENV,
    "PYPSA_FLEXPLAN_BLOCK_GSCR_ROOT",
    raw"D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr",
)
const _DATASET_NAME = "base_s_5_24snap"
const _CASE_PATH = normpath(_ROOT, _DATASET_NAME, "case.json")
const _REPORT_PATH = normpath(@__DIR__, "..", "reports", "pypsa_24h_gscr_sensitivity_study.md")

const _ACTIVE_OK = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL"])
const _DOC_STATUS = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL", "INFEASIBLE"])
const _EPS = 1e-6
const _NEAR = 1e-6
const _GMIN_VALUES = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
const _GMIN_AUDIT_VALUES = Set([0.0, 1.0, 2.0, 3.0])
const _BASELINE_GMIN = 0.0

const _THERMAL_CARRIERS = Set(["CCGT", "nuclear", "biomass", "oil"])
const _NONSYNC_CARRIERS = Set(["battery", "solar", "onwind", "offwind-ac", "offwind-dc"])

function _dataset_path()
    return _CASE_PATH
end

function _load_case()
    return JSON.parsefile(_dataset_path())
end

function _status_str(status)
    return string(status)
end

function _fmt(x; digits::Int=6)
    if isnothing(x)
        return "NaN"
    end
    if x isa Real
        if !isfinite(x)
            return "NaN"
        end
        return @sprintf("%.*f", digits, x)
    end
    return string(x)
end

function _add_dimensions!(data::Dict{String,Any})
    if !haskey(data, "dim")
        _FP.add_dimension!(data, :hour, length(data["nw"]))
        _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
        _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    end
    return data
end

function _link_to_dcline(nw::Dict{String,Any})
    bus_name_to_id = Dict(bus["name"] => parse(Int, id) for (id, bus) in nw["bus"])
    dcline = Dict{String,Any}()
    skipped = 0
    ignored = 0
    for (idx, (link_id, link)) in enumerate(sort(collect(get(nw, "link", Dict{String,Any}())); by=first))
        if get(link, "carrier", "") != "DC"
            ignored += 1
            continue
        end
        f_bus = get(bus_name_to_id, link["bus0"], nothing)
        t_bus = get(bus_name_to_id, link["bus1"], nothing)
        if isnothing(f_bus) || isnothing(t_bus)
            skipped += 1
            continue
        end
        rate = get(link, "p_nom", get(link, "rate_a", 0.0))
        dcline[string(idx)] = Dict{String,Any}(
            "index" => idx,
            "source_id" => ["pypsa_link", link_id],
            "name" => get(link, "name", link_id),
            "carrier" => get(link, "carrier", "dc"),
            "f_bus" => f_bus,
            "t_bus" => t_bus,
            "br_status" => get(link, "status", 1),
            "pf" => get(link, "pf", 0.0),
            "pt" => get(link, "pt", 0.0),
            "qf" => get(link, "qf", 0.0),
            "qt" => get(link, "qt", 0.0),
            "pminf" => get(link, "pminf", -rate),
            "pmaxf" => get(link, "pmaxf", rate),
            "pmint" => get(link, "pmint", -rate),
            "pmaxt" => get(link, "pmaxt", rate),
            "qminf" => get(link, "qminf", 0.0),
            "qmaxf" => get(link, "qmaxf", 0.0),
            "qmint" => get(link, "qmint", 0.0),
            "qmaxt" => get(link, "qmaxt", 0.0),
            "loss0" => get(link, "loss0", 0.0),
            "loss1" => get(link, "loss1", 0.0),
            "vf" => get(link, "vf", 1.0),
            "vt" => get(link, "vt", 1.0),
            "model" => get(link, "model", 2),
            "cost" => get(link, "cost", [0.0, 0.0]),
        )
    end
    return dcline, skipped, ignored
end

function _prepare_solver_data(raw::Dict{String,Any}; mode::Symbol=:capexp)
    data = deepcopy(raw)
    data["per_unit"] = get(data, "per_unit", false)
    data["source_type"] = get(data, "source_type", "pypsa-flexplan-json")
    data["name"] = get(data, "name", "pypsa-flexplan-block-gscr")
    _add_dimensions!(data)

    for nw in values(data["nw"])
        dcline, _, _ = _link_to_dcline(nw)
        delete!(nw, "link")
        nw["per_unit"] = get(nw, "per_unit", data["per_unit"])
        nw["source_type"] = get(nw, "source_type", data["source_type"])
        nw["time_elapsed"] = get(nw, "time_elapsed", 1.0)
        nw["ne_storage"] = get(nw, "ne_storage", Dict{String,Any}())
        nw["dcline"] = dcline
        for table in ("shunt", "switch")
            nw[table] = get(nw, table, Dict{String,Any}())
        end
        for table in ("bus", "branch", "gen", "storage", "load")
            for (id, c) in get(nw, table, Dict{String,Any}())
                c["index"] = get(c, "index", parse(Int, id))
            end
        end

        # g_min is a FlexPlan optimization parameter injected later per scenario.
        nw["g_min"] = 0.0
        nw["_g_min_source"] = "flexplan_injected_default"
        for bus in values(nw["bus"])
            bus["zone"] = get(bus, "zone", 1)
        end
        for branch in values(nw["branch"])
            branch["tap"] = get(branch, "tap", 1.0)
            branch["shift"] = get(branch, "shift", 0.0)
            branch["transformer"] = get(branch, "transformer", false)
            branch["g_fr"] = get(branch, "g_fr", 0.0)
            branch["g_to"] = get(branch, "g_to", 0.0)
        end
        for load in values(nw["load"])
            load["status"] = get(load, "status", 1)
        end

        for gen in values(nw["gen"])
            gen["status"] = get(gen, "status", get(gen, "gen_status", 1))
            gen["dispatchable"] = get(gen, "dispatchable", true)
            gen["model"] = get(gen, "model", 2)
            gen["cost"] = get(gen, "cost", [0.0, 0.0])
            if haskey(gen, "n_block0")
                gen["n0"] = gen["n_block0"]
                gen["nmax"] = mode == :uc ? gen["n0"] : gen["n_block_max"]
            end
        end

        for st in values(nw["storage"])
            if haskey(st, "n_block0")
                st["n0"] = st["n_block0"]
                st["nmax"] = mode == :uc ? st["n0"] : st["n_block_max"]
            end
            st["r"] = get(st, "r", 0.0)
            st["x"] = get(st, "x", 0.0)
            st["p_loss"] = get(st, "p_loss", 0.0)
            st["q_loss"] = get(st, "q_loss", 0.0)
            st["stationary_energy_inflow"] = get(st, "stationary_energy_inflow", 0.0)
            st["stationary_energy_outflow"] = get(st, "stationary_energy_outflow", 0.0)
            st["thermal_rating"] = get(st, "thermal_rating", max(get(st, "charge_rating", 0.0), get(st, "discharge_rating", 0.0), 1.0))
            st["qmin"] = get(st, "qmin", get(st, "q_block_min", -1.0))
            st["qmax"] = get(st, "qmax", get(st, "q_block_max", 1.0))
            st["energy_rating"] = get(st, "energy_rating", get(st, "energy", 1.0))
            st["max_energy_absorption"] = get(st, "max_energy_absorption", Inf)
            st["self_discharge_rate"] = get(st, "self_discharge_rate", 0.0)
        end

        for st in values(get(nw, "ne_storage", Dict{String,Any}()))
            if haskey(st, "n_block0")
                st["n0"] = st["n_block0"]
                st["nmax"] = mode == :uc ? st["n0"] : st["n_block_max"]
            end
        end
    end
    return data
end

function _inject_g_min!(data::Dict{String,Any}, g_min_value::Float64)
    for nw in values(data["nw"])
        nw["g_min"] = g_min_value
        nw["_g_min_source"] = "flexplan_injected_uniform"
        for bus in values(get(nw, "bus", Dict{String,Any}()))
            bus["g_min"] = g_min_value
        end
    end
    return data
end

function _device_bus(table::String, d::Dict{String,Any})
    if table == "gen"
        return get(d, "gen_bus", -1)
    end
    return get(d, "storage_bus", -1)
end

function _is_battery_gfm(d::Dict{String,Any})
    return String(get(d, "carrier", "")) == "battery_gfm" && String(get(d, "type", "")) == "gfm"
end

function _max_component_id(data::Dict{String,Any}, table::String)
    max_id = 0
    for nw in values(data["nw"])
        for id in keys(get(nw, table, Dict{String,Any}()))
            max_id = max(max_id, parse(Int, id))
        end
    end
    return max_id
end

function _sigma0_by_bus(data::Dict{String,Any})
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _FP.build_uc_gscr_block_integration;
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    first_nw = first(sort(collect(_FP.nw_ids(pm))))
    out = Dict{Int,Float64}()
    for bus in sort(collect(_PM.ids(pm, first_nw, :bus)))
        out[bus] = _PM.ref(pm, first_nw, :gscr_sigma0_gershgorin_margin, bus)
    end
    return out
end

function _build_diagnostic_candidate_plan(raw::Dict{String,Any}; target_gmin::Float64=3.0, minimum_candidate_blocks::Int=1, candidate_b_block::Float64=0.2)
    data = _prepare_solver_data(raw; mode=:capexp)
    first_nw_id = first(sort(collect(keys(data["nw"])); by=x -> parse(Int, x)))
    nw = data["nw"][first_nw_id]
    sigma0_by_bus = _sigma0_by_bus(data)

    battery_templates = Dict{Int,String}()
    fallback_template_id = nothing
    for (id, st) in sort(collect(get(nw, "storage", Dict{String,Any}())); by=x -> parse(Int, x.first))
        if String(get(st, "carrier", "")) == "battery" && String(get(st, "type", "")) == "gfl"
            bus = get(st, "storage_bus", -1)
            if bus > 0 && !haskey(battery_templates, bus)
                battery_templates[bus] = id
            end
            if isnothing(fallback_template_id)
                fallback_template_id = id
            end
        end
    end
    if isnothing(fallback_template_id)
        error("No battery gfl storage template found in solver-copy data; cannot build diagnostic battery_gfm candidates.")
    end

    gfl_nameplate_by_bus = Dict{Int,Float64}()
    gfm_strength_before_by_bus = Dict{Int,Float64}()
    for bus in sort(parse.(Int, collect(keys(get(nw, "bus", Dict{String,Any})))))
        gfl_nameplate_by_bus[bus] = 0.0
        gfm_strength_before_by_bus[bus] = 0.0
    end
    for (table, _, d) in _iter_block_devices(nw)
        bus = _device_bus(table, d)
        if !haskey(gfl_nameplate_by_bus, bus)
            continue
        end
        n0 = float(get(d, "n_block0", get(d, "n0", 0.0)))
        if String(get(d, "type", "")) == "gfl"
            gfl_nameplate_by_bus[bus] += float(get(d, "p_block_max", 0.0)) * n0
        elseif String(get(d, "type", "")) == "gfm"
            gfm_strength_before_by_bus[bus] += float(get(d, "b_block", 0.0)) * n0
        end
    end

    next_id = _max_component_id(data, "storage") + 1
    rows = Dict{String,Any}[]
    for (idx, bus) in enumerate(sort(parse.(Int, collect(keys(get(nw, "bus", Dict{String,Any}))))))
        template_id = get(battery_templates, bus, String(fallback_template_id))
        tmpl = nw["storage"][template_id]
        p_block_max = float(get(tmpl, "p_block_max", 0.0))
        p_block_min = float(get(tmpl, "p_block_min", 0.0))
        q_block_min = float(get(tmpl, "q_block_min", get(tmpl, "qmin", 0.0)))
        q_block_max = float(get(tmpl, "q_block_max", get(tmpl, "qmax", 0.0)))
        e_block = float(get(tmpl, "e_block", get(tmpl, "energy_rating", 0.0)))
        cost_inv_base = float(get(tmpl, "cost_inv_block", 0.0))
        startup_base = haskey(tmpl, "startup_block_cost") ? float(get(tmpl, "startup_block_cost", 0.0)) : 0.0
        shutdown_base = haskey(tmpl, "shutdown_block_cost") ? float(get(tmpl, "shutdown_block_cost", 0.0)) : 0.0

        has_marginal = false
        marginal_base = NaN
        if haskey(tmpl, "marginal_cost") && get(tmpl, "marginal_cost", nothing) isa Real
            has_marginal = true
            marginal_base = float(tmpl["marginal_cost"])
        elseif haskey(tmpl, "opex") && get(tmpl, "opex", nothing) isa Real
            has_marginal = true
            marginal_base = float(tmpl["opex"])
        elseif haskey(tmpl, "cost")
            cost = get(tmpl, "cost", Any[])
            if cost isa AbstractVector && length(cost) >= 2 && all(x -> x isa Real, cost)
                has_marginal = true
                marginal_base = float(cost[end - 1])
            end
        end

        sigma0 = get(sigma0_by_bus, bus, 0.0)
        gfl_nameplate = get(gfl_nameplate_by_bus, bus, 0.0)
        required_blocks_for_gmin3 = ceil(Int, max(0.0, target_gmin * gfl_nameplate - sigma0) / candidate_b_block)
        n_block_max = max(required_blocks_for_gmin3, minimum_candidate_blocks)

        push!(rows, Dict{String,Any}(
            "bus" => bus,
            "candidate_id" => string(next_id + idx - 1),
            "template_storage_id" => template_id,
            "carrier" => "battery_gfm",
            "type" => "gfm",
            "component_kind" => "storage",
            "p_block_max" => p_block_max,
            "p_block_min" => p_block_min,
            "q_block_min" => q_block_min,
            "q_block_max" => q_block_max,
            "e_block" => e_block,
            "b_block" => candidate_b_block,
            "b_block_source_note" => "diagnostic_value_on_ac_base_not_calibrated",
            "n_block0" => 0.0,
            "na0" => 0.0,
            "n_block_max" => float(n_block_max),
            "required_blocks_for_gmin3" => float(required_blocks_for_gmin3),
            "minimum_candidate_blocks" => float(minimum_candidate_blocks),
            "sigma0_at_bus" => sigma0,
            "local_gfl_nameplate_at_bus" => gfl_nameplate,
            "cost_inv_block" => 1.5 * cost_inv_base,
            "startup_block_cost" => startup_base,
            "shutdown_block_cost" => shutdown_base,
            "marginal_cost_base" => marginal_base,
            "marginal_cost_scaled" => has_marginal ? 1.3 * marginal_base : NaN,
            "marginal_cost_available" => has_marginal,
            "startup_source_note" => haskey(tmpl, "startup_block_cost") ? "copied_from_gfl_battery" : "missing_in_template_set_to_zero",
            "shutdown_source_note" => haskey(tmpl, "shutdown_block_cost") ? "copied_from_gfl_battery" : "missing_in_template_set_to_zero",
            "cost_source_note" => "gfl_battery_reference_with_requested_multipliers",
            "gfm_strength_before_bus" => get(gfm_strength_before_by_bus, bus, 0.0),
        ))
    end

    return Dict{String,Any}(
        "rows" => rows,
        "target_gmin_for_sizing" => target_gmin,
        "minimum_candidate_blocks" => minimum_candidate_blocks,
        "candidate_b_block" => candidate_b_block,
        "marginal_cost_used_in_objective_note" => "UC/CAPEXP objective path may ignore storage marginal/opex depending on formulation coefficients; report flags availability.",
    )
end

function _apply_diagnostic_candidate_plan!(data::Dict{String,Any}, plan::Dict{String,Any})
    rows = get(plan, "rows", Dict{String,Any}[])
    if isempty(rows)
        return data
    end
    for (_, nw) in sort(collect(data["nw"]); by=x -> parse(Int, x.first))
        storage_tbl = get(nw, "storage", Dict{String,Any}())
        for row in rows
            bus = Int(row["bus"])
            template_id = String(row["template_storage_id"])
            template = if haskey(storage_tbl, template_id)
                storage_tbl[template_id]
            else
                first(values(storage_tbl))
            end
            cand = deepcopy(template)
            cand["index"] = parse(Int, String(row["candidate_id"]))
            cand["name"] = "diag_battery_gfm_bus$(bus)"
            cand["carrier"] = row["carrier"]
            cand["type"] = row["type"]
            cand["storage_bus"] = bus
            cand["status"] = get(cand, "status", 1)
            cand["n_block0"] = 0.0
            cand["na0"] = 0.0
            cand["n0"] = 0.0
            cand["n_block_max"] = row["n_block_max"]
            cand["nmax"] = row["n_block_max"]
            cand["p_block_max"] = row["p_block_max"]
            cand["p_block_min"] = row["p_block_min"]
            cand["q_block_min"] = row["q_block_min"]
            cand["q_block_max"] = row["q_block_max"]
            cand["e_block"] = row["e_block"]
            cand["b_block"] = row["b_block"]
            cand["cost_inv_block"] = row["cost_inv_block"]
            cand["startup_block_cost"] = row["startup_block_cost"]
            cand["shutdown_block_cost"] = row["shutdown_block_cost"]
            if get(row, "marginal_cost_available", false)
                mc = row["marginal_cost_scaled"]
                if haskey(cand, "marginal_cost")
                    cand["marginal_cost"] = mc
                elseif haskey(cand, "opex")
                    cand["opex"] = mc
                elseif haskey(cand, "cost")
                    cost = get(cand, "cost", Any[])
                    if cost isa AbstractVector && length(cost) >= 2 && all(x -> x isa Real, cost)
                        cost[end - 1] = mc
                        cand["cost"] = cost
                    end
                end
            end
            cand["energy"] = 0.0
            cand["energy_rating"] = 0.0
            if haskey(cand, "energy_raw")
                cand["energy_raw"] = 0.0
            end
            if haskey(cand, "energy_clamped")
                cand["energy_clamped"] = 0.0
            end
            cand["_diag_candidate"] = true
            cand["_diag_cost_source_note"] = row["cost_source_note"]
            cand["_diag_b_block_source_note"] = row["b_block_source_note"]
            storage_tbl[String(row["candidate_id"])] = cand
        end
        nw["storage"] = storage_tbl
    end
    return data
end

function _iter_block_devices(nw::Dict{String,Any})
    items = Tuple{String,String,Dict{String,Any}}[]
    for table in ("gen", "storage", "ne_storage")
        for (id, d) in get(nw, table, Dict{String,Any}())
            if haskey(d, "type")
                push!(items, (table, id, d))
            end
        end
    end
    return items
end

function _set_mode_nmax_policy!(data::Dict{String,Any}, mode_name::String)
    for nw in values(data["nw"])
        for (table, _, d) in _iter_block_devices(nw)
            if !haskey(d, "n0") || !haskey(d, "nmax")
                continue
            end
            if mode_name == "uc_only"
                d["nmax"] = d["n0"]
            elseif mode_name == "full_capexp"
                d["nmax"] = get(d, "n_block_max", d["nmax"])
            elseif mode_name == "storage_only"
                if table == "gen"
                    d["nmax"] = d["n0"]
                else
                    d["nmax"] = get(d, "n_block_max", d["nmax"])
                end
            elseif mode_name == "generator_only"
                if table == "gen"
                    d["nmax"] = get(d, "n_block_max", d["nmax"])
                else
                    d["nmax"] = d["n0"]
                end
            end
            d["nmax"] = max(d["nmax"], d["n0"])
        end
    end
    return data
end

function _scale_cost_linear!(d::Dict{String,Any}, factor::Float64)
    if !haskey(d, "cost")
        return false
    end
    cost = d["cost"]
    if !(cost isa AbstractVector) || length(cost) < 2 || !all(x -> x isa Real, cost)
        return false
    end
    idx = length(cost) - 1
    cost[idx] = factor * cost[idx]
    d["cost"] = cost
    return true
end

function _apply_gfm_opex_multiplier!(data::Dict{String,Any}, factor::Float64)
    touched = 0
    candidates = 0
    for nw in values(data["nw"])
        for (_, _, d) in _iter_block_devices(nw)
            if get(d, "type", "") == "gfm"
                candidates += 1
                ok = _scale_cost_linear!(d, factor)
                if ok
                    touched += 1
                end
            end
        end
    end
    return Dict("available" => touched > 0, "touched" => touched, "candidates" => candidates)
end

function _apply_gfm_startup_multiplier!(data::Dict{String,Any}, factor::Float64)
    touched = 0
    for nw in values(data["nw"])
        for (_, _, d) in _iter_block_devices(nw)
            if get(d, "type", "") == "gfm" && haskey(d, "startup_block_cost")
                d["startup_block_cost"] = factor * d["startup_block_cost"]
                touched += 1
            end
        end
    end
    return touched
end

function _apply_gfm_alpha_reduction!(data::Dict{String,Any}, alpha::Float64)
    clamp_count = 0
    touched = 0
    for nw in values(data["nw"])
        for (_, _, d) in _iter_block_devices(nw)
            if get(d, "type", "") != "gfm" || !haskey(d, "n0")
                continue
            end
            old_n0 = d["n0"]
            new_n0 = floor(alpha * old_n0)
            if haskey(d, "na0") && d["na0"] > new_n0
                d["na0"] = new_n0
                clamp_count += 1
            end
            d["n0"] = new_n0
            d["nmax"] = max(get(d, "nmax", new_n0), new_n0)
            touched += 1
        end
    end
    return Dict("touched" => touched, "na0_clamped" => clamp_count)
end

function _apply_reclassification!(data::Dict{String,Any}, scenario::String)
    touched = 0
    for nw in values(data["nw"])
        for (_, _, d) in _iter_block_devices(nw)
            if get(d, "type", "") != "gfm"
                continue
            end
            carrier = String(get(d, "carrier", ""))
            convert = false
            if scenario == "battery_gfm_to_gfl"
                convert = carrier == "battery"
            elseif scenario == "thermal_gfm_to_gfl"
                convert = carrier in _THERMAL_CARRIERS
            elseif scenario == "nonsync_gfm_to_gfl"
                convert = carrier in _NONSYNC_CARRIERS
            end
            if convert
                d["type"] = "gfl"
                d["b_block"] = 0.0
                touched += 1
            end
        end
    end
    return touched
end

function _capacity_adequacy_check(data::Dict{String,Any})
    valid = true
    detail = Dict{Int,Float64}()
    for (nw_id, nw) in sort(collect(data["nw"]); by=x -> parse(Int, x.first))
        load = sum(get(load, "pd", 0.0) for load in values(get(nw, "load", Dict{String,Any}())) if get(load, "status", 1) != 0)
        gen_cap = 0.0
        for d in values(get(nw, "gen", Dict{String,Any}()))
            if get(d, "status", 1) == 0
                continue
            end
            if haskey(d, "nmax") && haskey(d, "p_block_max")
                gen_cap += d["p_block_max"] * d["nmax"]
            else
                gen_cap += get(d, "pmax", 0.0)
            end
        end
        st_cap = 0.0
        for d in values(get(nw, "storage", Dict{String,Any}()))
            if haskey(d, "nmax") && haskey(d, "p_block_max")
                st_cap += d["p_block_max"] * d["nmax"]
            else
                st_cap += get(d, "discharge_rating", 0.0)
            end
        end
        lhs = gen_cap + st_cap
        detail[parse(Int, nw_id)] = lhs - load
        valid &= lhs + _EPS >= load
    end
    return Dict("valid" => valid, "margin_by_snapshot" => detail, "min_margin" => minimum(values(detail)))
end

function _safe_objective(model)
    status = JuMP.termination_status(model)
    if status in (JuMP.MOI.OPTIMAL, JuMP.MOI.LOCALLY_SOLVED, JuMP.MOI.ALMOST_OPTIMAL)
        return JuMP.objective_value(model)
    end
    return nothing
end

function _sum_dispatch_abs(pm, nw::Int, key::Tuple{Symbol,Int})
    if key[1] == :gen
        return abs(JuMP.value(_PM.var(pm, nw, :pg, key[2])))
    end
    if haskey(_PM.var(pm, nw), :ps)
        ps = _PM.var(pm, nw, :ps)
        if key[2] in axes(ps, 1)
            return abs(JuMP.value(ps[key[2]]))
        end
    end
    if haskey(_PM.var(pm, nw), :sc) && haskey(_PM.var(pm, nw), :sd)
        sc = _PM.var(pm, nw, :sc)
        sd = _PM.var(pm, nw, :sd)
        if key[2] in axes(sc, 1) && key[2] in axes(sd, 1)
            return abs(JuMP.value(sc[key[2]])) + abs(JuMP.value(sd[key[2]]))
        end
    end
    return 0.0
end

function _bus_diag_from_pm(pm, nw::Int)
    bus_ids = sort(collect(_PM.ids(pm, nw, :bus)))
    b0 = _PM.ref(pm, nw, :gscr_b0)
    sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin)
    diag = Dict{Int,Float64}()
    offabs = Dict{Int,Float64}()
    for b in bus_ids
        diag[b] = b0[(b, b)]
        offabs[b] = sum(abs(b0[(b, j)]) for j in bus_ids if j != b)
    end
    return Dict("diag" => diag, "offabs" => offabs, "sigma0" => sigma0)
end

function _solve_active(data::Dict{String,Any}, run_label::String, mode_name::String)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _FP.build_uc_gscr_block_integration;
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    t0 = time()
    JuMP.optimize!(pm.model)
    elapsed = time() - t0
    status = _status_str(JuMP.termination_status(pm.model))

    result = Dict{String,Any}(
        "scenario" => run_label,
        "mode" => mode_name,
        "status" => status,
        "objective" => _safe_objective(pm.model),
        "solve_time_sec" => elapsed,
        "investment_cost" => nothing,
        "startup_cost" => nothing,
        "shutdown_cost" => nothing,
        "startup_count" => nothing,
        "shutdown_count" => nothing,
        "invested_gfm" => nothing,
        "invested_gfl" => nothing,
        "invested_gen" => nothing,
        "invested_storage" => nothing,
        "invested_battery_gfm" => nothing,
        "invested_battery_gfm_by_bus" => Dict{Int,Float64}(),
        "min_margin" => nothing,
        "min_margin_bus" => nothing,
        "min_margin_nw" => nothing,
        "near_binding" => 0,
        "online_gfm_by_snapshot" => Dict{Int,Float64}(),
        "online_gfl_by_snapshot" => Dict{Int,Float64}(),
        "dispatch_gfm_by_snapshot" => Dict{Int,Float64}(),
        "dispatch_gfl_by_snapshot" => Dict{Int,Float64}(),
        "battery_gfm_online_by_snapshot" => Dict{Int,Float64}(),
        "battery_gfm_dispatch_by_snapshot" => Dict{Int,Float64}(),
        "battery_gfm_online_by_bus_snapshot" => Dict{Tuple{Int,Int},Float64}(),
        "battery_gfm_dispatch_by_bus_snapshot" => Dict{Tuple{Int,Int},Float64}(),
        "battery_gfm_zero_dispatch_online_count" => nothing,
        "zero_dispatch_online_count" => nothing,
        "transition_residual_max" => nothing,
        "active_bound_violation_max" => nothing,
        "gscr_violation_max" => nothing,
        "n_shared_residual_max" => nothing,
        "investment_recon_residual" => nothing,
        "startup_cost_recon_residual" => nothing,
        "shutdown_cost_recon_residual" => nothing,
        "bus_diag" => Dict{String,Any}(),
        "bus_strength_summary" => Dict{Int,Dict{String,Any}}(),
        "weakest_bus_rows" => Dict{Int,Dict{String,Any}}(),
        "gfl_nameplate_by_bus" => Dict{Int,Float64}(),
        "gfm_strength_before_by_bus" => Dict{Int,Float64}(),
        "gfm_strength_after_by_bus" => Dict{Int,Float64}(),
        "rhs_snapshot_audit_rows" => Dict{Int,Vector{Dict{String,Any}}}(),
        "gfl_device_audit_rows" => Dict{String,Any}[],
        "gfm_device_strength_audit_rows" => Dict{String,Any}[],
        "rhs_total_by_snapshot" => Dict{Int,Float64}(),
        "rhs_assertions" => Dict{String,Any}(
            "has_positive_gfl_pmax" => false,
            "rhs_bus_positive_ok" => false,
            "rhs_total_positive_ok" => false,
            "rhs_positive_when_gmin_positive" => false,
            "rhs_zero_when_gmin_zero" => false,
            "messages" => String[],
        ),
        "rhs_builder_recon_max_diff" => nothing,
        "g_min_meta" => Dict{String,Any}(),
    )

    if !(status in _ACTIVE_OK)
        return result
    end

    nws = sort(collect(_FP.nw_ids(pm)))
    first_nw = first(nws)
    device_keys = sort(collect(_FP._uc_gscr_block_device_keys(pm, first_nw)); by=x -> (String(x[1]), x[2]))
    bus_ids = sort(collect(_PM.ids(pm, first_nw, :bus)))

    startup_cost = 0.0
    shutdown_cost = 0.0
    startup_count = 0.0
    shutdown_count = 0.0
    investment_cost = 0.0
    invested_gfm = 0.0
    invested_gfl = 0.0
    invested_gen = 0.0
    invested_storage = 0.0
    invested_battery_gfm = 0.0
    min_margin = Inf
    min_bus = first(bus_ids)
    min_nw = first_nw
    near_binding = 0
    zero_dispatch_online_count = 0
    battery_gfm_zero_dispatch_online_count = 0
    transition_residual_max = 0.0
    active_bound_vmax = 0.0
    gscr_vmax = 0.0
    n_shared_residual_max = 0.0
    rhs_builder_recon_max_diff = 0.0
    gfl_nameplate_by_bus = Dict(bus => 0.0 for bus in bus_ids)
    gfm_strength_before_by_bus = Dict(bus => 0.0 for bus in bus_ids)
    gfm_strength_after_by_bus = Dict(bus => 0.0 for bus in bus_ids)
    invested_battery_gfm_by_bus = Dict(bus => 0.0 for bus in bus_ids)

    bus_strength = Dict{Int,Dict{String,Any}}()
    for bus in bus_ids
        bus_strength[bus] = Dict{String,Any}(
            "installed_gfm_strength" => 0.0,
            "max_gfm_strength" => 0.0,
            "weakest_snapshot" => first_nw,
            "rhs_at_weakest" => 0.0,
            "margin_at_weakest" => Inf,
        )
    end

    for key in device_keys
        d = _PM.ref(pm, first_nw, key[1], key[2])
        bus = key[1] == :gen ? d["gen_bus"] : d["storage_bus"]
        n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
        n_first = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        dn = n_first - n0
        investment_cost += d["cost_inv_block"] * dn

        if d["type"] == "gfm"
            invested_gfm += dn
            bus_strength[bus]["installed_gfm_strength"] += d["b_block"] * n0
            bus_strength[bus]["max_gfm_strength"] += d["b_block"] * d["nmax"]
            gfm_strength_before_by_bus[bus] += d["b_block"] * n0
            gfm_strength_after_by_bus[bus] += d["b_block"] * n_first
        elseif d["type"] == "gfl"
            invested_gfl += dn
            gfl_nameplate_by_bus[bus] += float(get(d, "p_block_max", 0.0)) * n0
        end

        if _is_battery_gfm(d)
            invested_battery_gfm += dn
            invested_battery_gfm_by_bus[bus] += dn
        end

        if key[1] == :gen
            invested_gen += dn
        else
            invested_storage += dn
        end
        for nw in nws
            n_shared_residual_max = max(n_shared_residual_max, abs(JuMP.value(_PM.var(pm, nw, :n_block, key)) - n_first))
        end
    end

    rhs_by_bus_snapshot = Dict{Tuple{Int,Int},Float64}()
    gfl_na_by_bus_snapshot = Dict{Tuple{Int,Int},Float64}()
    gfl_pmax_na_by_bus_snapshot = Dict{Tuple{Int,Int},Float64}()
    gfm_b_na_by_bus_snapshot = Dict{Tuple{Int,Int},Float64}()

    for nw in nws
        gfl_online = 0.0
        gfm_online = 0.0
        gfl_dispatch = 0.0
        gfm_dispatch = 0.0
        battery_gfm_online = 0.0
        battery_gfm_dispatch = 0.0

        for key in device_keys
            d = _PM.ref(pm, nw, key[1], key[2])
            bus = key[1] == :gen ? d["gen_bus"] : d["storage_bus"]
            n = JuMP.value(_PM.var(pm, nw, :n_block, key))
            na = JuMP.value(_PM.var(pm, nw, :na_block, key))
            su = JuMP.value(_PM.var(pm, nw, :su_block, key))
            sd = JuMP.value(_PM.var(pm, nw, :sd_block, key))
            prev = _FP.is_first_id(pm, nw, :hour) ? d["na0"] : JuMP.value(_PM.var(pm, _FP.prev_id(pm, nw, :hour), :na_block, key))

            startup_cost += d["startup_block_cost"] * su
            shutdown_cost += d["shutdown_block_cost"] * sd
            startup_count += su
            shutdown_count += sd
            transition_residual_max = max(transition_residual_max, abs((na - prev) - (su - sd)))
            active_bound_vmax = max(active_bound_vmax, max(0.0, -na, na - n))

            disp = _sum_dispatch_abs(pm, nw, key)
            if d["type"] == "gfm"
                gfm_online += na
                gfm_dispatch += disp
            elseif d["type"] == "gfl"
                gfl_online += na
                gfl_dispatch += disp
            end
            if _is_battery_gfm(d)
                battery_gfm_online += na
                battery_gfm_dispatch += disp
                result["battery_gfm_online_by_bus_snapshot"][(nw, bus)] = get(result["battery_gfm_online_by_bus_snapshot"], (nw, bus), 0.0) + na
                result["battery_gfm_dispatch_by_bus_snapshot"][(nw, bus)] = get(result["battery_gfm_dispatch_by_bus_snapshot"], (nw, bus), 0.0) + disp
            end
            if na > 1.0 + _EPS && disp <= 1e-5
                zero_dispatch_online_count += 1
                if _is_battery_gfm(d)
                    battery_gfm_zero_dispatch_online_count += 1
                end
            end
        end
        result["online_gfm_by_snapshot"][nw] = gfm_online
        result["online_gfl_by_snapshot"][nw] = gfl_online
        result["dispatch_gfm_by_snapshot"][nw] = gfm_dispatch
        result["dispatch_gfl_by_snapshot"][nw] = gfl_dispatch
        result["battery_gfm_online_by_snapshot"][nw] = battery_gfm_online
        result["battery_gfm_dispatch_by_snapshot"][nw] = battery_gfm_dispatch

        for bus in bus_ids
            sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus)
            g_min = _PM.ref(pm, nw, :g_min)
            lhs_gfm = sum(
                _PM.ref(pm, nw, k[1], k[2], "b_block") * JuMP.value(_PM.var(pm, nw, :na_block, k))
                for k in _PM.ref(pm, nw, :bus_gfm_devices, bus);
                init=0.0,
            )
            rhs_sum = sum(
                _PM.ref(pm, nw, k[1], k[2], "p_block_max") * JuMP.value(_PM.var(pm, nw, :na_block, k))
                for k in _PM.ref(pm, nw, :bus_gfl_devices, bus);
                init=0.0,
            )
            rhs = g_min * rhs_sum

            rhs_sum_recon = 0.0
            for k in keys(_PM.ref(pm, nw, :gfl_devices))
                on_bus = (k[1] == :gen && _PM.ref(pm, nw, k[1], k[2], "gen_bus") == bus) ||
                         (k[1] != :gen && _PM.ref(pm, nw, k[1], k[2], "storage_bus") == bus)
                if on_bus
                    rhs_sum_recon += _PM.ref(pm, nw, k[1], k[2], "p_block_max") * JuMP.value(_PM.var(pm, nw, :na_block, k))
                end
            end
            rhs_builder_recon_max_diff = max(rhs_builder_recon_max_diff, abs(rhs_sum - rhs_sum_recon))

            margin = sigma0 + lhs_gfm - rhs
            if margin < min_margin
                min_margin = margin
                min_bus = bus
                min_nw = nw
            end
            if margin <= _NEAR
                near_binding += 1
            end
            gscr_vmax = max(gscr_vmax, max(0.0, -margin))

            row = bus_strength[bus]
            if margin < row["margin_at_weakest"]
                row["margin_at_weakest"] = margin
                row["weakest_snapshot"] = nw
                row["rhs_at_weakest"] = rhs
            end

            rhs_by_bus_snapshot[(nw, bus)] = rhs
            gfl_pmax_na_by_bus_snapshot[(nw, bus)] = rhs_sum
            gfm_b_na_by_bus_snapshot[(nw, bus)] = lhs_gfm
            gfl_na_by_bus_snapshot[(nw, bus)] = sum(JuMP.value(_PM.var(pm, nw, :na_block, k)) for k in _PM.ref(pm, nw, :bus_gfl_devices, bus); init=0.0)
        end
    end

    startup_cost_recon = 0.0
    shutdown_cost_recon = 0.0
    investment_cost_recon = 0.0
    for key in device_keys
        d = _PM.ref(pm, first_nw, key[1], key[2])
        n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
        n_first = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        investment_cost_recon += d["cost_inv_block"] * (n_first - n0)
        for nw in nws
            startup_cost_recon += d["startup_block_cost"] * JuMP.value(_PM.var(pm, nw, :su_block, key))
            shutdown_cost_recon += d["shutdown_block_cost"] * JuMP.value(_PM.var(pm, nw, :sd_block, key))
        end
    end

    result["startup_cost"] = startup_cost
    result["shutdown_cost"] = shutdown_cost
    result["startup_count"] = startup_count
    result["shutdown_count"] = shutdown_count
    result["investment_cost"] = investment_cost
    result["invested_gfm"] = invested_gfm
    result["invested_gfl"] = invested_gfl
    result["invested_gen"] = invested_gen
    result["invested_storage"] = invested_storage
    result["invested_battery_gfm"] = invested_battery_gfm
    result["invested_battery_gfm_by_bus"] = invested_battery_gfm_by_bus
    result["min_margin"] = min_margin
    result["min_margin_bus"] = min_bus
    result["min_margin_nw"] = min_nw
    result["binding_bus_snapshot"] = "bus=$(min_bus), snapshot=$(min_nw)"
    result["near_binding"] = near_binding
    result["zero_dispatch_online_count"] = zero_dispatch_online_count
    result["battery_gfm_zero_dispatch_online_count"] = battery_gfm_zero_dispatch_online_count
    result["transition_residual_max"] = transition_residual_max
    result["active_bound_violation_max"] = active_bound_vmax
    result["gscr_violation_max"] = gscr_vmax
    result["n_shared_residual_max"] = n_shared_residual_max
    result["investment_recon_residual"] = abs(investment_cost - investment_cost_recon)
    result["startup_cost_recon_residual"] = abs(startup_cost - startup_cost_recon)
    result["shutdown_cost_recon_residual"] = abs(shutdown_cost - shutdown_cost_recon)
    result["rhs_builder_recon_max_diff"] = rhs_builder_recon_max_diff
    result["bus_diag"] = _bus_diag_from_pm(pm, first_nw)
    result["bus_strength_summary"] = bus_strength
    result["weakest_bus_rows"] = bus_strength
    result["gfl_nameplate_by_bus"] = gfl_nameplate_by_bus
    result["gfm_strength_before_by_bus"] = gfm_strength_before_by_bus
    result["gfm_strength_after_by_bus"] = gfm_strength_after_by_bus

    selected = sort(unique([first_nw, min_nw, last(nws)]))
    for nw in selected
        rows = Dict{String,Any}[]
        rhs_total = 0.0
        for bus in bus_ids
            g_min = _PM.ref(pm, nw, :g_min)
            gfl_devices = _PM.ref(pm, nw, :bus_gfl_devices, bus)
            gfm_devices = _PM.ref(pm, nw, :bus_gfm_devices, bus)
            rhs_sum = gfl_pmax_na_by_bus_snapshot[(nw, bus)]
            rhs = rhs_by_bus_snapshot[(nw, bus)]
            lhs_gfm = gfm_b_na_by_bus_snapshot[(nw, bus)]
            sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus)
            margin = sigma0 + lhs_gfm - rhs
            rhs_total += rhs
            push!(rows, Dict{String,Any}(
                "nw" => nw,
                "bus" => bus,
                "g_min" => g_min,
                "gfl_count" => length(gfl_devices),
                "gfm_count" => length(gfm_devices),
                "sum_gfl_p_block_max_na" => rhs_sum,
                "rhs" => rhs,
                "sum_gfm_b_block_na" => lhs_gfm,
                "sigma0" => sigma0,
                "margin" => margin,
                "online_gfl_na" => gfl_na_by_bus_snapshot[(nw, bus)],
            ))
        end
        result["rhs_snapshot_audit_rows"][nw] = rows
        result["rhs_total_by_snapshot"][nw] = rhs_total
    end

    gfl_keys = sort(collect(keys(_PM.ref(pm, min_nw, :gfl_devices))); by=x -> (String(x[1]), x[2]))
    for k in gfl_keys
        d = _PM.ref(pm, min_nw, k[1], k[2])
        bus = k[1] == :gen ? d["gen_bus"] : d["storage_bus"]
        p_used = _PM.ref(pm, min_nw, k[1], k[2], "p_block_max")
        na = JuMP.value(_PM.var(pm, min_nw, :na_block, k))
        push!(result["gfl_device_audit_rows"], Dict{String,Any}(
            "component_key" => string(k),
            "component_type" => String(k[1]),
            "component_id" => k[2],
            "carrier" => String(get(d, "carrier", "")),
            "bus" => bus,
            "type" => String(get(d, "type", "")),
            "p_block_max_raw" => get(d, "p_block_max", NaN),
            "p_block_max_used" => p_used,
            "na_block_weakest_snapshot" => na,
            "contribution" => p_used * na,
            "in_gfl_devices" => haskey(_PM.ref(pm, min_nw, :gfl_devices), k),
            "in_bus_gfl_devices" => (k in _PM.ref(pm, min_nw, :bus_gfl_devices, bus)),
            "weakest_snapshot" => min_nw,
        ))
    end

    gfm_keys = sort(collect(keys(_PM.ref(pm, min_nw, :gfm_devices))); by=x -> (String(x[1]), x[2]))
    for k in gfm_keys
        d = _PM.ref(pm, min_nw, k[1], k[2])
        bus = k[1] == :gen ? d["gen_bus"] : d["storage_bus"]
        b_out = _PM.ref(pm, min_nw, k[1], k[2], "b_block")
        n0 = get(d, "n_block0", get(d, "n0", NaN))
        nmax = get(d, "n_block_max", get(d, "nmax", NaN))
        push!(result["gfm_device_strength_audit_rows"], Dict{String,Any}(
            "component_key" => string(k),
            "component_type" => String(k[1]),
            "component_id" => k[2],
            "carrier" => String(get(d, "carrier", "")),
            "bus" => bus,
            "type" => String(get(d, "type", "")),
            "b_gfm_input" => get(d, "b_gfm_input", get(d, "b_block", NaN)),
            "b_gfm_base" => get(d, "b_gfm_base", NaN),
            "s_block_mva" => get(d, "s_block", NaN),
            "b_block_output" => b_out,
            "n_block0" => n0,
            "n_block_max" => nmax,
            "installed_strength" => b_out * n0,
            "max_strength" => b_out * nmax,
        ))
    end

    assertion_messages = String[]
    gfl_positive_count = count(row -> row["p_block_max_used"] > _EPS, result["gfl_device_audit_rows"])
    has_positive_gfl_pmax = gfl_positive_count > 0
    if !has_positive_gfl_pmax
        push!(assertion_messages, "No GFL device with p_block_max > 0 found.")
    end

    rhs_bus_positive_ok = true
    for nw in nws
        for bus in bus_ids
            online_gfl = gfl_na_by_bus_snapshot[(nw, bus)]
            rhs_sum = gfl_pmax_na_by_bus_snapshot[(nw, bus)]
            if online_gfl > _EPS && rhs_sum <= _EPS
                rhs_bus_positive_ok = false
                push!(assertion_messages, "nw=$(nw) bus=$(bus): online GFL na>0 but RHS sum <= 0.")
            end
        end
    end

    rhs_total_positive_ok = true
    rhs_positive_when_gmin_positive = true
    rhs_zero_when_gmin_zero = true
    for nw in nws
        online_gfl_total = get(result["online_gfl_by_snapshot"], nw, 0.0)
        rhs_sum_total = sum(gfl_pmax_na_by_bus_snapshot[(nw, bus)] for bus in bus_ids)
        if online_gfl_total > _EPS && rhs_sum_total <= _EPS
            rhs_total_positive_ok = false
            push!(assertion_messages, "nw=$(nw): online GFL total > 0 but total sum_GFL_p_block_max_na <= 0.")
        end
        g_min = _PM.ref(pm, nw, :g_min)
        for bus in bus_ids
            rhs = rhs_by_bus_snapshot[(nw, bus)]
            if g_min > _EPS && gfl_na_by_bus_snapshot[(nw, bus)] > _EPS && rhs <= _EPS
                rhs_positive_when_gmin_positive = false
                push!(assertion_messages, "nw=$(nw) bus=$(bus): g_min>0 and online GFL>0 but RHS <= 0.")
            end
            if abs(g_min) <= _EPS && abs(rhs) > 1e-8
                rhs_zero_when_gmin_zero = false
                push!(assertion_messages, "nw=$(nw) bus=$(bus): g_min=0 but RHS is nonzero.")
            end
        end
    end

    result["rhs_assertions"] = Dict{String,Any}(
        "has_positive_gfl_pmax" => has_positive_gfl_pmax,
        "rhs_bus_positive_ok" => rhs_bus_positive_ok,
        "rhs_total_positive_ok" => rhs_total_positive_ok,
        "rhs_positive_when_gmin_positive" => rhs_positive_when_gmin_positive,
        "rhs_zero_when_gmin_zero" => rhs_zero_when_gmin_zero,
        "messages" => assertion_messages,
    )
    return result
end

function _run_mode(
    raw::Dict{String,Any},
    scenario::String,
    mode_name::String;
    policy_mode::String=mode_name,
    g_min_value::Float64=_BASELINE_GMIN,
    diag_candidates::Bool=false,
    diag_plan::Union{Nothing,Dict{String,Any}}=nothing,
)
    base_mode = policy_mode == "uc_only" ? :uc : :capexp
    data = _prepare_solver_data(raw; mode=base_mode)

    meta = Dict{String,Any}(
        "scenario" => scenario,
        "mode" => mode_name,
        "policy_mode" => policy_mode,
        "capacity_check" => Dict{String,Any}(),
        "g_min_value_injected" => g_min_value,
        "diagnostic_candidates_applied" => diag_candidates,
        "diagnostic_candidate_count" => 0,
        "diagnostic_candidate_rows" => Dict{String,Any}[],
        "g_min_sources" => Dict{Int,String}(),
        "g_min_values" => Dict{Int,Float64}(),
    )

    if diag_candidates
        if isnothing(diag_plan)
            error("Diagnostic candidates requested but no candidate plan was supplied.")
        end
        _apply_diagnostic_candidate_plan!(data, diag_plan)
        rows = get(diag_plan, "rows", Dict{String,Any}[])
        meta["diagnostic_candidate_count"] = length(rows)
        meta["diagnostic_candidate_rows"] = deepcopy(rows)
    end

    _set_mode_nmax_policy!(data, policy_mode)
    _inject_g_min!(data, g_min_value)

    for (nw_id, nw) in sort(collect(data["nw"]); by=x -> parse(Int, x.first))
        nwi = parse(Int, nw_id)
        meta["g_min_sources"][nwi] = String(get(nw, "_g_min_source", "unknown"))
        meta["g_min_values"][nwi] = get(nw, "g_min", NaN)
    end

    cap_check = _capacity_adequacy_check(data)
    meta["capacity_check"] = cap_check
    if !cap_check["valid"]
        return merge(
            Dict{String,Any}(
                "scenario" => scenario,
                "mode" => mode_name,
                "status" => "SKIPPED_INVALID_CAPACITY",
                "objective" => nothing,
                "solve_time_sec" => 0.0,
                "investment_cost" => nothing,
                "startup_cost" => nothing,
                "shutdown_cost" => nothing,
                "startup_count" => nothing,
                "shutdown_count" => nothing,
                "invested_gfm" => nothing,
                "invested_gfl" => nothing,
                "invested_gen" => nothing,
                "invested_storage" => nothing,
                "invested_battery_gfm" => nothing,
                "invested_battery_gfm_by_bus" => Dict{Int,Float64}(),
                "min_margin" => nothing,
                "near_binding" => 0,
                "online_gfm_by_snapshot" => Dict{Int,Float64}(),
                "online_gfl_by_snapshot" => Dict{Int,Float64}(),
                "dispatch_gfm_by_snapshot" => Dict{Int,Float64}(),
                "dispatch_gfl_by_snapshot" => Dict{Int,Float64}(),
                "battery_gfm_online_by_snapshot" => Dict{Int,Float64}(),
                "battery_gfm_dispatch_by_snapshot" => Dict{Int,Float64}(),
                "battery_gfm_online_by_bus_snapshot" => Dict{Tuple{Int,Int},Float64}(),
                "battery_gfm_dispatch_by_bus_snapshot" => Dict{Tuple{Int,Int},Float64}(),
                "zero_dispatch_online_count" => nothing,
                "battery_gfm_zero_dispatch_online_count" => nothing,
                "bus_diag" => Dict{String,Any}(),
                "bus_strength_summary" => Dict{Int,Dict{String,Any}}(),
                "gfl_nameplate_by_bus" => Dict{Int,Float64}(),
                "gfm_strength_before_by_bus" => Dict{Int,Float64}(),
                "gfm_strength_after_by_bus" => Dict{Int,Float64}(),
            ),
            Dict("meta" => meta),
        )
    end

    result = _solve_active(data, scenario, mode_name)
    result["meta"] = meta
    return result
end

function _avg(d::Dict{Int,Float64})
    return isempty(d) ? NaN : sum(values(d)) / length(d)
end

function _sumv(d::Dict{Int,Float64})
    return isempty(d) ? NaN : sum(values(d))
end

function _mode_order(mode::String)
    order = Dict(
        "baseline_uc_only" => 1,
        "baseline_full_capexp" => 2,
        "diagnostic_uc_only" => 3,
        "diagnostic_full_capexp" => 4,
        "diagnostic_storage_only" => 5,
        "diagnostic_generator_only" => 6,
    )
    return get(order, mode, 99)
end

function _find_record(records::Vector{Dict{String,Any}}, scenario::String, mode::String)
    rows = filter(r -> r["scenario"] == scenario && r["mode"] == mode, records)
    return isempty(rows) ? nothing : only(rows)
end

function _max_feasible_gmin(records::Vector{Dict{String,Any}}, mode::String)
    feasible = Float64[]
    for g in _GMIN_VALUES
        scen = "gmin_abs_$(replace(string(g), "." => "p"))"
        r = _find_record(records, scen, mode)
        if !isnothing(r) && r["status"] in _ACTIVE_OK
            push!(feasible, g)
        end
    end
    return isempty(feasible) ? nothing : maximum(feasible)
end

function _write_report(records::Vector{Dict{String,Any}}, diag_plan::Dict{String,Any})
    mkpath(dirname(_REPORT_PATH))
    sorted_rows = sort(get(diag_plan, "rows", Dict{String,Any}[]); by=x -> Int(x["bus"]))
    cost_by_bus = Dict(Int(r["bus"]) => float(r["cost_inv_block"]) for r in sorted_rows)
    battery_pmax_ref = isempty(sorted_rows) ? NaN : float(sorted_rows[1]["p_block_max"])

    open(_REPORT_PATH, "w") do io
        println(io, "# PyPSA 24h gSCR Sensitivity Study")
        println(io)
        println(io, "Generated by `test/pypsa_24h_gscr_sensitivity_study.jl` on ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"), ".")
        println(io, "Dataset: `", _dataset_path(), "`")
        println(io)
        println(io, "## Setup")
        println(io, "- Formulation unchanged: `n_block`, `na_block`, `su_block`, `sd_block`, block dispatch/storage, investment cost, startup/shutdown costs, AC-side Gershgorin gSCR.")
        println(io, "- Not activated: min-up/down, ramping, no-load costs, binary UC, SDP/LMI, new gSCR formulations.")
        println(io, "- Converter dataset remains unchanged; diagnostic additions are solver-copy only.")
        println(io)

        println(io, "## Comparison to OPF Plausibility Audit")
        println(io, "- Standard OPF path (`standard_opf_24h`) was `OPTIMAL`.")
        println(io, "- Max system active-power residual: `0.0`; max bus residual: `0.0`.")
        println(io, "- Max branch loading: about `92.26%`; overloaded branches: `0`.")
        println(io, "- Generator/storage bound violations: `0.0`.")
        println(io, "- DCP limits: reactive balance and voltage magnitudes are not checked.")
        println(io, "- UC/CAPEXP integration path is system-balance based; branch/voltage physics are not directly exposed in this path.")
        println(io)

        println(io, "## Diagnostic Local GFM Battery Candidate Study")
        println(io)
        println(io, "### A. Candidate Assumptions")
        println(io, "| bus | candidate id/key | carrier | type | p_block_max | p_block_min | q_block_min | q_block_max | e_block | b_block | n_block0 | n_block_max | cost_inv_block | startup_block_cost | shutdown_block_cost | marginal_cost/opex | cost source note | b_block source note |")
        println(io, "|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|")
        for row in sorted_rows
            mcost = get(row, "marginal_cost_available", false) ? row["marginal_cost_scaled"] : NaN
            println(io, "| ", Int(row["bus"]), " | ", row["candidate_id"], " | ", row["carrier"], " | ", row["type"], " | ", _fmt(row["p_block_max"]), " | ", _fmt(row["p_block_min"]), " | ", _fmt(row["q_block_min"]), " | ", _fmt(row["q_block_max"]), " | ", _fmt(row["e_block"]), " | ", _fmt(row["b_block"]), " | ", _fmt(row["n_block0"]), " | ", _fmt(row["n_block_max"]), " | ", _fmt(row["cost_inv_block"]), " | ", _fmt(row["startup_block_cost"]), " | ", _fmt(row["shutdown_block_cost"]), " | ", _fmt(mcost), " | ", row["cost_source_note"], " | ", row["b_block_source_note"], " |")
        end
        println(io, "- Candidate sizing target: `required_blocks_for_gmin3 = ceil(max(0, 3.0*local_GFL_nameplate - sigma0_G)/b_block)` with minimum `1` block.")
        println(io, "- `battery_gfm` b_block is diagnostic, not calibrated.")
        println(io, "- Marginal/OPEX usage note: ", get(diag_plan, "marginal_cost_used_in_objective_note", "n/a"))
        println(io)

        println(io, "### B. Feasibility by g_min and Mode")
        println(io, "| g_min | mode | status | objective | investment cost | startup cost | shutdown cost | invested battery_gfm blocks | invested total GFM blocks | invested total GFL blocks | invested generator blocks | invested storage blocks | min gSCR margin | near-binding count | binding bus/snapshot | average online GFM blocks | average online GFL blocks |")
        println(io, "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|")
        for g in _GMIN_VALUES
            scen = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in ("baseline_uc_only", "baseline_full_capexp", "diagnostic_uc_only", "diagnostic_full_capexp", "diagnostic_storage_only", "diagnostic_generator_only")
                r = _find_record(records, scen, mode)
                if isnothing(r)
                    continue
                end
                println(io, "| ", _fmt(g), " | ", mode, " | ", r["status"], " | ", _fmt(r["objective"]), " | ", _fmt(r["investment_cost"]), " | ", _fmt(r["startup_cost"]), " | ", _fmt(r["shutdown_cost"]), " | ", _fmt(r["invested_battery_gfm"]), " | ", _fmt(r["invested_gfm"]), " | ", _fmt(r["invested_gfl"]), " | ", _fmt(r["invested_gen"]), " | ", _fmt(r["invested_storage"]), " | ", _fmt(r["min_margin"]), " | ", r["near_binding"], " | ", get(r, "binding_bus_snapshot", "n/a"), " | ", _fmt(_avg(r["online_gfm_by_snapshot"])), " | ", _fmt(_avg(r["online_gfl_by_snapshot"])), " |")
            end
        end
        println(io)

        println(io, "### C. Investment by Bus (Solved Diagnostic CAPEXP and Storage-Only)")
        println(io, "| g_min | mode | bus | invested battery_gfm blocks | battery_gfm investment cost | local GFL nameplate | local GFM strength before investment | local GFM strength after investment | resulting local gSCR margin at weakest snapshot |")
        println(io, "|---:|---|---:|---:|---:|---:|---:|---:|---:|")
        for g in _GMIN_VALUES
            scen = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in ("diagnostic_full_capexp", "diagnostic_storage_only")
                r = _find_record(records, scen, mode)
                if isnothing(r) || !(r["status"] in _ACTIVE_OK)
                    continue
                end
                for row in sorted_rows
                    bus = Int(row["bus"])
                    inv = get(r["invested_battery_gfm_by_bus"], bus, 0.0)
                    inv_cost = inv * get(cost_by_bus, bus, 0.0)
                    margin = haskey(r["bus_strength_summary"], bus) ? r["bus_strength_summary"][bus]["margin_at_weakest"] : NaN
                    println(io, "| ", _fmt(g), " | ", mode, " | ", bus, " | ", _fmt(inv), " | ", _fmt(inv_cost), " | ", _fmt(get(r["gfl_nameplate_by_bus"], bus, NaN)), " | ", _fmt(get(r["gfm_strength_before_by_bus"], bus, NaN)), " | ", _fmt(get(r["gfm_strength_after_by_bus"], bus, NaN)), " | ", _fmt(margin), " |")
                end
            end
        end
        println(io)

        println(io, "### D. Online/Dispatch Behavior of battery_gfm (Solved Diagnostic Runs)")
        println(io, "| g_min | mode | snapshot | bus | battery_gfm_online_blocks | battery_gfm_dispatch_abs |")
        println(io, "|---:|---|---:|---:|---:|---:|")
        for g in _GMIN_VALUES
            scen = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in ("diagnostic_uc_only", "diagnostic_full_capexp", "diagnostic_storage_only", "diagnostic_generator_only")
                r = _find_record(records, scen, mode)
                if isnothing(r) || !(r["status"] in _ACTIVE_OK)
                    continue
                end
                keys_sorted = sort(collect(keys(r["battery_gfm_online_by_bus_snapshot"])); by=x -> (x[1], x[2]))
                for k in keys_sorted
                    online = r["battery_gfm_online_by_bus_snapshot"][k]
                    dispatch = get(r["battery_gfm_dispatch_by_bus_snapshot"], k, 0.0)
                    println(io, "| ", _fmt(g), " | ", mode, " | ", k[1], " | ", k[2], " | ", _fmt(online), " | ", _fmt(dispatch), " |")
                end
                total_online = _sumv(r["battery_gfm_online_by_snapshot"])
                total_dispatch = _sumv(r["battery_gfm_dispatch_by_snapshot"])
                avg_dispatch_per_online_block = (total_online isa Real && isfinite(total_online) && total_online > _EPS) ? total_dispatch / total_online : NaN
                support_flag = (avg_dispatch_per_online_block isa Real && isfinite(avg_dispatch_per_online_block) && battery_pmax_ref isa Real && isfinite(battery_pmax_ref) && avg_dispatch_per_online_block <= 0.05 * battery_pmax_ref) ? "yes" : "no_or_mixed"
                println(io, "- run g_min=", _fmt(g), ", mode=", mode, ": zero_dispatch_online_count=", _fmt(r["battery_gfm_zero_dispatch_online_count"]), ", avg_dispatch_per_online_block=", _fmt(avg_dispatch_per_online_block), ", mainly_grid_strength_support=", support_flag, ".")
            end
        end
        println(io)

        println(io, "### E. Comparison to OPF Plausibility Audit")
        println(io, "- Standard OPF was physically plausible in DCP.")
        println(io, "- Positive g_min infeasibility before adding local candidates was not explained by OPF balance/branch/storage invalidity.")
        println(io, "- This diagnostic specifically tests whether missing local GFM expansion options cause infeasibility under buswise gSCR.")
        full_pos = [r for r in records if r["mode"] == "diagnostic_full_capexp" && r["status"] in _ACTIVE_OK && parse(Float64, replace(replace(r["scenario"], "gmin_abs_" => ""), "p" => ".")) > 0.0]
        if !isempty(full_pos)
            println(io, "- Positive-g_min diagnostic CAPEXP runs became feasible. Branch-flow and voltage plausibility of these UC/CAPEXP runs is not directly checked in this integration path.")
        end
        println(io)

        println(io, "### Reconstruction Checks (Solved Diagnostic Runs)")
        println(io, "| g_min | mode | gSCR max violation | na/n bounds violation | n shared residual | startup/shutdown transition residual | investment recon residual | startup cost recon residual | shutdown cost recon residual | mode-specific assertion pass |")
        println(io, "|---:|---|---:|---:|---:|---:|---:|---:|---:|---|")
        for g in _GMIN_VALUES
            scen = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in ("diagnostic_uc_only", "diagnostic_full_capexp", "diagnostic_storage_only", "diagnostic_generator_only")
                r = _find_record(records, scen, mode)
                if isnothing(r) || !(r["status"] in _ACTIVE_OK)
                    continue
                end
                mode_assert = true
                if mode == "diagnostic_uc_only"
                    mode_assert &= abs(r["invested_battery_gfm"]) <= 1e-6
                elseif mode == "diagnostic_storage_only"
                    mode_assert &= abs(r["invested_gen"]) <= 1e-6
                elseif mode == "diagnostic_generator_only"
                    mode_assert &= abs(r["invested_storage"]) <= 1e-6
                    mode_assert &= abs(r["invested_battery_gfm"]) <= 1e-6
                end
                println(io, "| ", _fmt(g), " | ", mode, " | ", _fmt(r["gscr_violation_max"]), " | ", _fmt(r["active_bound_violation_max"]), " | ", _fmt(r["n_shared_residual_max"]), " | ", _fmt(r["transition_residual_max"]), " | ", _fmt(r["investment_recon_residual"]), " | ", _fmt(r["startup_cost_recon_residual"]), " | ", _fmt(r["shutdown_cost_recon_residual"]), " | ", mode_assert, " |")
            end
        end
        println(io)

        println(io, "### F. Interpretation")
        base_pos_infeasible = any(r["mode"] == "baseline_uc_only" && r["status"] ∉ _ACTIVE_OK && parse(Float64, replace(replace(r["scenario"], "gmin_abs_" => ""), "p" => ".")) > 0.0 for r in records)
        diag_pos_feasible = any(r["mode"] == "diagnostic_full_capexp" && r["status"] in _ACTIVE_OK && parse(Float64, replace(replace(r["scenario"], "gmin_abs_" => ""), "p" => ".")) > 0.0 for r in records)
        max_full = _max_feasible_gmin(records, "diagnostic_full_capexp")
        max_storage = _max_feasible_gmin(records, "diagnostic_storage_only")
        gen_pos_feasible = any(r["mode"] == "diagnostic_generator_only" && r["status"] in _ACTIVE_OK && parse(Float64, replace(replace(r["scenario"], "gmin_abs_" => ""), "p" => ".")) > 0.0 for r in records)
        invests_no_local_gfm = false
        for r in records
            if r["mode"] != "diagnostic_full_capexp" || !(r["status"] in _ACTIVE_OK)
                continue
            end
            for row in sorted_rows
                bus = Int(row["bus"])
                inv = get(r["invested_battery_gfm_by_bus"], bus, 0.0)
                if inv > _EPS && get(r["gfm_strength_before_by_bus"], bus, 0.0) <= _EPS && get(r["gfl_nameplate_by_bus"], bus, 0.0) > _EPS
                    invests_no_local_gfm = true
                end
            end
        end
        zero_dispatch_any = any((r["mode"] in ("diagnostic_uc_only", "diagnostic_full_capexp", "diagnostic_storage_only", "diagnostic_generator_only")) && (r["status"] in _ACTIVE_OK) && (get(r, "battery_gfm_zero_dispatch_online_count", 0.0) > 0.0) for r in records)
        println(io, "- Does adding local battery_gfm restore feasibility for g_min>0? ", diag_pos_feasible ? "yes" : "no", ".")
        println(io, "- Up to which g_min is full diagnostic CAPEXP feasible? ", isnothing(max_full) ? "none in tested range" : _fmt(max_full), ".")
        println(io, "- Is storage-only expansion sufficient? ", isnothing(max_storage) ? "no positive-g_min feasibility observed" : "yes up to g_min=" * _fmt(max_storage), ".")
        println(io, "- Does generator-only remain infeasible? ", gen_pos_feasible ? "no (some positive-g_min cases feasible)" : "yes (in tested positive-g_min range)", ".")
        println(io, "- Does investment occur at buses with no local GFM and positive local GFL RHS driver? ", invests_no_local_gfm ? "yes" : "not observed", ".")
        println(io, "- Are battery_gfm units online with zero dispatch? ", zero_dispatch_any ? "yes" : "not observed", ".")
        println(io, "- Does this indicate missing online/no-load cost may matter later? ", zero_dispatch_any ? "yes; zero-dispatch-online support appears and no-load cost may become important in later calibration." : "not indicated by this run set", ".")
        println(io, "- Is local buswise gSCR too restrictive without local GFM candidates? ", (base_pos_infeasible && diag_pos_feasible) ? "yes, strongly indicated by this diagnostic." : "not conclusively shown in tested range", ".")
        println(io, "- Next modeling/data decision: keep the local-candidate mechanism for diagnosis, then calibrate battery_gfm `b_block` on AC/B0 base and cost/no-load treatment before policy conclusions.")
    end
    return _REPORT_PATH
end

@testset "PyPSA 24h gSCR sensitivity study" begin
    if get(ENV, "RUN_PYPSA_24H_SENSITIVITY", "0") != "1"
        @info "Skipping 24h sensitivity study; set RUN_PYPSA_24H_SENSITIVITY=1 to execute" case=_dataset_path()
    elseif !isfile(_dataset_path())
        @test isfile(_dataset_path())
    else
        raw = _load_case()
        diag_plan = _build_diagnostic_candidate_plan(raw; target_gmin=3.0, minimum_candidate_blocks=1, candidate_b_block=0.2)
        records = Dict{String,Any}[]

        mode_specs = [
            ("baseline_uc_only", "uc_only", false),
            ("baseline_full_capexp", "full_capexp", false),
            ("diagnostic_uc_only", "uc_only", true),
            ("diagnostic_full_capexp", "full_capexp", true),
            ("diagnostic_storage_only", "storage_only", true),
            ("diagnostic_generator_only", "generator_only", true),
        ]

        for g in _GMIN_VALUES
            sname = "gmin_abs_$(replace(string(g), "." => "p"))"
            for (mode_name, policy_mode, use_diag) in mode_specs
                r = _run_mode(raw, sname, mode_name; policy_mode=policy_mode, g_min_value=g, diag_candidates=use_diag, diag_plan=diag_plan)
                push!(records, r)
                @test r["status"] in union(_DOC_STATUS, Set(["SKIPPED_INVALID_CAPACITY"]))
                if r["status"] in _ACTIVE_OK
                    @test r["transition_residual_max"] <= 1e-6
                    @test r["active_bound_violation_max"] <= 1e-6
                    @test r["gscr_violation_max"] <= 1e-6
                    @test r["n_shared_residual_max"] <= 1e-6
                    @test r["investment_recon_residual"] <= 1e-6
                    @test r["startup_cost_recon_residual"] <= 1e-6
                    @test r["shutdown_cost_recon_residual"] <= 1e-6
                end
                if mode_name == "diagnostic_uc_only" && r["status"] in _ACTIVE_OK
                    @test abs(r["invested_battery_gfm"]) <= 1e-6
                end
                if mode_name == "diagnostic_storage_only" && r["status"] in _ACTIVE_OK
                    @test abs(r["invested_gen"]) <= 1e-6
                end
                if mode_name == "diagnostic_generator_only" && r["status"] in _ACTIVE_OK
                    @test abs(r["invested_storage"]) <= 1e-6
                    @test abs(r["invested_battery_gfm"]) <= 1e-6
                end
            end
        end

        report = _write_report(records, diag_plan)
        @test isfile(report)
    end
end
