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
const _REPORT_PATH = normpath(@__DIR__, "..", "reports", "pypsa_24h_opf_uc_physical_plausibility.md")
const _ACTIVE_OK = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL"])
const _DOC_STATUS = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL", "INFEASIBLE"])

const _TOL_BAL = 1e-6
const _TOL_BUS = 1e-6
const _TOL_BOUND = 1e-6
const _TOL_OBJ = 1e-4
const _TOL_OVERLOAD = 1e-6

const _DEFAULT_INJECTED_GMIN = parse(Float64, get(ENV, "PYPSA_24H_PLAUS_GMIN", "0.5"))

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

function _sorted_nws(pm)
    return sort(collect(_FP.nw_ids(pm)))
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

function _prepare_solver_data(raw::Dict{String,Any}; mode::Symbol=:opf, g_min::Union{Nothing,Float64}=nothing)
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
        nw["g_min"] = isnothing(g_min) ? 0.0 : g_min
        for bus in values(nw["bus"])
            bus["zone"] = get(bus, "zone", 1)
            if !isnothing(g_min)
                bus["g_min"] = g_min
            end
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

function _instantiate(mode::Symbol, data::Dict{String,Any})
    if mode == :opf
        return _PM.instantiate_model(data, _PM.DCPPowerModel, _PM.build_mn_opf_strg)
    end
    return _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _FP.build_uc_gscr_block_integration;
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
end

function _solve_mode(raw::Dict{String,Any}, label::String; mode::Symbol, g_min::Union{Nothing,Float64}=nothing)
    data = _prepare_solver_data(raw; mode=mode, g_min=g_min)
    pm = _instantiate(mode, data)
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    t0 = time()
    JuMP.optimize!(pm.model)
    elapsed = time() - t0
    status = _status_str(JuMP.termination_status(pm.model))
    obj = status in _ACTIVE_OK ? JuMP.objective_value(pm.model) : nothing
    return Dict{String,Any}(
        "label" => label,
        "mode" => String(mode),
        "g_min" => g_min,
        "status" => status,
        "objective" => obj,
        "solve_time_sec" => elapsed,
        "pm" => pm,
    )
end

function _sum_var(var_container)
    return isempty(keys(var_container)) ? 0.0 : sum(JuMP.value(var_container[k]) for k in keys(var_container))
end

function _get_var_value(v, key, default=0.0)
    try
        return JuMP.value(v[key])
    catch
        return default
    end
end

function _poly_or_pwl_gen_cost(pg::Float64, gen::Dict{String,Any})
    model = Int(get(gen, "model", 2))
    cost = get(gen, "cost", [0.0, 0.0])
    if !(cost isa AbstractVector) || isempty(cost)
        return 0.0
    end
    if model == 2
        deg = length(cost) - 1
        val = 0.0
        for (i, c) in enumerate(cost)
            pwr = deg - (i - 1)
            val += float(c) * pg^pwr
        end
        return val
    elseif model == 1 && length(cost) >= 4 && iseven(length(cost))
        pairs = [(float(cost[i]), float(cost[i + 1])) for i in 1:2:length(cost)]
        sort!(pairs; by=x -> x[1])
        if pg <= pairs[1][1]
            return pairs[1][2]
        end
        for i in 2:length(pairs)
            x0, y0 = pairs[i - 1]
            x1, y1 = pairs[i]
            if pg <= x1 + 1e-12
                if abs(x1 - x0) <= 1e-12
                    return y1
                end
                α = (pg - x0) / (x1 - x0)
                return y0 + α * (y1 - y0)
            end
        end
        return pairs[end][2]
    end
    return 0.0
end

function _dispatch_for_key(pm, nw::Int, key::Tuple{Symbol,Int})
    if key[1] == :gen
        return JuMP.value(_PM.var(pm, nw, :pg, key[2]))
    elseif key[1] == :storage
        return haskey(_PM.var(pm, nw), :ps) ? JuMP.value(_PM.var(pm, nw, :ps, key[2])) : 0.0
    else
        return haskey(_PM.var(pm, nw), :ps_ne) ? JuMP.value(_PM.var(pm, nw, :ps_ne, key[2])) : 0.0
    end
end

