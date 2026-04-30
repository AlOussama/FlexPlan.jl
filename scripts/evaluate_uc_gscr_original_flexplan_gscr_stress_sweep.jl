import CSV
import DataFrames
import FlexPlan as _FP
import HiGHS
import JuMP
import Memento
import PowerModels as _PM

const ROOT = normpath(@__DIR__, "..")
const REPORT_MD = normpath(ROOT, "reports", "original_flexplan_uc_gscr_stress_sweep.md")
const REPORT_CSV = normpath(ROOT, "reports", "original_flexplan_uc_gscr_stress_sweep.csv")
const CASE2_STRG = normpath(ROOT, "test", "data", "case2", "case2_d_strg.m")
const REJECTED_V1_FIELDS = Set([
    "type",
    "cost_inv_block",
    "startup_block_cost",
    "shutdown_block_cost",
    "activation_policy",
    "uc_policy",
    "gscr_exposure_policy",
])

Memento.setlevel!(Memento.getlogger(_PM), "error")

schema_v2() = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")

function add_block_fields!(
    device::Dict{String,Any},
    mode::String;
    carrier::String,
    n0::Real,
    nmax::Real,
    na0::Real,
    p_block_max::Real,
    q_block_min::Real=get(device, "qmin", -1.0),
    q_block_max::Real=get(device, "qmax", 1.0),
    b_block::Real=(mode == "gfm" ? 1.0 : 0.0),
    cost_inv_per_mw::Real=1.0,
    startup_cost_per_mw::Union{Nothing,Real}=1.0,
    shutdown_cost_per_mw::Union{Nothing,Real}=1.0,
    e_block::Union{Nothing,Real}=nothing,
)
    device["carrier"] = carrier
    device["grid_control_mode"] = mode
    device["n0"] = Float64(n0)
    device["nmax"] = Float64(nmax)
    device["na0"] = Float64(na0)
    device["p_block_max"] = Float64(p_block_max)
    device["q_block_min"] = Float64(q_block_min)
    device["q_block_max"] = Float64(q_block_max)
    device["b_block"] = Float64(b_block)
    device["cost_inv_per_mw"] = Float64(cost_inv_per_mw)
    device["p_min_pu"] = 0.0
    device["p_max_pu"] = 1.0
    if !isnothing(startup_cost_per_mw)
        device["startup_cost_per_mw"] = Float64(startup_cost_per_mw)
    end
    if !isnothing(shutdown_cost_per_mw)
        device["shutdown_cost_per_mw"] = Float64(shutdown_cost_per_mw)
    end
    if !isnothing(e_block)
        device["e_block"] = Float64(e_block)
    end
    return device
end

function stamp_network_fields!(data::Dict{String,Any}; g_min::Float64)
    for (_, nw) in data["nw"]
        nw["block_model_schema"] = schema_v2()
        nw["operation_weight"] = 1.0
        nw["time_elapsed"] = get(nw, "time_elapsed", 1.0)
        nw["g_min"] = g_min
    end
    return data
end

