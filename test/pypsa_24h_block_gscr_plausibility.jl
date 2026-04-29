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

# Suppress warnings during targeted diagnostics.
Memento.setlevel!(Memento.getlogger(_IM), "error")
Memento.setlevel!(Memento.getlogger(_PM), "error")

const _PYPSA_24H_ROOT = get(
    ENV,
    "PYPSA_FLEXPLAN_BLOCK_GSCR_ROOT",
    raw"D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr",
)
const _PYPSA_24H_DATASET_NAME = "base_s_5_24snap"
const _PYPSA_24H_CASE = normpath(_PYPSA_24H_ROOT, _PYPSA_24H_DATASET_NAME, "case.json")
const _PYPSA_24H_REPORT = normpath(@__DIR__, "..", "reports", "pypsa_24h_block_gscr_plausibility.md")

const _PYPSA_BLOCK_FIELDS = [
    "type",
    "n_block0",
    "n_block_max",
    "na0",
    "p_block_min",
    "p_block_max",
    "q_block_min",
    "q_block_max",
    "H",
    "b_block",
    "cost_inv_block",
    "startup_block_cost",
    "shutdown_block_cost",
]

const _ACTIVE_OK_STATUSES = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL"])
const _DOCUMENTED_STATUSES = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL", "INFEASIBLE"])
const _EPS = 1e-6
const _NEAR_TOL = 1e-6

milp_optimizer = _FP.optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false)

function _status_str(status)
    return string(status)
end

function _dataset_path()
    return _PYPSA_24H_CASE
end

function _load_case()
    return JSON.parsefile(_dataset_path())
end

function _sorted_nw_ids(data::Dict{String,Any})
    return sort(parse.(Int, collect(keys(data["nw"]))))
end

function _block_devices(nw::Dict{String,Any})
    devices = Tuple{String,String,Any}[]
    for table in ("gen", "storage")
        for (id, device) in get(nw, table, Dict{String,Any}())
            if haskey(device, "type")
                push!(devices, (table, id, device))
            end
        end
    end
    return devices
end

function _check_raw_invariants(data::Dict{String,Any})
    violations = Dict{String,Any}[]
    for nw_id in _sorted_nw_ids(data)
        nw = data["nw"][string(nw_id)]
        for table in ("gen", "storage", "ne_storage")
            for (component_id, component) in get(nw, table, Dict{String,Any}())
                if !haskey(component, "type")
                    continue
                end
                na0 = component["na0"]
                n_block0 = component["n_block0"]
                n_block_max = component["n_block_max"]
                if !(0.0 <= na0 <= n_block0 <= n_block_max)
                    push!(violations, Dict{String,Any}(
                        "snapshot" => nw_id,
                        "table" => table,
                        "id" => component_id,
                        "na0" => na0,
                        "n_block0" => n_block0,
                        "n_block_max" => n_block_max,
                    ))
                end
            end
        end
    end
    return violations
end

function _schema_summary(data::Dict{String,Any})
    nw1 = data["nw"]["1"]
    devices = _block_devices(nw1)
    return Dict{String,Any}(
        "multinetwork" => get(data, "multinetwork", false),
        "snapshots" => length(data["nw"]),
        "bus_count" => length(get(nw1, "bus", Dict{String,Any}())),
        "branch_count" => length(get(nw1, "branch", Dict{String,Any}())),
        "gen_count" => length(get(nw1, "gen", Dict{String,Any}())),
        "storage_count" => length(get(nw1, "storage", Dict{String,Any}())),
        "gfl_count" => count(d -> d[3]["type"] == "gfl", devices),
        "gfm_count" => count(d -> d[3]["type"] == "gfm", devices),
        "all_block_fields_present" => all(all(haskey(d[3], f) for f in _PYPSA_BLOCK_FIELDS) for d in devices),
    )
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

function _add_dimensions!(data::Dict{String,Any})
    snapshots = length(data["nw"])
    if !haskey(data, "dim")
        _FP.add_dimension!(data, :hour, snapshots)
        _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
        _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    end
    return data
end

