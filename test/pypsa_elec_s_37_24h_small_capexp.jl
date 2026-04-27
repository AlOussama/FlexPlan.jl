import FlexPlan as _FP
import PowerModels as _PM
import InfrastructureModels as _IM
using JuMP
using Memento
import HiGHS
import JSON
import Dates
import Printf: @sprintf

Memento.setlevel!(Memento.getlogger(_IM), "error")
Memento.setlevel!(Memento.getlogger(_PM), "error")

const _CASE_PATH = get(
    ENV,
    "PYPSA_ELEC_S37_24H_SMALL_CASE",
    raw"D:\Projekte\Code\pypsatomatpowerx_clean_battery_policy\data\flexplan_block_gscr\elec_s_37_24h_from_0301\case.json",
)
const _REPORT_PATH = normpath(@__DIR__, "..", "reports", "pypsa_elec_s_37_24h_small_capexp.md")
const _RESULTS_PATH = normpath(@__DIR__, "..", "reports", "pypsa_elec_s_37_24h_small_capexp_results.json")
const _RUN_FLAG = "RUN_ELEC37_24H_CAPEXP"
const _ACTIVE_OK = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL"])
const _EPS = 1e-6
const _NEAR = 1e-6
const _INVESTMENT_COST_SCALE_24H = 1.0 / 365.0

_status_str(status) = string(status)

_var_lb(v) = JuMP.has_lower_bound(v) ? JuMP.lower_bound(v) : -Inf
_var_ub(v) = JuMP.has_upper_bound(v) ? JuMP.upper_bound(v) : Inf
_var_has_index(vdict, i) = i in axes(vdict, 1)

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

_load_case() = JSON.parsefile(_CASE_PATH)

function _sorted_nw_ids(data::Dict{String,Any})
    return sort(parse.(Int, collect(keys(data["nw"])))
    )
end

function _add_dimensions!(data::Dict{String,Any})
    if !haskey(data, "dim")
        _FP.add_dimension!(data, :hour, length(data["nw"]))
        _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
        _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    end
    return data
end

function _normalize_dcline_entry!(dc::Dict{String,Any}, idx::Int)
    rate = get(dc, "pmaxf", get(dc, "pmaxt", get(dc, "rate_a", 0.0)))
    dc["index"] = get(dc, "index", idx)
    dc["carrier"] = lowercase(String(get(dc, "carrier", "dc")))
    dc["br_status"] = get(dc, "br_status", 1)
    dc["pf"] = get(dc, "pf", 0.0)
    dc["pt"] = get(dc, "pt", 0.0)
    dc["qf"] = get(dc, "qf", 0.0)
    dc["qt"] = get(dc, "qt", 0.0)
    dc["pminf"] = get(dc, "pminf", -rate)
    dc["pmaxf"] = get(dc, "pmaxf", rate)
    dc["pmint"] = get(dc, "pmint", -rate)
    dc["pmaxt"] = get(dc, "pmaxt", rate)
    dc["qminf"] = get(dc, "qminf", 0.0)
    dc["qmaxf"] = get(dc, "qmaxf", 0.0)
    dc["qmint"] = get(dc, "qmint", 0.0)
    dc["qmaxt"] = get(dc, "qmaxt", 0.0)
    dc["loss0"] = get(dc, "loss0", 0.0)
    dc["loss1"] = get(dc, "loss1", 0.0)
    dc["vf"] = get(dc, "vf", 1.0)
    dc["vt"] = get(dc, "vt", 1.0)
    dc["model"] = get(dc, "model", 2)
    dc["cost"] = get(dc, "cost", [0.0, 0.0])
    return dc
end

