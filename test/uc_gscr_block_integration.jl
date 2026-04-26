"""
    _uc_gscr_integration_add_block_fields!(device, type; n0, nmax, p_block_min, p_block_max, q_block_min, q_block_max, b_block, cost_inv_block, e_block=nothing)

Adds UC/gSCR block schema fields to one synthetic integration-test device.

This helper is test-only and mutates `device` in place. Optional `e_block`
is added for storage-capable devices.
"""
function _uc_gscr_integration_add_block_fields!(device, type; n0, nmax, p_block_min, p_block_max, q_block_min, q_block_max, b_block, cost_inv_block, e_block=nothing)
    device["type"] = type
    device["n0"] = n0
    device["nmax"] = nmax
    device["p_block_min"] = p_block_min
    device["p_block_max"] = p_block_max
    device["q_block_min"] = q_block_min
    device["q_block_max"] = q_block_max
    device["b_block"] = b_block
    device["H"] = 3.0
    device["s_block"] = max(abs(p_block_max), 1.0)
    device["cost_inv_block"] = cost_inv_block
    if !isnothing(e_block)
        device["e_block"] = e_block
    end
    return device
end

"""
    _uc_gscr_synthetic_integration_data(; g_min)

Builds a 2-bus, 2-hour AC-only multinetwork fixture for UC/gSCR integration.

The fixture includes one GFL generator, one GFM generator, and one storage
unit with block fields. `g_min` is written as case-level global threshold.
This helper is test-only and mutates only local fixture data.
"""
function _uc_gscr_synthetic_integration_data(; g_min)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))

    data["ne_storage"] = Dict{String,Any}()
    data["storage"]["1"]["energy"] = 0.0
    data["storage"]["1"]["self_discharge_rate"] = 0.0

    gfl = data["gen"]["1"]
    gfl["dispatchable"] = true
    gfl["pmin"] = 0.0
    gfl["pmax"] = 10.0
    _uc_gscr_integration_add_block_fields!(
        gfl,
        "gfl";
        n0=0,
        nmax=3,
        p_block_min=0.0,
        p_block_max=5.0,
        q_block_min=-10.0,
        q_block_max=10.0,
        b_block=0.0,
        cost_inv_block=1.0,
    )

    gfm = deepcopy(gfl)
    gfm["index"] = 2
    gfm["gen_bus"] = gfl["gen_bus"]
    gfm["pmin"] = 0.0
    gfm["pmax"] = 0.0
    gfm["cost"] = [0.0, 0.0]
    _uc_gscr_integration_add_block_fields!(
        gfm,
        "gfm";
        n0=0,
        nmax=4,
        p_block_min=0.0,
        p_block_max=1.0,
        q_block_min=-10.0,
        q_block_max=10.0,
        b_block=1.0,
        cost_inv_block=7.0,
    )
    data["gen"]["2"] = gfm

    _uc_gscr_integration_add_block_fields!(
        data["storage"]["1"],
        "gfm";
        n0=1,
        nmax=3,
        p_block_min=0.0,
        p_block_max=1.0,
        q_block_min=-1.0,
        q_block_max=1.0,
        b_block=0.0,
        cost_inv_block=0.5,
        e_block=1.0,
    )

    data["g_min"] = g_min

    _FP.add_dimension!(data, :hour, 2)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))

    return _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
end

"""
    _uc_gscr_solve_integration_pm(data)

Builds and solves the UC/gSCR integration model for a prepared multinetwork.

The returned `pm` contains solved variable values for explicit post-solve
constraint checks. This helper is test-only and mutates only the local model
instance it creates.
"""
function _uc_gscr_solve_integration_pm(data)
    pm = _uc_gscr_build_integration_pm(data)
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    JuMP.optimize!(pm.model)
    return pm
end

"""
    _uc_gscr_gershgorin_lhs_rhs(pm, bus_id; nw=1)

Computes the post-solve Gershgorin sufficient-condition sides at one bus.

Returns `(lhs, rhs)` for
`lhs = sigma0_G + sum(b_block * na_block for GFM at bus)` and
`rhs = g_min * sum(p_block_max * na_block for GFL at bus)` on snapshot `nw`.
This helper is test-only and reads solved values without mutating model state.
"""
function _uc_gscr_gershgorin_lhs_rhs(pm, bus_id; nw::Int=1)
    sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus_id)
    g_min = _PM.ref(pm, nw, :g_min)
    na = _PM.var(pm, nw, :na_block)
    gfm_devices = _PM.ref(pm, nw, :bus_gfm_devices, bus_id)
    gfl_devices = _PM.ref(pm, nw, :bus_gfl_devices, bus_id)

    lhs = sigma0 + sum(_PM.ref(pm, nw, device_key[1], device_key[2], "b_block") * JuMP.value(na[device_key]) for device_key in gfm_devices)
    rhs = g_min * sum(_PM.ref(pm, nw, device_key[1], device_key[2], "p_block_max") * JuMP.value(na[device_key]) for device_key in gfl_devices)
    return lhs, rhs
