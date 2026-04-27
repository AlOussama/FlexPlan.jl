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
    "PYPSA_ELEC_S37_24H_CASE",
    raw"D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr\elec_s_37_24h_from_0301\case.json",
)
const _REPORT_PATH = normpath(@__DIR__, "..", "reports", "pypsa_elec_s_37_24h_gscr_study.md")

const _ACTIVE_OK = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL"])
const _MODES = ("uc_only", "full_capexp", "storage_only", "generator_only")
const _GATE_GMIN = 0.0
const _POSITIVE_GMIN_VALUES = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
const _EPS = 1e-6
const _NEAR = 1e-6

const _SYNC_CARRIERS = Set([
    "CCGT", "nuclear", "biomass", "oil", "lignite", "coal", "hard coal",
    "run-of-river", "ror", "hydro dams and reservoirs", "pumped hydro storage", "OCGT",
])

const _BLOCK_REQUIRED_FIELDS = [
    "type", "n_block0", "n_block_max", "na0", "p_block_min", "p_block_max",
    "q_block_min", "q_block_max", "b_block", "cost_inv_block",
    "startup_block_cost", "shutdown_block_cost",
]

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

_status_str(status) = string(status)

function _sorted_nw_ids(data::Dict{String,Any})
    return sort(parse.(Int, collect(keys(data["nw"]))))
end

_load_case() = JSON.parsefile(_CASE_PATH)

function _add_dimensions!(data::Dict{String,Any})
    if !haskey(data, "dim")
        _FP.add_dimension!(data, :hour, length(data["nw"]))
        _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
        _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    end
    return data
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

_is_bess_gfm(d::Dict{String,Any}) = String(get(d, "carrier", "")) == "BESS-GFM" && String(get(d, "type", "")) == "gfm"
_is_sync_gfm(d::Dict{String,Any}) = String(get(d, "type", "")) == "gfm" && String(get(d, "carrier", "")) in _SYNC_CARRIERS
_device_bus(table::String, d::Dict{String,Any}) = table == "gen" ? Int(get(d, "gen_bus", -1)) : Int(get(d, "storage_bus", -1))

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

function _prepare_solver_data(raw::Dict{String,Any}; mode::Symbol=:capexp)
    data = deepcopy(raw)
    data["per_unit"] = get(data, "per_unit", false)
    data["source_type"] = get(data, "source_type", "pypsa-flexplan-json")
    data["name"] = get(data, "name", "pypsa-elec-s37-24h")
    _add_dimensions!(data)
    for nw in values(data["nw"])
        _ensure_dcline!(nw)
        nw["per_unit"] = get(nw, "per_unit", data["per_unit"])
        nw["source_type"] = get(nw, "source_type", data["source_type"])
        nw["time_elapsed"] = get(nw, "time_elapsed", 1.0)
        nw["ne_storage"] = get(nw, "ne_storage", Dict{String,Any}())
        nw["g_min"] = 0.0
        nw["_g_min_source"] = "flexplan_injected_default"
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
        end
        for table in ("storage", "ne_storage")
            for st in values(get(nw, table, Dict{String,Any}()))
                if haskey(st, "n_block0")
                    st["n0"] = float(st["n_block0"])
                    st["nmax"] = mode == :uc ? st["n0"] : float(get(st, "n_block_max", st["n0"]))
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

function _set_mode_nmax_policy!(data::Dict{String,Any}, mode_name::String)
    for nw in values(data["nw"])
        for (table, _, d) in _iter_block_devices(nw)
            if !(haskey(d, "n0") && haskey(d, "nmax"))
                continue
            end
            if mode_name == "uc_only"
                d["nmax"] = d["n0"]
            elseif mode_name == "full_capexp"
                d["nmax"] = get(d, "n_block_max", d["nmax"])
            elseif mode_name == "storage_only"
                d["nmax"] = table == "gen" ? d["n0"] : get(d, "n_block_max", d["nmax"])
            elseif mode_name == "generator_only"
                d["nmax"] = table == "gen" ? get(d, "n_block_max", d["nmax"]) : d["n0"]
            end
            d["nmax"] = max(float(d["n0"]), float(d["nmax"]))
        end
    end
    return data
end

function _sum_dispatch_abs(pm, nw::Int, key::Tuple{Symbol,Int})
    if key[1] == :gen
        return haskey(_PM.var(pm, nw), :pg) ? abs(JuMP.value(_PM.var(pm, nw, :pg, key[2]))) : 0.0
    elseif key[1] == :storage
        return haskey(_PM.var(pm, nw), :ps) ? abs(JuMP.value(_PM.var(pm, nw, :ps, key[2]))) : 0.0
    else
        return haskey(_PM.var(pm, nw), :ps_ne) ? abs(JuMP.value(_PM.var(pm, nw, :ps_ne, key[2]))) : 0.0
    end
end

function _extract_dcline_flow_info(pm, nw::Int)
    ids = collect(_PM.ids(pm, nw, :dcline))
    if isempty(ids)
        return Dict("available" => false, "max_abs_flow" => nothing, "max_bound_violation" => nothing, "note" => "no dclines")
    end
    values = Float64[]
    for var_sym in (:p_dc, :pdc, :pdcf, :pf_dc, :p_dcgrid, :pconv_tf_fr)
        if !haskey(_PM.var(pm, nw), var_sym)
            continue
        end
        vdict = _PM.var(pm, nw, var_sym)
        for i in ids
            if haskey(vdict, i)
                push!(values, JuMP.value(vdict[i]))
            end
        end
    end
    if isempty(values)
        return Dict("available" => false, "max_abs_flow" => nothing, "max_bound_violation" => nothing, "note" => "flow var unavailable")
    end
    max_abs = maximum(abs.(values))
    max_viol = 0.0
    for i in ids
        dc = _PM.ref(pm, nw, :dcline, i)
        lb = min(float(get(dc, "pminf", -Inf)), float(get(dc, "pmint", -Inf)))
        ub = max(float(get(dc, "pmaxf", Inf)), float(get(dc, "pmaxt", Inf)))
        for v in values
            max_viol = max(max_viol, max(0.0, lb - v, v - ub))
        end
    end
    return Dict("available" => true, "max_abs_flow" => max_abs, "max_bound_violation" => max_viol, "note" => "")
end

function _solve_opf(raw::Dict{String,Any})
    data = _prepare_solver_data(raw; mode=:opf)
    try
        pm = _PM.instantiate_model(data, _PM.DCPPowerModel, _PM.build_mn_opf_strg)
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        t0 = time()
        JuMP.optimize!(pm.model)
        status = _status_str(JuMP.termination_status(pm.model))
        return Dict(
            "ok" => true,
            "pm" => pm,
            "status" => status,
            "objective" => (status in _ACTIVE_OK ? JuMP.objective_value(pm.model) : nothing),
            "solve_time_sec" => time() - t0,
            "error" => "",
        )
    catch err
        return Dict("ok" => false, "status" => "ERROR", "objective" => nothing, "solve_time_sec" => 0.0, "error" => sprint(showerror, err))
    end
end

