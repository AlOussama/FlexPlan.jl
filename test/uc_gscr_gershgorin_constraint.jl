"""
    _uc_gscr_gershgorin_device(type, bus; id=1, n0=0, nmax=1, pmax=1.0, bblock=0.0)

Builds one synthetic generator with UC/gSCR block fields for Gershgorin tests.

The helper creates test-only device records whose `p_block_max` and `b_block`
values exercise the linear sufficient condition. It is formulation-independent
and mutates no external state.
"""
function _uc_gscr_gershgorin_device(type, bus; id=1, n0=0, nmax=1, pmax=1.0, bblock=0.0)
    return Dict{String,Any}(
        "index" => id,
        "gen_bus" => bus,
        "gen_status" => 1,
        "pmin" => 0.0,
        "pmax" => pmax,
        "qmin" => -1.0,
        "qmax" => 1.0,
        "vg" => 1.0,
        "mbase" => 1.0,
        "model" => 2,
        "startup" => 0.0,
        "shutdown" => 0.0,
        "ncost" => 2,
        "cost" => [0.0, 0.0],
        "carrier" => "test-carrier",
        "grid_control_mode" => type,
        "n0" => n0,
        "nmax" => nmax,
        "na0" => n0,
        "p_block_min" => 0.0,
        "p_block_max" => pmax,
        "q_block_min" => -1.0,
        "q_block_max" => 1.0,
        "b_block" => bblock,
        "cost_inv_per_mw" => 1.0,
        "p_min_pu" => 0.0,
        "p_max_pu" => 1.0,
        "startup_cost_per_mw" => 1.0,
        "shutdown_cost_per_mw" => 1.0,
    )
end

"""
    _uc_gscr_gershgorin_data(; g_min=2.0, include_g_min=true, gfm_b=3.0)

Builds a four-bus UC/gSCR block fixture for Gershgorin constraint tests.

The buses cover mixed GFL/GFM, only GFL, only GFM, and neither. Branches are
empty so `gscr_sigma0_gershgorin_margin` is zero at every bus. The helper is
test-only, formulation-independent, and mutates only its local fixture data.
"""
function _uc_gscr_gershgorin_data(; g_min=2.0, include_g_min::Bool=true, gfm_b=3.0)
    data = Dict{String,Any}(
        "bus" => Dict{String,Any}(
            string(i) => Dict{String,Any}(
                "index" => i,
                "bus_i" => i,
                "bus_type" => i == 1 ? 3 : 1,
                "vmin" => 0.9,
                "vmax" => 1.1,
                "va" => 0.0,
                "vm" => 1.0,
                "base_kv" => 1.0,
                "zone" => 1,
            ) for i in 1:4
        ),
        "branch" => Dict{String,Any}(),
        "gen" => Dict{String,Any}(
            "1" => _uc_gscr_gershgorin_device("gfl", 1; id=1, n0=1, nmax=1, pmax=1.0, bblock=0.0),
            "2" => _uc_gscr_gershgorin_device("gfm", 1; id=2, n0=1, nmax=1, pmax=0.0, bblock=gfm_b),
            "3" => _uc_gscr_gershgorin_device("gfl", 2; id=3, n0=0, nmax=1, pmax=1.5, bblock=0.0),
            "4" => _uc_gscr_gershgorin_device("gfm", 3; id=4, n0=0, nmax=1, pmax=1.0, bblock=0.7),
        ),
        "load" => Dict{String,Any}(),
        "shunt" => Dict{String,Any}(),
        "storage" => Dict{String,Any}(),
        "switch" => Dict{String,Any}(),
        "dcline" => Dict{String,Any}(),
        "per_unit" => true,
        "block_model_schema" => Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0"),
        "operation_weight" => 1.0,
    )

    if include_g_min
        data["g_min"] = g_min
    end

    _FP.add_dimension!(data, :hour, 1)
    return _FP.make_multinetwork(data, Dict{String,Any}())
end

function _uc_gscr_gershgorin_test_template()
    return _FP.UCGSCRBlockTemplate(Dict((:gen, "test-carrier") => _FP.BlockThermalCommitment()), _FP.NoGSCR())
end

