using Printf

function _bench_set_block_fields!(device::Dict{String,Any}, type::String; n0, nmax, na0, p_block_min, p_block_max, q_block_min, q_block_max, b_block, cost_inv_block, startup_block_cost, shutdown_block_cost)
    return _uc_gscr_add_block_fields!(
        device,
        type;
        carrier=get(device, "carrier", "test-carrier"),
        n0,
        nmax,
        na0,
        p_block_min,
        p_block_max,
        q_block_min,
        q_block_max,
        b_block,
        cost_inv_per_mw=cost_inv_block,
        startup_cost_per_mw=startup_block_cost,
        shutdown_cost_per_mw=shutdown_block_cost,
    )
end

function _bench_remove_block_fields!(device::Dict{String,Any})
    for field in (
        "type", "grid_control_mode", "carrier", "n0", "nmax", "na0", "p_block_min", "p_block_max", "q_block_min", "q_block_max", "b_block",
        "cost_inv_block", "cost_inv_per_mw", "startup_block_cost", "shutdown_block_cost", "startup_cost_per_mw", "shutdown_cost_per_mw", "p_min_pu", "p_max_pu", "min_up_block_time", "min_down_block_time",
    )
        if haskey(device, field)
            delete!(device, field)
        end
    end
    return device
end

function _bench_uc_gscr_template()
    return _uc_gscr_common_test_template(gscr=_FP.GershgorinGSCR(_FP.OnlineNameplateExposure()))
end

function _bench_sorted_gen_ids(sn_data::Dict{String,Any})
    return sort(
        collect(keys(sn_data["gen"]));
        by = id -> begin
            parsed = tryparse(Int, id)
            isnothing(parsed) ? (typemax(Int), id) : (parsed, id)
        end,
    )
end

function _bench_ensure_second_generator!(sn_data::Dict{String,Any})
    gen_ids = _bench_sorted_gen_ids(sn_data)
    if length(gen_ids) >= 2
        return gen_ids
    end

    first_id = gen_ids[1]
    clone = deepcopy(sn_data["gen"][first_id])
    parsed_ids = [pid for pid in (tryparse(Int, id) for id in gen_ids) if !isnothing(pid)]
    new_int = isempty(parsed_ids) ? 2 : maximum(parsed_ids) + 1
    new_id = string(new_int)
    clone["index"] = new_int
    clone["gen_bus"] = sn_data["gen"][first_id]["gen_bus"]
    clone["pmax"] = 0.0
    clone["pmin"] = 0.0
    clone["cost"] = [0.0, 0.0]
    sn_data["gen"][new_id] = clone

    return _bench_sorted_gen_ids(sn_data)
end

function _bench_scale_loads!(sn_data::Dict{String,Any}; target_total_load::Float64=1.0)
    if !haskey(sn_data, "load") || isempty(sn_data["load"])
        return 1.0
    end
    total = sum(load["pd"] for load in values(sn_data["load"]))
    if total <= 0.0
        return 1.0
    end
    scale = target_total_load / total
    for load in values(sn_data["load"])
        load["pd"] *= scale
        if haskey(load, "qd")
            load["qd"] *= scale
        end
    end
    return scale
end