function _prepare_solver_data(raw_data::Dict{String,Any}; mode::Symbol=:opf)
    data = deepcopy(raw_data)
    data["per_unit"] = get(data, "per_unit", false)
    data["source_type"] = get(data, "source_type", "pypsa-flexplan-json")
    data["name"] = get(data, "name", "pypsa-flexplan-block-gscr")
    _add_dimensions!(data)

    total_links = 0
    total_converted_links = 0
    total_skipped_links = 0
    total_ignored_links = 0

    for nw in values(data["nw"])
        total_links += length(get(nw, "link", Dict{String,Any}()))
        dcline, skipped_links, ignored_links = _link_to_dcline(nw)
        total_converted_links += length(dcline)
        total_skipped_links += skipped_links
        total_ignored_links += ignored_links
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
            for (id, component) in get(nw, table, Dict{String,Any}())
                component["index"] = get(component, "index", parse(Int, id))
            end
        end

        nw["g_min"] = maximum(get(bus, "g_min", 0.0) for bus in values(nw["bus"]))

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
                if !(0.0 <= gen["na0"] <= gen["n_block0"] <= gen["n_block_max"])
                    error("Invariant violation in solver adapter for gen $(gen["index"]).")
                end
                gen["n0"] = gen["n_block0"]
                gen["nmax"] = mode == :uc ? gen["n0"] : gen["n_block_max"]
            end
        end

        for storage in values(nw["storage"])
            if haskey(storage, "n_block0")
                if !(0.0 <= storage["na0"] <= storage["n_block0"] <= storage["n_block_max"])
                    error("Invariant violation in solver adapter for storage $(storage["index"]).")
                end
                storage["n0"] = storage["n_block0"]
                storage["nmax"] = mode == :uc ? storage["n0"] : storage["n_block_max"]
            end
            storage["r"] = get(storage, "r", 0.0)
            storage["x"] = get(storage, "x", 0.0)
            storage["p_loss"] = get(storage, "p_loss", 0.0)
            storage["q_loss"] = get(storage, "q_loss", 0.0)
            storage["stationary_energy_inflow"] = get(storage, "stationary_energy_inflow", 0.0)
            storage["stationary_energy_outflow"] = get(storage, "stationary_energy_outflow", 0.0)
            storage["thermal_rating"] = get(storage, "thermal_rating", max(get(storage, "charge_rating", 0.0), get(storage, "discharge_rating", 0.0), 1.0))
            storage["qmin"] = get(storage, "qmin", get(storage, "q_block_min", -1.0))
            storage["qmax"] = get(storage, "qmax", get(storage, "q_block_max", 1.0))
            storage["energy_rating"] = get(storage, "energy_rating", get(storage, "energy", 1.0))
            storage["max_energy_absorption"] = get(storage, "max_energy_absorption", Inf)
            storage["self_discharge_rate"] = get(storage, "self_discharge_rate", 0.0)
        end
    end

    data["_pypsa_link_count"] = total_links
    data["_pypsa_dcline_count"] = total_converted_links
    data["_pypsa_skipped_link_count"] = total_skipped_links
    data["_pypsa_ignored_link_count"] = total_ignored_links
    return data
end

function _instantiate_standard_opf(data::Dict{String,Any})
    return _PM.instantiate_model(data, _PM.DCPPowerModel, _PM.build_mn_opf_strg)
end

function _build_active_pm(data::Dict{String,Any})
    return _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _FP.build_uc_gscr_block_integration;
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
end

function _safe_objective(model::JuMP.Model)
    status = JuMP.termination_status(model)
    if status in (JuMP.MOI.OPTIMAL, JuMP.MOI.LOCALLY_SOLVED, JuMP.MOI.ALMOST_OPTIMAL)
        return JuMP.objective_value(model)
    end
    return nothing
end

function _device_bus_id(pm, nw::Int, key::Tuple{Symbol,Int})
    dev = _PM.ref(pm, nw, key[1], key[2])
    if key[1] == :gen
        return dev["gen_bus"]
    else
        return dev["storage_bus"]
    end
end

function _sum_dispatch_abs(pm, nw::Int, key::Tuple{Symbol,Int})
    if key[1] == :gen
        return abs(JuMP.value(_PM.var(pm, nw, :pg, key[2])))
    end
    has_ps = haskey(_PM.var(pm, nw), :ps)
    has_sc = haskey(_PM.var(pm, nw), :sc)
    has_sd = haskey(_PM.var(pm, nw), :sd)
    if has_ps
        ps = _PM.var(pm, nw, :ps)
        if key[2] in axes(ps, 1)
            return abs(JuMP.value(ps[key[2]]))
        end
    end
    if has_sc && has_sd
        sc = _PM.var(pm, nw, :sc)
        sd = _PM.var(pm, nw, :sd)
        if key[2] in axes(sc, 1) && key[2] in axes(sd, 1)
            return abs(JuMP.value(sc[key[2]])) + abs(JuMP.value(sd[key[2]]))
        end
    end
    return 0.0
end