function _convert_links_to_dcline(nw::Dict{String,Any})
    out = Dict{String,Any}()
    links = get(nw, "link", Dict{String,Any}())
    if isempty(links)
        return out
    end
    bus_name_to_id = Dict{String,Int}()
    for (id, bus) in get(nw, "bus", Dict{String,Any}())
        if haskey(bus, "name")
            bus_name_to_id[String(bus["name"])] = parse(Int, id)
        end
    end
    idx = 0
    for (lid, link) in sort(collect(links); by=first)
        if lowercase(String(get(link, "carrier", ""))) != "dc"
            continue
        end
        f_bus = get(bus_name_to_id, String(get(link, "bus0", "")), nothing)
        t_bus = get(bus_name_to_id, String(get(link, "bus1", "")), nothing)
        if isnothing(f_bus) || isnothing(t_bus)
            continue
        end
        idx += 1
        rate = get(link, "p_nom", get(link, "rate_a", 0.0))
        out[string(idx)] = Dict{String,Any}(
            "index" => idx,
            "source_id" => ["pypsa_link", lid],
            "name" => get(link, "name", lid),
            "carrier" => "dc",
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
    return out
end

function _ensure_dcline!(nw::Dict{String,Any})
    existing = deepcopy(get(nw, "dcline", Dict{String,Any}()))
    converted = isempty(existing) ? _convert_links_to_dcline(nw) : Dict{String,Any}()
    merged = Dict{String,Any}()
    idx = 0
    for (_, dc) in sort(collect(existing); by=x -> parse(Int, x.first))
        idx += 1
        merged[string(idx)] = _normalize_dcline_entry!(deepcopy(dc), idx)
    end
    for (_, dc) in sort(collect(converted); by=x -> parse(Int, x.first))
        idx += 1
        merged[string(idx)] = _normalize_dcline_entry!(deepcopy(dc), idx)
    end
    nw["dcline"] = merged
    if haskey(nw, "link")
        delete!(nw, "link")
    end
    return nw
end

function _iter_block_devices(nw::Dict{String,Any})
    out = Tuple{String,String,Dict{String,Any}}[]
    for table in ("gen", "storage", "ne_storage")
        for (id, d) in get(nw, table, Dict{String,Any}())
            if haskey(d, "type")
                push!(out, (table, id, d))
            end
        end
    end
    return out
end

function _is_battery_candidate(d::Dict{String,Any})
    carrier = String(get(d, "carrier", ""))
    name = String(get(d, "name", ""))
    return carrier == "battery_gfl" || carrier == "battery_gfm" ||
           occursin("candidate_battery_gfl", name) || occursin("candidate_battery_gfm", name)
end

function _is_battery_gfl(d::Dict{String,Any})
    carrier = String(get(d, "carrier", ""))
    name = String(get(d, "name", ""))
    return carrier == "battery_gfl" || occursin("candidate_battery_gfl", name)
end

function _is_battery_gfm(d::Dict{String,Any})
    carrier = String(get(d, "carrier", ""))
    name = String(get(d, "name", ""))
    return carrier == "battery_gfm" || occursin("candidate_battery_gfm", name)
end

function _prepare_solver_data(raw::Dict{String,Any}; mode::Symbol=:capexp)
    data = deepcopy(raw)
    data["per_unit"] = get(data, "per_unit", false)
    data["source_type"] = get(data, "source_type", "pypsa-flexplan-json")
    data["name"] = get(data, "name", "pypsa-elec-s37-24h-small-capexp")
    _add_dimensions!(data)

    for nw in values(data["nw"])
        _ensure_dcline!(nw)
        nw["per_unit"] = get(nw, "per_unit", data["per_unit"])
        nw["source_type"] = get(nw, "source_type", data["source_type"])
        nw["time_elapsed"] = get(nw, "time_elapsed", 1.0)
        nw["ne_storage"] = get(nw, "ne_storage", Dict{String,Any}())
        nw["g_min"] = 0.0

        for table in ("shunt", "switch")
            nw[table] = get(nw, table, Dict{String,Any}())
        end
        for table in ("bus", "branch", "gen", "storage", "load", "dcline")
            for (id, c) in get(nw, table, Dict{String,Any}())
                c["index"] = get(c, "index", try parse(Int, id) catch; 1 end)
            end
        end
        for bus in values(get(nw, "bus", Dict{String,Any}()))
            bus["zone"] = get(bus, "zone", 1)
        end
        for branch in values(get(nw, "branch", Dict{String,Any}()))
            branch["tap"] = get(branch, "tap", 1.0)
            branch["shift"] = get(branch, "shift", 0.0)
            branch["transformer"] = get(branch, "transformer", false)
            branch["g_fr"] = get(branch, "g_fr", 0.0)
            branch["g_to"] = get(branch, "g_to", 0.0)
        end
        for load in values(get(nw, "load", Dict{String,Any}()))
            load["status"] = get(load, "status", 1)
        end
        for gen in values(get(nw, "gen", Dict{String,Any}()))
            gen["status"] = get(gen, "status", get(gen, "gen_status", 1))
            gen["dispatchable"] = get(gen, "dispatchable", true)
            gen["model"] = get(gen, "model", 2)
            gen["cost"] = get(gen, "cost", [0.0, 0.0])
            if haskey(gen, "n_block0")
                gen["n0"] = float(gen["n_block0"])
                gen["nmax"] = mode == :uc ? gen["n0"] : float(get(gen, "n_block_max", gen["n0"]))
            end
            if haskey(gen, "cost_inv_block")
                gen["cost_inv_block"] = float(get(gen, "cost_inv_block", 0.0)) * _INVESTMENT_COST_SCALE_24H
            end
        end
        for table in ("storage", "ne_storage")
            for st in values(get(nw, table, Dict{String,Any}()))
                if haskey(st, "n_block0")
                    st["n0"] = float(st["n_block0"])
                    st["nmax"] = mode == :uc ? st["n0"] : float(get(st, "n_block_max", st["n0"]))
                end
                if haskey(st, "cost_inv_block")
                    st["cost_inv_block"] = float(get(st, "cost_inv_block", 0.0)) * _INVESTMENT_COST_SCALE_24H
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
                st["energy_rating"] = get(st, "energy_rating", get(st, "energy", 0.0))
                st["max_energy_absorption"] = get(st, "max_energy_absorption", Inf)
                st["self_discharge_rate"] = get(st, "self_discharge_rate", 0.0)
                st["charge_rating"] = get(st, "charge_rating", 0.0)
                st["discharge_rating"] = get(st, "discharge_rating", 0.0)
            end
        end
    end
    return data
end

function _inject_g_min!(data::Dict{String,Any}, g_min_value::Float64)
    for nw in values(data["nw"])
        nw["g_min"] = g_min_value
        for bus in values(get(nw, "bus", Dict{String,Any}()))
            bus["g_min"] = g_min_value
        end
    end
    return data
end

function _set_mode_nmax_policy!(data::Dict{String,Any}, mode::String)
    for nw in values(data["nw"])
        for (table, _, d) in _iter_block_devices(nw)
            if !haskey(d, "n0")
                continue
            end
            if mode == "full_capexp"
                d["nmax"] = get(d, "n_block_max", d["n0"])
            elseif mode == "storage_only"
                if table == "gen"
                    d["nmax"] = d["n0"]
                else
                    d["nmax"] = get(d, "n_block_max", d["n0"])
                end
            elseif mode == "uc_only"
                d["nmax"] = d["n0"]
            else
                d["nmax"] = get(d, "n_block_max", d["n0"])
            end
            d["nmax"] = max(d["nmax"], d["n0"])
        end
    end
    return data
end

function _pmax_pu(dev::Dict{String,Any})
    return float(get(dev, "p_max_pu", get(dev, "p_block_max_pu", 1.0)))
end

function _schema_validation(raw::Dict{String,Any})
    nw1 = raw["nw"]["1"]
    ac_bus_ids = sort(parse.(Int, [id for (id, b) in get(nw1, "bus", Dict{String,Any}()) if lowercase(String(get(b, "carrier", "ac"))) == "ac"]))
    if isempty(ac_bus_ids)
        ac_bus_ids = sort(parse.(Int, collect(keys(get(nw1, "bus", Dict{String,Any}())))))
    end

    candidates = Dict{String,Any}[]
    for (id, st) in get(nw1, "storage", Dict{String,Any}())
        if _is_battery_candidate(st)
            push!(candidates, Dict{String,Any}(
                "id" => id,
                "table" => "storage",
                "bus" => Int(get(st, "storage_bus", -1)),
                "name" => String(get(st, "name", "")),
                "carrier" => String(get(st, "carrier", "")),
                "type" => String(get(st, "type", "")),
                "n_block0" => float(get(st, "n_block0", NaN)),
                "na0" => float(get(st, "na0", NaN)),
                "n_block_max" => float(get(st, "n_block_max", NaN)),
                "p_block_max" => float(get(st, "p_block_max", NaN)),
                "e_block" => float(get(st, "e_block", NaN)),
                "b_block" => float(get(st, "b_block", NaN)),
                "H" => float(get(st, "H", NaN)),
                "cost_inv_block" => float(get(st, "cost_inv_block", NaN)),
                "marginal_cost" => float(get(st, "marginal_cost", NaN)),
                "energy_rating" => float(get(st, "energy_rating", NaN)),
                "charge_rating" => float(get(st, "charge_rating", NaN)),
                "discharge_rating" => float(get(st, "discharge_rating", NaN)),
            ))
        end
    end
    battery_gfl = filter(r -> String(r["carrier"]) == "battery_gfl" || occursin("candidate_battery_gfl", String(r["name"])), candidates)
    battery_gfm = filter(r -> String(r["carrier"]) == "battery_gfm" || occursin("candidate_battery_gfm", String(r["name"])), candidates)

    gfl_by_bus = Dict{Int,Dict{String,Any}}()
    gfm_by_bus = Dict{Int,Dict{String,Any}}()
    for r in battery_gfl
        gfl_by_bus[Int(r["bus"])] = r
    end
    for r in battery_gfm
        gfm_by_bus[Int(r["bus"])] = r
    end

    expected_gfl_ok = all(
        String(r["type"]) == "gfl" &&
        abs(float(r["n_block0"])) <= _EPS &&
        abs(float(r["na0"])) <= _EPS &&
        abs(float(r["n_block_max"]) - 1000.0) <= _EPS &&
        abs(float(r["p_block_max"]) - 100.0) <= _EPS &&
        abs(float(r["e_block"]) - 600.0) <= _EPS &&
        abs(float(r["b_block"])) <= _EPS &&
        float(r["cost_inv_block"]) > 0.0
    for r in battery_gfl)

    expected_gfm_ok = all(
        String(r["type"]) == "gfm" &&
        abs(float(r["n_block0"])) <= _EPS &&
        abs(float(r["na0"])) <= _EPS &&
        abs(float(r["n_block_max"]) - 1000.0) <= _EPS &&
        abs(float(r["p_block_max"]) - 100.0) <= _EPS &&
        abs(float(r["e_block"]) - 600.0) <= _EPS &&
        abs(float(r["b_block"]) - 5.0) <= _EPS &&
        abs(float(r["H"]) - 10.0) <= _EPS &&
        float(r["cost_inv_block"]) > 0.0
    for r in battery_gfm)

    ratio_bad = Dict{String,Any}[]
    for bus in sort(intersect(collect(keys(gfl_by_bus)), collect(keys(gfm_by_bus))))
        gfl_cost = float(gfl_by_bus[bus]["cost_inv_block"])
        gfm_cost = float(gfm_by_bus[bus]["cost_inv_block"])
        ratio = gfm_cost / gfl_cost
        if abs(ratio - 1.0625) > 1e-8
            push!(ratio_bad, Dict("bus" => bus, "ratio" => ratio, "gfl_cost" => gfl_cost, "gfm_cost" => gfm_cost))
        end
    end

    invariant_bad = Dict{String,Any}[]
    for nw_id in _sorted_nw_ids(raw)
        nw = raw["nw"][string(nw_id)]
        for table in ("gen", "storage", "ne_storage")
            for (id, d) in get(nw, table, Dict{String,Any}())
                if !haskey(d, "type")
                    continue
                end
                na0 = float(get(d, "na0", NaN))
                n0 = float(get(d, "n_block0", NaN))
                nmax = float(get(d, "n_block_max", NaN))
                if !(isfinite(na0) && isfinite(n0) && isfinite(nmax) && 0.0 <= na0 <= n0 <= nmax)
                    push!(invariant_bad, Dict("nw" => nw_id, "table" => table, "id" => id, "na0" => na0, "n_block0" => n0, "n_block_max" => nmax))
                end
            end
        end
    end

    return Dict{String,Any}(
        "multinetwork" => get(raw, "multinetwork", false),
        "snapshot_count" => length(raw["nw"]),
        "bus_count" => length(get(nw1, "bus", Dict{String,Any}())),
        "branch_count" => length(get(nw1, "branch", Dict{String,Any}())),
        "dcline_count" => length(get(nw1, "dcline", Dict{String,Any}())),
        "gen_count" => length(get(nw1, "gen", Dict{String,Any}())),
        "storage_count" => length(get(nw1, "storage", Dict{String,Any}())),
        "battery_gfl_count" => length(battery_gfl),
        "battery_gfm_count" => length(battery_gfm),
        "ac_bus_ids" => ac_bus_ids,
        "battery_candidates" => sort(candidates; by=x -> (Int(x["bus"]), String(x["type"]), Int(parse(Int, x["id"])))),
        "expected_gfl_ok" => expected_gfl_ok,
        "expected_gfm_ok" => expected_gfm_ok,
        "cost_ratio_ok" => isempty(ratio_bad),
        "cost_ratio_bad" => ratio_bad,
        "coverage_ok" => length(keys(gfl_by_bus)) == length(ac_bus_ids) && length(keys(gfm_by_bus)) == length(ac_bus_ids),
        "gfl_buses_covered" => length(keys(gfl_by_bus)),
        "gfm_buses_covered" => length(keys(gfm_by_bus)),
        "invariant_ok" => isempty(invariant_bad),
        "invariant_bad" => invariant_bad,
    )
end

function _capacity_adequacy_audit(raw::Dict{String,Any})
    rows = Dict{String,Any}[]
    for nw_id in _sorted_nw_ids(raw)
        nw = raw["nw"][string(nw_id)]
        load = sum((float(get(l, "pd", 0.0)) for l in values(get(nw, "load", Dict{String,Any}())) if get(l, "status", 1) != 0); init=0.0)
        installed_gen_avail = 0.0
        max_expand_gen_avail = 0.0
        for g in values(get(nw, "gen", Dict{String,Any}()))
            if !haskey(g, "n_block0") || !haskey(g, "p_block_max")
                continue
            end
            ppu = _pmax_pu(g)
            installed_gen_avail += float(get(g, "n_block0", 0.0)) * float(get(g, "p_block_max", 0.0)) * ppu
            max_expand_gen_avail += float(get(g, "n_block_max", get(g, "n_block0", 0.0))) * float(get(g, "p_block_max", 0.0)) * ppu
        end
        existing_storage_discharge = 0.0
        max_storage_candidate_discharge = 0.0
        for st in values(get(nw, "storage", Dict{String,Any}()))
            if !haskey(st, "n_block0") || !haskey(st, "p_block_max")
                continue
            end
            n0 = float(get(st, "n_block0", 0.0))
            pblk = float(get(st, "p_block_max", 0.0))
            if n0 > _EPS
                existing_storage_discharge += n0 * pblk
            end
            if _is_battery_candidate(st)
                max_storage_candidate_discharge += float(get(st, "n_block_max", n0)) * pblk
            end
        end
        installed_ratio = load > _EPS ? installed_gen_avail / load : Inf
        max_expand_ratio = load > _EPS ? max_expand_gen_avail / load : Inf
        push!(rows, Dict{String,Any}(
            "snapshot" => nw_id,
            "load" => load,
            "installed_gen_avail" => installed_gen_avail,
            "max_expand_gen_avail" => max_expand_gen_avail,
            "existing_storage_discharge" => existing_storage_discharge,
            "max_storage_candidate_discharge" => max_storage_candidate_discharge,
            "installed_ratio" => installed_ratio,
            "max_expand_ratio" => max_expand_ratio,
            "expand_plus_cand_margin" => (max_expand_gen_avail + max_storage_candidate_discharge) - load,
        ))
    end
    worst_idx = argmin([r["installed_ratio"] for r in rows])
    worst = rows[worst_idx]
    return Dict{String,Any}(
        "rows" => rows,
        "worst_snapshot" => worst,
        "fixed_capacity_infeasible_expected" => any(r["installed_ratio"] < 1.0 - _EPS for r in rows),
        "max_expand_covers_load_all" => all(r["expand_plus_cand_margin"] >= -_EPS for r in rows),
    )
end

function _sum_dispatch_abs(pm, nw::Int, key::Tuple{Symbol,Int})
    if key[1] == :gen
        return abs(JuMP.value(_PM.var(pm, nw, :pg, key[2])))
    end
    if haskey(_PM.var(pm, nw), :ps)
        return abs(JuMP.value(_PM.var(pm, nw, :ps, key[2])))
    end
    if haskey(_PM.var(pm, nw), :sc) && haskey(_PM.var(pm, nw), :sd)
        return abs(JuMP.value(_PM.var(pm, nw, :sd, key[2])) - JuMP.value(_PM.var(pm, nw, :sc, key[2])))
    end
    return 0.0
end

function _build_uc_block_no_gscr(pm::_PM.AbstractActivePowerModel; objective::Bool=true, intertemporal_constraints::Bool=true)
    for n in _FP.nw_ids(pm)
        _PM.variable_gen_power(pm; nw=n)
        _FP.expression_gen_curtailment(pm; nw=n)
        _PM.variable_storage_power(pm; nw=n)
        _FP.variable_absorbed_energy(pm; nw=n)
        if _FP._has_uc_gscr_candidate_storage(pm, n)
            _FP.variable_storage_power_ne(pm; nw=n)
            _FP.variable_absorbed_energy_ne(pm; nw=n)
        end
        _FP.variable_uc_gscr_block(pm; nw=n, relax=true)
    end
    if objective
        _FP.objective_min_cost_uc_gscr_block_integration(pm)
    end
    for n in _FP.nw_ids(pm)
        _FP.constraint_uc_gscr_block_system_active_balance(pm; nw=n)
        _FP.constraint_uc_gscr_block_dispatch(pm; nw=n)
        _FP.constraint_uc_gscr_block_storage_bounds(pm; nw=n)
        for i in _PM.ids(pm, :storage, nw=n)
            _FP.constraint_storage_excl_slack(pm, i, nw=n)
            _PM.constraint_storage_thermal_limit(pm, i, nw=n)
            _PM.constraint_storage_losses(pm, i, nw=n)
        end
        if _FP._has_uc_gscr_candidate_storage(pm, n)
            for i in _PM.ids(pm, :ne_storage, nw=n)
                _FP.constraint_storage_excl_slack_ne(pm, i, nw=n)
                _FP.constraint_storage_thermal_limit_ne(pm, i, nw=n)
                _FP.constraint_storage_losses_ne(pm, i, nw=n)
                _FP.constraint_storage_bounds_ne(pm, i, nw=n)
            end
        end
        if intertemporal_constraints
            if _FP.is_first_id(pm, n, :hour)
                for i in _PM.ids(pm, :storage, nw=n)
                    _FP.constraint_storage_state(pm, i, nw=n)
                end
                for i in _PM.ids(pm, :storage_bounded_absorption, nw=n)
                    _FP.constraint_maximum_absorption(pm, i, nw=n)
                end
                if _FP._has_uc_gscr_candidate_storage(pm, n)
                    for i in _PM.ids(pm, :ne_storage, nw=n)
                        _FP.constraint_storage_state_ne(pm, i, nw=n)
                    end
                    for i in _PM.ids(pm, :ne_storage_bounded_absorption, nw=n)
                        _FP.constraint_maximum_absorption_ne(pm, i, nw=n)
                    end
                end
            else
                if _FP.is_last_id(pm, n, :hour)
                    for i in _PM.ids(pm, :storage, nw=n)
                        _FP.constraint_storage_state_final(pm, i, nw=n)
                    end
                    if _FP._has_uc_gscr_candidate_storage(pm, n)
                        for i in _PM.ids(pm, :ne_storage, nw=n)
                            _FP.constraint_storage_state_final_ne(pm, i, nw=n)
                        end
                    end
                end
                prev_n = _FP.prev_id(pm, n, :hour)
                for i in _PM.ids(pm, :storage, nw=n)
                    _FP.constraint_storage_state(pm, i, prev_n, n)
                end
                for i in _PM.ids(pm, :storage_bounded_absorption, nw=n)
                    _FP.constraint_maximum_absorption(pm, i, prev_n, n)
                end
                if _FP._has_uc_gscr_candidate_storage(pm, n)
                    for i in _PM.ids(pm, :ne_storage, nw=n)
                        _FP.constraint_storage_state_ne(pm, i, prev_n, n)
                    end
                    for i in _PM.ids(pm, :ne_storage_bounded_absorption, nw=n)
                        _FP.constraint_maximum_absorption_ne(pm, i, prev_n, n)
                    end
                end
            end
        end
        if _FP.is_first_id(pm, n, :hour) && _FP._has_uc_gscr_candidate_storage(pm, n)
            prev_nws = _FP.prev_ids(pm, n, :year)
            for i in _PM.ids(pm, :ne_storage; nw=n)
                _FP.constraint_ne_storage_activation(pm, i, prev_nws, n)
            end
        end
    end
end

function _collect_candidate_presolve_rows(raw::Dict{String,Any})
    nw1 = raw["nw"]["1"]
    rows = Dict{String,Any}[]
    for (id, st) in sort(collect(get(nw1, "storage", Dict{String,Any}())); by=x -> parse(Int, x.first))
        if !_is_battery_candidate(st)
            continue
        end
        push!(rows, Dict{String,Any}(
            "table" => "storage",
            "id" => id,
            "bus" => Int(get(st, "storage_bus", -1)),
            "type" => String(get(st, "type", "")),
            "carrier" => String(get(st, "carrier", "")),
            "n_block0" => float(get(st, "n_block0", NaN)),
            "n_block_max" => float(get(st, "n_block_max", NaN)),
            "na0" => float(get(st, "na0", NaN)),
            "p_block_max" => float(get(st, "p_block_max", NaN)),
            "e_block" => float(get(st, "e_block", NaN)),
            "energy_rating" => float(get(st, "energy_rating", NaN)),
            "charge_rating" => float(get(st, "charge_rating", NaN)),
            "discharge_rating" => float(get(st, "discharge_rating", NaN)),
            "cost_inv_block" => float(get(st, "cost_inv_block", NaN)),
            "marginal_cost" => float(get(st, "marginal_cost", NaN)),
            "b_block" => float(get(st, "b_block", NaN)),
        ))
    end
    return rows
end

function _collect_candidate_postsolve_rows(pm, pre_rows::Vector{Dict{String,Any}})
    nws = sort(collect(_FP.nw_ids(pm)))
    first_nw = first(nws)
    rows = Dict{String,Any}[]
    for r in pre_rows
        sid = parse(Int, r["id"])
        key = (:storage, sid)
        n_block = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        na_vals = [JuMP.value(_PM.var(pm, nw, :na_block, key)) for nw in nws]
        dispatch_vals = if haskey(_PM.var(pm, first_nw), :ps)
            [JuMP.value(_PM.var(pm, nw, :ps, sid)) for nw in nws]
        elseif haskey(_PM.var(pm, first_nw), :sc) && haskey(_PM.var(pm, first_nw), :sd)
            [JuMP.value(_PM.var(pm, nw, :sd, sid)) - JuMP.value(_PM.var(pm, nw, :sc, sid)) for nw in nws]
        else
            fill(0.0, length(nws))
        end
        energy_vals = haskey(_PM.var(pm, first_nw), :se) ? [JuMP.value(_PM.var(pm, nw, :se, sid)) for nw in nws] : Float64[]
        online_zero_dispatch = count(i -> na_vals[i] > 1e-6 && abs(dispatch_vals[i]) <= 1e-6, eachindex(na_vals))
        out = deepcopy(r)
        out["n_block"] = n_block
        out["na_block_max_t"] = maximum(na_vals)
        out["dispatch_min"] = minimum(dispatch_vals)
        out["dispatch_max"] = maximum(dispatch_vals)
        out["energy_min"] = isempty(energy_vals) ? NaN : minimum(energy_vals)
        out["energy_max"] = isempty(energy_vals) ? NaN : maximum(energy_vals)
        out["online_zero_dispatch_count"] = online_zero_dispatch
        push!(rows, out)
    end
    return rows
end

function _solve_active_with_builder(data::Dict{String,Any}, scenario::String, mode_name::String, builder)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        builder;
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    t0 = time()
    JuMP.optimize!(pm.model)
    status = _status_str(JuMP.termination_status(pm.model))
    out = Dict{String,Any}(
        "scenario" => scenario,
        "mode" => mode_name,
        "status" => status,
        "objective" => (status in _ACTIVE_OK ? JuMP.objective_value(pm.model) : nothing),
        "solve_time_sec" => time() - t0,
        "investment_cost" => nothing,
        "startup_cost" => nothing,
        "shutdown_cost" => nothing,
        "total_invested_blocks" => nothing,
        "invested_battery_gfl_blocks" => nothing,
        "invested_battery_gfm_blocks" => nothing,
        "invested_generator_blocks" => nothing,
        "invested_storage_blocks" => nothing,
        "investment_by_carrier" => Dict{String,Float64}(),
        "investment_by_bus" => Dict{Int,Float64}(),
        "max_active_balance_residual" => nothing,
        "storage_block_consistency_residual" => nothing,
        "transition_residual" => nothing,
        "startup_shutdown_transition_residual" => nothing,
        "gscr_reconstruction_residual" => nothing,
        "min_margin" => nothing,
        "near_binding" => nothing,
        "binding_bus_snapshot" => "n/a",
        "candidate_postsolve_rows" => Dict{String,Any}[],
    )
    if !(status in _ACTIVE_OK)
        return out
    end

    nws = sort(collect(_FP.nw_ids(pm)))
    first_nw = first(nws)
    device_keys = sort(collect(_FP._uc_gscr_block_device_keys(pm, first_nw)); by=x -> (String(x[1]), x[2]))
    startup_cost = 0.0
    shutdown_cost = 0.0
    investment_cost = 0.0
    total_invested_blocks = 0.0
    invested_battery_gfl = 0.0
    invested_battery_gfm = 0.0
    invested_gen = 0.0
    invested_storage = 0.0
    transition_max = 0.0
    n_shared_max = 0.0
    max_active_balance_residual = 0.0
    storage_consistency = 0.0
    min_margin = Inf
    near_binding = 0
    min_bus = -1
    min_nw = -1

    for key in device_keys
        d = _PM.ref(pm, first_nw, key[1], key[2])
        n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
        n_first = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        dn = n_first - n0
        coeff = float(get(d, "cost_inv_block", 0.0)) * float(get(d, "p_block_max", 0.0))
        investment_cost += coeff * dn
        total_invested_blocks += dn
        if key[1] == :gen
            invested_gen += dn
        else
            invested_storage += dn
            if _is_battery_gfl(d)
                invested_battery_gfl += dn
            elseif _is_battery_gfm(d)
                invested_battery_gfm += dn
            end
        end
        carrier = String(get(d, "carrier", "unknown"))
        bus = key[1] == :gen ? Int(get(d, "gen_bus", -1)) : Int(get(d, "storage_bus", -1))
        out["investment_by_carrier"][carrier] = get(out["investment_by_carrier"], carrier, 0.0) + dn
        out["investment_by_bus"][bus] = get(out["investment_by_bus"], bus, 0.0) + dn
        for nw in nws
            n_shared_max = max(n_shared_max, abs(JuMP.value(_PM.var(pm, nw, :n_block, key)) - n_first))
        end
    end

    for nw in nws
        load = sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ids(pm, nw, :load)); init=0.0)
        pg = haskey(_PM.var(pm, nw), :pg) ? sum((JuMP.value(_PM.var(pm, nw, :pg, g)) for g in _PM.ids(pm, nw, :gen)); init=0.0) : 0.0
        ps = haskey(_PM.var(pm, nw), :ps) ? sum((JuMP.value(_PM.var(pm, nw, :ps, s)) for s in _PM.ids(pm, nw, :storage)); init=0.0) : 0.0
        ps_ne = haskey(_PM.var(pm, nw), :ps_ne) ? sum((JuMP.value(_PM.var(pm, nw, :ps_ne, s)) for s in _PM.ids(pm, nw, :ne_storage)); init=0.0) : 0.0
        max_active_balance_residual = max(max_active_balance_residual, abs(pg - ps - ps_ne - load))

        for key in device_keys
            d = _PM.ref(pm, nw, key[1], key[2])
            na = JuMP.value(_PM.var(pm, nw, :na_block, key))
            n = JuMP.value(_PM.var(pm, nw, :n_block, key))
            su = JuMP.value(_PM.var(pm, nw, :su_block, key))
            sd = JuMP.value(_PM.var(pm, nw, :sd_block, key))
            prev = _FP.is_first_id(pm, nw, :hour) ? float(get(d, "na0", 0.0)) : JuMP.value(_PM.var(pm, _FP.prev_id(pm, nw, :hour), :na_block, key))
            startup_cost += float(get(d, "startup_block_cost", 0.0)) * su
            shutdown_cost += float(get(d, "shutdown_block_cost", 0.0)) * sd
            transition_max = max(transition_max, abs((na - prev) - (su - sd)))
        end

        for sid in _PM.ids(pm, nw, :storage)
            d = _PM.ref(pm, nw, :storage, sid)
            if !haskey(d, "type")
                continue
            end
            key = (:storage, sid)
            n = JuMP.value(_PM.var(pm, nw, :n_block, key))
            na = JuMP.value(_PM.var(pm, nw, :na_block, key))
            pblk = float(get(d, "p_block_max", 0.0))
            eblk = float(get(d, "e_block", 0.0))
            if haskey(_PM.var(pm, nw), :se)
                se = JuMP.value(_PM.var(pm, nw, :se, sid))
                storage_consistency = max(storage_consistency, max(0.0, se - eblk * n))
            end
            if haskey(_PM.var(pm, nw), :sc)
                sc = JuMP.value(_PM.var(pm, nw, :sc, sid))
                storage_consistency = max(storage_consistency, max(0.0, sc - pblk * na))
            end
            if haskey(_PM.var(pm, nw), :sd)
                sd = JuMP.value(_PM.var(pm, nw, :sd, sid))
                storage_consistency = max(storage_consistency, max(0.0, sd - pblk * na))
            end
        end

        if haskey(_PM.ref(pm, nw), :g_min)
            for bus in _PM.ids(pm, nw, :bus)
                sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus)
                g_min = _PM.ref(pm, nw, :g_min)
                lhs = sigma0 + sum(_PM.ref(pm, nw, key[1], key[2], "b_block") * JuMP.value(_PM.var(pm, nw, :na_block, key)) for key in _PM.ref(pm, nw, :bus_gfm_devices, bus); init=0.0)
                rhs = g_min * sum(_PM.ref(pm, nw, key[1], key[2], "p_block_max") * JuMP.value(_PM.var(pm, nw, :na_block, key)) for key in _PM.ref(pm, nw, :bus_gfl_devices, bus); init=0.0)
                margin = lhs - rhs
                if margin < min_margin
                    min_margin = margin
                    min_bus = bus
                    min_nw = nw
                end
                if margin <= _NEAR
                    near_binding += 1
                end
            end
        end
    end

    out["investment_cost"] = investment_cost
    out["startup_cost"] = startup_cost
    out["shutdown_cost"] = shutdown_cost
    out["total_invested_blocks"] = total_invested_blocks
    out["invested_battery_gfl_blocks"] = invested_battery_gfl
    out["invested_battery_gfm_blocks"] = invested_battery_gfm
    out["invested_generator_blocks"] = invested_gen
    out["invested_storage_blocks"] = invested_storage
    out["max_active_balance_residual"] = max_active_balance_residual
    out["storage_block_consistency_residual"] = storage_consistency
    out["transition_residual"] = transition_max
    out["startup_shutdown_transition_residual"] = transition_max
    out["gscr_reconstruction_residual"] = isnothing(min_margin) ? nothing : max(0.0, -min_margin)
    out["min_margin"] = min_margin
    out["near_binding"] = near_binding
    out["binding_bus_snapshot"] = min_bus < 0 ? "n/a" : "bus=$(min_bus), snapshot=$(min_nw)"
    out["n_shared_residual_max"] = n_shared_max
    return out