function _bench_apply_uc_gscr_fields!(sn_data::Dict{String,Any}; mode::Symbol, profile::Symbol, g_min::Float64, target_total_load::Float64=1.0, include_min_up_down::Bool=false)
    sn_data["block_model_schema"] = _uc_gscr_block_schema_v2()
    sn_data["operation_weight"] = 1.0
    sn_data["g_min"] = g_min
    _bench_scale_loads!(sn_data; target_total_load)

    gen_ids = _bench_ensure_second_generator!(sn_data)
    gfl_id = gen_ids[1]
    gfm_id = gen_ids[2]
    gfl_bus = sn_data["gen"][gfl_id]["gen_bus"]

    b_strength = profile == :strong ? 2.0 : 1.0

    for gen_id in gen_ids
        gen = sn_data["gen"][gen_id]
        _bench_remove_block_fields!(gen)

        gen["dispatchable"] = true
        gen["pmin"] = 0.0
        gen["qmin"] = get(gen, "qmin", -1.0)
        gen["qmax"] = get(gen, "qmax", 1.0)

        if gen_id == gfl_id
            gen["pmax"] = 2.0
            _bench_set_block_fields!(
                gen,
                "gfl";
                n0=2,
                nmax=2,
                na0=1,
                p_block_min=0.0,
                p_block_max=1.0,
                q_block_min=gen["qmin"],
                q_block_max=gen["qmax"],
                b_block=0.0,
                cost_inv_block=0.0,
                startup_block_cost=2.0,
                shutdown_block_cost=2.0,
            )
            if include_min_up_down
                gen["min_up_block_time"] = 2
                gen["min_down_block_time"] = 2
            end
        elseif gen_id == gfm_id
            gen["gen_bus"] = gfl_bus
            gen["pmax"] = 0.0

            if mode == :uc
                fixed_n = profile == :strong ? 2 : 1
                n0 = fixed_n
                nmax = fixed_n
                na0 = fixed_n
            else
                n0 = profile == :strong ? 1 : 0
                nmax = profile == :strong ? 4 : 3
                na0 = n0
            end

            _bench_set_block_fields!(
                gen,
                "gfm";
                n0=n0,
                nmax=nmax,
                na0=na0,
                p_block_min=0.0,
                p_block_max=1.0,
                q_block_min=gen["qmin"],
                q_block_max=gen["qmax"],
                b_block=b_strength,
                cost_inv_block=10.0,
                startup_block_cost=3.0,
                shutdown_block_cost=3.0,
            )

            if include_min_up_down
                gen["min_up_block_time"] = 2
                gen["min_down_block_time"] = 2
            end
        else
            gen["pmax"] = 0.0
        end
    end

    return sn_data
end

function _bench_uc_case2_data(; g_min::Float64, profile::Symbol=:weak, include_min_up_down::Bool=false)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
    _bench_apply_uc_gscr_fields!(data; mode=:uc, profile, g_min, target_total_load=1.0, include_min_up_down)
    _FP.add_dimension!(data, :hour, 3)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    return _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
end

function _bench_capexp_case2_data(; g_min::Float64, profile::Symbol=:weak)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
    _bench_apply_uc_gscr_fields!(data; mode=:capexp, profile, g_min, target_total_load=1.0)
    _FP.add_dimension!(data, :hour, 3)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    return _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
end

function _bench_case6_data(; mode::Symbol, profile::Symbol, g_min::Float64)
    return load_case6(
        number_of_hours=2,
        number_of_scenarios=1,
        number_of_years=1,
        share_data=false,
        init_data_extensions=[data -> data["block_model_schema"] = _uc_gscr_block_schema_v2()],
        sn_data_extensions=[sn_data -> _bench_apply_uc_gscr_fields!(sn_data; mode, profile, g_min, target_total_load=1.0)],
    )
end

function _bench_case67_data(; mode::Symbol, profile::Symbol, g_min::Float64)
    return load_case67(
        number_of_hours=2,
        number_of_scenarios=1,
        number_of_years=1,
        share_data=false,
        init_data_extensions=[data -> data["block_model_schema"] = _uc_gscr_block_schema_v2()],
        sn_data_extensions=[sn_data -> _bench_apply_uc_gscr_fields!(sn_data; mode, profile, g_min, target_total_load=1.0)],
    )
end

function _bench_build_and_solve_pm(data)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        pm -> _FP.build_uc_gscr_block_integration(pm; template=_bench_uc_gscr_template());
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    JuMP.optimize!(pm.model)
    return pm
end

function _bench_is_feasible(status)
    return status in (
        JuMP.MOI.OPTIMAL,
        JuMP.MOI.LOCALLY_SOLVED,
        JuMP.MOI.ALMOST_OPTIMAL,
    )
end

