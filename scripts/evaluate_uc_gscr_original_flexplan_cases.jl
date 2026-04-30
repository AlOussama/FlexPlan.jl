import CSV
import DataFrames
import FlexPlan as _FP
import HiGHS
import JuMP
import Memento
import PowerModels as _PM

include(normpath(@__DIR__, "..", "test", "io", "load_case.jl"))

const ROOT = normpath(@__DIR__, "..")
const REPORT_MD = normpath(ROOT, "reports", "original_flexplan_uc_gscr_small_case_evaluation.md")
const REPORT_CSV = normpath(ROOT, "reports", "original_flexplan_uc_gscr_small_case_summary.csv")
const MILP_OPTIMIZER = _FP.optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false)
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

function case2_multinetwork(file_name::String; hours::Int=2)
    data = _FP.parse_file(normpath(ROOT, "test", "data", "case2", file_name))
    data["operation_weight"] = 1.0
    data["time_elapsed"] = get(data, "time_elapsed", 1.0)
    data["storage"] = get(data, "storage", Dict{String,Any}())
    data["ne_storage"] = get(data, "ne_storage", Dict{String,Any}())
    _FP.add_dimension!(data, :hour, hours)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    mn = _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
    stamp_common_network_fields!(mn; operation_weight=1.0, time_elapsed=data["time_elapsed"])
    return mn
end

function stamp_common_network_fields!(
    data::Dict{String,Any};
    block_schema::Union{Nothing,Dict{String,Any}}=nothing,
    operation_weight::Float64=1.0,
    time_elapsed::Float64=1.0,
    g_min::Union{Nothing,Float64}=nothing,
)
    if haskey(data, "nw")
        for (_, nw) in data["nw"]
            if !isnothing(block_schema)
                nw["block_model_schema"] = deepcopy(block_schema)
            end
            nw["operation_weight"] = operation_weight
            nw["time_elapsed"] = get(nw, "time_elapsed", time_elapsed)
            if !isnothing(g_min)
                nw["g_min"] = g_min
            end
        end
    end
    return data
end

function original_case2_block_fixture(; hours::Int=2, g_min::Float64=0.0)
    data = _FP.parse_file(normpath(ROOT, "test", "data", "case2", "case2_d_strg.m"))
    data["block_model_schema"] = schema_v2()
    data["operation_weight"] = 1.0
    data["time_elapsed"] = get(data, "time_elapsed", 1.0)
    data["g_min"] = g_min

    gen_ids = sort(collect(keys(data["gen"])); by=x -> parse(Int, x))
    gfl = data["gen"][first(gen_ids)]
    gfl["dispatchable"] = true
    gfl["pmin"] = 0.0
    gfl["pmax"] = 10.0
    add_block_fields!(
        gfl,
        "gfl";
        carrier="test-gfl",
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
        carrier="test-gfm",
        n0=0,
        nmax=3,
        na0=0,
        p_block_max=1.0,
        q_block_min=-10.0,
        q_block_max=10.0,
        b_block=5.0,
        cost_inv_per_mw=20.0,
        startup_cost_per_mw=nothing,
        shutdown_cost_per_mw=nothing,
    )
    data["gen"]["2"] = gfm

    storage = data["storage"]["1"]
    storage["energy"] = 2.0
    storage["self_discharge_rate"] = 0.0
    storage["stationary_energy_inflow"] = 0.0
    storage["stationary_energy_outflow"] = 0.0
    add_block_fields!(
        storage,
        "gfm";
        carrier="test-gfm-storage",
        n0=1,
        nmax=2,
        na0=1,
        p_block_max=1.0,
        q_block_min=get(storage, "qmin", -1.0),
        q_block_max=get(storage, "qmax", 1.0),
        b_block=1.0,
        cost_inv_per_mw=5.0,
        startup_cost_per_mw=nothing,
        shutdown_cost_per_mw=nothing,
        e_block=4.0,
    )

    if haskey(data, "ne_storage") && haskey(data["ne_storage"], "1")
        ne = data["ne_storage"]["1"]
        ne["energy"] = 0.0
        ne["energy_rating"] = 2.0
        ne["charge_rating"] = 2.0
        ne["discharge_rating"] = 2.0
        ne["thermal_rating"] = 2.0
        ne["self_discharge_rate"] = 0.0
        ne["stationary_energy_inflow"] = 0.0
        ne["stationary_energy_outflow"] = 0.0
        add_block_fields!(
            ne,
            "gfm";
            carrier="test-gfm-ne-storage",
            n0=0,
            nmax=2,
            na0=0,
            p_block_max=1.0,
            q_block_min=get(ne, "qmin", -1.0),
            q_block_max=get(ne, "qmax", 1.0),
            b_block=1.0,
            cost_inv_per_mw=30.0,
            startup_cost_per_mw=nothing,
            shutdown_cost_per_mw=nothing,
            e_block=4.0,
        )
    end

    _FP.add_dimension!(data, :hour, hours)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    mn = _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
    stamp_common_network_fields!(mn; block_schema=schema_v2(), operation_weight=1.0, time_elapsed=data["time_elapsed"], g_min=g_min)
    return mn