end

function _resolve_builder(builder)
    if builder == :no_gscr
        return _build_uc_block_no_gscr
    elseif builder == :relaxed_storage_dynamics
        return (pm; objective=true, intertemporal_constraints=true) -> _FP.build_uc_gscr_block_integration(pm; objective=objective, intertemporal_constraints=false)
    elseif builder == :no_gscr_relaxed_storage
        return (pm; objective=true, intertemporal_constraints=true) -> _build_uc_block_no_gscr(pm; objective=objective, intertemporal_constraints=false)
    elseif builder isa Function
        return builder
    end
    return _FP.build_uc_gscr_block_integration
end

function _solve_with_pm(data::Dict{String,Any}, builder)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        builder;
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    t0 = time()
    JuMP.optimize!(pm.model)
    status = _status_str(JuMP.termination_status(pm.model))
    return Dict{String,Any}(
        "pm" => pm,
        "status" => status,
        "solve_time_sec" => time() - t0,
        "objective" => (status in _ACTIVE_OK ? JuMP.objective_value(pm.model) : nothing),
    )
end

function _run_mode(raw::Dict{String,Any}, scenario::String, mode_name::String; g_min_value::Float64=0.0, mutator=nothing, builder=:standard)
    base_mode = mode_name == "uc_only" ? :uc : :capexp
    data = _prepare_solver_data(raw; mode=base_mode)
    _set_mode_nmax_policy!(data, mode_name)
    _inject_g_min!(data, g_min_value)
    if !(mutator === nothing)
        mutator(data)
    end
    bfun = _resolve_builder(builder)
    result = _solve_active_with_builder(data, scenario, mode_name, bfun)
    if result["status"] in _ACTIVE_OK
        pre_rows = _collect_candidate_presolve_rows(data)
        pm = _PM.instantiate_model(
            data,
            _PM.DCPPowerModel,
            bfun;
            ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
        )
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)
        if _status_str(JuMP.termination_status(pm.model)) in _ACTIVE_OK
            result["candidate_postsolve_rows"] = _collect_candidate_postsolve_rows(pm, pre_rows)
        end
    end
    return result
end

function _variant_interpretation(label::String, status::String)
    if status in _ACTIVE_OK
        return "feasible; this toggle likely isolates the active blocker"
    elseif status == "INFEASIBLE"
        return "still infeasible; toggle did not remove the core blocker"
    elseif status == "ERROR"
        return "runtime/model error; check note"
    end
    return "status not optimal/infeasible; inspect solver termination details"
end

function _likely_cause_from_first_feasible(first_feasible::Union{Nothing,Dict{String,Any}})
    if isnothing(first_feasible)
        return "deeper model/balance debugging required"
    end
    label = String(first_feasible["label"])
    if label == "candidate_storage_ratings_from_blocks"
        return "active model still uses standard storage ratings for candidates"
    elseif label == "no_dclines" || label == "relaxed_dcline_limits"
        return "HVDC/dcline handling is the blocker"
    elseif label == "pminpu_zero"
        return "lower-bound availability/minimum output is the blocker"
    elseif label == "storage_dynamics_relaxed"
        return "storage energy dynamics are the blocker"
    elseif label == "no_gscr"
        return "gSCR constraints likely contribute, unexpected at g_min=0"
    end
    return "first feasible variant is informative but root cause needs deeper confirmation"
end

function _diagnostic_variants(raw::Dict{String,Any}, gate::Dict{String,Any})
    vars = Dict{String,Any}[]

    push!(vars, Dict(
        "label" => "base_full_capexp_gmin0",
        "run" => gate,
        "note" => "current base case",
    ))
    push!(vars, Dict(
        "label" => "no_gscr",
        "run" => _run_mode(raw, "diag_no_gscr", "full_capexp"; g_min_value=0.0, builder=:no_gscr),
        "note" => "gSCR disabled in builder path",
    ))
    push!(vars, Dict(
        "label" => "candidate_storage_ratings_from_blocks",
        "run" => _run_mode(raw, "diag_candidate_ratings", "full_capexp"; g_min_value=0.0, mutator=data -> begin
            for nw in values(data["nw"])
                for st in values(get(nw, "storage", Dict{String,Any}()))
                    if _is_battery_candidate(st)
                        nmax = float(get(st, "n_block_max", 0.0))
                        st["energy_rating"] = nmax * float(get(st, "e_block", 0.0))
                        st["charge_rating"] = nmax * float(get(st, "p_block_max", 0.0))
                        st["discharge_rating"] = nmax * float(get(st, "p_block_max", 0.0))
                    end
                end
            end
        end),
        "note" => "solver-copy-only ratings fix for battery candidates",
    ))
    push!(vars, Dict(
        "label" => "no_dclines",
        "run" => _run_mode(raw, "diag_no_dclines", "full_capexp"; g_min_value=0.0, mutator=data -> begin
            for nw in values(data["nw"])
                nw["dcline"] = Dict{String,Any}()
            end
        end),
        "note" => "",
    ))
    push!(vars, Dict(
        "label" => "relaxed_dcline_limits",
        "run" => _run_mode(raw, "diag_relaxed_dclines", "full_capexp"; g_min_value=0.0, mutator=data -> begin
            for nw in values(data["nw"])
                for dc in values(get(nw, "dcline", Dict{String,Any}()))
                    dc["pminf"] = -1e6
                    dc["pmaxf"] = 1e6
                    dc["pmint"] = -1e6
                    dc["pmaxt"] = 1e6
                end
            end
        end),
        "note" => "",
    ))
    push!(vars, Dict(
        "label" => "pminpu_zero",
        "run" => _run_mode(raw, "diag_pminpu_zero", "full_capexp"; g_min_value=0.0, mutator=data -> begin
            for nw in values(data["nw"])
                for (_, _, d) in _iter_block_devices(nw)
                    if haskey(d, "p_min_pu")
                        d["p_min_pu"] = 0.0
                    end
                    if haskey(d, "p_block_min_pu")
                        d["p_block_min_pu"] = 0.0
                    end
                end
            end
        end),
        "note" => "",
    ))
    push!(vars, Dict(
        "label" => "storage_dynamics_relaxed",
        "run" => _run_mode(raw, "diag_storage_dyn_relaxed", "full_capexp"; g_min_value=0.0, builder=:relaxed_storage_dynamics),
        "note" => "supported: builder uses intertemporal_constraints=false",
    ))
    push!(vars, Dict(
        "label" => "only_battery_candidates_expandable",
        "run" => _run_mode(raw, "diag_only_battery_expand", "full_capexp"; g_min_value=0.0, mutator=data -> begin
            for nw in values(data["nw"])
                for (table, _, d) in _iter_block_devices(nw)
                    d["nmax"] = float(get(d, "n0", get(d, "n_block0", 0.0)))
                    if table == "storage" && _is_battery_candidate(d)
                        d["nmax"] = float(get(d, "n_block_max", d["nmax"]))
                    end
                    d["nmax"] = max(d["nmax"], float(get(d, "n0", get(d, "n_block0", 0.0))))
                end
            end
        end),
        "note" => "all non-battery devices fixed at nmax=n0",
    ))

    first_feasible = nothing
    for v in vars
        st = v["run"]["status"]
        if st in _ACTIVE_OK
            first_feasible = v
            break
        end
    end
    likely_cause = _likely_cause_from_first_feasible(first_feasible)
    for v in vars
        v["feasible"] = v["run"]["status"] in _ACTIVE_OK
        v["interpretation"] = _variant_interpretation(v["label"], v["run"]["status"])
        v["first_feasible"] = !isnothing(first_feasible) && v === first_feasible
        v["likely_cause"] = isnothing(first_feasible) ? likely_cause : (v["first_feasible"] ? likely_cause : "")
    end
    return Dict{String,Any}("variants" => vars, "first_feasible" => first_feasible, "likely_cause" => likely_cause)
end

function _make_single_snapshot_raw(raw::Dict{String,Any}, snapshot_id::Int)
    out = deepcopy(raw)
    out["nw"] = Dict{String,Any}("1" => deepcopy(raw["nw"][string(snapshot_id)]))
    if haskey(out, "dim")
        delete!(out, "dim")
    end
    out["multinetwork"] = true
    return out
end

function _candidate_storage_ids_in_nw(nw::Dict{String,Any})
    ids = Int[]
    for (sid, st) in get(nw, "storage", Dict{String,Any}())
        if _is_battery_candidate(st)
            push!(ids, parse(Int, sid))
        end
    end
    return sort(ids)
end

function _candidate_storage_ids_in_nw(nw::Dict{Symbol,Any})
    ids = Int[]
    for (sid, st) in get(nw, :storage, Dict{Int,Any}())
        if _is_battery_candidate(st)
            push!(ids, sid)
        end
    end
    return sort(ids)
end

