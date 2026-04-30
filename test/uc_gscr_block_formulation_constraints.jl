function _uc_gscr_formulation_set_block_fields!(
    device,
    mode,
    carrier;
    n0=1.0,
    nmax=6.0,
    na0=1.0,
    p_block_max=10.0,
    b_block=nothing,
    e_block=nothing,
    startup=false,
)
    device["carrier"] = carrier
    device["grid_control_mode"] = mode
    device["n0"] = n0
    device["nmax"] = nmax
    device["na0"] = na0
    device["p_block_max"] = p_block_max
    device["q_block_min"] = -2.0
    device["q_block_max"] = 2.0
    device["b_block"] = isnothing(b_block) ? (mode == "gfm" ? 1.0 : 0.0) : b_block
    device["cost_inv_per_mw"] = 1.0
    device["p_min_pu"] = 0.0
    device["p_max_pu"] = 1.0
    if startup
        device["startup_cost_per_mw"] = 10.0
        device["shutdown_cost_per_mw"] = 20.0
    else
        delete!(device, "startup_cost_per_mw")
        delete!(device, "shutdown_cost_per_mw")
    end
    if !isnothing(e_block)
        device["e_block"] = e_block
    end
    return device
end

function _uc_gscr_formulation_template()
    return _FP.UCGSCRBlockTemplate(
        Dict(
            (:gen, "CCGT") => _FP.BlockThermalCommitment(),
            (:gen, "onwind") => _FP.BlockRenewableParticipation(),
            (:ne_storage, "BESS-GFM") => _FP.BlockFixedInstalled(),
        ),
        _FP.NoGSCR(),
    )
end

function _uc_gscr_storage_participation_template()
    return _FP.UCGSCRBlockTemplate(
        Dict(
            (:gen, "CCGT") => _FP.BlockThermalCommitment(),
            (:gen, "onwind") => _FP.BlockRenewableParticipation(),
            (:ne_storage, "BESS-GFM") => _FP.BlockStorageParticipation(),
        ),
        _FP.NoGSCR(),
    )
end

function _uc_gscr_formulation_data(; hours=2, thermal_n0=1.0, thermal_na0=1.0, thermal_nmax=6.0)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
    data["block_model_schema"] = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
    data["operation_weight"] = 1.0
    data["time_elapsed"] = 1.0
    data["storage"] = Dict{String,Any}()

    thermal = data["gen"]["1"]
    thermal["index"] = 1
    thermal["gen_bus"] = 1
    thermal["pmin"] = 0.0
    thermal["pmax"] = 60.0
    _uc_gscr_formulation_set_block_fields!(
        thermal,
        "gfl",
        "CCGT";
        n0=thermal_n0,
        nmax=thermal_nmax,
        na0=thermal_na0,
        p_block_max=10.0,
        startup=true,
    )

    wind = deepcopy(thermal)
    wind["index"] = 2
    wind["gen_bus"] = 1
    wind["pmax"] = 60.0
    _uc_gscr_formulation_set_block_fields!(
        wind,
        "gfl",
        "onwind";
        n0=0.0,
        nmax=4.0,
        na0=0.0,
        p_block_max=15.0,
        startup=false,
    )
    wind["p_max_pu"] = 0.5
    data["gen"]["2"] = wind

    bess = data["ne_storage"]["1"]
    bess["charge_rating"] = 10.0
    bess["discharge_rating"] = 10.0
    _uc_gscr_formulation_set_block_fields!(
        bess,
        "gfm",
        "BESS-GFM";
        n0=2.0,
        nmax=2.0,
        na0=2.0,
        p_block_max=5.0,
        e_block=10.0,
        startup=false,
    )

    _FP.add_dimension!(data, :hour, hours)
    _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
    _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    return _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
end

