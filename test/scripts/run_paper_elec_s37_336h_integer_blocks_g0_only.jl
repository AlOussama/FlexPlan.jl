import FlexPlan as _FP
import PowerModels as _PM
import InfrastructureModels as _IM
using JuMP
import JSON
using LinearAlgebra
using Statistics
using Dates
using DelimitedFiles
import Gurobi
using Memento
const MOI = JuMP.MOI

Memento.setlevel!(Memento.getlogger(_IM), "error")
Memento.setlevel!(Memento.getlogger(_PM), "error")

include(normpath(@__DIR__, "..", "pypsa_elec_s_37_24h_small_capexp.jl"))

const _UNBOUNDED_TERMINATIONS = Set(["DUAL_INFEASIBLE", "INFEASIBLE_OR_UNBOUNDED", "UNBOUNDED"])
const _DATA_ROOT = raw"D:\Projekte\Code\pypsatomatpowerx_clean_battery_policy\data\flexplan_block_gscr"
const _OUT_ROOT = normpath(@__DIR__, "..", "..", "reports", "paper_elec_s_37_campaign_336h_integer_blocks_v2_g0_base")
const _RUNS = [
    ("H_336h_gmin_0p0_integer_blocks", "BASE-INTEGER", "elec_s_37_2weeks_from_0301", 336, 0.0),
]
const _POSTHOC_BASE_ALPHA = 1.5
const _POSTHOC_ALPHA_PAPER = 1.5
const _BINDING_EPSILON = 1e-5
const _EXCLUDED_CARRIERS = Set(["coal", "hard coal", "lignite", "oil"])
const _EXCLUDED_CARRIERS_REPORTED = ["coal", "lignite", "oil"]
const _SELECTED_WEEKS_POLICY = "two_weeks_from_0301_with_preprocessed_fossil_exclusion"
const _SOLVER_NAME = "Gurobi"
const _GUROBI_OPTIONS = Dict(
    "MIPGap" => 0.005,
    "TimeLimit" => 6 * 60 * 60,
    "Threads" => 0,
    "OutputFlag" => 0,
)

_fmt(x) = isnothing(x) ? "" : (x isa Real ? (isfinite(x) ? string(x) : "") : string(x))

function _git_info()
    commit = strip(readchomp(`git rev-parse HEAD`))
    branch = strip(readchomp(`git rev-parse --abbrev-ref HEAD`))
    tags_raw = split(strip(readchomp(`git tag --points-at HEAD`)), '\n')
    tags = [t for t in tags_raw if !isempty(strip(t))]
    return Dict("commit" => commit, "branch" => branch, "tags" => tags)
end

function _load_case(path::String)
    if !isfile(path)
        error("Missing dataset case file: $path")
    end
    return JSON.parsefile(path)
end

function _carrier_key(x)
    return lowercase(strip(String(get(x, "carrier", ""))))
end

function _remove_excluded_generators!(data::Dict{String,Any})
    removed_by_carrier = Dict{String,Int}()
    removed_by_snapshot = Dict{String,Int}()
    for (nw_id, nw) in data["nw"]
        gens = get(nw, "gen", Dict{String,Any}())
        remove_ids = String[]
        for (gid, gen) in gens
            carrier = _carrier_key(gen)
            if carrier in _EXCLUDED_CARRIERS
                push!(remove_ids, String(gid))
                reported = carrier == "hard coal" ? "coal" : carrier
                removed_by_carrier[reported] = get(removed_by_carrier, reported, 0) + 1
            end
        end
        for gid in remove_ids
            delete!(gens, gid)
        end
        removed_by_snapshot[String(nw_id)] = length(remove_ids)
    end
    return Dict(
        "excluded_carriers" => _EXCLUDED_CARRIERS_REPORTED,
        "excluded_aliases" => ["hard coal"],
        "removed_generator_records_by_reported_carrier" => removed_by_carrier,
        "removed_generator_records_total" => sum(values(removed_by_carrier); init=0),
        "removed_generator_records_by_snapshot" => removed_by_snapshot,
        "coal_lignite_oil_excluded_before_solver" => true,
    )
end

function _assert_excluded_generators_absent(data::Dict{String,Any})
    present = Set{String}()
    for nw in values(data["nw"])
        for gen in values(get(nw, "gen", Dict{String,Any}()))
            carrier = _carrier_key(gen)
            if carrier in _EXCLUDED_CARRIERS
                push!(present, carrier)
            end
        end
    end
    if !isempty(present)
        error("Excluded generator carriers still present after preprocessing: $(sort(collect(present)))")
    end
end

function _scale_investment_costs!(data::Dict{String,Any})
    return data
end

function _drop_deprecated_p_block_min!(data::Dict{String,Any})
    for nw in values(data["nw"])
        for table in ("gen", "storage", "ne_storage")
            for d in values(get(nw, table, Dict{String,Any}()))
                if haskey(d, "p_block_min")
                    delete!(d, "p_block_min")
                end
            end
        end
    end
end

function _constraint_count(model::JuMP.Model)
    total = 0
    for (F, S) in JuMP.list_of_constraint_types(model)
        total += JuMP.num_constraints(model, F, S)
    end
    return total
end

function _safe_moi(model::JuMP.Model, attr)
    try
        return MOI.get(model, attr)
    catch
        return nothing
    end
end

function _bounds_summary(vdict)
    n = 0
    free = 0
    lb_missing = 0
    ub_missing = 0
    for v in values(vdict)
        n += 1
        has_lb = JuMP.has_lower_bound(v)
        has_ub = JuMP.has_upper_bound(v)
        lb_missing += has_lb ? 0 : 1
        ub_missing += has_ub ? 0 : 1
        if !has_lb && !has_ub
            free += 1
        end
    end
    return Dict("count" => n, "free" => free, "missing_lb" => lb_missing, "missing_ub" => ub_missing)
end

function _extract_flow(pvar, key)
    return (_has_axis_key(pvar, key) ? JuMP.value(pvar[key]) : 0.0)
end

function _ac_loading(pm)
    rows = Dict{String,Any}[]
    max_loading = 0.0
    overload_count = 0
    for n in sort(collect(_FP.nw_ids(pm)))
        if !haskey(_PM.var(pm, n), :p)
            continue
        end
        pvar = _PM.var(pm, n, :p)
        for bid in _PM.ids(pm, n, :branch)
            br = _PM.ref(pm, n, :branch, bid)
            fbus = Int(get(br, "f_bus", -1))
            tbus = Int(get(br, "t_bus", -1))
            key_ft = (bid, fbus, tbus)
            key_tf = (bid, tbus, fbus)
            pf = _extract_flow(pvar, key_ft)
            pt = _extract_flow(pvar, key_tf)
            flow = max(abs(pf), abs(pt))
            rating = float(get(br, "rate_a", 0.0))
            ratio = rating > 1e-9 ? flow / rating : 0.0
            max_loading = max(max_loading, ratio)
            if ratio > 1.0 + 1e-6
                overload_count += 1
            end
            push!(rows, Dict(
                "branch_id" => bid,
                "from_bus" => fbus,
                "to_bus" => tbus,
                "snapshot" => n,
                "flow" => flow,
                "rating" => rating,
                "loading_ratio" => ratio,
            ))
        end
    end
    sort!(rows, by=r -> r["loading_ratio"], rev=true)
    return Dict("max_loading" => max_loading, "overload_count" => overload_count, "top" => rows[1:min(20, length(rows))])
end

function _dcline_loading(pm)
    rows = Dict{String,Any}[]
    max_loading = 0.0
    overload_count = 0
    sign_loss_inconsistent = 0
    for n in sort(collect(_FP.nw_ids(pm)))
        if !haskey(_PM.var(pm, n), :p_dc)
            continue
        end
        pdc = _PM.var(pm, n, :p_dc)
        for did in _PM.ids(pm, n, :dcline)
            dc = _PM.ref(pm, n, :dcline, did)
            fbus = Int(get(dc, "f_bus", -1))
            tbus = Int(get(dc, "t_bus", -1))
            key_ft = (did, fbus, tbus)
            key_tf = (did, tbus, fbus)
            pf = _extract_flow(pdc, key_ft)
            pt = _extract_flow(pdc, key_tf)
            pmin = min(float(get(dc, "pminf", 0.0)), float(get(dc, "pmint", 0.0)))
            pmax = max(float(get(dc, "pmaxf", 0.0)), float(get(dc, "pmaxt", 0.0)))
            cap = max(abs(pmin), abs(pmax))
            flow = max(abs(pf), abs(pt))
            ratio = cap > 1e-9 ? flow / cap : 0.0
            max_loading = max(max_loading, ratio)
            if ratio > 1.0 + 1e-6
                overload_count += 1
            end
            loss0 = float(get(dc, "loss0", 0.0))
            loss1 = float(get(dc, "loss1", 0.0))
            loss_res = abs(pt + (1 - loss1) * pf - loss0)
            ok = loss_res <= 1e-5
            sign_loss_inconsistent += ok ? 0 : 1
            push!(rows, Dict(
                "dcline_id" => did,
                "from_bus" => fbus,
                "to_bus" => tbus,
                "snapshot" => n,
                "flow_from_side" => pf,
                "flow_to_side" => pt,
                "pmin" => pmin,
                "pmax" => pmax,
                "loading_ratio" => ratio,
                "sign_loss_consistency" => ok,
            ))
        end
    end
    sort!(rows, by=r -> r["loading_ratio"], rev=true)
    return Dict("max_loading" => max_loading, "overload_count" => overload_count, "inconsistent_count" => sign_loss_inconsistent, "top" => rows[1:min(20, length(rows))])