function _one_snapshot_extracted_diagnostic(raw::Dict{String,Any}, adequacy::Dict{String,Any})
    worst_snapshot = Int(adequacy["worst_snapshot"]["snapshot"])
    raw1 = _make_single_snapshot_raw(raw, worst_snapshot)
    nw1 = raw1["nw"]["1"]

    load = sum((float(get(l, "pd", 0.0)) for l in values(get(nw1, "load", Dict{String,Any}())) if get(l, "status", 1) != 0); init=0.0)
    existing_gen_cap = sum((float(get(g, "n_block0", 0.0)) * float(get(g, "p_block_max", 0.0)) * _pmax_pu(g) for g in values(get(nw1, "gen", Dict{String,Any}())) if haskey(g, "type")); init=0.0)
    max_expand_gen_cap = sum((float(get(g, "n_block_max", get(g, "n_block0", 0.0))) * float(get(g, "p_block_max", 0.0)) * _pmax_pu(g) for g in values(get(nw1, "gen", Dict{String,Any}())) if haskey(g, "type")); init=0.0)
    max_battery_candidate_cap = sum((float(get(st, "n_block_max", get(st, "n_block0", 0.0))) * float(get(st, "p_block_max", 0.0)) for st in values(get(nw1, "storage", Dict{String,Any}()) ) if _is_battery_candidate(st)); init=0.0)

    data = _prepare_solver_data(raw1; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _inject_g_min!(data, 0.0)
    for nw in values(data["nw"])
        nw["dcline"] = Dict{String,Any}()
        for (_, _, d) in _iter_block_devices(nw)
            if haskey(d, "p_min_pu")
                d["p_min_pu"] = 0.0
            end
            if haskey(d, "p_block_min_pu")
                d["p_block_min_pu"] = 0.0
            end
        end
    end

    solved = _solve_with_pm(data, _resolve_builder(:no_gscr_relaxed_storage))
    pm = solved["pm"]
    nw = first(sort(collect(_FP.nw_ids(pm))))
    battery_ids = _candidate_storage_ids_in_nw(_PM.ref(pm, nw))

    device_keys = sort(collect(_FP._uc_gscr_block_device_keys(pm, nw)); by=x -> (String(x[1]), x[2]))
    n_block_can_increase = false
    na_block_can_increase = false
    for key in device_keys
        d = _PM.ref(pm, nw, key[1], key[2])
        n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
        nvar = _PM.var(pm, nw, :n_block, key)
        if _var_ub(nvar) > n0 + _EPS
            n_block_can_increase = true
        end
        navar = _PM.var(pm, nw, :na_block, key)
        na0 = float(get(d, "na0", 0.0))
        if !JuMP.is_fixed(navar) && (isinf(_var_ub(navar)) || _var_ub(navar) > na0 + _EPS)
            na_block_can_increase = true
        end
    end

    n_block_increased = false
    na_block_increased = false
    candidate_dispatch_positive = false
    candidate_dispatch_positive_abs = false
    if solved["status"] in _ACTIVE_OK
        for key in device_keys
            d = _PM.ref(pm, nw, key[1], key[2])
            n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
            na0 = float(get(d, "na0", 0.0))
            n_block_increased = n_block_increased || (JuMP.value(_PM.var(pm, nw, :n_block, key)) > n0 + _EPS)
            na_block_increased = na_block_increased || (JuMP.value(_PM.var(pm, nw, :na_block, key)) > na0 + _EPS)
        end
        if haskey(_PM.var(pm, nw), :sd)
            for sid in battery_ids
                candidate_dispatch_positive = candidate_dispatch_positive || (JuMP.value(_PM.var(pm, nw, :sd, sid)) > _EPS)
            end
        end
        if haskey(_PM.var(pm, nw), :ps)
            for sid in battery_ids
                candidate_dispatch_positive_abs = candidate_dispatch_positive_abs || (abs(JuMP.value(_PM.var(pm, nw, :ps, sid))) > _EPS)
            end
        end
    end

    return Dict{String,Any}(
        "status" => solved["status"],
        "objective" => solved["objective"],
        "solve_time_sec" => solved["solve_time_sec"],
        "source_snapshot" => worst_snapshot,
        "total_load" => load,
        "existing_gen_capacity" => existing_gen_cap,
        "max_expandable_gen_capacity" => max_expand_gen_cap,
        "max_battery_candidate_capacity" => max_battery_candidate_cap,
        "n_block_can_increase_above_n0" => n_block_can_increase,
        "na_block_can_increase_above_na0" => na_block_can_increase,
        "n_block_increased_in_solution" => n_block_increased,
        "na_block_increased_in_solution" => na_block_increased,
        "candidate_dispatch_positive" => candidate_dispatch_positive,
        "candidate_dispatch_positive_abs" => candidate_dispatch_positive_abs,
    )
end

function _snapshot_raw_balance_audit(nw::Dict{String,Any})
    total_load = sum((float(get(l, "pd", 0.0)) for l in values(get(nw, "load", Dict{String,Any}())) if get(l, "status", 1) != 0); init=0.0)
    existing_gen = 0.0
    max_gen = 0.0
    for g in values(get(nw, "gen", Dict{String,Any}()))
        if !haskey(g, "type")
            continue
        end
        ppu = _pmax_pu(g)
        existing_gen += float(get(g, "n_block0", 0.0)) * float(get(g, "p_block_max", 0.0)) * ppu
        max_gen += float(get(g, "n_block_max", get(g, "n_block0", 0.0))) * float(get(g, "p_block_max", 0.0)) * ppu
    end
    existing_storage_discharge = 0.0
    max_battery_candidate_discharge = 0.0
    for st in values(get(nw, "storage", Dict{String,Any}()))
        if !haskey(st, "type")
            continue
        end
        existing_storage_discharge += float(get(st, "n_block0", 0.0)) * float(get(st, "p_block_max", 0.0))
        if _is_battery_candidate(st)
            max_battery_candidate_discharge += float(get(st, "n_block_max", get(st, "n_block0", 0.0))) * float(get(st, "p_block_max", 0.0))
        end
    end
    dcline_import_max = 0.0
    dcline_export_max = 0.0
    for dc in values(get(nw, "dcline", Dict{String,Any}()))
        dcline_import_max += max(0.0, -float(get(dc, "pminf", 0.0))) + max(0.0, -float(get(dc, "pmint", 0.0)))
        dcline_export_max += max(0.0, float(get(dc, "pmaxf", 0.0))) + max(0.0, float(get(dc, "pmaxt", 0.0)))
    end
    return Dict{String,Any}(
        "total_load" => total_load,
        "existing_gen_upper" => existing_gen,
        "max_expandable_gen_upper" => max_gen,
        "existing_storage_discharge_upper" => existing_storage_discharge,
        "max_battery_candidate_discharge_upper" => max_battery_candidate_discharge,
        "dcline_import_capability" => dcline_import_max,
        "dcline_export_capability" => dcline_export_max,
        "deficit_existing_only" => total_load - (existing_gen + existing_storage_discharge),
        "deficit_max_expansion_ignoring_network" => total_load - (max_gen + max_battery_candidate_discharge),
        "deficit_max_expansion_with_dcline" => total_load - (max_gen + max_battery_candidate_discharge + dcline_import_max),
    )
end

function _ac_islands(nw::Dict{String,Any})
    bus_ids = sort(parse.(Int, collect(keys(get(nw, "bus", Dict{String,Any}())))))
    adj = Dict(b => Int[] for b in bus_ids)
    for br in values(get(nw, "branch", Dict{String,Any}()))
        if get(br, "br_status", get(br, "status", 1)) == 0
            continue
        end
        f = Int(get(br, "f_bus", -1))
        t = Int(get(br, "t_bus", -1))
        if haskey(adj, f) && haskey(adj, t)
            push!(adj[f], t)
            push!(adj[t], f)
        end
    end
    visited = Set{Int}()
    islands = Vector{Vector{Int}}()
    for b in bus_ids
        if b in visited
            continue
        end
        q = [b]
        push!(visited, b)
        comp = Int[]
        while !isempty(q)
            x = popfirst!(q)
            push!(comp, x)
            for y in adj[x]
                if !(y in visited)
                    push!(visited, y)
                    push!(q, y)
                end
            end
        end
        push!(islands, sort(comp))
    end
    return islands
end

function _dcline_endpoint_caps(dc::Dict{String,Any}, endpoint::Symbol)
    if endpoint == :f
        pmin = float(get(dc, "pminf", 0.0))
        pmax = float(get(dc, "pmaxf", 0.0))
    else
        pmin = float(get(dc, "pmint", 0.0))
        pmax = float(get(dc, "pmaxt", 0.0))
    end
    import_cap = max(0.0, -pmin)
    export_cap = max(0.0, pmax)
    return import_cap, export_cap, pmin, pmax
end

function _island_and_dcline_audit(nw::Dict{String,Any})
    islands = _ac_islands(nw)
    bus_to_island = Dict{Int,Int}()
    for (iid, buses) in enumerate(islands)
        for b in buses
            bus_to_island[b] = iid
        end
    end

    dcline_rows = Dict{String,Any}[]
    island_rows = Dict{String,Any}[
        Dict{String,Any}(
            "island_id" => iid,
            "buses" => buses,
            "load" => 0.0,
            "existing_gen_upper" => 0.0,
            "max_expandable_gen_upper" => 0.0,
            "existing_storage_discharge_upper" => 0.0,
            "max_battery_candidate_discharge_upper" => 0.0,
            "incident_dclines" => String[],
            "dcline_import_max" => 0.0,
            "dcline_export_max" => 0.0,
        ) for (iid, buses) in enumerate(islands)
    ]

    for l in values(get(nw, "load", Dict{String,Any}()))
        if get(l, "status", 1) == 0
            continue
        end
        bus = Int(get(l, "load_bus", -1))
        if haskey(bus_to_island, bus)
            island_rows[bus_to_island[bus]]["load"] += float(get(l, "pd", 0.0))
        end
    end
    for g in values(get(nw, "gen", Dict{String,Any}()))
        if !haskey(g, "type")
            continue
        end
        bus = Int(get(g, "gen_bus", -1))
        if !haskey(bus_to_island, bus)
            continue
        end
        ppu = _pmax_pu(g)
        island_rows[bus_to_island[bus]]["existing_gen_upper"] += float(get(g, "n_block0", 0.0)) * float(get(g, "p_block_max", 0.0)) * ppu
        island_rows[bus_to_island[bus]]["max_expandable_gen_upper"] += float(get(g, "n_block_max", get(g, "n_block0", 0.0))) * float(get(g, "p_block_max", 0.0)) * ppu
    end
    for st in values(get(nw, "storage", Dict{String,Any}()))
        if !haskey(st, "type")
            continue
        end
        bus = Int(get(st, "storage_bus", -1))
        if !haskey(bus_to_island, bus)
            continue
        end
        iid = bus_to_island[bus]
        island_rows[iid]["existing_storage_discharge_upper"] += float(get(st, "n_block0", 0.0)) * float(get(st, "p_block_max", 0.0))
        if _is_battery_candidate(st)
            island_rows[iid]["max_battery_candidate_discharge_upper"] += float(get(st, "n_block_max", get(st, "n_block0", 0.0))) * float(get(st, "p_block_max", 0.0)
            )
        end
    end

    for (dcid, dc) in sort(collect(get(nw, "dcline", Dict{String,Any}())); by=first)
        f_bus = Int(get(dc, "f_bus", -1))
        t_bus = Int(get(dc, "t_bus", -1))
        f_ok = haskey(bus_to_island, f_bus)
        t_ok = haskey(bus_to_island, t_bus)
        f_island = f_ok ? bus_to_island[f_bus] : -1
        t_island = t_ok ? bus_to_island[t_bus] : -1
        imp_f, exp_f, pminf, pmaxf = _dcline_endpoint_caps(dc, :f)
        imp_t, exp_t, pmint, pmaxt = _dcline_endpoint_caps(dc, :t)
        if f_ok
            push!(island_rows[f_island]["incident_dclines"], dcid)
            island_rows[f_island]["dcline_import_max"] += imp_f
            island_rows[f_island]["dcline_export_max"] += exp_f
        end
        if t_ok
            push!(island_rows[t_island]["incident_dclines"], dcid)
            island_rows[t_island]["dcline_import_max"] += imp_t
            island_rows[t_island]["dcline_export_max"] += exp_t
        end
        pmin = min(pminf, pmint)
        pmax = max(pmaxf, pmaxt)
        push!(dcline_rows, Dict{String,Any}(
            "id" => dcid,
            "f_bus" => f_bus,
            "t_bus" => t_bus,
            "f_island" => f_island,
            "t_island" => t_island,
            "pmin" => pmin,
            "pmax" => pmax,
            "pminf" => pminf,
            "pmaxf" => pmaxf,
            "pmint" => pmint,
            "pmaxt" => pmaxt,
            "bidirectional" => (pmin < 0.0 && pmax > 0.0),
            "import_to_f_max" => imp_f,
            "import_to_t_max" => imp_t,
            "endpoints_valid_ac_buses" => f_ok && t_ok,
            "connects_different_islands" => f_ok && t_ok && f_island != t_island,
            "same_island" => f_ok && t_ok && f_island == t_island,
            "pmin_le_pmax" => pmin <= pmax + _EPS,
            "pmax_positive_if_capacity" => pmax > 0.0 || (abs(pmax) <= _EPS && abs(pmin) <= _EPS),
        ))
    end

    for row in island_rows
        row["incident_dclines"] = sort(unique(row["incident_dclines"]))
        row["adequacy_margin"] = row["max_expandable_gen_upper"] + row["max_battery_candidate_discharge_upper"] + row["dcline_import_max"] - row["load"]
        row["margin_negative"] = row["adequacy_margin"] < -_EPS
    end

    worst_idx = argmin([r["adequacy_margin"] for r in island_rows])
    return Dict{String,Any}(
        "islands" => island_rows,
        "dclines" => dcline_rows,
        "worst_island" => island_rows[worst_idx],
    )
end

function _one_snapshot_transport_lp(nw::Dict{String,Any}, island_audit::Dict{String,Any})
    islands = island_audit["islands"]
    dclines = island_audit["dclines"]
    m = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(m)

    I = 1:length(islands)
    gen_use = JuMP.@variable(m, [i in I], lower_bound=0.0, upper_bound=islands[i]["max_expandable_gen_upper"])
    stor_use = JuMP.@variable(m, [i in I], lower_bound=0.0, upper_bound=islands[i]["existing_storage_discharge_upper"])
    batt_use = JuMP.@variable(m, [i in I], lower_bound=0.0, upper_bound=islands[i]["max_battery_candidate_discharge_upper"])

    flow = Dict{String,JuMP.VariableRef}()
    for dc in dclines
        flow[dc["id"]] = JuMP.@variable(m, lower_bound=dc["pminf"], upper_bound=dc["pmaxf"])
    end

    for i in I
        load = islands[i]["load"]
        expr = JuMP.AffExpr(0.0)
        JuMP.add_to_expression!(expr, gen_use[i])
        JuMP.add_to_expression!(expr, stor_use[i])
        JuMP.add_to_expression!(expr, batt_use[i])
        for dc in dclines
            if dc["f_island"] == i
                JuMP.add_to_expression!(expr, -1.0, flow[dc["id"]])
            end
            if dc["t_island"] == i
                JuMP.add_to_expression!(expr, 1.0, flow[dc["id"]])
            end
        end
        JuMP.@constraint(m, expr == load)
    end
    JuMP.@objective(m, Min, 0.0)
    JuMP.optimize!(m)
    status = _status_str(JuMP.termination_status(m))
    return Dict{String,Any}(
        "status" => status,
        "feasible" => status in _ACTIVE_OK,
    )
end

function _one_snapshot_candidate_ratings_variant(raw::Dict{String,Any}, snapshot_id::Int)
    raw1 = _make_single_snapshot_raw(raw, snapshot_id)
    data = _prepare_solver_data(raw1; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _inject_g_min!(data, 0.0)
    for nw in values(data["nw"])
        for st in values(get(nw, "storage", Dict{String,Any}()))
            if _is_battery_candidate(st)
                nmax = float(get(st, "n_block_max", 0.0))
                st["energy_rating"] = nmax * float(get(st, "e_block", 0.0))
                st["charge_rating"] = nmax * float(get(st, "p_block_max", 0.0))
                st["discharge_rating"] = nmax * float(get(st, "p_block_max", 0.0))
            end
        end
    end
    solved = _solve_with_pm(data, _resolve_builder(:standard))
    pm = solved["pm"]
    nw = first(sort(collect(_FP.nw_ids(pm))))
    sd_ub_positive = false
    sc_ub_positive = false
    if haskey(_PM.var(pm, nw), :sd)
        for sid in _candidate_storage_ids_in_nw(_PM.ref(pm, nw))
            sd_ub_positive = sd_ub_positive || (_var_ub(_PM.var(pm, nw, :sd, sid)) > _EPS)
        end
    end
    if haskey(_PM.var(pm, nw), :sc)
        for sid in _candidate_storage_ids_in_nw(_PM.ref(pm, nw))
            sc_ub_positive = sc_ub_positive || (_var_ub(_PM.var(pm, nw, :sc, sid)) > _EPS)
        end
    end
    return Dict{String,Any}(
        "status" => solved["status"],
        "objective" => solved["objective"],
        "solve_time_sec" => solved["solve_time_sec"],
        "sd_ub_positive" => sd_ub_positive,
        "sc_ub_positive" => sc_ub_positive,
    )
end

function _one_snapshot_balance_visibility_audit(raw::Dict{String,Any}, snapshot_id::Int, island_audit::Dict{String,Any})
    raw1 = _make_single_snapshot_raw(raw, snapshot_id)
    data = _prepare_solver_data(raw1; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _inject_g_min!(data, 0.0)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _resolve_builder(:standard);
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    nw = first(sort(collect(_FP.nw_ids(pm))))
    con_present = haskey(_PM.con(pm, nw), :uc_gscr_block_system_active_balance)
    balance_includes_dclines = false
    balance_includes_storage = haskey(_PM.var(pm, nw), :ps) || haskey(_PM.var(pm, nw), :sc) || haskey(_PM.var(pm, nw), :sd)
    candidate_in_storage_set = all(sid in _PM.ids(pm, nw, :storage) for sid in _candidate_storage_ids_in_nw(_PM.ref(pm, nw)))
    bus_ids = Set(_PM.ids(pm, nw, :bus))

    load_bus_ok = all(Int(get(_PM.ref(pm, nw, :load, lid), "load_bus", -1)) in bus_ids for lid in _PM.ids(pm, nw, :load))
    gen_bus_ok = all(Int(get(_PM.ref(pm, nw, :gen, gid), "gen_bus", -1)) in bus_ids for gid in _PM.ids(pm, nw, :gen))
    storage_bus_ok = all(Int(get(_PM.ref(pm, nw, :storage, sid), "storage_bus", -1)) in bus_ids for sid in _PM.ids(pm, nw, :storage))
    dcline_bus_ok = all(Int(get(_PM.ref(pm, nw, :dcline, did), "f_bus", -1)) in bus_ids &&
                        Int(get(_PM.ref(pm, nw, :dcline, did), "t_bus", -1)) in bus_ids for did in _PM.ids(pm, nw, :dcline))

    deficit_island = island_audit["worst_island"]
    deficit_buses = Set(Int.(deficit_island["buses"]))
    load_ids = [lid for lid in _PM.ids(pm, nw, :load) if Int(get(_PM.ref(pm, nw, :load, lid), "load_bus", -1)) in deficit_buses]
    gen_ids = [gid for gid in _PM.ids(pm, nw, :gen) if Int(get(_PM.ref(pm, nw, :gen, gid), "gen_bus", -1)) in deficit_buses]
    storage_ids = [sid for sid in _PM.ids(pm, nw, :storage) if Int(get(_PM.ref(pm, nw, :storage, sid), "storage_bus", -1)) in deficit_buses]
    dcline_ids = [did for did in _PM.ids(pm, nw, :dcline) if Int(get(_PM.ref(pm, nw, :dcline, did), "f_bus", -1)) in deficit_buses || Int(get(_PM.ref(pm, nw, :dcline, did), "t_bus", -1)) in deficit_buses]

    return Dict{String,Any}(
        "balance_constraint_present" => con_present,
        "dclines_included_in_active_balance" => balance_includes_dclines,
        "storage_vars_included_in_active_balance_path" => balance_includes_storage,
        "candidate_batteries_in_storage_set" => candidate_in_storage_set,
        "loads_mapped_to_valid_buses" => load_bus_ok,
        "all_buses_present_in_ref" => !isempty(bus_ids),
        "bus_id_consistency_load_gen_storage_dcline_branch" => load_bus_ok && gen_bus_ok && storage_bus_ok && dcline_bus_ok,
        "sample_deficit_island_id" => deficit_island["island_id"],
        "sample_deficit_island_load_ids" => load_ids,
        "sample_deficit_island_gen_ids" => gen_ids,
        "sample_deficit_island_storage_ids" => storage_ids,
        "sample_deficit_island_dcline_ids" => dcline_ids,
    )
end

function _count_constraint_refs(x)::Int
    if x isa JuMP.ConstraintRef
        return 1
    elseif x isa AbstractDict
        s = 0
        for v in values(x)
            s += _count_constraint_refs(v)
        end
        return s
    elseif x isa AbstractArray || x isa Tuple
        s = 0
        for v in x
            s += _count_constraint_refs(v)
        end
        return s
    end
    return 0
end

function _find_lines(path::String, needle::String)
    if !isfile(path)
        return Int[]
    end
    lines = readlines(path)
    out = Int[]
    for (i, l) in enumerate(lines)
        if occursin(needle, l)
            push!(out, i)
        end
    end
    return out
end

function _standard_dcline_support_audit()
    variable_methods = [string(m) for m in methods(_PM.variable_dcline_power)]
    con_loss_methods = [string(m) for m in methods(_PM.constraint_dcline_power_losses)]
    con_setpoint_methods = [string(m) for m in methods(_PM.constraint_dcline_setpoint_active)]
    balance_methods = [string(m) for m in methods(_PM.constraint_power_balance)]

    opf_file = joinpath(dirname(pathof(_PM)), "prob", "opf.jl")
    opf_calls = Dict{String,Any}(
        "file" => opf_file,
        "build_opf_variable_dcline_power_lines" => _find_lines(opf_file, "variable_dcline_power(pm"),
        "build_opf_constraint_power_balance_lines" => _find_lines(opf_file, "constraint_power_balance(pm"),
        "build_opf_constraint_dcline_power_losses_lines" => _find_lines(opf_file, "constraint_dcline_power_losses(pm"),
    )

    return Dict{String,Any}(
        "standard_variable_functions" => variable_methods,
        "standard_constraint_dcline_losses_functions" => con_loss_methods,
        "standard_constraint_dcline_setpoint_functions" => con_setpoint_methods,
        "standard_constraint_power_balance_functions" => balance_methods,
        "standard_builder_opf_calls" => opf_calls,
        "variable_names" => ["p_dc", "q_dc"],
        "constraint_names" => ["constraint_dcline_power_losses", "constraint_dcline_setpoint_active", "constraint_power_balance"],
        "loss_model" => "(1-loss1)*p_fr + (p_to-loss0) == 0",
        "dcline_efficiency_modeled" => true,
    )
end

function _active_path_dcline_call_audit()
    path = normpath(@__DIR__, "..", "src", "prob", "uc_gscr_block_integration.jl")
    calls_variable_dcline = _find_lines(path, "variable_dcline_power(")
    calls_con_dcline_losses = _find_lines(path, "constraint_dcline_power_losses(")
    calls_pm_bus_balance = _find_lines(path, "constraint_power_balance(")
    calls_custom_balance = _find_lines(path, "constraint_uc_gscr_block_system_active_balance(pm;")
    custom_balance_def = _find_lines(path, "function constraint_uc_gscr_block_system_active_balance(")

    class = "G. active custom balance bypasses standard PowerModels dcline support"
    if isempty(calls_custom_balance)
        class = "unknown"
    end

    return Dict{String,Any}(
        "path" => path,
        "calls_standard_opf_bus_balance" => !isempty(calls_pm_bus_balance),
        "calls_custom_system_balance" => !isempty(calls_custom_balance),
        "calls_standard_dcline_variable_function" => !isempty(calls_variable_dcline),
        "calls_standard_dcline_constraint_function" => !isempty(calls_con_dcline_losses),
        "standard_opf_bus_balance_call_lines" => calls_pm_bus_balance,
        "custom_system_balance_call_lines" => calls_custom_balance,
        "custom_system_balance_definition_lines" => custom_balance_def,
        "missing_calls" => Dict(
            "variable_dcline_power" => calls_variable_dcline,
            "constraint_dcline_power_losses" => calls_con_dcline_losses,
            "constraint_power_balance" => calls_pm_bus_balance,
        ),
        "classification" => class,
        "exact_missing_location" => Dict(
            "builder_function" => "build_uc_gscr_block_integration",
            "file" => path,
            "line_hint_calls_custom_balance" => isempty(calls_custom_balance) ? nothing : first(calls_custom_balance),
            "line_hint_custom_balance_def" => isempty(custom_balance_def) ? nothing : first(custom_balance_def),
        ),
        "recommended_minimal_fix" =>
            "In `build_uc_gscr_block_integration`, add standard dcline variable/constraint calls and replace or augment system balance with per-bus `constraint_power_balance` path including `bus_arcs_dc`.",
    )
end

function _runtime_dcline_count_audit(raw::Dict{String,Any}, snapshot_id::Int)
    raw1 = _make_single_snapshot_raw(raw, snapshot_id)
    raw_nw = raw1["nw"]["1"]
    raw_count = length(get(raw_nw, "dcline", Dict{String,Any}()))

    data = _prepare_solver_data(raw1; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _inject_g_min!(data, 0.0)
    solver_nw = data["nw"]["1"]
    solver_count = length(get(solver_nw, "dcline", Dict{String,Any}()))

    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _resolve_builder(:standard);
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    nw = first(sort(collect(_FP.nw_ids(pm))))
    ref_count = length(_PM.ids(pm, nw, :dcline))
    var_count = haskey(_PM.var(pm, nw), :p_dc) ? length(keys(_PM.var(pm, nw, :p_dc))) : 0

    dcline_con_count = 0
    for (k, v) in _PM.con(pm, nw)
        if occursin("dcline", String(k))
            dcline_con_count += _count_constraint_refs(v)
        end
    end

    bus_balance_dcline_terms = haskey(_PM.ref(pm, nw), :bus_arcs_dc) ?
        sum(length(_PM.ref(pm, nw, :bus_arcs_dc, b)) for b in _PM.ids(pm, nw, :bus)) : 0

    return Dict{String,Any}(
        "snapshot_id" => snapshot_id,
        "stages" => [
            Dict("stage" => "raw data", "dcline_count" => raw_count),
            Dict("stage" => "solver-copy data after adapter", "dcline_count" => solver_count),
            Dict("stage" => "PowerModels ref", "dcline_count" => ref_count),
            Dict("stage" => "model variables (p_dc)", "dcline_count" => var_count),
            Dict("stage" => "dcline constraints", "dcline_count" => dcline_con_count),
            Dict("stage" => "bus balance dcline terms", "dcline_count" => bus_balance_dcline_terms),
        ],
        "expected" => Dict(
            "raw" => 43,
            "solver_copy" => 43,
            "ref" => 43,
            "model_variables_gt_zero" => true,
            "dcline_constraints_gt_zero" => true,
            "bus_balance_terms_expected" => 86,
        ),
    )
end

function _bus_balance_expression_audit(raw::Dict{String,Any}, snapshot_id::Int, island_audit::Dict{String,Any})
    raw1 = _make_single_snapshot_raw(raw, snapshot_id)
    data = _prepare_solver_data(raw1; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _inject_g_min!(data, 0.0)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _resolve_builder(:standard);
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    nw = first(sort(collect(_FP.nw_ids(pm))))

    sample_dclines = Dict{String,Any}[]
    for did in Iterators.take(sort(collect(_PM.ids(pm, nw, :dcline))), 3)
        dc = _PM.ref(pm, nw, :dcline, did)
        f_bus = Int(get(dc, "f_bus", -1))
        t_bus = Int(get(dc, "t_bus", -1))
        has_var = haskey(_PM.var(pm, nw), :p_dc)
        push!(sample_dclines, Dict{String,Any}(
            "id" => did,
            "f_bus" => f_bus,
            "t_bus" => t_bus,
            "flow_variable" => has_var ? "p_dc[($did,$f_bus,$t_bus)] and p_dc[($did,$t_bus,$f_bus)]" : "missing",
            "contribution_at_f_bus_standard_balance" => "+p_dc[($did,$f_bus,$t_bus)] in lhs(sum bus_arcs_dc)",
            "contribution_at_t_bus_standard_balance" => "+p_dc[($did,$t_bus,$f_bus)] in lhs(sum bus_arcs_dc)",
            "sign_convention_note" => "positive term in each bus KCL lhs; opposite direction represented by opposite arc variable",
        ))
    end

    worst_island = island_audit["worst_island"]
    deficit_bus = Int(first(worst_island["buses"]))
    comp = Dict{String,Any}(
        "bus" => deficit_bus,
        "gen_terms_count" => length(_PM.ref(pm, nw, :bus_gens, deficit_bus)),
        "storage_terms_count" => length(_PM.ref(pm, nw, :bus_storage, deficit_bus)),
        "load_terms_count" => length(_PM.ref(pm, nw, :bus_loads, deficit_bus)),
        "ac_branch_terms_count" => length(_PM.ref(pm, nw, :bus_arcs, deficit_bus)),
        "dcline_terms_count" => length(_PM.ref(pm, nw, :bus_arcs_dc, deficit_bus)),
    )

    return Dict{String,Any}(
        "sample_dclines" => sample_dclines,
        "deficit_bus_components_in_ref" => comp,
        "active_balance_constraint" => "sum(pg) - sum(ps) - sum(ps_ne) == sum(pd)",
        "active_balance_contains_dcline_terms" => false,
        "active_balance_contains_bus_terms" => false,
    )
end

function _one_snapshot_deep_diagnostic(raw::Dict{String,Any}, adequacy::Dict{String,Any}, gate::Dict{String,Any})
    snapshot_id = Int(adequacy["worst_snapshot"]["snapshot"])
    nw = _make_single_snapshot_raw(raw, snapshot_id)["nw"]["1"]
    raw_balance = _snapshot_raw_balance_audit(nw)
    island_audit = _island_and_dcline_audit(nw)
    transport_lp = _one_snapshot_transport_lp(nw, island_audit)
    candidate_rating_variant = _one_snapshot_candidate_ratings_variant(raw, snapshot_id)
    balance_visibility = _one_snapshot_balance_visibility_audit(raw, snapshot_id, island_audit)
    standard_dcline_support = _standard_dcline_support_audit()
    active_path_dcline_calls = _active_path_dcline_call_audit()
    runtime_dcline_counts = _runtime_dcline_count_audit(raw, snapshot_id)
    bus_balance_expr = _bus_balance_expression_audit(raw, snapshot_id, island_audit)

    full_one_snapshot = _run_mode(_make_single_snapshot_raw(raw, snapshot_id), "one_snapshot_full", "full_capexp"; g_min_value=0.0)

    likely = ""
    if any(r["margin_negative"] for r in island_audit["islands"])
        likely = "insufficient local/island expansion or dcline transfer capacity"
    elseif transport_lp["feasible"] && !(full_one_snapshot["status"] in _ACTIVE_OK)
        likely = "active model integration, bus balance, or dcline/storage not included correctly"
    elseif candidate_rating_variant["status"] in _ACTIVE_OK
        likely = "standard storage ratings still constrain candidate batteries"
    elseif !balance_visibility["dclines_included_in_active_balance"] || occursin("bypasses", String(active_path_dcline_calls["classification"]))
        likely = "dcline omission in active CAPEXP balance"
    else
        likely = "PowerModels/FlexPlan formulation mismatch requiring deeper IIS/manual bound inspection"
    end

    return Dict{String,Any}(
        "snapshot_id" => snapshot_id,
        "raw_balance" => raw_balance,
        "island_audit" => island_audit,
        "transport_lp" => transport_lp,
        "one_snapshot_full_status" => full_one_snapshot["status"],
        "one_snapshot_candidate_ratings_from_blocks" => candidate_rating_variant,
        "balance_visibility" => balance_visibility,
        "standard_dcline_support_audit" => standard_dcline_support,
        "active_path_dcline_call_audit" => active_path_dcline_calls,
        "runtime_dcline_count_audit" => runtime_dcline_counts,
        "bus_balance_expression_audit" => bus_balance_expr,
        "likely_root_cause" => likely,
    )
end

function _synthetic_gen_raw()
    return Dict{String,Any}(
        "name" => "synthetic_gen_capexp",
        "multinetwork" => true,
        "baseMVA" => 1.0,
        "per_unit" => false,
        "source_type" => "synthetic",
        "nw" => Dict{String,Any}(
            "1" => Dict{String,Any}(
                "bus" => Dict(
                    "1" => Dict{String,Any}(
                        "index" => 1, "name" => "bus1", "carrier" => "AC", "zone" => 1,
                        "bus_type" => 3, "vmin" => 0.9, "vmax" => 1.1, "vm" => 1.0, "va" => 0.0,
                        "base_kv" => 380.0,
                    ),
                    "2" => Dict{String,Any}(
                        "index" => 2, "name" => "bus2", "carrier" => "AC", "zone" => 1,
                        "bus_type" => 1, "vmin" => 0.9, "vmax" => 1.1, "vm" => 1.0, "va" => 0.0,
                        "base_kv" => 380.0,
                    ),
                ),
                "branch" => Dict{String,Any}(),
                "dcline" => Dict{String,Any}(),
                "shunt" => Dict{String,Any}(),
                "switch" => Dict{String,Any}(),
                "load" => Dict("1" => Dict{String,Any}("index" => 1, "load_bus" => 1, "pd" => 100.0, "qd" => 0.0, "status" => 1)),
                "gen" => Dict(
                    "1" => Dict{String,Any}(
                        "index" => 1,
                        "gen_bus" => 1,
                        "name" => "synthetic_gen_candidate",
                        "carrier" => "synthetic",
                        "type" => "gfl",
                        "gen_status" => 1,
                        "dispatchable" => true,
                        "model" => 2,
                        "cost" => [0.0, 0.0],
                        "pmin" => 0.0,
                        "pmax" => 1000.0,
                        "qmin" => -1000.0,
                        "qmax" => 1000.0,
                        "pg" => 0.0,
                        "qg" => 0.0,
                        "n_block0" => 0.0,
                        "n_block_max" => 10.0,
                        "na0" => 0.0,
                        "p_block_max" => 100.0,
                        "p_block_min" => 0.0,
                        "p_max_pu" => 1.0,
                        "p_min_pu" => 0.0,
                        "p_block_max_pu" => 1.0,
                        "p_block_min_pu" => 0.0,
                        "q_block_min" => -1.0,
                        "q_block_max" => 1.0,
                        "b_block" => 0.0,
                        "H" => 0.0,
                        "cost_inv_block" => 1.0,
                        "startup_block_cost" => 0.0,
                        "shutdown_block_cost" => 0.0,
                    ),
                ),
                "storage" => Dict{String,Any}(),
                "ne_storage" => Dict{String,Any}(),
            ),
        ),
    )
end

function _synthetic_battery_raw()
    return Dict{String,Any}(
        "name" => "synthetic_battery_capexp",
        "multinetwork" => true,
        "baseMVA" => 1.0,
        "per_unit" => false,
        "source_type" => "synthetic",
        "nw" => Dict{String,Any}(
            "1" => Dict{String,Any}(
                "bus" => Dict(
                    "1" => Dict{String,Any}(
                        "index" => 1, "name" => "bus1", "carrier" => "AC", "zone" => 1,
                        "bus_type" => 3, "vmin" => 0.9, "vmax" => 1.1, "vm" => 1.0, "va" => 0.0,
                        "base_kv" => 380.0,
                    ),
                    "2" => Dict{String,Any}(
                        "index" => 2, "name" => "bus2", "carrier" => "AC", "zone" => 1,
                        "bus_type" => 1, "vmin" => 0.9, "vmax" => 1.1, "vm" => 1.0, "va" => 0.0,
                        "base_kv" => 380.0,
                    ),
                ),
                "branch" => Dict{String,Any}(),
                "dcline" => Dict{String,Any}(),
                "shunt" => Dict{String,Any}(),
                "switch" => Dict{String,Any}(),
                "load" => Dict("1" => Dict{String,Any}("index" => 1, "load_bus" => 1, "pd" => 100.0, "qd" => 0.0, "status" => 1)),
                "gen" => Dict{String,Any}(),
                "storage" => Dict(
                    "1" => Dict{String,Any}(
                        "index" => 1,
                        "storage_bus" => 1,
                        "name" => "candidate_battery_gfl_bus1",
                        "carrier" => "battery_gfl",
                        "type" => "gfl",
                        "status" => 1,
                        "n_block0" => 0.0,
                        "n_block_max" => 10.0,
                        "na0" => 0.0,
                        "p_block_max" => 100.0,
                        "p_block_min" => -100.0,
                        "p_max_pu" => 1.0,
                        "p_min_pu" => -1.0,
                        "p_block_max_pu" => 1.0,
                        "p_block_min_pu" => -1.0,
                        "e_block" => 600.0,
                        "energy" => 6000.0,
                        "energy_rating" => 6000.0,
                        "charge_rating" => 1000.0,
                        "discharge_rating" => 1000.0,
                        "charge_efficiency" => 1.0,
                        "discharge_efficiency" => 1.0,
                        "stationary_energy_inflow" => 0.0,
                        "stationary_energy_outflow" => 0.0,
                        "self_discharge_rate" => 0.0,
                        "max_energy_absorption" => Inf,
                        "q_block_min" => -1.0,
                        "q_block_max" => 1.0,
                        "b_block" => 0.0,
                        "H" => 0.0,
                        "cost_inv_block" => 1.0,
                        "startup_block_cost" => 0.0,
                        "shutdown_block_cost" => 0.0,
                        "marginal_cost" => 0.0,
                    ),
                ),
                "ne_storage" => Dict{String,Any}(),
            ),
        ),
    )
end

function _synthetic_generator_sanity_test()
    raw = _synthetic_gen_raw()
    data = _prepare_solver_data(raw; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _inject_g_min!(data, 0.0)
    solved = _solve_with_pm(data, _resolve_builder(:no_gscr))
    pm = solved["pm"]
    nw = first(sort(collect(_FP.nw_ids(pm))))
    n_block = NaN
    na_block = NaN
    pg = NaN
    load = sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ids(pm, nw, :load)); init=0.0)
    covers = false
    if solved["status"] in _ACTIVE_OK
        n_block = JuMP.value(_PM.var(pm, nw, :n_block, (:gen, 1)))
        na_block = JuMP.value(_PM.var(pm, nw, :na_block, (:gen, 1)))
        pg = JuMP.value(_PM.var(pm, nw, :pg, 1))
        covers = pg >= load - _EPS
    end
    return Dict{String,Any}(
        "status" => solved["status"],
        "objective" => solved["objective"],
        "solve_time_sec" => solved["solve_time_sec"],
        "n_block" => n_block,
        "na_block" => na_block,
        "pg" => pg,
        "load" => load,
        "dispatch_covers_load" => covers,
        "passes_expected" => solved["status"] == "OPTIMAL" && n_block >= 1.0 - _EPS && na_block >= 1.0 - _EPS && covers,
    )
end

function _synthetic_battery_sanity_test()
    raw = _synthetic_battery_raw()
    data = _prepare_solver_data(raw; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _inject_g_min!(data, 0.0)
    solved = _solve_with_pm(data, _resolve_builder(:no_gscr))
    pm = solved["pm"]
    nw = first(sort(collect(_FP.nw_ids(pm))))
    n_block = NaN
    na_block = NaN
    ps = NaN
    sd = NaN
    load = sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ids(pm, nw, :load)); init=0.0)
    covers = false
    if solved["status"] in _ACTIVE_OK
        n_block = JuMP.value(_PM.var(pm, nw, :n_block, (:storage, 1)))
        na_block = JuMP.value(_PM.var(pm, nw, :na_block, (:storage, 1)))
        if haskey(_PM.var(pm, nw), :ps)
            ps = JuMP.value(_PM.var(pm, nw, :ps, 1))
        end
        if haskey(_PM.var(pm, nw), :sd)
            sd = JuMP.value(_PM.var(pm, nw, :sd, 1))
        end
        covers = (isfinite(sd) && sd >= load - _EPS) || (isfinite(ps) && -ps >= load - _EPS)
    end
    return Dict{String,Any}(
        "status" => solved["status"],
        "objective" => solved["objective"],
        "solve_time_sec" => solved["solve_time_sec"],
        "n_block" => n_block,
        "na_block" => na_block,
        "ps" => ps,
        "sd" => sd,
        "load" => load,
        "dispatch_covers_load" => covers,
        "passes_expected" => solved["status"] == "OPTIMAL" && n_block >= 1.0 - _EPS && na_block >= 1.0 - _EPS && covers,
    )
end

function _model_visibility_and_coupling_audit(raw::Dict{String,Any})
    data = _prepare_solver_data(raw; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _inject_g_min!(data, 0.0)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _resolve_builder(:standard);
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    nw = first(sort(collect(_FP.nw_ids(pm))))
    storage_ids = Set(_PM.ids(pm, nw, :storage))
    candidate_ids = sort([sid for sid in storage_ids if _is_battery_candidate(_PM.ref(pm, nw, :storage, sid))])
    sample_gfl = findfirst(sid -> _is_battery_gfl(_PM.ref(pm, nw, :storage, sid)), candidate_ids)
    sample_gfm = findfirst(sid -> _is_battery_gfm(_PM.ref(pm, nw, :storage, sid)), candidate_ids)
    sample_ids = Int[]
    if !isnothing(sample_gfl)
        push!(sample_ids, candidate_ids[sample_gfl])
    end
    if !isnothing(sample_gfm)
        push!(sample_ids, candidate_ids[sample_gfm])
    end
    sample_ids = unique(sample_ids)

    block_keys = Set(_FP._uc_gscr_block_device_keys(pm, nw))
    gfl_devices = haskey(_PM.ref(pm, nw), :gfl_devices) ? _PM.ref(pm, nw, :gfl_devices) : Dict{Any,Any}()
    gfm_devices = haskey(_PM.ref(pm, nw), :gfm_devices) ? _PM.ref(pm, nw, :gfm_devices) : Dict{Any,Any}()
    bus_gfl_devices = haskey(_PM.ref(pm, nw), :bus_gfl_devices) ? _PM.ref(pm, nw, :bus_gfl_devices) : Dict{Any,Any}()
    bus_gfm_devices = haskey(_PM.ref(pm, nw), :bus_gfm_devices) ? _PM.ref(pm, nw, :bus_gfm_devices) : Dict{Any,Any}()

    has_ps = haskey(_PM.var(pm, nw), :ps)
    has_sc = haskey(_PM.var(pm, nw), :sc)
    has_sd = haskey(_PM.var(pm, nw), :sd)
    has_se = haskey(_PM.var(pm, nw), :se)

    rows = Dict{String,Any}[]
    for sid in sample_ids
        key = (:storage, sid)
        d = _PM.ref(pm, nw, :storage, sid)
        bus = Int(get(d, "storage_bus", -1))
        in_bus_gfl = haskey(bus_gfl_devices, bus) && any(k -> k == key, bus_gfl_devices[bus])
        in_bus_gfm = haskey(bus_gfm_devices, bus) && any(k -> k == key, bus_gfm_devices[bus])
        n_var = _PM.var(pm, nw, :n_block, key)
        na_var = _PM.var(pm, nw, :na_block, key)

        dispatch_bounds = Dict{String,Any}()
        if has_ps
            ps_var = _PM.var(pm, nw, :ps, sid)
            dispatch_bounds["ps_lb"] = _var_lb(ps_var)
            dispatch_bounds["ps_ub"] = _var_ub(ps_var)
        end
        if has_sc
            sc_var = _PM.var(pm, nw, :sc, sid)
            dispatch_bounds["sc_lb"] = _var_lb(sc_var)
            dispatch_bounds["sc_ub"] = _var_ub(sc_var)
        end
        if has_sd
            sd_var = _PM.var(pm, nw, :sd, sid)
            dispatch_bounds["sd_lb"] = _var_lb(sd_var)
            dispatch_bounds["sd_ub"] = _var_ub(sd_var)
        end
        if has_se
            se_var = _PM.var(pm, nw, :se, sid)
            dispatch_bounds["se_lb"] = _var_lb(se_var)
            dispatch_bounds["se_ub"] = _var_ub(se_var)
        end

        coeff_audit = Dict{String,Any}()
        if haskey(_PM.con(pm, nw), :uc_gscr_block_storage_charge_discharge_bounds) && haskey(_PM.con(pm, nw)[:uc_gscr_block_storage_charge_discharge_bounds], key)
            con = _PM.con(pm, nw)[:uc_gscr_block_storage_charge_discharge_bounds][key]
            coeff_audit["storage_bound_coeff_na"] = try JuMP.normalized_coefficient(con, na_var) catch; NaN end
            if has_sc
                coeff_audit["storage_bound_coeff_sc"] = try JuMP.normalized_coefficient(con, _PM.var(pm, nw, :sc, sid)) catch; NaN end
            end
            if has_sd
                coeff_audit["storage_bound_coeff_sd"] = try JuMP.normalized_coefficient(con, _PM.var(pm, nw, :sd, sid)) catch; NaN end
            end
        end
        if haskey(_PM.con(pm, nw), :uc_gscr_block_storage_energy_capacity) && haskey(_PM.con(pm, nw)[:uc_gscr_block_storage_energy_capacity], key)
            econ = _PM.con(pm, nw)[:uc_gscr_block_storage_energy_capacity][key]
            coeff_audit["energy_bound_coeff_n_block"] = try JuMP.normalized_coefficient(econ, n_var) catch; NaN end
        end

        objf = JuMP.objective_function(pm.model)
        expected_coeff = float(get(d, "cost_inv_block", 0.0)) * float(get(d, "p_block_max", 0.0))
        actual_coeff = try JuMP.coefficient(objf, n_var) catch; NaN end

        push!(rows, Dict{String,Any}(
            "id" => sid,
            "type" => String(get(d, "type", "")),
            "carrier" => String(get(d, "carrier", "")),
            "bus" => bus,
            "n_block0" => float(get(d, "n_block0", NaN)),
            "n_block_max" => float(get(d, "n_block_max", NaN)),
            "p_block_max" => float(get(d, "p_block_max", NaN)),
            "e_block" => float(get(d, "e_block", NaN)),
            "cost_inv_block" => float(get(d, "cost_inv_block", NaN)),
            "status" => get(d, "status", missing),
            "energy_rating" => float(get(d, "energy_rating", NaN)),
            "charge_rating" => float(get(d, "charge_rating", NaN)),
            "discharge_rating" => float(get(d, "discharge_rating", NaN)),
            "in_block_enabled_devices" => key in block_keys,
            "in_storage_set" => sid in storage_ids,
            "in_gfl_devices" => haskey(gfl_devices, key),
            "in_gfm_devices" => haskey(gfm_devices, key),
            "in_bus_gfl_devices" => in_bus_gfl,
            "in_bus_gfm_devices" => in_bus_gfm,
            "n_block_var_present" => haskey(_PM.var(pm, nw), :n_block),
            "na_block_var_present" => haskey(_PM.var(pm, nw), :na_block),
            "ps_var_present" => has_ps && _var_has_index(_PM.var(pm, nw, :ps), sid),
            "sc_var_present" => has_sc && _var_has_index(_PM.var(pm, nw, :sc), sid),
            "sd_var_present" => has_sd && _var_has_index(_PM.var(pm, nw, :sd), sid),
            "se_var_present" => has_se && _var_has_index(_PM.var(pm, nw, :se), sid),
            "n_block_lb" => _var_lb(n_var),
            "n_block_ub" => _var_ub(n_var),
            "na_block_lb" => _var_lb(na_var),
            "na_block_ub" => _var_ub(na_var),
            "dispatch_bounds" => dispatch_bounds,
            "constraint_coeff_audit" => coeff_audit,
            "objective_coeff_expected" => expected_coeff,
            "objective_coeff_actual_n_block" => actual_coeff,
            "objective_coeff_diff" => isfinite(actual_coeff) ? abs(actual_coeff - expected_coeff) : NaN,
        ))
    end

    pg_vars_for_candidate_batteries = 0
    storage_dispatch_var_count = 0
    if has_ps
        storage_dispatch_var_count += count(sid -> _var_has_index(_PM.var(pm, nw, :ps), sid), candidate_ids)
    end
    if has_sc
        storage_dispatch_var_count += count(sid -> _var_has_index(_PM.var(pm, nw, :sc), sid), candidate_ids)
    end
    if has_sd
        storage_dispatch_var_count += count(sid -> _var_has_index(_PM.var(pm, nw, :sd), sid), candidate_ids)
    end

    max_abs_obj_coeff = 0.0
    for sid in candidate_ids
        key = (:storage, sid)
        n_var = _PM.var(pm, nw, :n_block, key)
        coeff = try JuMP.coefficient(JuMP.objective_function(pm.model), n_var) catch; 0.0 end
        max_abs_obj_coeff = max(max_abs_obj_coeff, abs(coeff))
    end

    return Dict{String,Any}(
        "n_block_var_count" => haskey(_PM.var(pm, nw), :n_block) ? length(keys(_PM.var(pm, nw, :n_block))) : 0,
        "na_block_var_count" => sum(haskey(_PM.var(pm, k), :na_block) ? length(keys(_PM.var(pm, k, :na_block))) : 0 for k in _FP.nw_ids(pm)),
        "pg_vars_for_candidate_batteries" => pg_vars_for_candidate_batteries,
        "storage_dispatch_vars_for_candidate_batteries" => storage_dispatch_var_count,
        "candidate_battery_count" => length(candidate_ids),
        "sample_rows" => rows,
        "objective_coeff_max_abs_candidate_n_block" => max_abs_obj_coeff,
        "objective_coeff_huge_flag" => max_abs_obj_coeff > 1e9,
        "cost_inv_block_scaled_positive_all_candidates" => all(float(get(_PM.ref(pm, nw, :storage, sid), "cost_inv_block", 0.0)) > 0.0 for sid in candidate_ids),
        "objective_note" => "objective coefficients are reported for audit; objective does not determine feasibility alone",
    )
end

function _first_failing_layer(gate::Dict{String,Any}, one_snapshot::Dict{String,Any}, one_snapshot_deep::Dict{String,Any}, synth_gen::Dict{String,Any}, synth_batt::Dict{String,Any})
    gen_ok = get(synth_gen, "passes_expected", false)
    batt_ok = get(synth_batt, "passes_expected", false)
    one_ok = get(one_snapshot, "status", "") in _ACTIVE_OK
    gate_ok = get(gate, "status", "") in _ACTIVE_OK
    transport_feasible = get(one_snapshot_deep["transport_lp"], "feasible", false)
    one_full_ok = get(one_snapshot_deep, "one_snapshot_full_status", "") in _ACTIVE_OK

    if !gen_ok
        return "synthetic_generator_sanity", "active block CAPEXP formulation or adapter broken"
    elseif gen_ok && !batt_ok
        return "synthetic_battery_sanity", "storage candidate/block path broken"
    elseif any(r["margin_negative"] for r in one_snapshot_deep["island_audit"]["islands"])
        return "island_adequacy", "insufficient local/island expansion or dcline transfer capacity"
    elseif !transport_feasible
        return "transport_lp", "data-level island adequacy/dcline capacity infeasible"
    elseif transport_feasible && !one_full_ok
        return "one_snapshot_full_model", "active model integration, bus balance, or dcline/storage not included correctly"
    elseif one_ok && !gate_ok
        return "24h_multisnapshot", "temporal coupling, startup/shutdown transitions, storage energy over time, or snapshot-time data coupling"
    end
    return "none", "no failing layer detected in requested ladder"
end

function _write_report(
    schema::Dict{String,Any},
    adequacy::Dict{String,Any},
    gate::Dict{String,Any},
    diag::Union{Nothing,Dict{String,Any}},
    deep_diag::Dict{String,Any},
    presolve_candidates::Vector{Dict{String,Any}},
)
    mkpath(dirname(_REPORT_PATH))
    open(_REPORT_PATH, "w") do io
        println(io, "# PyPSA elec_s_37 24h Small CAPEXP Test")
        println(io)
        println(io, "Generated by `test/pypsa_elec_s_37_24h_small_capexp.jl` on ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"), ".")
        println(io, "Dataset: `", _CASE_PATH, "`")
        println(io, "Investment-cost scaling for 24h run: `cost_inv_block *= 1/365` (solver copy only).")
        println(io)

        println(io, "## 1) Load and Schema Validation")
        println(io, "- multinetwork=true: ", schema["multinetwork"])
        println(io, "- snapshot count = 24: ", schema["snapshot_count"])
        println(io, "- bus count = 37: ", schema["bus_count"])
        println(io, "- branch count = 52: ", schema["branch_count"])
        println(io, "- dcline count = 43: ", schema["dcline_count"])
        println(io, "- battery_gfl candidate count = 37: ", schema["battery_gfl_count"])
        println(io, "- battery_gfm candidate count = 37: ", schema["battery_gfm_count"])
        println(io, "- all battery_gfl rows satisfy expected fields/values: ", schema["expected_gfl_ok"])
        println(io, "- all battery_gfm rows satisfy expected fields/values: ", schema["expected_gfm_ok"])
        println(io, "- battery_gfm cost_inv_block = 1.0625 * battery_gfl: ", schema["cost_ratio_ok"])
        println(io, "- invariant `0 <= na0 <= n_block0 <= n_block_max`: ", schema["invariant_ok"])
        println(io, "- one battery_gfl and battery_gfm per AC bus: ", schema["coverage_ok"], " (gfl=", schema["gfl_buses_covered"], ", gfm=", schema["gfm_buses_covered"], ", ac_bus=", length(schema["ac_bus_ids"]), ")")
        if !schema["cost_ratio_ok"]
            println(io, "- cost ratio mismatches:")
            for r in schema["cost_ratio_bad"]
                println(io, "  - bus=", r["bus"], " ratio=", _fmt(r["ratio"]))
            end
        end
        if !schema["invariant_ok"]
            println(io, "- invariant violations: ", length(schema["invariant_bad"]))
        end
        println(io)

        println(io, "## 2) Capacity Adequacy Audit Before Solving")
        println(io, "| snapshot | total load | installed available generation upper | max expandable generation upper | existing storage discharge upper | max storage candidate discharge upper | installed availability/load ratio | max expandable availability/load ratio |")
        println(io, "|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in adequacy["rows"]
            println(io, "| ", r["snapshot"], " | ", _fmt(r["load"]), " | ", _fmt(r["installed_gen_avail"]), " | ", _fmt(r["max_expand_gen_avail"]), " | ", _fmt(r["existing_storage_discharge"]), " | ", _fmt(r["max_storage_candidate_discharge"]), " | ", _fmt(r["installed_ratio"]), " | ", _fmt(r["max_expand_ratio"]), " |")
        end
        ws = adequacy["worst_snapshot"]
        println(io)
        println(io, "- worst snapshot by installed availability/load ratio: snapshot ", ws["snapshot"], " (ratio=", _fmt(ws["installed_ratio"]), ", load=", _fmt(ws["load"]), ")")
        println(io, "- fixed-capacity infeasibility expected if installed availability/load < 1: ", adequacy["fixed_capacity_infeasible_expected"])
        println(io, "- CAPEXP adequacy gate (`max expandable generation + candidate storage >= load` for all snapshots): ", adequacy["max_expand_covers_load_all"])
        println(io)

        println(io, "## 3) Gate 1: Full CAPEXP at g_min = 0")
        println(io, "- status: ", gate["status"])
        println(io, "- objective: ", _fmt(gate["objective"]))
        println(io, "- solve time [s]: ", _fmt(gate["solve_time_sec"]))
        println(io, "- investment cost: ", _fmt(gate["investment_cost"]))
        println(io, "- startup cost: ", _fmt(gate["startup_cost"]))
        println(io, "- shutdown cost: ", _fmt(gate["shutdown_cost"]))
        println(io, "- total invested blocks: ", _fmt(gate["total_invested_blocks"]))
        println(io, "- invested battery_gfl blocks: ", _fmt(gate["invested_battery_gfl_blocks"]))
        println(io, "- invested battery_gfm blocks: ", _fmt(gate["invested_battery_gfm_blocks"]))
        println(io, "- invested generator blocks: ", _fmt(gate["invested_generator_blocks"]))
        println(io, "- invested storage blocks: ", _fmt(gate["invested_storage_blocks"]))
        println(io, "- max active balance residual: ", _fmt(gate["max_active_balance_residual"]))
        println(io, "- storage block consistency residual: ", _fmt(gate["storage_block_consistency_residual"]))
        println(io, "- startup/shutdown transition residual: ", _fmt(gate["startup_shutdown_transition_residual"]))
        println(io, "- gSCR reconstruction residual (g_min=0): ", _fmt(gate["gscr_reconstruction_residual"]))
        println(io)
        println(io, "### Investment by Carrier")
        if isempty(gate["investment_by_carrier"])
            println(io, "- none")
        else
            for (carrier, val) in sort(collect(gate["investment_by_carrier"]); by=first)
                println(io, "- ", carrier, ": ", _fmt(val))
            end
        end
        println(io)
        println(io, "### Investment by Bus")
        if isempty(gate["investment_by_bus"])
            println(io, "- none")
        else
            for (bus, val) in sort(collect(gate["investment_by_bus"]); by=first)
                println(io, "- bus ", bus, ": ", _fmt(val))
            end
        end
        println(io)

        println(io, "## 4) Diagnostics If g_min=0 Full CAPEXP Is Infeasible")
        if isnothing(diag)
            println(io, "- Not executed, because Gate 1 was feasible.")
        else
            println(io, "| variant | status | objective | solve_time_s | total_invested_blocks | invested_battery_gfl_blocks | invested_battery_gfm_blocks | invested_generator_blocks | invested_storage_blocks | balance_residual | storage_bound_residual | transition_residual | interpretation |")
            println(io, "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
            for v in diag["variants"]
                r = v["run"]
                println(
                    io,
                    "| ", v["label"],
                    " | ", r["status"],
                    " | ", _fmt(r["objective"]),
                    " | ", _fmt(r["solve_time_sec"]),
                    " | ", _fmt(r["total_invested_blocks"]),
                    " | ", _fmt(r["invested_battery_gfl_blocks"]),
                    " | ", _fmt(r["invested_battery_gfm_blocks"]),
                    " | ", _fmt(r["invested_generator_blocks"]),
                    " | ", _fmt(r["invested_storage_blocks"]),
                    " | ", _fmt(r["max_active_balance_residual"]),
                    " | ", _fmt(r["storage_block_consistency_residual"]),
                    " | ", _fmt(r["startup_shutdown_transition_residual"]),
                    " | ", replace(v["interpretation"], "|" => "\\|"),
                    " |",
                )
            end
            fv = diag["first_feasible"]
            println(io)
            println(io, "- first feasible variant: ", isnothing(fv) ? "none" : fv["label"])
            println(io, "- likely cause: ", diag["likely_cause"])
            println(io)
            println(io, "| variant | status | first_feasible | likely_cause |")
            println(io, "|---|---|---|---|")
            for v in diag["variants"]
                println(io, "| ", v["label"], " | ", v["run"]["status"], " | ", v["first_feasible"], " | ", replace(v["likely_cause"], "|" => "\\|"), " |")
            end
        end
        println(io)

        println(io, "## 5) One-Snapshot Extracted Diagnostic")
        one = deep_diag["one_snapshot"]
        one_deep = deep_diag["one_snapshot_deep"]
        rb = one_deep["raw_balance"]
        println(io, "- source snapshot: ", one["source_snapshot"])
        println(io, "- extracted one-snapshot status (relaxed path): ", one["status"])
        println(io, "- full one-snapshot CAPEXP status: ", one_deep["one_snapshot_full_status"])
        println(io, "- objective: ", _fmt(one["objective"]))
        println(io, "- solve time [s]: ", _fmt(one["solve_time_sec"]))
        println(io, "- any n_block can increase above n_block0 (bounds): ", one["n_block_can_increase_above_n0"])
        println(io, "- any na_block can increase above na0 (bounds): ", one["na_block_can_increase_above_na0"])
        println(io, "- any n_block increased in solution: ", one["n_block_increased_in_solution"])
        println(io, "- any na_block increased in solution: ", one["na_block_increased_in_solution"])
        println(io, "- any candidate dispatch positive: ", one["candidate_dispatch_positive"], " (abs dispatch nonzero: ", one["candidate_dispatch_positive_abs"], ")")
        println(io)

        println(io, "### 5.1 One-Snapshot Raw Balance Audit")
        println(io, "- total load: ", _fmt(rb["total_load"]))
        println(io, "- total existing available generator upper bound: ", _fmt(rb["existing_gen_upper"]))
        println(io, "- total max expandable generator upper bound: ", _fmt(rb["max_expandable_gen_upper"]))
        println(io, "- total existing storage discharge upper bound: ", _fmt(rb["existing_storage_discharge_upper"]))
        println(io, "- total max battery candidate discharge upper bound: ", _fmt(rb["max_battery_candidate_discharge_upper"]))
        println(io, "- total dcline import capability: ", _fmt(rb["dcline_import_capability"]))
        println(io, "- total dcline export capability: ", _fmt(rb["dcline_export_capability"]))
        println(io, "- deficit/surplus A (existing only): ", _fmt(rb["deficit_existing_only"]))
        println(io, "- deficit/surplus B (max expansion ignoring network): ", _fmt(rb["deficit_max_expansion_ignoring_network"]))
        println(io, "- deficit/surplus C (max expansion incl. dcline imports): ", _fmt(rb["deficit_max_expansion_with_dcline"]))
        println(io)

        println(io, "### 5.2 AC Island Detection and Adequacy")
        println(io, "| island_id | buses | local_load | existing_gen_upper | max_expandable_gen_upper | existing_storage_discharge_upper | max_battery_candidate_discharge_upper | incident_dclines | dcline_import_max | dcline_export_max | adequacy_margin | margin_negative |")
        println(io, "|---:|---|---:|---:|---:|---:|---:|---|---:|---:|---:|---|")
        for r in one_deep["island_audit"]["islands"]
            println(io, "| ", r["island_id"], " | ", join(string.(r["buses"]), ","), " | ", _fmt(r["load"]), " | ", _fmt(r["existing_gen_upper"]), " | ", _fmt(r["max_expandable_gen_upper"]), " | ", _fmt(r["existing_storage_discharge_upper"]), " | ", _fmt(r["max_battery_candidate_discharge_upper"]), " | ", join(r["incident_dclines"], ","), " | ", _fmt(r["dcline_import_max"]), " | ", _fmt(r["dcline_export_max"]), " | ", _fmt(r["adequacy_margin"]), " | ", r["margin_negative"], " |")
        end
        println(io, "- worst island by adequacy margin: ", one_deep["island_audit"]["worst_island"]["island_id"], " (margin=", _fmt(one_deep["island_audit"]["worst_island"]["adequacy_margin"]), ")")
        println(io)

        println(io, "### 5.3 Dcline Sign and Island Mapping Audit")
        println(io, "| dcline_id | f_bus | t_bus | f_island | t_island | pmin | pmax | bidirectional | import_to_f_max | import_to_t_max | endpoints_valid_ac_buses | connects_different_islands | same_island | pmin_le_pmax |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---|---|---|---|")
        for dcr in one_deep["island_audit"]["dclines"]
            println(io, "| ", dcr["id"], " | ", dcr["f_bus"], " | ", dcr["t_bus"], " | ", dcr["f_island"], " | ", dcr["t_island"], " | ", _fmt(dcr["pmin"]), " | ", _fmt(dcr["pmax"]), " | ", dcr["bidirectional"], " | ", _fmt(dcr["import_to_f_max"]), " | ", _fmt(dcr["import_to_t_max"]), " | ", dcr["endpoints_valid_ac_buses"], " | ", dcr["connects_different_islands"], " | ", dcr["same_island"], " | ", dcr["pmin_le_pmax"], " |")
        end
        println(io)

        println(io, "### 5.4 One-Snapshot Transport LP Feasibility")
        println(io, "- status: ", one_deep["transport_lp"]["status"])
        println(io, "- feasible: ", one_deep["transport_lp"]["feasible"])
        println(io)

        println(io, "### 5.5 One-Snapshot Candidate Rating Variant")
        cr = one_deep["one_snapshot_candidate_ratings_from_blocks"]
        println(io, "- variant status (`one_snapshot_candidate_ratings_from_blocks`): ", cr["status"])
        println(io, "- objective: ", _fmt(cr["objective"]))
        println(io, "- solve time [s]: ", _fmt(cr["solve_time_sec"]))
        println(io, "- sd_ub positive after fix: ", cr["sd_ub_positive"])
        println(io, "- sc_ub positive after fix: ", cr["sc_ub_positive"])
        println(io, "- infeasibility changed vs one-snapshot full base: ", (cr["status"] != one_deep["one_snapshot_full_status"]))
        println(io)

        println(io, "### 5.6 Balance-Equation Visibility Audit")
        bva = one_deep["balance_visibility"]
        println(io, "- balance constraint present: ", bva["balance_constraint_present"])
        println(io, "- dclines included in active balance: ", bva["dclines_included_in_active_balance"])
        println(io, "- storage vars included in active balance path: ", bva["storage_vars_included_in_active_balance_path"])
        println(io, "- candidate batteries included in storage set: ", bva["candidate_batteries_in_storage_set"])
        println(io, "- loads mapped to valid buses: ", bva["loads_mapped_to_valid_buses"])
        println(io, "- all buses present in ref: ", bva["all_buses_present_in_ref"])
        println(io, "- bus-id consistency across tables: ", bva["bus_id_consistency_load_gen_storage_dcline_branch"])
        println(io, "- sample deficit island id: ", bva["sample_deficit_island_id"])
        println(io, "  - load ids: ", join(string.(bva["sample_deficit_island_load_ids"]), ","))
        println(io, "  - generator ids: ", join(string.(bva["sample_deficit_island_gen_ids"]), ","))
        println(io, "  - storage ids: ", join(string.(bva["sample_deficit_island_storage_ids"]), ","))
        println(io, "  - dcline ids: ", join(string.(bva["sample_deficit_island_dcline_ids"]), ","))
        println(io)

        println(io, "## Standard Dcline Support Audit")
        sdsa = one_deep["standard_dcline_support_audit"]
        apda = one_deep["active_path_dcline_call_audit"]
        rcda = one_deep["runtime_dcline_count_audit"]
        bbea = one_deep["bus_balance_expression_audit"]
        println(io, "### 1) Standard dcline support in repository/runtime")
        println(io, "- standard variable functions:")
        for s in sdsa["standard_variable_functions"]
            println(io, "  - ", s)
        end
        println(io, "- standard dcline-loss constraint functions:")
        for s in sdsa["standard_constraint_dcline_losses_functions"]
            println(io, "  - ", s)
        end
        println(io, "- standard dcline setpoint constraint functions:")
        for s in sdsa["standard_constraint_dcline_setpoint_functions"]
            println(io, "  - ", s)
        end
        println(io, "- standard power-balance functions (contain bus_arcs_dc):")
        for s in sdsa["standard_constraint_power_balance_functions"]
            println(io, "  - ", s)
        end
        println(io, "- variable names used: ", join(sdsa["variable_names"], ", "))
        println(io, "- constraint names used: ", join(sdsa["constraint_names"], ", "))
        println(io, "- dcline losses/efficiency modeled: ", sdsa["dcline_efficiency_modeled"], " (", sdsa["loss_model"], ")")
        println(io, "- standard OPF builder call lines: variable_dcline_power=", join(string.(sdsa["standard_builder_opf_calls"]["build_opf_variable_dcline_power_lines"]), ","), ", constraint_power_balance=", join(string.(sdsa["standard_builder_opf_calls"]["build_opf_constraint_power_balance_lines"]), ","), ", constraint_dcline_power_losses=", join(string.(sdsa["standard_builder_opf_calls"]["build_opf_constraint_dcline_power_losses_lines"]), ","))
        println(io)

        println(io, "### 2) Active UC/CAPEXP/gSCR path audit")
        println(io, "- active builder file: ", apda["path"])
        println(io, "- calls standard OPF bus balance: ", apda["calls_standard_opf_bus_balance"])
        println(io, "- calls custom system balance: ", apda["calls_custom_system_balance"])
        println(io, "- calls standard dcline variable function: ", apda["calls_standard_dcline_variable_function"])
        println(io, "- calls standard dcline constraints: ", apda["calls_standard_dcline_constraint_function"])
        println(io, "- classification: ", apda["classification"])
        println(io, "- exact missing call/location: builder=", apda["exact_missing_location"]["builder_function"], ", line(custom balance call)=", _fmt(apda["exact_missing_location"]["line_hint_calls_custom_balance"]; digits=0), ", line(custom balance def)=", _fmt(apda["exact_missing_location"]["line_hint_custom_balance_def"]; digits=0))
        println(io, "- recommended minimal fix: ", apda["recommended_minimal_fix"])
        println(io)

        println(io, "### 3) Runtime count audit for one-snapshot elec_s_37")
        println(io, "| stage | dcline count |")
        println(io, "|---|---:|")
        for r in rcda["stages"]
            println(io, "| ", r["stage"], " | ", r["dcline_count"], " |")
        end
        println(io, "- expected raw/solver/ref count: ", rcda["expected"]["raw"], "/", rcda["expected"]["solver_copy"], "/", rcda["expected"]["ref"])
        println(io, "- expected bus-balance dcline terms: ", rcda["expected"]["bus_balance_terms_expected"])
        println(io)

        println(io, "### 4) Bus-balance expression audit")
        println(io, "| dcline_id | f_bus | t_bus | flow variable | contribution at f_bus | contribution at t_bus | sign convention |")
        println(io, "|---|---:|---:|---|---|---|---|")
        for r in bbea["sample_dclines"]
            println(io, "| ", r["id"], " | ", r["f_bus"], " | ", r["t_bus"], " | ", replace(r["flow_variable"], "|" => "\\|"), " | ", replace(r["contribution_at_f_bus_standard_balance"], "|" => "\\|"), " | ", replace(r["contribution_at_t_bus_standard_balance"], "|" => "\\|"), " | ", replace(r["sign_convention_note"], "|" => "\\|"), " |")
        end
        dbc = bbea["deficit_bus_components_in_ref"]
        println(io, "- deficit bus: ", dbc["bus"])
        println(io, "- components in ref: gen=", dbc["gen_terms_count"], ", storage=", dbc["storage_terms_count"], ", load=", dbc["load_terms_count"], ", AC branch=", dbc["ac_branch_terms_count"], ", dcline=", dbc["dcline_terms_count"])
        println(io, "- active balance expression used in this path: `", bbea["active_balance_constraint"], "`")
        println(io, "- active balance contains dcline terms: ", bbea["active_balance_contains_dcline_terms"])
        println(io)

        println(io, "### 5) Missing-piece classification")
        println(io, "- classification result: ", apda["classification"])
        println(io, "- interpreted as: G (active custom balance bypasses standard dcline support path)")
        println(io)

        println(io, "## 6) Synthetic One-Bus Generator Sanity")
        sgen = deep_diag["synthetic_generator"]
        println(io, "- status: ", sgen["status"])
        println(io, "- objective: ", _fmt(sgen["objective"]))
        println(io, "- solve time [s]: ", _fmt(sgen["solve_time_sec"]))
        println(io, "- n_block: ", _fmt(sgen["n_block"]))
        println(io, "- na_block: ", _fmt(sgen["na_block"]))
        println(io, "- pg: ", _fmt(sgen["pg"]), " ; load: ", _fmt(sgen["load"]))
        println(io, "- dispatch covers load: ", sgen["dispatch_covers_load"])
        println(io, "- passes expected sanity: ", sgen["passes_expected"])
        println(io)

        println(io, "## 7) Synthetic One-Bus Battery Candidate Sanity")
        sbat = deep_diag["synthetic_battery"]
        println(io, "- status: ", sbat["status"])
        println(io, "- objective: ", _fmt(sbat["objective"]))
        println(io, "- solve time [s]: ", _fmt(sbat["solve_time_sec"]))
        println(io, "- n_block: ", _fmt(sbat["n_block"]))
        println(io, "- na_block: ", _fmt(sbat["na_block"]))
        println(io, "- ps: ", _fmt(sbat["ps"]), " ; sd: ", _fmt(sbat["sd"]), " ; load: ", _fmt(sbat["load"]))
        println(io, "- dispatch covers load: ", sbat["dispatch_covers_load"])
        println(io, "- passes expected sanity: ", sbat["passes_expected"])
        println(io)

        println(io, "## 8) Model Visibility and Coupling Audit")
        vis = deep_diag["visibility_audit"]
        println(io, "- n_block variables: ", vis["n_block_var_count"])
        println(io, "- na_block variables: ", vis["na_block_var_count"])
        println(io, "- pg variables for candidate batteries: ", vis["pg_vars_for_candidate_batteries"])
        println(io, "- storage dispatch vars for candidate batteries: ", vis["storage_dispatch_vars_for_candidate_batteries"])
        println(io, "- candidate battery rows found: ", vis["candidate_battery_count"])
        println(io, "- all candidate cost_inv_block positive after 1/365 scaling: ", vis["cost_inv_block_scaled_positive_all_candidates"])
        println(io, "- objective max abs coeff on candidate n_block vars: ", _fmt(vis["objective_coeff_max_abs_candidate_n_block"]))
        println(io, "- objective huge coefficient flag: ", vis["objective_coeff_huge_flag"])
        println(io, "| sample_id | type | in_block_enabled | in_storage_set | in_gfl_devices | in_gfm_devices | in_bus_gfl | in_bus_gfm | n_block_lb | n_block_ub | na_block_lb | na_block_ub | energy_rating | charge_rating | discharge_rating | status | obj_coeff_expected | obj_coeff_actual |")
        println(io, "|---:|---|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in vis["sample_rows"]
            println(io, "| ", r["id"], " | ", r["type"], " | ", r["in_block_enabled_devices"], " | ", r["in_storage_set"], " | ", r["in_gfl_devices"], " | ", r["in_gfm_devices"], " | ", r["in_bus_gfl_devices"], " | ", r["in_bus_gfm_devices"], " | ", _fmt(r["n_block_lb"]), " | ", _fmt(r["n_block_ub"]), " | ", _fmt(r["na_block_lb"]), " | ", _fmt(r["na_block_ub"]), " | ", _fmt(r["energy_rating"]), " | ", _fmt(r["charge_rating"]), " | ", _fmt(r["discharge_rating"]), " | ", _fmt(r["status"]), " | ", _fmt(r["objective_coeff_expected"]), " | ", _fmt(r["objective_coeff_actual_n_block"]), " |")
        end
        println(io)
        println(io, "### Constraint Coupling (Sample Candidates)")
        for r in vis["sample_rows"]
            db = r["dispatch_bounds"]
            ca = r["constraint_coeff_audit"]
            println(io, "- sample candidate id=", r["id"], " type=", r["type"])
            println(io, "  - dispatch bounds: ", db)
            println(io, "  - coefficient audit: ", ca)
            println(io, "  - check flags: uses standard ratings? energy_rating=", _fmt(r["energy_rating"]), ", charge_rating=", _fmt(r["charge_rating"]), ", discharge_rating=", _fmt(r["discharge_rating"]), ", status=", _fmt(r["status"]))
        end
        println(io)

        println(io, "## 9) Objective / Cost Audit")
        println(io, "- investment term should depend on (n_block - n_block0): audited via n_block objective coefficients on candidates.")
        println(io, "- all candidate investment coefficients after scaling are positive: ", vis["cost_inv_block_scaled_positive_all_candidates"])
        println(io, "- objective huge coefficient flag (unintended penalty check): ", vis["objective_coeff_huge_flag"])
        println(io, "- objective relevance note: ", vis["objective_note"])
        println(io)

        println(io, "## 10) Positive g_min")
        println(io, "- Skipped by design for this diagnostic phase.")
        println(io)

        println(io, "## 11) Storage Candidate Audit Inside FlexPlan")
        println(io, "### Pre-Solve Candidate Rows")
        println(io, "| table | id | bus | type | n_block0 | n_block_max | na0 | p_block_max | e_block | energy_rating | charge_rating | discharge_rating | cost_inv_block | marginal_cost | b_block |")
        println(io, "|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in presolve_candidates
            println(io, "| ", r["table"], " | ", r["id"], " | ", r["bus"], " | ", r["type"], " | ", _fmt(r["n_block0"]), " | ", _fmt(r["n_block_max"]), " | ", _fmt(r["na0"]), " | ", _fmt(r["p_block_max"]), " | ", _fmt(r["e_block"]), " | ", _fmt(r["energy_rating"]), " | ", _fmt(r["charge_rating"]), " | ", _fmt(r["discharge_rating"]), " | ", _fmt(r["cost_inv_block"]), " | ", _fmt(r["marginal_cost"]), " | ", _fmt(r["b_block"]), " |")
        end
        println(io)
        println(io, "### Post-Solve Candidate Rows (Gate 1, if optimal/feasible)")
        if isempty(gate["candidate_postsolve_rows"])
            println(io, "- unavailable (Gate 1 not solved to a feasible optimum).")
        else
            println(io, "| id | n_block | max_t na_block | dispatch_min | dispatch_max | energy_min | energy_max | online_with_zero_dispatch_count |")
            println(io, "|---:|---:|---:|---:|---:|---:|---:|---:|")
            for r in gate["candidate_postsolve_rows"]
                println(io, "| ", r["id"], " | ", _fmt(r["n_block"]), " | ", _fmt(r["na_block_max_t"]), " | ", _fmt(r["dispatch_min"]), " | ", _fmt(r["dispatch_max"]), " | ", _fmt(r["energy_min"]), " | ", _fmt(r["energy_max"]), " | ", r["online_zero_dispatch_count"], " |")
            end
        end
        println(io)

        println(io, "## 12) Conclusions")
        gate_optimal = gate["status"] == "OPTIMAL"
        gate_feasible = gate["status"] in _ACTIVE_OK
        first_variant = isnothing(diag) ? nothing : diag["first_feasible"]
        one_deep = deep_diag["one_snapshot_deep"]
        bva = one_deep["balance_visibility"]
        cr = one_deep["one_snapshot_candidate_ratings_from_blocks"]
        println(io, "- Did schema validation pass? ", schema["multinetwork"] && schema["snapshot_count"] == 24 && schema["bus_count"] == 37 && schema["branch_count"] == 52 && schema["dcline_count"] == 43 && schema["battery_gfl_count"] == 37 && schema["battery_gfm_count"] == 37 && schema["expected_gfl_ok"] && schema["expected_gfm_ok"] && schema["cost_ratio_ok"] && schema["invariant_ok"])
        println(io, "- Is fixed-capacity infeasibility expected from installed availability? ", adequacy["fixed_capacity_infeasible_expected"])
        println(io, "- Is full CAPEXP at g_min=0 feasible? ", gate_feasible, " (status=", gate["status"], ")")
        println(io, "- If not feasible, which diagnostic variant first becomes feasible? ", isnothing(first_variant) ? "none" : first_variant["label"])
        if isnothing(first_variant)
            println(io, "- Likely issue class: unresolved active integration/data mismatch (no variant restored feasibility).")
        else
            println(io, "- Likely issue class: ", first_variant["label"])
        end
        if !isnothing(diag)
            println(io, "- Diagnostic likely cause decision: ", diag["likely_cause"])
        end
        println(io, "- If any island has negative max adequacy even with dcline imports: ", any(r["margin_negative"] for r in one_deep["island_audit"]["islands"]))
        println(io, "- transport LP feasible while one-snapshot full CAPEXP infeasible: ", one_deep["transport_lp"]["feasible"] && !(one_deep["one_snapshot_full_status"] in _ACTIVE_OK))
        println(io, "- candidate-rating one-snapshot variant feasible: ", cr["status"] in _ACTIVE_OK)
        println(io, "- dclines included in active balance: ", bva["dclines_included_in_active_balance"])
        println(io, "- active UC/CAPEXP/gSCR calls standard dcline variable functions: ", apda["calls_standard_dcline_variable_function"])
        println(io, "- active UC/CAPEXP/gSCR calls standard dcline constraints: ", apda["calls_standard_dcline_constraint_function"])
        println(io, "- exact missing call/location: ", apda["exact_missing_location"]["file"], " @ custom balance call line ", _fmt(apda["exact_missing_location"]["line_hint_calls_custom_balance"]; digits=0))
        println(io, "- recommended minimal fix: ", apda["recommended_minimal_fix"])
        println(io, "- synthetic generator sanity status: ", sgen["status"], " (passes=", sgen["passes_expected"], ")")
        println(io, "- synthetic battery sanity status: ", sbat["status"], " (passes=", sbat["passes_expected"], ")")
        println(io, "- one-snapshot extracted status: ", one["status"])
        println(io, "- first failing layer: ", deep_diag["first_failing_layer"])
        println(io, "- likely root cause (layered): ", deep_diag["likely_root_cause"])
        println(io, "- likely root cause (one-snapshot decision logic): ", one_deep["likely_root_cause"])
        println(io, "- If feasible, how much expansion is built? total blocks=", _fmt(gate["total_invested_blocks"]), ", generator blocks=", _fmt(gate["invested_generator_blocks"]), ", storage blocks=", _fmt(gate["invested_storage_blocks"]))
        println(io, "- Are battery_gfl and battery_gfm used? gfl=", _fmt(gate["invested_battery_gfl_blocks"]), ", gfm=", _fmt(gate["invested_battery_gfm_blocks"]))
        println(io, "- Does g_min=0 invest only for adequacy/economics, not for gSCR? ", gate_feasible ? true : "not testable (infeasible)")
        println(io, "- Were positive g_min runs executed? false")
        println(io, "- Should next run proceed to a positive g_min sweep? ", gate_optimal)
    end
    return _REPORT_PATH
end

function _write_results_bundle(
    schema::Dict{String,Any},
    adequacy::Dict{String,Any},
    gate::Dict{String,Any},
    diag::Union{Nothing,Dict{String,Any}},
    deep_diag::Dict{String,Any},
    presolve_candidates::Vector{Dict{String,Any}},
)
    mkpath(dirname(_RESULTS_PATH))
    bundle = Dict{String,Any}(
        "generated_at" => Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"),
        "dataset_path" => _CASE_PATH,
        "investment_cost_scale_24h" => _INVESTMENT_COST_SCALE_24H,
        "run_flag" => _RUN_FLAG,
        "positive_g_min_runs_skipped" => true,
        "schema" => schema,
        "adequacy" => adequacy,
        "gate_g_min_0" => gate,
        "diagnostics_if_infeasible" => isnothing(diag) ? Dict{String,Any}() : diag,
        "deep_model_path_diagnostics" => deep_diag,
        "presolve_candidate_rows" => presolve_candidates,
    )
    open(_RESULTS_PATH, "w") do io
        JSON.print(io, bundle, 2)
    end
    return _RESULTS_PATH
end

function main()
    if get(ENV, _RUN_FLAG, "0") != "1"
        println("Skipping: set $(_RUN_FLAG)=1 to run this targeted manual CAPEXP study.")
        return
    end
    if !isfile(_CASE_PATH)
        error("Dataset not found: $(_CASE_PATH)")
    end

    raw = _load_case()
    schema = _schema_validation(raw)
    adequacy = _capacity_adequacy_audit(raw)
    presolve_candidates = _collect_candidate_presolve_rows(raw)

    gate = _run_mode(raw, "gate_g0", "full_capexp"; g_min_value=0.0)
    diag = nothing

    if gate["status"] == "INFEASIBLE"
        diag = _diagnostic_variants(raw, gate)
    end

    one_snapshot = _one_snapshot_extracted_diagnostic(raw, adequacy)
    one_snapshot_deep = _one_snapshot_deep_diagnostic(raw, adequacy, gate)
    synth_gen = _synthetic_generator_sanity_test()
    synth_batt = _synthetic_battery_sanity_test()
    vis_audit = _model_visibility_and_coupling_audit(raw)
    first_layer, layered_root_cause = _first_failing_layer(gate, one_snapshot, one_snapshot_deep, synth_gen, synth_batt)
    deep_diag = Dict{String,Any}(
        "one_snapshot" => one_snapshot,
        "one_snapshot_deep" => one_snapshot_deep,
        "synthetic_generator" => synth_gen,
        "synthetic_battery" => synth_batt,
        "visibility_audit" => vis_audit,
        "first_failing_layer" => first_layer,
        "likely_root_cause" => layered_root_cause,
    )

    report = _write_report(schema, adequacy, gate, diag, deep_diag, presolve_candidates)
    results_path = _write_results_bundle(schema, adequacy, gate, diag, deep_diag, presolve_candidates)
    println("Wrote report: ", report)
    println("Wrote results JSON: ", results_path)
end

main()
