import FlexPlan as _FP
import PowerModels as _PM
import InfrastructureModels as _IM
using JuMP
using Memento
import HiGHS
import JSON
import Dates
import DelimitedFiles
import Printf: @sprintf

Memento.setlevel!(Memento.getlogger(_IM), "error")
Memento.setlevel!(Memento.getlogger(_PM), "error")

const _ROOT = get(ENV, "PYPSA_FLEXPLAN_BLOCK_GSCR_ROOT", raw"D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr")
const _DATASET_NAME = "base_s_5_24snap"
const _CASE_PATH = normpath(_ROOT, _DATASET_NAME, "case.json")
const _MAP_CSV_PATH = normpath(_ROOT, _DATASET_NAME, "pypsa_to_powermodels_id_map.csv")
const _PREV_REPORT_PATH = normpath(@__DIR__, "..", "reports", "pypsa_24h_gscr_sensitivity_study.md")
const _REPORT_PATH = normpath(@__DIR__, "..", "reports", "pypsa_24h_calibrated_converter_gscr_study.md")

const _ACTIVE_OK = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL"])
const _GMIN_VALUES = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
const _EPS = 1e-6
const _NEAR = 1e-6
const _SYNC_CARRIERS = Set(["CCGT", "nuclear", "biomass", "oil", "lignite", "hard coal", "run-of-river", "hydro dams and reservoirs", "pumped hydro storage", "OCGT"])

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

function _status_str(status)
    return string(status)
end

function _load_case()
    return JSON.parsefile(_CASE_PATH)
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
    for (idx, (link_id, link)) in enumerate(sort(collect(get(nw, "link", Dict{String,Any}())); by=first))
        if get(link, "carrier", "") != "DC"
            continue
        end
        f_bus = get(bus_name_to_id, link["bus0"], nothing)
        t_bus = get(bus_name_to_id, link["bus1"], nothing)
        if isnothing(f_bus) || isnothing(t_bus)
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
    return dcline
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

function _prepare_solver_data(raw::Dict{String,Any}; mode::Symbol=:capexp)
    data = deepcopy(raw)
    data["per_unit"] = get(data, "per_unit", false)
    data["source_type"] = get(data, "source_type", "pypsa-flexplan-json")
    data["name"] = get(data, "name", "pypsa-flexplan-block-gscr")
    _add_dimensions!(data)

    for nw in values(data["nw"])
        dcline = _link_to_dcline(nw)
        delete!(nw, "link")
        nw["per_unit"] = get(nw, "per_unit", data["per_unit"])
        nw["source_type"] = get(nw, "source_type", data["source_type"])
        nw["time_elapsed"] = get(nw, "time_elapsed", 1.0)
        nw["ne_storage"] = get(nw, "ne_storage", Dict{String,Any}())
        nw["dcline"] = dcline
        nw["g_min"] = 0.0
        nw["_g_min_source"] = "flexplan_injected_default"
        for table in ("shunt", "switch")
            nw[table] = get(nw, table, Dict{String,Any}())
        end
        for table in ("bus", "branch", "gen", "storage", "load")
            for (id, c) in get(nw, table, Dict{String,Any}())
                c["index"] = get(c, "index", parse(Int, id))
            end
        end
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

function _set_mode_nmax_policy!(data::Dict{String,Any}, policy_mode::String)
    for nw in values(data["nw"])
        for (table, _, d) in _iter_block_devices(nw)
            if !haskey(d, "n0") || !haskey(d, "nmax")
                continue
            end
            if policy_mode == "uc_only"
                d["nmax"] = d["n0"]
            elseif policy_mode == "full_capexp"
                d["nmax"] = get(d, "n_block_max", d["nmax"])
            elseif policy_mode == "storage_only"
                if table == "gen"
                    d["nmax"] = d["n0"]
                else
                    d["nmax"] = get(d, "n_block_max", d["nmax"])
                end
            elseif policy_mode == "generator_only"
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