end

function _balance_residuals(pm)
    max_bus = 0.0
    max_sys = 0.0
    worst_bus = -1
    worst_nw = -1
    total_load = 0.0
    for n in sort(collect(_FP.nw_ids(pm)))
        nload = 0.0
        for l in _PM.ids(pm, n, :load)
            nload += float(get(_PM.ref(pm, n, :load, l), "pd", 0.0))
        end
        total_load += nload
        sys_pg = haskey(_PM.var(pm, n), :pg) ? sum((JuMP.value(v) for v in values(_PM.var(pm, n, :pg))); init=0.0) : 0.0
        sys_ps = haskey(_PM.var(pm, n), :ps) ? sum((JuMP.value(v) for v in values(_PM.var(pm, n, :ps))); init=0.0) : 0.0
        sys_ps_ne = haskey(_PM.var(pm, n), :ps_ne) ? sum((JuMP.value(v) for v in values(_PM.var(pm, n, :ps_ne))); init=0.0) : 0.0
        max_sys = max(max_sys, abs(sys_pg - sys_ps - sys_ps_ne - nload))

        for b in _PM.ids(pm, n, :bus)
            lhs = haskey(_PM.var(pm, n), :p) ? sum((JuMP.value(_PM.var(pm, n, :p, a)) for a in _PM.ref(pm, n, :bus_arcs, b)); init=0.0) : 0.0
            lhs += haskey(_PM.var(pm, n), :p_dc) ? sum((JuMP.value(_PM.var(pm, n, :p_dc, a)) for a in _PM.ref(pm, n, :bus_arcs_dc, b)); init=0.0) : 0.0
            rhs = sum((JuMP.value(_PM.var(pm, n, :pg, g)) for g in _PM.ref(pm, n, :bus_gens, b)); init=0.0)
            rhs -= haskey(_PM.var(pm, n), :ps) ? sum((JuMP.value(_PM.var(pm, n, :ps, s)) for s in _PM.ref(pm, n, :bus_storage, b)); init=0.0) : 0.0
            rhs -= sum((float(get(_PM.ref(pm, n, :load, l), "pd", 0.0)) for l in _PM.ref(pm, n, :bus_loads, b)); init=0.0)
            r = abs(lhs - rhs)
            if r > max_bus
                max_bus = r
                worst_bus = b
                worst_nw = n
            end
        end
    end
    return Dict(
        "max_bus_active_power_balance_residual" => max_bus,
        "max_bus_balance_bus" => worst_bus,
        "max_bus_balance_snapshot" => worst_nw,
        "max_system_active_power_balance_residual" => max_sys,
        "residual_normalized_by_total_load" => total_load > 1e-9 ? max_sys / total_load : nothing,
        "dcline_contribution_included" => true,
        "storage_contribution_included" => true,
    )
end

function _storage_details(pm, metrics::Dict{String,Any})
    max_e_envelope = get(metrics["physical_plausibility"], "max_storage_energy_bound_residual", nothing)
    max_c_env = get(metrics["physical_plausibility"], "max_storage_charge_bound_residual", nothing)
    max_d_env = get(metrics["physical_plausibility"], "max_storage_discharge_bound_residual", nothing)
    max_state_res = get(metrics["physical_plausibility"], "max_storage_state_residual", nothing)

    total_charge = 0.0
    total_discharge = 0.0
    by_charge = Dict{String,Float64}()
    by_discharge = Dict{String,Float64}()
    first_nw = minimum(_FP.nw_ids(pm))
    last_nw = maximum(_FP.nw_ids(pm))
    depletion = Dict{String,Any}[]
    for sid in _PM.ids(pm, :storage, nw=first_nw)
        st0 = _PM.ref(pm, first_nw, :storage, sid)
        carrier = String(get(st0, "carrier", "unknown"))
        e0 = float(get(st0, "energy", 0.0))
        eT = haskey(_PM.var(pm, last_nw), :se) ? JuMP.value(_PM.var(pm, last_nw, :se, sid)) : e0
        ratio = e0 > 1e-9 ? eT / e0 : nothing
        push!(depletion, Dict("storage_id" => sid, "carrier" => carrier, "initial_energy" => e0, "final_energy" => eT, "final_to_initial_ratio" => ratio))
    end
    sort!(depletion, by=x -> isnothing(x["final_to_initial_ratio"]) ? Inf : x["final_to_initial_ratio"])

    for (k, v) in metrics["storage_charge_by_carrier"]
        by_charge[k] = v
        total_charge += v
    end
    for (k, v) in metrics["storage_discharge_by_carrier"]
        by_discharge[k] = v
        total_discharge += v
    end

    return Dict(
        "max_storage_energy_balance_residual" => max_state_res,
        "max_storage_energy_envelope_residual" => max_e_envelope,
        "max_charge_envelope_residual" => max_c_env,
        "max_discharge_envelope_residual" => max_d_env,
        "aggregate_initial_storage_energy" => get(metrics, "aggregate_initial_storage_energy", nothing),
        "aggregate_final_storage_energy" => get(metrics, "aggregate_final_storage_energy", nothing),
        "final_initial_storage_ratio" => get(metrics, "final_storage_depletion_ratio", nothing),
        "total_charge" => total_charge,
        "total_discharge" => total_discharge,
        "storage_discharge_by_carrier" => by_discharge,
        "storage_charge_by_carrier" => by_charge,
        "top_storage_depletion_units" => depletion[1:min(20, length(depletion))],
    )
end

function _block_details(pm, metrics::Dict{String,Any})
    max_n_bound = 0.0
    max_na_le_n = 0.0
    startup_total = 0.0
    shutdown_total = 0.0
    for n in sort(collect(_FP.nw_ids(pm)))
        if !haskey(_PM.var(pm, n), :n_block)
            continue
        end
        for key in keys(_PM.var(pm, n, :n_block))
            dev_key = key[1]
            nvar = _PM.var(pm, n, :n_block, dev_key)
            nav = _PM.var(pm, n, :na_block, dev_key)
            max_n_bound = max(max_n_bound, _max_bound_residual(nvar))
            max_na_le_n = max(max_na_le_n, max(0.0, JuMP.value(nav) - JuMP.value(nvar)))
            if haskey(_PM.var(pm, n), :su_block)
                startup_total += JuMP.value(_PM.var(pm, n, :su_block, dev_key))
            end
            if haskey(_PM.var(pm, n), :sd_block)
                shutdown_total += JuMP.value(_PM.var(pm, n, :sd_block, dev_key))
            end
        end
    end
    return Dict(
        "max_n_block_bound_residual" => max_n_bound,
        "max_na_block_le_n_block_residual" => max_na_le_n,
        "max_startup_shutdown_transition_residual" => get(metrics["physical_plausibility"], "max_startup_shutdown_transition_residual", nothing),
        "total_startup_count" => startup_total,
        "total_shutdown_count" => shutdown_total,
        "startup_cost" => get(metrics, "startup_cost", nothing),
        "shutdown_cost" => get(metrics, "shutdown_cost", nothing),
    )
end