function _opf_plausibility(opf_run::Dict{String,Any})
    out = Dict{String,Any}(
        "status" => opf_run["status"],
        "objective" => opf_run["objective"],
        "solve_time_sec" => get(opf_run, "solve_time_sec", 0.0),
        "available" => false,
        "reason" => get(opf_run, "error", ""),
    )
    if !get(opf_run, "ok", false) || !(opf_run["status"] in _ACTIVE_OK)
        return out
    end
    pm = opf_run["pm"]
    nws = sort(collect(_FP.nw_ids(pm)))
    max_sys_res = 0.0
    max_bus_res = 0.0
    max_branch_loading = 0.0
    overloaded = 0
    max_gen_bound = 0.0
    max_storage_power_bound = 0.0
    max_storage_energy_bound = 0.0
    dcline_note = ""
    dcline_max_abs = nothing
    dcline_max_viol = nothing
    for nw in nws
        pg = haskey(_PM.var(pm, nw), :pg) ? sum((JuMP.value(_PM.var(pm, nw, :pg, g)) for g in _PM.ids(pm, nw, :gen)); init=0.0) : 0.0
        ps = haskey(_PM.var(pm, nw), :ps) ? sum((JuMP.value(_PM.var(pm, nw, :ps, s)) for s in _PM.ids(pm, nw, :storage)); init=0.0) : 0.0
        ps_ne = haskey(_PM.var(pm, nw), :ps_ne) ? sum((JuMP.value(_PM.var(pm, nw, :ps_ne, s)) for s in _PM.ids(pm, nw, :ne_storage)); init=0.0) : 0.0
        load_pd = sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ids(pm, nw, :load)); init=0.0)
        max_sys_res = max(max_sys_res, abs(pg - ps - ps_ne - load_pd))
        if haskey(_PM.var(pm, nw), :p)
            p = _PM.var(pm, nw, :p)
            for bus in _PM.ids(pm, nw, :bus)
                bus_g = haskey(_PM.ref(pm, nw), :bus_gens) ? sum((JuMP.value(_PM.var(pm, nw, :pg, g)) for g in _PM.ref(pm, nw, :bus_gens, bus)); init=0.0) : 0.0
                bus_s = haskey(_PM.ref(pm, nw), :bus_storage) ? -sum((JuMP.value(_PM.var(pm, nw, :ps, s)) for s in _PM.ref(pm, nw, :bus_storage, bus)); init=0.0) : 0.0
                bus_l = haskey(_PM.ref(pm, nw), :bus_loads) ? sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ref(pm, nw, :bus_loads, bus)); init=0.0) : 0.0
                branch_net = haskey(_PM.ref(pm, nw), :bus_arcs) ? sum((JuMP.value(get(p, a, 0.0)) for a in _PM.ref(pm, nw, :bus_arcs, bus)); init=0.0) : 0.0
                max_bus_res = max(max_bus_res, abs(bus_g + bus_s - bus_l - branch_net))
            end
            for br in _PM.ids(pm, nw, :branch)
                b = _PM.ref(pm, nw, :branch, br)
                f, t = b["f_bus"], b["t_bus"]
                pf = JuMP.value(get(p, (br, f, t), 0.0))
                pt = JuMP.value(get(p, (br, t, f), 0.0))
                rate = float(get(b, "rate_a", 0.0))
                if rate > _EPS
                    loading = 100.0 * max(abs(pf), abs(pt)) / rate
                    max_branch_loading = max(max_branch_loading, loading)
                    overloaded += loading > 100.0 + 1e-6 ? 1 : 0
                end
            end
        end
        for g in _PM.ids(pm, nw, :gen)
            gen = _PM.ref(pm, nw, :gen, g)
            pgv = JuMP.value(_PM.var(pm, nw, :pg, g))
            pmax = float(get(gen, "pmax", Inf))
            pmin = float(get(gen, "pmin", -Inf))
            max_gen_bound = max(max_gen_bound, max(0.0, pmin - pgv, pgv - pmax))
        end
        for s in _PM.ids(pm, nw, :storage)
            ref_s = _PM.ref(pm, nw, :storage, s)
            sc = haskey(_PM.var(pm, nw), :sc) ? JuMP.value(_PM.var(pm, nw, :sc, s)) : 0.0
            sd = haskey(_PM.var(pm, nw), :sd) ? JuMP.value(_PM.var(pm, nw, :sd, s)) : 0.0
            sev = haskey(_PM.var(pm, nw), :se) ? JuMP.value(_PM.var(pm, nw, :se, s)) : 0.0
            er = float(get(ref_s, "energy_rating", get(ref_s, "energy", 0.0)))
            cr = float(get(ref_s, "charge_rating", Inf))
            dr = float(get(ref_s, "discharge_rating", Inf))
            max_storage_power_bound = max(max_storage_power_bound, max(0.0, -sc, sc - cr, -sd, sd - dr))
            max_storage_energy_bound = max(max_storage_energy_bound, max(0.0, -sev, sev - er))
        end
        dci = _extract_dcline_flow_info(pm, nw)
        if dci["available"]
            dcline_max_abs = isnothing(dcline_max_abs) ? dci["max_abs_flow"] : max(dcline_max_abs, dci["max_abs_flow"])
            dcline_max_viol = isnothing(dcline_max_viol) ? dci["max_bound_violation"] : max(dcline_max_viol, dci["max_bound_violation"])
        else
            dcline_note = dci["note"]
        end
    end
    out["available"] = true
    out["max_system_residual"] = max_sys_res
    out["max_bus_residual"] = max_bus_res
    out["max_branch_loading_percent"] = max_branch_loading
    out["overloaded_branch_count"] = overloaded
    out["max_gen_bound_violation"] = max_gen_bound
    out["max_storage_power_bound_violation"] = max_storage_power_bound
    out["max_storage_energy_bound_violation"] = max_storage_energy_bound
    out["dcline_max_abs_flow"] = dcline_max_abs
    out["dcline_max_bound_violation"] = dcline_max_viol
    out["dcline_note"] = dcline_note
    return out
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
    result = Dict{String,Any}(
        "scenario" => scenario,
        "mode" => mode_name,
        "status" => status,
        "objective" => (status in _ACTIVE_OK ? JuMP.objective_value(pm.model) : nothing),
        "solve_time_sec" => time() - t0,
        "investment_cost" => nothing,
        "startup_cost" => nothing,
        "shutdown_cost" => nothing,
        "invested_bess_gfm" => nothing,
        "invested_sync_gfm" => nothing,
        "invested_gfl" => nothing,
        "invested_by_bus_carrier" => Dict{Tuple{Int,String},Float64}(),
        "invested_cost_by_bus_carrier" => Dict{Tuple{Int,String},Float64}(),
        "min_margin" => nothing,
        "near_binding" => 0,
        "binding_bus_snapshot" => "n/a",
        "bess_zero_dispatch_online_count" => nothing,
        "gscr_violation_max" => nothing,
        "active_bound_violation_max" => nothing,
        "transition_residual_max" => nothing,
        "n_shared_residual_max" => nothing,
        "investment_recon_residual" => nothing,
        "startup_cost_recon_residual" => nothing,
        "shutdown_cost_recon_residual" => nothing,
        "max_active_balance_residual" => nothing,
        "adequacy_load_peak" => nothing,
        "adequacy_supply_upper_peak" => nothing,
        "adequacy_margin_worst" => nothing,
        "storage_feasibility_ok" => nothing,
        "gscr_reconstruction_residual" => nothing,
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
    investment_cost = 0.0
    invested_bess_gfm = 0.0
    invested_sync_gfm = 0.0
    invested_gfl = 0.0
    min_margin = Inf
    min_bus = first(bus_ids)
    min_nw = first_nw
    near_binding = 0
    bess_zero_dispatch_online_count = 0
    transition_residual_max = 0.0
    active_bound_vmax = 0.0
    gscr_vmax = 0.0
    n_shared_residual_max = 0.0
    max_active_balance_residual = 0.0
    storage_feasibility_ok = true
    for key in device_keys
        d = _PM.ref(pm, first_nw, key[1], key[2])
        bus = key[1] == :gen ? Int(get(d, "gen_bus", -1)) : Int(get(d, "storage_bus", -1))
        carrier = String(get(d, "carrier", ""))
        n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
        n_first = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        dn = n_first - n0
        coeff = float(get(d, "cost_inv_block", 0.0)) * float(get(d, "p_block_max", 0.0))
        investment_cost += coeff * dn
        result["invested_by_bus_carrier"][(bus, carrier)] = get(result["invested_by_bus_carrier"], (bus, carrier), 0.0) + dn
        result["invested_cost_by_bus_carrier"][(bus, carrier)] = get(result["invested_cost_by_bus_carrier"], (bus, carrier), 0.0) + coeff * dn
        if String(get(d, "type", "")) == "gfl"
            invested_gfl += dn
        elseif _is_bess_gfm(d)
            invested_bess_gfm += dn
        elseif _is_sync_gfm(d)
            invested_sync_gfm += dn
        end
        for nw in nws
            n_shared_residual_max = max(n_shared_residual_max, abs(JuMP.value(_PM.var(pm, nw, :n_block, key)) - n_first))
        end
    end
    for nw in nws
        load = sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ids(pm, nw, :load)); init=0.0)
        supply_upper = 0.0
        for g in _PM.ids(pm, nw, :gen)
            gen = _PM.ref(pm, nw, :gen, g)
            supply_upper += float(get(gen, "p_block_max", 0.0)) * JuMP.value(_PM.var(pm, nw, :na_block, (:gen, g)))
        end
        for s in _PM.ids(pm, nw, :storage)
            st = _PM.ref(pm, nw, :storage, s)
            supply_upper += float(get(st, "p_dch_block_max", get(st, "discharge_rating", 0.0))) * JuMP.value(_PM.var(pm, nw, :na_block, (:storage, s)))
            if haskey(_PM.var(pm, nw), :se)
                sev = JuMP.value(_PM.var(pm, nw, :se, s))
                er = float(get(st, "e_block", get(st, "energy_rating", 0.0))) * JuMP.value(_PM.var(pm, nw, :na_block, (:storage, s)))
                if sev < -1e-5 || sev > er + 1e-5
                    storage_feasibility_ok = false
                end
            end
        end
        if haskey(_PM.var(pm, nw), :ps_ne)
            for s in _PM.ids(pm, nw, :ne_storage)
                st = _PM.ref(pm, nw, :ne_storage, s)
                supply_upper += float(get(st, "p_dch_block_max", get(st, "discharge_rating", 0.0))) * JuMP.value(_PM.var(pm, nw, :na_block, (:ne_storage, s)))
            end
        end
        dcline_import = haskey(_PM.ref(pm, nw), :dcline) ? sum((max(0.0, float(get(_PM.ref(pm, nw, :dcline, dc), "pmaxt", 0.0))) for dc in _PM.ids(pm, nw, :dcline)); init=0.0) : 0.0
        supply_upper += dcline_import
        result["adequacy_load_peak"] = max(coalesce(result["adequacy_load_peak"], 0.0), load)
        result["adequacy_supply_upper_peak"] = max(coalesce(result["adequacy_supply_upper_peak"], 0.0), supply_upper)
        margin = supply_upper - load
        result["adequacy_margin_worst"] = isnothing(result["adequacy_margin_worst"]) ? margin : min(result["adequacy_margin_worst"], margin)
        for key in device_keys
            d = _PM.ref(pm, nw, key[1], key[2])
            na = JuMP.value(_PM.var(pm, nw, :na_block, key))
            n = JuMP.value(_PM.var(pm, nw, :n_block, key))
            su = JuMP.value(_PM.var(pm, nw, :su_block, key))
            sd = JuMP.value(_PM.var(pm, nw, :sd_block, key))
            prev = _FP.is_first_id(pm, nw, :hour) ? float(get(d, "na0", 0.0)) : JuMP.value(_PM.var(pm, _FP.prev_id(pm, nw, :hour), :na_block, key))
            startup_cost += float(get(d, "startup_block_cost", 0.0)) * su
            shutdown_cost += float(get(d, "shutdown_block_cost", 0.0)) * sd
            transition_residual_max = max(transition_residual_max, abs((na - prev) - (su - sd)))
            active_bound_vmax = max(active_bound_vmax, max(0.0, -na, na - n))
            if _is_bess_gfm(d) && na > 1.0 + _EPS && _sum_dispatch_abs(pm, nw, key) <= 1e-5
                bess_zero_dispatch_online_count += 1
            end
        end
        pg = haskey(_PM.var(pm, nw), :pg) ? sum((JuMP.value(_PM.var(pm, nw, :pg, g)) for g in _PM.ids(pm, nw, :gen)); init=0.0) : 0.0
        ps = haskey(_PM.var(pm, nw), :ps) ? sum((JuMP.value(_PM.var(pm, nw, :ps, s)) for s in _PM.ids(pm, nw, :storage)); init=0.0) : 0.0
        ps_ne = haskey(_PM.var(pm, nw), :ps_ne) ? sum((JuMP.value(_PM.var(pm, nw, :ps_ne, s)) for s in _PM.ids(pm, nw, :ne_storage)); init=0.0) : 0.0
        max_active_balance_residual = max(max_active_balance_residual, abs(pg - ps - ps_ne - load))
        if haskey(_PM.ref(pm, nw), :g_min)
            for bus in bus_ids
                sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus)
                g_min = _PM.ref(pm, nw, :g_min)
                lhs_gfm = sum(_PM.ref(pm, nw, k[1], k[2], "b_block") * JuMP.value(_PM.var(pm, nw, :na_block, k)) for k in _PM.ref(pm, nw, :bus_gfm_devices, bus); init=0.0)
                rhs = g_min * sum(_PM.ref(pm, nw, k[1], k[2], "p_block_max") * JuMP.value(_PM.var(pm, nw, :na_block, k)) for k in _PM.ref(pm, nw, :bus_gfl_devices, bus); init=0.0)
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
            end
        end
    end
    startup_cost_recon = 0.0
    shutdown_cost_recon = 0.0
    investment_cost_recon = 0.0
    for key in device_keys
        d = _PM.ref(pm, first_nw, key[1], key[2])
        n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
        n_first = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        coeff = float(get(d, "cost_inv_block", 0.0)) * float(get(d, "p_block_max", 0.0))
        investment_cost_recon += coeff * (n_first - n0)
        for nw in nws
            startup_cost_recon += float(get(d, "startup_block_cost", 0.0)) * JuMP.value(_PM.var(pm, nw, :su_block, key))
            shutdown_cost_recon += float(get(d, "shutdown_block_cost", 0.0)) * JuMP.value(_PM.var(pm, nw, :sd_block, key))
        end
    end
    result["investment_cost"] = investment_cost
    result["startup_cost"] = startup_cost
    result["shutdown_cost"] = shutdown_cost
    result["invested_bess_gfm"] = invested_bess_gfm
    result["invested_sync_gfm"] = invested_sync_gfm
    result["invested_gfl"] = invested_gfl
    result["min_margin"] = min_margin
    result["near_binding"] = near_binding
    result["binding_bus_snapshot"] = "bus=$(min_bus), snapshot=$(min_nw)"
    result["bess_zero_dispatch_online_count"] = bess_zero_dispatch_online_count
    result["gscr_violation_max"] = gscr_vmax
    result["active_bound_violation_max"] = active_bound_vmax
    result["transition_residual_max"] = transition_residual_max
    result["n_shared_residual_max"] = n_shared_residual_max
    result["investment_recon_residual"] = abs(investment_cost - investment_cost_recon)
    result["startup_cost_recon_residual"] = abs(startup_cost - startup_cost_recon)
    result["shutdown_cost_recon_residual"] = abs(shutdown_cost - shutdown_cost_recon)
    result["max_active_balance_residual"] = max_active_balance_residual
    result["storage_feasibility_ok"] = storage_feasibility_ok
    result["gscr_reconstruction_residual"] = gscr_vmax
    return result