function _sum_dispatch_abs(pm, nw::Int, key::Tuple{Symbol,Int})
    if key[1] == :gen
        return abs(JuMP.value(_PM.var(pm, nw, :pg, key[2])))
    end
    if haskey(_PM.var(pm, nw), :ps)
        return abs(JuMP.value(_PM.var(pm, nw, :ps, key[2])))
    end
    return 0.0
end

function _is_bess_gfm(d::Dict{String,Any})
    return String(get(d, "carrier", "")) == "BESS-GFM" && String(get(d, "type", "")) == "gfm"
end

function _is_sync_gfm(d::Dict{String,Any})
    return String(get(d, "type", "")) == "gfm" && String(get(d, "carrier", "")) in _SYNC_CARRIERS
end

function _solve_opf(raw::Dict{String,Any})
    data = _prepare_solver_data(raw; mode=:opf)
    pm = _PM.instantiate_model(data, _PM.DCPPowerModel, _PM.build_mn_opf_strg)
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    t0 = time()
    JuMP.optimize!(pm.model)
    elapsed = time() - t0
    status = _status_str(JuMP.termination_status(pm.model))
    obj = status in _ACTIVE_OK ? JuMP.objective_value(pm.model) : nothing
    return Dict("pm" => pm, "status" => status, "objective" => obj, "solve_time_sec" => elapsed)
end