function _gscr_details(pm, metrics::Dict{String,Any})
    rows = Dict{String,Any}[]
    min_margin = Inf
    weak_bus = -1
    weak_nw = -1
    near_binding = 0
    violated = 0
    for n in sort(collect(_FP.nw_ids(pm)))
        gmin = float(get(_PM.ref(pm, n), :g_min, 0.0))
        for b in _PM.ids(pm, n, :bus)
            sigma0 = float(_PM.ref(pm, n, :gscr_sigma0_gershgorin_margin, b))
            gfm_by_carrier = Dict{String,Float64}()
            gfl_by_carrier = Dict{String,Float64}()
            lhs = sigma0
            rhs = 0.0
            battery_gfm_local = 0.0
            for key in _PM.ref(pm, n, :bus_gfm_devices, b)
                d = _PM.ref(pm, n, key[1], key[2])
                carrier = String(get(d, "carrier", "unknown"))
                val = float(get(d, "b_block", 0.0)) * JuMP.value(_PM.var(pm, n, :na_block, key))
                lhs += val
                gfm_by_carrier[carrier] = get(gfm_by_carrier, carrier, 0.0) + val
                if carrier == "battery_gfm"
                    battery_gfm_local += val
                end
            end
            for key in _PM.ref(pm, n, :bus_gfl_devices, b)
                d = _PM.ref(pm, n, key[1], key[2])
                carrier = String(get(d, "carrier", "unknown"))
                val = gmin * float(get(d, "p_block_max", 0.0)) * JuMP.value(_PM.var(pm, n, :na_block, key))
                rhs += val
                gfl_by_carrier[carrier] = get(gfl_by_carrier, carrier, 0.0) + val
            end
            margin = lhs - rhs
            near_binding += (margin <= 1e-6 ? 1 : 0)
            violated += (margin < -1e-6 ? 1 : 0)
            if margin < min_margin
                min_margin = margin
                weak_bus = b
                weak_nw = n
            end
            push!(rows, Dict(
                "snapshot" => n,
                "bus" => b,
                "margin" => margin,
                "lhs_sigma0_G" => sigma0,
                "lhs_gfm_contribution_by_carrier" => gfm_by_carrier,
                "rhs_gfl_exposure_by_carrier" => gfl_by_carrier,
                "battery_gfm_contribution" => battery_gfm_local,
            ))
        end
    end
    sort!(rows, by=r -> r["margin"])
    weakest = rows[1:min(20, length(rows))]
    weak_buses = Set(r["bus"] for r in weakest)
    invest_by_bus = get(metrics, "investment_by_bus", Dict{Int,Float64}())
    local_invest = any(get(invest_by_bus, b, 0.0) > 1e-8 for b in weak_buses)
    return Dict(
        "gscr_reconstruction_residual" => get(metrics["physical_plausibility"], "gscr_reconstruction_residual", nothing),
        "min_gscr_margin" => (isfinite(min_margin) ? min_margin : nothing),
        "weakest_bus" => weak_bus,
        "weakest_snapshot" => weak_nw,
        "near_binding_count" => near_binding,
        "violated_gscr_count" => violated,
        "top_weakest_constraints" => weakest,
        "battery_gfm_contribution_at_weakest_bus" => (isempty(rows) ? 0.0 : rows[1]["battery_gfm_contribution"]),
        "gfm_investment_local_to_weak_buses" => local_invest,
    )
end

function _write_json(path::String, obj)
    open(path, "w") do io
        JSON.print(io, obj, 2)
    end
end

function _write_csv(path::String, header::Vector{String}, rows::AbstractVector{<:AbstractVector})
    open(path, "w") do io
        writedlm(io, [header], ',')
        for r in rows
            writedlm(io, [r], ',')
        end
    end
end

function _solver_summary(model::JuMP.Model, status::String, solve_time::Float64, build_time::Float64)
    return Dict(
        "status" => status,
        "termination_status" => status,
        "primal_status" => string(JuMP.primal_status(model)),
        "dual_status" => string(JuMP.dual_status(model)),
        "objective_value" => try JuMP.objective_value(model) catch; nothing end,
        "solve_time_sec" => solve_time,
        "build_time_sec" => build_time,
        "num_variables" => JuMP.num_variables(model),
        "num_constraints" => _constraint_count(model),
        "relative_gap" => _safe_moi(model, MOI.RelativeGap()),
        "node_count" => _safe_moi(model, MOI.NodeCount()),
        "simplex_iterations" => _safe_moi(model, MOI.SimplexIterations()),
        "barrier_iterations" => _safe_moi(model, MOI.BarrierIterations()),
        "solve_time_moi_sec" => _safe_moi(model, MOI.SolveTimeSec()),
    )
end

function _architecture_safety(pm, metrics)
    nw = minimum(_FP.nw_ids(pm))
    vars = _PM.var(pm, nw)
    arch = get(pm.ext, :uc_gscr_block_architecture_diagnostics, Dict{String,Any}())
    ps_ne_ok = !haskey(vars, :ps_ne) || (_bounds_summary(_PM.var(pm, nw, :ps_ne))["free"] == 0)
    qs_ne_ok = !haskey(vars, :qs_ne) || (_bounds_summary(_PM.var(pm, nw, :qs_ne))["free"] == 0)
    pg_ok = !haskey(vars, :pg) || (_bounds_summary(_PM.var(pm, nw, :pg))["free"] == 0)
    qg_ok = !haskey(vars, :qg) || (_bounds_summary(_PM.var(pm, nw, :qg))["free"] == 0)
    block_env = true
    for row in get(arch, "block_enabled_ne_storage_audit", Any[])
        block_env &= Bool(get(row, "block_envelopes_active", false))
    end
    return Dict(
        "z_strg_ne_present" => haskey(vars, :z_strg_ne),
        "z_strg_ne_investment_present" => haskey(vars, :z_strg_ne_investment),
        "uses_standard_candidate_build_variables" => get(arch, "uses_standard_candidate_build_variables", nothing),
        "uses_standard_candidate_investment_cost" => get(arch, "uses_standard_candidate_investment_cost", nothing),
        "ps_ne_coupled_not_free" => ps_ne_ok,
        "qs_ne_bounded_or_not_created" => qs_ne_ok,
        "pg_not_free" => pg_ok,
        "qg_not_free" => qg_ok,
        "block_storage_envelopes_active" => block_env,
        "max_storage_state_residual" => get(metrics["physical_plausibility"], "max_storage_state_residual", nothing),
    )
end

function _block_integrality_summary(pm)
    summary = Dict{String,Any}(
        "relax_block_variables" => false,
        "expected_integer_block_variables" => true,
        "variables" => Dict{String,Any}(),
    )
    all_integer = true
    for sym in (:n_block, :na_block, :su_block, :sd_block)
        count_total = 0
        count_integer = 0
        count_continuous = 0
        max_fractionality = 0.0
        checked_values = 0
        for n in sort(collect(_FP.nw_ids(pm)))
            vars = _PM.var(pm, n)
            if !haskey(vars, sym)
                continue
            end
            for v in values(_PM.var(pm, n, sym))
                count_total += 1
                if JuMP.is_integer(v)
                    count_integer += 1
                else
                    count_continuous += 1
                    all_integer = false
                end
                val = try JuMP.value(v) catch; nothing end
                if !isnothing(val) && isfinite(val)
                    checked_values += 1
                    max_fractionality = max(max_fractionality, abs(val - round(val)))
                end
            end
        end
        summary["variables"][String(sym)] = Dict(
            "count" => count_total,
            "integer_count" => count_integer,
            "continuous_count" => count_continuous,
            "max_fractionality_after_solve" => max_fractionality,
            "value_count_checked" => checked_values,
        )
    end
    summary["all_block_variables_integer_created"] = all_integer
    return summary
end

function _stop_due_to_safety(safety::AbstractDict{String,<:Any}, status::String)
    if status in _UNBOUNDED_TERMINATIONS
        return true, "unbounded solver termination"
    end
    if Bool(get(safety, "z_strg_ne_present", true)) || Bool(get(safety, "z_strg_ne_investment_present", true))
        return true, "unexpected z_strg_ne variable present"
    end
    if Bool(get(safety, "uses_standard_candidate_build_variables", true)) || Bool(get(safety, "uses_standard_candidate_investment_cost", true))
        return true, "standard candidate path unexpectedly active"
    end
    if !Bool(get(safety, "ps_ne_coupled_not_free", false)) || !Bool(get(safety, "qs_ne_bounded_or_not_created", false))
        return true, "ps_ne/qs_ne unconstrained-variable safety failed"
    end
    if !Bool(get(safety, "block_storage_envelopes_active", false))
        return true, "block storage envelope constraints not active"
    end
    return false, ""
end

function _annual_cost_summary(metrics::Dict{String,Any}, horizon_hours::Int)
    investment = float(get(metrics, "investment_cost", 0.0))
    startup = float(get(metrics, "startup_cost", 0.0))
    shutdown = float(get(metrics, "shutdown_cost", 0.0))
    objective = float(get(metrics, "objective", investment + startup + shutdown))
    operation = max(0.0, objective - investment - startup - shutdown)
    weeks = horizon_hours / 168.0
    scale = 52.0 / weeks
    annual_operation = scale * operation
    annual_startup = scale * startup
    annual_shutdown = scale * shutdown
    total = investment + annual_operation + annual_startup + annual_shutdown
    return Dict(
        "investment_cost" => investment,
        "operation_cost_raw_horizon" => operation,
        "startup_cost_raw_horizon" => startup,
        "shutdown_cost_raw_horizon" => shutdown,
        "horizon_hours" => horizon_hours,
        "number_of_weeks" => weeks,
        "annual_operation_scaling_factor" => scale,
        "annualized_operation_cost" => annual_operation,
        "annualized_startup_cost" => annual_startup,
        "annualized_shutdown_cost" => annual_shutdown,
        "total_annual_system_cost" => total,
        "total_annual_system_cost_BEUR_per_year" => total / 1e9,
    )
end