function _solve_standard_opf_metrics(raw::Dict{String,Any})
    data = _prepare_solver_data(raw; mode=:opf)
    pm = _instantiate_standard_opf(data)
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)

    t0 = time()
    JuMP.optimize!(pm.model)
    elapsed = time() - t0

    status = _status_str(JuMP.termination_status(pm.model))
    objective = _safe_objective(pm.model)

    storage_violations = Dict{String,Any}[]
    if status in _ACTIVE_OK_STATUSES
        for nw in _FP.nw_ids(pm)
            if haskey(_PM.var(pm, nw), :se)
                for storage_id in _PM.ids(pm, nw, :storage)
                    storage = _PM.ref(pm, nw, :storage, storage_id)
                    se = JuMP.value(_PM.var(pm, nw, :se, storage_id))
                    sc = haskey(_PM.var(pm, nw), :sc) ? JuMP.value(_PM.var(pm, nw, :sc, storage_id)) : 0.0
                    sd = haskey(_PM.var(pm, nw), :sd) ? JuMP.value(_PM.var(pm, nw, :sd, storage_id)) : 0.0
                    if se < -_EPS || se > storage["energy_rating"] + _EPS || sc < -_EPS || sc > storage["charge_rating"] + _EPS || sd < -_EPS || sd > storage["discharge_rating"] + _EPS
                        push!(storage_violations, Dict{String,Any}(
                            "nw" => nw,
                            "storage" => storage_id,
                            "se" => se,
                            "sc" => sc,
                            "sd" => sd,
                        ))
                    end
                end
            end
        end
    end

    return Dict{String,Any}(
        "status" => status,
        "objective" => objective,
        "solve_time_sec" => elapsed,
        "feasible" => status in _ACTIVE_OK_STATUSES,
        "storage_bounds_consistent" => isempty(storage_violations),
        "storage_bound_violations" => storage_violations,
        "mode" => "full",
    )
end

