"""
    _add_uc_gscr_dispatch_test_fields!(device, type; pmin, pmax, qmin, qmax)

Adds UC/gSCR block fields used by dispatch-bound tests.

The helper fills the required block schema with deterministic bounds and is
test-only.
"""
function _add_uc_gscr_dispatch_test_fields!(device, type; pmin, pmax, qmin, qmax)
    merge!(device, Dict{String,Any}(
        "type" => type,
        "n0" => 1,
        "nmax" => 4,
        "p_block_min" => pmin,
        "p_block_max" => pmax,
        "q_block_min" => qmin,
        "q_block_max" => qmax,
        "b_block" => type == "gfm" ? 0.5 : 0.0,
    ))
    return device
end

"""
    _uc_gscr_dispatch_test_pm(model_type)

Builds a minimal model fixture with UC/gSCR block variables and dispatch vars.

The fixture includes one block-annotated generator, storage, and candidate
storage device and is used only for dispatch-bound unit tests.
"""
function _uc_gscr_dispatch_test_pm(model_type)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))

    _add_uc_gscr_dispatch_test_fields!(data["gen"]["1"], "gfl"; pmin=1.0, pmax=5.0, qmin=-2.0, qmax=2.0)
    _add_uc_gscr_dispatch_test_fields!(data["storage"]["1"], "gfm"; pmin=0.5, pmax=3.0, qmin=-1.5, qmax=1.5)
    _add_uc_gscr_dispatch_test_fields!(data["ne_storage"]["1"], "gfl"; pmin=0.25, pmax=2.5, qmin=-1.0, qmax=1.0)

    _FP.add_dimension!(data, :hour, 1)
    mn_data = _FP.make_multinetwork(data, Dict{String,Any}())

    pm = _PM.instantiate_model(
        mn_data,
        model_type,
        pm -> nothing;
        ref_extensions=[_FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )

    for nw in _FP.nw_ids(pm)
        _FP.variable_uc_gscr_block(pm; nw, relax=true, report=false)

        _PM.var(pm, nw)[:pg] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_pg_test")
        _PM.var(pm, nw)[:ps] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :storage)], base_name="$(nw)_ps_test")
        _PM.var(pm, nw)[:ps_ne] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :ne_storage)], base_name="$(nw)_ps_ne_test")

        _PM.var(pm, nw)[:qg] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_qg_test")
        _PM.var(pm, nw)[:qs] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :storage)], base_name="$(nw)_qs_test")
        _PM.var(pm, nw)[:qs_ne] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :ne_storage)], base_name="$(nw)_qs_ne_test")
    end

    return pm
end

@testset "UC/gSCR dispatch bounds constraints" begin
    @testset "Active-power dispatch bounds follow block equation" begin
        pm = _uc_gscr_dispatch_test_pm(_PM.DCPPowerModel)
        _FP.constraint_uc_gscr_block_active_dispatch_bounds(pm; nw=1)

        constraints = _PM.con(pm, 1)[:uc_gscr_block_active_dispatch_bounds]
        for device_key in _FP._uc_gscr_block_device_keys(pm, 1)
            device = _PM.ref(pm, 1, device_key[1], device_key[2])
            p = _FP._uc_gscr_block_dispatch_variable(pm, 1, device_key, :p)
            na = _PM.var(pm, 1, :na_block, device_key)
            lower, upper = constraints[device_key]

            @test JuMP.normalized_coefficient(lower, p) == 1.0
            @test JuMP.normalized_coefficient(lower, na) == -device["p_block_min"]
            @test JuMP.normalized_rhs(lower) == 0.0

            @test JuMP.normalized_coefficient(upper, p) == 1.0
            @test JuMP.normalized_coefficient(upper, na) == -device["p_block_max"]
            @test JuMP.normalized_rhs(upper) == 0.0
        end
    end

    @testset "Reactive-power dispatch bounds follow block equation on AC formulations" begin
        pm = _uc_gscr_dispatch_test_pm(_PM.ACPPowerModel)
        _FP.constraint_uc_gscr_block_reactive_dispatch_bounds(pm; nw=1)

        constraints = _PM.con(pm, 1)[:uc_gscr_block_reactive_dispatch_bounds]
        for device_key in _FP._uc_gscr_block_device_keys(pm, 1)
            device = _PM.ref(pm, 1, device_key[1], device_key[2])
            q = _FP._uc_gscr_block_dispatch_variable(pm, 1, device_key, :q)
            na = _PM.var(pm, 1, :na_block, device_key)
            lower, upper = constraints[device_key]

            @test JuMP.normalized_coefficient(lower, q) == 1.0
            @test JuMP.normalized_coefficient(lower, na) == -device["q_block_min"]
            @test JuMP.normalized_rhs(lower) == 0.0

            @test JuMP.normalized_coefficient(upper, q) == 1.0
            @test JuMP.normalized_coefficient(upper, na) == -device["q_block_max"]
            @test JuMP.normalized_rhs(upper) == 0.0
        end
    end

    @testset "Reactive bounds are no-op for active-power-only formulations" begin
        pm = _uc_gscr_dispatch_test_pm(_PM.DCPPowerModel)
        _FP.constraint_uc_gscr_block_reactive_dispatch_bounds(pm; nw=1)

        @test !haskey(_PM.con(pm, 1), :uc_gscr_block_reactive_dispatch_bounds)
    end
end