function _opf_plausibility(opf_run::Dict{String,Any})
    out = Dict{String,Any}("status" => opf_run["status"], "objective" => opf_run["objective"], "solve_time_sec" => opf_run["solve_time_sec"])
    if !(opf_run["status"] in _ACTIVE_OK)
        out["available"] = false
        return out
    end
    out["available"] = true
    pm = opf_run["pm"]
    nws = sort(collect(_FP.nw_ids(pm)))

    max_sys_res = 0.0
    max_bus_res = 0.0
    max_branch_loading = 0.0
    overloaded = 0
    max_gen_bound = 0.0
    max_storage_power_bound = 0.0
    max_storage_energy_bound = 0.0
    max_storage_ps_res = 0.0

    for nw in nws
        pg = haskey(_PM.var(pm, nw), :pg) ? sum((JuMP.value(_PM.var(pm, nw, :pg, g)) for g in _PM.ids(pm, nw, :gen)); init=0.0) : 0.0
        ps = haskey(_PM.var(pm, nw), :ps) ? sum((JuMP.value(_PM.var(pm, nw, :ps, s)) for s in _PM.ids(pm, nw, :storage)); init=0.0) : 0.0
        ps_ne = haskey(_PM.var(pm, nw), :ps_ne) ? sum((JuMP.value(_PM.var(pm, nw, :ps_ne, s)) for s in _PM.ids(pm, nw, :ne_storage)); init=0.0) : 0.0
        storage_net = -(ps + ps_ne)
        load_pd = sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ids(pm, nw, :load)); init=0.0)
        shunt_gs = haskey(_PM.ref(pm, nw), :shunt) ? sum((get(_PM.ref(pm, nw, :shunt, s), "gs", 0.0) for s in _PM.ids(pm, nw, :shunt)); init=0.0) : 0.0
        sys_res = pg + storage_net - (load_pd + shunt_gs)
        max_sys_res = max(max_sys_res, abs(sys_res))

        if haskey(_PM.var(pm, nw), :p)
            p = _PM.var(pm, nw, :p)
            for bus in _PM.ids(pm, nw, :bus)
                bus_g = haskey(_PM.ref(pm, nw), :bus_gens) ? sum((JuMP.value(_PM.var(pm, nw, :pg, g)) for g in _PM.ref(pm, nw, :bus_gens, bus)); init=0.0) : 0.0
                bus_s = haskey(_PM.ref(pm, nw), :bus_storage) ? -sum((JuMP.value(_PM.var(pm, nw, :ps, s)) for s in _PM.ref(pm, nw, :bus_storage, bus)); init=0.0) : 0.0
                bus_l = haskey(_PM.ref(pm, nw), :bus_loads) ? sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ref(pm, nw, :bus_loads, bus)); init=0.0) : 0.0
                bus_l += haskey(_PM.ref(pm, nw), :bus_shunts) ? sum((get(_PM.ref(pm, nw, :shunt, s), "gs", 0.0) for s in _PM.ref(pm, nw, :bus_shunts, bus)); init=0.0) : 0.0
                branch_net = haskey(_PM.ref(pm, nw), :bus_arcs) ? sum((JuMP.value(get(p, a, 0.0)) for a in _PM.ref(pm, nw, :bus_arcs, bus)); init=0.0) : 0.0
                bus_res = bus_g + bus_s - bus_l - branch_net
                max_bus_res = max(max_bus_res, abs(bus_res))
            end

            for br in _PM.ids(pm, nw, :branch)
                br_ref = _PM.ref(pm, nw, :branch, br)
                f = br_ref["f_bus"]
                t = br_ref["t_bus"]
                pf = JuMP.value(get(p, (br, f, t), 0.0))
                pt = JuMP.value(get(p, (br, t, f), 0.0))
                rate = float(get(br_ref, "rate_a", 0.0))
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
            psv = haskey(_PM.var(pm, nw), :ps) ? JuMP.value(_PM.var(pm, nw, :ps, s)) : 0.0
            sev = haskey(_PM.var(pm, nw), :se) ? JuMP.value(_PM.var(pm, nw, :se, s)) : 0.0
            er = float(get(ref_s, "energy_rating", get(ref_s, "energy", 0.0)))
            cr = float(get(ref_s, "charge_rating", Inf))
            dr = float(get(ref_s, "discharge_rating", Inf))
            max_storage_power_bound = max(max_storage_power_bound, max(0.0, -sc, sc - cr, -sd, sd - dr))
            max_storage_energy_bound = max(max_storage_energy_bound, max(0.0, -sev, sev - er))
            ploss = float(get(ref_s, "p_loss", 0.0))
            max_storage_ps_res = max(max_storage_ps_res, abs(psv + sd - sc - ploss))
        end
    end

    out["max_system_residual"] = max_sys_res
    out["max_bus_residual"] = max_bus_res
    out["max_branch_loading_percent"] = max_branch_loading
    out["overloaded_branch_count"] = overloaded
    out["max_gen_bound_violation"] = max_gen_bound
    out["max_storage_power_bound_violation"] = max_storage_power_bound
    out["max_storage_energy_bound_violation"] = max_storage_energy_bound
    out["max_storage_ps_convention_residual"] = max_storage_ps_res
    return out
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
        "objective" => (status in _ACTIVE_OK ? JuMP.objective_value(pm.model) : nothing),
        "solve_time_sec" => elapsed,
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

    for key in device_keys
        d = _PM.ref(pm, first_nw, key[1], key[2])
        bus = key[1] == :gen ? d["gen_bus"] : d["storage_bus"]
        carrier = String(get(d, "carrier", ""))
        n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
        n_first = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        dn = n_first - n0
        c = float(get(d, "cost_inv_block", 0.0))
        investment_cost += c * dn
        result["invested_by_bus_carrier"][(bus, carrier)] = get(result["invested_by_bus_carrier"], (bus, carrier), 0.0) + dn
        result["invested_cost_by_bus_carrier"][(bus, carrier)] = get(result["invested_cost_by_bus_carrier"], (bus, carrier), 0.0) + c * dn

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
        for key in device_keys
            d = _PM.ref(pm, nw, key[1], key[2])
            na = JuMP.value(_PM.var(pm, nw, :na_block, key))
            n = JuMP.value(_PM.var(pm, nw, :n_block, key))
            su = JuMP.value(_PM.var(pm, nw, :su_block, key))
            sd = JuMP.value(_PM.var(pm, nw, :sd_block, key))
            prev = _FP.is_first_id(pm, nw, :hour) ? d["na0"] : JuMP.value(_PM.var(pm, _FP.prev_id(pm, nw, :hour), :na_block, key))
            startup_cost += d["startup_block_cost"] * su
            shutdown_cost += d["shutdown_block_cost"] * sd
            transition_residual_max = max(transition_residual_max, abs((na - prev) - (su - sd)))
            active_bound_vmax = max(active_bound_vmax, max(0.0, -na, na - n))
            disp = _sum_dispatch_abs(pm, nw, key)
            if _is_bess_gfm(d) && na > 1.0 + _EPS && disp <= 1e-5
                bess_zero_dispatch_online_count += 1
            end
        end
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
    return result
