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
        "na0" => 1,
        "p_block_min" => 0.0,
        "p_block_max" => 10.0,
        "q_block_min" => -2.0,
        "q_block_max" => 2.0,
        "b_block" => type == "gfm" ? 0.5 : 0.0,
        "startup_block_cost" => 1.0,
        "shutdown_block_cost" => 1.0,
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

    @testset "B_pm DC-flow sign convention and B0_strength mapping on a 2-bus inductive network" begin
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1, "bus_i" => 1, "bus_type" => 3),
                2 => Dict{String,Any}("index" => 2, "bus_i" => 2, "bus_type" => 1),
            ),
            :branch => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1, "f_bus" => 1, "t_bus" => 2, "br_r" => 0.0, "br_x" => 0.5, "br_status" => 1),
            ),
            :gen => Dict{Int,Any}(1 => _uc_gscr_test_device("gfm", 1)),
            :storage => Dict{Int,Any}(),
            :ne_storage => Dict{Int,Any}(),
        )

        basic_data = _FP._uc_gscr_basic_susceptance_data(nw_ref)
        b_pm = _PM.calc_basic_susceptance_matrix(basic_data)
        @test b_pm[1, 1] == -2.0
        @test b_pm[1, 2] == 2.0
        @test b_pm[2, 1] == 2.0
        @test b_pm[2, 2] == -2.0

        b0 = _FP._calc_uc_gscr_susceptance_matrix(nw_ref)
        @test b0[(1, 1)] == 2.0
        @test b0[(1, 2)] == -2.0
        @test b0[(2, 1)] == -2.0
        @test b0[(2, 2)] == 2.0

        _FP._add_uc_gscr_row_metrics!(nw_ref)
        sigma1 = nw_ref[:gscr_sigma0_gershgorin_margin][1]
        sigma2 = nw_ref[:gscr_sigma0_gershgorin_margin][2]
        @test sigma1 == b0[(1, 1)] - abs(b0[(1, 2)])
        @test sigma2 == b0[(2, 2)] - abs(b0[(2, 1)])
    end

    @testset "B0 ignores DC-side tables in mixed AC/DC references" begin
        nw_ref_ac_only = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1, "bus_i" => 1),
                2 => Dict{String,Any}("index" => 2, "bus_i" => 2),
            ),
            :branch => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1, "f_bus" => 1, "t_bus" => 2, "br_x" => 0.5, "br_status" => 1),
            ),
            :gen => Dict{Int,Any}(1 => _uc_gscr_test_device("gfm", 1)),
        )

        nw_ref_mixed = deepcopy(nw_ref_ac_only)
        nw_ref_mixed[:busdc] = Dict{Int,Any}(101 => Dict{String,Any}("index" => 101))
        nw_ref_mixed[:branchdc] = Dict{Int,Any}(
            201 => Dict{String,Any}("index" => 201, "fbusdc" => 101, "tbusdc" => 102),
        )
        nw_ref_mixed[:convdc] = Dict{Int,Any}(
            301 => Dict{String,Any}("index" => 301, "busac_i" => 1, "busdc_i" => 101),
        )

        b0_ac_only = _FP._calc_uc_gscr_susceptance_matrix(nw_ref_ac_only)
        b0_mixed = _FP._calc_uc_gscr_susceptance_matrix(nw_ref_mixed)
        @test b0_mixed == b0_ac_only
    end

    @testset "Disconnected AC graph is allowed and sigma0_G is computed row-wise" begin
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1),
                2 => Dict{String,Any}("index" => 2),
                3 => Dict{String,Any}("index" => 3),
                4 => Dict{String,Any}("index" => 4),
            ),
            :branch => Dict{Int,Any}(
                1 => Dict{String,Any}("f_bus" => 1, "t_bus" => 2, "br_x" => 0.5, "br_status" => 1),
                2 => Dict{String,Any}("f_bus" => 3, "t_bus" => 4, "br_x" => 0.25, "br_status" => 1),
            ),
            :gen => Dict{Int,Any}(1 => _uc_gscr_test_device("gfm", 1)),
        )

        _FP._add_uc_gscr_row_metrics!(nw_ref)
        @test nw_ref[:gscr_sigma0_gershgorin_margin][1] == 0.0
        @test nw_ref[:gscr_sigma0_gershgorin_margin][2] == 0.0
        @test nw_ref[:gscr_sigma0_gershgorin_margin][3] == 0.0
        @test nw_ref[:gscr_sigma0_gershgorin_margin][4] == 0.0
        @test nw_ref[:gscr_sigma0_raw_rowsum][1] == 0.0
        @test nw_ref[:gscr_sigma0_raw_rowsum][4] == 0.0
    end

    @testset "Ambiguous AC-side extraction raises explicit error" begin
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1),
                2 => Dict{String,Any}("index" => 2),
            ),
            :branch => Dict{Int,Any}(
                1 => Dict{String,Any}("f_bus" => 1, "t_bus" => 99, "br_x" => 0.5, "br_status" => 1),
            ),
            :gen => Dict{Int,Any}(1 => _uc_gscr_test_device("gfm", 1)),
        )

        err = try
            _FP._calc_uc_gscr_susceptance_matrix(nw_ref)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("AC-side extraction is ambiguous", sprint(showerror, err))
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

        missing_report = _FP._uc_gscr_missing_required_fields_report(nw_ref)
        @test haskey(missing_report, (:gen, 1))
        @test missing_report[(:gen, 1)] == ["b_block"]
        @test_throws ErrorException _FP.ref_add_uc_gscr_block!(ref, Dict{String,Any}())
    end

    @testset "Stage-required temporal fields remain na0/startup/shutdown only" begin
        device = _uc_gscr_test_device("gfl", 1)
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1),
                2 => Dict{String,Any}("index" => 2),
            ),
            :gen => Dict{Int,Any}(1 => device),
            :branch => Dict{Int,Any}(
                1 => Dict{String,Any}("f_bus" => 1, "t_bus" => 2, "br_x" => 0.5, "br_status" => 1),
            ),
        )
        ref = _uc_gscr_test_ref(nw_ref)

        missing = _FP._uc_gscr_missing_required_fields_report(nw_ref)
        @test isempty(missing)
        _FP.ref_add_uc_gscr_block!(ref, Dict{String,Any}())
        @test haskey(ref[:it][_PM.pm_it_sym][:nw][0], :gfl_devices)
    end

    #=
    Archived (commented-out) min-up/min-down validation tests for a future stage:
    - Minimum up/down fields are conditionally required when enabled
    - Minimum up/down field validation accepts integer snapshots and rejects invalid values
    =#

    @testset "ne_storage with charge_rating < p_block_max warns about rating conflict" begin
        # Validates: _warn_uc_gscr_storage_rating_conflict emits a warn-level message
        # containing "charge_rating" when ne_storage.charge_rating < p_block_max.
        # The standard rating sets a hard variable upper bound (constraint_storage_bounds_ne)
        # that will be binding before the block-scaled bound sc <= p_block_max * na_block.
        ne_device = _uc_gscr_test_device("gfl", 1; table=:ne_storage, e_block=4.0)
        ne_device["charge_rating"] = 0.5   # smaller than p_block_max=10.0
        ne_device["discharge_rating"] = 10.0
        Memento.TestUtils.@test_log(
            Memento.getlogger(_FP), "warn", "charge_rating",
            _FP._warn_uc_gscr_storage_rating_conflict(ne_device, 1, ne_device["p_block_max"], ne_device["nmax"])
        )
    end

    @testset "ne_storage with discharge_rating < p_block_max warns about rating conflict" begin
        # Validates: _warn_uc_gscr_storage_rating_conflict emits a warn-level message
        # containing "discharge_rating" when ne_storage.discharge_rating < p_block_max.
        ne_device = _uc_gscr_test_device("gfl", 1; table=:ne_storage, e_block=4.0)
        ne_device["charge_rating"] = 10.0
        ne_device["discharge_rating"] = 0.3  # smaller than p_block_max=10.0
        Memento.TestUtils.@test_log(
            Memento.getlogger(_FP), "warn", "discharge_rating",
            _FP._warn_uc_gscr_storage_rating_conflict(ne_device, 1, ne_device["p_block_max"], ne_device["nmax"])
        )
    end

    @testset "ne_storage with ratings >= p_block_max emits no warning" begin
        # Validates: no warn-level message for "charge_rating" or "discharge_rating" when
        # both ratings are at or above p_block_max (no conflict present).
        ne_device = _uc_gscr_test_device("gfl", 1; table=:ne_storage, e_block=4.0)
        ne_device["charge_rating"] = 10.0    # equal to p_block_max=10.0
        ne_device["discharge_rating"] = 15.0
        Memento.TestUtils.@test_nolog(
            Memento.getlogger(_FP), "warn", "charge_rating",
            _FP._warn_uc_gscr_storage_rating_conflict(ne_device, 1, ne_device["p_block_max"], ne_device["nmax"])
        )
    end

    @testset "ref_add_uc_gscr_block! triggers rating conflict check for ne_storage" begin
        # Validates: the conflict check is wired into ref_add_uc_gscr_block! via _validate_uc_gscr_block_devices.
        # When charge_rating < p_block_max the full extension must still succeed (warning, not error)
        # and gfl_devices is populated.
        ne_device = _uc_gscr_test_device("gfl", 1; table=:ne_storage, e_block=4.0)
        ne_device["charge_rating"] = 0.5   # triggers warning
        ne_device["discharge_rating"] = 0.5
        nw_ref = Dict{Symbol,Any}(
            :bus => Dict{Int,Any}(
                1 => Dict{String,Any}("index" => 1),
                2 => Dict{String,Any}("index" => 2),
            ),
            :gen => Dict{Int,Any}(),
            :ne_storage => Dict{Int,Any}(1 => ne_device),
            :branch => Dict{Int,Any}(
                1 => Dict{String,Any}("f_bus" => 1, "t_bus" => 2, "br_x" => 0.5, "br_status" => 1),
            ),
        )
        ref = _uc_gscr_test_ref(nw_ref)
        @test_nowarn _FP.ref_add_uc_gscr_block!(ref, Dict{String,Any}())
        @test haskey(ref[:it][_PM.pm_it_sym][:nw][0], :gfl_devices)
    end
end