function _solve_active_metrics(raw::Dict{String,Any}; mode::Symbol)
    data = _prepare_solver_data(raw; mode=mode)
    pm = _build_active_pm(data)
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)

    t0 = time()
    JuMP.optimize!(pm.model)
    elapsed = time() - t0

    status = _status_str(JuMP.termination_status(pm.model))
    objective = _safe_objective(pm.model)

    metrics = Dict{String,Any}(
        "status" => status,
        "objective" => objective,
        "solve_time_sec" => elapsed,
        "mode" => String(mode),
        "startup_cost" => nothing,
        "shutdown_cost" => nothing,
        "startup_count" => nothing,
        "shutdown_count" => nothing,
        "investment_cost" => nothing,
        "investment_cost_with_pmax" => nothing,
        "min_gscr_margin" => nothing,
        "min_gscr_margin_nw" => nothing,
        "min_gscr_margin_bus" => nothing,
        "near_binding_count" => 0,
        "transition_max_residual" => nothing,
        "gscr_max_violation" => nothing,
        "active_bound_max_violation" => nothing,
        "n_shared_max_residual" => nothing,
        "online_gfl_by_snapshot" => Dict{Int,Float64}(),
        "online_gfm_by_snapshot" => Dict{Int,Float64}(),
        "online_total_by_snapshot" => Dict{Int,Float64}(),
        "gfl_dispatch_abs_by_snapshot" => Dict{Int,Float64}(),
        "gfm_dispatch_abs_by_snapshot" => Dict{Int,Float64}(),
        "invested_gfl_blocks" => nothing,
        "invested_gfm_blocks" => nothing,
        "investment_by_carrier" => Dict{String,Float64}(),
        "investment_by_bus" => Dict{Int,Float64}(),
        "suspicious_snapshots" => Int[],
        "near_zero_dispatch_online_examples" => String[],
        "rapid_oscillation_devices" => String[],
    )

    if !(status in _ACTIVE_OK_STATUSES)
        return metrics
    end

    nws = sort(collect(_FP.nw_ids(pm)))
    first_nw = first(nws)
    keys = sort(collect(_FP._uc_gscr_block_device_keys(pm, first_nw)); by=x -> (String(x[1]), x[2]))

    startup_cost = 0.0
    shutdown_cost = 0.0
    startup_count = 0.0
    shutdown_count = 0.0
    investment_cost = 0.0
    investment_cost_with_pmax = 0.0
    invested_gfl = 0.0
    invested_gfm = 0.0
    transition_max_residual = 0.0
    gscr_max_violation = 0.0
    active_bound_max_violation = 0.0
    n_shared_max_residual = 0.0
    min_margin = Inf
    min_margin_nw = first_nw
    min_margin_bus = first(_PM.ids(pm, first_nw, :bus))
    near_binding_count = 0

    per_key_na = Dict{Tuple{Symbol,Int},Vector{Float64}}(key => Float64[] for key in keys)

    for key in keys
        dev = _PM.ref(pm, first_nw, key[1], key[2])
        n_first = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        inv_delta = n_first - dev["n0"]
        investment_cost += dev["cost_inv_block"] * inv_delta
        investment_cost_with_pmax += dev["cost_inv_block"] * dev["p_block_max"] * inv_delta

        if dev["type"] == "gfl"
            invested_gfl += inv_delta
        elseif dev["type"] == "gfm"
            invested_gfm += inv_delta
        end

        carrier = String(get(dev, "carrier", "unknown"))
        metrics["investment_by_carrier"][carrier] = get(metrics["investment_by_carrier"], carrier, 0.0) + inv_delta
        bus_id = _device_bus_id(pm, first_nw, key)
        metrics["investment_by_bus"][bus_id] = get(metrics["investment_by_bus"], bus_id, 0.0) + inv_delta

        for nw in nws
            n_nw = JuMP.value(_PM.var(pm, nw, :n_block, key))
            n_shared_max_residual = max(n_shared_max_residual, abs(n_nw - n_first))
        end
    end

    for nw in nws
        online_gfl = 0.0
        online_gfm = 0.0
        online_total = 0.0
        dispatch_gfl = 0.0
        dispatch_gfm = 0.0

        for key in keys
            dev = _PM.ref(pm, nw, key[1], key[2])
            n_val = JuMP.value(_PM.var(pm, nw, :n_block, key))
            na_val = JuMP.value(_PM.var(pm, nw, :na_block, key))
            su_val = JuMP.value(_PM.var(pm, nw, :su_block, key))
            sd_val = JuMP.value(_PM.var(pm, nw, :sd_block, key))
            prev_na = _FP.is_first_id(pm, nw, :hour) ? dev["na0"] : JuMP.value(_PM.var(pm, _FP.prev_id(pm, nw, :hour), :na_block, key))

            startup_cost += dev["startup_block_cost"] * su_val
            shutdown_cost += dev["shutdown_block_cost"] * sd_val
            startup_count += su_val
            shutdown_count += sd_val

            transition_residual = abs((na_val - prev_na) - (su_val - sd_val))
            transition_max_residual = max(transition_max_residual, transition_residual)
            active_bound_max_violation = max(active_bound_max_violation, max(0.0, -na_val, na_val - n_val))

            if dev["type"] == "gfl"
                online_gfl += na_val
                dispatch_gfl += _sum_dispatch_abs(pm, nw, key)
            elseif dev["type"] == "gfm"
                online_gfm += na_val
                dispatch_gfm += _sum_dispatch_abs(pm, nw, key)
            end
            online_total += na_val

            if na_val > 1.0 + _EPS && _sum_dispatch_abs(pm, nw, key) <= 1e-5 && length(metrics["near_zero_dispatch_online_examples"]) < 15
                push!(metrics["near_zero_dispatch_online_examples"], "nw=$(nw) key=$(key) na_block=$(round(na_val, digits=6)) dispatch_abs=$(round(_sum_dispatch_abs(pm, nw, key), digits=6))")
            end

            push!(per_key_na[key], na_val)
        end

        metrics["online_gfl_by_snapshot"][nw] = online_gfl
        metrics["online_gfm_by_snapshot"][nw] = online_gfm
        metrics["online_total_by_snapshot"][nw] = online_total
        metrics["gfl_dispatch_abs_by_snapshot"][nw] = dispatch_gfl
        metrics["gfm_dispatch_abs_by_snapshot"][nw] = dispatch_gfm

        for bus_id in sort(collect(_PM.ids(pm, nw, :bus)))
            sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus_id)
            g_min = _PM.ref(pm, nw, :g_min)
            lhs = sigma0 + sum(
                _PM.ref(pm, nw, key[1], key[2], "b_block") * JuMP.value(_PM.var(pm, nw, :na_block, key))
                for key in _PM.ref(pm, nw, :bus_gfm_devices, bus_id);
                init=0.0,
            )
            rhs = g_min * sum(
                _PM.ref(pm, nw, key[1], key[2], "p_block_max") * JuMP.value(_PM.var(pm, nw, :na_block, key))
                for key in _PM.ref(pm, nw, :bus_gfl_devices, bus_id);
                init=0.0,
            )
            margin = lhs - rhs
            if margin < min_margin
                min_margin = margin
                min_margin_nw = nw
                min_margin_bus = bus_id
            end
            if margin <= _NEAR_TOL
                near_binding_count += 1
            end
            gscr_max_violation = max(gscr_max_violation, max(0.0, -margin))
        end

        if gscr_max_violation > _EPS || active_bound_max_violation > _EPS
            push!(metrics["suspicious_snapshots"], nw)
        end
    end

    for key in keys
        deltas = [per_key_na[key][i] - per_key_na[key][i - 1] for i in 2:length(per_key_na[key])]
        sign_changes = 0
        for i in 2:length(deltas)
            if abs(deltas[i]) > _EPS && abs(deltas[i - 1]) > _EPS && sign(deltas[i]) != sign(deltas[i - 1])
                sign_changes += 1
            end
        end
        if sign_changes >= 3
            push!(metrics["rapid_oscillation_devices"], "$(key) sign_changes=$(sign_changes)")
        end
    end

    metrics["startup_cost"] = startup_cost
    metrics["shutdown_cost"] = shutdown_cost
    metrics["startup_count"] = startup_count
    metrics["shutdown_count"] = shutdown_count
    metrics["investment_cost"] = investment_cost
    metrics["investment_cost_with_pmax"] = investment_cost_with_pmax
    metrics["invested_gfl_blocks"] = invested_gfl
    metrics["invested_gfm_blocks"] = invested_gfm
    metrics["min_gscr_margin"] = min_margin
    metrics["min_gscr_margin_nw"] = min_margin_nw
    metrics["min_gscr_margin_bus"] = min_margin_bus
    metrics["near_binding_count"] = near_binding_count
    metrics["transition_max_residual"] = transition_max_residual
    metrics["gscr_max_violation"] = gscr_max_violation
    metrics["active_bound_max_violation"] = active_bound_max_violation
    metrics["n_shared_max_residual"] = n_shared_max_residual

    return metrics