function stress_fixture(; hours::Int=2, g_min::Float64, gfm_b_block::Float64, gfm_cost_multiplier::Float64)
    data = _FP.parse_file(CASE2_STRG)
    data["block_model_schema"] = schema_v2()
    data["operation_weight"] = 1.0
    data["time_elapsed"] = get(data, "time_elapsed", 1.0)
    data["g_min"] = g_min

    gfl = data["gen"]["1"]
    gfl["dispatchable"] = true
    gfl["pmin"] = 0.0
    gfl["pmax"] = 10.0
    add_block_fields!(
        gfl,
        "gfl";
        carrier="stress-gfl",
        n0=1,
        nmax=2,
        na0=1,
        p_block_max=10.0,
        q_block_min=get(gfl, "qmin", -10.0),
        q_block_max=get(gfl, "qmax", 10.0),
        b_block=0.0,
        cost_inv_per_mw=1.0,
        startup_cost_per_mw=1.0,
        shutdown_cost_per_mw=1.0,
    )

    gfm = deepcopy(gfl)
    gfm["index"] = 2
    gfm["gen_bus"] = gfl["gen_bus"]
    gfm["pmin"] = 0.0
    gfm["pmax"] = 0.0
    gfm["cost"] = [0.0, 0.0]
    add_block_fields!(
        gfm,
        "gfm";
        carrier="stress-gfm",
        n0=0,
        nmax=12,
        na0=0,
        p_block_max=1.0,
        q_block_min=-10.0,
        q_block_max=10.0,
        b_block=gfm_b_block,
        cost_inv_per_mw=20.0 * gfm_cost_multiplier,
        startup_cost_per_mw=nothing,
        shutdown_cost_per_mw=nothing,
    )
    data["gen"]["2"] = gfm

    storage = data["storage"]["1"]
    storage["energy"] = 2.0
    storage["energy_rating"] = 4.0
    storage["charge_rating"] = 2.0
    storage["discharge_rating"] = 2.0
    storage["thermal_rating"] = 2.0
    storage["self_discharge_rate"] = 0.0
    storage["stationary_energy_inflow"] = 0.0
    storage["stationary_energy_outflow"] = 0.0
    add_block_fields!(
        storage,
        "gfm";
        carrier="stress-gfm-storage",
        n0=1,
        nmax=6,
        na0=1,
        p_block_max=1.0,
        q_block_min=get(storage, "qmin", -1.0),
        q_block_max=get(storage, "qmax", 1.0),
        b_block=gfm_b_block,
        cost_inv_per_mw=5.0 * gfm_cost_multiplier,
        startup_cost_per_mw=nothing,
        shutdown_cost_per_mw=nothing,
        e_block=4.0,
    )

    if haskey(data, "ne_storage") && haskey(data["ne_storage"], "1")
        ne = data["ne_storage"]["1"]
        ne["energy"] = 0.0
        ne["energy_rating"] = 4.0
        ne["charge_rating"] = 2.0
        ne["discharge_rating"] = 2.0
        ne["thermal_rating"] = 2.0
        ne["self_discharge_rate"] = 0.0
        ne["stationary_energy_inflow"] = 0.0
        ne["stationary_energy_outflow"] = 0.0
        add_block_fields!(
            ne,
            "gfm";
            carrier="stress-gfm-ne-storage",
            n0=0,
            nmax=6,
            na0=0,
            p_block_max=1.0,
            q_block_min=get(ne, "qmin", -1.0),
            q_block_max=get(ne, "qmax", 1.0),
            b_block=gfm_b_block,
            cost_inv_per_mw=30.0 * gfm_cost_multiplier,
            startup_cost_per_mw=nothing,
            shutdown_cost_per_mw=nothing,
            e_block=4.0,
        )
    end

    _FP.add_dimension!(data, :hour, hours)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    mn = _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
    return stamp_network_fields!(mn; g_min)
end

function validate_fixture!(data::Dict{String,Any})
    for (_, nw) in data["nw"]
        get(nw, "block_model_schema", nothing) == schema_v2() || error("missing schema-v2 marker")
        haskey(nw, "operation_weight") || error("missing operation_weight")
        haskey(nw, "time_elapsed") || error("missing time_elapsed")
        for table in ("gen", "storage", "ne_storage")
            for (_, device) in get(nw, table, Dict{String,Any}())
                rejected = intersect(Set(keys(device)), REJECTED_V1_FIELDS)
                isempty(rejected) || error("rejected v1 fields on $table device: $(collect(rejected))")
                if haskey(device, "grid_control_mode")
                    0.0 <= device["na0"] <= device["n0"] <= device["nmax"] || error("invalid na0/n0/nmax on $table")
                    required = ["carrier", "grid_control_mode", "n0", "nmax", "na0", "p_block_max", "q_block_min", "q_block_max", "b_block", "cost_inv_per_mw", "p_min_pu", "p_max_pu"]
                    for field in required
                        haskey(device, field) || error("missing block field $field on $table")
                    end
                    if table == "gen" && device["grid_control_mode"] == "gfl"
                        haskey(device, "startup_cost_per_mw") || error("missing startup_cost_per_mw on thermal GFL")
                        haskey(device, "shutdown_cost_per_mw") || error("missing shutdown_cost_per_mw on thermal GFL")
                    end
                    if table in ("storage", "ne_storage")
                        haskey(device, "e_block") || error("missing e_block on $table")
                    end
                end
            end
        end
    end
    return true
