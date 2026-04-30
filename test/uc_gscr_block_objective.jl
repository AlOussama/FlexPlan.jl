"""
    _set_uc_gscr_objective_fields!(device, type; n0, nmax, p_block_max, cost_inv_per_mw)

Adds deterministic UC/gSCR block objective fields to one test device.

The helper sets the required block schema and objective fields used to validate
`cost_inv_per_mw * p_block_max * (n_block - n0)`. Argument `type` must be
`"gfl"` or `"gfm"`. Values are interpreted on the model's internal base, with
`cost_inv_per_mw` treated as objective-level coefficient. This helper is
formulation-independent and mutates `device`.
"""
function _set_uc_gscr_objective_fields!(device, type; n0, nmax, p_block_max, cost_inv_per_mw)
    merge!(device, Dict{String,Any}(
        "carrier" => "test-carrier",
        "grid_control_mode" => type,
        "n0" => n0,
        "nmax" => nmax,
        "na0" => n0,
        "p_block_min" => 0.0,
        "p_block_max" => p_block_max,
        "q_block_min" => -1.0,
        "q_block_max" => 1.0,
        "b_block" => type == "gfm" ? 0.6 : 0.0,
        "cost_inv_per_mw" => cost_inv_per_mw,
        "p_min_pu" => 0.0,
        "p_max_pu" => 1.0,
        "startup_cost_per_mw" => 1.0,
        "shutdown_cost_per_mw" => 1.0,
    ))
    return device
end

"""
    _uc_gscr_objective_test_data(; hours=2, with_block=true, include_cost_inv=true, include_p_block_max=true)

Builds a deterministic multinetwork fixture for UC/gSCR block objective tests.

The fixture uses one generator, one storage, and one candidate storage device,
all sharing numeric id `1` to validate collision-free compound keys across
tables. When `with_block=false`, no block fields are added. Flags
`include_cost_inv` and `include_p_block_max` remove specific fields to test
validation paths. This helper is test-only and mutates only local fixture data.
"""
function _uc_gscr_objective_test_data(; hours::Int=2, with_block::Bool=true, include_cost_inv::Bool=true, include_p_block_max::Bool=true)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))

    if with_block
        _set_uc_gscr_objective_fields!(data["gen"]["1"], "gfl"; n0=1, nmax=4, p_block_max=3.0, cost_inv_per_mw=2.0)
        _set_uc_gscr_objective_fields!(data["storage"]["1"], "gfm"; n0=2, nmax=5, p_block_max=4.0, cost_inv_per_mw=5.0)
        data["storage"]["1"]["e_block"] = 1.0
        _set_uc_gscr_objective_fields!(data["ne_storage"]["1"], "gfl"; n0=0, nmax=3, p_block_max=1.5, cost_inv_per_mw=7.0)
        data["ne_storage"]["1"]["e_block"] = 1.0

        if !include_cost_inv
            delete!(data["storage"]["1"], "cost_inv_per_mw")
        end
        if !include_p_block_max
            delete!(data["gen"]["1"], "p_block_max")
        end
    end
    if with_block
        data["block_model_schema"] = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
        data["operation_weight"] = 1.0
    end

    _FP.add_dimension!(data, :hour, hours)
    return _FP.make_multinetwork(data, Dict{String,Any}())
end