function _capacity_outputs(pm)
    first_nw = minimum(_FP.nw_ids(pm))
    by_carrier = Dict{String,Float64}()
    by_bus = Dict{Int,Float64}()
    if haskey(_PM.var(pm, first_nw), :n_block)
        for key in keys(_PM.var(pm, first_nw, :n_block))
            dev_key = key[1]
            d = _PM.ref(pm, first_nw, dev_key[1], dev_key[2])
            n0 = float(get(d, "n0", get(d, "n_block0", 0.0)))
            n = JuMP.value(_PM.var(pm, first_nw, :n_block, dev_key))
            cap_gw = max(0.0, n - n0) * float(get(d, "p_block_max", 0.0)) / 1000.0
            carrier = String(get(d, "carrier", "unknown"))
            bus = dev_key[1] == :gen ? Int(get(d, "gen_bus", -1)) : Int(get(d, "storage_bus", -1))
            by_carrier[carrier] = get(by_carrier, carrier, 0.0) + cap_gw
            by_bus[bus] = get(by_bus, bus, 0.0) + cap_gw
        end
    end
    wind = sum(get(by_carrier, c, 0.0) for c in ("onwind", "offwind-ac", "offwind-dc"))
    solar = get(by_carrier, "solar", 0.0)
    return Dict(
        "installed_BESS_GFM_GW" => get(by_carrier, "battery_gfm", 0.0),
        "installed_BESS_GFL_GW" => get(by_carrier, "battery_gfl", 0.0),
        "installed_RES_GW" => wind + solar,
        "installed_wind_GW" => wind,
        "installed_solar_GW" => solar,
        "installed_PV_GW" => solar,
        "installed_CCGT_GW" => get(by_carrier, "CCGT", 0.0),
        "installed_OCGT_GW" => get(by_carrier, "OCGT", 0.0),
        "installed_gas_total_GW" => get(by_carrier, "CCGT", 0.0) + get(by_carrier, "OCGT", 0.0),
        "installed_by_carrier_GW" => by_carrier,
        "installed_by_bus_GW" => by_bus,
    )
end

function _device_bus(d, table::Symbol)
    return table == :gen ? Int(get(d, "gen_bus", -1)) : Int(get(d, "storage_bus", -1))
end

function _online_schedule_rows(pm)
    rows = Vector{Vector}()
    for n in sort(collect(_FP.nw_ids(pm)))
        if !haskey(_PM.var(pm, n), :na_block)
            continue
        end
        raw_keys = Any[]
        for key in keys(_PM.var(pm, n, :na_block))
            push!(raw_keys, key)
        end
        for key in sort(raw_keys; by=x -> (String(x[1][1]), x[1][2]))
            dev_key = key[1]
            table, id = dev_key
            d = _PM.ref(pm, n, table, id)
            pmax = float(get(d, "p_block_max", 0.0))
            bblock = float(get(d, "b_block", 0.0))
            nblock = JuMP.value(_PM.var(pm, n, :n_block, dev_key))
            nablock = JuMP.value(_PM.var(pm, n, :na_block, dev_key))
            push!(rows, [
                n, String(table), id, _device_bus(d, table), get(d, "carrier", "unknown"), get(d, "type", ""),
                pmax, bblock, nblock, nablock, pmax * nablock, bblock * nablock,
            ])
        end
    end
    return rows
end

function _bus_name(pm, nw, bus)
    b = _PM.ref(pm, nw, :bus, bus)
    return string(get(b, "name", get(b, "zone", bus)))
end

function _bus_lat_lon(pm, nw, bus)
    b = _PM.ref(pm, nw, :bus, bus)
    lat = get(b, "lat", get(b, "latitude", get(b, "y", "")))
    lon = get(b, "lon", get(b, "longitude", get(b, "x", "")))
    return lat, lon
end

function _posthoc_strength(pm, g_min::Float64; posthoc_alpha::Float64=(g_min == 0.0 ? _POSTHOC_BASE_ALPHA : g_min), epsilon::Float64=_BINDING_EPSILON)
    timeseries = Dict{String,Any}[]
    kappas_by_bus = Dict{Int,Vector{Float64}}()
    bind_by_bus = Dict{Int,Int}()
    gfm_cap_by_bus = Dict{Int,Float64}()
    gfm_strength_by_bus = Dict{Int,Float64}()
    gfl_peak_by_bus = Dict{Int,Float64}()
    min_gscr = Inf
    min_mu = Inf
    rels = Float64[]
    for n in sort(collect(_FP.nw_ids(pm)))
        buses = sort(collect(_PM.ids(pm, n, :bus)))
        idx = Dict(b => i for (i, b) in enumerate(buses))
        nb = length(buses)
        B = zeros(nb, nb)
        b0 = _PM.ref(pm, n, :gscr_b0)
        for i in buses, j in buses
            B[idx[i], idx[j]] = float(get(b0, (i, j), 0.0))
        end
        Sdiag = zeros(nb)
        kappa = Dict{Int,Float64}()
        total_gfm_strength = 0.0
        total_gfl_exposure = 0.0
        for b in buses
            delta = 0.0
            gflp = 0.0
            gfm_bess_cap = 0.0
            for key in _PM.ref(pm, n, :bus_gfm_devices, b)
                d = _PM.ref(pm, n, key[1], key[2])
                na = JuMP.value(_PM.var(pm, n, :na_block, key))
                delta += float(get(d, "b_block", 0.0)) * na
                if String(get(d, "carrier", "")) == "battery_gfm"
                    gfm_bess_cap += float(get(d, "p_block_max", 0.0)) * na / 1000.0
                end
            end
            for key in _PM.ref(pm, n, :bus_gfl_devices, b)
                d = _PM.ref(pm, n, key[1], key[2])
                gflp += float(get(d, "p_block_max", 0.0)) * JuMP.value(_PM.var(pm, n, :na_block, key))
            end
            B[idx[b], idx[b]] += delta
            Sdiag[idx[b]] = gflp
            total_gfm_strength += delta
            total_gfl_exposure += gflp
            k = float(_PM.ref(pm, n, :gscr_sigma0_gershgorin_margin, b)) + delta - posthoc_alpha * gflp
            kappa[b] = k
            push!(get!(kappas_by_bus, b, Float64[]), k)
            bind_by_bus[b] = get(bind_by_bus, b, 0) + (k <= epsilon ? 1 : 0)
            gfm_cap_by_bus[b] = max(get(gfm_cap_by_bus, b, 0.0), gfm_bess_cap)
            gfm_strength_by_bus[b] = max(get(gfm_strength_by_bus, b, 0.0), delta)
            gfl_peak_by_bus[b] = max(get(gfl_peak_by_bus, b, 0.0), gflp)
        end
        M = Symmetric(B - posthoc_alpha * Diagonal(Sdiag))
        mu = minimum(eigvals(M))
        active = findall(x -> x > 1e-9, Sdiag)
        gscr = Inf
        if !isempty(active)
            vals = eigvals(Symmetric(B[active, active]), Symmetric(Matrix(Diagonal(Sdiag[active]))))
            finite_vals = [real(v) for v in vals if isfinite(real(v))]
            gscr = isempty(finite_vals) ? Inf : minimum(finite_vals)
        end
        rel = isfinite(gscr) ? (gscr - posthoc_alpha) / posthoc_alpha : Inf
        push!(rels, rel)
        min_mu = min(min_mu, mu)
        min_gscr = min(min_gscr, gscr)
        min_bus = first(sort(collect(keys(kappa)); by=b -> kappa[b]))
        local_rel = posthoc_alpha > 0 ? kappa[min_bus] / posthoc_alpha : kappa[min_bus]
        push!(timeseries, Dict(
            "snapshot" => n,
            "mu_t" => mu,
            "gSCR_t" => gscr,
            "relative_margin_rG" => rel,
            "min_kappa" => kappa[min_bus],
            "median_kappa" => median(collect(values(kappa))),
            "min_kappa_bus" => min_bus,
            "binding_node_count" => count(v -> v <= epsilon, values(kappa)),
            "violating_node_count" => count(v -> v < -epsilon, values(kappa)),
            "total_GFL_exposure" => total_gfl_exposure,
            "total_GFM_strength" => total_gfm_strength,
            "local_relative_slack_min" => local_rel,
            "gershgorin_conservatism_gap" => isfinite(gscr) ? gscr - posthoc_alpha - kappa[min_bus] : Inf,
        ))
    end
    node_rows = Dict{String,Any}[]
    snap_count = length(timeseries)
    first_nw = minimum(_FP.nw_ids(pm))
    for b in sort(collect(keys(kappas_by_bus)))
        vals = sort(kappas_by_bus[b])
        p05 = vals[max(1, ceil(Int, 0.05 * length(vals)))]
        push!(node_rows, Dict(
            "bus" => b,
            "region_name" => _bus_name(pm, first_nw, b),
            "beta_i" => get(bind_by_bus, b, 0) / max(1, snap_count),
            "gfm_bess_capacity_GW" => get(gfm_cap_by_bus, b, 0.0),
            "GFM_strength_installed" => get(gfm_strength_by_bus, b, 0.0),
            "GFL_exposure_peak" => get(gfl_peak_by_bus, b, 0.0),
            "min_kappa" => minimum(vals),
            "mean_kappa" => mean(vals),
            "p05_kappa" => p05,
        ))
    end
    sort!(node_rows, by=r -> r["beta_i"], rev=true)
    finite_rels = [r for r in rels if isfinite(r)]
    summary = Dict(
        "posthoc_alpha" => posthoc_alpha,
        "binding_epsilon" => epsilon,
        "min_mu_t" => min_mu,
        "min_gSCR_t" => min_gscr,
        "min_relative_margin_rG" => isempty(finite_rels) ? nothing : minimum(finite_rels),
        "max_relative_margin_rG" => isempty(finite_rels) ? nothing : maximum(finite_rels),
        "mean_relative_margin_rG" => isempty(finite_rels) ? nothing : mean(finite_rels),
        "number_of_snapshots_with_mu_negative" => count(r -> r["mu_t"] < -epsilon, timeseries),
        "number_of_snapshots_with_gSCR_below_alpha" => count(r -> isfinite(r["gSCR_t"]) && r["gSCR_t"] < posthoc_alpha - epsilon, timeseries),
        "top_5_most_binding_regions" => node_rows[1:min(5, length(node_rows))],
    )
    return summary, timeseries, node_rows