end

function stress_template(gscr)
    return _FP.UCGSCRBlockTemplate(
        Dict(
            (:gen, "stress-gfl") => _FP.BlockThermalCommitment(),
            (:gen, "stress-gfm") => _FP.BlockFixedInstalled(),
            (:storage, "stress-gfm-storage") => _FP.BlockStorageParticipation(),
            (:ne_storage, "stress-gfm-ne-storage") => _FP.BlockStorageParticipation(),
        ),
        gscr,
    )
end

function build_and_solve(data::Dict{String,Any}; template, storage_terminal_policy::Symbol, storage_terminal_fraction::Float64)
    t0 = time()
    try
        pm = _PM.instantiate_model(
            data,
            _PM.DCPPowerModel,
            pm -> _FP.build_uc_gscr_block_integration(
                pm;
                template,
                storage_terminal_policy,
                storage_terminal_fraction,
            );
            ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
        )
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)
        status = JuMP.termination_status(pm.model)
        objective = status == JuMP.MOI.OPTIMAL ? JuMP.objective_value(pm.model) : missing
        return Dict{String,Any}("pm" => pm, "status" => string(status), "objective" => objective, "solve_time_sec" => time() - t0, "error" => "")
    catch err
        return Dict{String,Any}("pm" => nothing, "status" => "ERROR", "objective" => missing, "solve_time_sec" => time() - t0, "error" => sprint(showerror, err))
    end
end

function device_filter(pm, ref_key::Symbol)
    return (device_key, nw) -> haskey(_PM.ref(pm, nw, ref_key), device_key)
end

function var_total(pm, family::Symbol; filter=(_device_key, _nw) -> true)
    isnothing(pm) && return missing
    total = 0.0
    for nw in _FP.nw_ids(pm)
        haskey(_PM.var(pm, nw), family) || continue
        for device_key in axes(_PM.var(pm, nw, family), 1)
            filter(device_key, nw) || continue
            total += JuMP.value(_PM.var(pm, nw, family, device_key))
        end
    end
    return total
end

function con_count(pm, family::Symbol)
    isnothing(pm) && return 0
    total = 0
    for nw in _FP.nw_ids(pm)
        if haskey(_PM.con(pm, nw), family)
            total += length(_PM.con(pm, nw, family))
        end
    end
    return total
end

function has_con(pm, family::Symbol)
    return con_count(pm, family) > 0
end

function final_storage_energy(pm)
    isnothing(pm) && return missing
    last_nw = maximum(_FP.nw_ids(pm))
    total = 0.0
    if haskey(_PM.var(pm, last_nw), :se)
        total += sum((JuMP.value(_PM.var(pm, last_nw, :se, i)) for i in axes(_PM.var(pm, last_nw, :se), 1)); init=0.0)
    end
    if haskey(_PM.var(pm, last_nw), :se_ne)
        total += sum((JuMP.value(_PM.var(pm, last_nw, :se_ne, i)) for i in axes(_PM.var(pm, last_nw, :se_ne), 1)); init=0.0)
    end
    return total
end

function architecture_guard_passed(pm)
    isnothing(pm) && return false
    diag = get(pm.ext, :uc_gscr_block_architecture_diagnostics, Dict{String,Any}())
    return get(diag, "block_architecture_guard_passed", false)
end

function gershgorin_metrics(pm)
    if isnothing(pm) || !has_con(pm, :gscr_gershgorin_sufficient)
        return Dict("min_margin" => missing, "near_binding_count" => 0, "weakest" => "n/a")
    end
    margins = Vector{Tuple{Int,Int,Float64}}()
    for nw in _FP.nw_ids(pm)
        g_min = _PM.ref(pm, nw, :g_min)
        na = _PM.var(pm, nw, :na_block)
        for bus_id in _PM.ids(pm, nw, :bus)
            sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus_id)
            lhs = sigma0 + sum((_PM.ref(pm, nw, key[1], key[2], "b_block") * JuMP.value(na[key]) for key in _PM.ref(pm, nw, :bus_gfm_devices, bus_id)); init=0.0)
            rhs = g_min * sum((_PM.ref(pm, nw, key[1], key[2], "p_block_max") * JuMP.value(na[key]) for key in _PM.ref(pm, nw, :bus_gfl_devices, bus_id)); init=0.0)
            push!(margins, (nw, bus_id, lhs - rhs))
        end
    end
    minrow = margins[argmin([row[3] for row in margins])]
    near = count(row[3] <= 1e-6 for row in margins)
    return Dict("min_margin" => minrow[3], "near_binding_count" => near, "weakest" => "nw=$(minrow[1]), bus=$(minrow[2])")
