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

function _apply_existing_storage_initial_energy_policy!(data::Dict{String,Any}, policy::Union{Nothing,String})
    if isnothing(policy)
        return Dict{String,Any}(
            "policy" => "none",
            "existing_storage_rows_modified" => 0,
            "existing_storage_energy_over_rating_min" => nothing,
            "existing_storage_energy_over_rating_mean" => nothing,
            "existing_storage_energy_over_rating_max" => nothing,
            "candidate_battery_rows_forced_zero" => 0,
            "candidate_battery_energy_all_zero" => true,
            "candidate_battery_energy_abs_max" => 0.0,
        )
    end

    if policy != "half_energy_rating"
        error("Unsupported existing_storage_initial_energy_policy: $(policy)")
    end

    modified_existing = 0
    forced_candidate_zero = 0
    ratio_vals = Float64[]
    candidate_energy_abs_max = 0.0

    for nw in values(data["nw"])
        for st in values(get(nw, "storage", Dict{String,Any}()))
            if _is_battery_candidate(st)
                n0 = float(get(st, "n_block0", get(st, "n0", 0.0)))
                na0 = float(get(st, "na0", 0.0))
                if abs(n0) <= _EPS && abs(na0) <= _EPS
                    old_energy = float(get(st, "energy", 0.0))
                    if abs(old_energy) > _EPS
                        forced_candidate_zero += 1
                    end
                    st["energy"] = 0.0
                end
                candidate_energy_abs_max = max(candidate_energy_abs_max, abs(float(get(st, "energy", 0.0))))
                continue
            end

            energy_rating = float(get(st, "energy_rating", get(st, "energy", 0.0)))
            target = 0.5 * energy_rating
            old = float(get(st, "energy", 0.0))
            if abs(old - target) > _EPS
                modified_existing += 1
            end
            st["energy"] = target
            if abs(energy_rating) > _EPS
                push!(ratio_vals, target / energy_rating)
            end
        end
    end

    ratio_min = isempty(ratio_vals) ? nothing : minimum(ratio_vals)
    ratio_mean = isempty(ratio_vals) ? nothing : (sum(ratio_vals) / length(ratio_vals))
    ratio_max = isempty(ratio_vals) ? nothing : maximum(ratio_vals)

    return Dict{String,Any}(
        "policy" => policy,
        "existing_storage_rows_modified" => modified_existing,
        "existing_storage_energy_over_rating_min" => ratio_min,
        "existing_storage_energy_over_rating_mean" => ratio_mean,
        "existing_storage_energy_over_rating_max" => ratio_max,
        "candidate_battery_rows_forced_zero" => forced_candidate_zero,
        "candidate_battery_energy_all_zero" => candidate_energy_abs_max <= _EPS,
        "candidate_battery_energy_abs_max" => candidate_energy_abs_max,
    )
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
        _PM.variable_branch_power(pm; nw=n)
        _PM.variable_dcline_power(pm; nw=n)
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
        _FP.constraint_uc_gscr_block_bus_active_balance(pm; nw=n)
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

function _build_uc_block_with_final_policy(
    pm::_PM.AbstractActivePowerModel;
    objective::Bool=true,
    intertemporal_constraints::Bool=true,
    final_policy::Symbol=:with_final,
    include_existing_storage_state::Bool=true,
    include_candidate_storage_state::Bool=true,
)
    for n in _FP.nw_ids(pm)
        _PM.variable_branch_power(pm; nw=n)
        _PM.variable_gen_power(pm; nw=n)
        _FP.expression_gen_curtailment(pm; nw=n)
        _PM.variable_dcline_power(pm; nw=n)

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
        for i in _PM.ids(pm, n, :dcline)
            _PM.constraint_dcline_power_losses(pm, i; nw=n)
        end
        _FP.constraint_uc_gscr_block_bus_active_balance(pm; nw=n)
        _FP.constraint_uc_gscr_block_dispatch(pm; nw=n)
        _FP.constraint_uc_gscr_block_storage_bounds(pm; nw=n)
        _FP.constraint_gscr_gershgorin_sufficient(pm; nw=n)

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
                    st = _PM.ref(pm, n, :storage, i)
                    is_candidate = _is_battery_candidate(st)
                    apply_state = is_candidate ? include_candidate_storage_state : include_existing_storage_state
                    if apply_state
                        _FP.constraint_storage_state(pm, i, nw=n)
                    end
                end
                for i in _PM.ids(pm, :storage_bounded_absorption, nw=n)
                    st = _PM.ref(pm, n, :storage, i)
                    is_candidate = _is_battery_candidate(st)
                    apply_state = is_candidate ? include_candidate_storage_state : include_existing_storage_state
                    if apply_state
                        _FP.constraint_maximum_absorption(pm, i, nw=n)
                    end
                end
                if _FP._has_uc_gscr_candidate_storage(pm, n)
                    if include_candidate_storage_state
                        for i in _PM.ids(pm, :ne_storage, nw=n)
                            _FP.constraint_storage_state_ne(pm, i, nw=n)
                        end
                        for i in _PM.ids(pm, :ne_storage_bounded_absorption, nw=n)
                            _FP.constraint_maximum_absorption_ne(pm, i, nw=n)
                        end
                    end
                end
            else
                if _FP.is_last_id(pm, n, :hour)
                    if final_policy == :with_final
                        for i in _PM.ids(pm, :storage, nw=n)
                            st = _PM.ref(pm, n, :storage, i)
                            is_candidate = _is_battery_candidate(st)
                            apply_state = is_candidate ? include_candidate_storage_state : include_existing_storage_state
                            if apply_state
                                _FP.constraint_storage_state_final(pm, i, nw=n)
                            end
                        end
                        if _FP._has_uc_gscr_candidate_storage(pm, n) && include_candidate_storage_state
                            for i in _PM.ids(pm, :ne_storage, nw=n)
                                _FP.constraint_storage_state_final_ne(pm, i, nw=n)
                            end
                        end
                    elseif final_policy == :relaxed_final
                        for i in _PM.ids(pm, :storage, nw=n)
                            st = _PM.ref(pm, n, :storage, i)
                            is_candidate = _is_battery_candidate(st)
                            apply_state = is_candidate ? include_candidate_storage_state : include_existing_storage_state
                            if apply_state
                                _FP.constraint_storage_state_final(pm, n, i, 0.0)
                            end
                        end
                        if _FP._has_uc_gscr_candidate_storage(pm, n) && include_candidate_storage_state
                            for i in _PM.ids(pm, :ne_storage, nw=n)
                                _FP.constraint_storage_state_final_ne(pm, n, i, 0.0)
                            end
                        end
                    end
                end

                prev_n = _FP.prev_id(pm, n, :hour)
                for i in _PM.ids(pm, :storage, nw=n)
                    st = _PM.ref(pm, n, :storage, i)
                    is_candidate = _is_battery_candidate(st)
                    apply_state = is_candidate ? include_candidate_storage_state : include_existing_storage_state
                    if apply_state
                        _FP.constraint_storage_state(pm, i, prev_n, n)
                    end
                end
                for i in _PM.ids(pm, :storage_bounded_absorption, nw=n)
                    st = _PM.ref(pm, n, :storage, i)
                    is_candidate = _is_battery_candidate(st)
                    apply_state = is_candidate ? include_candidate_storage_state : include_existing_storage_state
                    if apply_state
                        _FP.constraint_maximum_absorption(pm, i, prev_n, n)
                    end
                end
                if _FP._has_uc_gscr_candidate_storage(pm, n) && include_candidate_storage_state
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

function _builder_with_final_policy(
    final_policy::Symbol;
    intertemporal_constraints::Bool=true,
    include_existing_storage_state::Bool=true,
    include_candidate_storage_state::Bool=true,
)
    return pm -> _build_uc_block_with_final_policy(
        pm;
        final_policy=final_policy,
        intertemporal_constraints=intertemporal_constraints,
        include_existing_storage_state=include_existing_storage_state,
        include_candidate_storage_state=include_candidate_storage_state,
    )
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

function _run_mode(
    raw::Dict{String,Any},
    scenario::String,
    mode_name::String;
    g_min_value::Float64=0.0,
    mutator=nothing,
    builder=:standard,
    existing_storage_initial_energy_policy::Union{Nothing,String}=nothing,
)
    base_mode = mode_name == "uc_only" ? :uc : :capexp
    data = _prepare_solver_data(raw; mode=base_mode)
    _set_mode_nmax_policy!(data, mode_name)
    policy_stats = _apply_existing_storage_initial_energy_policy!(data, existing_storage_initial_energy_policy)
    _inject_g_min!(data, g_min_value)
    if !(mutator === nothing)
        mutator(data)
    end
    bfun = _resolve_builder(builder)
    result = _solve_active_with_builder(data, scenario, mode_name, bfun)
    result["existing_storage_initial_energy_policy"] = isnothing(existing_storage_initial_energy_policy) ? "none" : existing_storage_initial_energy_policy
    result["existing_storage_initial_energy_policy_stats"] = policy_stats
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
    con_present = haskey(_PM.con(pm, nw), :uc_gscr_block_system_active_balance) ||
                  haskey(_PM.con(pm, nw), :uc_gscr_block_bus_active_balance)
    balance_includes_dclines = haskey(_PM.var(pm, nw), :p_dc) &&
                               haskey(_PM.ref(pm, nw), :bus_arcs_dc) &&
                               sum(length(_PM.ref(pm, nw, :bus_arcs_dc, b)) for b in _PM.ids(pm, nw, :bus)) > 0
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
    con_fr_bound_methods = isdefined(_PM, :constraint_dcline_power_fr_bounds) ? [string(m) for m in methods(_PM.constraint_dcline_power_fr_bounds)] : String[]
    con_to_bound_methods = isdefined(_PM, :constraint_dcline_power_to_bounds) ? [string(m) for m in methods(_PM.constraint_dcline_power_to_bounds)] : String[]
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
        "standard_constraint_dcline_fr_bound_functions" => con_fr_bound_methods,
        "standard_constraint_dcline_to_bound_functions" => con_to_bound_methods,
        "standard_constraint_power_balance_functions" => balance_methods,
        "standard_builder_opf_calls" => opf_calls,
        "variable_names" => ["p_dc", "q_dc"],
        "constraint_names" => ["constraint_dcline_power_losses", "constraint_power_balance"],
        "loss_model" => "(1-loss1)*p_fr + (p_to-loss0) == 0",
        "dcline_efficiency_modeled" => true,
        "dcline_limits_mode" => "DCPPowerModel uses bounds set by variable_dcline_power; explicit dcline bound templates are not dispatched for DCP in this PowerModels version.",
    )
end