end

function _run_one_case(git::Dict{String,Any}, run_name::String, scenario_name::String, case_dir::String, horizon_hours::Int, g_min::Float64)
    dataset_path = normpath(_DATA_ROOT, case_dir, "case.json")
    out_dir = normpath(_OUT_ROOT, run_name)
    mkpath(out_dir)
    timestamp = Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")

    raw = _load_case(dataset_path)
    preprocessing_summary = _remove_excluded_generators!(raw)
    _assert_excluded_generators_absent(raw)
    snap_count = length(raw["nw"])
    data = _prepare_solver_data(raw; mode=:capexp)
    _set_mode_nmax_policy!(data, "full_capexp")
    _apply_existing_storage_initial_energy_policy!(data, "half_energy_rating")
    _drop_deprecated_p_block_min!(data)
    _inject_g_min!(data, g_min)

    run_config = Dict(
        "git_commit" => git["commit"],
        "git_branch" => git["branch"],
        "git_tags" => git["tags"],
        "dataset_path" => dataset_path,
        "scenario_name" => scenario_name,
        "optimization_g_min" => g_min,
        "posthoc_alpha_paper" => _POSTHOC_ALPHA_PAPER,
        "horizon_length" => "$(horizon_hours) h",
        "horizon_hours" => horizon_hours,
        "snapshot_count" => snap_count,
        "number_of_weeks" => 2,
        "annual_operation_scaling_factor" => 26,
        "selected_weeks_policy" => _SELECTED_WEEKS_POLICY,
        "selected_window_source" => "elec_s_37_2weeks_from_0301",
        "excluded_carriers" => _EXCLUDED_CARRIERS_REPORTED,
        "preprocessing" => preprocessing_summary,
        "baseline_strength_policy" => "conservative_no_baseline_strength",
        "investment_cost_policy" => "annualized cost_inv_block used directly; no day/week scaling",
        "g_min" => g_min,
        "final_storage_policy" => "short_horizon_relaxed",
        "block_integrality_policy" => "n_block, na_block, su_block, and sd_block are integer; relax_block_variables=false",
        "relax_block_variables" => false,
        "initial_online_block_policy" => "validated 24h dry-run policy from included helper",
        "startup_shutdown_policy" => "su_block/sd_block only for conventional non-renewable synchronous generators after excluding coal/lignite/oil",
        "solver_name" => _SOLVER_NAME,
        "solver_options" => _GUROBI_OPTIONS,
        "timestamp" => timestamp,
        "continue_on_infeasible" => true,
        "architecture_flags" => Dict(
            "block_only" => true,
            "standard_candidate_expansion" => false,
            "standard_uc" => false,
            "dcline_setpoints" => false,
            "dcline_in_gscr" => false,
        ),
    )
    _write_json(normpath(out_dir, "run_config.json"), run_config)

    build_t0 = time()
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        pm -> _FP.build_uc_gscr_block_integration(pm; final_storage_policy=:short_horizon_relaxed, relax_block_variables=false);
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    build_time = time() - build_t0
    JuMP.set_optimizer(pm.model, Gurobi.Optimizer)
    for (k, v) in _GUROBI_OPTIONS
        JuMP.set_optimizer_attribute(pm.model, k, v)
    end

    t0 = time()
    JuMP.optimize!(pm.model)
    solve_time = time() - t0
    status = string(JuMP.termination_status(pm.model))
    solver_sum = _solver_summary(pm.model, status, solve_time, build_time)
    _write_json(normpath(out_dir, "solver_summary.json"), solver_sum)

    metrics = _collect_controlled_case_metrics(pm, g_min, status)
    safety = _architecture_safety(pm, metrics)
    integrality = _block_integrality_summary(pm)
    _write_json(normpath(out_dir, "block_variable_summary.json"), safety)
    _write_json(normpath(out_dir, "block_integrality_summary.json"), integrality)

    stop_safety, stop_reason = _stop_due_to_safety(safety, status)
    if stop_safety
        _write_json(normpath(out_dir, "objective_summary.json"), Dict("status" => status))
        _write_json(normpath(out_dir, "investment_summary.json"), Dict("status" => status))
        open(normpath(out_dir, "infeasibility_or_failure_report.md"), "w") do io
            println(io, "# Failure Report")
            println(io)
            println(io, "- status: ", status)
            println(io, "- reason: ", stop_reason)
        end
        open(normpath(out_dir, "failure_report.md"), "w") do io
            println(io, "# Failure Report")
            println(io)
            println(io, "- status: ", status)
            println(io, "- reason: ", stop_reason)
        end
        return Dict("run_name" => run_name, "scenario_name" => scenario_name, "horizon_hours" => horizon_hours, "snapshot_count" => snap_count, "g_min" => g_min, "optimization_g_min" => g_min, "posthoc_alpha_paper" => _POSTHOC_ALPHA_PAPER, "status" => status, "stop_entire_campaign" => true, "stop_reason" => stop_reason)
    end

    if !(status in _ACTIVE_OK)
        _write_json(normpath(out_dir, "objective_summary.json"), Dict("status" => status, "objective" => nothing))
        _write_json(normpath(out_dir, "investment_summary.json"), Dict("status" => status))
        open(normpath(out_dir, "infeasibility_or_failure_report.md"), "w") do io
            println(io, "# Failure Report")
            println(io)
            println(io, "- status: ", status)
            println(io, "- termination_status: ", status)
            println(io, "- model construction error: false")
            println(io, "- unbounded: ", status in _UNBOUNDED_TERMINATIONS)
        end
        open(normpath(out_dir, "failure_report.md"), "w") do io
            println(io, "# Failure Report")
            println(io)
            println(io, "- status: ", status)
            println(io, "- termination_status: ", status)
            println(io, "- model construction error: false")
            println(io, "- unbounded: ", status in _UNBOUNDED_TERMINATIONS)
        end
        return Dict("run_name" => run_name, "scenario_name" => scenario_name, "horizon_hours" => horizon_hours, "snapshot_count" => snap_count, "g_min" => g_min, "optimization_g_min" => g_min, "posthoc_alpha_paper" => _POSTHOC_ALPHA_PAPER, "status" => status, "stop_entire_campaign" => false)
    end

    ac = _ac_loading(pm)
    dc = _dcline_loading(pm)
    bal = _balance_residuals(pm)
    st = _storage_details(pm, metrics)
    blk = _block_details(pm, metrics)
    gscr = _gscr_details(pm, metrics)
    cost_summary = _annual_cost_summary(metrics, horizon_hours)
    capacity_summary = _capacity_outputs(pm)
    posthoc_summary, posthoc_ts, node_binding = _posthoc_strength(pm, g_min; posthoc_alpha=_POSTHOC_ALPHA_PAPER)
    own_posthoc_summary, own_posthoc_ts, _ = _posthoc_strength(pm, g_min; posthoc_alpha=g_min)
    posthoc_summary["min_mu_t_alpha_1p5"] = posthoc_summary["min_mu_t"]
    posthoc_summary["violating_snapshots_percent_alpha_1p5"] = 100.0 * posthoc_summary["number_of_snapshots_with_mu_negative"] / max(1, snap_count)
    posthoc_summary["own_target_mu_t"] = own_posthoc_summary["min_mu_t"]
    posthoc_summary["optimization_g_min"] = g_min
    posthoc_summary["posthoc_alpha_paper"] = _POSTHOC_ALPHA_PAPER
    posthoc_summary["own_target_number_of_snapshots_with_mu_negative"] = own_posthoc_summary["number_of_snapshots_with_mu_negative"]

    objective_summary = Dict(
        "status" => status,
        "objective" => metrics["objective"],
        "investment_cost" => metrics["investment_cost"],
        "startup_cost" => metrics["startup_cost"],
        "shutdown_cost" => metrics["shutdown_cost"],
        "solve_time_sec" => solve_time,
        "build_time_sec" => build_time,
    )
    _write_json(normpath(out_dir, "objective_summary.json"), objective_summary)
    _write_json(normpath(out_dir, "cost_summary.json"), cost_summary)
    _write_json(normpath(out_dir, "capacity_summary.json"), capacity_summary)

    total_blocks = get(metrics, "generator_invested_blocks", 0.0) + get(metrics, "storage_invested_blocks", 0.0)
    invest_summary = Dict(
        "total_invested_blocks" => total_blocks,
        "invested_blocks_by_carrier" => metrics["investment_by_carrier"],
        "invested_blocks_by_bus" => metrics["investment_by_bus"],
        "battery_gfl_invested_blocks" => metrics["battery_gfl_invested_blocks"],
        "battery_gfm_invested_blocks" => metrics["battery_gfm_invested_blocks"],
        "generator_invested_blocks" => metrics["generator_invested_blocks"],
        "storage_invested_blocks" => metrics["storage_invested_blocks"],
        "total_gfm_strength_investment" => sum(values(metrics["online_gfm_blocks_by_snapshot"]); init=0.0),
    )
    _write_json(normpath(out_dir, "investment_summary.json"), invest_summary)

    _write_csv(
        normpath(out_dir, "investment_by_carrier.csv"),
        ["carrier", "installed_capacity_GW"],
        [[k, v] for (k, v) in sort(collect(capacity_summary["installed_by_carrier_GW"]); by=first)],
    )
    _write_csv(
        normpath(out_dir, "investment_by_bus.csv"),
        ["bus", "installed_capacity_GW"],
        [[k, v] for (k, v) in sort(collect(capacity_summary["installed_by_bus_GW"]); by=first)],
    )
    _write_csv(
        normpath(out_dir, "dispatch_by_carrier.csv"),
        ["carrier", "generation", "storage_discharge", "storage_charge"],
        [[c, get(metrics["generation_by_carrier"], c, 0.0), get(metrics["storage_discharge_by_carrier"], c, 0.0), get(metrics["storage_charge_by_carrier"], c, 0.0)] for c in sort(collect(Set(vcat(collect(keys(metrics["generation_by_carrier"])), collect(keys(metrics["storage_discharge_by_carrier"])), collect(keys(metrics["storage_charge_by_carrier"]))))))],
    )

    _write_json(normpath(out_dir, "storage_summary.json"), st)
    _write_csv(
        normpath(out_dir, "storage_timeseries_summary.csv"),
        ["snapshot", "online_gfm_strength", "online_gfl_exposure"],
        [[n, get(metrics["online_gfm_blocks_by_snapshot"], n, 0.0), get(metrics["online_gfl_blocks_by_snapshot"], n, 0.0)] for n in sort(collect(_FP.nw_ids(pm)))],
    )

    _write_json(normpath(out_dir, "gscr_summary.json"), gscr)
    _write_json(normpath(out_dir, "gscr_constraint_summary.json"), gscr)
    _write_csv(
        normpath(out_dir, "gscr_weakest_constraints.csv"),
        ["snapshot", "bus", "margin", "sigma0_G", "battery_gfm_contribution"],
        [[r["snapshot"], r["bus"], r["margin"], r["lhs_sigma0_G"], r["battery_gfm_contribution"]] for r in gscr["top_weakest_constraints"]],
    )
    _write_csv(
        normpath(out_dir, "online_schedule.csv"),
        ["snapshot", "component_table", "component_id", "bus", "carrier", "type", "p_block_max", "b_block", "n_block", "na_block", "online_capacity_MW", "online_strength"],
        _online_schedule_rows(pm),
    )
    _write_json(normpath(out_dir, "posthoc_strength_summary.json"), posthoc_summary)
    _write_csv(
        normpath(out_dir, "posthoc_strength_timeseries.csv"),
        ["snapshot", "mu_t", "min_mu_t_alpha_1p5", "gSCR_t", "relative_margin_rG", "min_kappa", "median_kappa", "min_kappa_bus", "binding_node_count", "violating_node_count", "total_GFL_exposure", "total_GFM_strength", "local_relative_slack_min", "gershgorin_conservatism_gap"],
        [[r["snapshot"], r["mu_t"], r["mu_t"], r["gSCR_t"], r["relative_margin_rG"], r["min_kappa"], r["median_kappa"], r["min_kappa_bus"], r["binding_node_count"], r["violating_node_count"], r["total_GFL_exposure"], r["total_GFM_strength"], r["local_relative_slack_min"], r["gershgorin_conservatism_gap"]] for r in posthoc_ts],
    )
    _write_csv(
        normpath(out_dir, "node_binding_frequency.csv"),
        ["bus", "region_name", "beta_i", "gfm_bess_capacity_GW", "GFM_strength_installed", "GFL_exposure_peak", "min_kappa", "mean_kappa", "p05_kappa"],
        [[r["bus"], r["region_name"], r["beta_i"], r["gfm_bess_capacity_GW"], r["GFM_strength_installed"], r["GFL_exposure_peak"], r["min_kappa"], r["mean_kappa"], r["p05_kappa"]] for r in node_binding],
    )

    _write_csv(
        normpath(out_dir, "ac_branch_loading_top.csv"),
        ["branch_id", "from_bus", "to_bus", "snapshot", "flow", "rating", "loading_ratio"],
        [[r["branch_id"], r["from_bus"], r["to_bus"], r["snapshot"], r["flow"], r["rating"], r["loading_ratio"]] for r in ac["top"]],
    )
    _write_csv(
        normpath(out_dir, "dcline_loading_top.csv"),
        ["dcline_id", "from_bus", "to_bus", "snapshot", "flow_from_side", "flow_to_side", "pmin", "pmax", "loading_ratio", "sign_loss_consistency"],
        [[r["dcline_id"], r["from_bus"], r["to_bus"], r["snapshot"], r["flow_from_side"], r["flow_to_side"], r["pmin"], r["pmax"], r["loading_ratio"], r["sign_loss_consistency"]] for r in dc["top"]],
    )

    residual_summary = Dict(
        "max_bus_active_power_balance_residual" => bal["max_bus_active_power_balance_residual"],
        "max_system_active_power_balance_residual" => bal["max_system_active_power_balance_residual"],
        "max_storage_state_residual" => st["max_storage_energy_balance_residual"],
        "max_startup_shutdown_transition_residual" => blk["max_startup_shutdown_transition_residual"],
        "gscr_reconstruction_residual" => gscr["gscr_reconstruction_residual"],
        "max_AC_branch_loading" => ac["max_loading"],
        "AC_overload_count" => ac["overload_count"],
        "max_dcline_loading" => dc["max_loading"],
        "dcline_overload_count" => dc["overload_count"],
        "storage_final_initial_energy_ratio" => st["final_initial_storage_ratio"],
        "total_storage_charge" => st["total_charge"],
        "total_storage_discharge" => st["total_discharge"],
        "balance" => bal,
        "storage" => Dict(
            "max_storage_state_residual" => st["max_storage_energy_balance_residual"],
            "max_storage_envelope_residual" => st["max_storage_energy_envelope_residual"],
            "max_storage_charge_envelope_residual" => st["max_charge_envelope_residual"],
            "max_storage_discharge_envelope_residual" => st["max_discharge_envelope_residual"],
        ),
        "block" => blk,
        "gscr" => Dict(
            "gscr_reconstruction_residual" => gscr["gscr_reconstruction_residual"],
            "min_gscr_margin" => gscr["min_gscr_margin"],
        ),
    )
    _write_json(normpath(out_dir, "residual_summary.json"), residual_summary)

    open(normpath(out_dir, "run_report.md"), "w") do io
        println(io, "# $(run_name)")
        println(io)
        println(io, "- status: ", status)
        println(io, "- objective_raw_horizon: ", metrics["objective"])
        println(io, "- total_annual_system_cost_BEUR_per_year: ", cost_summary["total_annual_system_cost_BEUR_per_year"])
        println(io, "- solve_time_sec: ", solve_time)
        println(io, "- scenario_name: ", scenario_name)
        println(io, "- optimization_g_min: ", g_min)
        println(io, "- posthoc_alpha_paper: ", _POSTHOC_ALPHA_PAPER)
        println(io, "- selected_weeks_policy: ", _SELECTED_WEEKS_POLICY)
        println(io, "- excluded_carriers: coal, lignite, oil")
        println(io, "- removed_generator_records_total: ", preprocessing_summary["removed_generator_records_total"])
        println(io, "- startup_shutdown_policy: su_block/sd_block only for conventional non-renewable synchronous generators after excluding coal/lignite/oil")
        println(io, "- min_gSCR_margin: ", gscr["min_gscr_margin"])
        println(io, "- min_mu_t_alpha_1p5: ", posthoc_summary["min_mu_t_alpha_1p5"])
        println(io, "- min_gSCR_t: ", posthoc_summary["min_gSCR_t"])
        println(io, "- own_target_mu_t: ", posthoc_summary["own_target_mu_t"])
        println(io, "- weakest_bus/snapshot: ", gscr["weakest_bus"], " / ", gscr["weakest_snapshot"])
        println(io, "- max_AC_branch_loading: ", ac["max_loading"])
        println(io, "- max_dcline_loading: ", dc["max_loading"])
        println(io, "- max_bus_balance_residual: ", bal["max_bus_active_power_balance_residual"])
        println(io, "- max_storage_state_residual: ", st["max_storage_energy_balance_residual"])
    end

    return Dict(
        "run_name" => run_name,
        "scenario_name" => scenario_name,
        "horizon_hours" => horizon_hours,
        "snapshot_count" => snap_count,
        "g_min" => g_min,
        "optimization_g_min" => g_min,
        "posthoc_alpha_paper" => _POSTHOC_ALPHA_PAPER,
        "status" => status,
        "objective" => metrics["objective"],
        "solve_time" => solve_time,
        "relative_gap" => solver_sum["relative_gap"],
        "total_invested_blocks" => total_blocks,
        "battery_gfl_blocks" => metrics["battery_gfl_invested_blocks"],
        "battery_gfm_blocks" => metrics["battery_gfm_invested_blocks"],
        "total_GFM_strength" => sum(values(metrics["online_gfm_blocks_by_snapshot"]); init=0.0),
        "investment_cost" => metrics["investment_cost"],
        "startup_cost" => metrics["startup_cost"],
        "shutdown_cost" => metrics["shutdown_cost"],
        "total_annual_system_cost_BEUR_per_year" => cost_summary["total_annual_system_cost_BEUR_per_year"],
        "installed_BESS_GFM_GW" => capacity_summary["installed_BESS_GFM_GW"],
        "installed_BESS_GFL_GW" => capacity_summary["installed_BESS_GFL_GW"],
        "installed_RES_GW" => capacity_summary["installed_RES_GW"],
        "installed_wind_GW" => capacity_summary["installed_wind_GW"],
        "installed_PV_GW" => capacity_summary["installed_PV_GW"],
        "installed_CCGT_GW" => capacity_summary["installed_CCGT_GW"],
        "installed_OCGT_GW" => capacity_summary["installed_OCGT_GW"],
        "installed_gas_total_GW" => capacity_summary["installed_gas_total_GW"],
        "min_mu_t" => posthoc_summary["min_mu_t"],
        "min_mu_t_alpha_1p5" => posthoc_summary["min_mu_t_alpha_1p5"],
        "violating_snapshots_percent_alpha_1p5" => posthoc_summary["violating_snapshots_percent_alpha_1p5"],
        "own_target_mu_t" => posthoc_summary["own_target_mu_t"],
        "min_gSCR_t" => posthoc_summary["min_gSCR_t"],
        "preprocessing" => preprocessing_summary,
        "total_storage_discharge" => st["total_discharge"],
        "total_storage_charge" => st["total_charge"],
        "final_storage_ratio" => st["final_initial_storage_ratio"],
        "min_gSCR_margin" => gscr["min_gscr_margin"],
        "weakest_bus" => gscr["weakest_bus"],
        "weakest_snapshot" => gscr["weakest_snapshot"],
        "near_binding_count" => gscr["near_binding_count"],
        "max_AC_branch_loading" => ac["max_loading"],
        "AC_overload_count" => ac["overload_count"],
        "max_dcline_loading" => dc["max_loading"],
        "dcline_overload_count" => dc["overload_count"],
        "max_bus_balance_residual" => bal["max_bus_active_power_balance_residual"],
        "max_storage_state_residual" => st["max_storage_energy_balance_residual"],
        "max_startup_shutdown_residual" => blk["max_startup_shutdown_transition_residual"],
        "stop_entire_campaign" => false,
    )