end

_solve_active(data::Dict{String,Any}, scenario::String, mode_name::String) = _solve_active_with_builder(data, scenario, mode_name, _FP.build_uc_gscr_block_integration)

function _run_mode(raw::Dict{String,Any}, scenario::String, mode_name::String; g_min_value::Float64)
    base_mode = mode_name == "uc_only" ? :uc : :capexp
    data = _prepare_solver_data(raw; mode=base_mode)
    _set_mode_nmax_policy!(data, mode_name)
    _inject_g_min!(data, g_min_value)
    return _solve_active(data, scenario, mode_name)
end

function _schema_audit(raw::Dict{String,Any})
    first_nw = raw["nw"][string(first(_sorted_nw_ids(raw)))]
    buses = get(first_nw, "bus", Dict{String,Any}())
    ac_bus_ids = sort(parse.(Int, [id for (id, b) in buses if lowercase(String(get(b, "carrier", "ac"))) == "ac"]))
    counts = Dict(
        "bus" => length(get(first_nw, "bus", Dict{String,Any}())),
        "branch" => length(get(first_nw, "branch", Dict{String,Any}())),
        "dcline" => length(get(first_nw, "dcline", Dict{String,Any}())) == 0 ? length(_convert_links_to_dcline(first_nw)) : length(get(first_nw, "dcline", Dict{String,Any}())),
        "gen" => length(get(first_nw, "gen", Dict{String,Any}())),
        "storage" => length(get(first_nw, "storage", Dict{String,Any}())),
        "load" => length(get(first_nw, "load", Dict{String,Any}())),
    )
    bess_rows = Dict{String,Any}[]
    sync_bblock_bad = Dict{String,Any}[]
    missing_fields = Dict{String,Any}[]
    invariant_bad = Dict{String,Any}[]
    storage_energy_bad = Dict{String,Any}[]
    gfm_count = 0
    gfl_count = 0
    for (table, id, d) in _iter_block_devices(first_nw)
        t = String(get(d, "type", ""))
        gfm_count += t == "gfm"
        gfl_count += t == "gfl"
        for f in _BLOCK_REQUIRED_FIELDS
            if !haskey(d, f)
                push!(missing_fields, Dict("table" => table, "id" => id, "field" => f))
            end
        end
        na0 = float(get(d, "na0", NaN))
        n0 = float(get(d, "n_block0", NaN))
        nmax = float(get(d, "n_block_max", NaN))
        if !(isfinite(na0) && isfinite(n0) && isfinite(nmax) && 0.0 <= na0 <= n0 <= nmax)
            push!(invariant_bad, Dict("table" => table, "id" => id, "na0" => na0, "n_block0" => n0, "n_block_max" => nmax))
        end
        if table != "gen"
            e = float(get(d, "energy", 0.0))
            er = float(get(d, "energy_rating", get(d, "e_block", 0.0) * max(get(d, "n_block0", 0.0), 1.0)))
            if e < -1e-8 || er < -1e-8 || e > er + 1e-8
                push!(storage_energy_bad, Dict("table" => table, "id" => id, "energy" => e, "energy_rating" => er))
            end
        end
        if _is_bess_gfm(d)
            push!(bess_rows, Dict(
                "table" => table,
                "id" => id,
                "bus" => _device_bus(table, d),
                "b_block" => float(get(d, "b_block", NaN)),
                "n_block0" => float(get(d, "n_block0", NaN)),
                "n_block_max" => float(get(d, "n_block_max", NaN)),
                "na0" => float(get(d, "na0", NaN)),
                "e_block" => float(get(d, "e_block", NaN)),
                "energy_rating" => float(get(d, "energy_rating", NaN)),
                "charge_rating" => float(get(d, "charge_rating", NaN)),
                "discharge_rating" => float(get(d, "discharge_rating", NaN)),
            ))
        end
        if table == "gen" && _is_sync_gfm(d)
            p_block_max = float(get(d, "p_block_max", NaN))
            expected = 5.0 * p_block_max / 100.0
            actual = float(get(d, "b_block", NaN))
            if !(isfinite(expected) && isfinite(actual) && abs(actual - expected) <= 1e-8)
                push!(sync_bblock_bad, Dict("id" => id, "carrier" => String(get(d, "carrier", "")), "expected" => expected, "actual" => actual))
            end
        end
    end
    bess_by_bus = Dict(b => 0 for b in ac_bus_ids)
    for r in bess_rows
        b = Int(r["bus"])
        bess_by_bus[b] = get(bess_by_bus, b, 0) + 1
    end
    missing_bess_buses = [b for b in ac_bus_ids if get(bess_by_bus, b, 0) == 0]
    bus_gmin_in_raw = any(haskey(bus, "g_min") for bus in values(get(first_nw, "bus", Dict{String,Any}())))
    nw_gmin_in_raw = any(haskey(nw, "g_min") for nw in values(raw["nw"]))
    return Dict{String,Any}(
        "multinetwork" => get(raw, "multinetwork", false),
        "snapshot_count" => length(raw["nw"]),
        "counts" => counts,
        "ac_bus_ids" => ac_bus_ids,
        "gfm_count" => gfm_count,
        "gfl_count" => gfl_count,
        "bess_rows" => sort(bess_rows; by=x -> (x["bus"], x["table"], x["id"])),
        "bess_by_bus" => bess_by_bus,
        "missing_bess_buses" => missing_bess_buses,
        "bess_at_every_ac_bus" => isempty(missing_bess_buses),
        "bess_b_block_is_5" => all(abs(r["b_block"] - 5.0) <= 1e-8 for r in bess_rows),
        "sync_b_block_ok" => isempty(sync_bblock_bad),
        "sync_b_block_bad_rows" => sync_bblock_bad,
        "missing_block_fields" => missing_fields,
        "all_block_fields_present" => isempty(missing_fields),
        "invariant_violations" => invariant_bad,
        "invariant_ok" => isempty(invariant_bad),
        "storage_energy_bad" => storage_energy_bad,
        "storage_energy_ok" => isempty(storage_energy_bad),
        "raw_bus_has_gmin" => bus_gmin_in_raw,
        "raw_nw_has_gmin" => nw_gmin_in_raw,
        "g_min_injected_not_converter" => !(bus_gmin_in_raw || nw_gmin_in_raw),
    )