end

function row_from_run(; case_id::String, formulation::String, g_min::Float64, gfm_b_block::Float64, gfm_cost_multiplier::Float64, policy::Symbol, fraction::Float64, run::Dict{String,Any}, baseline::Union{Nothing,Dict{String,Any}})
    pm = run["pm"]
    gm = gershgorin_metrics(pm)
    gfm_n = isnothing(pm) ? missing : var_total(pm, :n_block; filter=device_filter(pm, :gfm_devices))
    gfm_na = isnothing(pm) ? missing : var_total(pm, :na_block; filter=device_filter(pm, :gfm_devices))
    gfl_na = isnothing(pm) ? missing : var_total(pm, :na_block; filter=device_filter(pm, :gfl_devices))

    delta_objective = ismissing(run["objective"]) || isnothing(baseline) || ismissing(baseline["objective"]) ? missing : run["objective"] - baseline["objective"]
    delta_gfm_installed = ismissing(gfm_n) || isnothing(baseline) || ismissing(baseline["gfm_n_block_total"]) ? missing : gfm_n - baseline["gfm_n_block_total"]
    delta_gfm_online = ismissing(gfm_na) || isnothing(baseline) || ismissing(baseline["gfm_na_block_total"]) ? missing : gfm_na - baseline["gfm_na_block_total"]
    delta_gfl_online = ismissing(gfl_na) || isnothing(baseline) || ismissing(baseline["gfl_na_block_total"]) ? missing : gfl_na - baseline["gfl_na_block_total"]

    changed = any(!ismissing(x) && abs(x) > 1e-6 for x in (delta_objective, delta_gfm_installed, delta_gfm_online, delta_gfl_online))
    binding = !ismissing(gm["min_margin"]) && (gm["near_binding_count"] > 0 || gm["min_margin"] <= 1e-6)
    classification = run["status"] != "OPTIMAL" ? "infeasible" :
                     changed ? "feasible_gscr_changes_decision" :
                     binding ? "feasible_binding_gscr" :
                     "feasible_nonbinding_gscr"

    note = run["error"]
    if formulation == "NoGSCR" && has_con(pm, :gscr_gershgorin_sufficient)
        note = string(note, " unexpected_gscr_constraints")
    elseif formulation != "NoGSCR" && run["status"] == "OPTIMAL" && !has_con(pm, :gscr_gershgorin_sufficient)
        note = string(note, " missing_gscr_constraints")
    end

    return Dict{String,Any}(
        "case_id" => case_id,
        "formulation" => formulation,
        "g_min" => g_min,
        "gfm_b_block" => gfm_b_block,
        "gfm_cost_multiplier" => gfm_cost_multiplier,
        "storage_terminal_policy" => string(policy),
        "storage_terminal_fraction" => fraction,
        "termination_status" => run["status"],
        "objective" => run["objective"],
        "solve_time_sec" => run["solve_time_sec"],
        "n_block_total" => var_total(pm, :n_block),
        "na_block_total" => var_total(pm, :na_block),
        "su_block_total" => var_total(pm, :su_block),
        "sd_block_total" => var_total(pm, :sd_block),
        "gfm_n_block_total" => gfm_n,
        "gfm_na_block_total" => gfm_na,
        "gfl_na_block_total" => gfl_na,
        "min_gershgorin_margin" => gm["min_margin"],
        "near_binding_count" => gm["near_binding_count"],
        "min_margin_location" => gm["weakest"],
        "gscr_constraint_count" => con_count(pm, :gscr_gershgorin_sufficient),
        "terminal_constraints_present" => has_con(pm, :uc_gscr_storage_terminal),
        "final_storage_energy" => final_storage_energy(pm),
        "architecture_guard_passed" => architecture_guard_passed(pm),
        "delta_objective_vs_nogscr" => delta_objective,
        "delta_gfm_installed_vs_nogscr" => delta_gfm_installed,
        "delta_gfm_online_vs_nogscr" => delta_gfm_online,
        "delta_gfl_online_vs_nogscr" => delta_gfl_online,
        "classification" => classification,
        "notes" => note,
    )
