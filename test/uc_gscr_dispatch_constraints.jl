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
    _add_uc_gscr_storage_block_test_fields!(device, type; eblock)

Adds deterministic UC/gSCR storage block fields for storage-bound tests.

This helper augments `_add_uc_gscr_dispatch_test_fields!` by setting `e_block`
for the storage energy-capacity equation and is test-only.
"""
function _add_uc_gscr_storage_block_test_fields!(device, type; eblock)
    _add_uc_gscr_dispatch_test_fields!(device, type; pmin=0.0, pmax=device["charge_rating"], qmin=-1.0, qmax=1.0)
    device["e_block"] = eblock
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
    _add_uc_gscr_storage_block_test_fields!(data["storage"]["1"], "gfm"; eblock=4.0)
    _add_uc_gscr_storage_block_test_fields!(data["ne_storage"]["1"], "gfl"; eblock=6.0)

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

        _PM.var(pm, nw)[:se] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :storage)], base_name="$(nw)_se_test", lower_bound=0.0)
        _PM.var(pm, nw)[:sc] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :storage)], base_name="$(nw)_sc_test", lower_bound=0.0)
        _PM.var(pm, nw)[:sd] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :storage)], base_name="$(nw)_sd_test", lower_bound=0.0)

        _PM.var(pm, nw)[:se_ne] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :ne_storage)], base_name="$(nw)_se_ne_test", lower_bound=0.0)
        _PM.var(pm, nw)[:sc_ne] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :ne_storage)], base_name="$(nw)_sc_ne_test", lower_bound=0.0)
        _PM.var(pm, nw)[:sd_ne] = JuMP.@variable(pm.model, [i in _PM.ids(pm, nw, :ne_storage)], base_name="$(nw)_sd_ne_test", lower_bound=0.0)
    end

    return pm
end

"""
    _uc_gscr_dispatch_no_block_pm(model_type)

Builds a minimal model fixture without UC/gSCR block fields.

This fixture validates that storage block-constraint templates remain no-op
and backward compatible when block schema fields are absent.
"""
function _uc_gscr_dispatch_no_block_pm(model_type)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
    _FP.add_dimension!(data, :hour, 1)
    mn_data = _FP.make_multinetwork(data, Dict{String,Any}())
    return _PM.instantiate_model(
        mn_data,
        model_type,
        pm -> nothing;
        ref_extensions=[_FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
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

    @testset "Storage energy capacity scales with installed n_block" begin
        pm = _uc_gscr_dispatch_test_pm(_PM.DCPPowerModel)
        _FP.constraint_uc_gscr_block_storage_energy_capacity(pm; nw=1)

        constraints = _PM.con(pm, 1)[:uc_gscr_block_storage_energy_capacity]
        @test Set(keys(constraints)) == Set([(:storage, 1), (:ne_storage, 1)])

        for device_key in keys(constraints)
            device = _PM.ref(pm, 1, device_key[1], device_key[2])
            e = _FP._uc_gscr_block_storage_variable(pm, 1, device_key, :energy)
            n_block = _PM.var(pm, 1, :n_block, device_key)
            con = constraints[device_key]

            @test JuMP.normalized_coefficient(con, e) == 1.0
            @test JuMP.normalized_coefficient(con, n_block) == -device["e_block"]
            @test JuMP.normalized_rhs(con) == 0.0
        end
    end

    @testset "Storage charge and discharge bounds scale with active na_block" begin
        pm = _uc_gscr_dispatch_test_pm(_PM.DCPPowerModel)
        _FP.constraint_uc_gscr_block_storage_charge_discharge_bounds(pm; nw=1)

        constraints = _PM.con(pm, 1)[:uc_gscr_block_storage_charge_discharge_bounds]
        @test Set(keys(constraints)) == Set([(:storage, 1), (:ne_storage, 1)])

        for device_key in keys(constraints)
            device = _PM.ref(pm, 1, device_key[1], device_key[2])
            na = _PM.var(pm, 1, :na_block, device_key)
            sc = _FP._uc_gscr_block_storage_variable(pm, 1, device_key, :charge)
            sd = _FP._uc_gscr_block_storage_variable(pm, 1, device_key, :discharge)
            charge_con, discharge_con = constraints[device_key]

            @test JuMP.normalized_coefficient(charge_con, sc) == 1.0
            @test JuMP.normalized_coefficient(charge_con, na) == -device["charge_rating"]
            @test JuMP.normalized_rhs(charge_con) == 0.0

            @test JuMP.normalized_coefficient(discharge_con, sd) == 1.0
            @test JuMP.normalized_coefficient(discharge_con, na) == -device["discharge_rating"]
            @test JuMP.normalized_rhs(discharge_con) == 0.0
        end
    end

    @testset "Storage block constraints keep compound keys collision-free" begin
        pm = _uc_gscr_dispatch_test_pm(_PM.DCPPowerModel)
        _FP.constraint_uc_gscr_block_storage_bounds(pm; nw=1)

        energy_keys = Set(keys(_PM.con(pm, 1)[:uc_gscr_block_storage_energy_capacity]))
        power_keys = Set(keys(_PM.con(pm, 1)[:uc_gscr_block_storage_charge_discharge_bounds]))
        @test energy_keys == Set([(:storage, 1), (:ne_storage, 1)])
        @test power_keys == Set([(:storage, 1), (:ne_storage, 1)])
    end

    @testset "Storage block constraints are backward compatible without block fields" begin
        pm = _uc_gscr_dispatch_no_block_pm(_PM.DCPPowerModel)
        _FP.constraint_uc_gscr_block_storage_bounds(pm; nw=1)

        @test !haskey(_PM.con(pm, 1), :uc_gscr_block_storage_energy_capacity)
        @test !haskey(_PM.con(pm, 1), :uc_gscr_block_storage_charge_discharge_bounds)
    end
end