function _bench_collect_metrics(pm; bind_tol::Float64=1e-5)
    status = JuMP.termination_status(pm.model)
    summary = Dict{String,Any}(
        "status" => string(status),
        "objective" => nothing,
        "investment_by_type" => Dict("gfl" => 0.0, "gfm" => 0.0),
        "online_by_snapshot" => Dict{Int,Dict{String,Float64}}(),
        "startup_total" => 0.0,
        "shutdown_total" => 0.0,
        "min_gscr_margin" => Inf,
        "binding_or_near_binding_count" => 0,
        "max_transition_violation" => 0.0,
        "max_installed_active_violation" => 0.0,
    )

    if !_bench_is_feasible(status)
        return summary
    end

    summary["objective"] = JuMP.objective_value(pm.model)

    nws = sort(collect(_FP.nw_ids(pm)))
    first_nw = first(nws)
    device_keys = _FP._uc_gscr_block_device_keys(pm, first_nw)

    n_block_first = _PM.var(pm, first_nw, :n_block)
    for key in device_keys
        device = _PM.ref(pm, first_nw, key[1], key[2])
        typ = device["grid_control_mode"]
        n_val = JuMP.value(n_block_first[key])
        summary["investment_by_type"][typ] += max(0.0, n_val - device["n0"])
    end

    for nw in nws
        na = _PM.var(pm, nw, :na_block)
        su = _PM.var(pm, nw, :su_block)
        sd = _PM.var(pm, nw, :sd_block)

        online = Dict("gfl" => 0.0, "gfm" => 0.0)

        for key in device_keys
            device = _PM.ref(pm, nw, key[1], key[2])
            typ = device["grid_control_mode"]
            na_val = JuMP.value(na[key])
            su_val = JuMP.value(su[key])
            sd_val = JuMP.value(sd[key])

            online[typ] += na_val
            summary["startup_total"] += su_val
            summary["shutdown_total"] += sd_val

            n_val = JuMP.value(_PM.var(pm, nw, :n_block, key))
            summary["max_installed_active_violation"] = max(
                summary["max_installed_active_violation"],
                max(0.0, -na_val, na_val - n_val),
            )

            na_prev = if _FP.is_first_id(pm, nw, :hour)
                device["na0"]
            else
                JuMP.value(_PM.var(pm, _FP.prev_id(pm, nw, :hour), :na_block, key))
            end
            transition_residual = abs((na_val - na_prev) - (su_val - sd_val))
            summary["max_transition_violation"] = max(summary["max_transition_violation"], transition_residual)
        end

        summary["online_by_snapshot"][nw] = online

        for bus_id in sort(collect(_PM.ids(pm, nw, :bus)))
            sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus_id)
            g_min = _PM.ref(pm, nw, :g_min)
            lhs = sigma0 + sum(
                _PM.ref(pm, nw, key[1], key[2], "b_block") * JuMP.value(_PM.var(pm, nw, :na_block, key))
                for key in _PM.ref(pm, nw, :bus_gfm_devices, bus_id);
                init=0.0
            )
            rhs = g_min * sum(
                _PM.ref(pm, nw, key[1], key[2], "p_block_max") * JuMP.value(_PM.var(pm, nw, :na_block, key))
                for key in _PM.ref(pm, nw, :bus_gfl_devices, bus_id);
                init=0.0
            )
            margin = lhs - rhs
            summary["min_gscr_margin"] = min(summary["min_gscr_margin"], margin)
            if margin <= bind_tol
                summary["binding_or_near_binding_count"] += 1
            end
        end
    end

    return summary
end

function _bench_feasibility_monotone(g_values::Vector{Float64}, statuses::Vector{String})
    pairs = sort(collect(zip(g_values, statuses)); by=first)
    feasible_statuses = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL"])
    feasible_flags = [status in feasible_statuses for (_, status) in pairs]
    for idx in 2:length(feasible_flags)
        if feasible_flags[idx] && !feasible_flags[idx - 1]
            return false
        end
    end
    return true
end