end

function _capacity_reserve_audit(raw::Dict{String,Any})
    rows = Dict{String,Any}[]
    by_carrier = Dict{String,Dict{String,Float64}}()
    for nw_id in _sorted_nw_ids(raw)
        nw = raw["nw"][string(nw_id)]
        load = sum((float(get(l, "pd", 0.0)) for l in values(get(nw, "load", Dict{String,Any}())) if get(l, "status", 1) != 0); init=0.0)
        gen_installed_upper = 0.0
        renewable_upper = 0.0
        min_generation_lower = 0.0
        for g in values(get(nw, "gen", Dict{String,Any}()))
            if !haskey(g, "type")
                continue
            end
            n0 = float(get(g, "n_block0", 0.0))
            nmax = float(get(g, "n_block_max", n0))
            pblk = float(get(g, "p_block_max", 0.0))
            ppu = float(get(g, "p_block_max_pu", 1.0))
            pminblk = float(get(g, "p_block_min", 0.0))
            carrier = String(get(g, "carrier", ""))
            gen_installed_upper += pblk * n0
            min_generation_lower += pminblk * float(get(g, "na0", 0.0))
            if String(get(g, "type", "")) == "gfl"
                renewable_upper += pblk * n0 * max(0.0, ppu)
            end
            c = get!(by_carrier, carrier, Dict{String,Float64}("installed_blockized" => 0.0, "max_expandable" => 0.0))
            c["installed_blockized"] += pblk * n0
            c["max_expandable"] += pblk * nmax
        end
        storage_discharge = 0.0
        for table in ("storage", "ne_storage")
            for st in values(get(nw, table, Dict{String,Any}()))
                if !haskey(st, "type")
                    continue
                end
                n0 = float(get(st, "n_block0", 0.0))
                nmax = float(get(st, "n_block_max", n0))
                pdis = float(get(st, "p_dch_block_max", get(st, "discharge_rating", 0.0)))
                carrier = String(get(st, "carrier", ""))
                storage_discharge += pdis * n0
                c = get!(by_carrier, carrier, Dict{String,Float64}("installed_blockized" => 0.0, "max_expandable" => 0.0))
                c["installed_blockized"] += pdis * n0
                c["max_expandable"] += pdis * nmax
            end
        end
        dclines = get(nw, "dcline", Dict{String,Any}())
        dcline_import = sum((max(0.0, float(get(dc, "pmaxt", 0.0))) for dc in values(dclines) if get(dc, "br_status", 1) != 0); init=0.0)
        dcline_export = sum((max(0.0, float(get(dc, "pmaxf", 0.0))) for dc in values(dclines) if get(dc, "br_status", 1) != 0); init=0.0)
        adequacy_margin = gen_installed_upper + storage_discharge + dcline_import - load
        push!(rows, Dict{String,Any}(
            "snapshot" => nw_id,
            "load" => load,
            "gen_installed_upper" => gen_installed_upper,
            "renewable_upper" => renewable_upper,
            "storage_discharge" => storage_discharge,
            "dcline_import" => dcline_import,
            "dcline_export" => dcline_export,
            "min_generation_lower" => min_generation_lower,
            "adequacy_margin" => adequacy_margin,
        ))
    end
    worst = isempty(rows) ? nothing : argmin([r["adequacy_margin"] for r in rows])
    worst_row = isnothing(worst) ? nothing : rows[worst]
    carrier_rows = Dict{String,Any}[]
    for (carrier, vals) in sort(collect(by_carrier); by=x -> x.first)
        push!(carrier_rows, Dict("carrier" => carrier, "installed_blockized" => vals["installed_blockized"], "max_expandable" => vals["max_expandable"]))
    end
    return Dict{String,Any}("snapshots" => rows, "worst_snapshot" => worst_row, "carrier" => carrier_rows)