end

function run_one(; case_id::String, formulation::String, g_min::Float64, gfm_b_block::Float64, gfm_cost_multiplier::Float64, policy::Symbol, fraction::Float64, baseline::Union{Nothing,Dict{String,Any}})
    data = stress_fixture(; g_min, gfm_b_block, gfm_cost_multiplier)
    validate_fixture!(data)
    gscr = formulation == "NoGSCR" ? _FP.NoGSCR() : _FP.GershgorinGSCR(_FP.OnlineNameplateExposure())
    run = build_and_solve(data; template=stress_template(gscr), storage_terminal_policy=policy, storage_terminal_fraction=fraction)
    return row_from_run(; case_id, formulation, g_min, gfm_b_block, gfm_cost_multiplier, policy, fraction, run, baseline)
end

function fmt(x)
    if ismissing(x)
        return "missing"
    elseif x isa AbstractFloat
        return string(round(x; sigdigits=7))
    else
        return string(x)
    end
end

function baseline_key(policy::Symbol, fraction::Float64, b::Float64, c::Float64)
    return (string(policy), fraction, b, c)
end

function write_report(rows::Vector{Dict{String,Any}})
    status_counts = Dict(status => count(r["termination_status"] == status for r in rows) for status in unique([r["termination_status"] for r in rows]))
    class_counts = Dict(class => count(r["classification"] == class for r in rows) for class in unique([r["classification"] for r in rows]))
    gscr_rows = [r for r in rows if r["formulation"] != "NoGSCR"]
    any_binding = any(r["classification"] in ("feasible_binding_gscr", "feasible_gscr_changes_decision") for r in gscr_rows)
    any_changes = any(r["classification"] == "feasible_gscr_changes_decision" for r in gscr_rows)
    infeasible_count = count(r["termination_status"] != "OPTIMAL" for r in rows)

    open(REPORT_MD, "w") do io
        println(io, "# Original FlexPlan UC/gSCR gSCR Stress Sweep")
        println(io)
        println(io, "## Purpose")
        println(io)
        println(io, "This analysis-only sweep uses a native FlexPlan `case2_d_strg.m` fixture to test whether the Gershgorin gSCR constraint can become binding or economically visible before external PyPSA fixtures are regenerated.")
        println(io)
        println(io, "## Data And Model Setup")
        println(io)
        println(io, "- Source data: `test/data/case2/case2_d_strg.m`")
        println(io, "- Model type: `DCPPowerModel`")
        println(io, "- Solver: `HiGHS`")
        println(io, "- Template: explicit `UCGSCRBlockTemplate`")
        println(io, "- gSCR formulations: `NoGSCR` and `GershgorinGSCR(OnlineNameplateExposure())`")
        println(io, "- Storage terminal policies: `:none` for the full grid and `:relaxed_cyclic` with `storage_terminal_fraction=0.8` for a focused subset")
        println(io, "- External PyPSA fixtures were not used.")
        println(io)
        println(io, "## Sweep Results")
        println(io)
        println(io, "- Total runs: ", length(rows))
        println(io, "- Status counts: ", status_counts)
        println(io, "- Classification counts: ", class_counts)
        println(io)
        println(io, "| formulation | g_min | b_block | cost_mult | policy | status | objective | min margin | near | GFM n | GFM na | delta obj | class | notes |")
        println(io, "| --- | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |")
        for r in rows
            println(io, "| ", r["formulation"], " | ", fmt(r["g_min"]), " | ", fmt(r["gfm_b_block"]), " | ", fmt(r["gfm_cost_multiplier"]), " | ", r["storage_terminal_policy"], " | ", r["termination_status"], " | ", fmt(r["objective"]), " | ", fmt(r["min_gershgorin_margin"]), " | ", r["near_binding_count"], " | ", fmt(r["gfm_n_block_total"]), " | ", fmt(r["gfm_na_block_total"]), " | ", fmt(r["delta_objective_vs_nogscr"]), " | ", r["classification"], " | ", r["notes"], " |")
        end
        println(io)
        println(io, "## Findings")
        println(io)
        println(io, "- gSCR became binding: ", any_binding)
        println(io, "- gSCR changed objective or block decisions relative to matched NoGSCR baselines: ", any_changes)
        println(io, "- Infeasible runs: ", infeasible_count)
        println(io, "- Storage terminal policy changes objective independently of gSCR when `:relaxed_cyclic` is used; the matching NoGSCR rows provide that baseline.")
        if any_changes
            changed = [r for r in gscr_rows if r["classification"] == "feasible_gscr_changes_decision"]
            best = changed[argmax([ismissing(r["delta_objective_vs_nogscr"]) ? -Inf : abs(r["delta_objective_vs_nogscr"]) for r in changed])]
            println(io, "- Largest visible gSCR effect in this sweep: `", best["case_id"], "` with delta objective ", fmt(best["delta_objective_vs_nogscr"]), ", GFM installed delta ", fmt(best["delta_gfm_installed_vs_nogscr"]), ", and GFM online delta ", fmt(best["delta_gfm_online_vs_nogscr"]), ".")
        else
            println(io, "- The sweep did not find an economically visible gSCR effect in this native case2-derived fixture.")
        end
        println(io, "- The fixture remains useful for smoke/regression testing. Publication-style economics still require a stronger native synthetic case or regenerated PyPSA-derived fixtures with meaningful weak-grid structure.")
        println(io)
        println(io, "## Recommendation")
        println(io)
        if any_changes
            println(io, "Use the identified binding rows as a compact regression/stress fixture, but still treat the case2-derived setup as a diagnostic toy case. For meaningful gSCR economics and plots, regenerate or curate larger fixtures with spatially separated GFL exposure and costly GFM support.")
        else
            println(io, "Generate a stronger synthetic/native case or continue with regenerated PyPSA fixtures for meaningful gSCR economics. The original case2-derived fixture is too small and degenerate for publication-style gSCR plots.")
        end
    end