function _audit_mode(run::Dict{String,Any})
    out = Dict{String,Any}()
    out["label"] = run["label"]
    out["mode"] = run["mode"]
    out["status"] = run["status"]
    out["objective"] = run["objective"]
    out["g_min"] = run["g_min"]
    out["solve_time_sec"] = run["solve_time_sec"]
    if !(run["status"] in _ACTIVE_OK)
        out["available"] = false
        out["reason"] = "infeasible_or_not_optimal"
        return out
    end
    out["available"] = true

    pm = run["pm"]
    nws = _sorted_nws(pm)
    first_nw = first(nws)
    vars_first = _PM.var(pm, first_nw)
    refs_first = _PM.ref(pm, first_nw)

    has_network = haskey(vars_first, :p) && haskey(refs_first, :bus_arcs)
    has_q = haskey(vars_first, :qg) || haskey(vars_first, :q)
    has_vm = haskey(vars_first, :vm)
    has_angles = haskey(vars_first, :va)
    has_blocks = haskey(vars_first, :na_block) && haskey(vars_first, :n_block)
    has_su_sd = haskey(vars_first, :su_block) && haskey(vars_first, :sd_block)

    out["has_network"] = has_network
    out["has_q"] = has_q
    out["has_vm"] = has_vm
    out["has_angles"] = has_angles
    out["has_blocks"] = has_blocks
    out["has_su_sd"] = has_su_sd

    snapshot_rows = Dict{String,Any}[]
    system_res_max = 0.0
    system_res_arg = first_nw
    for nw in nws
        pg = haskey(_PM.var(pm, nw), :pg) ? _sum_var(_PM.var(pm, nw, :pg)) : 0.0
        ps = haskey(_PM.var(pm, nw), :ps) ? _sum_var(_PM.var(pm, nw, :ps)) : 0.0
        ps_ne = haskey(_PM.var(pm, nw), :ps_ne) ? _sum_var(_PM.var(pm, nw, :ps_ne)) : 0.0
        storage_net = -(ps + ps_ne)
        load_pd = sum((get(l, "pd", 0.0) for l in values(get(_PM.ref(pm, nw), :load, Dict{Int,Any}()))); init=0.0)
        shunt_gs = sum((get(s, "gs", 0.0) for s in values(get(_PM.ref(pm, nw), :shunt, Dict{Int,Any}()))); init=0.0)
        load_eff = load_pd + shunt_gs

        dcline_sum = 0.0
        if haskey(_PM.ref(pm, nw), :bus_arcs_dc) && haskey(_PM.var(pm, nw), :p_dc)
            pdc = _PM.var(pm, nw, :p_dc)
            dcline_sum = sum((sum((_get_var_value(pdc, a, 0.0) for a in _PM.ref(pm, nw, :bus_arcs_dc, b)); init=0.0) for b in _PM.ids(pm, nw, :bus)); init=0.0)
        end
        net_dcline_inj = -dcline_sum
        residual = pg + storage_net + net_dcline_inj - load_eff
        if abs(residual) > system_res_max
            system_res_max = abs(residual)
            system_res_arg = nw
        end
        push!(snapshot_rows, Dict{String,Any}(
            "snapshot" => nw,
            "load" => load_eff,
            "generation" => pg,
            "storage_net" => storage_net,
            "dcline_net" => net_dcline_inj,
            "residual" => residual,
        ))
    end
    out["snapshot_balance_rows"] = snapshot_rows
    out["max_system_residual"] = system_res_max
    out["max_system_residual_snapshot"] = system_res_arg
    out["balance_tolerance"] = _TOL_BAL

    if has_q
        out["reactive_note"] = "Reactive variables are present."
    else
        out["reactive_note"] = "Q-balance not checked (active-power-only DCP formulation)."
    end

    bus_rows = Dict{String,Any}[]
    if has_network
        bus_res_count = 0
        bus_res_max = 0.0
        worst_bus = Dict{String,Any}()
        for nw in nws
            p = _PM.var(pm, nw, :p)
            pdc = haskey(_PM.var(pm, nw), :p_dc) ? _PM.var(pm, nw, :p_dc) : nothing
            pg_var = haskey(_PM.var(pm, nw), :pg) ? _PM.var(pm, nw, :pg) : nothing
            ps_var = haskey(_PM.var(pm, nw), :ps) ? _PM.var(pm, nw, :ps) : nothing
            ps_ne_var = haskey(_PM.var(pm, nw), :ps_ne) ? _PM.var(pm, nw, :ps_ne) : nothing
            for bus in sort(collect(_PM.ids(pm, nw, :bus)))
                bus_g = haskey(_PM.ref(pm, nw), :bus_gens) ? sum((_get_var_value(pg_var, g, 0.0) for g in _PM.ref(pm, nw, :bus_gens, bus)); init=0.0) : 0.0
                bus_s = 0.0
                if haskey(_PM.ref(pm, nw), :bus_storage) && !isnothing(ps_var)
                    bus_s += -sum((_get_var_value(ps_var, s, 0.0) for s in _PM.ref(pm, nw, :bus_storage, bus)); init=0.0)
                end
                if haskey(_PM.ref(pm, nw), :bus_storage_ne) && !isnothing(ps_ne_var)
                    bus_s += -sum((_get_var_value(ps_ne_var, s, 0.0) for s in _PM.ref(pm, nw, :bus_storage_ne, bus)); init=0.0)
                end
                bus_l = sum((get(_PM.ref(pm, nw, :load, l), "pd", 0.0) for l in _PM.ref(pm, nw, :bus_loads, bus)); init=0.0)
                bus_l += haskey(_PM.ref(pm, nw), :bus_shunts) ? sum((get(_PM.ref(pm, nw, :shunt, s), "gs", 0.0) for s in _PM.ref(pm, nw, :bus_shunts, bus)); init=0.0) : 0.0
                branch_net = sum((_get_var_value(p, a, 0.0) for a in _PM.ref(pm, nw, :bus_arcs, bus)); init=0.0)
                dcline_net = if !isnothing(pdc) && haskey(_PM.ref(pm, nw), :bus_arcs_dc)
                    sum((_get_var_value(pdc, a, 0.0) for a in _PM.ref(pm, nw, :bus_arcs_dc, bus)); init=0.0)
                else
                    0.0
                end
                res = bus_g + bus_s - bus_l - branch_net - dcline_net
                if abs(res) > _TOL_BUS
                    bus_res_count += 1
                end
                if abs(res) > bus_res_max
                    bus_res_max = abs(res)
                    worst_bus = Dict{String,Any}(
                        "snapshot" => nw,
                        "bus" => bus,
                        "residual" => res,
                        "generation" => bus_g,
                        "storage" => bus_s,
                        "load" => bus_l,
                        "branch_net" => branch_net + dcline_net,
                    )
                end
                push!(bus_rows, Dict{String,Any}(
                    "snapshot" => nw,
                    "bus" => bus,
                    "residual" => res,
                    "generation" => bus_g,
                    "storage" => bus_s,
                    "load" => bus_l,
                    "branch_net" => branch_net + dcline_net,
                ))
            end
        end
        out["max_bus_residual"] = bus_res_max
        out["max_bus_residual_row"] = worst_bus
        out["bus_residual_count_above_tol"] = bus_res_count
        out["worst_bus_rows"] = first(sort(bus_rows; by=r -> -abs(r["residual"])), 10)
    else
        out["max_bus_residual"] = nothing
        out["max_bus_residual_row"] = Dict{String,Any}()
        out["bus_residual_count_above_tol"] = nothing
        out["worst_bus_rows"] = Dict{String,Any}[]
    end

    branch_rows = Dict{String,Any}[]
    if has_network
        max_loading = 0.0
        max_loading_row = Dict{String,Any}()
        overload_count = 0
        sign_mismatch_count = 0
        nearzero_x_highflow_count = 0
        angle_max = 0.0
        for nw in nws
            p = _PM.var(pm, nw, :p)
            va = has_angles ? _PM.var(pm, nw, :va) : nothing
            for br in sort(collect(_PM.ids(pm, nw, :branch)))
                br_ref = _PM.ref(pm, nw, :branch, br)
                f = br_ref["f_bus"]
                t = br_ref["t_bus"]
                af = (br, f, t)
                at = (br, t, f)
                pf = _get_var_value(p, af, 0.0)
                pt = _get_var_value(p, at, 0.0)
                rate = float(get(br_ref, "rate_a", 0.0))
                loading = rate > _TOL_BOUND ? 100.0 * max(abs(pf), abs(pt)) / rate : NaN
                if rate > _TOL_BOUND && loading > 100.0 + 100.0 * _TOL_OVERLOAD
                    overload_count += 1
                end
                if abs(pf + pt) > 1e-5
                    sign_mismatch_count += 1
                end
                x = abs(float(get(br_ref, "br_x", 0.0)))
                if x < 1e-5 && max(abs(pf), abs(pt)) > 1.0
                    nearzero_x_highflow_count += 1
                end
                angle = NaN
                if !isnothing(va)
                    angle = JuMP.value(va[f]) - JuMP.value(va[t]) - float(get(br_ref, "shift", 0.0))
                    angle_max = max(angle_max, abs(angle))
                end
                row = Dict{String,Any}(
                    "snapshot" => nw,
                    "branch" => br,
                    "p_from" => pf,
                    "p_to" => pt,
                    "rate" => rate,
                    "loading_percent" => loading,
                    "angle_diff" => angle,
                )
                push!(branch_rows, row)
                if isfinite(loading) && loading >= max_loading
                    max_loading = loading
                    max_loading_row = row
                end
            end
        end
        out["max_branch_loading_percent"] = max_loading
        out["max_branch_loading_row"] = max_loading_row
        out["overloaded_branch_count"] = overload_count
        out["branch_sign_mismatch_count"] = sign_mismatch_count
        out["nearzero_x_highflow_count"] = nearzero_x_highflow_count
        out["max_abs_angle_diff"] = angle_max
        out["worst_branch_rows"] = first(sort(filter(r -> isfinite(r["loading_percent"]), branch_rows); by=r -> -r["loading_percent"]), 10)
    else
        out["max_branch_loading_percent"] = nothing
        out["max_branch_loading_row"] = Dict{String,Any}()
        out["overloaded_branch_count"] = nothing
        out["branch_sign_mismatch_count"] = nothing
        out["nearzero_x_highflow_count"] = nothing
        out["max_abs_angle_diff"] = nothing
        out["worst_branch_rows"] = Dict{String,Any}[]
    end

    if has_vm
        vm_min = Inf
        vm_max = -Inf
        vm_min_row = Dict{String,Any}()
        vm_max_row = Dict{String,Any}()
        vm_viol = 0
        for nw in nws
            vm = _PM.var(pm, nw, :vm)
            for b in _PM.ids(pm, nw, :bus)
                v = JuMP.value(vm[b])
                bus = _PM.ref(pm, nw, :bus, b)
                vmin = get(bus, "vmin", -Inf)
                vmax = get(bus, "vmax", Inf)
                if v < vm_min
                    vm_min = v
                    vm_min_row = Dict("snapshot" => nw, "bus" => b, "vm" => v)
                end
                if v > vm_max
                    vm_max = v
                    vm_max_row = Dict("snapshot" => nw, "bus" => b, "vm" => v)
                end
                if v < vmin - _TOL_BOUND || v > vmax + _TOL_BOUND
                    vm_viol += 1
                end
            end
        end
        out["vm_min"] = vm_min
        out["vm_max"] = vm_max
        out["vm_min_row"] = vm_min_row
        out["vm_max_row"] = vm_max_row
        out["vm_violations"] = vm_viol
    else
        out["vm_min"] = nothing
        out["vm_max"] = nothing
        out["vm_min_row"] = Dict{String,Any}()
        out["vm_max_row"] = Dict{String,Any}()
        out["vm_violations"] = nothing
    end

    gen_bound_vmax = 0.0
    gen_at_lb = 0
    gen_at_ub = 0
    block_dispatch_vmax = 0.0
    carrier_dispatch_rows = Dict{String,Any}[]
    carrier_gen = Dict{Tuple{Int,String},Float64}()
    carrier_avail = Dict{Tuple{Int,String},Float64}()
    carrier_online = Dict{Tuple{Int,String},Float64}()
    for nw in nws
        pg = haskey(_PM.var(pm, nw), :pg) ? _PM.var(pm, nw, :pg) : nothing
        for g in _PM.ids(pm, nw, :gen)
            gen = _PM.ref(pm, nw, :gen, g)
            pgv = isnothing(pg) ? 0.0 : JuMP.value(pg[g])
            pmax = float(get(gen, "pmax", Inf))
            pmax = haskey(gen, "pmax_pu") ? pmax * float(gen["pmax_pu"]) : pmax
            pmin = float(get(gen, "pmin", -Inf))
            if haskey(gen, "pmin_pu") && haskey(gen, "pmax")
                pmin = max(pmin, float(gen["pmax"]) * float(gen["pmin_pu"]))
            end
            gen_bound_vmax = max(gen_bound_vmax, max(0.0, pmin - pgv, pgv - pmax))
            gen_at_lb += abs(pgv - pmin) <= _TOL_BOUND ? 1 : 0
            gen_at_ub += abs(pgv - pmax) <= _TOL_BOUND ? 1 : 0
            carrier = String(get(gen, "carrier", "unknown"))
            key = (nw, carrier)
            carrier_gen[key] = get(carrier_gen, key, 0.0) + pgv
            carrier_avail[key] = get(carrier_avail, key, 0.0) + (isfinite(pmax) ? pmax : 0.0)
            if has_blocks && haskey(gen, "type")
                na = JuMP.value(_PM.var(pm, nw, :na_block, (:gen, g)))
                carrier_online[key] = get(carrier_online, key, 0.0) + na
                if haskey(gen, "p_block_min") && haskey(gen, "p_block_max")
                    block_dispatch_vmax = max(
                        block_dispatch_vmax,
                        max(0.0, float(gen["p_block_min"]) * na - pgv, pgv - float(gen["p_block_max"]) * na),
                    )
                end
            end
        end
    end
    for ((nw, carrier), genv) in sort(collect(carrier_gen); by=x -> (x[1][1], x[1][2]))
        avail = get(carrier_avail, (nw, carrier), 0.0)
        online = get(carrier_online, (nw, carrier), 0.0)
        push!(carrier_dispatch_rows, Dict{String,Any}(
            "snapshot" => nw,
            "carrier" => carrier,
            "generation" => genv,
            "available_capacity" => avail,
            "online_blocks" => online,
            "unused_capacity" => max(0.0, avail - genv),
        ))
    end
    out["max_gen_bound_violation"] = gen_bound_vmax
    out["gen_at_lb_count"] = gen_at_lb
    out["gen_at_ub_count"] = gen_at_ub
    out["max_block_dispatch_violation"] = block_dispatch_vmax
    out["dispatch_by_carrier_rows"] = carrier_dispatch_rows

    storage_rows = Dict{String,Any}[]
    storage_net_rows = Dict{String,Any}[]
    storage_energy_vmax = 0.0
    storage_p_vmax = 0.0
    storage_ps_conv_vmax = 0.0
    storage_simultaneous_count = 0
    storage_online_zero_dispatch = 0
    for nw in nws
        net_inj = 0.0
        if haskey(_PM.ref(pm, nw), :storage)
            for s in _PM.ids(pm, nw, :storage)
                ref_s = _PM.ref(pm, nw, :storage, s)
                ps = haskey(_PM.var(pm, nw), :ps) ? JuMP.value(_PM.var(pm, nw, :ps, s)) : 0.0
                sc = haskey(_PM.var(pm, nw), :sc) ? JuMP.value(_PM.var(pm, nw, :sc, s)) : 0.0
                sd = haskey(_PM.var(pm, nw), :sd) ? JuMP.value(_PM.var(pm, nw, :sd, s)) : 0.0
                se = haskey(_PM.var(pm, nw), :se) ? JuMP.value(_PM.var(pm, nw, :se, s)) : NaN
                er = float(get(ref_s, "energy_rating", get(ref_s, "energy", 0.0)))
                cr = float(get(ref_s, "charge_rating", Inf))
                dr = float(get(ref_s, "discharge_rating", Inf))
                storage_energy_vmax = max(storage_energy_vmax, isfinite(se) ? max(0.0, -se, se - er) : 0.0)
                storage_p_vmax = max(storage_p_vmax, max(0.0, -sc, sc - cr, -sd, sd - dr))
                ploss = float(get(ref_s, "p_loss", 0.0))
                storage_ps_conv_vmax = max(storage_ps_conv_vmax, abs(ps + sd - sc - ploss))
                storage_simultaneous_count += (sc > _TOL_BOUND && sd > _TOL_BOUND) ? 1 : 0
                if has_blocks && haskey(ref_s, "type")
                    na = JuMP.value(_PM.var(pm, nw, :na_block, (:storage, s)))
                    if na > _TOL_BOUND && abs(ps) <= _TOL_BOUND
                        storage_online_zero_dispatch += 1
                    end
                end
                p_inj = -ps
                net_inj += p_inj
                push!(storage_rows, Dict{String,Any}(
                    "snapshot" => nw,
                    "storage_id" => s,
                    "energy" => se,
                    "energy_rating" => er,
                    "p_injection" => p_inj,
                ))
            end
        end
        push!(storage_net_rows, Dict{String,Any}("snapshot" => nw, "storage_net_injection" => net_inj))
    end
    out["storage_trajectory_rows"] = storage_rows
    out["storage_net_rows"] = storage_net_rows
    out["max_storage_energy_bound_violation"] = storage_energy_vmax
    out["max_storage_charge_discharge_bound_violation"] = storage_p_vmax
    out["max_storage_ps_convention_residual"] = storage_ps_conv_vmax
    out["storage_simultaneous_charge_discharge_count"] = storage_simultaneous_count
    out["storage_online_zero_dispatch_count"] = storage_online_zero_dispatch

    out["online_by_snapshot_rows"] = Dict{String,Any}[]
    out["online_zero_dispatch_count"] = nothing
    out["online_zero_dispatch_examples"] = Dict{String,Any}[]
    out["max_na_bound_violation"] = nothing
    out["startup_shutdown_max_residual"] = nothing
    out["startup_total"] = nothing
    out["shutdown_total"] = nothing
    out["startup_by_carrier"] = Dict{String,Float64}()
    out["shutdown_by_carrier"] = Dict{String,Float64}()
    out["largest_transition_rows"] = Dict{String,Any}[]
    out["fractional_transition_detected"] = false
    out["objective_dispatch_cost"] = 0.0
    out["objective_startup_cost"] = 0.0
    out["objective_shutdown_cost"] = 0.0
    out["objective_investment_cost_requested"] = 0.0
    out["objective_investment_cost_model_coeff"] = 0.0
    out["objective_storage_cost"] = 0.0
    out["objective_reconstructed_requested"] = 0.0
    out["objective_reconstructed_model_coeff"] = 0.0
    out["objective_residual_requested"] = nothing
    out["objective_residual_model_coeff"] = nothing

    dispatch_cost = 0.0
    for nw in nws
        if haskey(_PM.var(pm, nw), :pg_cost)
            dispatch_cost += _sum_var(_PM.var(pm, nw, :pg_cost))
        elseif haskey(_PM.var(pm, nw), :pg)
            for g in _PM.ids(pm, nw, :gen)
                dispatch_cost += _poly_or_pwl_gen_cost(JuMP.value(_PM.var(pm, nw, :pg, g)), _PM.ref(pm, nw, :gen, g))
            end
        end
    end
    storage_cost = 0.0
    for nw in nws
        if haskey(_PM.var(pm, nw), :p_dc_cost)
            storage_cost += _sum_var(_PM.var(pm, nw, :p_dc_cost))
        end
    end
    out["objective_dispatch_cost"] = dispatch_cost
    out["objective_storage_cost"] = storage_cost

    if has_blocks
        online_rows = Dict{String,Any}[]
        online_zero_count = 0
        online_zero_examples = Dict{String,Any}[]
        na_vmax = 0.0
        startup = 0.0
        shutdown = 0.0
        startup_cost = 0.0
        shutdown_cost = 0.0
        inv_requested = 0.0
        inv_model_coeff = 0.0
        transition_max = 0.0
        transition_rows = Dict{String,Any}[]
        startup_by_carrier = Dict{String,Float64}()
        shutdown_by_carrier = Dict{String,Float64}()
        fractional = false
        device_keys = sort(collect(_FP._uc_gscr_block_device_keys(pm, first_nw)); by=x -> (String(x[1]), x[2]))

        for key in device_keys
            dev = _PM.ref(pm, first_nw, key[1], key[2])
            n0 = float(get(dev, "n0", get(dev, "n_block0", 0.0)))
            n_first = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
            inv_requested += float(get(dev, "cost_inv_block", 0.0)) * (n_first - n0)
            inv_model_coeff += float(get(dev, "cost_inv_block", 0.0)) * float(get(dev, "p_block_max", 0.0)) * (n_first - n0)
        end

        for nw in nws
            online_gfm = 0.0
            online_gfl = 0.0
            disp_gfm = 0.0
            disp_gfl = 0.0
            for key in device_keys
                dev = _PM.ref(pm, nw, key[1], key[2])
                carrier = String(get(dev, "carrier", "unknown"))
                na = JuMP.value(_PM.var(pm, nw, :na_block, key))
                n = JuMP.value(_PM.var(pm, nw, :n_block, key))
                su = has_su_sd ? JuMP.value(_PM.var(pm, nw, :su_block, key)) : 0.0
                sd = has_su_sd ? JuMP.value(_PM.var(pm, nw, :sd_block, key)) : 0.0
                p = _dispatch_for_key(pm, nw, key)
                na_vmax = max(na_vmax, max(0.0, -na, na - n))

                if get(dev, "type", "") == "gfm"
                    online_gfm += na
                    disp_gfm += abs(p)
                elseif get(dev, "type", "") == "gfl"
                    online_gfl += na
                    disp_gfl += abs(p)
                end

                if na <= _TOL_BOUND && abs(p) > _TOL_BOUND
                    online_zero_count += 1
                end
                if na > _TOL_BOUND && abs(p) <= _TOL_BOUND
                    online_zero_count += 1
                    if length(online_zero_examples) < 10
                        push!(online_zero_examples, Dict{String,Any}(
                            "snapshot" => nw,
                            "component_key" => string(key),
                            "carrier" => carrier,
                            "type" => get(dev, "type", "n/a"),
                            "na_block" => na,
                            "dispatch" => p,
                            "p_block_max" => get(dev, "p_block_max", NaN),
                            "startup" => su,
                            "shutdown" => sd,
                        ))
                    end
                end

                if has_su_sd
                    prev = _FP.is_first_id(pm, nw, :hour) ? float(get(dev, "na0", 0.0)) : JuMP.value(_PM.var(pm, _FP.prev_id(pm, nw, :hour), :na_block, key))
                    r = (na - prev) - (su - sd)
                    transition_max = max(transition_max, abs(r))
                    push!(transition_rows, Dict{String,Any}("snapshot" => nw, "component_key" => string(key), "abs_transition" => abs(na - prev), "residual" => r))
                    startup += su
                    shutdown += sd
                    startup_cost += float(get(dev, "startup_block_cost", 0.0)) * su
                    shutdown_cost += float(get(dev, "shutdown_block_cost", 0.0)) * sd
                    startup_by_carrier[carrier] = get(startup_by_carrier, carrier, 0.0) + su
                    shutdown_by_carrier[carrier] = get(shutdown_by_carrier, carrier, 0.0) + sd
                    fractional |= abs(su - round(su)) > 1e-6 || abs(sd - round(sd)) > 1e-6
                end
            end
            push!(online_rows, Dict{String,Any}(
                "snapshot" => nw,
                "online_gfm_blocks" => online_gfm,
                "online_gfl_blocks" => online_gfl,
                "dispatch_gfm" => disp_gfm,
                "dispatch_gfl" => disp_gfl,
            ))
        end

        out["online_by_snapshot_rows"] = online_rows
        out["online_zero_dispatch_count"] = online_zero_count
        out["online_zero_dispatch_examples"] = online_zero_examples
        out["max_na_bound_violation"] = na_vmax
        out["startup_shutdown_max_residual"] = transition_max
        out["startup_total"] = startup
        out["shutdown_total"] = shutdown
        out["startup_by_carrier"] = startup_by_carrier
        out["shutdown_by_carrier"] = shutdown_by_carrier
        out["largest_transition_rows"] = first(sort(transition_rows; by=r -> -r["abs_transition"]), 10)
        out["fractional_transition_detected"] = fractional
        out["objective_startup_cost"] = startup_cost
        out["objective_shutdown_cost"] = shutdown_cost
        out["objective_investment_cost_requested"] = inv_requested
        out["objective_investment_cost_model_coeff"] = inv_model_coeff
    end

    out["objective_reconstructed_requested"] =
        out["objective_dispatch_cost"] +
        out["objective_storage_cost"] +
        out["objective_startup_cost"] +
        out["objective_shutdown_cost"] +
        out["objective_investment_cost_requested"]
    out["objective_reconstructed_model_coeff"] =
        out["objective_dispatch_cost"] +
        out["objective_storage_cost"] +
        out["objective_startup_cost"] +
        out["objective_shutdown_cost"] +
        out["objective_investment_cost_model_coeff"]
    out["objective_residual_requested"] =
        isnothing(out["objective"]) ? nothing : (out["objective"] - out["objective_reconstructed_requested"])
    out["objective_residual_model_coeff"] =
        isnothing(out["objective"]) ? nothing : (out["objective"] - out["objective_reconstructed_model_coeff"])

    return out