function _uc_gscr_formulation_pm(; hours=2, thermal_n0=1.0, thermal_na0=1.0, thermal_nmax=6.0, template=_uc_gscr_formulation_template())
    data = _uc_gscr_formulation_data(; hours, thermal_n0, thermal_na0, thermal_nmax)
    pm = _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        pm -> nothing;
        ref_extensions=[_FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
    _FP.resolve_uc_gscr_block_template!(pm, template)
    for nw in _FP.nw_ids(pm)
        _FP.variable_uc_gscr_block(pm; nw, relax=true, report=false)
    end
    return pm
end

@testset "UC/gSCR block formulation-specific constraints" begin
    thermal_key = (:gen, 1)
    wind_key = (:gen, 2)
    bess_key = (:ne_storage, 1)

    @testset "Block variables require a resolved template" begin
        data = _uc_gscr_formulation_data()
        pm = _PM.instantiate_model(
            data,
            _PM.DCPPowerModel,
            pm -> nothing;
            ref_extensions=[_FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
        )

        @test_throws ErrorException _FP.variable_uc_gscr_block(pm; nw=1, relax=true, report=false)
    end

    @testset "Variables follow resolved formulation device sets" begin
        pm = _uc_gscr_formulation_pm()

        all_keys = Set([thermal_key, wind_key, bess_key])
        @test Set(axes(_PM.var(pm, 1, :n_block), 1)) == all_keys
        @test Set(axes(_PM.var(pm, 1, :na_block), 1)) == all_keys
        @test Set(axes(_PM.var(pm, 1, :su_block), 1)) == Set([thermal_key])
        @test Set(axes(_PM.var(pm, 1, :sd_block), 1)) == Set([thermal_key])
        @test !(wind_key in axes(_PM.var(pm, 1, :su_block), 1))
        @test !(bess_key in axes(_PM.var(pm, 1, :sd_block), 1))
    end

    @testset "Thermal transition constraints use startup/shutdown variables" begin
        pm = _uc_gscr_formulation_pm(; thermal_n0=1.0, thermal_na0=1.0, thermal_nmax=6.0)

        JuMP.fix(_PM.var(pm, 1, :na_block, thermal_key), 1.0; force=true)
        JuMP.fix(_PM.var(pm, 2, :na_block, thermal_key), 4.0; force=true)
        JuMP.@objective(pm.model, Min, _FP.calc_uc_gscr_block_startup_shutdown_cost(pm))
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)

        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
        @test JuMP.value(_PM.var(pm, 2, :su_block, thermal_key)) ≈ 3.0 atol=1e-6
        @test JuMP.value(_PM.var(pm, 2, :sd_block, thermal_key)) ≈ 0.0 atol=1e-6

        pm_down = _uc_gscr_formulation_pm(; thermal_n0=5.0, thermal_na0=5.0, thermal_nmax=6.0)
        JuMP.fix(_PM.var(pm_down, 1, :na_block, thermal_key), 5.0; force=true)
        JuMP.fix(_PM.var(pm_down, 2, :na_block, thermal_key), 2.0; force=true)
        JuMP.@objective(pm_down.model, Min, _FP.calc_uc_gscr_block_startup_shutdown_cost(pm_down))
        JuMP.set_optimizer(pm_down.model, HiGHS.Optimizer)
        JuMP.set_silent(pm_down.model)
        JuMP.optimize!(pm_down.model)

        @test JuMP.termination_status(pm_down.model) == JuMP.MOI.OPTIMAL
        @test JuMP.value(_PM.var(pm_down, 2, :su_block, thermal_key)) ≈ 0.0 atol=1e-6
        @test JuMP.value(_PM.var(pm_down, 2, :sd_block, thermal_key)) ≈ 3.0 atol=1e-6
    end

    @testset "First snapshot transition uses thermal na0" begin
        pm = _uc_gscr_formulation_pm(; thermal_n0=2.0, thermal_na0=2.0, thermal_nmax=6.0)

        JuMP.fix(_PM.var(pm, 1, :na_block, thermal_key), 5.0; force=true)
        JuMP.@objective(pm.model, Min, _FP.calc_uc_gscr_block_startup_shutdown_cost(pm))
        JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)

        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
        @test JuMP.value(_PM.var(pm, 1, :su_block, thermal_key)) ≈ 3.0 atol=1e-6
        @test JuMP.value(_PM.var(pm, 1, :sd_block, thermal_key)) ≈ 0.0 atol=1e-6
    end

    @testset "Fixed installed devices impose na_block equals n_block" begin
        pm = _uc_gscr_formulation_pm()
        con = _PM.con(pm, 1)[:fixed_installed_active_equals_installed][bess_key]

        @test JuMP.normalized_coefficient(con, _PM.var(pm, 1, :na_block, bess_key)) == 1.0
        @test JuMP.normalized_coefficient(con, _PM.var(pm, 1, :n_block, bess_key)) == -1.0
        @test JuMP.normalized_rhs(con) == 0.0
    end

    @testset "Renewable participation has bounds but no startup/shutdown transition" begin
        pm = _uc_gscr_formulation_pm()

        @test !(wind_key in axes(_PM.var(pm, 1, :su_block), 1))
        @test !haskey(_PM.con(pm, 1)[:block_count_transitions], wind_key)

        na_wind = _PM.var(pm, 1, :na_block, wind_key)
        n_wind = _PM.var(pm, 1, :n_block, wind_key)
        con = _PM.con(pm, 1)[:active_blocks_le_installed][wind_key]
        @test JuMP.lower_bound(na_wind) == 0.0
        @test JuMP.normalized_coefficient(con, na_wind) == 1.0
        @test JuMP.normalized_coefficient(con, n_wind) == -1.0
        @test JuMP.normalized_rhs(con) == 0.0
    end

    @testset "Startup/shutdown objective only reads thermal devices" begin
        pm = _uc_gscr_formulation_pm()
        expr = _FP.calc_uc_gscr_block_startup_shutdown_cost(pm)

        @test JuMP.coefficient(expr, _PM.var(pm, 1, :su_block, thermal_key)) == 10.0
        @test JuMP.coefficient(expr, _PM.var(pm, 1, :sd_block, thermal_key)) == 20.0
        @test !(wind_key in axes(_PM.var(pm, 1, :su_block), 1))
        @test !(bess_key in axes(_PM.var(pm, 1, :sd_block), 1))
    end

    @testset "Storage participation has active bounds but no startup/shutdown transition" begin
        pm = _uc_gscr_formulation_pm(; template=_uc_gscr_storage_participation_template())

        @test !(bess_key in axes(_PM.var(pm, 1, :su_block), 1))
        @test !haskey(_PM.con(pm, 1)[:block_count_transitions], bess_key)
        @test haskey(_PM.con(pm, 1)[:active_blocks_le_installed], bess_key)
        @test isempty(_PM.con(pm, 1)[:fixed_installed_active_equals_installed])
    end
end
