"""
    _uc_gscr_test_ref(nw_ref)

Builds the minimal PowerModels-style reference wrapper used by the UC/gSCR
reference-extension tests.

The helper validates reference-extension wiring rules on deterministic
single-network data. It is test-only and mutates no input data.
"""
function _uc_gscr_test_ref(nw_ref)
    return Dict{Symbol,Any}(
        :it => Dict{Symbol,Any}(
            _PM.pm_it_sym => Dict{Symbol,Any}(
                :nw => Dict{Int,Any}(0 => nw_ref),
            ),
        ),
    )
end

"""
    _uc_gscr_test_device(type, bus; table=:gen, kwargs...)

Builds one synthetic UC/gSCR block device for parser/reference tests.

The fields satisfy the required block schema for the requested `type`, use
per-unit-style numeric values, and place the device at `bus` using the
PowerModels field name for `table`. It is test-only and mutates no data.
"""
function _uc_gscr_test_device(type, bus; kwargs...)
    device = Dict{String,Any}(
        "type" => type,
        "n0" => 1,
        "nmax" => 3,
        "p_block_min" => 0.0,
        "p_block_max" => 10.0,
        "q_block_min" => -2.0,
        "q_block_max" => 2.0,
        "b_block" => type == "gfm" ? 0.5 : 0.0,
    )
    table = get(kwargs, :table, :gen)
    if table == :gen
        device["gen_bus"] = bus
    else
        device["storage_bus"] = bus
    end
    for (key, value) in kwargs
        if key != :table
            device[string(key)] = value
        end
    end
    return device
end

@testset "UC/gSCR block reference extension" begin
    @testset "A1 device type classification and bus mapping rule" begin
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(1 => Dict{String,Any}("index" => 1), 2 => Dict{String,Any}("index" => 2)),
            :gen => Dict{Int,Any}(
                1 => _uc_gscr_test_device("gfl", 1),
                2 => _uc_gscr_test_device("gfm", 2),
            ),
            :storage => Dict{Int,Any}(
                3 => _uc_gscr_test_device("gfl", 2; table=:storage, e_block=40.0),
            ),
            :ne_storage => Dict{Int,Any}(
                4 => _uc_gscr_test_device("gfm", 1; table=:ne_storage, H=5.0, s_block=10.0),
            ),
            :branch => Dict{Int,Any}(),
        )
        ref = _uc_gscr_test_ref(nw_ref)

        _FP.ref_add_uc_gscr_block!(ref, Dict{String,Any}())
        ext = ref[:it][_PM.pm_it_sym][:nw][0]

        @test Set(keys(ext[:gfl_devices])) == Set([(:gen, 1), (:storage, 3)])
        @test Set(keys(ext[:gfm_devices])) == Set([(:gen, 2), (:ne_storage, 4)])
        @test ext[:bus_gfl_devices][1] == [(:gen, 1)]
        @test ext[:bus_gfl_devices][2] == [(:storage, 3)]
        @test ext[:bus_gfm_devices][1] == [(:ne_storage, 4)]
        @test ext[:bus_gfm_devices][2] == [(:gen, 2)]
    end

    @testset "A2 full-network indexing keeps buses without block devices" begin
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1),
                2 => Dict{String,Any}("index" => 2),
                3 => Dict{String,Any}("index" => 3),
            ),
            :gen => Dict{Int,Any}(1 => _uc_gscr_test_device("gfl", 1)),
            :branch => Dict{Int,Any}(),
        )
        ref = _uc_gscr_test_ref(nw_ref)

        _FP.ref_add_uc_gscr_block!(ref, Dict{String,Any}())
        ext = ref[:it][_PM.pm_it_sym][:nw][0]

        @test Set(keys(ext[:bus_gfl_devices])) == Set([1, 2, 3])
        @test Set(keys(ext[:bus_gfm_devices])) == Set([1, 2, 3])
        @test haskey(ext[:gscr_sigma0_gershgorin_margin], 3)
    end

    @testset "A3 susceptance matrix and Gershgorin row metric equation" begin
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1),
                2 => Dict{String,Any}("index" => 2),
                3 => Dict{String,Any}("index" => 3),
            ),
            :gen => Dict{Int,Any}(1 => _uc_gscr_test_device("gfm", 1)),
            :branch => Dict{Int,Any}(
                1 => Dict{String,Any}("f_bus" => 1, "t_bus" => 2, "br_x" => 0.5, "br_status" => 1),
                2 => Dict{String,Any}("f_bus" => 2, "t_bus" => 3, "br_x" => 0.25, "br_status" => 1),
            ),
        )
        ref = _uc_gscr_test_ref(nw_ref)

        _FP.ref_add_uc_gscr_block!(ref, Dict{String,Any}())
        ext = ref[:it][_PM.pm_it_sym][:nw][0]

        @test ext[:gscr_b0][(1, 1)] == 2.0
        @test ext[:gscr_b0][(1, 2)] == -2.0
        @test ext[:gscr_b0][(2, 2)] == 6.0
        @test ext[:gscr_b0][(2, 3)] == -4.0
        @test ext[:gscr_sigma0_gershgorin_margin][1] == 0.0
        @test ext[:gscr_sigma0_gershgorin_margin][2] == 0.0
        @test ext[:gscr_sigma0_raw_rowsum][2] == 0.0
    end

    @testset "G regression rule for cases without block fields" begin
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(1 => Dict{String,Any}("index" => 1)),
            :gen => Dict{Int,Any}(1 => Dict{String,Any}("gen_bus" => 1)),
            :branch => Dict{Int,Any}(),
        )
        ref = _uc_gscr_test_ref(nw_ref)

        _FP.ref_add_uc_gscr_block!(ref, Dict{String,Any}())
        ext = ref[:it][_PM.pm_it_sym][:nw][0]

        @test !haskey(ext, :gfl_devices)
        @test !haskey(ext, :gscr_sigma0_gershgorin_margin)
    end

    @testset "Missing-field validation rule for mathematical block fields" begin
        bad_device = _uc_gscr_test_device("gfl", 1)
        delete!(bad_device, "b_block")
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(1 => Dict{String,Any}("index" => 1)),
            :gen => Dict{Int,Any}(1 => bad_device),
            :branch => Dict{Int,Any}(),
        )
        ref = _uc_gscr_test_ref(nw_ref)

        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(ref, Dict{String,Any}())
    end
end
