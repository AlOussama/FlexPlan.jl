function _schema_v2_ref(nw_ref)
    return Dict{Symbol,Any}(
        :it => Dict{Symbol,Any}(
            _PM.pm_it_sym => Dict{Symbol,Any}(
                :nw => Dict{Int,Any}(1 => nw_ref),
            ),
        ),
    )
end

function _schema_v2_data(; schema=true, name="uc_gscr_block", version="2.0")
    data = Dict{String,Any}()
    if schema
        data["block_model_schema"] = Dict{String,Any}("name" => name, "version" => version)
    end
    return data
end

function _schema_v2_device(; table=:gen, mode="gfl")
    device = Dict{String,Any}(
        "index" => 1,
        "carrier" => "test-carrier",
        "grid_control_mode" => mode,
        "n0" => 1,
        "nmax" => 2,
        "na0" => 1,
        "p_block_max" => 10.0,
        "q_block_min" => -2.0,
        "q_block_max" => 2.0,
        "b_block" => mode == "gfm" ? 1.0 : 0.0,
        "cost_inv_per_mw" => 3.0,
        "p_min_pu" => 0.0,
        "p_max_pu" => 1.0,
    )
    if table == :gen
        device["gen_bus"] = 1
    else
        device["storage_bus"] = 1
        device["e_block"] = 4.0
    end
    return device
end

function _schema_v2_nw_ref(; table=:gen, device=nothing, operation_weight=true)
    if isnothing(device)
        device = _schema_v2_device(; table=table)
    end
    nw_ref = Dict{Symbol,Any}(
        :bus => Dict{Int,Any}(1 => Dict{String,Any}("index" => 1)),
        :branch => Dict{Int,Any}(),
        :gen => Dict{Int,Any}(),
        :storage => Dict{Int,Any}(),
        :ne_storage => Dict{Int,Any}(),
        :time_elapsed => 1.0,
    )
    if operation_weight
        nw_ref[:operation_weight] = 1.0
    end
    nw_ref[table][1] = device
    return nw_ref
end

@testset "UC/gSCR block schema v2 validation" begin
    @testset "valid schema v2 data passes" begin
        nw_ref = _schema_v2_nw_ref()
        ref = _schema_v2_ref(nw_ref)
        _FP.ref_add_uc_gscr_block!(ref, _schema_v2_data())
        ext = ref[:it][_PM.pm_it_sym][:nw][1]
        @test Set(keys(ext[:gfl_devices])) == Set([(:gen, 1)])
        @test isempty(ext[:gfm_devices])
    end

    @testset "missing block_model_schema fails for block data" begin
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref()), _schema_v2_data(; schema=false))
    end

    @testset "wrong schema name or unsupported version fails for block data" begin
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref()), _schema_v2_data(; name="wrong"))
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref()), _schema_v2_data(; version="1.0"))
    end

    @testset "old type fails and grid_control_mode is required" begin
        old = _schema_v2_device()
        old["type"] = "gfl"
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=old)), _schema_v2_data())

        missing = _schema_v2_device()
        delete!(missing, "grid_control_mode")
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=missing)), _schema_v2_data())
    end

    @testset "invalid grid_control_mode fails" begin
        bad = _schema_v2_device(; mode="grid-forming")
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad)), _schema_v2_data())
    end

    @testset "missing carrier fails" begin
        bad = _schema_v2_device()
        delete!(bad, "carrier")
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad)), _schema_v2_data())
    end

    @testset "old startup/shutdown/cost fields fail" begin
        for field in ("startup_block_cost", "shutdown_block_cost", "cost_inv_block")
            bad = _schema_v2_device()
            bad[field] = 1.0
            @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad)), _schema_v2_data())
        end
    end

    @testset "old policy fields fail" begin
        for field in ("activation_policy", "uc_policy", "gscr_exposure_policy")
            bad = _schema_v2_device()
            bad[field] = "policy"
            @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad)), _schema_v2_data())
        end
    end

    @testset "invalid block counts fail" begin
        for (field, value) in (("na0", 2.0), ("n0", 3.0), ("nmax", -1.0))
            bad = _schema_v2_device()
            bad[field] = value
            @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad)), _schema_v2_data())
        end
    end

    @testset "invalid physical scalar fields fail" begin
        for (field, value) in (
            ("p_block_max", "10"),
            ("q_block_min", "bad"),
            ("q_block_max", "bad"),
            ("b_block", "bad"),
            ("cost_inv_per_mw", "bad"),
            ("cost_inv_per_mw", -1.0),
        )
            bad = _schema_v2_device()
            bad[field] = value
            @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad)), _schema_v2_data())
        end

        bad_q = _schema_v2_device()
        bad_q["q_block_min"] = 3.0
        bad_q["q_block_max"] = 2.0
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad_q)), _schema_v2_data())

        bad_expandable = _schema_v2_device()
        bad_expandable["p_block_max"] = 0.0
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad_expandable)), _schema_v2_data())
    end

    @testset "active-power per-unit bounds validation" begin
        bad_scalar = _schema_v2_device()
        bad_scalar["p_min_pu"] = 0.7
        bad_scalar["p_max_pu"] = 0.6
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad_scalar)), _schema_v2_data())

        bad_negative = _schema_v2_device()
        bad_negative["p_min_pu"] = [-0.1, 0.0]
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad_negative)), _schema_v2_data())

        bad_vector = _schema_v2_device()
        bad_vector["p_min_pu"] = [0.2, 0.9]
        bad_vector["p_max_pu"] = [0.8, 0.7]
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad_vector)), _schema_v2_data())

        bad_dict = _schema_v2_device()
        bad_dict["p_min_pu"] = Dict(1 => 0.2, 2 => 0.9)
        bad_dict["p_max_pu"] = Dict(2 => 0.7)
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad_dict)), _schema_v2_data())

        bad_type = _schema_v2_device()
        bad_type["p_max_pu"] = [1.0, "bad"]
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=bad_type)), _schema_v2_data())

        partial = _schema_v2_device()
        partial["p_min_pu"] = [0.1]
        partial["p_max_pu"] = [0.9, 0.8]
        _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=partial)), _schema_v2_data())

        partial_dict = _schema_v2_device()
        partial_dict["p_min_pu"] = Dict(1 => 0.1)
        partial_dict["p_max_pu"] = Dict(2 => 0.8)
        _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; device=partial_dict)), _schema_v2_data())
    end

    @testset "missing operation_weight on a snapshot fails for block data" begin
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; operation_weight=false)), _schema_v2_data())
    end

    @testset "storage block device missing e_block fails" begin
        for table in (:storage, :ne_storage)
            bad = _schema_v2_device(; table=table, mode="gfm")
            delete!(bad, "e_block")
            @test_throws ErrorException _FP.ref_add_uc_gscr_block!(_schema_v2_ref(_schema_v2_nw_ref(; table=table, device=bad)), _schema_v2_data())
        end
    end

    @testset "no-block legacy cases remain backward compatible" begin
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(1 => Dict{String,Any}("index" => 1)),
            :branch => Dict{Int,Any}(),
            :gen => Dict{Int,Any}(1 => Dict{String,Any}("gen_bus" => 1)),
        )
        ref = _schema_v2_ref(nw_ref)
        _FP.ref_add_uc_gscr_block!(ref, Dict{String,Any}())
        @test !haskey(ref[:it][_PM.pm_it_sym][:nw][1], :gfl_devices)
    end
end