function _bench_write_report(records::Vector{Dict{String,Any}})
    report_dir = normpath(@__DIR__, "..", "reports")
    mkpath(report_dir)
    report_path = normpath(report_dir, "gscr_uc_capacity_expansion_benchmark_summary.md")

    open(report_path, "w") do io
        println(io, "# gSCR UC/Capacity Expansion Benchmark Summary")
        println(io)
        println(io, "Generated by `test/uc_gscr_block_benchmarks.jl` on local test run.")
        println(io)
        println(io, "| system | mode | g_min | status | objective | invest(gfl,gfm) | startup/shutdown | min gSCR margin | near-binding count | monotone feasibility |")
        println(io, "|---|---|---:|---|---:|---|---|---:|---:|---|")

        grouped = Dict{Tuple{String,String},Vector{Dict{String,Any}}}()
        for rec in records
            key = (rec["system"], rec["mode"])
            if !haskey(grouped, key)
                grouped[key] = Dict{String,Any}[]
            end
            push!(grouped[key], rec)
        end

        monotone_map = Dict{Tuple{String,String},Bool}()
        for (key, items) in grouped
            g_vals = [item["g_min"] for item in items]
            statuses = [item["status"] for item in items]
            monotone_map[key] = _bench_feasibility_monotone(g_vals, statuses)
        end

        for rec in records
            obj = isnothing(rec["objective"]) ? "NaN" : @sprintf("%.6f", rec["objective"])
            inv = @sprintf("%.4f, %.4f", rec["investment_by_type"]["gfl"], rec["investment_by_type"]["gfm"])
            su_sd = @sprintf("%.4f / %.4f", rec["startup_total"], rec["shutdown_total"])
            min_margin = isfinite(rec["min_gscr_margin"]) ? @sprintf("%.6f", rec["min_gscr_margin"]) : "NaN"
            mono = monotone_map[(rec["system"], rec["mode"])] ? "yes" : "no"
            println(
                io,
                "| ", rec["system"],
                " | ", rec["mode"],
                " | ", @sprintf("%.4f", rec["g_min"]),
                " | ", rec["status"],
                " | ", obj,
                " | ", inv,
                " | ", su_sd,
                " | ", min_margin,
                " | ", rec["binding_or_near_binding_count"],
                " | ", mono,
                " |",
            )
        end

        println(io)
        println(io, "## Online Block Decisions by Snapshot")
        println(io)
        for rec in records
            println(io, "### ", rec["system"], " / ", rec["mode"], " / g_min=", @sprintf("%.4f", rec["g_min"]))
            if isempty(rec["online_by_snapshot"])
                println(io, "- no feasible solution")
            else
                for nw in sort(collect(keys(rec["online_by_snapshot"])))
                    online = rec["online_by_snapshot"][nw]
                    println(io, "- nw ", nw, ": gfl=", @sprintf("%.4f", online["gfl"]), ", gfm=", @sprintf("%.4f", online["gfm"]))
                end
            end
            println(io)
        end

        println(io, "## Observed Issues / Limitations")
        println(io)
        println(io, "- Benchmarks use the active LP/MILP-compatible Gershgorin gSCR constraint only.")
        println(io, "- Min-up/min-down, ramping, no-load costs, binary UC flags, and SDP/LMI gSCR are intentionally not activated here.")
    end

    return report_path
end

function _bench_add_passive_block_fields!(single_network_data::Dict{String,Any})
    for gen in values(single_network_data["gen"])
        _bench_set_block_fields!(
            gen,
            "gfl";
            n0=1,
            nmax=1,
            na0=1,
            p_block_min=gen["pmin"],
            p_block_max=max(gen["pmax"], gen["pmin"]),
            q_block_min=get(gen, "qmin", -1.0),
            q_block_max=get(gen, "qmax", 1.0),
            b_block=0.0,
            cost_inv_block=0.0,
            startup_block_cost=0.0,
            shutdown_block_cost=0.0,
        )
    end
    return single_network_data
end