end

function _campaign_outputs(rows::Vector{Dict{String,Any}})
    _write_json(normpath(_OUT_ROOT, "campaign_summary.json"), Dict(
        "generated_at" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "selected_weeks_policy" => _SELECTED_WEEKS_POLICY,
        "excluded_carriers" => _EXCLUDED_CARRIERS_REPORTED,
        "heur_gfm_note" => "HEUR-GFM is not implemented in this campaign.",
        "rows" => rows,
    ))
    header = [
        "run_name", "scenario_name", "horizon_hours", "snapshot_count", "optimization_g_min", "posthoc_alpha_paper", "status", "objective", "solve_time", "relative_gap",
        "total_annual_system_cost_BEUR_per_year", "installed_BESS_GFM_GW", "installed_BESS_GFL_GW", "installed_RES_GW", "installed_wind_GW", "installed_PV_GW", "installed_CCGT_GW", "installed_OCGT_GW", "installed_gas_total_GW",
        "total_invested_blocks", "battery_gfl_blocks", "battery_gfm_blocks", "total_GFM_strength", "investment_cost",
        "startup_cost", "shutdown_cost", "total_storage_discharge", "total_storage_charge", "final_storage_ratio",
        "min_mu_t_alpha_1p5", "min_gSCR_t", "violating_snapshots_percent_alpha_1p5", "own_target_mu_t", "min_gSCR_margin", "weakest_bus", "weakest_snapshot", "near_binding_count", "max_AC_branch_loading",
        "AC_overload_count", "max_dcline_loading", "dcline_overload_count", "max_bus_balance_residual",
        "max_storage_state_residual", "max_startup_shutdown_residual",
    ]
    csv_rows = Vector{Vector}()
    for r in rows
        push!(csv_rows, [
            r["run_name"], get(r, "scenario_name", r["run_name"]), r["horizon_hours"], r["snapshot_count"], get(r, "optimization_g_min", get(r, "g_min", nothing)), get(r, "posthoc_alpha_paper", _POSTHOC_ALPHA_PAPER), r["status"], get(r, "objective", nothing), get(r, "solve_time", nothing), get(r, "relative_gap", nothing),
            get(r, "total_annual_system_cost_BEUR_per_year", nothing), get(r, "installed_BESS_GFM_GW", nothing), get(r, "installed_BESS_GFL_GW", nothing), get(r, "installed_RES_GW", nothing), get(r, "installed_wind_GW", nothing), get(r, "installed_PV_GW", nothing), get(r, "installed_CCGT_GW", nothing), get(r, "installed_OCGT_GW", nothing), get(r, "installed_gas_total_GW", nothing),
            get(r, "total_invested_blocks", nothing), get(r, "battery_gfl_blocks", nothing), get(r, "battery_gfm_blocks", nothing), get(r, "total_GFM_strength", nothing), get(r, "investment_cost", nothing),
            get(r, "startup_cost", nothing), get(r, "shutdown_cost", nothing), get(r, "total_storage_discharge", nothing), get(r, "total_storage_charge", nothing), get(r, "final_storage_ratio", nothing),
            get(r, "min_mu_t_alpha_1p5", nothing), get(r, "min_gSCR_t", nothing), get(r, "violating_snapshots_percent_alpha_1p5", nothing), get(r, "own_target_mu_t", nothing), get(r, "min_gSCR_margin", nothing), get(r, "weakest_bus", nothing), get(r, "weakest_snapshot", nothing), get(r, "near_binding_count", nothing), get(r, "max_AC_branch_loading", nothing),
            get(r, "AC_overload_count", nothing), get(r, "max_dcline_loading", nothing), get(r, "dcline_overload_count", nothing), get(r, "max_bus_balance_residual", nothing),
            get(r, "max_storage_state_residual", nothing), get(r, "max_startup_shutdown_residual", nothing),
        ])
    end
    _write_csv(normpath(_OUT_ROOT, "campaign_comparison.csv"), header, csv_rows)

    _write_csv(
        normpath(_OUT_ROOT, "paper_table_II_summary.csv"),
        ["scenario_name", "optimization_g_min", "posthoc_alpha_paper", "solver_status", "total_annual_system_cost_BEUR_per_year", "delta_cost_vs_BASE_BEUR_per_year", "delta_cost_vs_BASE_percent", "BESS_GFM_GW", "BESS_GFL_GW", "RES_GW", "wind_GW", "PV_GW", "CCGT_GW", "OCGT_GW", "gas_total_GW", "min_mu_t_alpha_1p5", "min_gSCR_t", "violating_snapshots_percent_alpha_1p5", "own_target_mu_t", "solver_wallclock_min"],
        begin
            base_cost = isempty(rows) ? nothing : get(rows[1], "total_annual_system_cost_BEUR_per_year", nothing)
            [[
                get(r, "scenario_name", r["run_name"]),
                get(r, "optimization_g_min", get(r, "g_min", nothing)),
                get(r, "posthoc_alpha_paper", _POSTHOC_ALPHA_PAPER),
                get(r, "status", nothing),
                get(r, "total_annual_system_cost_BEUR_per_year", nothing),
                (isnothing(base_cost) || isnothing(get(r, "total_annual_system_cost_BEUR_per_year", nothing))) ? nothing : get(r, "total_annual_system_cost_BEUR_per_year", nothing) - base_cost,
                (isnothing(base_cost) || abs(base_cost) <= 1e-12 || isnothing(get(r, "total_annual_system_cost_BEUR_per_year", nothing))) ? nothing : 100.0 * (get(r, "total_annual_system_cost_BEUR_per_year", nothing) - base_cost) / base_cost,
                get(r, "installed_BESS_GFM_GW", nothing),
                get(r, "installed_BESS_GFL_GW", nothing),
                get(r, "installed_RES_GW", nothing),
                get(r, "installed_wind_GW", nothing),
                get(r, "installed_PV_GW", nothing),
                get(r, "installed_CCGT_GW", nothing),
                get(r, "installed_OCGT_GW", nothing),
                get(r, "installed_gas_total_GW", nothing),
                get(r, "min_mu_t_alpha_1p5", nothing),
                get(r, "min_gSCR_t", nothing),
                get(r, "violating_snapshots_percent_alpha_1p5", nothing),
                get(r, "own_target_mu_t", nothing),
                get(r, "solve_time", 0.0) / 60.0,
            ] for r in rows]
        end,
    )
    map_rows = Vector{Vector}()
    dist_rows = Vector{Vector}()
    for r in rows
        run_dir = normpath(_OUT_ROOT, r["run_name"])
        node_path = normpath(run_dir, "node_binding_frequency.csv")
        ts_path = normpath(run_dir, "posthoc_strength_timeseries.csv")
        if isfile(node_path)
            raw = readdlm(node_path, ',', Any; header=true)
            data, hdr = raw
            col = Dict(String(hdr[i]) => i for i in eachindex(hdr))
            for i in axes(data, 1)
                bus = data[i, col["bus"]]
                region = data[i, col["region_name"]]
                lat = ""
                lon = ""
                push!(map_rows, [
                    get(r, "scenario_name", r["run_name"]),
                    bus,
                    region,
                    lat,
                    lon,
                    data[i, col["beta_i"]],
                    data[i, col["mean_kappa"]],
                    data[i, col["min_kappa"]],
                    data[i, col["gfm_bess_capacity_GW"]],
                    haskey(col, "GFM_strength_installed") ? data[i, col["GFM_strength_installed"]] : "",
                    haskey(col, "GFL_exposure_peak") ? data[i, col["GFL_exposure_peak"]] : "",
                    "",
                    "lat/lon missing; bus-level RES_GW unavailable in this campaign output",
                ])
            end
        end
        if isfile(ts_path)
            raw = readdlm(ts_path, ',', Any; header=true)
            data, hdr = raw
            col = Dict(String(hdr[i]) => i for i in eachindex(hdr))
            for i in axes(data, 1)
                push!(dist_rows, [
                    get(r, "scenario_name", r["run_name"]),
                    data[i, col["snapshot"]],
                    data[i, col["min_mu_t_alpha_1p5"]],
                    data[i, col["gSCR_t"]],
                    data[i, col["relative_margin_rG"]],
                    data[i, col["min_kappa"]],
                    data[i, col["median_kappa"]],
                    data[i, col["binding_node_count"]],
                    data[i, col["violating_node_count"]],
                    data[i, col["total_GFL_exposure"]],
                    data[i, col["total_GFM_strength"]],
                ])
            end
        end
    end
    _write_csv(normpath(_OUT_ROOT, "paper_figure_1_spatial_map.csv"), ["scenario_name", "bus_id", "bus_name", "latitude", "longitude", "binding_frequency_beta", "mean_kappa", "min_kappa", "BESS_GFM_GW", "GFM_strength_installed", "GFL_exposure_peak", "RES_GW", "note"], map_rows)
    _write_csv(normpath(_OUT_ROOT, "paper_figure_2_distribution.csv"), ["scenario_name", "t", "min_mu_t_alpha_1p5", "gSCR_t", "relative_margin_r_t", "min_local_kappa", "median_local_kappa", "number_binding_nodes", "number_violating_nodes_if_any", "total_GFL_exposure", "total_GFM_strength"], dist_rows)

    solved = [r for r in rows if get(r, "status", "") in _ACTIVE_OK]
    failed = [r for r in rows if !(get(r, "status", "") in _ACTIVE_OK)]
    open(normpath(_OUT_ROOT, "campaign_summary.md"), "w") do io
        println(io, "# Paper elec_s_37 336h CAPEXP/gSCR Campaign")
        println(io)
        println(io, "- solved cases: ", length(solved))
        println(io, "- failed/infeasible cases: ", length(failed))
        println(io, "- selected_weeks_policy: ", _SELECTED_WEEKS_POLICY)
        println(io, "- source dataset: elec_s_37_2weeks_from_0301")
        println(io, "- excluded_carriers: coal, lignite, oil")
        println(io, "- excluded aliases removed: hard coal")
        println(io, "- HEUR-GFM is not implemented in this campaign.")
        println(io, "- missing optional fields: bus latitude/longitude; bus-level RES_GW in paper_figure_1_spatial_map.csv")
        println(io, "- startup/shutdown costs are applied only through the existing conventional non-renewable synchronous su_block/sd_block policy after coal/lignite/oil exclusion.")
        println(io)
        println(io, "## Runs")
        for r in rows
            println(io, "- ", get(r, "scenario_name", r["run_name"]), ": status=", r["status"], ", objective=", _fmt(get(r, "objective", nothing)), ", min_gSCR_margin=", _fmt(get(r, "min_gSCR_margin", nothing)))
        end
        println(io)
        println(io, "## 336h Technical Matrix")
        for r in rows
            println(io, "- ", get(r, "scenario_name", r["run_name"]),
                ": optimization_g_min=", _fmt(get(r, "optimization_g_min", nothing)),
                ", total_annual_system_cost_BEUR_per_year=", _fmt(get(r, "total_annual_system_cost_BEUR_per_year", nothing)),
                ", BESS-GFM_GW=", _fmt(get(r, "installed_BESS_GFM_GW", nothing)),
                ", BESS-GFL_GW=", _fmt(get(r, "installed_BESS_GFL_GW", nothing)),
                ", RES_GW=", _fmt(get(r, "installed_RES_GW", nothing)),
                ", wind_GW=", _fmt(get(r, "installed_wind_GW", nothing)),
                ", PV_GW=", _fmt(get(r, "installed_PV_GW", nothing)),
                ", CCGT_GW=", _fmt(get(r, "installed_CCGT_GW", nothing)),
                ", OCGT_GW=", _fmt(get(r, "installed_OCGT_GW", nothing)),
                ", solver_wallclock_min=", _fmt(get(r, "solve_time", 0.0) / 60.0),
                ", min_mu_t_alpha_1p5=", _fmt(get(r, "min_mu_t_alpha_1p5", nothing)),
                ", min_gSCR_t=", _fmt(get(r, "min_gSCR_t", nothing)),
                ", violating_snapshots_percent_alpha_1p5=", _fmt(get(r, "violating_snapshots_percent_alpha_1p5", nothing)),
                ", own_target_mu_t=", _fmt(get(r, "own_target_mu_t", nothing)))
        end
        base = findfirst(r -> get(r, "scenario_name", "") == "BASE", rows)
        g10 = findfirst(r -> get(r, "scenario_name", "") == "gSCR-GERSH-1p0", rows)
        g15 = findfirst(r -> get(r, "scenario_name", "") == "gSCR-GERSH-1p5", rows)
        println(io)
        println(io, "## Validation Flags")
        if !isnothing(base)
            r = rows[base]
            println(io, "- BASE violates post-hoc system strength at alpha=1.5: ", get(r, "min_mu_t_alpha_1p5", 0.0) < -_BINDING_EPSILON)
        end
        if !isnothing(g15)
            r = rows[g15]
            println(io, "- gSCR-GERSH-1p5 satisfies mu_t >= 0 at alpha=1.5: ", get(r, "min_mu_t_alpha_1p5", -Inf) >= -_BINDING_EPSILON)
        end
        if !isnothing(g10)
            r = rows[g10]
            println(io, "- gSCR-GERSH-1p0 satisfies its own target g_min=1.0: ", get(r, "own_target_mu_t", -Inf) >= -_BINDING_EPSILON)
            println(io, "- gSCR-GERSH-1p0 satisfies paper target alpha=1.5: ", get(r, "min_mu_t_alpha_1p5", -Inf) >= -_BINDING_EPSILON)
        end
    end