end

function validate_block_fixture!(data::Dict{String,Any})
    for (_, nw) in data["nw"]
        schema = get(nw, "block_model_schema", nothing)
        schema == schema_v2() || error("schema-v2 marker missing or invalid")
        haskey(nw, "operation_weight") || error("operation_weight missing")
        haskey(nw, "time_elapsed") || error("time_elapsed missing")
        for table in ("gen", "storage", "ne_storage")
            for (_, device) in get(nw, table, Dict{String,Any}())
                rejected = intersect(Set(keys(device)), REJECTED_V1_FIELDS)
                isempty(rejected) || error("rejected v1 fields on $table device: $(collect(rejected))")
                if haskey(device, "grid_control_mode")
                    0.0 <= device["na0"] <= device["n0"] <= device["nmax"] || error("invalid na0/n0/nmax on $table")
                    if table in ("storage", "ne_storage")
                        haskey(device, "e_block") || error("block-enabled $table missing e_block")
                    end
                end
            end
        end
    end
    return true
end

function uc_gscr_template(gscr)
    return _FP.UCGSCRBlockTemplate(
        Dict(
            (:gen, "test-gfl") => _FP.BlockThermalCommitment(),
            (:gen, "test-gfm") => _FP.BlockFixedInstalled(),
            (:storage, "test-gfm-storage") => _FP.BlockStorageParticipation(),
            (:ne_storage, "test-gfm-ne-storage") => _FP.BlockStorageParticipation(),
        ),
        gscr,
    )
end

function solve_standard(data::Dict{String,Any}; with_storage::Bool=true)
    t0 = time()
    try
        result = with_storage ? _PM.solve_mn_opf_strg(data, _PM.DCPPowerModel, MILP_OPTIMIZER) :
                 _PM.solve_mn_opf(data, _PM.DCPPowerModel, MILP_OPTIMIZER)
        status = string(get(result, "termination_status", "missing"))
        objective = status == "OPTIMAL" ? get(result, "objective", missing) : missing
        return Dict{String,Any}(
            "status" => status,
            "objective" => objective,
            "solve_time_sec" => time() - t0,
            "error" => "",
        )
    catch err
        return Dict{String,Any}(
            "status" => "ERROR",
            "objective" => missing,
            "solve_time_sec" => time() - t0,
            "error" => sprint(showerror, err),
        )
    end
end

function build_and_solve_uc(data::Dict{String,Any}; template, storage_terminal_policy::Symbol=:none, storage_terminal_fraction::Float64=1.0)
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
        return Dict{String,Any}(
            "pm" => pm,
            "status" => string(status),
            "objective" => objective,
            "solve_time_sec" => time() - t0,
            "error" => "",
        )
    catch err
        return Dict{String,Any}(
            "pm" => nothing,
            "status" => "ERROR",
            "objective" => missing,
            "solve_time_sec" => time() - t0,
            "error" => sprint(showerror, err),
        )
    end
end

