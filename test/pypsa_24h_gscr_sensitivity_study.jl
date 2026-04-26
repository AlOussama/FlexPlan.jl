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
        "min_margin" => nothing,
        "min_margin_bus" => nothing,
        "min_margin_nw" => nothing,
        "near_binding" => 0,
        "online_gfm_by_snapshot" => Dict{Int,Float64}(),
        "online_gfl_by_snapshot" => Dict{Int,Float64}(),
        "dispatch_gfm_by_snapshot" => Dict{Int,Float64}(),
        "dispatch_gfl_by_snapshot" => Dict{Int,Float64}(),
        "zero_dispatch_online_count" => nothing,
        "transition_residual_max" => nothing,
        "active_bound_violation_max" => nothing,
        "gscr_violation_max" => nothing,
        "n_shared_residual_max" => nothing,
        "bus_diag" => Dict{String,Any}(),
        "bus_strength_summary" => Dict{Int,Dict{String,Any}}(),
        "weakest_bus_rows" => Dict{Int,Dict{String,Any}}(),
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

    startup_cost = 0.0
    shutdown_cost = 0.0
    startup_count = 0.0
    shutdown_count = 0.0
    investment_cost = 0.0
    invested_gfm = 0.0
    invested_gfl = 0.0
    invested_gen = 0.0
    invested_storage = 0.0
    min_margin = Inf
    min_bus = first(_PM.ids(pm, first_nw, :bus))
    min_nw = first_nw
    near_binding = 0
    zero_dispatch_online_count = 0
    transition_residual_max = 0.0
    active_bound_vmax = 0.0
    gscr_vmax = 0.0
    n_shared_residual_max = 0.0
    rhs_builder_recon_max_diff = 0.0

    bus_strength = Dict{Int,Dict{String,Any}}()
    for bus in sort(collect(_PM.ids(pm, first_nw, :bus)))
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
        n_first = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        dn = n_first - d["n0"]
        investment_cost += d["cost_inv_block"] * dn
        if d["type"] == "gfm"
            invested_gfm += dn
            bus = key[1] == :gen ? d["gen_bus"] : d["storage_bus"]
            bus_strength[bus]["installed_gfm_strength"] += d["b_block"] * d["n0"]
            bus_strength[bus]["max_gfm_strength"] += d["b_block"] * d["nmax"]
        elseif d["type"] == "gfl"
            invested_gfl += dn
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

    # capture g_min metadata from prepared solver data
    result["g_min_meta"] = Dict{String,Any}()
    if haskey(_PM.ref(pm, first_nw), :nw)
        # no-op placeholder; keep structure stable
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

        for key in device_keys
            d = _PM.ref(pm, nw, key[1], key[2])
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
            if na > 1.0 + _EPS && disp <= 1e-5
                zero_dispatch_online_count += 1
            end
        end
        result["online_gfm_by_snapshot"][nw] = gfm_online
        result["online_gfl_by_snapshot"][nw] = gfl_online
        result["dispatch_gfm_by_snapshot"][nw] = gfm_dispatch
        result["dispatch_gfl_by_snapshot"][nw] = gfl_dispatch

        for bus in sort(collect(_PM.ids(pm, nw, :bus)))
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

            # Independent reconstruction path over gfl_devices filtered by bus.
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

    result["startup_cost"] = startup_cost
    result["shutdown_cost"] = shutdown_cost
    result["startup_count"] = startup_count
    result["shutdown_count"] = shutdown_count
    result["investment_cost"] = investment_cost
    result["invested_gfm"] = invested_gfm
    result["invested_gfl"] = invested_gfl
    result["invested_gen"] = invested_gen
    result["invested_storage"] = invested_storage
    result["min_margin"] = min_margin
    result["min_margin_bus"] = min_bus
    result["min_margin_nw"] = min_nw
    result["binding_bus_snapshot"] = "bus=$(min_bus), snapshot=$(min_nw)"
    result["near_binding"] = near_binding
    result["zero_dispatch_online_count"] = zero_dispatch_online_count
    result["transition_residual_max"] = transition_residual_max
    result["active_bound_violation_max"] = active_bound_vmax
    result["gscr_violation_max"] = gscr_vmax
    result["n_shared_residual_max"] = n_shared_residual_max
    result["rhs_builder_recon_max_diff"] = rhs_builder_recon_max_diff
    result["bus_diag"] = _bus_diag_from_pm(pm, first_nw)
    result["bus_strength_summary"] = bus_strength
    result["weakest_bus_rows"] = bus_strength

    # selected snapshots: first, weakest, last
    selected = sort(unique([first_nw, min_nw, last(nws)]))
    for nw in selected
        rows = Dict{String,Any}[]
        rhs_total = 0.0
        for bus in sort(collect(_PM.ids(pm, nw, :bus)))
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

    # device-level GFL RHS audit at weakest snapshot
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

    # device-level GFM strength audit at weakest snapshot
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

    # required assertions
    assertion_messages = String[]
    gfl_positive_count = count(row -> row["p_block_max_used"] > _EPS, result["gfl_device_audit_rows"])
    has_positive_gfl_pmax = gfl_positive_count > 0
    if !has_positive_gfl_pmax
        push!(assertion_messages, "No GFL device with p_block_max > 0 found.")
    end

    rhs_bus_positive_ok = true
    for nw in nws
        for bus in sort(collect(_PM.ids(pm, nw, :bus)))
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
        rhs_sum_total = sum(gfl_pmax_na_by_bus_snapshot[(nw, bus)] for bus in _PM.ids(pm, nw, :bus))
        if online_gfl_total > _EPS && rhs_sum_total <= _EPS
            rhs_total_positive_ok = false
            push!(assertion_messages, "nw=$(nw): online GFL total > 0 but total sum_GFL_p_block_max_na <= 0.")
        end
        g_min = _PM.ref(pm, nw, :g_min)
        for bus in sort(collect(_PM.ids(pm, nw, :bus)))
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