function _bench_transition_fixture_all_components(; hours::Int=3)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
    data["block_model_schema"] = _uc_gscr_block_schema_v2()
    data["operation_weight"] = 1.0
    data["g_min"] = 0.0

    _bench_set_block_fields!(
        data["gen"]["1"],
        "gfl";
        n0=1,
        nmax=8,
        na0=1,
        p_block_min=0.0,
        p_block_max=20.0,
        q_block_min=-2.0,
        q_block_max=2.0,
        b_block=0.0,
        cost_inv_block=0.0,
        startup_block_cost=1.0,
        shutdown_block_cost=2.0,
    )

    _bench_set_block_fields!(
        data["storage"]["1"],
        "gfm";
        n0=1,
        nmax=8,
        na0=1,
        p_block_min=0.0,
        p_block_max=5.0,
        q_block_min=-1.0,
        q_block_max=1.0,
        b_block=0.5,
        cost_inv_block=0.0,
        startup_block_cost=2.0,
        shutdown_block_cost=3.0,
    )
    data["storage"]["1"]["e_block"] = 2.0

    _bench_set_block_fields!(
        data["ne_storage"]["1"],
        "gfl";
        n0=1,
        nmax=8,
        na0=1,
        p_block_min=0.0,
        p_block_max=5.0,
        q_block_min=-1.0,
        q_block_max=1.0,
        b_block=0.0,
        cost_inv_block=0.0,
        startup_block_cost=3.0,
        shutdown_block_cost=4.0,
    )
    data["ne_storage"]["1"]["e_block"] = 2.0

    _FP.add_dimension!(data, :hour, hours)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    mn_data = _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)

    pm = _PM.instantiate_model(
        mn_data,
        _PM.DCPPowerModel,
        pm -> nothing;
        ref_extensions=[_FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    _FP.resolve_uc_gscr_block_template!(pm, _bench_uc_gscr_template())
    for nw in _FP.nw_ids(pm)
        _FP.variable_uc_gscr_block(pm; nw, relax=false, report=false)
    end
    return pm
end

@testset "UC/gSCR block benchmark suite" begin
    @testset "A. OPF compatibility and active-path guardrails" begin
        base_opf_data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_gen.m"))
        baseline = _PM.solve_opf(base_opf_data, _PM.DCPPowerModel, milp_optimizer)
        @test baseline["termination_status"] == OPTIMAL

        opf_with_blocks = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_gen.m"))
        _bench_add_passive_block_fields!(opf_with_blocks)
        with_blocks = _PM.solve_opf(opf_with_blocks, _PM.DCPPowerModel, milp_optimizer)
        @test with_blocks["termination_status"] == OPTIMAL
        @test with_blocks["objective"] ≈ baseline["objective"] atol=1e-6

        no_block_data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
        _FP.add_dimension!(no_block_data, :hour, 2)
        no_block_mn = _FP.make_multinetwork(no_block_data, Dict{String,Any}(); share_data=false)
        no_block_pm = _PM.instantiate_model(
            no_block_mn,
            _PM.DCPPowerModel,
            pm -> nothing;
            ref_extensions=[_FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
        )
        for nw in sort(collect(_FP.nw_ids(no_block_pm)))
            _FP.variable_uc_gscr_block(no_block_pm; nw, relax=true, report=false)
            @test !haskey(_PM.var(no_block_pm, nw), :n_block)
            @test !haskey(_PM.var(no_block_pm, nw), :na_block)
            @test !haskey(_PM.var(no_block_pm, nw), :su_block)
            @test !haskey(_PM.var(no_block_pm, nw), :sd_block)
        end

        with_block_no_minud = _bench_uc_case2_data(; g_min=0.2, profile=:weak, include_min_up_down=false)
        with_block_result = _FP.uc_gscr_block_integration(with_block_no_minud, _PM.DCPPowerModel, milp_optimizer; template=_bench_uc_gscr_template())
        @test with_block_result["termination_status"] == OPTIMAL

        with_block_minud = _bench_uc_case2_data(; g_min=0.2, profile=:weak, include_min_up_down=true)
        pm_minud = _PM.instantiate_model(
            with_block_minud,
            _PM.DCPPowerModel,
            pm -> _FP.build_uc_gscr_block_integration(pm; template=_bench_uc_gscr_template());
            ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
        )
        for nw in sort(collect(_FP.nw_ids(pm_minud)))
            @test !haskey(_PM.con(pm_minud, nw), :block_minimum_up_time)
            @test !haskey(_PM.con(pm_minud, nw), :block_minimum_down_time)
        end
    end

    @testset "B. UC scheduling focused checks" begin
        pm_low = _bench_build_and_solve_pm(_bench_uc_case2_data(; g_min=0.2, profile=:weak))
        pm_mid = _bench_build_and_solve_pm(_bench_uc_case2_data(; g_min=0.9, profile=:weak))
        pm_high = _bench_build_and_solve_pm(_bench_uc_case2_data(; g_min=1.2, profile=:weak))

        @test JuMP.termination_status(pm_low.model) == JuMP.MOI.OPTIMAL
        @test JuMP.termination_status(pm_mid.model) == JuMP.MOI.OPTIMAL
        @test JuMP.termination_status(pm_high.model) in [JuMP.MOI.OPTIMAL, JuMP.MOI.INFEASIBLE]

        low_metrics = _bench_collect_metrics(pm_low)
        mid_metrics = _bench_collect_metrics(pm_mid)

        @test mid_metrics["min_gscr_margin"] <= 1e-4
        @test mid_metrics["binding_or_near_binding_count"] >= 1
        @test mid_metrics["objective"] >= low_metrics["objective"] - 1e-6
        @test mid_metrics["investment_by_type"]["gfm"] >= low_metrics["investment_by_type"]["gfm"] - 1e-6
        @test mid_metrics["max_transition_violation"] <= 1e-6
        @test mid_metrics["max_installed_active_violation"] <= 1e-6

        transition_pm = _bench_transition_fixture_all_components(; hours=3)
        component_keys = [(:gen, 1), (:storage, 1), (:ne_storage, 1)]

        for key in component_keys
            JuMP.fix(_PM.var(transition_pm, 1, :na_block, key), 1.0; force=true)
            JuMP.fix(_PM.var(transition_pm, 2, :na_block, key), 4.0; force=true)
            JuMP.fix(_PM.var(transition_pm, 3, :na_block, key), 2.0; force=true)
        end

        expr = _FP.calc_uc_gscr_block_startup_shutdown_cost(transition_pm)
        JuMP.@objective(transition_pm.model, Min, expr)
        JuMP.set_optimizer(transition_pm.model, HiGHS.Optimizer)
        JuMP.set_silent(transition_pm.model)
        JuMP.optimize!(transition_pm.model)

        @test JuMP.termination_status(transition_pm.model) == JuMP.MOI.OPTIMAL

        for key in component_keys
            na1 = JuMP.value(_PM.var(transition_pm, 1, :na_block, key))
            na2 = JuMP.value(_PM.var(transition_pm, 2, :na_block, key))
            na3 = JuMP.value(_PM.var(transition_pm, 3, :na_block, key))

            su1 = JuMP.value(_PM.var(transition_pm, 1, :su_block, key))
            su2 = JuMP.value(_PM.var(transition_pm, 2, :su_block, key))
            su3 = JuMP.value(_PM.var(transition_pm, 3, :su_block, key))

            sd1 = JuMP.value(_PM.var(transition_pm, 1, :sd_block, key))
            sd2 = JuMP.value(_PM.var(transition_pm, 2, :sd_block, key))
            sd3 = JuMP.value(_PM.var(transition_pm, 3, :sd_block, key))

            @test abs((na1 - _PM.ref(transition_pm, 1, key[1], key[2], "na0")) - (su1 - sd1)) <= 1e-6
            @test abs((na2 - na1) - (su2 - sd2)) <= 1e-6
            @test abs((na3 - na2) - (su3 - sd3)) <= 1e-6

            @test su2 ≈ 3.0 atol=1e-6
            @test sd2 ≈ 0.0 atol=1e-6
        end

        gen_startup_cost = _PM.ref(transition_pm, 2, :gen, 1, "startup_cost_per_mw")
        @test JuMP.objective_value(transition_pm.model) >= 3.0 * gen_startup_cost
    end

    @testset "C/D. Capacity-expansion checks and multi-system benchmark report" begin
        cap_low_pm = _bench_build_and_solve_pm(_bench_capexp_case2_data(; g_min=0.2, profile=:weak))
        cap_mid_pm = _bench_build_and_solve_pm(_bench_capexp_case2_data(; g_min=2.0, profile=:weak))
        cap_high_pm = _bench_build_and_solve_pm(_bench_capexp_case2_data(; g_min=4.0, profile=:weak))

        @test JuMP.termination_status(cap_low_pm.model) == JuMP.MOI.OPTIMAL
        @test JuMP.termination_status(cap_mid_pm.model) == JuMP.MOI.OPTIMAL
        @test JuMP.termination_status(cap_high_pm.model) in [JuMP.MOI.OPTIMAL, JuMP.MOI.INFEASIBLE]

        cap_low = _bench_collect_metrics(cap_low_pm)
        cap_mid = _bench_collect_metrics(cap_mid_pm)

        @test cap_mid["investment_by_type"]["gfm"] >= cap_low["investment_by_type"]["gfm"] - 1e-6

        cap_first_nw = first(sort(collect(_FP.nw_ids(cap_mid_pm))))
        cap_expr = _FP.calc_uc_gscr_block_investment_cost(cap_mid_pm)
        cap_key = (:gen, 2)
        coeff = JuMP.coefficient(cap_expr, _PM.var(cap_mid_pm, cap_first_nw, :n_block, cap_key))
        expected_coeff = _PM.ref(cap_mid_pm, cap_first_nw, :gen, 2, "cost_inv_per_mw") * _PM.ref(cap_mid_pm, cap_first_nw, :gen, 2, "p_block_max")
        @test coeff == expected_coeff

        for nw in sort(collect(_FP.nw_ids(cap_mid_pm)))
            n = _PM.var(cap_mid_pm, nw, :n_block, cap_key)
            na = _PM.var(cap_mid_pm, nw, :na_block, cap_key)
            @test JuMP.value(na) >= -1e-6
            @test JuMP.value(na) <= JuMP.value(n) + 1e-6
        end

        cap_n_ref = _PM.var(cap_mid_pm, cap_first_nw, :n_block, cap_key)
        for nw in sort(collect(_FP.nw_ids(cap_mid_pm)))[2:end]
            @test _PM.var(cap_mid_pm, nw, :n_block, cap_key) === cap_n_ref
            @test _PM.var(cap_mid_pm, nw, :na_block, cap_key) !== _PM.var(cap_mid_pm, cap_first_nw, :na_block, cap_key)
        end

        gscr_con = _PM.con(cap_mid_pm, cap_first_nw)[:gscr_gershgorin_sufficient][_PM.ref(cap_mid_pm, cap_first_nw, :gen, 1, "gen_bus")]
        @test JuMP.normalized_coefficient(gscr_con, _PM.var(cap_mid_pm, cap_first_nw, :na_block, (:gen, 2))) > 0.0
        @test JuMP.normalized_coefficient(gscr_con, _PM.var(cap_mid_pm, cap_first_nw, :na_block, (:gen, 1))) < 0.0

        systems = [
            Dict("name" => "synthetic-small-weak", "builder" => (mode, g) -> (mode == "UC" ? _bench_uc_case2_data(; g_min=g, profile=:weak) : _bench_capexp_case2_data(; g_min=g, profile=:weak))),
            Dict("name" => "synthetic-small-strong", "builder" => (mode, g) -> (mode == "UC" ? _bench_uc_case2_data(; g_min=g, profile=:strong) : _bench_capexp_case2_data(; g_min=g, profile=:strong))),
            Dict("name" => "case6-style", "builder" => (mode, g) -> _bench_case6_data(; mode=(mode == "UC" ? :uc : :capexp), profile=:strong, g_min=g)),
            Dict("name" => "case67-large", "builder" => (mode, g) -> _bench_case67_data(; mode=(mode == "UC" ? :uc : :capexp), profile=:strong, g_min=g)),
        ]

        g_sweep = [0.2, 1.0, 4.5]
        records = Dict{String,Any}[]

        for system in systems
            for mode in ("UC", "CAPEXP")
                for g in g_sweep
                    data = system["builder"](mode, g)
                    pm = _bench_build_and_solve_pm(data)
                    metrics = _bench_collect_metrics(pm)
                    push!(records, merge(metrics, Dict(
                        "system" => system["name"],
                        "mode" => mode,
                        "g_min" => g,
                    )))
                end
            end
        end

        grouped = Dict{Tuple{String,String},Vector{Dict{String,Any}}}()
        for rec in records
            key = (rec["system"], rec["mode"])
            if !haskey(grouped, key)
                grouped[key] = Dict{String,Any}[]
            end
            push!(grouped[key], rec)
        end

        for (_, items) in grouped
            g_vals = [item["g_min"] for item in items]
            statuses = [item["status"] for item in items]
            @test _bench_feasibility_monotone(g_vals, statuses)
        end

        report_path = _bench_write_report(records)
        @test isfile(report_path)
    end
end