end

function _fmt_num(x; digits::Int=6)
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

function _write_report(
    schema::Dict{String,Any},
    invariant_violations,
    opf::Dict{String,Any},
    uc::Dict{String,Any},
    cap::Dict{String,Any},
)
    mkpath(dirname(_PYPSA_24H_REPORT))

    comparison_3snap_margin = 0.8
    comparison_6snap_margin = 0.235571

    open(_PYPSA_24H_REPORT, "w") do io
        println(io, "# PyPSA 24h Block-gSCR Plausibility")
        println(io)
        println(io, "Generated by `test/pypsa_24h_block_gscr_plausibility.jl` on ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"), ".")
        println(io)
        println(io, "## Dataset and Modes")
        println(io, "- Dataset path: `", _dataset_path(), "`")
        println(io, "- Modes run: load/schema, standard OPF sanity, active UC/gSCR (`nmax=n0`), active CAPEXP/gSCR (`nmax>n0` where available).")
        println(io, "- Active formulation used: `n_block`, `na_block`, `su_block`, `sd_block`, block-scaled dispatch/storage constraints, block investment cost, startup/shutdown block-count costs, AC-side Gershgorin gSCR constraint.")
        println(io)

        println(io, "## Pre-Run Implementation Summary")
        println(io, "- 24h dataset loading follows the existing acceptance path: `JSON.parsefile(...)` and multinetwork access via `data[\"nw\"]`.")
        println(io, "- Active UC/gSCR and CAPEXP/gSCR reuse `build_uc_gscr_block_integration` with ref extensions `ref_add_gen!`, `ref_add_storage!`, `ref_add_ne_storage!`, `ref_add_uc_gscr_block!`.")
        println(io, "- Solver adapter is unchanged and value-preserving: `n_block0 -> n0`, `n_block_max -> nmax`, with UC mode forcing `nmax=n0`.")
        println(io, "- `n_block`, `na_block`, `su_block`, `sd_block` are read directly from model variables (`_PM.var(...)`) for reconstruction.")
        println(io, "- gSCR margins are reconstructed per bus/snapshot as `sigma0 + sum_gfm(b_block*na_block) - g_min*sum_gfl(p_block_max*na_block)`.")
        println(io, "- Startup/shutdown and investment decompositions are reconstructed from solved block variables and device coefficients.")
        println(io, "- This report is written by this targeted test to `reports/pypsa_24h_block_gscr_plausibility.md`.")
        println(io)

        println(io, "## 1) 24-Snapshot Schema Check")
        println(io, "- multinetwork = `", schema["multinetwork"], "`")
        println(io, "- snapshots = ", schema["snapshots"])
        println(io, "- snapshot-1 counts: bus=", schema["bus_count"], ", branch=", schema["branch_count"], ", gen=", schema["gen_count"], ", storage=", schema["storage_count"])
        println(io, "- block-enabled counts (snapshot 1): gfl=", schema["gfl_count"], ", gfm=", schema["gfm_count"])
        println(io, "- all required block fields present on block-enabled devices: `", schema["all_block_fields_present"], "`")
        println(io, "- raw invariant violations (`0 <= na0 <= n_block0 <= n_block_max`): ", length(invariant_violations))
        println(io)

        println(io, "## 2) 24-Snapshot Standard OPF Sanity")
        println(io, "- status: `", opf["status"], "`")
        println(io, "- objective: ", _fmt_num(opf["objective"]))
        println(io, "- solve_time_sec: ", _fmt_num(opf["solve_time_sec"]))
        println(io, "- feasible: `", opf["feasible"], "`")
        println(io, "- storage bounds consistent: `", opf["storage_bounds_consistent"], "`")
        if !isempty(opf["storage_bound_violations"])
            println(io, "- storage bound violations:")
            for item in opf["storage_bound_violations"]
                println(io, "  - nw=", item["nw"], " storage=", item["storage"], " se=", _fmt_num(item["se"]), " sc=", _fmt_num(item["sc"]), " sd=", _fmt_num(item["sd"]))
            end
        end
        println(io)

        println(io, "## 3) 24-Snapshot Active UC/gSCR (`nmax=n0`)")
        println(io, "- status: `", uc["status"], "`")
        println(io, "- objective: ", _fmt_num(uc["objective"]))
        println(io, "- solve_time_sec: ", _fmt_num(uc["solve_time_sec"]))
        println(io, "- total startup cost: ", _fmt_num(uc["startup_cost"]))
        println(io, "- total shutdown cost: ", _fmt_num(uc["shutdown_cost"]))
        println(io, "- total startup count: ", _fmt_num(uc["startup_count"]))
        println(io, "- total shutdown count: ", _fmt_num(uc["shutdown_count"]))
        println(io, "- minimum gSCR margin: ", _fmt_num(uc["min_gscr_margin"]), " (nw=", uc["min_gscr_margin_nw"], ", bus=", uc["min_gscr_margin_bus"], ")")
        println(io, "- near-binding gSCR constraints (margin <= ", _NEAR_TOL, "): ", uc["near_binding_count"])
        println(io, "- transition residual max |(na_t-na_prev)-(su_t-sd_t)|: ", _fmt_num(uc["transition_max_residual"]))
        println(io, "- gSCR max violation: ", _fmt_num(uc["gscr_max_violation"]))
        println(io, "- suspicious snapshots: ", isempty(uc["suspicious_snapshots"]) ? "none" : join(string.(uc["suspicious_snapshots"]), ", "))
        println(io)

        println(io, "### Online GFL/GFM Blocks by Snapshot (UC)")
        println(io, "| snapshot | online_gfl | online_gfm | online_total | dispatch_abs_gfl | dispatch_abs_gfm |")
        println(io, "|---:|---:|---:|---:|---:|---:|")
        for nw in sort(collect(keys(uc["online_gfl_by_snapshot"])))
            println(io, "| ", nw, " | ", _fmt_num(uc["online_gfl_by_snapshot"][nw]), " | ", _fmt_num(uc["online_gfm_by_snapshot"][nw]), " | ", _fmt_num(uc["online_total_by_snapshot"][nw]), " | ", _fmt_num(uc["gfl_dispatch_abs_by_snapshot"][nw]), " | ", _fmt_num(uc["gfm_dispatch_abs_by_snapshot"][nw]), " |")
        end
        println(io)

        println(io, "## 4) 24-Snapshot Active CAPEXP/gSCR")
        println(io, "- status: `", cap["status"], "`")
        println(io, "- objective: ", _fmt_num(cap["objective"]))
        println(io, "- solve_time_sec: ", _fmt_num(cap["solve_time_sec"]))
        println(io, "- total investment cost (requested reconstruction): ", _fmt_num(cap["investment_cost"]))
        println(io, "- total investment cost (model coefficient form with p_block_max): ", _fmt_num(cap["investment_cost_with_pmax"]))
        println(io, "- total startup cost: ", _fmt_num(cap["startup_cost"]))
        println(io, "- total shutdown cost: ", _fmt_num(cap["shutdown_cost"]))
        println(io, "- total invested GFL blocks: ", _fmt_num(cap["invested_gfl_blocks"]))
        println(io, "- total invested GFM blocks: ", _fmt_num(cap["invested_gfm_blocks"]))
        println(io, "- minimum gSCR margin: ", _fmt_num(cap["min_gscr_margin"]), " (nw=", cap["min_gscr_margin_nw"], ", bus=", cap["min_gscr_margin_bus"], ")")
        println(io, "- near-binding gSCR constraints (margin <= ", _NEAR_TOL, "): ", cap["near_binding_count"])
        println(io, "- n_block shared-across-snapshots max residual: ", _fmt_num(cap["n_shared_max_residual"]))
        println(io, "- active bound max violation (`0 <= na_block <= n_block`): ", _fmt_num(cap["active_bound_max_violation"]))
        println(io, "- gSCR max violation: ", _fmt_num(cap["gscr_max_violation"]))
        println(io)

        println(io, "### Investment by Carrier")
        if isempty(cap["investment_by_carrier"])
            println(io, "- unavailable")
        else
            for (carrier, val) in sort(collect(cap["investment_by_carrier"]); by=first)
                println(io, "- ", carrier, ": ", _fmt_num(val))
            end
        end
        println(io)

        println(io, "### Investment by Bus")
        if isempty(cap["investment_by_bus"])
            println(io, "- unavailable")
        else
            for (bus, val) in sort(collect(cap["investment_by_bus"]); by=first)
                println(io, "- bus ", bus, ": ", _fmt_num(val))
            end
        end
        println(io)

        println(io, "### Online GFL/GFM Blocks by Snapshot (CAPEXP)")
        println(io, "| snapshot | online_gfl | online_gfm | online_total | dispatch_abs_gfl | dispatch_abs_gfm |")
        println(io, "|---:|---:|---:|---:|---:|---:|")
        for nw in sort(collect(keys(cap["online_gfl_by_snapshot"])))
            println(io, "| ", nw, " | ", _fmt_num(cap["online_gfl_by_snapshot"][nw]), " | ", _fmt_num(cap["online_gfm_by_snapshot"][nw]), " | ", _fmt_num(cap["online_total_by_snapshot"][nw]), " | ", _fmt_num(cap["gfl_dispatch_abs_by_snapshot"][nw]), " | ", _fmt_num(cap["gfm_dispatch_abs_by_snapshot"][nw]), " |")
        end
        println(io)

        println(io, "## 5) Plausibility Analysis")
        println(io)
        println(io, "### A. Feasibility")
        println(io, "- Standard OPF: `", opf["status"], "` (feasible=", opf["feasible"], ")")
        println(io, "- UC/gSCR: `", uc["status"], "`")
        println(io, "- CAPEXP/gSCR: `", cap["status"], "`")
        if !(opf["feasible"] && uc["status"] in _ACTIVE_OK_STATUSES && cap["status"] in _ACTIVE_OK_STATUSES)
            println(io, "- Likely infeasibility driver: gSCR or dispatch/storage feasibility limits at one or more snapshots (inspect min margin and storage checks above).")
        else
            println(io, "- All requested modes solved with documented feasible statuses.")
        end
        println(io)

        println(io, "### B. gSCR Behavior")
        println(io, "- UC min margin: ", _fmt_num(uc["min_gscr_margin"]), "; CAPEXP min margin: ", _fmt_num(cap["min_gscr_margin"]))
        println(io, "- Near-binding count UC/CAPEXP: ", uc["near_binding_count"], " / ", cap["near_binding_count"])
        println(io, "- Minimum-margin location UC: nw=", uc["min_gscr_margin_nw"], ", bus=", uc["min_gscr_margin_bus"], "; CAPEXP: nw=", cap["min_gscr_margin_nw"], ", bus=", cap["min_gscr_margin_bus"])
        println(io, "- CAPEXP investment response (GFM vs GFL blocks): invested_gfm=", _fmt_num(cap["invested_gfm_blocks"]), ", invested_gfl=", _fmt_num(cap["invested_gfl_blocks"]))
        println(io)

        println(io, "### C. Startup/Shutdown Behavior")
        println(io, "- UC startup/shutdown counts: ", _fmt_num(uc["startup_count"]), " / ", _fmt_num(uc["shutdown_count"]))
        println(io, "- CAPEXP startup/shutdown counts: ", _fmt_num(cap["startup_count"]), " / ", _fmt_num(cap["shutdown_count"]))
        println(io, "- Transition reconstruction max residual UC/CAPEXP: ", _fmt_num(uc["transition_max_residual"]), " / ", _fmt_num(cap["transition_max_residual"]))
        println(io, "- Rapid oscillation flags UC/CAPEXP: ", isempty(uc["rapid_oscillation_devices"]) ? "none" : join(uc["rapid_oscillation_devices"], ", "), " / ", isempty(cap["rapid_oscillation_devices"]) ? "none" : join(cap["rapid_oscillation_devices"], ", "))
        println(io, "- First-snapshot consistency is included in the transition residual check by using `na0` for the first hour.")
        println(io)

        println(io, "### D. Investment Behavior")
        println(io, "- CAPEXP invested blocks (GFL/GFM): ", _fmt_num(cap["invested_gfl_blocks"]), " / ", _fmt_num(cap["invested_gfm_blocks"]))
        println(io, "- Investment cost reconstruction (requested): ", _fmt_num(cap["investment_cost"]))
        println(io, "- Investment cost reconstruction (model coefficient form): ", _fmt_num(cap["investment_cost_with_pmax"]))
        println(io, "- n_block shared across snapshots residual: ", _fmt_num(cap["n_shared_max_residual"]))
        println(io)

        println(io, "### E. Dispatch/Online-Block Behavior")
        println(io, "- Online block trajectories are provided in per-snapshot tables above for UC and CAPEXP.")
        println(io, "- Near-zero-dispatch while online examples (first 15): ", isempty(cap["near_zero_dispatch_online_examples"]) ? "none" : join(cap["near_zero_dispatch_online_examples"], " ; "))
        println(io, "- Standard OPF storage bound consistency: `", opf["storage_bounds_consistent"], "`.")
        println(io)

        println(io, "### F. Comparison with Accepted 3snap/6snap")
        println(io, "- Accepted UC/gSCR min margins: 3snap≈", _fmt_num(comparison_3snap_margin), ", 6snap≈", _fmt_num(comparison_6snap_margin), ".")
        println(io, "- 24snap UC/gSCR min margin: ", _fmt_num(uc["min_gscr_margin"]), ".")
        trend = "unavailable"
        if uc["min_gscr_margin"] isa Real
            trend = uc["min_gscr_margin"] < comparison_6snap_margin - 1e-6 ? "more constrained than 6snap" : "not more constrained than 6snap"
        end
        println(io, "- 24snap trend vs accepted runs: ", trend)
        println(io, "- 3snap/6snap CAPEXP matched UC objective in accepted tests; 24snap UC/CAPEXP objectives shown above indicate whether this pattern persists.")
        println(io)

        println(io, "### G. Known Limitations")
        println(io, "- Uses buswise Gershgorin LP/MILP gSCR condition only.")
        println(io, "- Not the global SDP/LMI gSCR constraint.")
        println(io, "- Min-up/down, ramping, no-load costs, and binary UC are inactive.")
        println(io, "- Results use the converter blockized PyPSA representation.")
        println(io, "- Storage initial energy may be clamped or interpreted by converter policy.")
    end

    return _PYPSA_24H_REPORT