end

function _local_gscr_structural_audit(raw::Dict{String,Any})
    data = _prepare_solver_data(raw; mode=:capexp)
    _inject_g_min!(data, 0.0)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _FP.build_uc_gscr_block_integration;
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    nw = first(sort(collect(_FP.nw_ids(pm))))
    rows = Dict{String,Any}[]
    for bus in sort(collect(_PM.ids(pm, nw, :bus)))
        sigma0 = float(_PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus))
        installed_gfm = 0.0
        max_gfm = 0.0
        installed_gfl = 0.0
        max_gfl = 0.0
        bess_nmax = 0.0
        for key in _PM.ref(pm, nw, :bus_gfm_devices, bus)
            d = _PM.ref(pm, nw, key[1], key[2])
            b = float(get(d, "b_block", 0.0))
            n0 = float(get(d, "n_block0", 0.0))
            nmax = float(get(d, "n_block_max", n0))
            installed_gfm += b * n0
            max_gfm += b * nmax
            if _is_bess_gfm(d)
                bess_nmax += nmax
            end
        end
        for key in _PM.ref(pm, nw, :bus_gfl_devices, bus)
            d = _PM.ref(pm, nw, key[1], key[2])
            pblk = float(get(d, "p_block_max", 0.0))
            n0 = float(get(d, "n_block0", 0.0))
            nmax = float(get(d, "n_block_max", n0))
            installed_gfl += pblk * n0
            max_gfl += pblk * nmax
        end
        critical = installed_gfl > _EPS ? (sigma0 + max_gfm) / installed_gfl : Inf
        limiting = isfinite(critical) && critical < 3.0
        push!(rows, Dict{String,Any}(
            "bus" => bus,
            "sigma0_G" => sigma0,
            "installed_gfm_strength" => installed_gfm,
            "max_gfm_strength" => max_gfm,
            "installed_gfl_nameplate" => installed_gfl,
            "max_gfl_nameplate" => max_gfl,
            "critical_g_min_est" => critical,
            "bess_n_block_max" => bess_nmax,
            "limiting" => limiting,
        ))
    end
    return rows
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

function _run_variant(raw::Dict{String,Any}, label::String; g_min::Float64=0.0, mode::String="full_capexp", builder=:standard, mutator=nothing)
    base_mode = mode == "uc_only" ? :uc : :capexp
    data = _prepare_solver_data(raw; mode=base_mode)
    _set_mode_nmax_policy!(data, mode)
    _inject_g_min!(data, g_min)
    if !(mutator === nothing)
        mutator(data)
    end
    try
        bfun = builder == :no_gscr ? _build_uc_block_no_gscr : _FP.build_uc_gscr_block_integration
        r = _solve_active_with_builder(data, "variant", mode, bfun)
        return Dict("label" => label, "status" => r["status"], "objective" => r["objective"], "note" => "")
    catch err
        return Dict("label" => label, "status" => "ERROR", "objective" => nothing, "note" => sprint(showerror, err))
    end
end