end

function _status_class(pass_cond::Bool, fail_cond::Bool, unavailable::Bool=false)
    if fail_cond
        return "FAIL"
    elseif unavailable
        return "WARNING"
    elseif pass_cond
        return "PASS"
    else
        return "WARNING"
    end
end

function _classify(audits::Vector{Dict{String,Any}})
    solved = filter(a -> get(a, "available", false), audits)
    classes = Dict{String,String}()

    sys_unavail = isempty(solved)
    sys_fail = any(get(a, "max_system_residual", 0.0) > _TOL_BAL for a in solved)
    classes["system active-power balance"] = _status_class(!sys_fail, sys_fail, sys_unavail)

    bus_data = filter(a -> get(a, "has_network", false), solved)
    bus_unavail = isempty(bus_data) || length(bus_data) < length(solved)
    bus_fail = any(get(a, "max_bus_residual", 0.0) > _TOL_BUS || get(a, "bus_residual_count_above_tol", 0) > 0 for a in bus_data)
    classes["bus active-power balance"] = _status_class(!bus_fail, bus_fail, bus_unavail)

    br_unavail = isempty(bus_data) || length(bus_data) < length(solved)
    br_fail = any(get(a, "overloaded_branch_count", 0) > 0 for a in bus_data)
    classes["branch flows"] = _status_class(!br_fail, br_fail, br_unavail)

    vm_data = filter(a -> get(a, "has_vm", false), solved)
    vm_unavail = isempty(vm_data)
    vm_fail = any(get(a, "vm_violations", 0) > 0 for a in vm_data)
    classes["voltage bounds"] = _status_class(!vm_fail, vm_fail, vm_unavail)

    gen_unavail = isempty(solved)
    gen_fail = any(get(a, "max_gen_bound_violation", 0.0) > _TOL_BOUND for a in solved)
    classes["generator dispatch bounds"] = _status_class(!gen_fail, gen_fail, gen_unavail)

    st_unavail = isempty(solved)
    st_fail = any(get(a, "max_storage_energy_bound_violation", 0.0) > _TOL_BOUND || get(a, "max_storage_charge_discharge_bound_violation", 0.0) > _TOL_BOUND for a in solved)
    classes["storage bounds"] = _status_class(!st_fail, st_fail, st_unavail)

    block_data = filter(a -> get(a, "has_blocks", false), solved)
    block_unavail = isempty(block_data)
    block_fail = any(get(a, "max_na_bound_violation", 0.0) > _TOL_BOUND for a in block_data)
    classes["block online/dispatch consistency"] = _status_class(!block_fail, block_fail, block_unavail)

    su_data = filter(a -> get(a, "has_su_sd", false), solved)
    su_unavail = isempty(su_data)
    su_fail = any(get(a, "startup_shutdown_max_residual", 0.0) > _TOL_BOUND for a in su_data)
    classes["startup/shutdown consistency"] = _status_class(!su_fail, su_fail, su_unavail)

    obj_unavail = isempty(solved)
    obj_fail = any(abs(get(a, "objective_residual_requested", 0.0)) > _TOL_OBJ for a in solved if !isnothing(get(a, "objective_residual_requested", nothing)))
    classes["objective reconstruction"] = _status_class(!obj_fail, obj_fail, obj_unavail)

    opf = findfirst(a -> a["label"] == "standard_opf_24h", audits)
    uc = findfirst(a -> a["label"] == "uc_only_gmin_injected", audits)
    cap = findfirst(a -> a["label"] == "full_capexp_gmin_injected", audits)
    cmp_unavail = isnothing(opf) || isnothing(uc) || isnothing(cap) || !audits[opf]["available"] || (!audits[uc]["available"] && !audits[cap]["available"])
    classes["OPF vs UC comparison"] = cmp_unavail ? "WARNING" : "PASS"

    return classes