end

@testset "PyPSA 24h block-gSCR plausibility" begin
    if get(ENV, "RUN_PYPSA_24H", "0") != "1"
        @info "Skipping 24h targeted run; set RUN_PYPSA_24H=1 to execute" case=_dataset_path()
    elseif !isfile(_dataset_path())
        @test isfile(_dataset_path())
    else
        raw = _load_case()
        schema = _schema_summary(raw)
        invariants = _check_raw_invariants(raw)

        @test schema["multinetwork"] == true
        @test schema["snapshots"] == 24
        @test schema["bus_count"] == 5
        @test schema["branch_count"] == 6
        @test schema["gen_count"] == 23
        @test schema["storage_count"] == 5
        @test schema["gfl_count"] == 17
        @test schema["gfm_count"] == 11
        @test schema["all_block_fields_present"] == true
        @test isempty(invariants)

        opf = _solve_standard_opf_metrics(raw)
        @test opf["status"] in _DOCUMENTED_STATUSES

        uc = _solve_active_metrics(raw; mode=:uc)
        cap = _solve_active_metrics(raw; mode=:capexp)

        @test uc["status"] in _DOCUMENTED_STATUSES
        @test cap["status"] in _DOCUMENTED_STATUSES

        if uc["status"] in _ACTIVE_OK_STATUSES
            @test uc["transition_max_residual"] <= 1e-6
            @test uc["gscr_max_violation"] <= 1e-6
            @test uc["active_bound_max_violation"] <= 1e-6
        end

        if cap["status"] in _ACTIVE_OK_STATUSES
            @test cap["transition_max_residual"] <= 1e-6
            @test cap["gscr_max_violation"] <= 1e-6
            @test cap["active_bound_max_violation"] <= 1e-6
            @test cap["n_shared_max_residual"] <= 1e-6
        end

        report = _write_report(schema, invariants, opf, uc, cap)
        @test isfile(report)
    end
end
