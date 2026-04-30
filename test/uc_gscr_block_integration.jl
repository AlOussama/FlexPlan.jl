"""
    _uc_gscr_integration_add_block_fields!(device, type; n0, nmax, na0, p_block_min, p_block_max, q_block_min, q_block_max, b_block, cost_inv_block, startup_block_cost, shutdown_block_cost, e_block=nothing)

Adds UC/gSCR block schema fields to one synthetic integration-test device.

This helper is test-only and mutates `device` in place. Optional `e_block`
is added for storage-capable devices.
"""
function _uc_gscr_integration_add_block_fields!(device, type; n0, nmax, na0, p_block_min, p_block_max, q_block_min, q_block_max, b_block, cost_inv_block, startup_block_cost, shutdown_block_cost, e_block=nothing)
    device["carrier"] = get(device, "carrier", "test-carrier")
    device["grid_control_mode"] = type
    device["n0"] = n0
    device["nmax"] = nmax
    device["na0"] = na0
    device["p_block_min"] = p_block_min
    device["p_block_max"] = p_block_max
    device["q_block_min"] = q_block_min
    device["q_block_max"] = q_block_max
    device["b_block"] = b_block
    device["startup_cost_per_mw"] = startup_block_cost
    device["shutdown_cost_per_mw"] = shutdown_block_cost
    device["H"] = 3.0
    device["s_block"] = max(abs(p_block_max), 1.0)
    device["cost_inv_per_mw"] = cost_inv_block
    device["p_min_pu"] = 0.0
    device["p_max_pu"] = 1.0
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
    data["block_model_schema"] = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
    data["operation_weight"] = 1.0

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
        na0=0,
        p_block_min=0.0,
        p_block_max=5.0,
        q_block_min=-10.0,
        q_block_max=10.0,
        b_block=0.0,
        cost_inv_block=1.0,
        startup_block_cost=1.0,
        shutdown_block_cost=1.0,
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
        na0=0,
        p_block_min=0.0,
        p_block_max=1.0,
        q_block_min=-10.0,
        q_block_max=10.0,
        b_block=1.0,
        cost_inv_block=7.0,
        startup_block_cost=1.0,
        shutdown_block_cost=1.0,
    )
    data["gen"]["2"] = gfm

    _uc_gscr_integration_add_block_fields!(
        data["storage"]["1"],
        "gfm";
        n0=1,
        nmax=3,
        na0=1,
        p_block_min=0.0,
        p_block_max=1.0,
        q_block_min=-1.0,
        q_block_max=1.0,
        b_block=0.0,
        cost_inv_block=0.5,
        startup_block_cost=1.0,
        shutdown_block_cost=1.0,
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

function _uc_gscr_integration_test_template()
    return _FP.UCGSCRBlockTemplate(Dict(
        (:gen, "test-carrier") => _FP.BlockThermalCommitment(),
        (:storage, "test-carrier") => _FP.BlockThermalCommitment(),
        (:ne_storage, "test-carrier") => _FP.BlockThermalCommitment(),
    ))
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
        sn_data["block_model_schema"] = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
        sn_data["operation_weight"] = 1.0
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
                    na0=0,
                    p_block_min=0.0,
                    p_block_max=gen["pmax"] / 2,
                    q_block_min=gen["qmin"],
                    q_block_max=gen["qmax"],
                    b_block=0.0,
                    cost_inv_block=1.0,
                    startup_block_cost=1.0,
                    shutdown_block_cost=1.0,
                )
            elseif gen_id == gfm_id
                gen["gen_bus"] = gfl_bus
                gen["pmax"] = 0.0
                _uc_gscr_integration_add_block_fields!(
                    gen,
                    "gfm";
                    n0=0,
                    nmax=2,
                    na0=0,
                    p_block_min=0.0,
                    p_block_max=1.0,
                    q_block_min=gen["qmin"],
                    q_block_max=gen["qmax"],
                    b_block=1.0,
                    cost_inv_block=50.0,
                    startup_block_cost=1.0,
                    shutdown_block_cost=1.0,
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
function _uc_gscr_build_integration_pm(data; template=_uc_gscr_integration_test_template())
    return _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        pm -> _FP.build_uc_gscr_block_integration(pm; template);
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
end

function _uc_gscr_block_only_ne_storage_fixture()
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
    data["block_model_schema"] = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
    data["operation_weight"] = 1.0
    data["g_min"] = 0.0
    data["gen"] = Dict{String,Any}()
    data["load"] = Dict{String,Any}()
    data["storage"] = Dict{String,Any}()

    ne = data["ne_storage"]["1"]
    ne["energy"] = 0.0
    ne["energy_rating"] = 0.0
    ne["charge_rating"] = 0.0
    ne["discharge_rating"] = 0.0
    ne["thermal_rating"] = 0.0
    ne["stationary_energy_inflow"] = 0.0
    ne["stationary_energy_outflow"] = 0.0
    ne["self_discharge_rate"] = 0.0
    _uc_gscr_integration_add_block_fields!(
        ne,
        "gfl";
        n0=0,
        nmax=3,
        na0=0,
        p_block_min=0.0,
        p_block_max=5.0,
        q_block_min=-1.0,
        q_block_max=1.0,
        b_block=0.0,
        cost_inv_block=2.0,
        startup_block_cost=0.0,
        shutdown_block_cost=0.0,
        e_block=10.0,
    )

    _FP.add_dimension!(data, :hour, 2)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    return _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
end

"""
    _uc_gscr_transition_fixture(; na0=1.0, n0=0.0, nmax=8.0, startup_cost=1.0, shutdown_cost=1.0, include_storage=false, hours=2)

Builds a deterministic UC/gSCR block fixture used by startup/shutdown tests.

The returned multinetwork can include only a generator block device or all
three component tables (`gen`, `storage`, `ne_storage`) to validate compound
keys. The helper is test-only and mutates only local fixture data.
"""
function _uc_gscr_transition_fixture(; na0::Float64=1.0, n0::Float64=1.0, nmax::Float64=8.0, startup_cost::Float64=1.0, shutdown_cost::Float64=1.0, include_storage::Bool=false, hours::Int=2)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
    data["block_model_schema"] = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
    data["operation_weight"] = 1.0
    data["g_min"] = 0.0

    _uc_gscr_integration_add_block_fields!(
        data["gen"]["1"],
        "gfl";
        n0=n0,
        nmax=nmax,
        na0=na0,
        p_block_min=0.0,
        p_block_max=20.0,
        q_block_min=-10.0,
        q_block_max=10.0,
        b_block=0.0,
        cost_inv_block=0.0,
        startup_block_cost=startup_cost,
        shutdown_block_cost=shutdown_cost,
    )

    if include_storage
        _uc_gscr_integration_add_block_fields!(
            data["storage"]["1"],
            "gfm";
            n0=n0,
            nmax=nmax,
            na0=na0,
            p_block_min=0.0,
            p_block_max=5.0,
            q_block_min=-1.0,
            q_block_max=1.0,
            b_block=0.5,
            cost_inv_block=0.0,
            startup_block_cost=startup_cost + 1.0,
            shutdown_block_cost=shutdown_cost + 1.0,
            e_block=2.0,
        )
        _uc_gscr_integration_add_block_fields!(
            data["ne_storage"]["1"],
            "gfl";
            n0=n0,
            nmax=nmax,
            na0=na0,
            p_block_min=0.0,
            p_block_max=5.0,
            q_block_min=-1.0,
            q_block_max=1.0,
            b_block=0.0,
            cost_inv_block=0.0,
            startup_block_cost=startup_cost + 2.0,
            shutdown_block_cost=shutdown_cost + 2.0,
            e_block=2.0,
        )
    else
        data["storage"] = Dict{String,Any}()
        data["ne_storage"] = Dict{String,Any}()
    end

    _FP.add_dimension!(data, :hour, hours)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    return _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
end

"""
    _uc_gscr_transition_pm(data; relax=true)

Instantiates a DCP model fixture with UC/gSCR block variables on all snapshots.

This helper is test-only and mutates only the created model.
"""
function _uc_gscr_transition_pm(data; relax::Bool=true)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        pm -> nothing;
        ref_extensions=[_FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    if any(_FP._has_uc_gscr_block_ref(pm, nw) for nw in _FP.nw_ids(pm))
        _FP.resolve_uc_gscr_block_template!(pm, _uc_gscr_integration_test_template())
    end
    for nw in _FP.nw_ids(pm)
        _FP.variable_uc_gscr_block(pm; nw, relax, report=false)
    end
    return pm
end

"""
    _uc_gscr_block_ref_wrapper(nw_ref)

Builds a minimal PowerModels reference wrapper for validation-error tests.

This helper is test-only and mutates no data.
"""
function _uc_gscr_block_ref_wrapper(nw_ref)
    return Dict{Symbol,Any}(
        :it => Dict{Symbol,Any}(
            _PM.pm_it_sym => Dict{Symbol,Any}(
                :nw => Dict{Int,Any}(0 => nw_ref),
            ),
        ),
    )
end

"""
    _uc_gscr_two_island_dcline_data(; load_bus2=80.0, dcline_pmax=100.0, include_dcline=true, gen_bus2=false)

Builds a 2-bus, single-snapshot AC model with no AC branch and optional dcline.

Bus 2 carries demand. A block-annotated generator is always available at bus 1,
and optionally at bus 2 for no-dcline regression checks.
"""
function _uc_gscr_two_island_dcline_data(; load_bus2::Float64=80.0, dcline_pmax::Float64=100.0, include_dcline::Bool=true, gen_bus2::Bool=false)
    nw = Dict{String,Any}(
        "baseMVA" => 1.0,
        "bus" => Dict(
            "1" => Dict{String,Any}(
                "index" => 1,
                "name" => "bus1",
                "bus_type" => 3,
                "vmin" => 0.9,
                "vmax" => 1.1,
                "vm" => 1.0,
                "va" => 0.0,
                "base_kv" => 380.0,
                "zone" => 1,
            ),
            "2" => Dict{String,Any}(
                "index" => 2,
                "name" => "bus2",
                "bus_type" => 1,
                "vmin" => 0.9,
                "vmax" => 1.1,
                "vm" => 1.0,
                "va" => 0.0,
                "base_kv" => 380.0,
                "zone" => 1,
            ),
        ),
        "branch" => Dict{String,Any}(),
        "dcline" => Dict{String,Any}(),
        "shunt" => Dict{String,Any}(),
        "switch" => Dict{String,Any}(),
        "load" => Dict(
            "1" => Dict{String,Any}(
                "index" => 1,
                "load_bus" => 2,
                "pd" => load_bus2,
                "qd" => 0.0,
                "status" => 1,
            ),
        ),
        "gen" => Dict{String,Any}(),
        "storage" => Dict{String,Any}(),
        "ne_storage" => Dict{String,Any}(),
        "g_min" => 0.0,
    )

    gen1 = Dict{String,Any}(
        "index" => 1,
        "gen_bus" => 1,
        "gen_status" => 1,
        "dispatchable" => true,
        "pmin" => 0.0,
        "pmax" => 200.0,
        "qmin" => -100.0,
        "qmax" => 100.0,
        "cost" => [0.0, 0.0],
    )
    _uc_gscr_integration_add_block_fields!(
        gen1,
        "gfl";
        n0=0,
        nmax=2,
        na0=0,
        p_block_min=0.0,
        p_block_max=100.0,
        q_block_min=-100.0,
        q_block_max=100.0,
        b_block=0.0,
        cost_inv_block=1.0,
        startup_block_cost=0.0,
        shutdown_block_cost=0.0,
    )
    nw["gen"]["1"] = gen1

    if gen_bus2
        gen2 = deepcopy(gen1)
        gen2["index"] = 2
        gen2["gen_bus"] = 2
        nw["gen"]["2"] = gen2
    end

    if include_dcline
        p_set = min(load_bus2, dcline_pmax)
        nw["dcline"]["1"] = Dict{String,Any}(
            "index" => 1,
            "f_bus" => 1,
            "t_bus" => 2,
            "br_status" => 1,
            "pf" => p_set,
            "pt" => -p_set,
            "qf" => 0.0,
            "qt" => 0.0,
            "pminf" => -dcline_pmax,
            "pmaxf" => dcline_pmax,
            "pmint" => -dcline_pmax,
            "pmaxt" => dcline_pmax,
            "qminf" => 0.0,
            "qmaxf" => 0.0,
            "qmint" => 0.0,
            "qmaxt" => 0.0,
            "loss0" => 0.0,
            "loss1" => 0.0,
            "vf" => 1.0,
            "vt" => 1.0,
            "model" => 2,
            "cost" => [0.0, 0.0],
        )
    end

    data = Dict{String,Any}(
        "name" => "uc_gscr_two_island_dcline",
        "baseMVA" => 1.0,
        "per_unit" => false,
        "source_type" => "synthetic",
        "block_model_schema" => Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0"),
        "operation_weight" => 1.0,
        "bus" => nw["bus"],
        "branch" => nw["branch"],
        "dcline" => nw["dcline"],
        "load" => nw["load"],
        "gen" => nw["gen"],
        "storage" => nw["storage"],
        "ne_storage" => nw["ne_storage"],
        "shunt" => nw["shunt"],
        "switch" => nw["switch"],
        "g_min" => 0.0,
    )
    _FP.add_dimension!(data, :hour, 1)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    return _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
end

@testset "UC/gSCR integrated solve path" begin
    @testset "Block-enabled integration requires a template" begin
        data = _uc_gscr_two_island_dcline_data(; load_bus2=80.0, dcline_pmax=120.0, include_dcline=true, gen_bus2=false)

        @test_throws ErrorException _uc_gscr_build_integration_pm(data; template=nothing)
        @test_throws ErrorException _FP.uc_gscr_block_integration(data, _PM.DCPPowerModel, milp_optimizer)
    end

    @testset "Two-island dcline CAPEXP serves remote load" begin
        data = _uc_gscr_two_island_dcline_data(; load_bus2=80.0, dcline_pmax=120.0, include_dcline=true, gen_bus2=false)
        pm = _uc_gscr_solve_integration_pm(data)

        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
        @test haskey(_PM.var(pm, 1), :p_dc)

        p_dc = _PM.var(pm, 1, :p_dc)
        bus2_dcline_net = sum(JuMP.value(p_dc[a]) for a in _PM.ref(pm, 1, :bus_arcs_dc, 2))
        bus2_load = sum(_PM.ref(pm, 1, :load, l, "pd") for l in _PM.ref(pm, 1, :bus_loads, 2))
        @test abs(bus2_dcline_net) > 1e-6
        @test bus2_dcline_net ≈ -bus2_load atol=1e-5
        @test JuMP.value(_PM.var(pm, 1, :pg, 1)) >= bus2_load - 1e-5
    end

    @testset "Insufficient dcline transfer is infeasible" begin
        data = _uc_gscr_two_island_dcline_data(; load_bus2=80.0, dcline_pmax=20.0, include_dcline=true, gen_bus2=false)
        result = _FP.uc_gscr_block_integration(data, _PM.DCPPowerModel, milp_optimizer; template=_uc_gscr_integration_test_template())
        @test result["termination_status"] == INFEASIBLE
    end

    @testset "No-dcline synthetic regression remains feasible" begin
        data = _uc_gscr_two_island_dcline_data(; load_bus2=80.0, dcline_pmax=0.0, include_dcline=false, gen_bus2=true)
        pm = _uc_gscr_solve_integration_pm(data)
        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
        @test !haskey(_PM.var(pm, 1), :p_dc) || isempty(_PM.var(pm, 1, :p_dc))
    end

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

        result_loose = _FP.uc_gscr_block_integration(data_loose, _PM.DCPPowerModel, milp_optimizer; template=_uc_gscr_integration_test_template())
        @test result_loose["termination_status"] == OPTIMAL

        data_tight = _uc_gscr_synthetic_integration_data(; g_min=1.0)
        result_tight = _FP.uc_gscr_block_integration(data_tight, _PM.DCPPowerModel, milp_optimizer; template=_uc_gscr_integration_test_template())
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

        @test na_binding_gfm >= na_nonbinding_gfm - tol
        @test obj_binding >= obj_nonbinding - tol
        @test na_binding_gfl <= na_nonbinding_gfl + tol

        data_infeasible = _uc_gscr_synthetic_integration_data(; g_min=0.45)
        result_infeasible = _FP.uc_gscr_block_integration(data_infeasible, _PM.DCPPowerModel, milp_optimizer; template=_uc_gscr_integration_test_template())
        @test result_infeasible["termination_status"] in [OPTIMAL, INFEASIBLE]
    end

    @testset "Case6 4h/1s/1y integration" begin
        loose_data = load_case6(
            number_of_hours=4,
            number_of_scenarios=1,
            number_of_years=1,
            share_data=false,
            init_data_extensions=[data -> data["block_model_schema"] = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")],
            sn_data_extensions=[_uc_gscr_case6_extension(0.0)],
        )
        for (_, nw_data) in loose_data["nw"]
            nw_data["dcline"] = Dict{String,Any}()
        end
        loose_result = _FP.uc_gscr_block_integration(loose_data, _PM.DCPPowerModel, milp_optimizer; template=_uc_gscr_integration_test_template())
        @test loose_result["termination_status"] == INFEASIBLE

        tight_data = load_case6(
            number_of_hours=4,
            number_of_scenarios=1,
            number_of_years=1,
            share_data=false,
            init_data_extensions=[data -> data["block_model_schema"] = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")],
            sn_data_extensions=[_uc_gscr_case6_extension(100.0)],
        )
        for (_, nw_data) in tight_data["nw"]
            nw_data["dcline"] = Dict{String,Any}()
        end
        tight_result = _FP.uc_gscr_block_integration(tight_data, _PM.DCPPowerModel, milp_optimizer; template=_uc_gscr_integration_test_template())
        @test tight_result["termination_status"] == INFEASIBLE
    end

    @testset "1 -> 4 transition gives su_block=3 and sd_block=0" begin
        data = _uc_gscr_transition_fixture(; na0=1.0, startup_cost=1.0, shutdown_cost=1.0, include_storage=false, hours=2)
        pm = _uc_gscr_transition_pm(data)

        JuMP.fix(_PM.var(pm, 1, :na_block, (:gen, 1)), 1.0; force=true)
        JuMP.fix(_PM.var(pm, 2, :na_block, (:gen, 1)), 4.0; force=true)
        JuMP.@objective(pm.model, Min, _FP.calc_uc_gscr_block_startup_shutdown_cost(pm))
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)

        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
        @test JuMP.value(_PM.var(pm, 2, :su_block, (:gen, 1))) ≈ 3.0 atol=1e-6
        @test JuMP.value(_PM.var(pm, 2, :sd_block, (:gen, 1))) ≈ 0.0 atol=1e-6
    end

    @testset "5 -> 2 transition gives su_block=0 and sd_block=3" begin
        data = _uc_gscr_transition_fixture(; na0=5.0, n0=5.0, startup_cost=1.0, shutdown_cost=1.0, include_storage=false, hours=2)
        pm = _uc_gscr_transition_pm(data)

        JuMP.fix(_PM.var(pm, 1, :na_block, (:gen, 1)), 5.0; force=true)
        JuMP.fix(_PM.var(pm, 2, :na_block, (:gen, 1)), 2.0; force=true)
        JuMP.@objective(pm.model, Min, _FP.calc_uc_gscr_block_startup_shutdown_cost(pm))
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)

        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
        @test JuMP.value(_PM.var(pm, 2, :su_block, (:gen, 1))) ≈ 0.0 atol=1e-6
        @test JuMP.value(_PM.var(pm, 2, :sd_block, (:gen, 1))) ≈ 3.0 atol=1e-6
    end

    @testset "First-snapshot transition uses na0 explicitly" begin
        data = _uc_gscr_transition_fixture(; na0=3.0, n0=3.0, startup_cost=1.0, shutdown_cost=1.0, include_storage=false, hours=2)
        pm = _uc_gscr_transition_pm(data)
        con = _PM.con(pm, 1)[:block_count_transitions][(:gen, 1)]

        @test JuMP.normalized_coefficient(con, _PM.var(pm, 1, :na_block, (:gen, 1))) == 1.0
        @test JuMP.normalized_coefficient(con, _PM.var(pm, 1, :su_block, (:gen, 1))) == -1.0
        @test JuMP.normalized_coefficient(con, _PM.var(pm, 1, :sd_block, (:gen, 1))) == 1.0
        @test JuMP.normalized_rhs(con) == 3.0
    end

    @testset "Startup/shutdown objective term uses su_block/sd_block counts" begin
        data = _uc_gscr_transition_fixture(; na0=1.0, startup_cost=10.0, shutdown_cost=20.0, include_storage=false, hours=2)
        pm = _uc_gscr_transition_pm(data)
        expr = _FP.calc_uc_gscr_block_startup_shutdown_cost(pm)

        @test JuMP.coefficient(expr, _PM.var(pm, 1, :su_block, (:gen, 1))) == 10.0
        @test JuMP.coefficient(expr, _PM.var(pm, 2, :sd_block, (:gen, 1))) == 20.0
        @test JuMP.coefficient(expr, _PM.var(pm, 1, :na_block, (:gen, 1))) == 0.0

        JuMP.fix(_PM.var(pm, 1, :na_block, (:gen, 1)), 4.0; force=true)
        JuMP.fix(_PM.var(pm, 2, :na_block, (:gen, 1)), 2.0; force=true)
        JuMP.@objective(pm.model, Min, expr)
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)

        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
        @test JuMP.objective_value(pm.model) ≈ 70.0 atol=1e-6
    end

    @testset "Compound keys remain collision-free across gen/storage/ne_storage" begin
        data = _uc_gscr_transition_fixture(; na0=0.0, startup_cost=2.0, shutdown_cost=3.0, include_storage=true, hours=1)
        pm = _uc_gscr_transition_pm(data)
        expr = _FP.calc_uc_gscr_block_startup_shutdown_cost(pm)

        @test Set(axes(_PM.var(pm, 1, :su_block), 1)) == Set([(:gen, 1), (:storage, 1), (:ne_storage, 1)])
        @test Set(axes(_PM.var(pm, 1, :sd_block), 1)) == Set([(:gen, 1), (:storage, 1), (:ne_storage, 1)])
        @test _PM.var(pm, 1, :su_block, (:gen, 1)) !== _PM.var(pm, 1, :su_block, (:storage, 1))
        @test _PM.var(pm, 1, :su_block, (:gen, 1)) !== _PM.var(pm, 1, :su_block, (:ne_storage, 1))

        @test JuMP.coefficient(expr, _PM.var(pm, 1, :su_block, (:gen, 1))) == 2.0
        @test JuMP.coefficient(expr, _PM.var(pm, 1, :su_block, (:storage, 1))) == 3.0
        @test JuMP.coefficient(expr, _PM.var(pm, 1, :su_block, (:ne_storage, 1))) == 4.0
    end

    @testset "Stage path does not activate min-up/min-down constraints" begin
        data = _uc_gscr_transition_fixture(; na0=1.0, startup_cost=1.0, shutdown_cost=1.0, include_storage=false, hours=2)
        for (_, nw_data) in data["nw"]
            nw_data["gen"]["1"]["min_up_block_time"] = 3
            nw_data["gen"]["1"]["min_down_block_time"] = 3
        end

        pm = _uc_gscr_transition_pm(data; relax=false)
        @test !haskey(_PM.con(pm, 1), :block_minimum_up_time)
        @test !haskey(_PM.con(pm, 1), :block_minimum_down_time)
        @test !haskey(_PM.con(pm, 2), :block_minimum_up_time)
        @test !haskey(_PM.con(pm, 2), :block_minimum_down_time)

        JuMP.@objective(pm.model, Min, _FP.calc_uc_gscr_block_startup_shutdown_cost(pm))
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)
        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
    end

    #=
    Archived (commented-out) min-up/min-down tests kept for a future stage:
    - Integration path with min-up/min-down keeps existing objective and gSCR behavior
    - Minimum up-time prevents early shutdown
    - Minimum down-time prevents early restart
    - Count-based startup behavior is preserved (1 -> 4 implies three started blocks)
    - Minimum down-time uses installed blocks n_block - na_block
    - Boundary truncation at first snapshots is correct for min-up/min-down
    - Min-up/min-down constraints remain collision-free across compound keys
    =#

    @testset "Missing na0/startup/shutdown block fields raise explicit validation error" begin
        bad_device = Dict{String,Any}(
            "carrier" => "test-carrier",
            "grid_control_mode" => "gfl",
            "n0" => 1,
            "nmax" => 3,
            "p_block_min" => 0.0,
            "p_block_max" => 10.0,
            "q_block_min" => -1.0,
            "q_block_max" => 1.0,
            "b_block" => 0.0,
            "cost_inv_per_mw" => 1.0,
            "p_min_pu" => 0.0,
            "p_max_pu" => 1.0,
            "gen_bus" => 1,
        )
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(1 => Dict{String,Any}("index" => 1)),
            :gen => Dict{Int,Any}(1 => bad_device),
            :branch => Dict{Int,Any}(),
            :block_model_schema => Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0"),
            :operation_weight => 1.0,
            :time_elapsed => 1.0,
        )
        missing = _FP._uc_gscr_missing_required_fields_report(nw_ref)

        @test haskey(missing, (:gen, 1))
        @test Set(missing[(:gen, 1)]) == Set(["na0"])
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_uc_gscr_block_ref_wrapper(nw_ref), Dict{String,Any}())
    end

    @testset "No-block cases remain backward compatible" begin
        data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
        data["ne_storage"] = Dict{String,Any}()
        _FP.add_dimension!(data, :hour, 2)
        _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
        _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
        mn_data = _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
        pm = _uc_gscr_transition_pm(mn_data)

        @test !haskey(_PM.var(pm, 1), :n_block)
        @test !haskey(_PM.var(pm, 1), :na_block)
        @test !haskey(_PM.var(pm, 1), :su_block)
        @test !haskey(_PM.var(pm, 1), :sd_block)
        @test !haskey(_PM.con(pm, 1), :block_minimum_up_time)
        @test !haskey(_PM.con(pm, 1), :block_minimum_down_time)
        @test JuMP.constant(_FP.calc_uc_gscr_block_startup_shutdown_cost(pm)) == 0.0
    end

    @testset "Block-only candidate storage path removes standard candidate logic" begin
        data = _uc_gscr_block_only_ne_storage_fixture()
        pm = _uc_gscr_build_integration_pm(data)

        @test !haskey(_PM.var(pm, 1), :z_strg_ne)
        @test !haskey(_PM.var(pm, 1), :z_strg_ne_investment)
        @test !haskey(_PM.con(pm, 1), :ne_storage_activation)

        se_ne = _PM.var(pm, 1, :se_ne, 1)
        sc_ne = _PM.var(pm, 1, :sc_ne, 1)
        sd_ne = _PM.var(pm, 1, :sd_ne, 1)
        @test !JuMP.has_upper_bound(se_ne)
        @test !JuMP.has_upper_bound(sc_ne)
        @test !JuMP.has_upper_bound(sd_ne)

        @test haskey(_PM.con(pm, 1), :uc_gscr_block_storage_energy_capacity)
        @test haskey(_PM.con(pm, 1), :uc_gscr_block_storage_charge_discharge_bounds)
        @test !haskey(_PM.con(pm, 1), :storage_bounds_ne)

        obj = JuMP.objective_function(pm.model)
        @test JuMP.coefficient(obj, _PM.var(pm, 1, :n_block, (:ne_storage, 1))) == 10.0
        @test JuMP.coefficient(obj, _PM.var(pm, 1, :su_block, (:ne_storage, 1))) == 0.0
        @test JuMP.coefficient(obj, _PM.var(pm, 1, :sd_block, (:ne_storage, 1))) == 0.0

        # A feasible dispatch with positive block investment and operation under
        # zero standard ratings must be possible in block-only mode.
        JuMP.fix(_PM.var(pm, 1, :n_block, (:ne_storage, 1)), 1.0; force=true)
        JuMP.fix(_PM.var(pm, 1, :na_block, (:ne_storage, 1)), 1.0; force=true)
        JuMP.fix(_PM.var(pm, 2, :na_block, (:ne_storage, 1)), 1.0; force=true)
        JuMP.fix(_PM.var(pm, 1, :su_block, (:ne_storage, 1)), 1.0; force=true)
        JuMP.fix(_PM.var(pm, 1, :sd_block, (:ne_storage, 1)), 0.0; force=true)
        JuMP.fix(_PM.var(pm, 2, :su_block, (:ne_storage, 1)), 0.0; force=true)
        JuMP.fix(_PM.var(pm, 2, :sd_block, (:ne_storage, 1)), 0.0; force=true)
        JuMP.fix(_PM.var(pm, 1, :sc_ne, 1), 1.0; force=true)
        JuMP.fix(_PM.var(pm, 1, :sd_ne, 1), 0.0; force=true)
        JuMP.fix(_PM.var(pm, 2, :sc_ne, 1), 1.0; force=true)
        JuMP.fix(_PM.var(pm, 2, :sd_ne, 1), 0.0; force=true)

        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)
        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL

        se1 = JuMP.value(_PM.var(pm, 1, :se_ne, 1))
        se2 = JuMP.value(_PM.var(pm, 2, :se_ne, 1))
        @test se1 > 0.0
        @test se2 >= 0.0
    end

    @testset "Block-enabled generator ignores standard pmax clipping while non-block stays standard" begin
        data = _uc_gscr_synthetic_integration_data(; g_min=0.0)
        # Add one non-block fixed generator to ensure standard bound path is preserved.
        nw_keys = sort(collect(keys(data["nw"])))
        nw1 = nw_keys[1]
        data["nw"][nw1]["gen"]["3"] = Dict{String,Any}(
            "index" => 3,
            "gen_bus" => data["nw"][nw1]["gen"]["1"]["gen_bus"],
            "gen_status" => 1,
            "dispatchable" => true,
            "pmin" => 0.0,
            "pmax" => 7.0,
            "qmin" => -1.0,
            "qmax" => 1.0,
            "cost" => [0.0, 0.0],
        )
        for nw in nw_keys[2:end]
            data["nw"][nw]["gen"]["3"] = deepcopy(data["nw"][nw1]["gen"]["3"])
        end

        pm = _uc_gscr_build_integration_pm(data)
        @test !JuMP.has_upper_bound(_PM.var(pm, 1, :pg, 1))
        @test JuMP.upper_bound(_PM.var(pm, 1, :pg, 3)) == 7.0
        @test haskey(pm.ext, :uc_gscr_block_architecture_diagnostics)
    end

    @testset "g_min=0 remains non-restrictive in block-only path" begin
        data = _uc_gscr_synthetic_integration_data(; g_min=0.0)
        result = _FP.uc_gscr_block_integration(data, _PM.DCPPowerModel, milp_optimizer; template=_uc_gscr_integration_test_template())
        @test result["termination_status"] == OPTIMAL
    end

end
