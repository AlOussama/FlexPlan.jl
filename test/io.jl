# Test IO functions provided by files in `src/io/`

@testset "Input-ouput" begin

    # case6:
    # - investments: AC branches, converters, DC branches, storage;
    # - generators: with `pg>0`, non-dispatchable with `pcurt>0`;
    case6_data = load_case6(number_of_hours=4, number_of_scenarios=1, number_of_years=1, scale_gen=13, share_data=false)
    case6_result = _FP.simple_stoch_flex_tnep(case6_data, _PM.DCPPowerModel, milp_optimizer; setting=Dict("conv_losses_mp"=>false))

    # ieee_33:
    # - investments: AC branches, storage, flexible loads;
    # - flexible loads: shift up, shift down, voluntary reduction, curtailment.
    ieee_33_data = load_ieee_33(number_of_hours=4, number_of_scenarios=1, number_of_years=1, scale_load=1.52, share_data=false)
    ieee_33_result = _FP.simple_stoch_flex_tnep(ieee_33_data, _FP.BFARadPowerModel, milp_optimizer)

    @testset "scale_data!" begin

        @testset "cost_scale_factor" begin
            scale_factor = 1e-6

            data = load_case6(number_of_hours=4, number_of_scenarios=1, number_of_years=1, scale_gen=13, cost_scale_factor=scale_factor)
            result_scaled = _FP.simple_stoch_flex_tnep(data, _PM.DCPPowerModel, milp_optimizer; setting=Dict("conv_losses_mp"=>false))
            @test result_scaled["objective"] ≈ scale_factor*case6_result["objective"] rtol=1e-5

            data = load_ieee_33(number_of_hours=4, number_of_scenarios=1, number_of_years=1, scale_load=1.52, cost_scale_factor=scale_factor)
            result_scaled = _FP.simple_stoch_flex_tnep(data, _FP.BFARadPowerModel, milp_optimizer)
            @test result_scaled["objective"] ≈ scale_factor*ieee_33_result["objective"] rtol=1e-5
        end
    end

    @testset "convert_mva_base!" begin
        for mva_base_ratio in [0.01, 100]
            data = deepcopy(case6_data)
            mva_base = data["nw"]["1"]["baseMVA"] * mva_base_ratio
            _FP.convert_mva_base!(data, mva_base)
            result = _FP.simple_stoch_flex_tnep(data, _PM.DCPPowerModel, milp_optimizer; setting=Dict("conv_losses_mp"=>false))
            @test result["objective"] ≈ case6_result["objective"] rtol=1e-5

            data = deepcopy(ieee_33_data)
            mva_base = data["nw"]["1"]["baseMVA"] * mva_base_ratio
            _FP.convert_mva_base!(data, mva_base)
            result = _FP.simple_stoch_flex_tnep(data, _FP.BFARadPowerModel, milp_optimizer)
            @test result["objective"] ≈ ieee_33_result["objective"] rtol=1e-5
        end
    end

    @testset "UC/gSCR block field unit conventions" begin
        @testset "Parser scaling matches gen/storage/ne_storage internal bases" begin
            parse_data = Dict{String,Any}(
                "baseMVA" => 100.0,
                "gen" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "dispatchable" => true,
                        "pmax" => 0.5,
                        "qmax" => 0.2,
                        "p_block_min" => 10.0,
                        "p_block_max" => 50.0,
                        "q_block_min" => -20.0,
                        "q_block_max" => 20.0,
                        "s_block" => 60.0,
                        "b_block" => 0.4,
                        "H" => 3.5,
                        "cost_inv_per_mw" => 1200.0,
                    ),
                ),
                "storage" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "max_energy_absorption" => 5.0,
                        "stationary_energy_outflow" => 2.0,
                        "stationary_energy_inflow" => 1.0,
                        "p_block_max" => 40.0,
                        "q_block_max" => 30.0,
                        "e_block" => 80.0,
                        "s_block" => 50.0,
                        "H" => 4.0,
                        "b_block" => 0.1,
                        "cost_inv_per_mw" => 2200.0,
                    ),
                ),
                "ne_storage" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "energy_rating" => 100.0,
                        "thermal_rating" => 100.0,
                        "discharge_rating" => 100.0,
                        "charge_rating" => 100.0,
                        "energy" => 20.0,
                        "ps" => 0.0,
                        "qs" => 0.0,
                        "q_loss" => 0.0,
                        "p_loss" => 0.0,
                        "qmax" => 50.0,
                        "qmin" => -50.0,
                        "max_energy_absorption" => 4.0,
                        "stationary_energy_outflow" => 1.0,
                        "stationary_energy_inflow" => 1.0,
                        "p_block_max" => 30.0,
                        "q_block_max" => 25.0,
                        "e_block" => 70.0,
                        "s_block" => 45.0,
                        "H" => 5.0,
                        "b_block" => 0.2,
                        "cost_inv_per_mw" => 3200.0,
                    ),
                ),
            )

            _FP._add_gen_data!(parse_data)
            _FP._add_storage_data!(parse_data)

            @test parse_data["gen"]["1"]["p_block_max"] ≈ parse_data["gen"]["1"]["pmax"]
            @test parse_data["gen"]["1"]["q_block_max"] ≈ parse_data["gen"]["1"]["qmax"]
            @test parse_data["gen"]["1"]["H"] == 3.5
            @test parse_data["gen"]["1"]["cost_inv_per_mw"] == 1200.0

            @test parse_data["storage"]["1"]["e_block"] ≈ 0.8
            @test parse_data["storage"]["1"]["p_block_max"] ≈ 0.4
            @test parse_data["storage"]["1"]["q_block_max"] ≈ 0.3

            @test parse_data["ne_storage"]["1"]["e_block"] ≈ 0.7
            @test parse_data["ne_storage"]["1"]["p_block_max"] ≈ 0.3
            @test parse_data["ne_storage"]["1"]["q_block_max"] ≈ 0.25
            @test parse_data["ne_storage"]["1"]["H"] == 5.0
            @test parse_data["ne_storage"]["1"]["cost_inv_per_mw"] == 3200.0
        end

        @testset "MVA-base conversion keeps block admittance on the same base as network admittance terms" begin
            mva_data = Dict{String,Any}(
                "baseMVA" => 100.0,
                "bus" => Dict{String,Any}(
                    "1" => Dict{String,Any}("index" => 1),
                    "2" => Dict{String,Any}("index" => 2),
                ),
                "branch" => Dict{String,Any}(
                    "1" => Dict{String,Any}("f_bus" => 1, "t_bus" => 2, "br_x" => 0.2, "br_status" => 1),
                ),
                "gen" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "pmax" => 1.0,
                        "pmin" => 0.0,
                        "qmax" => 0.4,
                        "qmin" => -0.4,
                        "model" => 2,
                        "ncost" => 2,
                        "pg" => 0.0,
                        "qg" => 0.0,
                        "p_block_max" => 0.8,
                        "q_block_max" => 0.3,
                        "s_block" => 0.8,
                        "b_block" => 5.0,
                        "H" => 6.0,
                        "cost_inv_per_mw" => 1800.0,
                        "cost" => [10.0, 0.0],
                    ),
                ),
                "storage" => Dict{String,Any}(),
                "ne_storage" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
                "shunt" => Dict{String,Any}(),
            )

            b_branch_before = 1 / mva_data["branch"]["1"]["br_x"]
            b_block_before = mva_data["gen"]["1"]["b_block"]

            _FP.convert_mva_base!(mva_data, 200.0)

            b_branch_after = 1 / mva_data["branch"]["1"]["br_x"]
            b_block_after = mva_data["gen"]["1"]["b_block"]

            @test mva_data["gen"]["1"]["p_block_max"] ≈ 0.4
            @test mva_data["gen"]["1"]["q_block_max"] ≈ 0.15
            @test mva_data["gen"]["1"]["s_block"] ≈ 0.4
            @test (b_block_after / b_block_before) ≈ (b_branch_after / b_branch_before)
            @test mva_data["gen"]["1"]["H"] == 6.0
            @test mva_data["gen"]["1"]["cost_inv_per_mw"] == 1800.0
        end

        @testset "JSON converter copies block fields without guessing missing entries" begin
            gen_source = Dict{String,Any}(
                "minReactivePower" => [0.0],
                "maxReactivePower" => [40.0],
                "generationCosts" => [5.0],
                "minActivePower" => [0.0],
                "maxActivePower" => [100.0],
                "carrier" => "CCGT",
                "grid_control_mode" => "gfm",
                "n0" => 1.0,
                "nmax" => 3.0,
                "na0" => 1.0,
                "p_block_min" => [0.0],
                "p_block_max" => [60.0],
                "q_block_min" => [-20.0],
                "q_block_max" => [20.0],
                "b_block" => [0.25],
                "H" => [4.5],
                "s_block" => [60.0],
                "cost_inv_per_mw" => [900.0],
                "lifetime" => 20.0,
                "discount_rate" => [0.05],
                "fixed_om_percent" => [2.0],
                "p_min_pu" => 0.0,
                "p_max_pu" => 1.0,
                "startup_cost_per_mw" => [11.0],
                "shutdown_cost_per_mw" => [7.0],
            )
            gen_target = _FP.JSONConverter.make_gen(gen_source, 1, ["gridModelInputFile", "generators", "G1"], 1, 1; scale_gen=1.0)
            @test gen_target["carrier"] == "CCGT"
            @test gen_target["grid_control_mode"] == "gfm"
            @test gen_target["p_block_max"] == 60.0
            @test gen_target["q_block_min"] == -20.0
            @test gen_target["q_block_max"] == 20.0
            @test gen_target["H"] == 4.5
            @test gen_target["cost_inv_per_mw"] == 900.0
            @test gen_target["lifetime"] == 20.0
            @test gen_target["discount_rate"] == 0.05
            @test gen_target["fixed_om_percent"] == 2.0
            @test gen_target["startup_cost_per_mw"] == 11.0
            @test gen_target["shutdown_cost_per_mw"] == 7.0
            @test !haskey(gen_target, "type")
            @test !haskey(gen_target, "cost_inv_block")
            @test !haskey(gen_target, "startup_block_cost")
            @test !haskey(gen_target, "shutdown_block_cost")

            storage_source = Dict{String,Any}(
                "maxEnergy" => [80.0],
                "maxAbsActivePower" => [20.0],
                "maxInjActivePower" => [20.0],
                "absEfficiency" => [0.95],
                "injEfficiency" => [0.95],
                "minReactivePowerExchange" => [-10.0],
                "maxReactivePowerExchange" => [10.0],
                "selfDischargeRate" => [0.0],
                "carrier" => "BESS-GFL",
                "grid_control_mode" => "gfl",
                "n0" => 0.0,
                "nmax" => 4.0,
                "na0" => 0.0,
                "p_block_max" => [20.0],
                "q_block_min" => [-10.0],
                "q_block_max" => [10.0],
                "e_block" => [80.0],
                "b_block" => [0.0],
                "H" => [3.0],
                "s_block" => [20.0],
                "cost_inv_per_mw" => [1500.0],
                "lifetime" => 15.0,
                "discount_rate" => [0.0],
                "fixed_om_percent" => [0.0],
                "p_min_pu" => 0.0,
                "p_max_pu" => 1.0,
            )
            storage_target = _FP.JSONConverter.make_storage(storage_source, 1, ["gridModelInputFile", "storage", "S1"], 1, 1)
            @test storage_target["carrier"] == "BESS-GFL"
            @test storage_target["grid_control_mode"] == "gfl"
            @test storage_target["e_block"] == 80.0
            @test storage_target["p_block_max"] == 20.0
            @test storage_target["q_block_min"] == -10.0
            @test storage_target["q_block_max"] == 10.0
            @test storage_target["H"] == 3.0
            @test !haskey(storage_target, "p_block_min")
            @test !haskey(storage_target, "type")
            @test !haskey(storage_target, "cost_inv_block")

            target = Dict{String,Any}("gen" => Dict{String,Any}("1" => gen_target), "storage" => Dict{String,Any}(), "ne_storage" => Dict{String,Any}())
            source = Dict{String,Any}("genericParameters" => Dict{String,Any}(
                "operation_weight" => [2.5],
                "uc_gscr_block_cost_convention" => Dict{String,Any}("capex_basis" => "annualized_per_mw_year"),
            ))
            # Converter copy-through only. This is not a canonical scale_data! optimization fixture.
            _FP.JSONConverter.add_uc_gscr_block_schema_fields!(target, source, 1)
            @test target["block_model_schema"] == Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
            @test target["operation_weight"] == 2.5
            @test target["uc_gscr_block_cost_convention"] == Dict{String,Any}("capex_basis" => "annualized_per_mw_year")

            missing_weight_source = Dict{String,Any}("genericParameters" => Dict{String,Any}())
            @test_throws ErrorException _FP.JSONConverter.add_uc_gscr_block_schema_fields!(target, missing_weight_source, 1)

            for field in ("type", "cost_inv_block", "startup_block_cost", "shutdown_block_cost", "activation_policy", "uc_policy", "gscr_exposure_policy")
                old_source = merge(copy(gen_source), Dict{String,Any}(field => field == "type" ? "gfm" : 1.0))
                @test_throws ErrorException _FP.JSONConverter.make_gen(old_source, 1, ["gridModelInputFile", "generators", "G1"], 1, 1; scale_gen=1.0)
            end
        end

        @testset "UC/gSCR block OPEX is annualized by scale_data!" begin
            scale_data = Dict{String,Any}(
                "operation_weight" => 1.0,
                "uc_gscr_block_cost_convention" => Dict{String,Any}("capex_basis" => "annualized_per_mw_year"),
                "gen" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "grid_control_mode" => "gfl",
                        "n0" => 1.0,
                        "nmax" => 2.0,
                        "p_block_max" => 1.0,
                        "startup_cost_per_mw" => 10.0,
                        "shutdown_cost_per_mw" => 5.0,
                        "cost_inv_per_mw" => 0.0,
                        "lifetime" => 20.0,
                        "discount_rate" => 0.0,
                        "fixed_om_percent" => 0.0,
                    ),
                ),
                "storage" => Dict{String,Any}(),
                "ne_storage" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
            )
            _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
            @test scale_data["gen"]["1"]["startup_cost_per_mw"] ≈ 10.0 * 365
            @test scale_data["gen"]["1"]["shutdown_cost_per_mw"] ≈ 5.0 * 365
            @test scale_data["operation_weight"] == 1.0
        end

        function _uc_gscr_block_scale_test_data(; convention=nothing, cost_inv_per_mw=1000.0, lifetime=20.0, discount_rate=0.0, fixed_om_percent=0.0)
            device = Dict{String,Any}(
                "grid_control_mode" => "gfl",
                "n0" => 0.0,
                "nmax" => 2.0,
                "p_block_max" => 1.0,
                "cost_inv_per_mw" => cost_inv_per_mw,
            )
            if !isnothing(lifetime)
                device["lifetime"] = lifetime
            end
            if !isnothing(discount_rate)
                device["discount_rate"] = discount_rate
            end
            if !isnothing(fixed_om_percent)
                device["fixed_om_percent"] = fixed_om_percent
            end
            data = Dict{String,Any}(
                "gen" => Dict{String,Any}(
                    "1" => device,
                ),
                "storage" => Dict{String,Any}(),
                "ne_storage" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
            )
            if !isnothing(convention)
                data["uc_gscr_block_cost_convention"] = Dict{String,Any}("capex_basis" => convention)
            end
            return data
        end

        @testset "UC/gSCR block CAPEX missing basis errors" begin
            scale_data = _uc_gscr_block_scale_test_data()
            err = try
                _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("Missing UC/gSCR block CAPEX basis", sprint(showerror, err))
        end

        @testset "UC/gSCR block overnight CAPEX is annualized by scale_data!" begin
            scale_data = _uc_gscr_block_scale_test_data(; convention="overnight_per_mw")
            _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
            @test scale_data["gen"]["1"]["cost_inv_per_mw"] ≈ 50.0
        end

        @testset "UC/gSCR block CAPEX annuity uses discount rate" begin
            scale_data = _uc_gscr_block_scale_test_data(; convention="overnight_per_mw", discount_rate=0.05)
            _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
            annuity = 0.05 / (1 - (1 + 0.05)^(-20))
            @test scale_data["gen"]["1"]["cost_inv_per_mw"] ≈ 1000.0 * annuity
        end

        @testset "UC/gSCR block CAPEX includes fixed O&M percent" begin
            scale_data = _uc_gscr_block_scale_test_data(; convention="overnight_per_mw", fixed_om_percent=2.0)
            _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
            @test scale_data["gen"]["1"]["cost_inv_per_mw"] ≈ 1000.0 * (1 / 20 + 0.02)
        end

        @testset "UC/gSCR block CAPEX uses explicit case-level assumptions" begin
            scale_data = Dict{String,Any}(
                "uc_gscr_block_cost_convention" => Dict{String,Any}("capex_basis" => "overnight_per_mw"),
                "uc_gscr_block_cost_assumptions" => Dict{String,Any}(
                    "discount_rate" => 0.0,
                    "fixed_om_percent" => 0.0,
                ),
                "gen" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "grid_control_mode" => "gfl",
                        "n0" => 0.0,
                        "nmax" => 2.0,
                        "p_block_max" => 1.0,
                        "cost_inv_per_mw" => 1000.0,
                        "lifetime" => 10.0,
                    ),
                ),
                "storage" => Dict{String,Any}(),
                "ne_storage" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
            )
            _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
            @test scale_data["gen"]["1"]["cost_inv_per_mw"] ≈ 100.0
        end

        @testset "UC/gSCR block CAPEX rejects case-level lifetime" begin
            scale_data = Dict{String,Any}(
                "uc_gscr_block_cost_convention" => Dict{String,Any}("capex_basis" => "overnight_per_mw"),
                "uc_gscr_block_cost_assumptions" => Dict{String,Any}(
                    "lifetime" => 20.0,
                    "discount_rate" => 0.0,
                    "fixed_om_percent" => 0.0,
                ),
                "gen" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "grid_control_mode" => "gfl",
                        "n0" => 0.0,
                        "nmax" => 2.0,
                        "p_block_max" => 1.0,
                        "cost_inv_per_mw" => 1000.0,
                    ),
                ),
                "storage" => Dict{String,Any}(),
                "ne_storage" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
            )
            err = try
                _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("device-level lifetime", sprint(showerror, err))
        end

        @testset "UC/gSCR block CAPEX device discount/FOM override case assumptions" begin
            scale_data = Dict{String,Any}(
                "uc_gscr_block_cost_convention" => Dict{String,Any}("capex_basis" => "overnight_per_mw"),
                "uc_gscr_block_cost_assumptions" => Dict{String,Any}(
                    "discount_rate" => 0.0,
                    "fixed_om_percent" => 0.0,
                ),
                "gen" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "grid_control_mode" => "gfl",
                        "n0" => 0.0,
                        "nmax" => 2.0,
                        "p_block_max" => 1.0,
                        "cost_inv_per_mw" => 1000.0,
                        "lifetime" => 20.0,
                        "discount_rate" => 0.05,
                        "fixed_om_percent" => 2.0,
                    ),
                ),
                "storage" => Dict{String,Any}(),
                "ne_storage" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
            )
            _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
            annuity = 0.05 / (1 - (1 + 0.05)^(-20))
            @test scale_data["gen"]["1"]["cost_inv_per_mw"] ≈ 1000.0 * (annuity + 0.02)
        end

        @testset "UC/gSCR block CAPEX requires explicit discount and FOM" begin
            for missing_field in ("discount_rate", "fixed_om_percent")
                device = Dict{String,Any}(
                    "grid_control_mode" => "gfl",
                    "n0" => 0.0,
                    "nmax" => 2.0,
                    "p_block_max" => 1.0,
                    "cost_inv_per_mw" => 1000.0,
                    "lifetime" => 20.0,
                )
                device[missing_field == "discount_rate" ? "fixed_om_percent" : "discount_rate"] = 0.0
                scale_data = Dict{String,Any}(
                    "uc_gscr_block_cost_convention" => Dict{String,Any}("capex_basis" => "overnight_per_mw"),
                    "gen" => Dict{String,Any}(
                        "1" => device,
                    ),
                    "storage" => Dict{String,Any}(),
                    "ne_storage" => Dict{String,Any}(),
                    "load" => Dict{String,Any}(),
                )
                err = try
                    _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
                    nothing
                catch e
                    e
                end
                @test err isa ErrorException
                @test occursin("$(missing_field) must be set", sprint(showerror, err))
            end
        end

        @testset "UC/gSCR block CAPEX annualization requires lifetime" begin
            scale_data = Dict{String,Any}(
                "uc_gscr_block_cost_convention" => Dict{String,Any}("capex_basis" => "overnight_per_mw"),
                "gen" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "grid_control_mode" => "gfl",
                        "n0" => 0.0,
                        "nmax" => 2.0,
                        "p_block_max" => 1.0,
                        "cost_inv_per_mw" => 1000.0,
                        "discount_rate" => 0.0,
                        "fixed_om_percent" => 0.0,
                    ),
                ),
                "storage" => Dict{String,Any}(),
                "ne_storage" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
            )
            @test_throws ErrorException _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
        end

        @testset "UC/gSCR block annualized CAPEX is not annualized again" begin
            scale_data = _uc_gscr_block_scale_test_data(; convention="annualized_per_mw_year", cost_inv_per_mw=50.0, lifetime=nothing, discount_rate=nothing, fixed_om_percent=nothing)
            _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
            @test scale_data["gen"]["1"]["cost_inv_per_mw"] ≈ 50.0

            scale_data_10y = _uc_gscr_block_scale_test_data(; convention="annualized_per_mw_year", cost_inv_per_mw=50.0, lifetime=nothing, discount_rate=nothing, fixed_om_percent=nothing)
            _FP.scale_data!(scale_data_10y; number_of_hours=24, year_scale_factor=10, number_of_years=1, year_idx=1)
            @test scale_data_10y["gen"]["1"]["cost_inv_per_mw"] ≈ 500.0
        end

        @testset "UC/gSCR block annualized CAPEX ignores provenance fields" begin
            scale_data = _uc_gscr_block_scale_test_data(; convention="annualized_per_mw_year", cost_inv_per_mw=50.0, lifetime=20.0, discount_rate=0.99, fixed_om_percent=99.0)
            _FP.scale_data!(scale_data; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1)
            @test scale_data["gen"]["1"]["cost_inv_per_mw"] ≈ 50.0
        end

        @testset "UC/gSCR block CAPEX keyword basis validates metadata consistency" begin
            conflict = _uc_gscr_block_scale_test_data(; convention="overnight_per_mw")
            @test_throws ErrorException _FP.scale_data!(conflict; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1, uc_gscr_block_capex_basis=:annualized_per_mw_year)

            keyword_only = _uc_gscr_block_scale_test_data(; convention=nothing, cost_inv_per_mw=50.0, lifetime=nothing, discount_rate=nothing, fixed_om_percent=nothing)
            _FP.scale_data!(keyword_only; number_of_hours=24, year_scale_factor=1, number_of_years=1, year_idx=1, uc_gscr_block_capex_basis=:annualized_per_mw_year)
            @test keyword_only["gen"]["1"]["cost_inv_per_mw"] ≈ 50.0
        end

        @testset "UC/gSCR block cost metadata is preserved globally by make_multinetwork" begin
            data = _uc_gscr_block_scale_test_data(; convention="annualized_per_mw_year", cost_inv_per_mw=50.0, lifetime=nothing, discount_rate=nothing, fixed_om_percent=nothing)
            data["block_model_schema"] = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
            data["uc_gscr_block_cost_assumptions"] = Dict{String,Any}("discount_rate" => 0.0, "fixed_om_percent" => 0.0)
            _FP.add_dimension!(data, :hour, 1)
            _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
            _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
            mn_data = _FP.make_multinetwork(data, Dict{String,Any}(); share_data=false)
            @test mn_data["uc_gscr_block_cost_convention"] == Dict{String,Any}("capex_basis" => "annualized_per_mw_year")
            @test mn_data["uc_gscr_block_cost_assumptions"] == Dict{String,Any}("discount_rate" => 0.0, "fixed_om_percent" => 0.0)
            @test !haskey(mn_data["nw"]["1"], "uc_gscr_block_cost_convention")
            @test !haskey(mn_data["nw"]["1"], "uc_gscr_block_cost_assumptions")
        end

        @testset "non-block cost_inv_per_mw remains untouched by scale_data!" begin
            scale_data = Dict{String,Any}(
                "gen" => Dict{String,Any}(),
                "load" => Dict{String,Any}(),
                "ne_storage" => Dict{String,Any}(
                    "1" => Dict{String,Any}(
                        "lifetime" => 10,
                        "eq_cost" => 100.0,
                        "inst_cost" => 20.0,
                        "co2_cost" => 0.0,
                        "cost_inv_per_mw" => 7.5,
                    ),
                ),
            )
            _FP.scale_data!(scale_data; number_of_hours=1, year_scale_factor=1, number_of_years=10, year_idx=1, cost_scale_factor=2.0)
            @test scale_data["ne_storage"]["1"]["eq_cost"] ≈ 200.0
            @test scale_data["ne_storage"]["1"]["inst_cost"] ≈ 40.0
            @test scale_data["ne_storage"]["1"]["cost_inv_per_mw"] == 7.5
        end
    end

end;