end

function main()
    git = _git_info()
    mkpath(_OUT_ROOT)

    for d in ["elec_s_37_2weeks_from_0301"]
        case_path = normpath(_DATA_ROOT, d, "case.json")
        if !isfile(case_path)
            error("Required dataset missing: $case_path")
        end
        raw_check = _load_case(case_path)
        if length(raw_check["nw"]) != 336
            error("Required 336h dataset has $(length(raw_check["nw"])) snapshots: $case_path")
        end
    end

    rows = Dict{String,Any}[]
    stop_campaign = false
    stage_g0_failed = false

    for (run_name, scenario_name, case_dir, hours, gmin) in _RUNS
        if stop_campaign
            break
        end

        run_dir = normpath(_OUT_ROOT, run_name)
        if isdir(run_dir) && isfile(normpath(run_dir, "solver_summary.json"))
            error("Refusing to overwrite completed run directory: $run_dir")
        end

        row = _run_one_case(git, run_name, scenario_name, case_dir, hours, gmin)
        push!(rows, row)

        if Bool(get(row, "stop_entire_campaign", false))
            stop_campaign = true
            break
        end

        if gmin == 0.0 && !(row["status"] in _ACTIVE_OK)
            stage_g0_failed = true
            break
        end
    end

    _campaign_outputs(rows)

    if stage_g0_failed
        error("Stopped after 336h g_min=0 feasibility failure by policy.")
    end
end

main()