function _run_mode(raw::Dict{String,Any}, scenario::String, mode_name::String; g_min_value::Float64=_BASELINE_GMIN, gfm_opex_mult::Union{Nothing,Float64}=nothing, gfm_startup_mult::Union{Nothing,Float64}=nothing, gfm_alpha::Union{Nothing,Float64}=nothing, reclass::Union{Nothing,String}=nothing)
    base_mode = mode_name == "uc_only" ? :uc : :capexp
    data = _prepare_solver_data(raw; mode=base_mode)

    meta = Dict{String,Any}(
        "scenario" => scenario,
        "mode" => mode_name,
        "gfm_opex_available" => true,
        "gfm_opex_meta" => Dict{String,Any}(),
        "gfm_startup_touched" => 0,
        "gfm_alpha_meta" => Dict{String,Any}(),
        "reclass_touched" => 0,
        "capacity_check" => Dict{String,Any}(),
        "g_min_value_injected" => g_min_value,
        "g_min_sources" => Dict{Int,String}(),
        "g_min_values" => Dict{Int,Float64}(),
    )

    if !isnothing(gfm_alpha)
        meta["gfm_alpha_meta"] = _apply_gfm_alpha_reduction!(data, gfm_alpha)
    end
    if !isnothing(reclass)
        meta["reclass_touched"] = _apply_reclassification!(data, reclass)
    end
    if !isnothing(gfm_opex_mult)
        opex_meta = _apply_gfm_opex_multiplier!(data, gfm_opex_mult)
        meta["gfm_opex_meta"] = opex_meta
        meta["gfm_opex_available"] = opex_meta["available"]
    end
    if !isnothing(gfm_startup_mult)
        meta["gfm_startup_touched"] = _apply_gfm_startup_multiplier!(data, gfm_startup_mult)
    end
    # Enforce selected expansion mode after all scenario mutations.
    _set_mode_nmax_policy!(data, mode_name)
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
                "min_margin" => nothing,
                "near_binding" => 0,
                "online_gfm_by_snapshot" => Dict{Int,Float64}(),
                "online_gfl_by_snapshot" => Dict{Int,Float64}(),
                "dispatch_gfm_by_snapshot" => Dict{Int,Float64}(),
                "dispatch_gfl_by_snapshot" => Dict{Int,Float64}(),
                "zero_dispatch_online_count" => nothing,
                "bus_diag" => Dict{String,Any}(),
                "bus_strength_summary" => Dict{Int,Dict{String,Any}}(),
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
    if mode == "uc_only"
        return 1
    elseif mode == "full_capexp"
        return 2
    elseif mode == "storage_only"
        return 3
    else
        return 4
    end
end