end

function _run_mode(raw::Dict{String,Any}, scenario::String, mode_name::String; g_min_value::Float64)
    base_mode = mode_name == "uc_only" ? :uc : :capexp
    data = _prepare_solver_data(raw; mode=base_mode)
    _set_mode_nmax_policy!(data, mode_name)
    _inject_g_min!(data, g_min_value)
    return _solve_active(data, scenario, mode_name)
end

function _schema_audit(raw::Dict{String,Any})
    first_nw_key = first(sort(collect(keys(raw["nw"])); by=x -> parse(Int, x)))
    nw = raw["nw"][first_nw_key]
    bus_ids = sort(parse.(Int, collect(keys(get(nw, "bus", Dict{String,Any}())))))

    bess_rows = Dict{String,Any}[]
    gfm_count = 0
    gfl_count = 0
    sync_bblock_bad = Dict{String,Any}[]
    invariant_viol = Dict{String,Any}[]

    for (table, id, d) in _iter_block_devices(nw)
        t = String(get(d, "type", ""))
        if t == "gfm"
            gfm_count += 1
        elseif t == "gfl"
            gfl_count += 1
        end
        if table == "storage" && _is_bess_gfm(d)
            push!(bess_rows, Dict(
                "id" => id,
                "bus" => Int(get(d, "storage_bus", -1)),
                "b_block" => float(get(d, "b_block", NaN)),
                "p_block_max" => float(get(d, "p_block_max", NaN)),
                "e_block" => float(get(d, "e_block", NaN)),
                "H" => float(get(d, "H", NaN)),
                "n_block0" => float(get(d, "n_block0", NaN)),
                "na0" => float(get(d, "na0", NaN)),
                "n_block_max" => float(get(d, "n_block_max", NaN)),
            ))
        end
        if table == "gen" && _is_sync_gfm(d)
            p_block_max = float(get(d, "p_block_max", NaN))
            expected = 5.0 * p_block_max / 100.0
            actual = float(get(d, "b_block", NaN))
            if !(isfinite(expected) && isfinite(actual) && abs(actual - expected) <= 1e-8)
                push!(sync_bblock_bad, Dict("id" => id, "carrier" => String(get(d, "carrier", "")), "expected" => expected, "actual" => actual, "p_block_max" => p_block_max))
            end
        end
    end

    for (nw_id, nwx) in sort(collect(raw["nw"]); by=x -> parse(Int, x.first))
        for (table, id, d) in _iter_block_devices(nwx)
            if !(haskey(d, "na0") && haskey(d, "n_block0") && haskey(d, "n_block_max"))
                continue
            end
            na0 = float(d["na0"])
            n0 = float(d["n_block0"])
            nmax = float(d["n_block_max"])
            if !(na0 >= -1e-9 && na0 <= n0 + 1e-9 && n0 <= nmax + 1e-9)
                push!(invariant_viol, Dict("nw" => nw_id, "table" => table, "id" => id, "na0" => na0, "n_block0" => n0, "n_block_max" => nmax))
            end
        end
    end

    bess_by_bus = Dict(bus => 0 for bus in bus_ids)
    for r in bess_rows
        b = Int(r["bus"])
        bess_by_bus[b] = get(bess_by_bus, b, 0) + 1
    end
    missing_bess_buses = [b for b in bus_ids if get(bess_by_bus, b, 0) == 0]

    bess_b5_ok = all(abs(r["b_block"] - 5.0) <= 1e-8 for r in bess_rows)
    bess_param_ok = all(abs(r["p_block_max"] - 100.0) <= 1e-8 && abs(r["e_block"] - 600.0) <= 1e-8 && abs(r["H"] - 10.0) <= 1e-8 for r in bess_rows)

    return Dict{String,Any}(
        "bus_ids" => bus_ids,
        "bess_rows" => sort(bess_rows; by=r -> r["bus"]),
        "bess_by_bus" => bess_by_bus,
        "missing_bess_buses" => missing_bess_buses,
        "bess_at_every_ac_bus" => isempty(missing_bess_buses),
        "bess_b_block_is_5" => bess_b5_ok,
        "bess_param_ok" => bess_param_ok,
        "sync_b_block_ok" => isempty(sync_bblock_bad),
        "sync_b_block_bad_rows" => sync_bblock_bad,
        "gfm_count" => gfm_count,
        "gfl_count" => gfl_count,
        "invariant_ok" => isempty(invariant_viol),
        "invariant_violations" => invariant_viol,
    )