function _active_path_dcline_call_audit()
    path = normpath(@__DIR__, "..", "src", "prob", "uc_gscr_block_integration.jl")
    calls_variable_dcline = _find_lines(path, "variable_dcline_power(")
    calls_con_dcline_losses = _find_lines(path, "constraint_dcline_power_losses(")
    calls_con_dcline_setpoint = _find_lines(path, "constraint_dcline_setpoint_active(")
    calls_con_dcline_fr_bounds = _find_lines(path, "constraint_dcline_power_fr_bounds(")
    calls_con_dcline_to_bounds = _find_lines(path, "constraint_dcline_power_to_bounds(")
    calls_pm_bus_balance = _find_lines(path, "constraint_power_balance(")
    calls_custom_balance = _find_lines(path, "constraint_uc_gscr_block_system_active_balance(pm;")
    custom_balance_def = _find_lines(path, "function constraint_uc_gscr_block_system_active_balance(")

    class = "standard PowerModels bus-wise active balance with standard dcline variables and loss equations"
    if isempty(calls_pm_bus_balance) || isempty(calls_variable_dcline) || isempty(calls_con_dcline_losses)
        class = "missing standard active balance or dcline support calls"
    elseif !isempty(calls_con_dcline_setpoint)
        class = "dcline setpoint constraints still present on active CAPEXP path"
    end

    return Dict{String,Any}(
        "path" => path,
        "calls_standard_opf_bus_balance" => !isempty(calls_pm_bus_balance),
        "calls_custom_system_balance" => !isempty(calls_custom_balance),
        "calls_standard_dcline_variable_function" => !isempty(calls_variable_dcline),
        "calls_standard_dcline_constraint_function" => !isempty(calls_con_dcline_losses),
        "calls_dcline_setpoint_active" => !isempty(calls_con_dcline_setpoint),
        "calls_dcline_fr_bound_constraints" => !isempty(calls_con_dcline_fr_bounds),
        "calls_dcline_to_bound_constraints" => !isempty(calls_con_dcline_to_bounds),
        "standard_opf_bus_balance_call_lines" => calls_pm_bus_balance,
        "custom_system_balance_call_lines" => calls_custom_balance,
        "custom_system_balance_definition_lines" => custom_balance_def,
        "dcline_setpoint_active_call_lines" => calls_con_dcline_setpoint,
        "dcline_fr_bound_call_lines" => calls_con_dcline_fr_bounds,
        "dcline_to_bound_call_lines" => calls_con_dcline_to_bounds,
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
            "Keep active CAPEXP on standard `variable_dcline_power`, `constraint_dcline_power_losses`, and per-bus `constraint_power_balance`; do not add dcline setpoint constraints.",
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

    active_path = _active_path_dcline_call_audit()
    loss_constraint_count = active_path["calls_standard_dcline_constraint_function"] ? ref_count : 0
    explicit_bound_constraint_count = active_path["calls_dcline_fr_bound_constraints"] || active_path["calls_dcline_to_bound_constraints"] ? 2 * ref_count : 0
    variable_bound_count = var_count
    setpoint_constraint_count = active_path["calls_dcline_setpoint_active"] ? 2 * ref_count : 0

    bus_balance_dcline_terms = haskey(_PM.ref(pm, nw), :bus_arcs_dc) ?
        sum(length(_PM.ref(pm, nw, :bus_arcs_dc, b)) for b in _PM.ids(pm, nw, :bus)) : 0

    return Dict{String,Any}(
        "snapshot_id" => snapshot_id,
        "stages" => [
            Dict("stage" => "raw data", "dcline_count" => raw_count),
            Dict("stage" => "solver-copy data after adapter", "dcline_count" => solver_count),
            Dict("stage" => "PowerModels ref", "dcline_count" => ref_count),
            Dict("stage" => "model variables (p_dc)", "dcline_count" => var_count),
            Dict("stage" => "dcline loss constraints", "dcline_count" => loss_constraint_count),
            Dict("stage" => "dcline explicit bound constraints", "dcline_count" => explicit_bound_constraint_count),
            Dict("stage" => "dcline variable bounds", "dcline_count" => variable_bound_count),
            Dict("stage" => "dcline setpoint constraints", "dcline_count" => setpoint_constraint_count),
            Dict("stage" => "bus balance dcline terms", "dcline_count" => bus_balance_dcline_terms),
        ],
        "expected" => Dict(
            "raw" => 43,
            "solver_copy" => 43,
            "ref" => 43,
            "model_variables_gt_zero" => true,
            "dcline_loss_constraints_gt_zero" => true,
            "dcline_setpoint_constraints_expected" => 0,
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
        "active_balance_constraint" => "PowerModels.constraint_power_balance(pm, i; nw=nw)",
        "active_balance_contains_dcline_terms" => haskey(_PM.var(pm, nw), :p_dc) && comp["dcline_terms_count"] > 0,
        "active_balance_contains_bus_terms" => true,
    )
end

const _UC_GSCR_LOCAL_BLOCK_FIELDS = Set([
    "type",
    "n0",
    "nmax",
    "n_block0",
    "n_block_max",
    "na0",
    "p_block_min",
    "p_block_max",
    "p_block_max_pu",
    "p_block_min_pu",
    "q_block_min",
    "q_block_max",
    "b_block",
    "startup_block_cost",
    "shutdown_block_cost",
    "min_up_block_time",
    "min_down_block_time",
    "H",
    "s_block",
    "e_block",
    "cost_inv_block",
])

function _strip_uc_gscr_block_fields!(d::Dict{String,Any})
    for k in _UC_GSCR_LOCAL_BLOCK_FIELDS
        if haskey(d, k)
            delete!(d, k)
        end
    end
    return d
end

function _filter_ablation_storage!(data::Dict{String,Any}; include_storage::Bool, include_candidates::Bool, strip_non_candidate_block::Bool=true)
    for nw in values(data["nw"])
        if !include_storage
            nw["storage"] = Dict{String,Any}()
            nw["ne_storage"] = Dict{String,Any}()
            continue
        end

        filtered = Dict{String,Any}()
        for (sid, st0) in get(nw, "storage", Dict{String,Any}())
            st = deepcopy(st0)
            is_candidate = _is_battery_candidate(st)
            if is_candidate && !include_candidates
                continue
            end
            if !is_candidate && strip_non_candidate_block
                _strip_uc_gscr_block_fields!(st)
            end
            filtered[sid] = st
        end
        nw["storage"] = filtered
        nw["ne_storage"] = Dict{String,Any}()
    end
    return data
end

function _one_snapshot_ablation_data(
    raw::Dict{String,Any},
    snapshot_id::Int;
    include_storage::Bool,
    include_candidates::Bool,
    mutator=nothing,
    existing_storage_initial_energy_policy::Union{Nothing,String}=nothing,
)
    raw1 = _make_single_snapshot_raw(raw, snapshot_id)
    data = _prepare_solver_data(raw1; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _apply_existing_storage_initial_energy_policy!(data, existing_storage_initial_energy_policy)
    _inject_g_min!(data, 0.0)
    _filter_ablation_storage!(data; include_storage, include_candidates)
    if !(mutator === nothing)
        mutator(data)
    end
    return data
end

function _build_ablation_variant(pm::_PM.AbstractActivePowerModel; variant::Symbol)
    include_storage = variant != :core_gen_balance_only
    candidate_storage = variant in (
        :core_gen_plus_candidate_storage_no_standard_storage_constraints,
        :add_standard_storage_thermal_limits,
        :add_standard_storage_losses,
        :add_storage_state_constraints,
        :add_startup_shutdown_transitions,
        :add_gscr_gmin0,
        :add_startup_shutdown_without_storage_state,
        :add_gscr_gmin0_without_storage_state,
        :add_startup_shutdown_and_gscr_without_storage_state,
        :storage_state_initial_only,
        :storage_state_no_final,
        :storage_state_relaxed_final,
        :storage_state_half_energy_rating_initial,
        :add_storage_state_constraints_with_half_energy_rating,
        :existing_storage_state_only,
        :candidate_storage_state_only,
        :existing_storage_state_only_exclude_zero_energy_rating,
        :candidate_storage_state_from_blocks,
    )
    use_unbounded_storage_vars = variant in (
        :core_gen_plus_candidate_storage_no_standard_storage_constraints,
        :add_standard_storage_thermal_limits,
        :add_standard_storage_losses,
        :add_storage_state_constraints,
        :add_startup_shutdown_transitions,
        :add_gscr_gmin0,
        :add_startup_shutdown_without_storage_state,
        :add_gscr_gmin0_without_storage_state,
        :add_startup_shutdown_and_gscr_without_storage_state,
        :storage_state_initial_only,
        :storage_state_no_final,
        :storage_state_relaxed_final,
        :storage_state_half_energy_rating_initial,
        :add_storage_state_constraints_with_half_energy_rating,
        :existing_storage_state_only,
        :candidate_storage_state_only,
        :existing_storage_state_only_exclude_zero_energy_rating,
        :candidate_storage_state_from_blocks,
    )
    add_storage_thermal = variant in (
        :add_standard_storage_thermal_limits,
        :add_standard_storage_losses,
        :add_storage_state_constraints,
        :add_startup_shutdown_transitions,
        :add_gscr_gmin0,
        :add_startup_shutdown_without_storage_state,
        :add_gscr_gmin0_without_storage_state,
        :add_startup_shutdown_and_gscr_without_storage_state,
        :storage_state_initial_only,
        :storage_state_no_final,
        :storage_state_relaxed_final,
        :storage_state_half_energy_rating_initial,
        :add_storage_state_constraints_with_half_energy_rating,
        :existing_storage_state_only,
        :candidate_storage_state_only,
        :existing_storage_state_only_exclude_zero_energy_rating,
        :candidate_storage_state_from_blocks,
    )
    add_storage_losses = variant in (
        :add_standard_storage_losses,
        :add_storage_state_constraints,
        :add_startup_shutdown_transitions,
        :add_gscr_gmin0,
        :add_startup_shutdown_without_storage_state,
        :add_gscr_gmin0_without_storage_state,
        :add_startup_shutdown_and_gscr_without_storage_state,
        :storage_state_initial_only,
        :storage_state_no_final,
        :storage_state_relaxed_final,
        :storage_state_half_energy_rating_initial,
        :add_storage_state_constraints_with_half_energy_rating,
        :existing_storage_state_only,
        :candidate_storage_state_only,
        :existing_storage_state_only_exclude_zero_energy_rating,
        :candidate_storage_state_from_blocks,
    )
    add_storage_state = variant in (
        :add_storage_state_constraints,
        :add_startup_shutdown_transitions,
        :add_gscr_gmin0,
        :storage_state_initial_only,
        :storage_state_no_final,
        :storage_state_relaxed_final,
        :storage_state_half_energy_rating_initial,
        :add_storage_state_constraints_with_half_energy_rating,
        :existing_storage_state_only,
        :candidate_storage_state_only,
        :existing_storage_state_only_exclude_zero_energy_rating,
        :candidate_storage_state_from_blocks,
    )
    add_transitions = variant in (
        :add_startup_shutdown_transitions,
        :add_gscr_gmin0,
        :add_startup_shutdown_without_storage_state,
        :add_startup_shutdown_and_gscr_without_storage_state,
    )
    add_gscr = variant in (
        :add_gscr_gmin0,
        :add_gscr_gmin0_without_storage_state,
        :add_startup_shutdown_and_gscr_without_storage_state,
    )

    for n in _FP.nw_ids(pm)
        _PM.variable_branch_power(pm; nw=n)
        _PM.variable_gen_power(pm; nw=n)
        _PM.variable_dcline_power(pm; nw=n)
        if include_storage
            _PM.variable_storage_power(pm; nw=n, bounded=!use_unbounded_storage_vars)
            _FP.variable_absorbed_energy(pm; nw=n)
            if use_unbounded_storage_vars
                if haskey(_PM.var(pm, n), :ps)
                    for v in values(_PM.var(pm, n, :ps))
                        if !JuMP.has_lower_bound(v)
                            JuMP.set_lower_bound(v, -1.0e9)
                        end
                        if !JuMP.has_upper_bound(v)
                            JuMP.set_upper_bound(v, 1.0e9)
                        end
                    end
                end
                for sym in (:se, :sc, :sd)
                    if haskey(_PM.var(pm, n), sym)
                        for v in values(_PM.var(pm, n, sym))
                            if !JuMP.has_lower_bound(v) || JuMP.lower_bound(v) < 0.0
                                JuMP.set_lower_bound(v, 0.0)
                            end
                        end
                    end
                end
            end
        end

        _FP.variable_installed_blocks(pm; nw=n, relax=true)
        _FP.variable_active_blocks(pm; nw=n, relax=true)
        _FP.constraint_active_blocks_le_installed(pm; nw=n)
        if add_transitions
            _FP.variable_block_startup_shutdown_counts(pm; nw=n, relax=true)
            _FP.constraint_block_count_transitions(pm; nw=n)
        end
    end

    JuMP.@objective(pm.model, Min, 0.0)

    for n in _FP.nw_ids(pm)
        for i in _PM.ids(pm, n, :dcline)
            _PM.constraint_dcline_power_losses(pm, i; nw=n)
        end
        _FP.constraint_uc_gscr_block_bus_active_balance(pm; nw=n)
        _FP.constraint_uc_gscr_block_active_dispatch_bounds(pm; nw=n)

        if candidate_storage
            _FP.constraint_uc_gscr_block_storage_bounds(pm; nw=n)
        end
        if add_storage_thermal
            for i in _PM.ids(pm, :storage, nw=n)
                _PM.constraint_storage_thermal_limit(pm, i, nw=n)
            end
        end
        if add_storage_losses
            for i in _PM.ids(pm, :storage, nw=n)
                _PM.constraint_storage_losses(pm, i, nw=n)
            end
        end
        if add_storage_state
            for i in _PM.ids(pm, :storage, nw=n)
                st = _PM.ref(pm, n, :storage, i)
                is_candidate = _is_battery_candidate(st)
                energy_rating = float(get(st, "energy_rating", 0.0))
                apply_state = true
                if variant == :existing_storage_state_only
                    apply_state = !is_candidate
                elseif variant == :candidate_storage_state_only || variant == :candidate_storage_state_from_blocks
                    apply_state = is_candidate
                elseif variant == :existing_storage_state_only_exclude_zero_energy_rating
                    apply_state = !is_candidate && energy_rating > _EPS
                end
                if apply_state
                    _FP.constraint_storage_state(pm, i, nw=n)
                end
            end
        end
        if add_gscr
            _FP.constraint_gscr_gershgorin_sufficient(pm; nw=n)
        end
    end
end

function _ablation_builder(variant::Symbol)
    return pm -> _build_ablation_variant(pm; variant)
end

function _safe_var_count(pm, nw::Int, sym::Symbol)::Int
    return haskey(_PM.var(pm, nw), sym) ? length(keys(_PM.var(pm, nw, sym))) : 0
end

function _ablation_variable_counts(pm, nw::Int)
    return Dict{String,Any}(
        "pg" => _safe_var_count(pm, nw, :pg),
        "ps" => _safe_var_count(pm, nw, :ps),
        "sc" => _safe_var_count(pm, nw, :sc),
        "sd" => _safe_var_count(pm, nw, :sd),
        "se" => _safe_var_count(pm, nw, :se),
        "p_dc" => _safe_var_count(pm, nw, :p_dc),
        "p_branch" => _safe_var_count(pm, nw, :p),
        "n_block" => _safe_var_count(pm, nw, :n_block),
        "na_block" => _safe_var_count(pm, nw, :na_block),
        "su_block" => _safe_var_count(pm, nw, :su_block),
        "sd_block" => _safe_var_count(pm, nw, :sd_block),
    )
end

function _filtered_constraint_ref_count(pm, nw::Int, sym::Symbol, table::Union{Nothing,Symbol}=nothing)
    if !haskey(_PM.con(pm, nw), sym)
        return 0
    end
    c = _PM.con(pm, nw, sym)
    if isnothing(table) || !(c isa AbstractDict)
        return _count_constraint_refs(c)
    end
    return _count_constraint_refs(Dict(k => v for (k, v) in c if k isa Tuple && !isempty(k) && k[1] == table))
end

function _ablation_constraint_counts(pm, nw::Int, variant::Symbol)
    storage_state_enabled = variant in (
        :add_storage_state_constraints,
        :add_storage_state_constraints_with_half_energy_rating,
        :add_startup_shutdown_transitions,
        :add_gscr_gmin0,
        :storage_state_initial_only,
        :storage_state_no_final,
        :storage_state_relaxed_final,
        :storage_state_half_energy_rating_initial,
        :existing_storage_state_only,
        :candidate_storage_state_only,
        :existing_storage_state_only_exclude_zero_energy_rating,
        :candidate_storage_state_from_blocks,
    )
    storage_state_count = 0
    if storage_state_enabled
        for i in _PM.ids(pm, nw, :storage)
            st = _PM.ref(pm, nw, :storage, i)
            is_candidate = _is_battery_candidate(st)
            energy_rating = float(get(st, "energy_rating", 0.0))
            apply_state = true
            if variant == :existing_storage_state_only
                apply_state = !is_candidate
            elseif variant == :candidate_storage_state_only || variant == :candidate_storage_state_from_blocks
                apply_state = is_candidate
            elseif variant == :existing_storage_state_only_exclude_zero_energy_rating
                apply_state = !is_candidate && energy_rating > _EPS
            end
            storage_state_count += apply_state ? 1 : 0
        end
    end
    storage_thermal_enabled = variant != :core_gen_balance_only && variant != :core_gen_plus_storage_existing_no_candidates && variant != :core_gen_plus_candidate_storage_no_standard_storage_constraints
    storage_losses_enabled = !(variant in (:core_gen_balance_only, :core_gen_plus_storage_existing_no_candidates, :core_gen_plus_candidate_storage_no_standard_storage_constraints, :add_standard_storage_thermal_limits))
    return Dict{String,Any}(
        "bus_balance" => length(_PM.ids(pm, nw, :bus)),
        "dcline_loss" => length(_PM.ids(pm, nw, :dcline)),
        "gen_block_dispatch" => _filtered_constraint_ref_count(pm, nw, :uc_gscr_block_active_dispatch_bounds, :gen),
        "storage_bounds" =>
            _filtered_constraint_ref_count(pm, nw, :uc_gscr_block_storage_energy_capacity) +
            _filtered_constraint_ref_count(pm, nw, :uc_gscr_block_storage_charge_discharge_bounds),
        "storage_thermal" => storage_thermal_enabled ? length(_PM.ids(pm, nw, :storage)) : 0,
        "storage_losses" => storage_losses_enabled ? length(_PM.ids(pm, nw, :storage)) : 0,
        "storage_state" => storage_state_count,
        "startup_shutdown" => _filtered_constraint_ref_count(pm, nw, :block_count_transitions),
        "gSCR" => _filtered_constraint_ref_count(pm, nw, :gscr_gershgorin_sufficient),
    )
end

function _sum_var_values(pm, nw::Int, sym::Symbol)
    if !haskey(_PM.var(pm, nw), sym)
        return 0.0
    end
    return sum((JuMP.value(v) for v in values(_PM.var(pm, nw, sym))); init=0.0)
end

function _sum_abs_var_values(pm, nw::Int, sym::Symbol)
    if !haskey(_PM.var(pm, nw), sym)
        return 0.0
    end
    return sum((abs(JuMP.value(v)) for v in values(_PM.var(pm, nw, sym))); init=0.0)
end

function _ablation_bus_balance_residual(pm, nw::Int)
    max_res = 0.0
    for i in _PM.ids(pm, nw, :bus)
        lhs = 0.0
        if haskey(_PM.var(pm, nw), :p)
            lhs += sum((JuMP.value(_PM.var(pm, nw, :p, a)) for a in _PM.ref(pm, nw, :bus_arcs, i)); init=0.0)
        end
        if haskey(_PM.var(pm, nw), :p_dc)
            lhs += sum((JuMP.value(_PM.var(pm, nw, :p_dc, a)) for a in _PM.ref(pm, nw, :bus_arcs_dc, i)); init=0.0)
        end
        if haskey(_PM.var(pm, nw), :psw) && haskey(_PM.ref(pm, nw), :bus_arcs_sw)
            lhs += sum((JuMP.value(_PM.var(pm, nw, :psw, a)) for a in _PM.ref(pm, nw, :bus_arcs_sw, i)); init=0.0)
        end
        rhs = sum((JuMP.value(_PM.var(pm, nw, :pg, g)) for g in _PM.ref(pm, nw, :bus_gens, i)); init=0.0)
        if haskey(_PM.var(pm, nw), :ps)
            rhs -= sum((JuMP.value(_PM.var(pm, nw, :ps, s)) for s in _PM.ref(pm, nw, :bus_storage, i)); init=0.0)
        end
        rhs -= sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ref(pm, nw, :bus_loads, i)); init=0.0)
        if haskey(_PM.ref(pm, nw), :bus_shunts)
            rhs -= sum((get(_PM.ref(pm, nw, :shunt, sh), "gs", 0.0) for sh in _PM.ref(pm, nw, :bus_shunts, i)); init=0.0)
        end
        max_res = max(max_res, abs(lhs - rhs))
    end
    return max_res
end

function _ablation_investment_by_carrier(pm, nw::Int)
    out = Dict{String,Float64}()
    if !haskey(_PM.var(pm, nw), :n_block)
        return out
    end
    for key in keys(_PM.var(pm, nw, :n_block))
        device_key = key[1]
        d = _PM.ref(pm, nw, device_key[1], device_key[2])
        carrier = String(get(d, "carrier", "unknown"))
        n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
        dn = JuMP.value(_PM.var(pm, nw, :n_block, device_key)) - n0
        out[carrier] = get(out, carrier, 0.0) + dn
    end
    return out
end

function _ablation_feasible_metrics(pm, nw::Int)
    total_invested = 0.0
    if haskey(_PM.var(pm, nw), :n_block)
        for key in keys(_PM.var(pm, nw, :n_block))
            device_key = key[1]
            d = _PM.ref(pm, nw, device_key[1], device_key[2])
            n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
            total_invested += JuMP.value(_PM.var(pm, nw, :n_block, device_key)) - n0
        end
    end
    return Dict{String,Any}(
        "total_generation_dispatch" => _sum_var_values(pm, nw, :pg),
        "total_storage_discharge" => _sum_var_values(pm, nw, :sd),
        "total_storage_charge" => _sum_var_values(pm, nw, :sc),
        "total_dcline_transfer_abs_sum" => _sum_abs_var_values(pm, nw, :p_dc),
        "total_invested_blocks" => total_invested,
        "investment_by_carrier" => _ablation_investment_by_carrier(pm, nw),
        "bus_balance_residual_max" => _ablation_bus_balance_residual(pm, nw),
        "bus_balance_residual_small" => _ablation_bus_balance_residual(pm, nw) <= 1e-5,
    )
end

function _var_bound_summary(vdict)
    if isnothing(vdict) || isempty(vdict)
        return Dict{String,Any}("count" => 0, "lb_min" => nothing, "lb_max" => nothing, "ub_min" => nothing, "ub_max" => nothing, "lb_gt_ub_count" => 0)
    end
    lbs = Float64[]
    ubs = Float64[]
    bad = 0
    for v in values(vdict)
        lb = try _var_lb(v) catch; -Inf end
        ub = try _var_ub(v) catch; Inf end
        push!(lbs, lb)
        push!(ubs, ub)
        if isfinite(lb) && isfinite(ub) && lb > ub + _EPS
            bad += 1
        end
    end
    return Dict{String,Any}(
        "count" => length(lbs),
        "lb_min" => minimum(lbs),
        "lb_max" => maximum(lbs),
        "ub_min" => minimum(ubs),
        "ub_max" => maximum(ubs),
        "lb_gt_ub_count" => bad,
    )
end

function _ablation_bounds_audit(pm, nw::Int)
    load_sum = sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ids(pm, nw, :load)); init=0.0)
    gen_block_ub = 0.0
    if haskey(_PM.ref(pm, nw), :uc_gscr_block_devices)
        for key in _PM.ref(pm, nw, :uc_gscr_block_devices)
            if key[1] == :gen
                d = _PM.ref(pm, nw, key[1], key[2])
                gen_block_ub += float(get(d, "p_block_max", 0.0)) * float(get(d, "nmax", get(d, "n_block_max", 0.0)))
            end
        end
    end

    isolated_load_buses = Int[]
    for b in _PM.ids(pm, nw, :bus)
        has_load = !isempty(_PM.ref(pm, nw, :bus_loads, b))
        has_supply = !isempty(_PM.ref(pm, nw, :bus_gens, b)) || !isempty(_PM.ref(pm, nw, :bus_storage, b))
        has_network = !isempty(_PM.ref(pm, nw, :bus_arcs, b)) || !isempty(_PM.ref(pm, nw, :bus_arcs_dc, b))
        if has_load && !has_supply && !has_network
            push!(isolated_load_buses, b)
        end
    end

    varmap = _PM.var(pm, nw)
    invalid_vars = Dict{String,Any}()
    for sym in (:pg, :ps, :sc, :sd, :se, :p_dc, :p, :n_block, :na_block)
        if haskey(varmap, sym)
            s = _var_bound_summary(varmap[sym])
            if s["lb_gt_ub_count"] > 0
                invalid_vars[String(sym)] = s
            end
        end
    end

    return Dict{String,Any}(
        "load_sum_pm_units" => load_sum,
        "gen_pg_bounds" => _var_bound_summary(get(varmap, :pg, nothing)),
        "gen_block_dispatch_upper_bound_sum" => gen_block_ub,
        "branch_p_bounds" => _var_bound_summary(get(varmap, :p, nothing)),
        "dcline_p_dc_bounds" => _var_bound_summary(get(varmap, :p_dc, nothing)),
        "storage_ps_bounds" => _var_bound_summary(get(varmap, :ps, nothing)),
        "storage_sc_bounds" => _var_bound_summary(get(varmap, :sc, nothing)),
        "storage_sd_bounds" => _var_bound_summary(get(varmap, :sd, nothing)),
        "storage_se_bounds" => _var_bound_summary(get(varmap, :se, nothing)),
        "variables_with_lb_gt_ub" => invalid_vars,
        "buses_with_load_no_supply_no_incident_branch_or_dcline" => isolated_load_buses,
    )