end

function main()
    g_min_values = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0]
    gfm_b_values = [0.5, 1.0, 2.0]
    cost_multipliers = [1.0, 5.0, 20.0, 50.0]
    policies = [(:none, 1.0)]
    relaxed_subset = Set([(0.5, 1.0), (1.0, 5.0), (2.0, 20.0)])

    rows = Vector{Dict{String,Any}}()
    baselines = Dict{Tuple{String,Float64,Float64,Float64},Dict{String,Any}}()

    for (policy, fraction) in policies
        for b in gfm_b_values, c in cost_multipliers
            case_id = "baseline_$(policy)_b$(b)_c$(c)"
            row = run_one(; case_id, formulation="NoGSCR", g_min=0.0, gfm_b_block=b, gfm_cost_multiplier=c, policy, fraction, baseline=nothing)
            baselines[baseline_key(policy, fraction, b, c)] = row
            push!(rows, row)
            for g_min in g_min_values
                case_id = "gersh_$(policy)_g$(g_min)_b$(b)_c$(c)"
                push!(rows, run_one(; case_id, formulation="GershgorinGSCR", g_min, gfm_b_block=b, gfm_cost_multiplier=c, policy, fraction, baseline=row))
            end
        end
    end

    policy = :relaxed_cyclic
    fraction = 0.8
    for (b, c) in relaxed_subset
        baseline = run_one(; case_id="baseline_$(policy)_b$(b)_c$(c)", formulation="NoGSCR", g_min=0.0, gfm_b_block=b, gfm_cost_multiplier=c, policy, fraction, baseline=nothing)
        push!(rows, baseline)
        for g_min in g_min_values
            case_id = "gersh_$(policy)_g$(g_min)_b$(b)_c$(c)"
            push!(rows, run_one(; case_id, formulation="GershgorinGSCR", g_min, gfm_b_block=b, gfm_cost_multiplier=c, policy, fraction, baseline))
        end
    end

    mkpath(dirname(REPORT_MD))
    CSV.write(REPORT_CSV, DataFrames.DataFrame(rows))
    write_report(rows)
    println("Wrote ", REPORT_MD)
    println("Wrote ", REPORT_CSV)
    println("Runs: ", length(rows))
end

main()
