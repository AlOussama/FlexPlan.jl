function _uc_gscr_template_gen(id; carrier="CCGT", mode="gfl", startup=true)
    return _uc_gscr_minimal_gen(id; carrier, mode, startup)
end

function _uc_gscr_template_data(; carriers=["CCGT"], startup=true, g_min=nothing)
    gens = Dict{String,Any}()
    for (offset, carrier) in enumerate(carriers)
        id = offset
        mode = carrier == "BESS-GFM" ? "gfm" : "gfl"
        gens[string(id)] = _uc_gscr_template_gen(id; carrier, mode, startup)
    end

    data = Dict{String,Any}(
        "bus" => Dict{String,Any}("1" => Dict{String,Any}("index" => 1, "bus_i" => 1, "bus_type" => 3, "vmin" => 0.9, "vmax" => 1.1, "va" => 0.0, "vm" => 1.0, "base_kv" => 1.0, "zone" => 1)),
        "branch" => Dict{String,Any}(),
        "gen" => gens,
        "load" => Dict{String,Any}(),
        "shunt" => Dict{String,Any}(),
        "storage" => Dict{String,Any}(),
        "switch" => Dict{String,Any}(),
        "dcline" => Dict{String,Any}(),
        "per_unit" => true,
        "operation_weight" => 1.0,
        "time_elapsed" => 1.0,
        "block_model_schema" => _uc_gscr_block_schema_v2(),
    )
    if !isnothing(g_min)
        data["g_min"] = g_min
    end
    _FP.add_dimension!(data, :hour, 1)
    return _FP.make_multinetwork(data, Dict{String,Any}())
end

function _uc_gscr_template_pm(; carriers=["CCGT"], startup=true, g_min=nothing)
    data = _uc_gscr_template_data(; carriers, startup, g_min)
    return _PM.instantiate_model(data, _PM.DCPPowerModel, pm -> nothing; ref_extensions=[_FP.ref_add_uc_gscr_block!])
end

struct _UnsupportedTemplateGSCR <: _FP.AbstractGSCRFormulation end