function variable_total(pm, family::Symbol; device_filter=(_device_key, _nw) -> true)
    isnothing(pm) && return missing
    total = 0.0
    for nw in _FP.nw_ids(pm)
        if haskey(_PM.var(pm, nw), family)
            for device_key in axes(_PM.var(pm, nw, family), 1)
                device_filter(device_key, nw) || continue
                total += JuMP.value(_PM.var(pm, nw, family, device_key))
            end
        end
    end
    return total
end

function gfm_filter(pm)
    return (device_key, nw) -> haskey(_PM.ref(pm, nw, :gfm_devices), device_key)
end

function has_constraint(pm, family::Symbol)
    isnothing(pm) && return false
    return any(haskey(_PM.con(pm, nw), family) for nw in _FP.nw_ids(pm))
end

function terminal_final_energy(pm)
    isnothing(pm) && return missing
    last_nw = maximum(_FP.nw_ids(pm))
    total = 0.0
    if haskey(_PM.var(pm, last_nw), :se)
        total += sum(JuMP.value(_PM.var(pm, last_nw, :se, i)) for i in axes(_PM.var(pm, last_nw, :se), 1))
    end
    if haskey(_PM.var(pm, last_nw), :se_ne)
        total += sum(JuMP.value(_PM.var(pm, last_nw, :se_ne, i)) for i in axes(_PM.var(pm, last_nw, :se_ne), 1))
    end
    return total
end

function architecture_summary(pm)
    isnothing(pm) && return "not built"
    diag = get(pm.ext, :uc_gscr_block_architecture_diagnostics, Dict{String,Any}())
    return "passed=$(get(diag, "block_architecture_guard_passed", missing)); standard_candidate_build_vars=$(get(diag, "uses_standard_candidate_build_variables", missing)); standard_candidate_activation=$(get(diag, "uses_standard_candidate_activation_constraints", missing)); standard_candidate_cost=$(get(diag, "uses_standard_candidate_investment_cost", missing))"
end

function gershgorin_metrics(pm)
    if isnothing(pm) || !has_constraint(pm, :gscr_gershgorin_sufficient)
        return Dict("min_margin" => missing, "near_binding_count" => 0, "weakest" => "n/a")
    end
    rows = Vector{Tuple{Int,Int,Float64}}()
    for nw in _FP.nw_ids(pm)
        g_min = _PM.ref(pm, nw, :g_min)
        na = _PM.var(pm, nw, :na_block)
        for bus_id in _PM.ids(pm, nw, :bus)
            sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus_id)
            lhs = sigma0 + sum((_PM.ref(pm, nw, key[1], key[2], "b_block") * JuMP.value(na[key]) for key in _PM.ref(pm, nw, :bus_gfm_devices, bus_id)); init=0.0)
            rhs = g_min * sum((_PM.ref(pm, nw, key[1], key[2], "p_block_max") * JuMP.value(na[key]) for key in _PM.ref(pm, nw, :bus_gfl_devices, bus_id)); init=0.0)
            push!(rows, (nw, bus_id, lhs - rhs))
        end
    end
    minrow = rows[argmin([r[3] for r in rows])]
    near = count(abs(r[3]) <= 1e-6 for r in rows)
    return Dict("min_margin" => minrow[3], "near_binding_count" => near, "weakest" => "nw=$(minrow[1]), bus=$(minrow[2])")
end

function collect_uc_row(label::String, run::Dict{String,Any}; source::String, formulation::String, policy::String, g_min=missing, note::String="")
    pm = run["pm"]
    gm = gershgorin_metrics(pm)
    gfm_online = isnothing(pm) ? missing : variable_total(pm, :na_block; device_filter=gfm_filter(pm))
    gfm_installed = isnothing(pm) ? missing : variable_total(pm, :n_block; device_filter=gfm_filter(pm))
    return Dict{String,Any}(
        "case" => label,
        "source" => source,
        "model" => "DCPPowerModel",
        "solver" => "HiGHS",
        "formulation" => formulation,
        "storage_terminal_policy" => policy,
        "g_min" => g_min,
        "status" => run["status"],
        "objective" => run["objective"],
        "solve_time_sec" => run["solve_time_sec"],
        "n_block_total" => variable_total(pm, :n_block),
        "na_block_total" => variable_total(pm, :na_block),
        "su_block_total" => variable_total(pm, :su_block),
        "sd_block_total" => variable_total(pm, :sd_block),
        "gfm_n_block_total" => gfm_installed,
        "gfm_na_block_total" => gfm_online,
        "gscr_constraints_present" => has_constraint(pm, :gscr_gershgorin_sufficient),
        "gscr_min_margin" => gm["min_margin"],
        "gscr_near_binding_count" => gm["near_binding_count"],
        "gscr_weakest" => gm["weakest"],
        "terminal_constraints_present" => has_constraint(pm, :uc_gscr_storage_terminal),
        "final_storage_energy" => terminal_final_energy(pm),
        "architecture_guard" => architecture_summary(pm),
        "note" => isempty(run["error"]) ? note : string(note, " error=", run["error"]),
    )