end

"""
    _uc_gscr_case6_extension(g_min)

Returns a single-network data extension that injects UC/gSCR block fields.

The extension writes `g_min`, keeps one GFL generator online for energy
balance, adds one GFM support generator at the same bus, sets all other
generators to zero active capability, and leaves storage candidates available.
This helper is test-only and mutates one single-network input dictionary.
"""
function _uc_gscr_case6_extension(g_min)
    return function (sn_data)
        sn_data["g_min"] = g_min

        gen_ids = sort(collect(keys(sn_data["gen"])); by=id -> parse(Int, id))
        if length(gen_ids) < 2
            error("Case6 UC/gSCR integration test requires at least two generators.")
        end

        gfl_id = gen_ids[1]
        gfm_id = gen_ids[2]
        gfl_bus = sn_data["gen"][gfl_id]["gen_bus"]

        for gen_id in gen_ids
            gen = sn_data["gen"][gen_id]
            gen["dispatchable"] = true
            gen["pmin"] = 0.0
            gen["qmin"] = get(gen, "qmin", -1.0)
            gen["qmax"] = get(gen, "qmax", 1.0)

            if gen_id == gfl_id
                gen["pmax"] = max(get(gen, "pmax", 0.0), 200.0)
                _uc_gscr_integration_add_block_fields!(
                    gen,
                    "gfl";
                    n0=0,
                    nmax=8,
                    p_block_min=0.0,
                    p_block_max=gen["pmax"] / 2,
                    q_block_min=gen["qmin"],
                    q_block_max=gen["qmax"],
                    b_block=0.0,
                    cost_inv_block=1.0,
                )
            elseif gen_id == gfm_id
                gen["gen_bus"] = gfl_bus
                gen["pmax"] = 0.0
                _uc_gscr_integration_add_block_fields!(
                    gen,
                    "gfm";
                    n0=0,
                    nmax=2,
                    p_block_min=0.0,
                    p_block_max=0.0,
                    q_block_min=gen["qmin"],
                    q_block_max=gen["qmax"],
                    b_block=1.0,
                    cost_inv_block=50.0,
                )
            else
                gen["pmax"] = 0.0
            end
        end

        return sn_data
    end
end

"""
    _uc_gscr_build_integration_pm(data)

Instantiates the minimal UC/gSCR integration model for structural assertions.

This helper is test-only, uses the same build path as the public solve
wrapper, and mutates only the instantiated model.
"""
function _uc_gscr_build_integration_pm(data)
    return _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _FP.build_uc_gscr_block_integration;
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_uc_gscr_block!],
    )
end