function _write_report(records::Vector{Dict{String,Any}}, baseline_uc::Dict{String,Any}, baseline_cap::Dict{String,Any})
    mkpath(dirname(_REPORT_PATH))
    function _is_gmin_sweep(r::Dict{String,Any})
        return startswith(r["scenario"], "gmin_abs_")
    end
    function _parse_gmin_from_scenario(s::String)
        return parse(Float64, replace(replace(s, "gmin_abs_" => ""), "p" => "."))
    end
    function _first_infeasible_gmin(records::Vector{Dict{String,Any}}, mode::String)
        vals = Float64[]
        for r in records
            if _is_gmin_sweep(r) && r["mode"] == mode && !(r["status"] in _ACTIVE_OK)
                push!(vals, _parse_gmin_from_scenario(r["scenario"]))
            end
        end
        return isempty(vals) ? nothing : minimum(vals)
    end

    open(_REPORT_PATH, "w") do io
        println(io, "# PyPSA 24h gSCR Sensitivity Study")
        println(io)
        println(io, "Generated by `test/pypsa_24h_gscr_sensitivity_study.jl` on ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"), ".")
        println(io, "Dataset: `", _dataset_path(), "`")
        println(io)
        println(io, "## Setup")
        println(io, "- Formulation unchanged: `n_block`, `na_block`, `su_block`, `sd_block`, block dispatch/storage, investment cost, startup/shutdown costs, AC-side Gershgorin gSCR.")
        println(io, "- Not activated: min-up/down, ramping, no-load costs, binary UC, SDP/LMI, new gSCR formulations.")
        println(io)
        println(io, "## g_min Handling")
        println(io, "- `g_min` is a FlexPlan optimization argument injected in the test/optimizer layer.")
        println(io, "- `g_min` is not required as converter-exported PyPSA dataset data.")
        println(io, "- Raw bus `g_min` in input case data is ignored for active gSCR tests.")
        println(io, "- This study injects a uniform `g_min` to all AC buses and snapshots before model build.")
        println(io, "- Injected values: `0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0`.")
        println(io)
        println(io, "## Baseline Diagnostic (`g_min=0.0`)")
        for r in (baseline_uc, baseline_cap)
            println(io, "- ", r["mode"], ": status=", r["status"], ", obj=", _fmt(r["objective"]), ", startup=", _fmt(r["startup_cost"]), ", shutdown=", _fmt(r["shutdown_cost"]), ", invest=", _fmt(r["investment_cost"]), ", min_margin=", _fmt(r["min_margin"]), ", near_binding=", r["near_binding"], ", zero_dispatch_online=", _fmt(r["zero_dispatch_online_count"]))
        end
        println(io)

        println(io, "## Absolute g_min Sweep Table")
        println(io, "| g_min | mode | status | objective | investment cost | startup cost | shutdown cost | invested_gfm | invested_gfl | invested_gen | invested_storage | online_gfm_avg | online_gfl_avg | min_margin | near_binding | binding bus/snapshot | startup_count | shutdown_count |")
        println(io, "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|")
        sweep_rows = filter(_is_gmin_sweep, records)
        for r in sort(sweep_rows; by=x -> (_parse_gmin_from_scenario(x["scenario"]), _mode_order(x["mode"])))
            gval = _parse_gmin_from_scenario(r["scenario"])
            println(io, "| ", _fmt(gval), " | ", r["mode"], " | ", r["status"], " | ", _fmt(r["objective"]), " | ", _fmt(r["investment_cost"]), " | ", _fmt(r["startup_cost"]), " | ", _fmt(r["shutdown_cost"]), " | ", _fmt(r["invested_gfm"]), " | ", _fmt(r["invested_gfl"]), " | ", _fmt(r["invested_gen"]), " | ", _fmt(r["invested_storage"]), " | ", _fmt(_avg(r["online_gfm_by_snapshot"])), " | ", _fmt(_avg(r["online_gfl_by_snapshot"])), " | ", _fmt(r["min_margin"]), " | ", r["near_binding"], " | ", get(r, "binding_bus_snapshot", "n/a"), " | ", _fmt(r["startup_count"]), " | ", _fmt(r["shutdown_count"]), " |")
        end
        println(io)

        println(io, "## RHS Audit (Constraint Data Path)")
        println(io, "- Constraint and reconstruction both use: `:bus_gfl_devices`, `:bus_gfm_devices`, `_PM.ref(..., \"p_block_max\")`, `_PM.ref(..., \"b_block\")`, `_PM.var(..., :na_block, key)`.")
        println(io, "- Builder-vs-reconstruction max |difference| in `sum_GFL_p_block_max_na` for baseline UC: ", _fmt(baseline_uc["rhs_builder_recon_max_diff"]))
        println(io)
        for audit_g in sort(collect(_GMIN_AUDIT_VALUES))
            scen = "gmin_abs_" * replace(string(audit_g), "." => "p")
            rows = filter(r -> r["scenario"] == scen && r["mode"] == "uc_only", records)
            if isempty(rows)
                continue
            end
            r = rows[1]
            for nw in (1, 24)
                if !haskey(r["rhs_snapshot_audit_rows"], nw)
                    continue
                end
                println(io, "### RHS Bus Audit (`g_min=", _fmt(audit_g), "`, snapshot ", nw, ")")
                println(io, "| bus | injected_g_min | #bus_gfl | #bus_gfm | sum_GFL_p_block_max_na | RHS | sum_GFM_b_block_na | sigma0_G | margin | online_gfl_na |")
                println(io, "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
                for row in sort(r["rhs_snapshot_audit_rows"][nw]; by=x -> x["bus"])
                    println(io, "| ", row["bus"], " | ", _fmt(row["g_min"]), " | ", row["gfl_count"], " | ", row["gfm_count"], " | ", _fmt(row["sum_gfl_p_block_max_na"]), " | ", _fmt(row["rhs"]), " | ", _fmt(row["sum_gfm_b_block_na"]), " | ", _fmt(row["sigma0"]), " | ", _fmt(row["margin"]), " | ", _fmt(row["online_gfl_na"]), " |")
                end
                println(io)
            end
        end

        println(io, "### Device-Level GFL RHS Audit (Baseline UC, Weakest Snapshot)")
        println(io, "| component_key | component_type | component_id | carrier | bus | type | p_block_max_raw | p_block_max_used | na_block@weakest | contribution | in_gfl_devices | in_bus_gfl_devices | weakest_snapshot |")
        println(io, "|---|---|---:|---|---:|---|---:|---:|---:|---:|---|---|---:|")
        for row in baseline_uc["gfl_device_audit_rows"]
            println(io, "| ", row["component_key"], " | ", row["component_type"], " | ", row["component_id"], " | ", row["carrier"], " | ", row["bus"], " | ", row["type"], " | ", _fmt(row["p_block_max_raw"]), " | ", _fmt(row["p_block_max_used"]), " | ", _fmt(row["na_block_weakest_snapshot"]), " | ", _fmt(row["contribution"]), " | ", row["in_gfl_devices"], " | ", row["in_bus_gfl_devices"], " | ", row["weakest_snapshot"], " |")
        end
        println(io)

        println(io, "### Device-Level GFM Strength Audit (Baseline UC, Weakest Snapshot)")
        println(io, "| component_key | component_type | component_id | carrier | bus | type | b_gfm_input | b_gfm_base | s_block_mva | b_block_output | n_block0 | n_block_max | installed_strength | max_strength |")
        println(io, "|---|---|---:|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for row in baseline_uc["gfm_device_strength_audit_rows"]
            println(io, "| ", row["component_key"], " | ", row["component_type"], " | ", row["component_id"], " | ", row["carrier"], " | ", row["bus"], " | ", row["type"], " | ", _fmt(row["b_gfm_input"]), " | ", _fmt(row["b_gfm_base"]), " | ", _fmt(row["s_block_mva"]), " | ", _fmt(row["b_block_output"]), " | ", _fmt(row["n_block0"]), " | ", _fmt(row["n_block_max"]), " | ", _fmt(row["installed_strength"]), " | ", _fmt(row["max_strength"]), " |")
        end
        println(io)

        println(io, "### Baseline RHS Assertions")
        ra = baseline_uc["rhs_assertions"]
        println(io, "- at least one GFL with p_block_max>0: `", ra["has_positive_gfl_pmax"], "`")
        println(io, "- bus-level condition (online GFL => positive sum_GFL_p_block_max_na): `", ra["rhs_bus_positive_ok"], "`")
        println(io, "- system-level condition (online GFL => positive total sum_GFL_p_block_max_na): `", ra["rhs_total_positive_ok"], "`")
        println(io, "- g_min>0 condition (online GFL => RHS>0): `", ra["rhs_positive_when_gmin_positive"], "`")
        println(io, "- g_min=0 condition (RHS==0): `", ra["rhs_zero_when_gmin_zero"], "`")
        if !isempty(ra["messages"])
            println(io, "- assertion messages:")
            for msg in ra["messages"]
                println(io, "  - ", msg)
            end
        end
        println(io)

        println(io, "## Sensitivity Table")
        println(io, "| scenario | mode | status | objective | min_margin | near_binding | invested_gfm | invested_gfl | online_gfm_avg | online_gfl_avg | startup_count | shutdown_count |")
        println(io, "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in sort(records; by=x -> (x["scenario"], _mode_order(x["mode"])))
            println(io, "| ", r["scenario"], " | ", r["mode"], " | ", r["status"], " | ", _fmt(r["objective"]), " | ", _fmt(r["min_margin"]), " | ", r["near_binding"], " | ", _fmt(r["invested_gfm"]), " | ", _fmt(r["invested_gfl"]), " | ", _fmt(_avg(r["online_gfm_by_snapshot"])), " | ", _fmt(_avg(r["online_gfl_by_snapshot"])), " | ", _fmt(r["startup_count"]), " | ", _fmt(r["shutdown_count"]), " |")
        end
        println(io)

        println(io, "## gSCR Diagnostic Table (Baseline UC)")
        bdiag = baseline_uc["bus_diag"]
        bsum = baseline_uc["bus_strength_summary"]
        println(io, "| bus | sigma0_G | B0_diag | B0_abs_rowsum | installed_gfm_strength | max_gfm_strength | weakest_snapshot | RHS_at_weakest | margin_at_weakest |")
        println(io, "|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        if !haskey(bdiag, "diag")
            println(io, "| - | NaN | NaN | NaN | NaN | NaN | NaN | NaN | NaN |")
        else
            for bus in sort(collect(keys(bdiag["diag"])))
                row = bsum[bus]
                println(io, "| ", bus, " | ", _fmt(bdiag["sigma0"][bus]), " | ", _fmt(bdiag["diag"][bus]), " | ", _fmt(bdiag["offabs"][bus]), " | ", _fmt(row["installed_gfm_strength"]), " | ", _fmt(row["max_gfm_strength"]), " | ", row["weakest_snapshot"], " | ", _fmt(row["rhs_at_weakest"]), " | ", _fmt(row["margin_at_weakest"]), " |")
            end
        end
        println(io)

        println(io, "## Sensitivity Diagnostics")
        opex_uc = filter(r -> r["scenario"] == "gfm_opex_x1p5" && r["mode"] == "uc_only", records)
        opex_cap = filter(r -> r["scenario"] == "gfm_opex_x1p5" && r["mode"] == "full_capexp", records)
        if !isempty(opex_uc) && get(opex_uc[1]["meta"], "gfm_opex_available", false)
            for r in (opex_uc[1], opex_cap[1])
                base = r["mode"] == "uc_only" ? baseline_uc : baseline_cap
                println(io, "- OPEX ", r["mode"], ": d_obj=", _fmt((r["objective"] isa Real && base["objective"] isa Real) ? r["objective"] - base["objective"] : NaN), ", d_online_gfm_avg=", _fmt(_avg(r["online_gfm_by_snapshot"]) - _avg(base["online_gfm_by_snapshot"])), ", d_dispatch_gfm_total=", _fmt(_sumv(r["dispatch_gfm_by_snapshot"]) - _sumv(base["dispatch_gfm_by_snapshot"])), ", min_margin=", _fmt(r["min_margin"]), ", zero_dispatch_online=", _fmt(r["zero_dispatch_online_count"]))
            end
        else
            println(io, "- GFM OPEX sensitivity unavailable: explicit linear marginal costs for GFM were not clearly editable in this dataset path.")
        end
        println(io)
        su_uc = filter(r -> r["scenario"] == "gfm_startup_x10" && r["mode"] == "uc_only", records)
        su_cap = filter(r -> r["scenario"] == "gfm_startup_x10" && r["mode"] == "full_capexp", records)
        if !isempty(su_uc)
            for r in (su_uc[1], su_cap[1])
                println(io, "- Startup x10 ", r["mode"], ": startup_count=", _fmt(r["startup_count"]), ", startup_cost=", _fmt(r["startup_cost"]), ", shutdown_count=", _fmt(r["shutdown_count"]), ", min_margin=", _fmt(r["min_margin"]))
            end
        end
        println(io)

        println(io, "## Plausibility Conclusions")
        uc_first_bad = _first_infeasible_gmin(records, "uc_only")
        cap_first_bad = _first_infeasible_gmin(records, "full_capexp")
        stor_first_bad = _first_infeasible_gmin(records, "storage_only")
        gen_first_bad = _first_infeasible_gmin(records, "generator_only")
        g0_uc = only(filter(r -> r["scenario"] == "gmin_abs_0p0" && r["mode"] == "uc_only", records))
        solved_positive_g_uc = filter(
            r -> startswith(r["scenario"], "gmin_abs_") &&
                 r["mode"] == "uc_only" &&
                 r["status"] in _ACTIVE_OK &&
                 r["scenario"] != "gmin_abs_0p0",
            records,
        )
        g3_uc = only(filter(r -> r["scenario"] == "gmin_abs_3p0" && r["mode"] == "uc_only", records))
        rhs_positive_for_positive_g =
            !isempty(solved_positive_g_uc) &&
            all(r["rhs_assertions"]["rhs_positive_when_gmin_positive"] for r in solved_positive_g_uc)
        println(io, "- Does RHS activate for g_min>0? ", isempty(solved_positive_g_uc) ? "not observable (all g_min>0 UC runs infeasible)." : (rhs_positive_for_positive_g ? "yes" : "no"), ".")
        println(io, "- g_min=0 reproduces zero-RHS diagnostic: ", g0_uc["rhs_assertions"]["rhs_zero_when_gmin_zero"], ".")
        println(io, "- At which g_min does UC-only become binding/infeasible? near-binding at low g_min if reported, infeasible threshold=", isnothing(uc_first_bad) ? "none <=3.0" : _fmt(uc_first_bad), ".")
        capexp_restores =
            !isnothing(uc_first_bad) &&
            (isnothing(cap_first_bad) || (!isnothing(cap_first_bad) && cap_first_bad > uc_first_bad))
        println(io, "- Does CAPEXP restore feasibility? ", capexp_restores ? "yes" : "not required or not observed within tested range", ".")
        println(io, "- Storage-only expansion sufficient? ", isnothing(stor_first_bad) ? "feasible in tested range" : "insufficient from g_min=" * _fmt(stor_first_bad), ".")
        println(io, "- Generator-only expansion sufficient? ", isnothing(gen_first_bad) ? "feasible in tested range" : "insufficient from g_min=" * _fmt(gen_first_bad), ".")
        println(io, "- Does investment occur mainly in GFM when tight? inspect high-g_min rows for nonzero invested_gfm vs invested_gfl.")
        monotonic_observed =
            (g3_uc["min_margin"] isa Real) &&
            (g0_uc["min_margin"] isa Real) &&
            (g3_uc["min_margin"] < g0_uc["min_margin"] - 1e-9)
        println(io, "- Is monotonic g_min behavior observed? ", monotonic_observed ? "yes (margin decreases from g_min=0 to 3)." : "no (flag for investigation).")
        println(io, "- Are B0, sigma0_G, and b_gfm contributions plausible? see diagnostic and device-level GFM strength tables.")
        println(io, "- Does GFM OPEX/startup sensitivity materially affect online GFM? see sensitivity diagnostics section.")
        println(io, "- Recommended next model/data correction: keep g_min explicitly configured per study/run and calibrate absolute g_min range to planning assumptions.")
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

        records = Dict{String,Any}[]

        # Primary deliverable: absolute g_min sweep (uniform injection, not factors).
        for g in _GMIN_VALUES
            sname = "gmin_abs_$(replace(string(g), "." => "p"))"
            for mode in ("uc_only", "full_capexp", "storage_only", "generator_only")
                r = _run_mode(raw, sname, mode; g_min_value=g)
                push!(records, r)
                @test r["status"] in union(_DOC_STATUS, Set(["SKIPPED_INVALID_CAPACITY"]))
                if mode == "uc_only" && r["status"] in _ACTIVE_OK
                    @test abs(r["investment_cost"]) <= 1e-6
                end
                if mode == "storage_only" && r["status"] in _ACTIVE_OK
                    @test abs(r["invested_gen"]) <= 1e-6
                end
                if mode == "generator_only" && r["status"] in _ACTIVE_OK
                    @test abs(r["invested_storage"]) <= 1e-6
                end
            end
        end

        baseline_uc = only(filter(r -> r["scenario"] == "gmin_abs_0p0" && r["mode"] == "uc_only", records))
        baseline_cap = only(filter(r -> r["scenario"] == "gmin_abs_0p0" && r["mode"] == "full_capexp", records))
        zero_uc = only(filter(r -> r["scenario"] == "gmin_abs_0p0" && r["mode"] == "uc_only", records))
        if baseline_uc["status"] in _ACTIVE_OK
            @test baseline_uc["rhs_assertions"]["has_positive_gfl_pmax"] == true
            @test baseline_uc["rhs_assertions"]["rhs_bus_positive_ok"] == true
            @test baseline_uc["rhs_assertions"]["rhs_total_positive_ok"] == true
            @test baseline_uc["rhs_builder_recon_max_diff"] <= 1e-9
        end
        if zero_uc["status"] in _ACTIVE_OK
            @test zero_uc["rhs_assertions"]["rhs_zero_when_gmin_zero"] == true
        end
        solved_positive_g = filter(r -> startswith(r["scenario"], "gmin_abs_") && r["mode"] == "uc_only" && r["status"] in _ACTIVE_OK && occursin("gmin_abs_0p0", r["scenario"]) == false, records)
        for r in solved_positive_g
            @test r["rhs_assertions"]["rhs_positive_when_gmin_positive"] == true
        end

        # Keep non-g_min sensitivities (run at baseline g_min=1.0).
        for mode in ("uc_only", "full_capexp")
            push!(records, _run_mode(raw, "gfm_opex_x1p5", mode; g_min_value=_BASELINE_GMIN, gfm_opex_mult=1.5))
        end

        for mode in ("uc_only", "full_capexp")
            push!(records, _run_mode(raw, "gfm_startup_x10", mode; g_min_value=_BASELINE_GMIN, gfm_startup_mult=10.0))
        end

        for alpha in (1.0, 0.75, 0.5, 0.25)
            sname = "alpha_$(replace(string(alpha), "." => "p"))"
            for mode in ("uc_only", "full_capexp")
                push!(records, _run_mode(raw, sname, mode; g_min_value=_BASELINE_GMIN, gfm_alpha=alpha))
            end
        end

        for reclass in ("battery_gfm_to_gfl", "thermal_gfm_to_gfl", "nonsync_gfm_to_gfl")
            sname = "reclass_" * reclass
            for mode in ("uc_only", "full_capexp")
                push!(records, _run_mode(raw, sname, mode; g_min_value=_BASELINE_GMIN, reclass=reclass))
            end
        end

        # Monotonic infeasibility check for absolute g_min sweep by mode.
        for mode in ("uc_only", "full_capexp", "storage_only", "generator_only")
            feasible_seen_infeasible = false
            for g in _GMIN_VALUES
                sname = "gmin_abs_$(replace(string(g), "." => "p"))"
                r = only(filter(x -> x["scenario"] == sname && x["mode"] == mode, records))
                feasible = r["status"] in _ACTIVE_OK
                if feasible_seen_infeasible && feasible
                    @test false
                end
                if !feasible
                    feasible_seen_infeasible = true
                end
            end
        end

        # Monotonic plausibility summary per mode (reported, not hard-failed).
        monotonic_summary = Dict{String,Bool}()
        for mode in ("uc_only", "full_capexp", "storage_only", "generator_only")
            solved = Dict{Float64,Float64}()
            for g in _GMIN_VALUES
                sname = "gmin_abs_$(replace(string(g), "." => "p"))"
                r = only(filter(x -> x["scenario"] == sname && x["mode"] == mode, records))
                if r["status"] in _ACTIVE_OK
                    solved[g] = r["min_margin"]
                end
            end
            if haskey(solved, 0.0)
                any_change = any(abs(solved[g] - solved[0.0]) > 1e-9 for g in keys(solved) if g > 0.0)
                monotonic_summary[mode] = any_change
            end
        end

        # Reconstruction and model-consistency checks on solved cases.
        for r in records
            if r["status"] in _ACTIVE_OK
                @test r["transition_residual_max"] <= 1e-6
                @test r["active_bound_violation_max"] <= 1e-6
                @test r["gscr_violation_max"] <= 1e-6
                @test r["n_shared_residual_max"] <= 1e-6
                @test r["rhs_builder_recon_max_diff"] <= 1e-9
            end
        end

        report = _write_report(records, baseline_uc, baseline_cap)
        @test isfile(report)
    end
end