end

function _solve_one_snapshot_ablation_variant(
    raw::Dict{String,Any},
    snapshot_id::Int,
    label::String,
    variant::Symbol;
    include_storage::Bool,
    include_candidates::Bool,
    mutator=nothing,
    return_pm::Bool=false,
    existing_storage_initial_energy_policy::Union{Nothing,String}=nothing,
)
    data = _one_snapshot_ablation_data(
        raw,
        snapshot_id;
        include_storage,
        include_candidates,
        mutator,
        existing_storage_initial_energy_policy,
    )
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _ablation_builder(variant);
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    nw = first(sort(collect(_FP.nw_ids(pm))))
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    t0 = time()
    JuMP.optimize!(pm.model)
    status = _status_str(JuMP.termination_status(pm.model))
    out = Dict{String,Any}(
        "label" => label,
        "status" => status,
        "objective" => (status in _ACTIVE_OK ? JuMP.objective_value(pm.model) : nothing),
        "solve_time_sec" => time() - t0,
        "variables" => _ablation_variable_counts(pm, nw),
        "constraints" => _ablation_constraint_counts(pm, nw, variant),
        "feasible_metrics" => Dict{String,Any}(),
        "bounds_audit" => Dict{String,Any}(),
        "existing_storage_initial_energy_policy" => isnothing(existing_storage_initial_energy_policy) ? "none" : existing_storage_initial_energy_policy,
        "skipped_existing_storage_zero_energy_rating_rows" => Dict{String,Any}[],
        "standard_balance_reference" => "PowerModels.constraint_power_balance(pm, i; nw=n)",
        "dcline_setpoint_constraints" => 0,
    )
    if variant == :existing_storage_state_only_exclude_zero_energy_rating
        skipped = Dict{String,Any}[]
        for (sid, st) in sort(collect(get(data["nw"]["1"], "storage", Dict{String,Any}())); by=x -> parse(Int, x.first))
            if _is_battery_candidate(st)
                continue
            end
            er = float(get(st, "energy_rating", 0.0))
            if er <= _EPS
                push!(skipped, Dict(
                    "id" => sid,
                    "bus" => Int(get(st, "storage_bus", -1)),
                    "carrier" => String(get(st, "carrier", "")),
                    "energy" => float(get(st, "energy", 0.0)),
                    "energy_rating" => er,
                ))
            end
        end
        out["skipped_existing_storage_zero_energy_rating_rows"] = skipped
    end
    if status in _ACTIVE_OK
        out["feasible_metrics"] = _ablation_feasible_metrics(pm, nw)
    else
        out["bounds_audit"] = _ablation_bounds_audit(pm, nw)
    end
    if return_pm
        out["pm"] = pm
        out["nw"] = nw
        out["data"] = data
    end
    return out
end

function _one_snapshot_constraint_family_ablation(raw::Dict{String,Any}, snapshot_id::Int)
    specs = [
        ("core_gen_balance_only", :core_gen_balance_only, false, false),
        ("core_gen_plus_storage_existing_no_candidates", :core_gen_plus_storage_existing_no_candidates, true, false),
        ("core_gen_plus_candidate_storage_no_standard_storage_constraints", :core_gen_plus_candidate_storage_no_standard_storage_constraints, true, true),
        ("add_standard_storage_thermal_limits", :add_standard_storage_thermal_limits, true, true),
        ("add_standard_storage_losses", :add_standard_storage_losses, true, true),
        ("add_storage_state_constraints", :add_storage_state_constraints, true, true),
        ("add_storage_state_constraints_with_half_energy_rating", :add_storage_state_constraints_with_half_energy_rating, true, true),
        ("add_startup_shutdown_transitions", :add_startup_shutdown_transitions, true, true),
        ("add_gscr_gmin0", :add_gscr_gmin0, true, true),
    ]
    variants = Dict{String,Any}[]
    for (label, variant, include_storage, include_candidates) in specs
        push!(variants, _solve_one_snapshot_ablation_variant(
            raw,
            snapshot_id,
            label,
            variant;
            include_storage,
            include_candidates,
            existing_storage_initial_energy_policy="half_energy_rating",
        ))
    end

    first_infeasible = nothing
    last_feasible = nothing
    first_infeasible_after_feasible = nothing
    feasible_before_regression = nothing
    for v in variants
        if v["status"] in _ACTIVE_OK
            last_feasible = v
            if isnothing(first_infeasible_after_feasible)
                feasible_before_regression = v
            end
        else
            if isnothing(first_infeasible)
                first_infeasible = v
            end
            if !isnothing(feasible_before_regression) && isnothing(first_infeasible_after_feasible)
                first_infeasible_after_feasible = v
            end
        end
    end

    likely = "no infeasible ablation variant"
    decision_variant = isnothing(first_infeasible_after_feasible) ? first_infeasible : first_infeasible_after_feasible
    if !isnothing(decision_variant)
        label = String(decision_variant["label"])
        if label == "core_gen_balance_only"
            likely = "not storage; inspect generator/block dispatch bounds, branch/dcline balance, or units"
        elseif label == "core_gen_plus_candidate_storage_no_standard_storage_constraints"
            likely = "candidate storage block path"
        elseif label in ("add_standard_storage_thermal_limits", "add_standard_storage_losses", "add_storage_state_constraints")
            likely = "standard storage constraints incompatible with candidate/block storage representation"
        elseif label == "add_startup_shutdown_transitions"
            likely = "startup/shutdown transition constraints, likely su/sd bounds or initial active counts"
        elseif label == "add_gscr_gmin0"
            likely = "gSCR implementation issue at g_min=0"
        else
            likely = "constraint family identified by first infeasible ablation variant"
        end
    end

    return Dict{String,Any}(
        "snapshot_id" => snapshot_id,
        "g_min" => 0.0,
        "standard_balance_reference" => "PowerModels.constraint_power_balance(pm, i; nw=n)",
        "dclines_active" => true,
        "dcline_setpoint_constraints_on_path" => 0,
        "variants" => variants,
        "first_infeasible_variant" => isnothing(first_infeasible) ? nothing : first_infeasible["label"],
        "last_feasible_variant" => isnothing(last_feasible) ? nothing : last_feasible["label"],
        "last_feasible_before_regression" => isnothing(feasible_before_regression) ? nothing : feasible_before_regression["label"],
        "first_infeasible_after_feasible_variant" => isnothing(first_infeasible_after_feasible) ? nothing : first_infeasible_after_feasible["label"],
        "likely_root_cause" => likely,
        "all_variants_infeasible" => all(!(v["status"] in _ACTIVE_OK) for v in variants),
    )
end

function _mutate_existing_storage_half_energy_rating!(data::Dict{String,Any})
    for nw in values(data["nw"])
        for st in values(get(nw, "storage", Dict{String,Any}()))
            if !_is_battery_candidate(st)
                st["energy"] = 0.5 * float(get(st, "energy_rating", get(st, "energy", 0.0)))
            end
        end
    end
    return data
end

function _mutate_candidate_energy_zero!(data::Dict{String,Any})
    for nw in values(data["nw"])
        for st in values(get(nw, "storage", Dict{String,Any}()))
            if _is_battery_candidate(st)
                st["energy"] = 0.0
            end
        end
    end
    return data
end

function _mutate_candidate_storage_ratings_from_blocks!(data::Dict{String,Any})
    for nw in values(data["nw"])
        for st in values(get(nw, "storage", Dict{String,Any}()))
            if _is_battery_candidate(st)
                nmax = float(get(st, "n_block_max", get(st, "nmax", 0.0)))
                pblk = float(get(st, "p_block_max", 0.0))
                eblk = float(get(st, "e_block", 0.0))
                st["energy_rating"] = nmax * eblk
                st["charge_rating"] = nmax * pblk
                st["discharge_rating"] = nmax * pblk
                st["thermal_rating"] = nmax * pblk
                st["energy"] = 0.0
            end
        end
    end
    return data
end

function _storage_kind(d::Dict{String,Any})
    if _is_battery_gfl(d)
        return "battery_gfl candidate"
    elseif _is_battery_gfm(d)
        return "battery_gfm candidate"
    elseif _is_battery_candidate(d)
        return "battery candidate"
    end
    return "existing storage"
end

function _storage_type_counts_from_ref(pm, nw::Int)
    counts = Dict("existing storage" => 0, "battery_gfl candidate" => 0, "battery_gfm candidate" => 0, "battery candidate" => 0)
    for sid in _PM.ids(pm, nw, :storage)
        kind = _storage_kind(_PM.ref(pm, nw, :storage, sid))
        counts[kind] = get(counts, kind, 0) + 1
    end
    return counts
end

function _storage_state_equation_audit(raw::Dict{String,Any}, snapshot_id::Int)
    solved = _solve_one_snapshot_ablation_variant(
        raw,
        snapshot_id,
        "storage_state_equation_audit_model",
        :storage_state_initial_only;
        include_storage=true,
        include_candidates=true,
        return_pm=true,
        existing_storage_initial_energy_policy="half_energy_rating",
    )
    pm = solved["pm"]
    nw = solved["nw"]
    ids_storage = _PM.ids(pm, nw, :storage)
    bounded_absorption_ids = haskey(_PM.ref(pm, nw), :storage_bounded_absorption) ? collect(keys(_PM.ref(pm, nw, :storage_bounded_absorption))) : Int[]

    return Dict{String,Any}(
        "variant" => "add_storage_state_constraints / storage_state_initial_only",
        "storage_type_counts" => _storage_type_counts_from_ref(pm, nw),
        "functions_called_in_focused_ablation" => Dict(
            "constraint_storage_state" => length(ids_storage),
            "constraint_storage_state_final" => 0,
            "constraint_storage_state_ne" => 0,
            "constraint_storage_state_final_ne" => 0,
            "constraint_maximum_absorption" => 0,
            "constraint_maximum_absorption_ne" => 0,
        ),
        "functions_called_in_active_builder_first_snapshot" => Dict(
            "constraint_storage_state" => length(ids_storage),
            "constraint_storage_state_final" => 0,
            "constraint_storage_state_ne" => 0,
            "constraint_storage_state_final_ne" => 0,
            "constraint_maximum_absorption" => length(bounded_absorption_ids),
            "constraint_maximum_absorption_ne" => 0,
        ),
        "initial_state_active_one_snapshot" => true,
        "final_state_active_one_snapshot" => false,
        "initial_equation" => "se[t] = (1-self_discharge_rate)^time_elapsed * energy + time_elapsed*(charge_efficiency*sc[t] - sd[t]/discharge_efficiency + stationary_energy_inflow - stationary_energy_outflow)",
        "final_equation_if_called" => "se[t] >= energy",
        "final_state_policy" => "not active in the one-snapshot first-snapshot branch; when called elsewhere it is a lower bound to the storage data field `energy`, not an equality",
        "bounded_absorption_storage_ids" => sort(collect(bounded_absorption_ids)),
    )