"""
    _uc_gscr_objective_test_pm(; kwargs...)

Instantiates a DCP model fixture with UC/gSCR block variables for objective tests.

This helper applies `ref_add_ne_storage!` and `ref_add_uc_gscr_block!`, then
creates `n_block`/`na_block` variables on all snapshots when block fields are
present. It is test-only and mutates only the model it creates.
"""
function _uc_gscr_objective_test_pm(; kwargs...)
    data = _uc_gscr_objective_test_data(; kwargs...)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        pm -> nothing;
        ref_extensions=[_FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    for nw in _FP.nw_ids(pm)
        _FP.variable_uc_gscr_block(pm; nw, relax=true, report=false)
    end
    return pm
end

@testset "UC/gSCR block objective term" begin
    @testset "Objective uses installed n_block variables, not active na_block variables" begin
        pm = _uc_gscr_objective_test_pm()
        expr = _FP.calc_uc_gscr_block_investment_cost(pm)
        expected_keys = [(:gen, 1), (:storage, 1), (:ne_storage, 1)]

        for key in expected_keys
            n_block = _PM.var(pm, 1, :n_block, key)
            na_block = _PM.var(pm, 1, :na_block, key)
            @test JuMP.coefficient(expr, n_block) != 0.0
            @test JuMP.coefficient(expr, na_block) == 0.0
        end
    end

    @testset "Objective follows cost_inv_per_mw * p_block_max * (n_block - n0)" begin
        pm = _uc_gscr_objective_test_pm()
        expr = _FP.calc_uc_gscr_block_investment_cost(pm)
        expected = Dict(
            (:gen, 1) => (2.0 * 3.0, 1),
            (:storage, 1) => (5.0 * 4.0, 2),
            (:ne_storage, 1) => (7.0 * 1.5, 0),
        )

        expected_constant = 0.0
        for (key, (coeff, n0)) in expected
            @test JuMP.coefficient(expr, _PM.var(pm, 1, :n_block, key)) == coeff
            expected_constant -= coeff * n0
        end
        @test JuMP.constant(expr) == expected_constant
    end

    @testset "Objective term is added once for the whole optimization problem" begin
        pm = _uc_gscr_objective_test_pm(; hours=3)
        expr = _FP.calc_uc_gscr_block_investment_cost(pm)

        @test JuMP.coefficient(expr, _PM.var(pm, 1, :n_block, (:gen, 1))) == 6.0
        @test JuMP.coefficient(expr, _PM.var(pm, 2, :n_block, (:gen, 1))) == 6.0
        @test JuMP.coefficient(expr, _PM.var(pm, 3, :n_block, (:gen, 1))) == 6.0
    end

    @testset "Compound keys keep objective coefficients collision-free across device tables" begin
        pm = _uc_gscr_objective_test_pm()
        expr = _FP.calc_uc_gscr_block_investment_cost(pm)

        @test JuMP.coefficient(expr, _PM.var(pm, 1, :n_block, (:gen, 1))) == 6.0
        @test JuMP.coefficient(expr, _PM.var(pm, 1, :n_block, (:storage, 1))) == 20.0
        @test JuMP.coefficient(expr, _PM.var(pm, 1, :n_block, (:ne_storage, 1))) == 10.5
        @test _PM.var(pm, 1, :n_block, (:gen, 1)) !== _PM.var(pm, 1, :n_block, (:storage, 1))
        @test _PM.var(pm, 1, :n_block, (:gen, 1)) !== _PM.var(pm, 1, :n_block, (:ne_storage, 1))
    end

    @testset "Missing objective fields fail via validation/reporting" begin
        @test_throws ErrorException _uc_gscr_objective_test_pm(; include_cost_inv=false)
        @test_throws ErrorException _uc_gscr_objective_test_pm(; include_p_block_max=false)
    end

    @testset "Cases without UC/gSCR block fields remain backward compatible" begin
        pm = _uc_gscr_objective_test_pm(; with_block=false)
        expr = _FP.calc_uc_gscr_block_investment_cost(pm)

        @test JuMP.constant(expr) == 0.0
        @test !haskey(_PM.var(pm, 1), :n_block)
        @test !haskey(_PM.var(pm, 1), :na_block)
    end

    @testset "Objective coefficient equals cost_inv_per_mw * p_block_max" begin
        pm = _uc_gscr_objective_test_pm()
        expr = _FP.calc_uc_gscr_block_investment_cost(pm)

        @test JuMP.coefficient(expr, _PM.var(pm, 1, :n_block, (:gen, 1))) == _PM.ref(pm, 1, :gen, 1, "cost_inv_per_mw") * _PM.ref(pm, 1, :gen, 1, "p_block_max")
        @test JuMP.coefficient(expr, _PM.var(pm, 1, :n_block, (:storage, 1))) == _PM.ref(pm, 1, :storage, 1, "cost_inv_per_mw") * _PM.ref(pm, 1, :storage, 1, "p_block_max")
        @test JuMP.coefficient(expr, _PM.var(pm, 1, :n_block, (:ne_storage, 1))) == _PM.ref(pm, 1, :ne_storage, 1, "cost_inv_per_mw") * _PM.ref(pm, 1, :ne_storage, 1, "p_block_max")
    end
end