@testset "UC/gSCR block model template" begin
    @testset "template type construction" begin
        base = _FP.UCGSCRBlockTemplate(Dict((:gen, "CCGT") => _FP.BlockThermalCommitment()), _FP.NoGSCR())
        gscr = _FP.UCGSCRBlockTemplate(Dict((:gen, "CCGT") => _FP.BlockThermalCommitment()), _FP.GershgorinGSCR(_FP.OnlineNameplateExposure()))
        default_gscr = _FP.GershgorinGSCR()

        @test _FP.BlockThermalCommitment() isa _FP.AbstractBlockDeviceFormulation
        @test _FP.BlockRenewableParticipation() isa _FP.AbstractBlockDeviceFormulation
        @test _FP.BlockFixedInstalled() isa _FP.AbstractBlockDeviceFormulation
        @test _FP.BlockStorageParticipation() isa _FP.AbstractBlockDeviceFormulation
        @test _FP.NoGSCR() isa _FP.AbstractGSCRFormulation
        @test _FP.OnlineNameplateExposure() isa _FP.AbstractGSCRExposure
        @test base.gscr_formulation isa _FP.NoGSCR
        @test gscr.gscr_formulation isa _FP.GershgorinGSCR
        @test gscr.gscr_formulation.exposure isa _FP.OnlineNameplateExposure
        @test default_gscr.exposure isa _FP.OnlineNameplateExposure
    end

    @testset "mapping by table and carrier resolves all block-enabled devices" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT", "wind", "BESS-GFL"])
        template = _FP.UCGSCRBlockTemplate(Dict(
            (:gen, "CCGT") => _FP.BlockThermalCommitment(),
            (:gen, "wind") => _FP.BlockRenewableParticipation(),
            (:gen, "BESS-GFL") => _FP.BlockFixedInstalled(),
        ))

        resolved = _FP.resolve_uc_gscr_block_template!(pm, template)
        @test resolved[1][(:gen, 1)] isa _FP.BlockThermalCommitment
        @test resolved[1][(:gen, 2)] isa _FP.BlockRenewableParticipation
        @test resolved[1][(:gen, 3)] isa _FP.BlockFixedInstalled
    end

    @testset "exact device override takes precedence" begin
        pm = _uc_gscr_template_pm(; carriers=["wind"])
        template = _FP.UCGSCRBlockTemplate(
            Dict((:gen, "wind") => _FP.BlockRenewableParticipation());
            device_formulations=Dict((:gen, 1) => _FP.BlockFixedInstalled()),
        )

        resolved = _FP.resolve_uc_gscr_block_template!(pm, template)
        @test resolved[1][(:gen, 1)] isa _FP.BlockFixedInstalled
    end

    @testset "missing mapping for block-enabled device fails" begin
        pm = _uc_gscr_template_pm(; carriers=["biomass"])
        template = _FP.UCGSCRBlockTemplate(Dict((:gen, "CCGT") => _FP.BlockThermalCommitment()))

        @test_throws ErrorException _FP.resolve_uc_gscr_block_template!(pm, template)
    end

    @testset "matching is table-specific without carrier-only fallback" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT"])
        template = _FP.UCGSCRBlockTemplate(Dict((:storage, "CCGT") => _FP.BlockFixedInstalled()))

        @test_throws ErrorException _FP.resolve_uc_gscr_block_template!(pm, template)
    end

    @testset "nonexistent exact override fails" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT"])
        template = _FP.UCGSCRBlockTemplate(
            Dict((:gen, "CCGT") => _FP.BlockThermalCommitment());
            device_formulations=Dict((:gen, 99) => _FP.BlockFixedInstalled()),
        )

        @test_throws ErrorException _FP.resolve_uc_gscr_block_template!(pm, template)
    end

    @testset "unsupported carrier-assignment table fails" begin
        @test_throws ErrorException _FP.UCGSCRBlockTemplate(Dict((:load, "CCGT") => _FP.BlockThermalCommitment()))
    end

    @testset "unsupported device-override table fails" begin
        @test_throws ErrorException _FP.UCGSCRBlockTemplate(
            Dict((:gen, "CCGT") => _FP.BlockThermalCommitment());
            device_formulations=Dict((:load, 1) => _FP.BlockFixedInstalled()),
        )
    end

    @testset "thermal commitment requires startup and shutdown costs" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT"], startup=false)
        template = _FP.UCGSCRBlockTemplate(Dict((:gen, "CCGT") => _FP.BlockThermalCommitment()))

        @test_throws ErrorException _FP.resolve_uc_gscr_block_template!(pm, template)
    end

    @testset "renewable participation does not require startup and shutdown costs" begin
        pm = _uc_gscr_template_pm(; carriers=["wind"], startup=false)
        template = _FP.UCGSCRBlockTemplate(Dict((:gen, "wind") => _FP.BlockRenewableParticipation()))

        resolved = _FP.resolve_uc_gscr_block_template!(pm, template)
        @test resolved[1][(:gen, 1)] isa _FP.BlockRenewableParticipation
    end

    @testset "fixed installed does not require startup and shutdown costs" begin
        pm = _uc_gscr_template_pm(; carriers=["BESS-GFL"], startup=false)
        template = _FP.UCGSCRBlockTemplate(Dict((:gen, "BESS-GFL") => _FP.BlockFixedInstalled()))

        resolved = _FP.resolve_uc_gscr_block_template!(pm, template)
        @test resolved[1][(:gen, 1)] isa _FP.BlockFixedInstalled
    end

    @testset "GershgorinGSCR requires g_min" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT"])
        template = _FP.UCGSCRBlockTemplate(Dict((:gen, "CCGT") => _FP.BlockThermalCommitment()), _FP.GershgorinGSCR(_FP.OnlineNameplateExposure()))

        @test_throws ErrorException _FP.resolve_uc_gscr_block_template!(pm, template)
    end

    @testset "GershgorinGSCR validates against physical GFL and GFM maps" begin
        pm = _uc_gscr_template_pm(; carriers=["wind", "BESS-GFM"], g_min=1.0)
        template = _FP.UCGSCRBlockTemplate(
            Dict(
                (:gen, "wind") => _FP.BlockRenewableParticipation(),
                (:gen, "BESS-GFM") => _FP.BlockFixedInstalled(),
            ),
            _FP.GershgorinGSCR(),
        )

        resolved = _FP.resolve_uc_gscr_block_template!(pm, template)
        @test resolved[1][(:gen, 1)] isa _FP.BlockRenewableParticipation
        @test resolved[1][(:gen, 2)] isa _FP.BlockFixedInstalled
        @test haskey(_PM.ref(pm, 1, :gfl_devices), (:gen, 1))
        @test haskey(_PM.ref(pm, 1, :gfm_devices), (:gen, 2))
    end

    @testset "NoGSCR does not require g_min" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT"])
        template = _FP.UCGSCRBlockTemplate(Dict((:gen, "CCGT") => _FP.BlockThermalCommitment()), _FP.NoGSCR())

        resolved = _FP.resolve_uc_gscr_block_template!(pm, template)
        @test resolved[1][(:gen, 1)] isa _FP.BlockThermalCommitment
        @test _FP._uc_gscr_block_gscr_formulation(pm, 1) isa _FP.NoGSCR
        @test !_FP._uc_gscr_block_requires_gscr_constraints(pm, 1)
    end

    @testset "GershgorinGSCR is selected from resolved template" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT"], g_min=1.0)
        template = _FP.UCGSCRBlockTemplate(Dict((:gen, "CCGT") => _FP.BlockThermalCommitment()), _FP.GershgorinGSCR())

        _FP.resolve_uc_gscr_block_template!(pm, template)
        @test _FP._uc_gscr_block_gscr_formulation(pm, 1) isa _FP.GershgorinGSCR
        @test _FP._uc_gscr_block_requires_gscr_constraints(pm, 1)
    end

    @testset "unsupported gSCR formulation fails with clear error" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT"])
        template = _FP.UCGSCRBlockTemplate(Dict((:gen, "CCGT") => _FP.BlockThermalCommitment()), _UnsupportedTemplateGSCR())

        err = try
            _FP.resolve_uc_gscr_block_template!(pm, template)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("Unsupported UC/gSCR block template gSCR formulation", sprint(showerror, err))
    end

    @testset "resolved device sets are cached in pm.ext" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT", "wind", "BESS-GFL"])
        template = _FP.UCGSCRBlockTemplate(Dict(
            (:gen, "CCGT") => _FP.BlockThermalCommitment(),
            (:gen, "wind") => _FP.BlockRenewableParticipation(),
            (:gen, "BESS-GFL") => _FP.BlockFixedInstalled(),
        ))

        _FP.resolve_uc_gscr_block_template!(pm, template)
        sets = pm.ext[:uc_gscr_block_device_sets]
        @test pm.ext[:uc_gscr_block_template] === template
        @test haskey(pm.ext, :uc_gscr_block_formulations)
        @test pm.ext[:uc_gscr_block_gscr_formulation] isa _FP.NoGSCR
        @test haskey(pm.ext, :uc_gscr_block_device_sets)
        @test Set(sets[:all]) == Set([(:gen, 1), (:gen, 2), (:gen, 3)])
        @test sets[:thermal_commitment] == [(:gen, 1)]
        @test sets[:renewable_participation] == [(:gen, 2)]
        @test sets[:fixed_installed] == [(:gen, 3)]
        @test sets[:startup_shutdown] == [(:gen, 1)]
        @test isempty(sets[:storage_participation])
    end

    @testset "policy fields are not introduced into device data" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT"])
        template = _FP.UCGSCRBlockTemplate(Dict((:gen, "CCGT") => _FP.BlockThermalCommitment()))
        _FP.resolve_uc_gscr_block_template!(pm, template)

        device = _PM.ref(pm, 1, :gen, 1)
        for field in ("activation_policy", "uc_policy", "gscr_exposure_policy")
            @test !haskey(device, field)
        end
    end

    @testset "BlockStorageParticipation is only present when assigned" begin
        pm = _uc_gscr_template_pm(; carriers=["CCGT"])
        template = _FP.UCGSCRBlockTemplate(
            Dict((:gen, "CCGT") => _FP.BlockThermalCommitment());
            device_formulations=Dict((:gen, 1) => _FP.BlockStorageParticipation()),
        )

        _FP.resolve_uc_gscr_block_template!(pm, template)
        sets = pm.ext[:uc_gscr_block_device_sets]
        @test isempty(sets[:thermal_commitment])
        @test isempty(sets[:startup_shutdown])
        @test sets[:storage_participation] == [(:gen, 1)]
    end
end