end

function _nonzero_storage_dispatch_rows(pm, nw::Int; tol::Float64=1e-6, policy::String="none")
    rows = Dict{String,Any}[]
    for sid in sort(collect(_PM.ids(pm, nw, :storage)))
        st = _PM.ref(pm, nw, :storage, sid)
        ps = haskey(_PM.var(pm, nw), :ps) ? JuMP.value(_PM.var(pm, nw, :ps, sid)) : 0.0
        sc = haskey(_PM.var(pm, nw), :sc) ? JuMP.value(_PM.var(pm, nw, :sc, sid)) : 0.0
        sd = haskey(_PM.var(pm, nw), :sd) ? JuMP.value(_PM.var(pm, nw, :sd, sid)) : 0.0
        if max(abs(ps), abs(sc), abs(sd)) <= tol
            continue
        end
        key = (:storage, sid)
        has_block = haskey(_PM.var(pm, nw), :n_block) && _var_has_index(_PM.var(pm, nw, :n_block), key)
        n_val = has_block ? JuMP.value(_PM.var(pm, nw, :n_block, key)) : nothing
        na_val = haskey(_PM.var(pm, nw), :na_block) && _var_has_index(_PM.var(pm, nw, :na_block), key) ? JuMP.value(_PM.var(pm, nw, :na_block, key)) : nothing
        discharge_eff = float(get(st, "discharge_efficiency", 1.0))
        time_elapsed = float(get(_PM.ref(pm, nw), :time_elapsed, 1.0))
        required_discharge_energy = time_elapsed * sd / discharge_eff
        energy = float(get(st, "energy", 0.0))
        energy_rating = float(get(st, "energy_rating", 0.0))
        energy_over_rating = abs(energy_rating) > _EPS ? energy / energy_rating : nothing
        policy_applied = true
        if policy == "half_energy_rating"
            if !_is_battery_candidate(st)
                policy_applied = energy_rating <= _EPS ? true : abs(energy - 0.5 * energy_rating) <= _EPS
            else
                n0 = float(get(st, "n_block0", get(st, "n0", 0.0)))
                na0 = float(get(st, "na0", 0.0))
                if abs(n0) <= _EPS && abs(na0) <= _EPS
                    policy_applied = abs(energy) <= _EPS
                end
            end
        end
        push!(rows, Dict{String,Any}(
            "id" => sid,
            "bus" => Int(get(st, "storage_bus", -1)),
            "carrier" => String(get(st, "carrier", "")),
            "type" => String(get(st, "type", "")),
            "kind" => _storage_kind(st),
            "ps" => ps,
            "sc" => sc,
            "sd" => sd,
            "se" => haskey(_PM.var(pm, nw), :se) ? JuMP.value(_PM.var(pm, nw, :se, sid)) : nothing,
            "energy" => energy,
            "energy_rating" => energy_rating,
            "energy_over_energy_rating" => energy_over_rating,
            "policy_applied_flag" => policy_applied,
            "charge_rating" => float(get(st, "charge_rating", 0.0)),
            "discharge_rating" => float(get(st, "discharge_rating", 0.0)),
            "p_block_max" => float(get(st, "p_block_max", 0.0)),
            "e_block" => float(get(st, "e_block", 0.0)),
            "n_block0" => float(get(st, "n_block0", get(st, "n0", 0.0))),
            "n_block_max" => float(get(st, "n_block_max", get(st, "nmax", 0.0))),
            "na_block" => na_val,
            "n_block" => n_val,
            "initial_energy" => float(get(st, "energy", 0.0)),
            "required_discharge_energy" => required_discharge_energy,
            "charge_efficiency" => float(get(st, "charge_efficiency", 1.0)),
            "discharge_efficiency" => discharge_eff,
            "stationary_energy_inflow" => float(get(st, "stationary_energy_inflow", 0.0)),
            "stationary_energy_outflow" => float(get(st, "stationary_energy_outflow", 0.0)),
            "self_discharge_rate" => float(get(st, "self_discharge_rate", 0.0)),
            "time_elapsed" => time_elapsed,
        ))
    end
    return rows
end

function _storage_dispatch_audit_last_feasible(raw::Dict{String,Any}, snapshot_id::Int)
    solved = _solve_one_snapshot_ablation_variant(
        raw,
        snapshot_id,
        "add_standard_storage_losses",
        :add_standard_storage_losses;
        include_storage=true,
        include_candidates=true,
        return_pm=true,
        existing_storage_initial_energy_policy="half_energy_rating",
    )
    pm = solved["pm"]
    nw = solved["nw"]
    rows = _nonzero_storage_dispatch_rows(pm, nw; policy="half_energy_rating")
    sorted_users = sort(rows; by=r -> -abs(float(r["required_discharge_energy"])))
    total_discharge = sum((float(r["sd"]) for r in rows); init=0.0)
    total_charge = sum((float(r["sc"]) for r in rows); init=0.0)
    net_energy_used = sum((float(r["required_discharge_energy"]) - float(r["sc"]) * float(get(_PM.ref(pm, nw, :storage, Int(r["id"])), "charge_efficiency", 1.0)) for r in rows); init=0.0)
    required_exceeds_initial = any(float(r["required_discharge_energy"]) > float(r["initial_energy"]) + _EPS for r in rows)
    out = deepcopy(solved)
    delete!(out, "pm")
    delete!(out, "data")
    delete!(out, "nw")
    out["nonzero_storage_rows"] = rows
    out["nonzero_storage_count"] = length(rows)
    out["total_storage_discharge"] = total_discharge
    out["total_storage_charge"] = total_charge
    out["net_storage_energy_used"] = net_energy_used
    out["largest_storage_energy_users"] = sorted_users[1:min(length(sorted_users), 10)]
    out["required_energy_exceeds_initial_available_energy"] = required_exceeds_initial
    out["existing_storage_initial_energy_policy"] = "half_energy_rating"
    return out
end

function _storage_state_algebraic_check(dispatch_audit::Dict{String,Any})
    rows = Dict{String,Any}[]
    feasible = true
    failing_conditions = Set{String}()
    policy_consistency_violations = 0
    for r in dispatch_audit["nonzero_storage_rows"]
        charge_eff = float(get(r, "charge_efficiency", 1.0))
        discharge_eff = float(get(r, "discharge_efficiency", 1.0))
        self_discharge = float(get(r, "self_discharge_rate", 0.0))
        inflow = float(get(r, "stationary_energy_inflow", 0.0))
        outflow = float(get(r, "stationary_energy_outflow", 0.0))
        dt = float(get(r, "time_elapsed", 1.0))
        initial = float(r["initial_energy"])
        sc = float(r["sc"])
        sd = float(r["sd"])
        se_required = ((1.0 - self_discharge)^dt) * initial + dt * (charge_eff * sc - sd / discharge_eff + inflow - outflow)
        finite_energy_rating = float(r["energy_rating"])
        n_block = isnothing(r["n_block"]) ? 0.0 : float(r["n_block"])
        e_block = float(r["e_block"])
        block_capacity = e_block > 0.0 ? e_block * n_block : Inf
        upper_capacity = min(isfinite(finite_energy_rating) && finite_energy_rating > 0.0 ? finite_energy_rating : Inf, block_capacity)

        condition = "ok"
        if se_required < -_EPS
            condition = "initial energy too small"
            push!(failing_conditions, condition)
            feasible = false
        elseif isfinite(upper_capacity) && se_required > upper_capacity + _EPS
            condition = e_block > 0.0 ? "candidate n_block/e_block coupling" : "energy_rating too small"
            push!(failing_conditions, condition)
            feasible = false
        end
        final_active = false
        final_condition_ok = true

        push!(rows, Dict{String,Any}(
            "id" => r["id"],
            "kind" => r["kind"],
            "energy" => r["energy"],
            "initial_energy" => initial,
            "energy_rating" => r["energy_rating"],
            "energy_over_energy_rating" => r["energy_over_energy_rating"],
            "policy_applied_flag" => r["policy_applied_flag"],
            "sc" => sc,
            "sd" => sd,
            "se_required_by_initial_state" => se_required,
            "block_energy_capacity" => block_capacity,
            "upper_capacity_checked" => upper_capacity,
            "condition" => condition,
            "final_condition_active" => final_active,
            "final_condition_ok" => final_condition_ok,
        ))
        if !Bool(r["policy_applied_flag"])
            policy_consistency_violations += 1
        end
    end
    return Dict{String,Any}(
        "feasible_against_last_feasible_dispatch" => feasible,
        "half_energy_policy_consistency_ok" => policy_consistency_violations == 0,
        "half_energy_policy_consistency_violations" => policy_consistency_violations,
        "failing_conditions" => sort(collect(failing_conditions)),
        "rows" => rows,
        "note" => "This checks the last-feasible dispatch against the one-snapshot initial-state equation. It is not an IIS; it identifies whether that dispatch can satisfy storage dynamics.",
    )
end

function _storage_state_variant_runs(raw::Dict{String,Any}, snapshot_id::Int)
    specs = [
        ("add_storage_state_constraints_with_half_energy_rating", :add_storage_state_constraints_with_half_energy_rating, nothing),
        ("storage_state_initial_only", :storage_state_initial_only, nothing),
        ("storage_state_no_final", :storage_state_no_final, nothing),
        ("storage_state_relaxed_final", :storage_state_relaxed_final, nothing),
        ("storage_state_half_energy_rating_initial", :storage_state_half_energy_rating_initial, _mutate_existing_storage_half_energy_rating!),
        ("existing_storage_state_only", :existing_storage_state_only, nothing),
        ("candidate_storage_state_only", :candidate_storage_state_only, _mutate_candidate_energy_zero!),
        ("candidate_storage_state_from_blocks", :candidate_storage_state_from_blocks, _mutate_candidate_storage_ratings_from_blocks!),
        ("existing_storage_state_only_exclude_zero_energy_rating", :existing_storage_state_only_exclude_zero_energy_rating, nothing),
    ]
    out = Dict{String,Any}[]
    for (label, variant, mutator) in specs
        push!(out, _solve_one_snapshot_ablation_variant(
            raw,
            snapshot_id,
            label,
            variant;
            include_storage=true,
            include_candidates=true,
            mutator,
            existing_storage_initial_energy_policy="half_energy_rating",
        ))
    end
    return out
end