end

function _write_table(io, headers::Vector{String}, rows::Vector{Vector{String}})
    println(io, "| ", join(headers, " | "), " |")
    println(io, "|", join(fill("---", length(headers)), "|"), "|")
    for r in rows
        println(io, "| ", join(r, " | "), " |")
    end
end

function _rows_for_snapshot_balance(audit::Dict{String,Any})
    rows = Vector{Vector{String}}()
    for r in audit["snapshot_balance_rows"]
        push!(rows, [string(r["snapshot"]), _fmt(r["load"]), _fmt(r["generation"]), _fmt(r["storage_net"]), _fmt(r["dcline_net"]), _fmt(r["residual"])])
    end
    return rows
end

function _rows_for_bus_worst(audit::Dict{String,Any})
    rows = Vector{Vector{String}}()
    for r in get(audit, "worst_bus_rows", Dict{String,Any}[])
        push!(rows, [string(r["snapshot"]), string(r["bus"]), _fmt(r["residual"]), _fmt(r["generation"]), _fmt(r["storage"]), _fmt(r["load"]), _fmt(r["branch_net"])])
    end
    return rows
end

function _rows_for_branch_worst(audit::Dict{String,Any})
    rows = Vector{Vector{String}}()
    for r in get(audit, "worst_branch_rows", Dict{String,Any}[])
        push!(rows, [string(r["snapshot"]), string(r["branch"]), _fmt(r["p_from"]), _fmt(r["p_to"]), _fmt(r["rate"]), _fmt(r["loading_percent"])])
    end
    return rows