end

function collect_baseline_row(label::String, source::String, run::Dict{String,Any}; note::String="")
    return Dict{String,Any}(
        "case" => label,
        "source" => source,
        "model" => "DCPPowerModel",
        "solver" => "HiGHS",
        "formulation" => "standard OPF",
        "storage_terminal_policy" => "n/a",
        "g_min" => missing,
        "status" => run["status"],
        "objective" => run["objective"],
        "solve_time_sec" => run["solve_time_sec"],
        "n_block_total" => missing,
        "na_block_total" => missing,
        "su_block_total" => missing,
        "sd_block_total" => missing,
        "gfm_n_block_total" => missing,
        "gfm_na_block_total" => missing,
        "gscr_constraints_present" => false,
        "gscr_min_margin" => missing,
        "gscr_near_binding_count" => 0,
        "gscr_weakest" => "n/a",
        "terminal_constraints_present" => false,
        "final_storage_energy" => missing,
        "architecture_guard" => "n/a",
        "note" => isempty(run["error"]) ? note : string(note, " error=", run["error"]),
    )
end

function fmt(x)
    if ismissing(x)
        return "missing"
    elseif x isa AbstractFloat
        return string(round(x; sigdigits=8))
    else
        return string(x)
    end
end

function write_report(rows)
    open(REPORT_MD, "w") do io
        println(io, "# Original FlexPlan UC/gSCR Small-Case Evaluation")
        println(io)
        println(io, "Generated by `scripts/evaluate_uc_gscr_original_flexplan_cases.jl`.")
        println(io)
        println(io, "## Data Sources")
        println(io)
        println(io, "- `test/data/case2/case2_d_gen.m`")
        println(io, "- `test/data/case2/case2_d_strg.m`")
        println(io, "- `test/io/load_case.jl` via `load_case6(number_of_hours=2, number_of_scenarios=1, number_of_years=1, share_data=false)`")
        println(io, "- No external PyPSA-exported fixtures were used.")
        println(io)
        println(io, "## Scenario Summary")
        println(io)
        println(io, "| case | formulation | policy | g_min | status | objective | n_block | na_block | su | sd | GFM n | GFM na | gSCR constraints | min margin | near-binding | terminal constraints | final storage energy |")
        println(io, "| --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | --- | ---: |")
        for r in rows
            println(io, "| ", r["case"], " | ", r["formulation"], " | ", r["storage_terminal_policy"], " | ", fmt(r["g_min"]), " | ", r["status"], " | ", fmt(r["objective"]), " | ", fmt(r["n_block_total"]), " | ", fmt(r["na_block_total"]), " | ", fmt(r["su_block_total"]), " | ", fmt(r["sd_block_total"]), " | ", fmt(r["gfm_n_block_total"]), " | ", fmt(r["gfm_na_block_total"]), " | ", r["gscr_constraints_present"], " | ", fmt(r["gscr_min_margin"]), " | ", fmt(r["gscr_near_binding_count"]), " | ", r["terminal_constraints_present"], " | ", fmt(r["final_storage_energy"]), " |")
        end
        println(io)
        println(io, "## Architecture Guard Diagnostics")
        println(io)
        for r in rows
            if r["architecture_guard"] != "n/a"
                println(io, "- `", r["case"], "`: ", r["architecture_guard"])
            end
        end
        println(io)
        println(io, "## Notes")
        println(io)
        println(io, "- Block-enabled case2 fixtures are copied in memory from `case2_d_strg.m`; original files are not modified.")
        println(io, "- Schema-v2 validation checks confirm `block_model_schema`, `operation_weight`, and `time_elapsed`, reject legacy v1 block fields, enforce `0 <= na0 <= n0 <= nmax`, and require `e_block` on block-enabled storage.")
        println(io, "- `NoGSCR` cases are checked for absent `:gscr_gershgorin_sufficient` constraints; Gershgorin cases are checked for present constraints.")
        println(io, "- Case6 block annotation is deferred in this report because clean schema-v2 extension across the richer generated time-series fixture is more intrusive than needed for this native-data smoke test.")
        for r in rows
            if !isempty(r["note"])
                println(io, "- `", r["case"], "` note: ", r["note"])
            end
        end
    end