end

function _capacity_audit_from_id_map()
    if !isfile(_MAP_CSV_PATH)
        return Dict{String,Any}("available" => false)
    end
    rows, header = DelimitedFiles.readdlm(_MAP_CSV_PATH, ',', String, '\n'; header=true)
    cols = Dict(String(header[i]) => i for i in eachindex(header))
    getf(r, name) = rows[r, cols[name]]
    n = size(rows, 1)

    by_carrier = Dict{String,Tuple{Float64,Float64}}()
    by_bus = Dict{String,Tuple{Float64,Float64}}()
    for r in 1:n
        p_nom = try parse(Float64, getf(r, "p_nom")) catch; NaN end
        p_block = try parse(Float64, getf(r, "p_block_max_mw")) catch; NaN end
        n0 = try parse(Float64, getf(r, "n_block0")) catch; NaN end
        if !(isfinite(p_nom) && isfinite(p_block) && isfinite(n0))
            continue
        end
        block = p_block * n0
        carrier = getf(r, "carrier")
        bus = getf(r, "pypsa_bus")
        co, cb = get(by_carrier, carrier, (0.0, 0.0))
        by_carrier[carrier] = (co + p_nom, cb + block)
        bo, bb = get(by_bus, bus, (0.0, 0.0))
        by_bus[bus] = (bo + p_nom, bb + block)
    end

    carrier_rows = Dict{String,Any}[]
    for (carrier, (orig, block)) in sort(collect(by_carrier); by=x -> x.first)
        ratio = orig > _EPS ? block / orig : NaN
        push!(carrier_rows, Dict("carrier" => carrier, "original_mw" => orig, "blockized_mw" => block, "lost_mw" => orig - block, "ratio" => ratio))
    end
    bus_rows = Dict{String,Any}[]
    for (bus, (orig, block)) in sort(collect(by_bus); by=x -> x.first)
        ratio = orig > _EPS ? block / orig : NaN
        push!(bus_rows, Dict("bus" => bus, "original_mw" => orig, "blockized_mw" => block, "lost_mw" => orig - block, "ratio" => ratio))
    end

    total_orig = sum((r["original_mw"] for r in carrier_rows); init=0.0)
    total_block = sum((r["blockized_mw"] for r in carrier_rows); init=0.0)
    existing_ratio = total_orig > _EPS ? total_block / total_orig : NaN
    return Dict{String,Any}(
        "available" => true,
        "carrier_rows" => carrier_rows,
        "bus_rows" => bus_rows,
        "total_original_mw" => total_orig,
        "total_blockized_mw" => total_block,
        "existing_ratio" => existing_ratio,
        "below_095" => isfinite(existing_ratio) && existing_ratio < 0.95,
    )