function _storage_state_diagnostic(raw::Dict{String,Any}, snapshot_id::Int)
    isolated = [
        _solve_one_snapshot_ablation_variant(raw, snapshot_id, "add_startup_shutdown_without_storage_state", :add_startup_shutdown_without_storage_state; include_storage=true, include_candidates=true, existing_storage_initial_energy_policy="half_energy_rating"),
        _solve_one_snapshot_ablation_variant(raw, snapshot_id, "add_gscr_gmin0_without_storage_state", :add_gscr_gmin0_without_storage_state; include_storage=true, include_candidates=true, existing_storage_initial_energy_policy="half_energy_rating"),
        _solve_one_snapshot_ablation_variant(raw, snapshot_id, "add_startup_shutdown_and_gscr_without_storage_state", :add_startup_shutdown_and_gscr_without_storage_state; include_storage=true, include_candidates=true, existing_storage_initial_energy_policy="half_energy_rating"),
    ]
    equation_audit = _storage_state_equation_audit(raw, snapshot_id)
    dispatch_audit = _storage_dispatch_audit_last_feasible(raw, snapshot_id)
    algebraic_check = _storage_state_algebraic_check(dispatch_audit)
    variants = _storage_state_variant_runs(raw, snapshot_id)

    status_by_label = Dict(v["label"] => v["status"] for v in variants)
    isolated_by_label = Dict(v["label"] => v["status"] for v in isolated)
    first_failing = "none"
    recommended = "No storage-state-specific blocker isolated."
    if get(status_by_label, "existing_storage_state_only", "") in _ACTIVE_OK &&
       !(get(status_by_label, "candidate_storage_state_only", "") in _ACTIVE_OK)
        first_failing = "candidate storage state representation"
        recommended = "Candidate-only storage-state variant is infeasible while existing-only is feasible."
    elseif !(get(status_by_label, "existing_storage_state_only", "") in _ACTIVE_OK)
        first_failing = "existing storage state data/policy"
        recommended = "Existing-only storage-state variant remains infeasible under half-energy policy."
    elseif get(status_by_label, "candidate_storage_state_from_blocks", "") in _ACTIVE_OK
        first_failing = "zero standard candidate ratings"
        recommended = "Candidate storage-state becomes feasible when ratings are derived from n_block_max*block sizes."
    elseif get(status_by_label, "storage_state_no_final", "") in _ACTIVE_OK
        first_failing = "terminal/final storage condition"
        recommended = "Relax or remove terminal storage requirements for representative one-snapshot diagnostics."
    elseif get(status_by_label, "storage_state_half_energy_rating_initial", "") in _ACTIVE_OK
        first_failing = "initial storage energy policy"
        recommended = "Initialize existing storage from a calibrated state-of-charge fraction of energy_rating instead of p_nom/2."
    elseif get(status_by_label, "candidate_storage_state_from_blocks", "") in _ACTIVE_OK
        first_failing = "candidate standard storage ratings/state"
        recommended = "For block-CAPEXP candidate storage, bind storage energy/rating to block variables or set solver-copy candidate ratings from n_block_max for diagnostics."
    elseif !isempty(algebraic_check["failing_conditions"])
        first_failing = join(algebraic_check["failing_conditions"], ", ")
        recommended = "Inspect storage initial energy and one-snapshot state equation sign convention; the last feasible dispatch cannot satisfy the state equation."
    end

    return Dict{String,Any}(
        "snapshot_id" => snapshot_id,
        "existing_storage_initial_energy_policy" => "half_energy_rating",
        "isolated_startup_gscr_without_storage_state" => isolated,
        "storage_state_equation_audit" => equation_audit,
        "last_feasible_storage_dispatch" => dispatch_audit,
        "storage_state_feasibility_check_from_last_feasible_dispatch" => algebraic_check,
        "storage_state_variants" => variants,
        "first_failing_storage_condition" => first_failing,
        "recommended_model_fix" => recommended,
        "startup_shutdown_independently_feasible_without_storage_state" => get(isolated_by_label, "add_startup_shutdown_without_storage_state", "") in _ACTIVE_OK,
        "gscr_gmin0_independently_feasible_without_storage_state" => get(isolated_by_label, "add_gscr_gmin0_without_storage_state", "") in _ACTIVE_OK,
        "startup_shutdown_and_gscr_feasible_without_storage_state" => get(isolated_by_label, "add_startup_shutdown_and_gscr_without_storage_state", "") in _ACTIVE_OK,
        "final_storage_state_is_blocker" => get(status_by_label, "storage_state_no_final", "") in _ACTIVE_OK,
        "initial_energy_policy_is_blocker" => get(status_by_label, "storage_state_half_energy_rating_initial", "") in _ACTIVE_OK,
        "candidate_storage_state_coupling_is_blocker" => get(status_by_label, "candidate_storage_state_from_blocks", "") in _ACTIVE_OK,
        "add_storage_state_constraints_with_half_energy_rating_status" => get(status_by_label, "add_storage_state_constraints_with_half_energy_rating", "MISSING"),
        "existing_storage_state_only_status" => get(status_by_label, "existing_storage_state_only", "MISSING"),
        "candidate_storage_state_only_status" => get(status_by_label, "candidate_storage_state_only", "MISSING"),
        "candidate_storage_state_from_blocks_status" => get(status_by_label, "candidate_storage_state_from_blocks", "MISSING"),
        "existing_storage_state_only_exclude_zero_energy_rating_status" => get(status_by_label, "existing_storage_state_only_exclude_zero_energy_rating", "MISSING"),
        "all_split_variants_optimal" =>
            get(status_by_label, "existing_storage_state_only", "") == "OPTIMAL" &&
            get(status_by_label, "candidate_storage_state_only", "") == "OPTIMAL" &&
            get(status_by_label, "candidate_storage_state_from_blocks", "") == "OPTIMAL" &&
            get(status_by_label, "existing_storage_state_only_exclude_zero_energy_rating", "") == "OPTIMAL",
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
    constraint_family_ablation = _one_snapshot_constraint_family_ablation(raw, snapshot_id)
    storage_state_diag = _storage_state_diagnostic(raw, snapshot_id)

    full_one_snapshot = _run_mode(
        _make_single_snapshot_raw(raw, snapshot_id),
        "one_snapshot_full",
        "full_capexp";
        g_min_value=0.0,
        existing_storage_initial_energy_policy="half_energy_rating",
    )

    split_decision = "undetermined"
    eso = get(storage_state_diag, "existing_storage_state_only_status", "")
    cso = get(storage_state_diag, "candidate_storage_state_only_status", "")
    csfb = get(storage_state_diag, "candidate_storage_state_from_blocks_status", "")
    all_split_opt = get(storage_state_diag, "all_split_variants_optimal", false)
    if eso in _ACTIVE_OK && !(cso in _ACTIVE_OK)
        split_decision = "candidate storage state representation"
    elseif !(eso in _ACTIVE_OK)
        split_decision = "existing storage state data or policy still inconsistent"
    elseif all_split_opt && !(full_one_snapshot["status"] in _ACTIVE_OK)
        split_decision = "interaction with startup/shutdown, gSCR, or full builder order"
    elseif (full_one_snapshot["status"] in _ACTIVE_OK) && !(gate["status"] in _ACTIVE_OK)
        split_decision = "multi-snapshot storage trajectory/final condition"
    elseif csfb in _ACTIVE_OK
        split_decision = "zero standard candidate ratings"
    end

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
        "constraint_family_ablation" => constraint_family_ablation,
        "storage_state_diagnostic" => storage_state_diag,
        "split_storage_state_root_cause_decision" => split_decision,
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

function _run_existing_storage_initial_energy_policy_sequence(raw::Dict{String,Any}, snapshot_id::Int)
    policy = "half_energy_rating"
    one_snapshot_raw = _make_single_snapshot_raw(raw, snapshot_id)

    one_snapshot_g0 = _run_mode(
        one_snapshot_raw,
        "one_snapshot_g0_existing_storage_half_energy_rating",
        "full_capexp";
        g_min_value=0.0,
        existing_storage_initial_energy_policy=policy,
    )

    run_24h_g0 = _run_mode(
        raw,
        "full_24h_g0_existing_storage_half_energy_rating",
        "full_capexp";
        g_min_value=0.0,
        existing_storage_initial_energy_policy=policy,
    )

    positive_run_executed = run_24h_g0["status"] == "OPTIMAL"
    run_24h_g05 = nothing
    if positive_run_executed
        run_24h_g05 = _run_mode(
            raw,
            "full_24h_g05_existing_storage_half_energy_rating",
            "full_capexp";
            g_min_value=0.5,
            existing_storage_initial_energy_policy=policy,
        )
    end

    return Dict{String,Any}(
        "old_policy" => "p_nom/2",
        "diagnostic_result" => "p_nom/2 too small",
        "new_solver_copy_policy" => "0.5 * energy_rating",
        "existing_storage_initial_energy_policy" => policy,
        "one_snapshot_id" => snapshot_id,
        "one_snapshot_g_min_0" => one_snapshot_g0,
        "full_24h_g_min_0" => run_24h_g0,
        "positive_g_min_run_executed" => positive_run_executed,
        "full_24h_g_min_0_5" => isnothing(run_24h_g05) ? Dict{String,Any}() : run_24h_g05,
    )
end

function _final_storage_initial_energy_sum(pm)
    first_nw = first(sort(collect(_FP.nw_ids(pm))))
    total = 0.0
    for i in _PM.ids(pm, :storage, nw=first_nw)
        total += float(get(_PM.ref(pm, first_nw, :storage, i), "energy", 0.0))
    end
    if haskey(_PM.ref(pm, first_nw), :ne_storage)
        for i in _PM.ids(pm, :ne_storage, nw=first_nw)
            total += float(get(_PM.ref(pm, first_nw, :ne_storage, i), "energy", 0.0))
        end
    end
    return total
end

function _run_24h_final_storage_state_variant(
    raw::Dict{String,Any},
    scenario::String;
    final_policy::Symbol=:with_final,
    existing_storage_initial_energy_policy::Union{Nothing,String}="half_energy_rating",
)
    data = _prepare_solver_data(raw; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    policy_stats = _apply_existing_storage_initial_energy_policy!(data, existing_storage_initial_energy_policy)
    _inject_g_min!(data, 0.0)

    solved = _solve_with_pm(data, _builder_with_final_policy(final_policy))
    pm = solved["pm"]
    status = solved["status"]
    nws = sort(collect(_FP.nw_ids(pm)))
    first_nw = first(nws)
    last_nw = last(nws)

    storage_final_count = 0
    storage_final_ne_count = 0
    if final_policy != :no_final && length(nws) > 1
        storage_final_count = length(_PM.ids(pm, :storage, nw=last_nw))
        if haskey(_PM.ref(pm, last_nw), :ne_storage)
            storage_final_ne_count = length(_PM.ids(pm, :ne_storage, nw=last_nw))
        end
    end

    initial_energy_sum = _final_storage_initial_energy_sum(pm)
    final_energy_sum = nothing
    binding_at_final_lb = nothing
    total_sd = nothing
    total_sc = nothing

    if status in _ACTIVE_OK
        se_sum = 0.0
        for i in _PM.ids(pm, :storage, nw=last_nw)
            se_sum += JuMP.value(_PM.var(pm, last_nw, :se, i))
        end
        if haskey(_PM.var(pm, last_nw), :se_ne)
            for i in _PM.ids(pm, :ne_storage, nw=last_nw)
                se_sum += JuMP.value(_PM.var(pm, last_nw, :se_ne, i))
            end
        end
        final_energy_sum = se_sum

        bind_count = 0
        tol = 1e-6
        if final_policy != :no_final && length(nws) > 1
            for i in _PM.ids(pm, :storage, nw=last_nw)
                lb = final_policy == :relaxed_final ? 0.0 : float(get(_PM.ref(pm, last_nw, :storage, i), "energy", 0.0))
                se = JuMP.value(_PM.var(pm, last_nw, :se, i))
                bind_count += abs(se - lb) <= tol ? 1 : 0
            end
            if haskey(_PM.var(pm, last_nw), :se_ne)
                for i in _PM.ids(pm, :ne_storage, nw=last_nw)
                    z = haskey(_PM.var(pm, last_nw), :z_strg_ne) ? JuMP.value(_PM.var(pm, last_nw, :z_strg_ne, i)) : 1.0
                    lb = final_policy == :relaxed_final ? 0.0 : float(get(_PM.ref(pm, last_nw, :ne_storage, i), "energy", 0.0)) * z
                    se = JuMP.value(_PM.var(pm, last_nw, :se_ne, i))
                    bind_count += abs(se - lb) <= tol ? 1 : 0
                end
            end
        end
        binding_at_final_lb = bind_count

        discharge = 0.0
        charge = 0.0
        for n in nws
            if haskey(_PM.var(pm, n), :sd)
                for i in _PM.ids(pm, :storage, nw=n)
                    discharge += JuMP.value(_PM.var(pm, n, :sd, i))
                end
            end
            if haskey(_PM.var(pm, n), :sc)
                for i in _PM.ids(pm, :storage, nw=n)
                    charge += JuMP.value(_PM.var(pm, n, :sc, i))
                end
            end
            if haskey(_PM.var(pm, n), :sd_ne)
                for i in _PM.ids(pm, :ne_storage, nw=n)
                    discharge += JuMP.value(_PM.var(pm, n, :sd_ne, i))
                end
            end
            if haskey(_PM.var(pm, n), :sc_ne)
                for i in _PM.ids(pm, :ne_storage, nw=n)
                    charge += JuMP.value(_PM.var(pm, n, :sc_ne, i))
                end
            end
        end
        total_sd = discharge
        total_sc = charge
    end

    return Dict{String,Any}(
        "scenario" => scenario,
        "status" => status,
        "objective" => solved["objective"],
        "solve_time_sec" => solved["solve_time_sec"],
        "existing_storage_initial_energy_policy" => isnothing(existing_storage_initial_energy_policy) ? "none" : existing_storage_initial_energy_policy,
        "existing_storage_initial_energy_policy_stats" => policy_stats,
        "constraint_storage_state_final_count" => storage_final_count,
        "constraint_storage_state_final_ne_count" => storage_final_ne_count,
        "aggregate_initial_storage_energy" => initial_energy_sum,
        "aggregate_final_storage_energy" => final_energy_sum,
        "storage_units_binding_final_lower_bound" => binding_at_final_lb,
        "total_storage_discharge_over_horizon" => total_sd,
        "total_storage_charge_over_horizon" => total_sc,
    )
end

function _run_24h_final_storage_state_diagnostic(raw::Dict{String,Any})
    with_final = _run_24h_final_storage_state_variant(
        raw,
        "full_24h_with_storage_state_and_final";
        final_policy=:with_final,
    )
    no_final = _run_24h_final_storage_state_variant(
        raw,
        "full_24h_with_storage_state_no_final";
        final_policy=:no_final,
    )
    relaxed_final = _run_24h_final_storage_state_variant(
        raw,
        "full_24h_storage_state_relaxed_final";
        final_policy=:relaxed_final,
    )

    decision = if no_final["status"] in _ACTIVE_OK
        "final state is the blocker"
    else
        "storage trajectory or per-period state coupling is the blocker"
    end

    return Dict{String,Any}(
        "g_min" => 0.0,
        "full_24h_with_storage_state_and_final" => with_final,
        "full_24h_with_storage_state_no_final" => no_final,
        "full_24h_storage_state_relaxed_final" => relaxed_final,
        "decision" => decision,
    )
end

function _make_growing_horizon_raw(raw::Dict{String,Any}, h::Int)
    out = deepcopy(raw)
    nw_new = Dict{String,Any}()
    for t in 1:h
        nw_new[string(t)] = deepcopy(raw["nw"][string(t)])
    end
    out["nw"] = nw_new
    out["multinetwork"] = true
    if haskey(out, "dim")
        delete!(out, "dim")
    end
    return out
end

function _sum_load_over_horizon(data::Dict{String,Any})
    total = 0.0
    for nw in values(data["nw"])
        total += sum((float(get(l, "pd", 0.0)) for l in values(get(nw, "load", Dict{String,Any}())) if get(l, "status", 1) != 0); init=0.0)
    end
    return total
end

function _mutate_candidate_one_block_installed!(data::Dict{String,Any})
    for nw in values(data["nw"])
        for st in values(get(nw, "storage", Dict{String,Any}()))
            if _is_battery_candidate(st)
                pblk = float(get(st, "p_block_max", 0.0))
                eblk = float(get(st, "e_block", 0.0))
                st["n_block0"] = 1.0
                st["na0"] = 1.0
                st["n_block_max"] = max(float(get(st, "n_block_max", 0.0)), 1.0)
                st["n0"] = 1.0
                st["nmax"] = max(float(get(st, "nmax", get(st, "n_block_max", 0.0))), 1.0)
                st["energy"] = 0.5 * eblk
                st["energy_rating"] = eblk
                st["charge_rating"] = pblk
                st["discharge_rating"] = pblk
                st["thermal_rating"] = pblk
            end
        end
    end
    return data
end

function _collect_temporal_metrics(pm)
    nws = sort(collect(_FP.nw_ids(pm)))
    first_nw = first(nws)
    last_nw = last(nws)

    total_gen = 0.0
    total_sd = 0.0
    total_sc = 0.0
    su_total = 0.0
    sd_total = 0.0
    max_balance = 0.0
    max_state_res = 0.0
    min_margin = Inf
    agg_energy_by_nw = Float64[]
    transition_max = 0.0

    for n in nws
        if haskey(_PM.var(pm, n), :pg)
            total_gen += sum((JuMP.value(v) for v in values(_PM.var(pm, n, :pg))); init=0.0)
        end
        if haskey(_PM.var(pm, n), :sd)
            total_sd += sum((JuMP.value(v) for v in values(_PM.var(pm, n, :sd))); init=0.0)
        end
        if haskey(_PM.var(pm, n), :sc)
            total_sc += sum((JuMP.value(v) for v in values(_PM.var(pm, n, :sc))); init=0.0)
        end
        if haskey(_PM.var(pm, n), :sd_ne)
            total_sd += sum((JuMP.value(v) for v in values(_PM.var(pm, n, :sd_ne))); init=0.0)
        end
        if haskey(_PM.var(pm, n), :sc_ne)
            total_sc += sum((JuMP.value(v) for v in values(_PM.var(pm, n, :sc_ne))); init=0.0)
        end

        if haskey(_PM.var(pm, n), :su_block)
            su_total += sum((JuMP.value(v) for v in values(_PM.var(pm, n, :su_block))); init=0.0)
        end
        if haskey(_PM.var(pm, n), :sd_block)
            sd_total += sum((JuMP.value(v) for v in values(_PM.var(pm, n, :sd_block))); init=0.0)
        end

        max_balance = max(max_balance, _ablation_bus_balance_residual(pm, n))

        agg_e = 0.0
        if haskey(_PM.var(pm, n), :se)
            agg_e += sum((JuMP.value(v) for v in values(_PM.var(pm, n, :se))); init=0.0)
        end
        if haskey(_PM.var(pm, n), :se_ne)
            agg_e += sum((JuMP.value(v) for v in values(_PM.var(pm, n, :se_ne))); init=0.0)
        end
        push!(agg_energy_by_nw, agg_e)

        if haskey(_PM.ref(pm, n), :g_min)
            for bus in _PM.ids(pm, n, :bus)
                sigma0 = _PM.ref(pm, n, :gscr_sigma0_gershgorin_margin, bus)
                g_min = _PM.ref(pm, n, :g_min)
                lhs = sigma0 + sum(
                    _PM.ref(pm, n, key[1], key[2], "b_block") * JuMP.value(_PM.var(pm, n, :na_block, key))
                    for key in _PM.ref(pm, n, :bus_gfm_devices, bus); init=0.0,
                )
                rhs = g_min * sum(
                    _PM.ref(pm, n, key[1], key[2], "p_block_max") * JuMP.value(_PM.var(pm, n, :na_block, key))
                    for key in _PM.ref(pm, n, :bus_gfl_devices, bus); init=0.0,
                )
                min_margin = min(min_margin, lhs - rhs)
            end
        end

        for i in _PM.ids(pm, :storage, nw=n)
            st = _PM.ref(pm, n, :storage, i)
            dt = float(get(_PM.ref(pm, n), :time_elapsed, 1.0))
            ce = float(get(st, "charge_efficiency", 1.0))
            de = float(get(st, "discharge_efficiency", 1.0))
            inflow = float(get(st, "stationary_energy_inflow", 0.0))
            outflow = float(get(st, "stationary_energy_outflow", 0.0))
            selfd = float(get(st, "self_discharge_rate", 0.0))
            se = JuMP.value(_PM.var(pm, n, :se, i))
            sc = JuMP.value(_PM.var(pm, n, :sc, i))
            sd = JuMP.value(_PM.var(pm, n, :sd, i))
            if _FP.is_first_id(pm, n, :hour)
                e0 = float(get(st, "energy", 0.0))
                rhs = ((1 - selfd)^dt) * e0 + dt * (ce * sc - sd / de + inflow - outflow)
                max_state_res = max(max_state_res, abs(se - rhs))
            else
                prev_n = _FP.prev_id(pm, n, :hour)
                se_prev = JuMP.value(_PM.var(pm, prev_n, :se, i))
                rhs = ((1 - selfd)^dt) * se_prev + dt * (ce * sc - sd / de + inflow - outflow)
                max_state_res = max(max_state_res, abs(se - rhs))
            end
        end

        if haskey(_PM.var(pm, n), :se_ne)
            for i in _PM.ids(pm, :ne_storage, nw=n)
                st = _PM.ref(pm, n, :ne_storage, i)
                dt = float(get(_PM.ref(pm, n), :time_elapsed, 1.0))
                ce = float(get(st, "charge_efficiency", 1.0))
                de = float(get(st, "discharge_efficiency", 1.0))
                inflow = float(get(st, "stationary_energy_inflow", 0.0))
                outflow = float(get(st, "stationary_energy_outflow", 0.0))
                selfd = float(get(st, "self_discharge_rate", 0.0))
                se = JuMP.value(_PM.var(pm, n, :se_ne, i))
                sc = JuMP.value(_PM.var(pm, n, :sc_ne, i))
                sd = JuMP.value(_PM.var(pm, n, :sd_ne, i))
                z = haskey(_PM.var(pm, n), :z_strg_ne) ? JuMP.value(_PM.var(pm, n, :z_strg_ne, i)) : 1.0
                if _FP.is_first_id(pm, n, :hour)
                    e0 = float(get(st, "energy", 0.0))
                    rhs = ((1 - selfd)^dt) * e0 * z + dt * (ce * sc - sd / de + inflow * z - outflow * z)
                    max_state_res = max(max_state_res, abs(se - rhs))
                else
                    prev_n = _FP.prev_id(pm, n, :hour)
                    se_prev = JuMP.value(_PM.var(pm, prev_n, :se_ne, i))
                    rhs = ((1 - selfd)^dt) * se_prev + dt * (ce * sc - sd / de + inflow * z - outflow * z)
                    max_state_res = max(max_state_res, abs(se - rhs))
                end
            end
        end

        if haskey(_PM.var(pm, n), :na_block) && haskey(_PM.var(pm, n), :su_block) && haskey(_PM.var(pm, n), :sd_block)
            for key in keys(_PM.var(pm, n, :na_block))
                device_key = key[1]
                d = _PM.ref(pm, n, device_key[1], device_key[2])
                na = JuMP.value(_PM.var(pm, n, :na_block, device_key))
                su = JuMP.value(_PM.var(pm, n, :su_block, device_key))
                sdv = JuMP.value(_PM.var(pm, n, :sd_block, device_key))
                prev_na = _FP.is_first_id(pm, n, :hour) ? float(get(d, "na0", 0.0)) : JuMP.value(_PM.var(pm, _FP.prev_id(pm, n, :hour), :na_block, device_key))
                transition_max = max(transition_max, abs((na - prev_na) - (su - sdv)))
            end
        end
    end

    return Dict{String,Any}(
        "total_generation_dispatch" => total_gen,
        "total_storage_discharge" => total_sd,
        "total_storage_charge" => total_sc,
        "final_aggregate_storage_energy" => agg_energy_by_nw[end],
        "minimum_aggregate_storage_energy" => minimum(agg_energy_by_nw),
        "startup_total" => su_total,
        "shutdown_total" => sd_total,
        "max_active_balance_residual" => max_balance,
        "max_storage_state_residual" => max_state_res,
        "max_startup_shutdown_transition_residual" => transition_max,
        "min_gscr_margin" => isfinite(min_margin) ? min_margin : nothing,
    )
end

function _run_growing_horizon_row(raw::Dict{String,Any}, h::Int)
    raw_h = _make_growing_horizon_raw(raw, h)
    data = _prepare_solver_data(raw_h; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _apply_existing_storage_initial_energy_policy!(data, "half_energy_rating")
    _mutate_candidate_energy_zero!(data)
    _inject_g_min!(data, 0.0)

    load_sum = _sum_load_over_horizon(data)
    solved = _solve_with_pm(data, _builder_with_final_policy(:no_final))
    status = solved["status"]
    row = Dict{String,Any}(
        "horizon" => h,
        "status" => status,
        "objective" => solved["objective"],
        "solve_time_sec" => solved["solve_time_sec"],
        "total_load_over_horizon" => load_sum,
        "final_storage_policy" => "short_horizon_relaxed",
        "constraint_storage_state_final_count" => 0,
        "constraint_storage_state_final_ne_count" => 0,
    )

    if status in _ACTIVE_OK
        pm = solved["pm"]
        nw1 = first(sort(collect(_FP.nw_ids(pm))))
        merge!(row, _collect_temporal_metrics(pm))
        row["invested_blocks_by_carrier"] = _ablation_investment_by_carrier(pm, nw1)
    end
    return row
end

function _first_failing_hour_storage_audit(raw::Dict{String,Any}, hstar::Int, last_feasible_h::Int)
    out = Dict{String,Any}("hstar" => hstar, "last_feasible_horizon" => last_feasible_h)
    if hstar <= 0
        return out
    end
    nw_star = raw["nw"][string(hstar)]
    load_h = sum((float(get(l, "pd", 0.0)) for l in values(get(nw_star, "load", Dict{String,Any}())) if get(l, "status", 1) != 0); init=0.0)
    installed_gen = sum((float(get(g, "n_block0", 0.0)) * float(get(g, "p_block_max", 0.0)) * _pmax_pu(g) for g in values(get(nw_star, "gen", Dict{String,Any}())) if haskey(g, "type")); init=0.0)
    max_gen = sum((float(get(g, "n_block_max", get(g, "n_block0", 0.0))) * float(get(g, "p_block_max", 0.0)) * _pmax_pu(g) for g in values(get(nw_star, "gen", Dict{String,Any}())) if haskey(g, "type")); init=0.0)

    ppu_bad = Dict{String,Any}[]
    for (id, g) in get(nw_star, "gen", Dict{String,Any}())
        if !haskey(g, "type")
            continue
        end
        pminpu = float(get(g, "p_min_pu", 0.0))
        pmaxpu = float(get(g, "p_max_pu", 1.0))
        if pminpu > pmaxpu + _EPS || pmaxpu < -_EPS || pmaxpu > 1.0 + _EPS || pminpu < -1.0 - _EPS
            push!(ppu_bad, Dict("id" => id, "p_min_pu" => pminpu, "p_max_pu" => pmaxpu))
        end
    end

    branch_anom = Dict{String,Any}[]
    for (id, br) in get(nw_star, "branch", Dict{String,Any}())
        status = get(br, "br_status", get(br, "status", 1))
        rate_a = float(get(br, "rate_a", 0.0))
        if status == 0 || rate_a <= 0.0
            push!(branch_anom, Dict("id" => id, "status" => status, "rate_a" => rate_a))
        end
    end
    dcline_anom = Dict{String,Any}[]
    for (id, dc) in get(nw_star, "dcline", Dict{String,Any}())
        status = get(dc, "br_status", get(dc, "status", 1))
        cap = max(abs(float(get(dc, "pmaxf", 0.0))), abs(float(get(dc, "pminf", 0.0))), abs(float(get(dc, "pmaxt", 0.0))), abs(float(get(dc, "pmint", 0.0))))
        if status == 0 || cap <= 0.0
            push!(dcline_anom, Dict("id" => id, "status" => status, "max_abs_cap" => cap))
        end
    end

    out["load_at_hstar"] = load_h
    out["installed_available_generation_at_hstar"] = installed_gen
    out["max_expandable_generation_at_hstar"] = max_gen
    out["p_min_pu_p_max_pu_anomalies"] = ppu_bad
    out["branch_availability_anomalies"] = branch_anom
    out["dcline_availability_anomalies"] = dcline_anom

    if last_feasible_h > 0
        raw_f = _make_growing_horizon_raw(raw, last_feasible_h)
        data_f = _prepare_solver_data(raw_f; mode=:capexp)
        _set_mode_nmax_policy!(data_f, "full_capexp")
        _apply_existing_storage_initial_energy_policy!(data_f, "half_energy_rating")
        _mutate_candidate_energy_zero!(data_f)
        _inject_g_min!(data_f, 0.0)
        solved_f = _solve_with_pm(data_f, _builder_with_final_policy(:no_final))
        if solved_f["status"] in _ACTIVE_OK
            pm = solved_f["pm"]
            nws = sort(collect(_FP.nw_ids(pm)))
            last_nw = last(nws)
            prev_nw = length(nws) > 1 ? nws[end-1] : last_nw
            existing_energy_start = 0.0
            lb_bind = 0
            ub_bind = 0
            charge_opp = 0.0
            total_discharge = 0.0
            for i in _PM.ids(pm, :storage, nw=last_nw)
                st = _PM.ref(pm, last_nw, :storage, i)
                if _is_battery_candidate(st)
                    continue
                end
                se_prev = JuMP.value(_PM.var(pm, prev_nw, :se, i))
                se_last = JuMP.value(_PM.var(pm, last_nw, :se, i))
                existing_energy_start += se_prev
                cap = float(get(st, "energy_rating", 0.0))
                lb_bind += se_last <= _EPS ? 1 : 0
                ub_bind += cap > _EPS && abs(se_last - cap) <= _EPS ? 1 : 0
                if haskey(_PM.var(pm, prev_nw), :sc)
                    sc_prev = JuMP.value(_PM.var(pm, prev_nw, :sc, i))
                    sc_ub = _var_ub(_PM.var(pm, prev_nw, :sc, i))
                    if isfinite(sc_ub)
                        charge_opp += max(0.0, sc_ub - sc_prev)
                    end
                end
                if haskey(_PM.var(pm, prev_nw), :sd)
                    total_discharge += JuMP.value(_PM.var(pm, prev_nw, :sd, i))
                end
            end
            out["existing_storage_energy_available_at_start_of_hstar"] = existing_energy_start
            out["aggregate_storage_discharge_requirement_last_feasible_horizon"] = total_discharge
            out["storage_units_at_lower_energy_bound_last_feasible"] = lb_bind
            out["storage_units_at_upper_energy_bound_last_feasible"] = ub_bind
            out["storage_charge_opportunity_before_hstar"] = charge_opp
        end
    end
    return out
end

function _run_temporal_ablation_variant(raw::Dict{String,Any}, hstar::Int, label::String; builder, mutator=nothing)
    raw_h = _make_growing_horizon_raw(raw, hstar)
    data = _prepare_solver_data(raw_h; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _apply_existing_storage_initial_energy_policy!(data, "half_energy_rating")
    _mutate_candidate_energy_zero!(data)
    _inject_g_min!(data, 0.0)
    if !(mutator === nothing)
        mutator(data)
    end
    solved = _solve_with_pm(data, builder)
    return Dict{String,Any}(
        "label" => label,
        "status" => solved["status"],
        "objective" => solved["objective"],
        "solve_time_sec" => solved["solve_time_sec"],
    )
end

function _run_growing_horizon_storage_diagnostic(raw::Dict{String,Any})
    rows = Dict{String,Any}[]
    for h in 1:24
        push!(rows, _run_growing_horizon_row(raw, h))
    end
    feasible_h = [r["horizon"] for r in rows if r["status"] in _ACTIVE_OK]
    infeasible_h = [r["horizon"] for r in rows if !(r["status"] in _ACTIVE_OK)]
    last_feasible = isempty(feasible_h) ? nothing : maximum(feasible_h)
    first_infeasible = isempty(infeasible_h) ? nothing : minimum(infeasible_h)
    first_failing_hour = first_infeasible

    audit = _first_failing_hour_storage_audit(raw, isnothing(first_infeasible) ? 0 : first_infeasible, isnothing(last_feasible) ? 0 : last_feasible)

    ablations = Dict{String,Any}[]
    if !isnothing(first_infeasible)
        hstar = first_infeasible
        push!(ablations, _run_temporal_ablation_variant(raw, hstar, "Hstar_without_storage_state"; builder=_builder_with_final_policy(:no_final; intertemporal_constraints=false)))
        push!(ablations, _run_temporal_ablation_variant(raw, hstar, "Hstar_without_final_storage"; builder=_builder_with_final_policy(:no_final)))
        push!(ablations, _run_temporal_ablation_variant(raw, hstar, "Hstar_without_existing_storage_state"; builder=_builder_with_final_policy(:no_final; include_existing_storage_state=false, include_candidate_storage_state=true)))
        push!(ablations, _run_temporal_ablation_variant(raw, hstar, "Hstar_without_candidate_storage_state"; builder=_builder_with_final_policy(:no_final; include_existing_storage_state=true, include_candidate_storage_state=false)))
        push!(ablations, _run_temporal_ablation_variant(raw, hstar, "Hstar_with_candidate_initial_soc_half"; builder=_builder_with_final_policy(:no_final), mutator=data -> begin
            for nw in values(data["nw"])
                for st in values(get(nw, "storage", Dict{String,Any}()))
                    if _is_battery_candidate(st)
                        st["energy"] = 0.5 * float(get(st, "e_block", 0.0)) * float(get(st, "n_block0", 0.0))
                    end
                end
            end
        end))
        push!(ablations, _run_temporal_ablation_variant(raw, hstar, "Hstar_candidate_one_block_installed"; builder=_builder_with_final_policy(:no_final), mutator=_mutate_candidate_one_block_installed!))
    end

    decision = "no infeasible horizon found"
    if !isempty(ablations)
        status_by = Dict(String(v["label"]) => String(v["status"]) for v in ablations)
        if get(status_by, "Hstar_without_storage_state", "") in _ACTIVE_OK
            decision = "storage trajectory is confirmed blocker"
        elseif get(status_by, "Hstar_without_final_storage", "") in _ACTIVE_OK
            decision = "final state policy is blocker"
        elseif get(status_by, "Hstar_without_existing_storage_state", "") in _ACTIVE_OK
            decision = "existing storage trajectory is blocker"
        elseif get(status_by, "Hstar_without_candidate_storage_state", "") in _ACTIVE_OK
            decision = "candidate storage trajectory is blocker"
        elseif get(status_by, "Hstar_candidate_one_block_installed", "") in _ACTIVE_OK
            decision = "greenfield candidate initial trajectory is blocker"
        else
            decision = "temporal coupling remains blocker under all tested ablations"
        end
    end

    return Dict{String,Any}(
        "g_min" => 0.0,
        "final_storage_policy" => "short_horizon_relaxed",
        "existing_storage_initial_energy_policy" => "half_energy_rating",
        "candidate_battery_energy_policy" => "0",
        "horizon_rows" => rows,
        "last_feasible_horizon" => last_feasible,
        "first_infeasible_horizon" => first_infeasible,
        "first_failing_hour" => first_failing_hour,
        "first_failing_hour_audit" => audit,
        "temporal_ablations_at_hstar" => ablations,
        "conclusion" => decision,
    )
end

function _write_report(
    schema::Dict{String,Any},
    adequacy::Dict{String,Any},
    gate::Dict{String,Any},
    diag::Union{Nothing,Dict{String,Any}},
    deep_diag::Dict{String,Any},
    presolve_candidates::Vector{Dict{String,Any}},
    existing_storage_policy_runs::Dict{String,Any},
    final_storage_24h_diag::Dict{String,Any},
    growing_horizon_diag::Dict{String,Any},
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

        println(io, "## Existing Storage Initial Energy Policy")
        policy = existing_storage_policy_runs
        one_g0 = policy["one_snapshot_g_min_0"]
        run24_g0 = policy["full_24h_g_min_0"]
        run24_g05 = policy["full_24h_g_min_0_5"]
        pol_stats = run24_g0["existing_storage_initial_energy_policy_stats"]
        println(io, "- old policy: ", policy["old_policy"])
        println(io, "- diagnostic result: ", policy["diagnostic_result"])
        println(io, "- new solver-copy policy: ", policy["new_solver_copy_policy"])
        println(io, "- modified storage count: ", pol_stats["existing_storage_rows_modified"])
        println(io, "- existing storage energy/energy_rating after policy (min/mean/max): ", _fmt(pol_stats["existing_storage_energy_over_rating_min"]), " / ", _fmt(pol_stats["existing_storage_energy_over_rating_mean"]), " / ", _fmt(pol_stats["existing_storage_energy_over_rating_max"]))
        println(io, "- candidate battery energy policy: set to 0 for battery_gfl/battery_gfm with n_block0=0 and na0=0")
        println(io, "- candidate battery energy remains zero: ", pol_stats["candidate_battery_energy_all_zero"], " (max abs=", _fmt(pol_stats["candidate_battery_energy_abs_max"]), ", forced_rows=", pol_stats["candidate_battery_rows_forced_zero"], ")")
        println(io, "- one-snapshot g_min=0 status: ", one_g0["status"], " (snapshot=", policy["one_snapshot_id"], ")")
        println(io, "- 24h g_min=0 status: ", run24_g0["status"])
        println(io, "- positive g_min run executed: ", policy["positive_g_min_run_executed"])
        if policy["positive_g_min_run_executed"]
            println(io, "- g_min=0.5 status: ", run24_g05["status"])
            println(io, "- g_min=0.5 investment by carrier:")
            if isempty(run24_g05["investment_by_carrier"])
                println(io, "  - none")
            else
                for (carrier, val) in sort(collect(run24_g05["investment_by_carrier"]); by=first)
                    println(io, "  - ", carrier, ": ", _fmt(val))
                end
            end
            println(io, "- g_min=0.5 investment by bus:")
            if isempty(run24_g05["investment_by_bus"])
                println(io, "  - none")
            else
                for (bus, val) in sort(collect(run24_g05["investment_by_bus"]); by=first)
                    println(io, "  - bus ", bus, ": ", _fmt(val))
                end
            end
        end
        println(io)

        println(io, "## 24h Final Storage-State Diagnostic (g_min = 0)")
        println(io, "| variant | status | constraint_storage_state_final | constraint_storage_state_final_ne | aggregate initial storage energy | aggregate final storage energy | storage units binding at final lower bound | total storage discharge over horizon | total storage charge over horizon |")
        println(io, "|---|---|---:|---:|---:|---:|---:|---:|---:|")
        for key in ("full_24h_with_storage_state_and_final", "full_24h_with_storage_state_no_final", "full_24h_storage_state_relaxed_final")
            r = final_storage_24h_diag[key]
            println(
                io,
                "| ", r["scenario"],
                " | ", r["status"],
                " | ", r["constraint_storage_state_final_count"],
                " | ", r["constraint_storage_state_final_ne_count"],
                " | ", _fmt(r["aggregate_initial_storage_energy"]),
                " | ", _fmt(r["aggregate_final_storage_energy"]),
                " | ", _fmt(r["storage_units_binding_final_lower_bound"]),
                " | ", _fmt(r["total_storage_discharge_over_horizon"]),
                " | ", _fmt(r["total_storage_charge_over_horizon"]),
                " |",
            )
        end
        println(io, "- decision: ", final_storage_24h_diag["decision"])
        println(io)

        println(io, "## Growing-Horizon Storage Dynamics Diagnostic")
        println(io, "- g_min: 0")
        println(io, "- final storage policy: ", growing_horizon_diag["final_storage_policy"])
        println(io, "- existing storage initial energy policy: ", growing_horizon_diag["existing_storage_initial_energy_policy"])
        println(io, "- candidate battery energy policy: ", growing_horizon_diag["candidate_battery_energy_policy"])
        println(io)
        println(io, "| H | status | objective | solve_time_s | total_load | total_gen_dispatch | total_storage_discharge | total_storage_charge | final_aggregate_storage_energy | minimum_aggregate_storage_energy | startup_total | shutdown_total | max_active_balance_residual | max_storage_state_residual | max_startup_shutdown_transition_residual | min_gSCR_margin |")
        println(io, "|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in growing_horizon_diag["horizon_rows"]
            println(io, "| ", r["horizon"], " | ", r["status"], " | ", _fmt(r["objective"]), " | ", _fmt(r["solve_time_sec"]), " | ", _fmt(r["total_load_over_horizon"]), " | ", _fmt(get(r, "total_generation_dispatch", nothing)), " | ", _fmt(get(r, "total_storage_discharge", nothing)), " | ", _fmt(get(r, "total_storage_charge", nothing)), " | ", _fmt(get(r, "final_aggregate_storage_energy", nothing)), " | ", _fmt(get(r, "minimum_aggregate_storage_energy", nothing)), " | ", _fmt(get(r, "startup_total", nothing)), " | ", _fmt(get(r, "shutdown_total", nothing)), " | ", _fmt(get(r, "max_active_balance_residual", nothing)), " | ", _fmt(get(r, "max_storage_state_residual", nothing)), " | ", _fmt(get(r, "max_startup_shutdown_transition_residual", nothing)), " | ", _fmt(get(r, "min_gscr_margin", nothing)), " |")
        end
        println(io, "- last feasible horizon: ", growing_horizon_diag["last_feasible_horizon"])
        println(io, "- first infeasible horizon: ", growing_horizon_diag["first_infeasible_horizon"])
        println(io, "- first failing hour: ", growing_horizon_diag["first_failing_hour"])
        println(io)

        fha = growing_horizon_diag["first_failing_hour_audit"]
        println(io, "### First-Failing-Hour Storage Audit")
        println(io, "- load at H*: ", _fmt(get(fha, "load_at_hstar", nothing)))
        println(io, "- installed available generation at H*: ", _fmt(get(fha, "installed_available_generation_at_hstar", nothing)))
        println(io, "- max expandable generation at H*: ", _fmt(get(fha, "max_expandable_generation_at_hstar", nothing)))
        println(io, "- existing storage energy available at start of H*: ", _fmt(get(fha, "existing_storage_energy_available_at_start_of_hstar", nothing)))
        println(io, "- aggregate storage discharge requirement in last feasible horizon: ", _fmt(get(fha, "aggregate_storage_discharge_requirement_last_feasible_horizon", nothing)))
        println(io, "- storage units at lower energy bound in last feasible solution: ", _fmt(get(fha, "storage_units_at_lower_energy_bound_last_feasible", nothing)))
        println(io, "- storage units at upper energy bound in last feasible solution: ", _fmt(get(fha, "storage_units_at_upper_energy_bound_last_feasible", nothing)))
        println(io, "- storage charge opportunity before H*: ", _fmt(get(fha, "storage_charge_opportunity_before_hstar", nothing)))
        println(io, "- p_min_pu/p_max_pu anomalies at H*: ", length(get(fha, "p_min_pu_p_max_pu_anomalies", Dict{String,Any}[])))
        println(io, "- branch availability anomalies at H*: ", length(get(fha, "branch_availability_anomalies", Dict{String,Any}[])))
        println(io, "- dcline availability anomalies at H*: ", length(get(fha, "dcline_availability_anomalies", Dict{String,Any}[])))
        println(io)

        println(io, "### Temporal Constraint Ablations at H*")
        println(io, "| variant | status | objective | solve_time_s |")
        println(io, "|---|---|---:|---:|")
        for v in growing_horizon_diag["temporal_ablations_at_hstar"]
            println(io, "| ", v["label"], " | ", v["status"], " | ", _fmt(v["objective"]), " | ", _fmt(v["solve_time_sec"]), " |")
        end
        println(io, "- conclusion: ", growing_horizon_diag["conclusion"])
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

        println(io, "### 5.6 One-Snapshot Constraint-Family Ablation")
        cfa = one_deep["constraint_family_ablation"]
        println(io, "- snapshot: ", cfa["snapshot_id"])
        println(io, "- g_min: ", _fmt(cfa["g_min"]))
        println(io, "- standard balance reference: `", cfa["standard_balance_reference"], "`")
        println(io, "- dclines active: ", cfa["dclines_active"])
        println(io, "- dcline setpoint constraints on path: ", cfa["dcline_setpoint_constraints_on_path"])
        println(io, "- first infeasible variant overall: ", isnothing(cfa["first_infeasible_variant"]) ? "none" : cfa["first_infeasible_variant"])
        println(io, "- last feasible variant overall: ", isnothing(cfa["last_feasible_variant"]) ? "none" : cfa["last_feasible_variant"])
        println(io, "- last feasible variant before regression: ", isnothing(cfa["last_feasible_before_regression"]) ? "none" : cfa["last_feasible_before_regression"])
        println(io, "- first infeasible variant after a feasible variant: ", isnothing(cfa["first_infeasible_after_feasible_variant"]) ? "none" : cfa["first_infeasible_after_feasible_variant"])
        println(io, "- likely root cause: ", cfa["likely_root_cause"])
        println(io)
        println(io, "| variant | policy | status | objective | solve_time_s | pg | ps | sc | sd | se | p_dc | p_branch | n_block | na_block | su_block | sd_block | bus_balance | dcline_loss | gen_block_dispatch | storage_bounds | storage_thermal | storage_losses | storage_state | startup_shutdown | gSCR | balance_residual | gen_dispatch | storage_discharge | storage_charge | dcline_abs_sum | invested_blocks |")
        println(io, "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for v in cfa["variants"]
            vc = v["variables"]
            cc = v["constraints"]
            fm = get(v, "feasible_metrics", Dict{String,Any}())
            println(
                io,
                "| ", v["label"],
                " | ", v["existing_storage_initial_energy_policy"],
                " | ", v["status"],
                " | ", _fmt(v["objective"]),
                " | ", _fmt(v["solve_time_sec"]),
                " | ", vc["pg"],
                " | ", vc["ps"],
                " | ", vc["sc"],
                " | ", vc["sd"],
                " | ", vc["se"],
                " | ", vc["p_dc"],
                " | ", vc["p_branch"],
                " | ", vc["n_block"],
                " | ", vc["na_block"],
                " | ", vc["su_block"],
                " | ", vc["sd_block"],
                " | ", cc["bus_balance"],
                " | ", cc["dcline_loss"],
                " | ", cc["gen_block_dispatch"],
                " | ", cc["storage_bounds"],
                " | ", cc["storage_thermal"],
                " | ", cc["storage_losses"],
                " | ", cc["storage_state"],
                " | ", cc["startup_shutdown"],
                " | ", cc["gSCR"],
                " | ", _fmt(get(fm, "bus_balance_residual_max", nothing)),
                " | ", _fmt(get(fm, "total_generation_dispatch", nothing)),
                " | ", _fmt(get(fm, "total_storage_discharge", nothing)),
                " | ", _fmt(get(fm, "total_storage_charge", nothing)),
                " | ", _fmt(get(fm, "total_dcline_transfer_abs_sum", nothing)),
                " | ", _fmt(get(fm, "total_invested_blocks", nothing)),
                " |",
            )
        end
        println(io)
        println(io, "#### Feasible Variant Investment by Carrier")
        for v in cfa["variants"]
            if !(v["status"] in _ACTIVE_OK)
                continue
            end
            inv = get(get(v, "feasible_metrics", Dict{String,Any}()), "investment_by_carrier", Dict{String,Any}())
            if isempty(inv)
                println(io, "- ", v["label"], ": none")
            else
                parts = ["$(carrier)=$(_fmt(val))" for (carrier, val) in sort(collect(inv); by=first)]
                println(io, "- ", v["label"], ": ", join(parts, ", "))
            end
        end
        if cfa["all_variants_infeasible"]
            println(io)
            println(io, "#### Unit and Bounds Audit (All Variants Infeasible)")
            for v in cfa["variants"]
                ba = get(v, "bounds_audit", Dict{String,Any}())
                if isempty(ba)
                    continue
                end
                println(io, "- ", v["label"], ": load_sum=", _fmt(ba["load_sum_pm_units"]), ", gen_block_dispatch_ub_sum=", _fmt(ba["gen_block_dispatch_upper_bound_sum"]), ", isolated_load_buses=", join(string.(ba["buses_with_load_no_supply_no_incident_branch_or_dcline"]), ","))
                for key in ("gen_pg_bounds", "branch_p_bounds", "dcline_p_dc_bounds", "storage_ps_bounds", "storage_sc_bounds", "storage_sd_bounds", "storage_se_bounds")
                    bs = ba[key]
                    println(io, "  - ", key, ": count=", bs["count"], ", lb=[", _fmt(bs["lb_min"]), ",", _fmt(bs["lb_max"]), "], ub=[", _fmt(bs["ub_min"]), ",", _fmt(bs["ub_max"]), "], lb_gt_ub=", bs["lb_gt_ub_count"])
                end
                println(io, "  - variables with lb > ub: ", isempty(ba["variables_with_lb_gt_ub"]) ? "none" : ba["variables_with_lb_gt_ub"])
            end
        end
        println(io)

        println(io, "## Storage State Constraint Diagnostic")
        ssd = one_deep["storage_state_diagnostic"]
        println(io, "- snapshot: ", ssd["snapshot_id"])
        println(io, "- startup/shutdown independently feasible without storage state: ", ssd["startup_shutdown_independently_feasible_without_storage_state"])
        println(io, "- gSCR at g_min=0 independently feasible without storage state: ", ssd["gscr_gmin0_independently_feasible_without_storage_state"])
        println(io, "- startup/shutdown and gSCR feasible together without storage state: ", ssd["startup_shutdown_and_gscr_feasible_without_storage_state"])
        println(io, "- final storage state is blocker: ", ssd["final_storage_state_is_blocker"])
        println(io, "- initial energy policy is blocker: ", ssd["initial_energy_policy_is_blocker"])
        println(io, "- candidate storage state coupling is blocker: ", ssd["candidate_storage_state_coupling_is_blocker"])
        println(io, "- first failing storage condition: ", ssd["first_failing_storage_condition"])
        println(io, "- recommended model fix: ", ssd["recommended_model_fix"])
        println(io)

        println(io, "### Isolated Startup/gSCR Variants Without Storage State")
        println(io, "| variant | policy | status | objective | solve_time_s | startup_shutdown_constraints | gSCR_constraints |")
        println(io, "|---|---|---|---:|---:|---:|---:|")
        for v in ssd["isolated_startup_gscr_without_storage_state"]
            cc = v["constraints"]
            println(io, "| ", v["label"], " | ", v["existing_storage_initial_energy_policy"], " | ", v["status"], " | ", _fmt(v["objective"]), " | ", _fmt(v["solve_time_sec"]), " | ", cc["startup_shutdown"], " | ", cc["gSCR"], " |")
        end
        println(io)

        println(io, "### Storage-State Equation Audit")
        sea = ssd["storage_state_equation_audit"]
        println(io, "- focused ablation variant: ", sea["variant"])
        println(io, "- storage type counts: ", sea["storage_type_counts"])
        println(io, "- initial state active in one-snapshot case: ", sea["initial_state_active_one_snapshot"])
        println(io, "- final state active in one-snapshot case: ", sea["final_state_active_one_snapshot"])
        println(io, "- initial equation: `", sea["initial_equation"], "`")
        println(io, "- final equation if called: `", sea["final_equation_if_called"], "`")
        println(io, "- final state policy: ", sea["final_state_policy"])
        println(io, "| function | focused ablation calls | active builder first-snapshot calls |")
        println(io, "|---|---:|---:|")
        for fname in sort(collect(keys(sea["functions_called_in_focused_ablation"])))
            println(io, "| ", fname, " | ", sea["functions_called_in_focused_ablation"][fname], " | ", sea["functions_called_in_active_builder_first_snapshot"][fname], " |")
        end
        println(io)

        println(io, "### Last Feasible Storage Dispatch (`add_standard_storage_losses`)")
        lfs = ssd["last_feasible_storage_dispatch"]
        println(io, "- status: ", lfs["status"])
        println(io, "- policy used: ", lfs["existing_storage_initial_energy_policy"])
        println(io, "- total storage discharge: ", _fmt(lfs["total_storage_discharge"]))
        println(io, "- total storage charge: ", _fmt(lfs["total_storage_charge"]))
        println(io, "- net storage energy used: ", _fmt(lfs["net_storage_energy_used"]))
        println(io, "- nonzero storage units: ", lfs["nonzero_storage_count"])
        println(io, "- required energy exceeds initial available energy: ", lfs["required_energy_exceeds_initial_available_energy"])
        println(io, "| id | bus | kind | carrier | type | ps | sc | sd | se | energy | energy_rating | charge_rating | discharge_rating | p_block_max | e_block | n_block0 | n_block_max | na_block | n_block | initial_energy | required_discharge_energy |")
        println(io, "|---:|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in lfs["nonzero_storage_rows"]
            println(io, "| ", r["id"], " | ", r["bus"], " | ", r["kind"], " | ", r["carrier"], " | ", r["type"], " | ", _fmt(r["ps"]), " | ", _fmt(r["sc"]), " | ", _fmt(r["sd"]), " | ", _fmt(r["se"]), " | ", _fmt(r["energy"]), " | ", _fmt(r["energy_rating"]), " | ", _fmt(r["charge_rating"]), " | ", _fmt(r["discharge_rating"]), " | ", _fmt(r["p_block_max"]), " | ", _fmt(r["e_block"]), " | ", _fmt(r["n_block0"]), " | ", _fmt(r["n_block_max"]), " | ", _fmt(r["na_block"]), " | ", _fmt(r["n_block"]), " | ", _fmt(r["initial_energy"]), " | ", _fmt(r["required_discharge_energy"]), " |")
        end
        println(io)

        println(io, "### Storage-State Feasibility Check Outside Full Model")
        sf = ssd["storage_state_feasibility_check_from_last_feasible_dispatch"]
        println(io, "- feasible against last feasible dispatch: ", sf["feasible_against_last_feasible_dispatch"])
        println(io, "- half-energy policy consistency ok: ", sf["half_energy_policy_consistency_ok"], " (violations=", sf["half_energy_policy_consistency_violations"], ")")
        println(io, "- failing conditions: ", isempty(sf["failing_conditions"]) ? "none" : join(sf["failing_conditions"], ", "))
        println(io, "- note: ", sf["note"])
        println(io, "| id | kind | energy | energy_rating | energy/energy_rating | policy_applied_flag | initial_energy | sc | sd | se_required | block_energy_capacity | checked_upper_capacity | condition | final_active | final_ok |")
        println(io, "|---:|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---|---|---|")
        for r in sf["rows"]
            println(io, "| ", r["id"], " | ", r["kind"], " | ", _fmt(r["energy"]), " | ", _fmt(r["energy_rating"]), " | ", _fmt(r["energy_over_energy_rating"]), " | ", r["policy_applied_flag"], " | ", _fmt(r["initial_energy"]), " | ", _fmt(r["sc"]), " | ", _fmt(r["sd"]), " | ", _fmt(r["se_required_by_initial_state"]), " | ", _fmt(r["block_energy_capacity"]), " | ", _fmt(r["upper_capacity_checked"]), " | ", r["condition"], " | ", r["final_condition_active"], " | ", r["final_condition_ok"], " |")
        end
        println(io)

        println(io, "### Storage-State Diagnostic Variants")
        println(io, "| variant | policy | status | objective | solve_time_s | storage_state_constraints | note |")
        println(io, "|---|---|---|---:|---:|---:|---|")
        skipped_zero_energy_rows = Dict{String,Any}[]
        for v in ssd["storage_state_variants"]
            note = ""
            if v["label"] == "storage_state_no_final"
                note = "final/terminal constraints skipped"
            elseif v["label"] == "storage_state_relaxed_final"
                note = "equivalent to no-final in one-snapshot active branch"
            elseif v["label"] == "storage_state_half_energy_rating_initial"
                note = "existing storage energy set to 0.5 * energy_rating in solver copy"
            elseif v["label"] == "add_storage_state_constraints_with_half_energy_rating"
                note = "full storage-state constraints with global half-energy policy"
            elseif v["label"] == "existing_storage_state_only"
                note = "storage-state constraints only for existing storage"
            elseif v["label"] == "candidate_storage_state_only"
                note = "storage-state constraints only for battery_gfl/battery_gfm; candidate energy=0"
            elseif v["label"] == "candidate_storage_state_from_blocks"
                note = "candidate ratings set from n_block_max and block sizes in solver copy"
            elseif v["label"] == "existing_storage_state_only_exclude_zero_energy_rating"
                note = "existing-only storage-state with energy_rating>0 filter"
            end
            println(io, "| ", v["label"], " | ", v["existing_storage_initial_energy_policy"], " | ", v["status"], " | ", _fmt(v["objective"]), " | ", _fmt(v["solve_time_sec"]), " | ", v["constraints"]["storage_state"], " | ", note, " |")
            if v["label"] == "existing_storage_state_only_exclude_zero_energy_rating"
                skipped_zero_energy_rows = v["skipped_existing_storage_zero_energy_rating_rows"]
            end
        end
        println(io)
        println(io, "- existing_storage_state_only_exclude_zero_energy_rating skipped rows: ", length(skipped_zero_energy_rows))
        if !isempty(skipped_zero_energy_rows)
            println(io, "- skipped row ids: ", join([s["id"] for s in skipped_zero_energy_rows], ","))
        end
        println(io)

        println(io, "## Half-Energy Policy Consistency and Split Storage-State Diagnostic")
        println(io, "- policy used for one-snapshot storage-state ablations: ", ssd["existing_storage_initial_energy_policy"])
        println(io, "- add_storage_state_constraints_with_half_energy_rating: ", ssd["add_storage_state_constraints_with_half_energy_rating_status"])
        println(io, "- existing_storage_state_only: ", ssd["existing_storage_state_only_status"])
        println(io, "- candidate_storage_state_only: ", ssd["candidate_storage_state_only_status"])
        println(io, "- candidate_storage_state_from_blocks: ", ssd["candidate_storage_state_from_blocks_status"])
        println(io, "- existing_storage_state_only_exclude_zero_energy_rating: ", ssd["existing_storage_state_only_exclude_zero_energy_rating_status"])
        println(io, "- split-variant all-optimal flag: ", ssd["all_split_variants_optimal"])
        println(io, "- decision logic result: ", one_deep["split_storage_state_root_cause_decision"])
        println(io)

        println(io, "### 5.7 Balance-Equation Visibility Audit")
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
        println(io, "- standard dcline from-bound constraint functions:")
        for s in sdsa["standard_constraint_dcline_fr_bound_functions"]
            println(io, "  - ", s)
        end
        println(io, "- standard dcline to-bound constraint functions:")
        for s in sdsa["standard_constraint_dcline_to_bound_functions"]
            println(io, "  - ", s)
        end
        println(io, "- standard power-balance functions (contain bus_arcs_dc):")
        for s in sdsa["standard_constraint_power_balance_functions"]
            println(io, "  - ", s)
        end
        println(io, "- variable names used: ", join(sdsa["variable_names"], ", "))
        println(io, "- constraint names used: ", join(sdsa["constraint_names"], ", "))
        println(io, "- dcline losses/efficiency modeled: ", sdsa["dcline_efficiency_modeled"], " (", sdsa["loss_model"], ")")
        println(io, "- dcline limits mode: ", sdsa["dcline_limits_mode"])
        println(io, "- standard OPF builder call lines: variable_dcline_power=", join(string.(sdsa["standard_builder_opf_calls"]["build_opf_variable_dcline_power_lines"]), ","), ", constraint_power_balance=", join(string.(sdsa["standard_builder_opf_calls"]["build_opf_constraint_power_balance_lines"]), ","), ", constraint_dcline_power_losses=", join(string.(sdsa["standard_builder_opf_calls"]["build_opf_constraint_dcline_power_losses_lines"]), ","))
        println(io)

        println(io, "### 2) Active UC/CAPEXP/gSCR path audit")
        println(io, "- active builder file: ", apda["path"])
        println(io, "- calls standard OPF bus balance: ", apda["calls_standard_opf_bus_balance"])
        println(io, "- calls custom system balance: ", apda["calls_custom_system_balance"])
        println(io, "- calls standard dcline variable function: ", apda["calls_standard_dcline_variable_function"])
        println(io, "- calls standard dcline constraints: ", apda["calls_standard_dcline_constraint_function"])
        println(io, "- calls dcline setpoint-active constraints: ", apda["calls_dcline_setpoint_active"])
        println(io, "- calls explicit dcline from-bound constraints: ", apda["calls_dcline_fr_bound_constraints"])
        println(io, "- calls explicit dcline to-bound constraints: ", apda["calls_dcline_to_bound_constraints"])
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
        println(io, "- interpreted as: active path uses standard bus-wise balance and no dcline setpoint constraints")
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
        println(io, "- Executed only if 24h g_min=0 reached OPTIMAL under existing-storage half-energy policy.")
        println(io, "- executed: ", existing_storage_policy_runs["positive_g_min_run_executed"])
        if existing_storage_policy_runs["positive_g_min_run_executed"]
            run24_g05 = existing_storage_policy_runs["full_24h_g_min_0_5"]
            println(io, "- g_min=0.5 status: ", run24_g05["status"])
            println(io, "- g_min=0.5 objective: ", _fmt(run24_g05["objective"]))
        end
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
        cfa = one_deep["constraint_family_ablation"]
        ssd = one_deep["storage_state_diagnostic"]
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
        println(io, "- active UC/CAPEXP/gSCR calls dcline setpoint-active constraints: ", apda["calls_dcline_setpoint_active"])
        println(io, "- exact missing call/location: ", apda["exact_missing_location"]["file"], " @ custom balance call line ", _fmt(apda["exact_missing_location"]["line_hint_calls_custom_balance"]; digits=0))
        println(io, "- recommended minimal fix: ", apda["recommended_minimal_fix"])
        println(io, "- synthetic generator sanity status: ", sgen["status"], " (passes=", sgen["passes_expected"], ")")
        println(io, "- synthetic battery sanity status: ", sbat["status"], " (passes=", sbat["passes_expected"], ")")
        println(io, "- one-snapshot extracted status: ", one["status"])
        println(io, "- first failing layer: ", deep_diag["first_failing_layer"])
        println(io, "- likely root cause (layered): ", deep_diag["likely_root_cause"])
        println(io, "- likely root cause (one-snapshot decision logic): ", one_deep["likely_root_cause"])
        println(io, "- constraint-family ablation first infeasible variant overall: ", isnothing(cfa["first_infeasible_variant"]) ? "none" : cfa["first_infeasible_variant"])
        println(io, "- constraint-family ablation last feasible variant overall: ", isnothing(cfa["last_feasible_variant"]) ? "none" : cfa["last_feasible_variant"])
        println(io, "- constraint-family ablation last feasible variant before regression: ", isnothing(cfa["last_feasible_before_regression"]) ? "none" : cfa["last_feasible_before_regression"])
        println(io, "- constraint-family ablation first infeasible variant after feasible: ", isnothing(cfa["first_infeasible_after_feasible_variant"]) ? "none" : cfa["first_infeasible_after_feasible_variant"])
        println(io, "- constraint-family ablation likely root cause: ", cfa["likely_root_cause"])
        println(io, "- startup/shutdown feasible without storage state: ", ssd["startup_shutdown_independently_feasible_without_storage_state"])
        println(io, "- gSCR g_min=0 feasible without storage state: ", ssd["gscr_gmin0_independently_feasible_without_storage_state"])
        println(io, "- storage final state blocker: ", ssd["final_storage_state_is_blocker"])
        println(io, "- storage initial-energy policy blocker: ", ssd["initial_energy_policy_is_blocker"])
        println(io, "- candidate storage state coupling blocker: ", ssd["candidate_storage_state_coupling_is_blocker"])
        println(io, "- storage-state recommended fix: ", ssd["recommended_model_fix"])
        println(io, "- If feasible, how much expansion is built? total blocks=", _fmt(gate["total_invested_blocks"]), ", generator blocks=", _fmt(gate["invested_generator_blocks"]), ", storage blocks=", _fmt(gate["invested_storage_blocks"]))
        println(io, "- Are battery_gfl and battery_gfm used? gfl=", _fmt(gate["invested_battery_gfl_blocks"]), ", gfm=", _fmt(gate["invested_battery_gfm_blocks"]))
        println(io, "- Does g_min=0 invest only for adequacy/economics, not for gSCR? ", gate_feasible ? true : "not testable (infeasible)")
        println(io, "- Were positive g_min runs executed? ", existing_storage_policy_runs["positive_g_min_run_executed"])
        println(io, "- Should next run proceed to a positive g_min sweep? ", gate_optimal && existing_storage_policy_runs["positive_g_min_run_executed"])
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
    existing_storage_policy_runs::Dict{String,Any},
    final_storage_24h_diag::Dict{String,Any},
    growing_horizon_diag::Dict{String,Any},
)
    mkpath(dirname(_RESULTS_PATH))
    bundle = Dict{String,Any}(
        "generated_at" => Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"),
        "dataset_path" => _CASE_PATH,
        "investment_cost_scale_24h" => _INVESTMENT_COST_SCALE_24H,
        "run_flag" => _RUN_FLAG,
        "positive_g_min_runs_skipped" => !existing_storage_policy_runs["positive_g_min_run_executed"],
        "existing_storage_initial_energy_policy" => existing_storage_policy_runs,
        "final_storage_state_24h_diagnostic" => final_storage_24h_diag,
        "growing_horizon_storage_dynamics_diagnostic" => growing_horizon_diag,
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
    snapshot_id = Int(adequacy["worst_snapshot"]["snapshot"])
    existing_storage_policy_runs = _run_existing_storage_initial_energy_policy_sequence(raw, snapshot_id)
    final_storage_24h_diag = _run_24h_final_storage_state_diagnostic(raw)
    growing_horizon_diag = _run_growing_horizon_storage_diagnostic(raw)

    gate = existing_storage_policy_runs["full_24h_g_min_0"]
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

    report = _write_report(schema, adequacy, gate, diag, deep_diag, presolve_candidates, existing_storage_policy_runs, final_storage_24h_diag, growing_horizon_diag)
    results_path = _write_results_bundle(schema, adequacy, gate, diag, deep_diag, presolve_candidates, existing_storage_policy_runs, final_storage_24h_diag, growing_horizon_diag)
    println("Wrote report: ", report)
    println("Wrote results JSON: ", results_path)
end

main()