end

function main()
    rows = Vector{Dict{String,Any}}()

    baseline_gen = solve_standard(case2_multinetwork("case2_d_gen.m"; hours=2); with_storage=false)
    push!(rows, collect_baseline_row("A1 case2_d_gen standard", "test/data/case2/case2_d_gen.m", baseline_gen))

    baseline_strg = solve_standard(case2_multinetwork("case2_d_strg.m"; hours=2); with_storage=true)
    push!(rows, collect_baseline_row("A2 case2_d_strg standard", "test/data/case2/case2_d_strg.m", baseline_strg))

    no_gscr_data = original_case2_block_fixture(; hours=2, g_min=0.0)
    validate_block_fixture!(no_gscr_data)
    no_gscr = build_and_solve_uc(no_gscr_data; template=uc_gscr_template(_FP.NoGSCR()), storage_terminal_policy=:none)
    has_constraint(no_gscr["pm"], :gscr_gershgorin_sufficient) && error("NoGSCR case unexpectedly has Gershgorin constraints")
    push!(rows, collect_uc_row("B case2 block NoGSCR", no_gscr, source="test/data/case2/case2_d_strg.m", formulation="NoGSCR", policy="none", g_min=0.0))

    for g_min in (0.1, 1.0)
        g_data = original_case2_block_fixture(; hours=2, g_min)
        validate_block_fixture!(g_data)
        run = build_and_solve_uc(g_data; template=uc_gscr_template(_FP.GershgorinGSCR(_FP.OnlineNameplateExposure())), storage_terminal_policy=:none)
        run["status"] == "OPTIMAL" && !has_constraint(run["pm"], :gscr_gershgorin_sufficient) && error("Gershgorin case missing Gershgorin constraints")
        push!(rows, collect_uc_row("C case2 Gershgorin g_min=$(g_min)", run, source="test/data/case2/case2_d_strg.m", formulation="GershgorinGSCR(OnlineNameplateExposure)", policy="none", g_min=g_min))
    end

    for (policy, fraction) in ((:none, 1.0), (:relaxed_cyclic, 0.8), (:cyclic, 1.0))
        s_data = original_case2_block_fixture(; hours=2, g_min=0.0)
        validate_block_fixture!(s_data)
        run = build_and_solve_uc(s_data; template=uc_gscr_template(_FP.NoGSCR()), storage_terminal_policy=policy, storage_terminal_fraction=fraction)
        push!(rows, collect_uc_row("D storage policy $(policy)", run, source="test/data/case2/case2_d_strg.m", formulation="NoGSCR", policy=string(policy), g_min=0.0))
    end

    case6_data = load_case6(number_of_hours=2, number_of_scenarios=1, number_of_years=1, share_data=false)
    case6_baseline = solve_standard(case6_data; with_storage=true)
    push!(rows, collect_baseline_row("E case6 standard smoke", "test/io/load_case.jl load_case6", case6_baseline; note="Block injection deferred; standard native FlexPlan load_case6 smoke only."))

    mkpath(dirname(REPORT_MD))
    CSV.write(REPORT_CSV, DataFrames.DataFrame(rows))
    write_report(rows)
    println("Wrote ", REPORT_MD)
    println("Wrote ", REPORT_CSV)
end

main()