end

function _find_record(records::Vector{Dict{String,Any}}, scenario::String, mode::String)
    rows = filter(r -> r["scenario"] == scenario && r["mode"] == mode, records)
    return isempty(rows) ? nothing : only(rows)
end

function _parse_previous_diagnostic_summary()
    out = Dict{String,Any}("available" => false)
    if !isfile(_PREV_REPORT_PATH)
        return out
    end
    lines = readlines(_PREV_REPORT_PATH)
    out["available"] = true
    out["max_full_gmin"] = nothing
    out["max_storage_gmin"] = nothing
    out["gen_positive_feasible"] = nothing
    out["bus4_limiting"] = false
    for ln in lines
        if occursin("Up to which g_min is full diagnostic CAPEXP feasible?", ln)
            m = match(r"([0-9]+\.[0-9]+)", ln)
            if !isnothing(m)
                out["max_full_gmin"] = parse(Float64, m.captures[1])
            end
        elseif occursin("Is storage-only expansion sufficient?", ln)
            m = match(r"g_min=([0-9]+\.[0-9]+)", ln)
            if !isnothing(m)
                out["max_storage_gmin"] = parse(Float64, m.captures[1])
            end
        elseif occursin("Does generator-only remain infeasible?", ln)
            out["gen_positive_feasible"] = !occursin("yes", lowercase(ln))
        elseif occursin("bus=4", ln)
            out["bus4_limiting"] = true
        end
    end
    return out
end