"""
    _uc_gscr_gershgorin_pm(; g_min=2.0, include_g_min=true, gfm_b=3.0)

Instantiates a minimal DCP model with UC/gSCR block variables.

The returned model is used to validate the Gershgorin sufficient condition
without adding any problem definition or objective term. It is test-only and
mutates only the model it creates.
"""
function _uc_gscr_gershgorin_pm(; g_min=2.0, include_g_min::Bool=true, gfm_b=3.0)
    data = _uc_gscr_gershgorin_data(; g_min, include_g_min, gfm_b)
    pm = _PM.instantiate_model(data, _PM.DCPPowerModel, pm -> nothing; ref_extensions=[_FP.ref_add_uc_gscr_block!])
    _FP.resolve_uc_gscr_block_template!(pm, _uc_gscr_gershgorin_test_template())
    _FP.variable_uc_gscr_block(pm; nw=1, relax=true, report=false)
    return pm
end

"""
    _fix_uc_gscr_active_blocks!(pm, values; nw=1)

Fixes selected active block variables for feasibility tests.

`values` maps compound device keys to fixed `na_block` values, allowing tests
to check feasible and infeasible realizations of the affine Gershgorin
condition. This test-only helper mutates only JuMP variable bounds.
"""
function _fix_uc_gscr_active_blocks!(pm, values; nw::Int=1)
    for (device_key, value) in values
        JuMP.fix(_PM.var(pm, nw, :na_block, device_key), value; force=true)
    end
end

@testset "UC/gSCR Gershgorin sufficient constraint" begin
    @testset "Builds the documented affine equation for all buses" begin
        pm = _uc_gscr_gershgorin_pm(; g_min=2.0)
        _PM.ref(pm, 1, :gscr_sigma0_gershgorin_margin)[1] = 4.25
        _FP.constraint_gscr_gershgorin_sufficient(pm; nw=1)

        constraints = _PM.con(pm, 1)[:gscr_gershgorin_sufficient]
        @test Set(keys(constraints)) == Set([1, 2, 3, 4])

        na_gfl_1 = _PM.var(pm, 1, :na_block, (:gen, 1))
        na_gfm_1 = _PM.var(pm, 1, :na_block, (:gen, 2))
        na_gfl_2 = _PM.var(pm, 1, :na_block, (:gen, 3))
        na_gfm_3 = _PM.var(pm, 1, :na_block, (:gen, 4))

        @test JuMP.normalized_coefficient(constraints[1], na_gfm_1) == 3.0
        @test JuMP.normalized_coefficient(constraints[1], na_gfl_1) == -2.0
        @test JuMP.normalized_rhs(constraints[1]) == -4.25

        @test JuMP.normalized_coefficient(constraints[2], na_gfl_2) == -3.0
        @test JuMP.normalized_rhs(constraints[2]) == 0.0

        @test JuMP.normalized_coefficient(constraints[3], na_gfm_3) == 0.7
        @test JuMP.normalized_rhs(constraints[3]) == 0.0

        @test JuMP.normalized_rhs(constraints[4]) == 0.0
    end

    @testset "Feasible fixed active blocks satisfy the Gershgorin inequality" begin
        pm = _uc_gscr_gershgorin_pm(; g_min=2.0, gfm_b=3.0)
        _fix_uc_gscr_active_blocks!(pm, Dict((:gen, 1) => 1.0, (:gen, 2) => 1.0, (:gen, 3) => 0.0, (:gen, 4) => 0.0))
        _FP.constraint_gscr_gershgorin_sufficient(pm; nw=1)
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)

        JuMP.optimize!(pm.model)
        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
    end

    @testset "Infeasible fixed active blocks violate the Gershgorin inequality" begin
        pm = _uc_gscr_gershgorin_pm(; g_min=2.0, gfm_b=1.5)
        _fix_uc_gscr_active_blocks!(pm, Dict((:gen, 1) => 1.0, (:gen, 2) => 1.0, (:gen, 3) => 0.0, (:gen, 4) => 0.0))
        _FP.constraint_gscr_gershgorin_sufficient(pm; nw=1)
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)

        JuMP.optimize!(pm.model)
        @test JuMP.termination_status(pm.model) == JuMP.MOI.INFEASIBLE
    end

    @testset "Missing global g_min raises an explicit validation error" begin
        pm = _uc_gscr_gershgorin_pm(; include_g_min=false)

        @test_throws ErrorException _FP.constraint_gscr_gershgorin_sufficient(pm; nw=1)
    end
end