function _infeasibility_diagnostics(raw::Dict{String,Any}, opf::Dict{String,Any}, gate_records::Vector{Dict{String,Any}})
    cap = _capacity_reserve_audit(raw)
    min_output_rows = Dict{String,Any}[]
    contributor = Dict{String,Float64}()
    min_load = Inf
    for nw_id in _sorted_nw_ids(raw)
        nw = raw["nw"][string(nw_id)]
        load = sum((float(get(l, "pd", 0.0)) for l in values(get(nw, "load", Dict{String,Any}())) if get(l, "status", 1) != 0); init=0.0)
        forced = 0.0
        for (_, _, d) in _iter_block_devices(nw)
            f = float(get(d, "p_block_min", 0.0)) * float(get(d, "na0", 0.0))
            forced += f
            carr = String(get(d, "carrier", ""))
            contributor[carr] = get(contributor, carr, 0.0) + f
        end
        min_load = min(min_load, load)
        push!(min_output_rows, Dict("snapshot" => nw_id, "forced_min_output" => forced, "load" => load, "overgen_risk" => forced - load))
    end
    storage_candidates = Dict{String,Any}[]
    first_nw = raw["nw"][string(first(_sorted_nw_ids(raw)))]
    for table in ("storage", "ne_storage")
        for (id, st) in get(first_nw, table, Dict{String,Any}())
            if _is_bess_gfm(st)
                push!(storage_candidates, Dict(
                    "table" => table,
                    "id" => id,
                    "bus" => Int(get(st, "storage_bus", -1)),
                    "n_block0" => float(get(st, "n_block0", NaN)),
                    "n_block_max" => float(get(st, "n_block_max", NaN)),
                    "na0" => float(get(st, "na0", NaN)),
                    "e_block" => float(get(st, "e_block", NaN)),
                    "energy_rating" => float(get(st, "energy_rating", NaN)),
                    "charge_rating" => float(get(st, "charge_rating", NaN)),
                    "discharge_rating" => float(get(st, "discharge_rating", NaN)),
                ))
            end
        end
    end
    dcline_count = length(get(first_nw, "dcline", Dict{String,Any}())) == 0 ? length(_convert_links_to_dcline(first_nw)) : length(get(first_nw, "dcline", Dict{String,Any}()))
    invariant_bad = Dict{String,Any}[]
    for (nw_id, nw) in sort(collect(raw["nw"]); by=x -> parse(Int, x.first))
        for (table, id, d) in _iter_block_devices(nw)
            na0 = float(get(d, "na0", NaN))
            n0 = float(get(d, "n_block0", NaN))
            nmax = float(get(d, "n_block_max", NaN))
            pmin = float(get(d, "p_block_min", NaN))
            pmax = float(get(d, "p_block_max", NaN))
            qmin = float(get(d, "q_block_min", NaN))
            qmax = float(get(d, "q_block_max", NaN))
            if !(isfinite(na0) && isfinite(n0) && isfinite(nmax) && 0.0 <= na0 <= n0 <= nmax)
                push!(invariant_bad, Dict("nw" => nw_id, "table" => table, "id" => id, "kind" => "0<=na0<=n0<=nmax"))
            end
            if !(isfinite(pmin) && isfinite(pmax) && pmin <= pmax + 1e-9)
                push!(invariant_bad, Dict("nw" => nw_id, "table" => table, "id" => id, "kind" => "p_block_min<=p_block_max"))
            end
            if !(isfinite(qmin) && isfinite(qmax) && qmin <= qmax + 1e-9)
                push!(invariant_bad, Dict("nw" => nw_id, "table" => table, "id" => id, "kind" => "q_block_min<=q_block_max"))
            end
        end
    end
    variants = Dict{String,Any}[]
    push!(variants, _run_variant(raw, "base full CAPEXP @ g_min=0", g_min=0.0, mode="full_capexp"))
    push!(variants, _run_variant(raw, "without gSCR constraints", g_min=0.0, mode="full_capexp", builder=:no_gscr))
    push!(variants, _run_variant(raw, "BESS-GFM candidates removed", g_min=0.0, mode="full_capexp", mutator=data -> begin
        for nw in values(data["nw"])
            for table in ("storage", "ne_storage")
                keep = Dict{String,Any}()
                for (id, st) in get(nw, table, Dict{String,Any}())
                    if !_is_bess_gfm(st)
                        keep[id] = st
                    end
                end
                nw[table] = keep
            end
        end
    end))
    push!(variants, _run_variant(raw, "storage removed", g_min=0.0, mode="full_capexp", mutator=data -> begin
        for nw in values(data["nw"])
            nw["storage"] = Dict{String,Any}()
            nw["ne_storage"] = Dict{String,Any}()
        end
    end))
    push!(variants, _run_variant(raw, "p_block_min set to 0", g_min=0.0, mode="full_capexp", mutator=data -> begin
        for nw in values(data["nw"])
            for (_, _, d) in _iter_block_devices(nw)
                d["p_block_min"] = 0.0
            end
        end
    end))
    push!(variants, _run_variant(raw, "dclines removed", g_min=0.0, mode="full_capexp", mutator=data -> begin
        for nw in values(data["nw"])
            nw["dcline"] = Dict{String,Any}()
        end
    end))
    first_feasible_variant = nothing
    for v in variants
        if v["status"] in _ACTIVE_OK
            first_feasible_variant = v
            break
        end
    end
    return Dict{String,Any}(
        "opf_status" => opf["status"],
        "gate_statuses" => Dict(r["mode"] => r["status"] for r in gate_records),
        "cap" => cap,
        "min_output_rows" => min_output_rows,
        "min_load" => min_load,
        "min_output_by_carrier" => sort(collect(contributor); by=x -> -x[2]),
        "storage_candidates" => storage_candidates,
        "dcline_count" => dcline_count,
        "invariant_bad" => invariant_bad,
        "variants" => variants,
        "first_feasible_variant" => first_feasible_variant,
    )
end

function _find_record(records::Vector{Dict{String,Any}}, scenario::String, mode::String)
    rows = filter(r -> r["scenario"] == scenario && r["mode"] == mode, records)
    return isempty(rows) ? nothing : only(rows)
end