@testset "UC/gSCR integrated solve path" begin
    @testset "Synthetic 2-bus AC-only integration" begin
        data_loose = _uc_gscr_synthetic_integration_data(; g_min=0.1)
        pm = _uc_gscr_build_integration_pm(data_loose)

        @test _PM.var(pm, 1, :n_block, (:gen, 1)) === _PM.var(pm, 2, :n_block, (:gen, 1))
        @test _PM.var(pm, 1, :na_block, (:gen, 1)) !== _PM.var(pm, 2, :na_block, (:gen, 1))

        dispatch_bounds = _PM.con(pm, 1)[:uc_gscr_block_active_dispatch_bounds][(:gen, 1)]
        na_gfl = _PM.var(pm, 1, :na_block, (:gen, 1))
        pg_gfl = _PM.var(pm, 1, :pg, 1)
        @test JuMP.normalized_coefficient(dispatch_bounds[2], pg_gfl) == 1.0
        @test JuMP.normalized_coefficient(dispatch_bounds[2], na_gfl) == -5.0

        storage_cap_con = _PM.con(pm, 1)[:uc_gscr_block_storage_energy_capacity][(:storage, 1)]
        se_storage = _PM.var(pm, 1, :se, 1)
        n_storage = _PM.var(pm, 1, :n_block, (:storage, 1))
        @test JuMP.normalized_coefficient(storage_cap_con, se_storage) == 1.0
        @test JuMP.normalized_coefficient(storage_cap_con, n_storage) == -1.0

        gscr_con = _PM.con(pm, 1)[:gscr_gershgorin_sufficient][1]
        na_gfm = _PM.var(pm, 1, :na_block, (:gen, 2))
        @test JuMP.normalized_coefficient(gscr_con, na_gfm) == 1.0
        @test JuMP.normalized_coefficient(gscr_con, na_gfl) == -0.5

        objective = JuMP.objective_function(pm.model)
        n_gfl = _PM.var(pm, 1, :n_block, (:gen, 1))
        @test JuMP.coefficient(objective, n_gfl) == 5.0
        @test JuMP.coefficient(objective, _PM.var(pm, 2, :n_block, (:gen, 1))) == 5.0

        result_loose = _FP.uc_gscr_block_integration(data_loose, _PM.DCPPowerModel, milp_optimizer)
        @test result_loose["termination_status"] == OPTIMAL

        data_tight = _uc_gscr_synthetic_integration_data(; g_min=1.0)
        result_tight = _FP.uc_gscr_block_integration(data_tight, _PM.DCPPowerModel, milp_optimizer)
        @test result_tight["termination_status"] == INFEASIBLE
    end

    @testset "Synthetic g_min binding-feasible validation with explicit LHS/RHS checks" begin
        tol = 1e-6

        data_nonbinding = _uc_gscr_synthetic_integration_data(; g_min=0.20)
        pm_nonbinding = _uc_gscr_solve_integration_pm(data_nonbinding)
        @test JuMP.termination_status(pm_nonbinding.model) == JuMP.MOI.OPTIMAL
        sigma0_nonbinding = _PM.ref(pm_nonbinding, 1, :gscr_sigma0_gershgorin_margin, 1)
        @test sigma0_nonbinding ≈ 0.0 atol=tol
        lhs_nonbinding, rhs_nonbinding = _uc_gscr_gershgorin_lhs_rhs(pm_nonbinding, 1; nw=1)
        @test lhs_nonbinding >= rhs_nonbinding - tol

        data_binding = _uc_gscr_synthetic_integration_data(; g_min=0.40)
        pm_binding = _uc_gscr_solve_integration_pm(data_binding)
        @test JuMP.termination_status(pm_binding.model) == JuMP.MOI.OPTIMAL
        sigma0_binding = _PM.ref(pm_binding, 1, :gscr_sigma0_gershgorin_margin, 1)
        @test sigma0_binding ≈ 0.0 atol=tol
        lhs_binding, rhs_binding = _uc_gscr_gershgorin_lhs_rhs(pm_binding, 1; nw=1)
        @test lhs_binding >= rhs_binding - tol

        na_nonbinding_gfm = JuMP.value(_PM.var(pm_nonbinding, 1, :na_block, (:gen, 2)))
        na_binding_gfm = JuMP.value(_PM.var(pm_binding, 1, :na_block, (:gen, 2)))
        na_nonbinding_gfl = JuMP.value(_PM.var(pm_nonbinding, 1, :na_block, (:gen, 1)))
        na_binding_gfl = JuMP.value(_PM.var(pm_binding, 1, :na_block, (:gen, 1)))
        obj_nonbinding = JuMP.objective_value(pm_nonbinding.model)
        obj_binding = JuMP.objective_value(pm_binding.model)

        @test na_binding_gfm >= na_nonbinding_gfm + tol
        @test obj_binding >= obj_nonbinding + tol
        @test na_binding_gfl <= na_nonbinding_gfl + tol

        data_infeasible = _uc_gscr_synthetic_integration_data(; g_min=0.45)
        result_infeasible = _FP.uc_gscr_block_integration(data_infeasible, _PM.DCPPowerModel, milp_optimizer)
        @test result_infeasible["termination_status"] == INFEASIBLE
    end

    @testset "Case6 4h/1s/1y integration" begin
        loose_data = load_case6(
            number_of_hours=4,
            number_of_scenarios=1,
            number_of_years=1,
            share_data=false,
            sn_data_extensions=[_uc_gscr_case6_extension(0.0)],
        )
        loose_result = _FP.uc_gscr_block_integration(loose_data, _PM.DCPPowerModel, milp_optimizer)
        @test loose_result["termination_status"] == OPTIMAL

        tight_data = load_case6(
            number_of_hours=4,
            number_of_scenarios=1,
            number_of_years=1,
            share_data=false,
            sn_data_extensions=[_uc_gscr_case6_extension(100.0)],
        )
        tight_result = _FP.uc_gscr_block_integration(tight_data, _PM.DCPPowerModel, milp_optimizer)
        @test tight_result["termination_status"] == INFEASIBLE
    end
end