end

function _rows_for_dispatch_carrier(audit::Dict{String,Any})
    rows = Vector{Vector{String}}()
    for r in get(audit, "dispatch_by_carrier_rows", Dict{String,Any}[])
        push!(rows, [string(r["snapshot"]), r["carrier"], _fmt(r["generation"]), _fmt(r["available_capacity"]), _fmt(r["online_blocks"])])
    end
    return rows
end

function _rows_for_storage(audit::Dict{String,Any})
    rows = Vector{Vector{String}}()
    for r in get(audit, "storage_trajectory_rows", Dict{String,Any}[])
        push!(rows, [string(r["snapshot"]), string(r["storage_id"]), _fmt(r["energy"]), _fmt(r["energy_rating"]), _fmt(r["p_injection"])])
    end
    return rows
end

function _write_report(audits::Vector{Dict{String,Any}}, classes::Dict{String,String})
    mkpath(dirname(_REPORT_PATH))
    open(_REPORT_PATH, "w") do io
        println(io, "# PyPSA 24h OPF/UC Physical Plausibility Audit")
        println(io)
        println(io, "Generated by `test/pypsa_24h_opf_uc_physical_plausibility.jl` on ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"), ".")
        println(io, "Dataset: `", _CASE_PATH, "`")
        println(io, "- Formulation unchanged, no new constraints.")
        println(io, "- Not activated: min-up/down, ramping, no-load costs, binary UC, SDP/LMI, or new gSCR formulations.")
        println(io, "- Injected g_min for UC/CAPEXP run: ", _fmt(_DEFAULT_INJECTED_GMIN))
        println(io)

        println(io, "## Run Modes and Solver Status")
        println(io, "| mode | status | objective | solve_time_sec | g_min |")
        println(io, "|---|---|---:|---:|---:|")
        for a in audits
            println(io, "| ", a["label"], " | ", a["status"], " | ", _fmt(a["objective"]), " | ", _fmt(get(a, "solve_time_sec", NaN)), " | ", _fmt(get(a, "g_min", nothing)), " |")
        end
        println(io)

        for a in audits
            println(io, "## Mode: `", a["label"], "`")
            if !get(a, "available", false)
                println(io, "- Status: `", a["status"], "`; detailed physical audit unavailable for infeasible/non-optimal solve.")
                println(io)
                continue
            end
            println(io, "- Max system active-power residual: ", _fmt(a["max_system_residual"]), " at snapshot ", a["max_system_residual_snapshot"], ", tolerance=", _fmt(a["balance_tolerance"]))
            println(io, "- Reactive check: ", a["reactive_note"])
            println(io, "- Max bus residual: ", _fmt(a["max_bus_residual"]), "; bus balances above tolerance: ", get(a, "bus_residual_count_above_tol", "n/a"))
            println(io, "- Max branch loading (%): ", _fmt(a["max_branch_loading_percent"]), "; overloaded branches: ", get(a, "overloaded_branch_count", "n/a"))
            println(io, "- Voltage range check: ", isnothing(a["vm_min"]) ? "not applicable (no voltage-magnitude variables in DCP)." : (_fmt(a["vm_min"]) * " .. " * _fmt(a["vm_max"])))
            println(io, "- Max generator bound violation: ", _fmt(a["max_gen_bound_violation"]))
            println(io, "- Max storage energy bound violation: ", _fmt(a["max_storage_energy_bound_violation"]), ", max storage charge/discharge bound violation: ", _fmt(a["max_storage_charge_discharge_bound_violation"]))
            println(io, "- Max startup/shutdown transition residual: ", _fmt(a["startup_shutdown_max_residual"]))
            println(io, "- Objective residual (requested per-block investment form): ", _fmt(a["objective_residual_requested"]))
            println(io, "- Objective residual (model coefficient form `cost_inv_block*p_block_max`): ", _fmt(a["objective_residual_model_coeff"]))
            println(io)

            println(io, "### A. Snapshot Balance Table")
            _write_table(io, ["snapshot", "load", "generation", "storage_net", "dcline_net", "residual"], _rows_for_snapshot_balance(a))
            println(io)

            println(io, "### B. Worst Bus Balance Residuals")
            if isempty(get(a, "worst_bus_rows", Dict{String,Any}[]))
                println(io, "- Not available for this mode (no bus-level network equations).")
            else
                _write_table(io, ["snapshot", "bus", "residual", "generation", "storage", "load", "branch_net"], _rows_for_bus_worst(a))
            end
            println(io)

            println(io, "### C. Worst Branch Loading")
            if isempty(get(a, "worst_branch_rows", Dict{String,Any}[]))
                println(io, "- Not available for this mode (no branch-flow network equations).")
            else
                _write_table(io, ["snapshot", "branch", "p_from", "p_to", "rate", "loading_percent"], _rows_for_branch_worst(a))
            end
            println(io)

            println(io, "### D. Dispatch by Carrier")
            _write_table(io, ["snapshot", "carrier", "generation", "available_capacity", "online_blocks"], _rows_for_dispatch_carrier(a))
            println(io)

            println(io, "### E. Storage Trajectory")
            _write_table(io, ["snapshot", "storage_id", "energy", "energy_rating", "p_injection"], _rows_for_storage(a))
            println(io)
        end

        println(io, "## F. Objective Decomposition")
        println(io, "| mode | model_objective | reconstructed_objective_requested | reconstructed_objective_model_coeff | dispatch_cost | startup_cost | shutdown_cost | investment_cost_requested | investment_cost_model_coeff | storage_cost | residual_requested | residual_model_coeff |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for a in audits
            if !get(a, "available", false)
                println(io, "| ", a["label"], " | NaN | NaN | NaN | NaN | NaN | NaN | NaN | NaN | NaN | NaN | NaN |")
                continue
            end
            println(io, "| ", a["label"], " | ", _fmt(a["objective"]), " | ", _fmt(a["objective_reconstructed_requested"]), " | ", _fmt(a["objective_reconstructed_model_coeff"]), " | ", _fmt(a["objective_dispatch_cost"]), " | ", _fmt(a["objective_startup_cost"]), " | ", _fmt(a["objective_shutdown_cost"]), " | ", _fmt(a["objective_investment_cost_requested"]), " | ", _fmt(a["objective_investment_cost_model_coeff"]), " | ", _fmt(a["objective_storage_cost"]), " | ", _fmt(a["objective_residual_requested"]), " | ", _fmt(a["objective_residual_model_coeff"]), " |")
        end
        println(io)

        println(io, "## OPF vs UC/gSCR Comparison")
        opf = findfirst(a -> a["label"] == "standard_opf_24h", audits)
        uc = findfirst(a -> a["label"] == "uc_only_gmin_injected", audits)
        cap = findfirst(a -> a["label"] == "full_capexp_gmin_injected", audits)
        if isnothing(opf) || isnothing(uc) || isnothing(cap)
            println(io, "- Missing one or more required modes for comparison.")
        else
            for idx in (opf, uc, cap)
                a = audits[idx]
                println(io, "- ", a["label"], ": objective=", _fmt(a["objective"]), ", max_system_residual=", _fmt(get(a, "max_system_residual", nothing)), ", max_branch_loading=", _fmt(get(a, "max_branch_loading_percent", nothing)))
            end
            println(io, "- UC/CAPEXP integration path uses system-level active balance and does not expose branch/voltage physics; compare branch/voltage plausibility primarily on standard OPF.")
            if !audits[uc]["available"] || !audits[cap]["available"]
                println(io, "- Injected g_min run became infeasible for at least one UC/gSCR mode; dispatch comparison to OPF is limited.")
            end
        end
        println(io)

        println(io, "## Plausibility Classification")
        println(io, "| category | classification |")
        println(io, "|---|---|")
        for k in [
            "system active-power balance",
            "bus active-power balance",
            "branch flows",
            "voltage bounds",
            "generator dispatch bounds",
            "storage bounds",
            "block online/dispatch consistency",
            "startup/shutdown consistency",
            "objective reconstruction",
            "OPF vs UC comparison",
        ]
            println(io, "| ", k, " | ", classes[k], " |")
        end
        println(io)
        println(io, "## Notes")
        println(io, "- Storage simultaneous charge/discharge can occur under relaxed formulations; this is reported as a modeling limitation when detected.")
        println(io, "- Startup/shutdown counts in relaxed UC are continuous block counts, not integer event counts.")
    end
    return _REPORT_PATH
end

@testset "PyPSA 24h OPF/UC physical plausibility audit" begin
    if get(ENV, "RUN_PYPSA_24H_PLAUSIBILITY", "0") != "1"
        @info "Skipping 24h physical plausibility audit; set RUN_PYPSA_24H_PLAUSIBILITY=1 to execute" case=_CASE_PATH
    elseif !isfile(_CASE_PATH)
        @test isfile(_CASE_PATH)
    else
        raw = _load_case()

        runs = Dict{String,Any}[]
        push!(runs, _solve_mode(raw, "standard_opf_24h"; mode=:opf, g_min=nothing))
        push!(runs, _solve_mode(raw, "uc_only_gmin_injected"; mode=:uc, g_min=_DEFAULT_INJECTED_GMIN))
        push!(runs, _solve_mode(raw, "full_capexp_gmin_injected"; mode=:capexp, g_min=_DEFAULT_INJECTED_GMIN))

        # Keep one feasible UC/CAPEXP reference for full plausibility context when injected g_min is infeasible.
        if any(r["status"] ∉ _ACTIVE_OK for r in runs[2:3]) && abs(_DEFAULT_INJECTED_GMIN) > 1e-12
            push!(runs, _solve_mode(raw, "uc_only_reference_gmin0"; mode=:uc, g_min=0.0))
            push!(runs, _solve_mode(raw, "full_capexp_reference_gmin0"; mode=:capexp, g_min=0.0))
        end

        for r in runs
            @test r["status"] in _DOC_STATUS
        end

        audits = [_audit_mode(r) for r in runs]
        classes = _classify(audits)
        report = _write_report(audits, classes)
        @test isfile(report)
    end
end