function _write_report(schema, opf, gate_records, sweep_records, cap_audit, local_gscr, infeas_diag)
    mkpath(dirname(_REPORT_PATH))
    all_records = vcat(gate_records, sweep_records)
    open(_REPORT_PATH, "w") do io
        println(io, "# PyPSA elec_s_37 24h FlexPlan gSCR Study")
        println(io)
        println(io, "Generated by `test/pypsa_elec_s_37_24h_gscr_study.jl` on ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"), ".")
        println(io, "Dataset: `", _CASE_PATH, "`")
        println(io)
        println(io, "## 1) Schema and Data Checks")
        println(io, "- `multinetwork=true`: ", schema["multinetwork"])
        println(io, "- snapshot count: ", schema["snapshot_count"])
        println(io, "- counts (snapshot 1): bus=", schema["counts"]["bus"], ", branch=", schema["counts"]["branch"], ", dcline=", schema["counts"]["dcline"], ", gen=", schema["counts"]["gen"], ", storage=", schema["counts"]["storage"], ", load=", schema["counts"]["load"])
        println(io, "- gfm/gfl in snapshot 1: gfm=", schema["gfm_count"], ", gfl=", schema["gfl_count"])
        println(io, "- BESS-GFM candidates at every AC bus: ", schema["bess_at_every_ac_bus"])
        println(io, "- BESS-GFM b_block = 5: ", schema["bess_b_block_is_5"])
        println(io, "- synchronous b_block = 5*p_block_max/100: ", schema["sync_b_block_ok"])
        println(io, "- required block fields exist: ", schema["all_block_fields_present"])
        println(io, "- invariant 0 <= na0 <= n_block0 <= n_block_max: ", schema["invariant_ok"])
        println(io, "- storage energy bounds valid: ", schema["storage_energy_ok"])
        println(io, "- g_min injected by study (not converter metadata): ", schema["g_min_injected_not_converter"])
        println(io)
        println(io, "| AC bus | BESS-GFM candidates |")
        println(io, "|---:|---:|")
        for b in schema["ac_bus_ids"]
            println(io, "| ", b, " | ", get(schema["bess_by_bus"], b, 0), " |")
        end
        println(io)
        println(io, "## 2) Standard OPF Plausibility")
        println(io, "- status: ", opf["status"])
        println(io, "- objective: ", _fmt(opf["objective"]))
        if get(opf, "available", false)
            println(io, "- system active-power balance residual (max): ", _fmt(opf["max_system_residual"]))
            println(io, "- bus active-power balance residual (max): ", _fmt(opf["max_bus_residual"]))
            println(io, "- max branch loading [%]: ", _fmt(opf["max_branch_loading_percent"]), " (overloaded count=", opf["overloaded_branch_count"], ")")
            println(io, "- dcline flow plausibility: max |flow|=", _fmt(get(opf, "dcline_max_abs_flow", nothing)), ", max bound violation=", _fmt(get(opf, "dcline_max_bound_violation", nothing)))
            if !isempty(String(get(opf, "dcline_note", "")))
                println(io, "- dcline note: ", opf["dcline_note"])
            end
            println(io, "- generator bound violations (max): ", _fmt(opf["max_gen_bound_violation"]))
            println(io, "- storage power bound violations (max): ", _fmt(opf["max_storage_power_bound_violation"]))
            println(io, "- storage energy bound violations (max): ", _fmt(opf["max_storage_energy_bound_violation"]))
        else
            println(io, "- OPF unavailable reason: ", get(opf, "reason", "unknown"))
        end
        println(io)
        println(io, "## 3) Gate 1 - Feasibility at g_min = 0")
        println(io, "| mode | status | objective | investment cost | startup cost | shutdown cost | total load adequacy check (worst margin) | storage feasibility | max active-power balance residual | gSCR reconstruction residual | min gSCR margin |")
        println(io, "|---|---|---:|---:|---:|---:|---:|---|---:|---:|---:|")
        for mode in _MODES
            r = _find_record(gate_records, "gmin_abs_0p0", mode)
            if isnothing(r)
                continue
            end
            println(io, "| ", mode, " | ", r["status"], " | ", _fmt(r["objective"]), " | ", _fmt(r["investment_cost"]), " | ", _fmt(r["startup_cost"]), " | ", _fmt(r["shutdown_cost"]), " | ", _fmt(r["adequacy_margin_worst"]), " | ", r["storage_feasibility_ok"], " | ", _fmt(r["max_active_balance_residual"]), " | ", _fmt(r["gscr_reconstruction_residual"]), " | ", _fmt(r["min_margin"]), " |")
        end
        println(io)
        gate_feasible = any(r["status"] in _ACTIVE_OK for r in gate_records)
        println(io, gate_feasible ? "Decision: at least one mode is feasible at g_min=0. Positive-g_min sweep executed." : "Decision: all modes infeasible at g_min=0. Positive-g_min sweep skipped; infeasibility diagnostics executed.")
        println(io)
        println(io, "## 4) g_min Sweep")
        println(io, "| g_min | mode | status | objective | investment cost | startup cost | shutdown cost | invested BESS-GFM blocks | invested synchronous GFM blocks | invested GFL blocks | min reconstructed gSCR margin | near-binding count | binding bus/snapshot | online BESS-GFM with zero dispatch | reconstruction residual max |")
        println(io, "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|")
        gvals = gate_feasible ? vcat([0.0], _POSITIVE_GMIN_VALUES) : [0.0]
        for g in gvals
            scen = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in _MODES
                r = _find_record(all_records, scen, mode)
                if isnothing(r)
                    continue
                end
                recon_max = maximum([
                    isnothing(r["investment_recon_residual"]) ? NaN : r["investment_recon_residual"],
                    isnothing(r["startup_cost_recon_residual"]) ? NaN : r["startup_cost_recon_residual"],
                    isnothing(r["shutdown_cost_recon_residual"]) ? NaN : r["shutdown_cost_recon_residual"],
                    isnothing(r["transition_residual_max"]) ? NaN : r["transition_residual_max"],
                    isnothing(r["active_bound_violation_max"]) ? NaN : r["active_bound_violation_max"],
                    isnothing(r["gscr_violation_max"]) ? NaN : r["gscr_violation_max"],
                    isnothing(r["n_shared_residual_max"]) ? NaN : r["n_shared_residual_max"],
                ])
                println(io, "| ", _fmt(g), " | ", mode, " | ", r["status"], " | ", _fmt(r["objective"]), " | ", _fmt(r["investment_cost"]), " | ", _fmt(r["startup_cost"]), " | ", _fmt(r["shutdown_cost"]), " | ", _fmt(r["invested_bess_gfm"]), " | ", _fmt(r["invested_sync_gfm"]), " | ", _fmt(r["invested_gfl"]), " | ", _fmt(r["min_margin"]), " | ", r["near_binding"], " | ", r["binding_bus_snapshot"], " | ", _fmt(r["bess_zero_dispatch_online_count"]), " | ", _fmt(recon_max), " |")
            end
        end
        println(io)
        println(io, "### Investment by Bus/Carrier")
        println(io, "| g_min | mode | bus | carrier | invested blocks | investment cost |")
        println(io, "|---:|---|---:|---|---:|---:|")
        for g in gvals
            scen = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in _MODES
                r = _find_record(all_records, scen, mode)
                if isnothing(r) || !(r["status"] in _ACTIVE_OK)
                    continue
                end
                for ((bus, carrier), blocks) in sort(collect(r["invested_by_bus_carrier"]); by=x -> (x[1][1], x[1][2]))
                    if abs(blocks) <= 1e-9
                        continue
                    end
                    cost = get(r["invested_cost_by_bus_carrier"], (bus, carrier), 0.0)
                    println(io, "| ", _fmt(g), " | ", mode, " | ", bus, " | ", carrier, " | ", _fmt(blocks), " | ", _fmt(cost), " |")
                end
            end
        end
        println(io)
        println(io, "## 5) Capacity and Reserve Audits")
        println(io, "| snapshot | total load | blockized installed gen upper | renewable available upper | storage discharge capability | dcline import capability | dcline export capability | minimum generation lower bound | adequacy margin |")
        println(io, "|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in cap_audit["snapshots"]
            println(io, "| ", r["snapshot"], " | ", _fmt(r["load"]), " | ", _fmt(r["gen_installed_upper"]), " | ", _fmt(r["renewable_upper"]), " | ", _fmt(r["storage_discharge"]), " | ", _fmt(r["dcline_import"]), " | ", _fmt(r["dcline_export"]), " | ", _fmt(r["min_generation_lower"]), " | ", _fmt(r["adequacy_margin"]), " |")
        end
        if !isnothing(cap_audit["worst_snapshot"])
            ws = cap_audit["worst_snapshot"]
            println(io)
            println(io, "- worst adequacy margin: snapshot ", ws["snapshot"], " (", _fmt(ws["adequacy_margin"]), ")")
        end
        println(io)
        println(io, "### By Carrier")
        println(io, "| carrier | installed blockized capacity | max expandable capacity |")
        println(io, "|---|---:|---:|")
        for r in cap_audit["carrier"]
            println(io, "| ", r["carrier"], " | ", _fmt(r["installed_blockized"]), " | ", _fmt(r["max_expandable"]), " |")
        end
        println(io)
        println(io, "## 6) Local gSCR Structural Audit")
        println(io, "| bus | sigma0_G | installed GFM strength | max GFM strength | installed GFL nameplate | max GFL nameplate | critical g_min estimate | BESS-GFM n_block_max | structurally limiting |")
        println(io, "|---:|---:|---:|---:|---:|---:|---:|---:|---|")
        for r in local_gscr
            println(io, "| ", r["bus"], " | ", _fmt(r["sigma0_G"]), " | ", _fmt(r["installed_gfm_strength"]), " | ", _fmt(r["max_gfm_strength"]), " | ", _fmt(r["installed_gfl_nameplate"]), " | ", _fmt(r["max_gfl_nameplate"]), " | ", _fmt(r["critical_g_min_est"]), " | ", _fmt(r["bess_n_block_max"]), " | ", r["limiting"], " |")
        end
        println(io)
        if !isnothing(infeas_diag)
            println(io, "## 7) Infeasibility Diagnostics (all g_min=0 modes failed)")
            println(io, "- standard OPF status: ", infeas_diag["opf_status"])
            println(io, "- active block statuses at g_min=0: ")
            for (mode, st) in sort(collect(infeas_diag["gate_statuses"]); by=first)
                println(io, "  - ", mode, ": ", st)
            end
            println(io, "- gSCR cannot be root cause at g_min=0 because RHS is zero by definition.")
            println(io)
            println(io, "### Minimum-Output Audit")
            println(io, "| snapshot | forced minimum output | load | overgeneration risk |")
            println(io, "|---:|---:|---:|---:|")
            for r in infeas_diag["min_output_rows"]
                println(io, "| ", r["snapshot"], " | ", _fmt(r["forced_min_output"]), " | ", _fmt(r["load"]), " | ", _fmt(r["overgen_risk"]), " |")
            end
            println(io, "- minimum load: ", _fmt(infeas_diag["min_load"]))
            println(io, "- top contributors to p_block_min*na0:")
            for (carrier, val) in first(infeas_diag["min_output_by_carrier"], min(length(infeas_diag["min_output_by_carrier"]), 10))
                println(io, "  - ", carrier, ": ", _fmt(val))
            end
            println(io)
            println(io, "### Storage Candidate Consistency (BESS-GFM)")
            println(io, "| table | id | bus | n_block0 | n_block_max | na0 | e_block | energy_rating | charge_rating | discharge_rating |")
            println(io, "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
            for r in infeas_diag["storage_candidates"]
                println(io, "| ", r["table"], " | ", r["id"], " | ", r["bus"], " | ", _fmt(r["n_block0"]), " | ", _fmt(r["n_block_max"]), " | ", _fmt(r["na0"]), " | ", _fmt(r["e_block"]), " | ", _fmt(r["energy_rating"]), " | ", _fmt(r["charge_rating"]), " | ", _fmt(r["discharge_rating"]), " |")
            end
            println(io)
            println(io, "### Dcline/Link Handling")
            println(io, "- dcline count: ", infeas_diag["dcline_count"])
            println(io, "- active integration path uses system-level balance and does not directly model bus-wise dcline balances.")
            println(io)
            println(io, "### Block Data Invariant Audit")
            println(io, "- invariant violations count: ", length(infeas_diag["invariant_bad"]))
            println(io)
            println(io, "### Variant Ladder")
            println(io, "| variant | status | objective | note |")
            println(io, "|---|---|---:|---|")
            for v in infeas_diag["variants"]
                println(io, "| ", v["label"], " | ", v["status"], " | ", _fmt(v["objective"]), " | ", replace(v["note"], "|" => "\\|"), " |")
            end
            fv = infeas_diag["first_feasible_variant"]
            println(io)
            println(io, "- first feasible variant: ", isnothing(fv) ? "none" : fv["label"])
        end
        println(io)
        println(io, "## 8) Interpretation")
        opf_plausible = get(opf, "available", false) && opf["status"] in _ACTIVE_OK && get(opf, "max_system_residual", 1.0) <= 1e-4
        println(io, "- Is OPF physically plausible? ", opf_plausible)
        gate_feasible = any(r["status"] in _ACTIVE_OK for r in gate_records)
        println(io, "- Is active block model feasible at g_min=0? ", gate_feasible)
        if gate_feasible
            uc_infeas_g = nothing
            for g in _POSITIVE_GMIN_VALUES
                r = _find_record(sweep_records, "gmin_abs_$(replace(string(g), "." => "p"))", "uc_only")
                if !isnothing(r) && !(r["status"] in _ACTIVE_OK)
                    uc_infeas_g = g
                    break
                end
            end
            println(io, "- UC-only first infeasible g_min (if any): ", isnothing(uc_infeas_g) ? "not reached up to 3.0" : _fmt(uc_infeas_g))
            full_ok = any(r["mode"] == "full_capexp" && r["status"] in _ACTIVE_OK for r in vcat(gate_records, sweep_records))
            st_ok = any(r["mode"] == "storage_only" && r["status"] in _ACTIVE_OK for r in vcat(gate_records, sweep_records))
            gen_ok = any(r["mode"] == "generator_only" && r["status"] in _ACTIVE_OK for r in vcat(gate_records, sweep_records))
            bess_used = any((r["status"] in _ACTIVE_OK) && !isnothing(r["invested_bess_gfm"]) && abs(r["invested_bess_gfm"]) > 1e-9 for r in vcat(gate_records, sweep_records))
            bess_zero = any((r["status"] in _ACTIVE_OK) && !isnothing(r["bess_zero_dispatch_online_count"]) && r["bess_zero_dispatch_online_count"] > 0 for r in vcat(gate_records, sweep_records))
            bind_expected = any((r["status"] in _ACTIVE_OK) && !isnothing(r["near_binding"]) && r["near_binding"] > 0 for r in vcat(gate_records, sweep_records))
            println(io, "- Does full CAPEXP restore feasibility? ", full_ok)
            println(io, "- Is storage-only sufficient in any run? ", st_ok)
            println(io, "- Is generator-only sufficient in any run? ", gen_ok)
            println(io, "- Are BESS-GFM candidates used? ", bess_used)
            println(io, "- Are BESS-GFM online with zero dispatch? ", bess_zero)
            println(io, "- Is local gSCR binding at expected buses/snapshots? ", bind_expected)
            println(io, "- Should 1week and 2weeks runs be attempted? ", full_ok)
        else
            println(io, "- likely root cause class: ", isnothing(infeas_diag) ? "unknown" : (isnothing(infeas_diag["first_feasible_variant"]) ? "active integration/data mismatch unresolved" : infeas_diag["first_feasible_variant"]["label"]))
            println(io, "- recommended correction before positive-g_min studies: resolve the first feasible variant delta and re-run Gate 1.")
            println(io, "- Should 1week and 2weeks runs be attempted now? false")
        end
    end
    return _REPORT_PATH
end

function main()
    if !isfile(_CASE_PATH)
        error("Dataset not found: $(_CASE_PATH)")
    end
    raw = _load_case()
    schema = _schema_audit(raw)
    opf = _opf_plausibility(_solve_opf(raw))
    gate_records = Dict{String,Any}[]
    for mode in _MODES
        push!(gate_records, _run_mode(raw, "gmin_abs_0p0", mode; g_min_value=_GATE_GMIN))
    end
    gate_feasible = any(r["status"] in _ACTIVE_OK for r in gate_records)
    sweep_records = Dict{String,Any}[]
    infeas_diag = nothing
    if gate_feasible
        for g in _POSITIVE_GMIN_VALUES
            scen = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in _MODES
                push!(sweep_records, _run_mode(raw, scen, mode; g_min_value=g))
            end
        end
    else
        infeas_diag = _infeasibility_diagnostics(raw, opf, gate_records)
    end
    cap_audit = _capacity_reserve_audit(raw)
    local_gscr = _local_gscr_structural_audit(raw)
    report = _write_report(schema, opf, gate_records, sweep_records, cap_audit, local_gscr, infeas_diag)
    println("Wrote report: ", report)
end

main()