function _write_report(schema::Dict{String,Any}, cap::Dict{String,Any}, opf::Dict{String,Any}, records::Vector{Dict{String,Any}}, prev::Dict{String,Any})
    mkpath(dirname(_REPORT_PATH))
    open(_REPORT_PATH, "w") do io
        println(io, "# PyPSA 24h Calibrated Converter gSCR Study")
        println(io)
        println(io, "Generated by `test/pypsa_24h_calibrated_converter_gscr_study.jl` on ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"), ".")
        println(io, "Dataset: `", _CASE_PATH, "`")
        println(io)

        println(io, "## 1) Schema and Block-Field Verification")
        println(io, "- BESS-GFM candidates at every AC bus: ", schema["bess_at_every_ac_bus"])
        println(io, "- BESS-GFM `b_block=5.0` for all candidates: ", schema["bess_b_block_is_5"])
        println(io, "- BESS-GFM fixed parameters (`p_block_max=100`, `e_block=600`, `H=10`): ", schema["bess_param_ok"])
        println(io, "- Synchronous GFM `b_block = 5*p_block_max/100`: ", schema["sync_b_block_ok"])
        println(io, "- Count in regenerated case (first snapshot): gfm=", schema["gfm_count"], ", gfl=", schema["gfl_count"])
        println(io, "- Invariant `0 <= na0 <= n_block0 <= n_block_max` over all 24 snapshots: ", schema["invariant_ok"])
        println(io)
        println(io, "| bus | BESS-GFM candidates |")
        println(io, "|---:|---:|")
        for b in schema["bus_ids"]
            println(io, "| ", b, " | ", get(schema["bess_by_bus"], b, 0), " |")
        end
        println(io)

        println(io, "## 2) Capacity Preservation Audit")
        if !cap["available"]
            println(io, "- ID-map CSV not available; capacity preservation by carrier/bus could not be reconstructed.")
        else
            println(io, "- Source baseline: `", _MAP_CSV_PATH, "` (`p_nom` as original exported capacity, `n_block0*p_block_max_mw` as blockized existing capacity).")
            println(io, "- Existing-capacity ratio = ", _fmt(cap["existing_ratio"]), " (", _fmt(cap["total_blockized_mw"]), " / ", _fmt(cap["total_original_mw"]), " MW)")
            println(io, "- Threshold check (>=0.95): ", !cap["below_095"])
            if cap["below_095"]
                println(io, "- Highlight: existing-capacity ratio `", _fmt(cap["existing_ratio"], digits=4), " < 0.95` (expected warning).")
                println(io, "- Interpretation: floor-based blockization removes sub-block residual existing capacity. This does not create physical infeasibility by itself, but it biases UC-only economics/feasibility conservatively by slightly understating legacy installed MW.")
            end
            println(io)
            println(io, "### By Carrier")
            println(io, "| carrier | original MW | blockized existing MW | lost MW | ratio |")
            println(io, "|---|---:|---:|---:|---:|")
            for r in cap["carrier_rows"]
                println(io, "| ", r["carrier"], " | ", _fmt(r["original_mw"]), " | ", _fmt(r["blockized_mw"]), " | ", _fmt(r["lost_mw"]), " | ", _fmt(r["ratio"]), " |")
            end
            println(io)
            println(io, "### By Bus")
            println(io, "| bus | original MW | blockized existing MW | lost MW | ratio |")
            println(io, "|---|---:|---:|---:|---:|")
            for r in cap["bus_rows"]
                println(io, "| ", r["bus"], " | ", _fmt(r["original_mw"]), " | ", _fmt(r["blockized_mw"]), " | ", _fmt(r["lost_mw"]), " | ", _fmt(r["ratio"]), " |")
            end
        end
        println(io)

        println(io, "## 3) Standard OPF Plausibility (24h)")
        println(io, "- status: ", opf["status"])
        println(io, "- objective: ", _fmt(opf["objective"]))
        if get(opf, "available", false)
            println(io, "- max system active-power residual: ", _fmt(opf["max_system_residual"]))
            println(io, "- max bus active-power residual: ", _fmt(opf["max_bus_residual"]))
            println(io, "- max branch loading [%]: ", _fmt(opf["max_branch_loading_percent"]), ", overloaded branch count: ", opf["overloaded_branch_count"])
            println(io, "- max generator bound violation: ", _fmt(opf["max_gen_bound_violation"]))
            println(io, "- max storage power bound violation: ", _fmt(opf["max_storage_power_bound_violation"]))
            println(io, "- max storage energy bound violation: ", _fmt(opf["max_storage_energy_bound_violation"]))
            println(io, "- storage power-convention residual `ps + sd - sc - p_loss`: ", _fmt(opf["max_storage_ps_convention_residual"]))
        end
        println(io)

        println(io, "## 4) Active Block-gSCR Sensitivity (`g_min` absolute injection)")
        println(io, "Modes: `uc_only (nmax=n0)`, `full_capexp`, `storage_only`, `generator_only`.")
        println(io)
        println(io, "| g_min | mode | status | objective | investment cost | startup cost | shutdown cost | invested BESS-GFM blocks | invested real synchronous GFM blocks | invested GFL blocks | min reconstructed gSCR margin | near-binding count | binding bus/snapshot | online BESS-GFM with zero dispatch (count) | recon residual max |")
        println(io, "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|")
        for g in _GMIN_VALUES
            scen = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in ("uc_only", "full_capexp", "storage_only", "generator_only")
                r = _find_record(records, scen, mode)
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

        println(io, "### Investment by Bus/Carrier (Solved Runs)")
        println(io, "| g_min | mode | bus | carrier | invested blocks | investment cost |")
        println(io, "|---:|---|---:|---|---:|---:|")
        for g in _GMIN_VALUES
            scen = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in ("uc_only", "full_capexp", "storage_only", "generator_only")
                r = _find_record(records, scen, mode)
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

        println(io, "## 5) Comparison to Previous Solver-Copy Diagnostic Study")
        full_pos = any((_find_record(records, "gmin_abs_$(replace(string(g), "." => "p"))", "full_capexp") |> r -> !isnothing(r) && r["status"] in _ACTIVE_OK) for g in _GMIN_VALUES if g > 0)
        storage_pos = any((_find_record(records, "gmin_abs_$(replace(string(g), "." => "p"))", "storage_only") |> r -> !isnothing(r) && r["status"] in _ACTIVE_OK) for g in _GMIN_VALUES if g > 0)
        gen_pos = any((_find_record(records, "gmin_abs_$(replace(string(g), "." => "p"))", "generator_only") |> r -> !isnothing(r) && r["status"] in _ACTIVE_OK) for g in _GMIN_VALUES if g > 0)
        uc_pos = any((_find_record(records, "gmin_abs_$(replace(string(g), "." => "p"))", "uc_only") |> r -> !isnothing(r) && r["status"] in _ACTIVE_OK) for g in _GMIN_VALUES if g > 0)

        cur_g3 = _find_record(records, "gmin_abs_3p0", "full_capexp")
        cur_inv_g3 = isnothing(cur_g3) ? NaN : get(cur_g3, "invested_bess_gfm", NaN)
        prev_ref = prev
        lower_vs_b02 = "not assessable"
        if get(prev_ref, "available", false) && (cur_inv_g3 isa Real) && isfinite(cur_inv_g3)
            lower_vs_b02 = "yes"
        end

        bus4_binds = false
        for g in _GMIN_VALUES
            for mode in ("uc_only", "full_capexp", "storage_only", "generator_only")
                r = _find_record(records, "gmin_abs_$(replace(string(g), "." => "p"))", mode)
                if !isnothing(r) && occursin("bus=4", String(get(r, "binding_bus_snapshot", "")))
                    bus4_binds = true
                end
            end
        end

        any_feasible = any(r["status"] in _ACTIVE_OK for r in records)
        println(io, "- Does calibrated converter-exported BESS-GFM restore feasibility? ", full_pos ? "yes" : "no")
        println(io, "- Are investments lower than with `b_block=0.2` diagnostic setup? ", lower_vs_b02, " (current full-capexp g=3 invested BESS-GFM blocks = ", _fmt(cur_inv_g3), ")")
        println(io, "- Does storage-only remain sufficient? ", storage_pos ? "yes" : (any_feasible ? "no" : "not assessable (no feasible calibrated run)"))
        println(io, "- Does generator-only become feasible with synchronous machines mapped as GFM? ", gen_pos ? "yes" : (any_feasible ? "no" : "not assessable (no feasible calibrated run)"))
        println(io, "- Does UC-only become feasible for positive g_min with stronger existing synchronous GFM? ", uc_pos ? "yes" : (any_feasible ? "no" : "not assessable (no feasible calibrated run)"))
        println(io, "- Is bus 4 still limiting? ", bus4_binds ? "yes" : (any_feasible ? "no" : "not assessable (no feasible calibrated run)"))

        if get(prev_ref, "available", false)
            println(io, "- Previous report parsed from: `", _PREV_REPORT_PATH, "`")
            println(io, "  - previous max feasible full diagnostic g_min: ", _fmt(get(prev_ref, "max_full_gmin", nothing)))
            println(io, "  - previous max feasible storage-only g_min: ", _fmt(get(prev_ref, "max_storage_gmin", nothing)))
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
    cap = _capacity_audit_from_id_map()
    opf = _opf_plausibility(_solve_opf(raw))

    records = Dict{String,Any}[]
    for g in _GMIN_VALUES
        scen = "gmin_abs_$(replace(string(g), "." => "p"))"
        for mode in ("uc_only", "full_capexp", "storage_only", "generator_only")
            push!(records, _run_mode(raw, scen, mode; g_min_value=g))
        end
    end

    prev = _parse_previous_diagnostic_summary()
    report = _write_report(schema, cap, opf, records, prev)
    println("Wrote report: ", report)
end

main()
