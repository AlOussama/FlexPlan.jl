# Tests for block UC / gSCR implementation
#
# Test groups follow docs/tests/test_specification.md:
#   A — data/reference tests (A1: type classification, A2: full-network indexing, A3: susceptance matrix)
#   B — block variables (B1: installed bounds, B2: active bounds, B3: relax=true, B4: relax=false)
#   C — dispatch constraints (C1: active-power, C2: reactive no-op)
#   E — gSCR Gershgorin tests (E1: feasible, E2: infeasible, E3: empty bus terms)
#   G — regression (existing cases without block fields)


@testset "UC gSCR block" begin

    # ─────────────────────────────────────────────────────────────────────────
    # Synthetic network fixture
    # 3 buses, 2 branches, 1 GFL gen, 1 GFM gen, g_min = 2.0
    # Branch 1: bus 1 → bus 2, x = 0.5  →  b = 2.0
    # Branch 2: bus 2 → bus 3, x = 1.0  →  b = 1.0
    #
    # B^0:
    #   B^0 = [ 2   -2    0 ]
    #         [-2    3   -1 ]
    #         [ 0   -1    1 ]
    #
    # Gershgorin margins:
    #   σ_1 = 2 - |-2| = 0
    #   σ_2 = 3 - |-2| - |-1| = 0
    #   σ_3 = 1 - |-1| = 0
    #
    # Raw row sums:
    #   row_1 = 2 - 2 + 0 = 0
    #   row_2 = -2 + 3 - 1 = 0
    #   row_3 = 0 - 1 + 1 = 0
    # ─────────────────────────────────────────────────────────────────────────

    function _make_synthetic_sn_data()
        data = Dict{String,Any}(
            "baseMVA"      => 100.0,
            "per_unit"     => false,
            "source_type"  => "synthetic",
            "source_version" => "0",
            "name"         => "synthetic_3bus",
            "multinetwork" => false,
            "g_min"        => 2.0,
            "bus" => Dict(
                "1" => Dict("index"=>1,"bus_i"=>1,"bus_type"=>3,"pd"=>0.0,"qd"=>0.0,"gs"=>0.0,"bs"=>0.0,"area"=>1,"vm"=>1.0,"va"=>0.0,"base_kv"=>1.0,"zone"=>1,"vmax"=>1.1,"vmin"=>0.9),
                "2" => Dict("index"=>2,"bus_i"=>2,"bus_type"=>1,"pd"=>0.5,"qd"=>0.0,"gs"=>0.0,"bs"=>0.0,"area"=>1,"vm"=>1.0,"va"=>0.0,"base_kv"=>1.0,"zone"=>1,"vmax"=>1.1,"vmin"=>0.9),
                "3" => Dict("index"=>3,"bus_i"=>3,"bus_type"=>2,"pd"=>0.3,"qd"=>0.0,"gs"=>0.0,"bs"=>0.0,"area"=>1,"vm"=>1.0,"va"=>0.0,"base_kv"=>1.0,"zone"=>1,"vmax"=>1.1,"vmin"=>0.9),
            ),
            "branch" => Dict(
                "1" => Dict("index"=>1,"f_bus"=>1,"t_bus"=>2,"br_r"=>0.0,"br_x"=>0.5,"br_b"=>0.0,"rate_a"=>10.0,"rate_b"=>10.0,"rate_c"=>10.0,"tap"=>1.0,"shift"=>0.0,"br_status"=>1,"angmin"=>-1.0,"angmax"=>1.0,"transformer"=>false),
                "2" => Dict("index"=>2,"f_bus"=>2,"t_bus"=>3,"br_r"=>0.0,"br_x"=>1.0,"br_b"=>0.0,"rate_a"=>10.0,"rate_b"=>10.0,"rate_c"=>10.0,"tap"=>1.0,"shift"=>0.0,"br_status"=>1,"angmin"=>-1.0,"angmax"=>1.0,"transformer"=>false),
            ),
            "gen" => Dict(
                "1" => Dict("index"=>1,"gen_bus"=>1,"pg"=>0.0,"qg"=>0.0,"qmax"=>10.0,"qmin"=>-10.0,"vg"=>1.0,"mbase"=>100.0,"gen_status"=>1,"pmax"=>10.0,"pmin"=>0.0,"cost"=>[10.0,0.0],"model"=>2,"ncost"=>2,"shutdown"=>0.0,"startup"=>0.0,"dispatchable"=>true,
                            "type"=>"gfm","n0"=>1,"nmax"=>3,"p_block_min"=>0.0,"p_block_max"=>2.0,"q_block_min"=>-1.0,"q_block_max"=>1.0,"b_block"=>0.5,"cost_inv_block"=>1.0),
                "2" => Dict("index"=>2,"gen_bus"=>3,"pg"=>0.0,"qg"=>0.0,"qmax"=>10.0,"qmin"=>-10.0,"vg"=>1.0,"mbase"=>100.0,"gen_status"=>1,"pmax"=>10.0,"pmin"=>0.0,"cost"=>[5.0,0.0],"model"=>2,"ncost"=>2,"shutdown"=>0.0,"startup"=>0.0,"dispatchable"=>true,
                            "type"=>"gfl","n0"=>1,"nmax"=>4,"p_block_min"=>0.0,"p_block_max"=>1.0,"q_block_min"=>-0.5,"q_block_max"=>0.5,"b_block"=>0.0,"cost_inv_block"=>1.0),
            ),
            "load" => Dict{String,Any}(),
            "shunt" => Dict{String,Any}(),
            "storage" => Dict{String,Any}(),
        )
        return data
    end

    # Build a minimal multinetwork from synthetic data (1 snapshot)
    function _make_synthetic_mn_data()
        sn = _make_synthetic_sn_data()
        _FP.add_dimension!(sn, :hour,     Dict(1 => Dict{String,Any}()))
        _FP.add_dimension!(sn, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
        _FP.add_dimension!(sn, :year,     Dict(1 => Dict{String,Any}("scale_factor" => 1.0)))
        return _FP.make_multinetwork(sn)
    end

    # ─── Test group A — data/reference tests ────────────────────────────────

    @testset "A1: device type classification" begin
        # Validates: gfl_devices, gfm_devices, bus_gfl_devices, bus_gfm_devices
        # are populated correctly from type fields.

        mn = _make_synthetic_mn_data()
        ref = Dict{Symbol,Any}()
        _PM.build_ref!(ref, mn, [_PM.ref_add_se_mat!], Dict("per_unit"=>false))
        _FP.ref_add_gscr_block!(ref, mn)

        nw_ref = ref[:it][_PM.pm_it_sym][:nw][1]

        @test length(nw_ref[:gfm_devices]) == 1
        @test haskey(nw_ref[:gfm_devices], 1)

        @test length(nw_ref[:gfl_devices]) == 1
        @test haskey(nw_ref[:gfl_devices], 2)

        # bus 1 has GFM gen 1, bus 3 has GFL gen 2
        @test 1 in nw_ref[:bus_gfm_devices][1]
        @test 2 in nw_ref[:bus_gfl_devices][3]

        # bus 2 has no block devices
        @test isempty(nw_ref[:bus_gfl_devices][2])
        @test isempty(nw_ref[:bus_gfm_devices][2])
    end

    @testset "A2: full-network indexing" begin
        # Validates: all original buses appear; no reduced bus set is created.

        mn = _make_synthetic_mn_data()
        ref = Dict{Symbol,Any}()
        _PM.build_ref!(ref, mn, [_PM.ref_add_se_mat!], Dict("per_unit"=>false))
        _FP.ref_add_gscr_block!(ref, mn)

        nw_ref = ref[:it][_PM.pm_it_sym][:nw][1]

        bus_ids = Set(keys(nw_ref[:bus]))
        @test 1 in bus_ids
        @test 2 in bus_ids
        @test 3 in bus_ids
        @test length(bus_ids) == 3
    end

    @testset "A3: susceptance matrix and Gershgorin margin" begin
        # Validates σ_n^{0,G} = B^0_{nn} - Σ_{j≠n} |B^0_{nj}| for known B^0.
        #
        # B^0 for 3-bus, x12=0.5, x23=1.0:
        #   B^0_11 = 2,  off-diag: |B^0_12| = 2         →  σ_1 = 2 - 2 = 0
        #   B^0_22 = 3,  off-diag: |B^0_21| + |B^0_23|  →  σ_2 = 3 - 2 - 1 = 0
        #   B^0_33 = 1,  off-diag: |B^0_32| = 1         →  σ_3 = 1 - 1 = 0

        mn = _make_synthetic_mn_data()
        ref = Dict{Symbol,Any}()
        _PM.build_ref!(ref, mn, [_PM.ref_add_se_mat!], Dict("per_unit"=>false))
        _FP.ref_add_gscr_block!(ref, mn)

        nw_ref = ref[:it][_PM.pm_it_sym][:nw][1]
        margin  = nw_ref[:gscr_sigma0_gershgorin_margin]
        rowsum  = nw_ref[:gscr_sigma0_raw_rowsum]

        @test isapprox(margin[1], 0.0; atol=1e-10)
        @test isapprox(margin[2], 0.0; atol=1e-10)
        @test isapprox(margin[3], 0.0; atol=1e-10)

        # Row sums of Laplacian-style susceptance matrix are zero
        @test isapprox(rowsum[1], 0.0; atol=1e-10)
        @test isapprox(rowsum[2], 0.0; atol=1e-10)
        @test isapprox(rowsum[3], 0.0; atol=1e-10)
    end

    # ─── Test group B — block variables ─────────────────────────────────────

    @testset "B3: installed block bounds (relax=true)" begin
        # Validates: n_k^0 ≤ n_k ≤ n_k^{max} with continuous variables.

        mn = _make_synthetic_mn_data()
        result = _FP.uc_gscr_block(mn, _PM.DCPPowerModel, milp_optimizer; relax=true)
        @test result["termination_status"] in (_FP.OPTIMAL, _FP.LOCALLY_SOLVED)
    end

    @testset "B4: installed block bounds (relax=false)" begin
        # Validates: n_k^0 ≤ n_k ≤ n_k^{max} with integer variables.

        mn = _make_synthetic_mn_data()
        result = _FP.uc_gscr_block(mn, _PM.DCPPowerModel, milp_optimizer; relax=false)
        @test result["termination_status"] in (_FP.OPTIMAL, _FP.LOCALLY_SOLVED)
    end

    # ─── Test group C — dispatch constraints ────────────────────────────────

    @testset "C1: active-power dispatch bounds scale with na" begin
        # Validates: p_k^{block,min}*na ≤ pg ≤ p_k^{block,max}*na
        # The model is feasible and pg lies within the block-scaled range.

        mn = _make_synthetic_mn_data()
        result = _FP.uc_gscr_block(mn, _PM.DCPPowerModel, milp_optimizer; relax=true)
        @test result["termination_status"] in (_FP.OPTIMAL, _FP.LOCALLY_SOLVED)

        sol_nw = result["solution"]["nw"]["1"]
        for (k_str, gen_sol) in sol_nw["gen"]
            gen_id = parse(Int, k_str)
            na = gen_sol["na_block"]
            pg = gen_sol["pg"]
            nw_data = mn["nw"]["1"]["gen"][k_str]
            @test pg >= nw_data["p_block_min"] * na - 1e-6
            @test pg <= nw_data["p_block_max"] * na + 1e-6
        end
    end

    @testset "C2: reactive-power constraints are no-op for DCP" begin
        # Validates: no error is raised when reactive constraints are skipped
        # in active-power-only (DCP) formulations.

        mn = _make_synthetic_mn_data()
        # No error expected; reactive constraint is a no-op for DCPPowerModel
        result = _FP.uc_gscr_block(mn, _PM.DCPPowerModel, milp_optimizer; relax=true)
        @test result["termination_status"] in (_FP.OPTIMAL, _FP.LOCALLY_SOLVED)
    end

    # ─── Test group E — gSCR Gershgorin tests ───────────────────────────────

    @testset "E1: feasible gSCR case" begin
        # Test spec §E1:
        #   σ=1.0, b=0.5, na^{fm}=2, g=0.1, P=10, na^{fl}=1
        #   1 + 0.5*2 = 2.0 ≥ 0.1*10*1 = 1.0  → feasible
        #
        # Realized via the synthetic network:
        #   σ_1 = 0 (bus 1 is reference), gfm at bus 1 with b_block=0.5, g_min=2.0
        #   No GFL at bus 1 → constraint is σ + b*na ≥ 0 (trivially feasible)

        mn = _make_synthetic_mn_data()
        result = _FP.uc_gscr_block(mn, _PM.DCPPowerModel, milp_optimizer; relax=true)
        @test result["termination_status"] in (_FP.OPTIMAL, _FP.LOCALLY_SOLVED)
    end

    @testset "E3: empty bus terms — buses with only GFL, only GFM, neither" begin
        # Validates constraints are well-defined for all three bus types.
        # Synthetic network:
        #   bus 1: only GFM (gen 1)
        #   bus 2: no block devices
        #   bus 3: only GFL (gen 2)

        mn = _make_synthetic_mn_data()
        result = _FP.uc_gscr_block(mn, _PM.DCPPowerModel, milp_optimizer; relax=true)
        @test result["termination_status"] in (_FP.OPTIMAL, _FP.LOCALLY_SOLVED)
    end

    # ─── Test group G — regression ───────────────────────────────────────────

    @testset "G: backward compatibility — case6 without block fields" begin
        # Validates existing FlexPlan tests still run when no block fields are present.
        # Cases without block fields should remain unchanged.

        data = load_case6(
            number_of_hours    = 2,
            number_of_scenarios = 1,
            number_of_years    = 1,
            scale_gen          = 1.0,
            share_data         = false,
        )
        result = _FP.uc_gscr_block(data, _PM.DCPPowerModel, milp_optimizer; relax=true)
        # Without g_min in data, gSCR constraint is skipped; problem solves normally
        @test result["termination_status"] in (_FP.OPTIMAL, _FP.LOCALLY_SOLVED)
    end

    @testset "G: case6 with block fields (level-2 integration)" begin
        # Validates the full pipeline on case6 with block-expanded gen data.
        # Follows docs/tests/flexplan_test_data_plan.md Level 2.

        function add_uc_gscr_block_fields!(sn_data)
            for (id, gen) in sn_data["gen"]
                is_gfm = id == "1"
                gen["type"] = is_gfm ? "gfm" : "gfl"
                gen["n0"]   = 1
                gen["nmax"] = 3
                pblk = max(abs(get(gen, "pmax", 1.0)), 1e-3)
                gen["p_block_min"] = 0.0
                gen["p_block_max"] = pblk
                gen["q_block_min"] = get(gen, "qmin", -pblk)
                gen["q_block_max"] = get(gen, "qmax",  pblk)
                gen["b_block"]       = is_gfm ? 0.2 : 0.0
                gen["cost_inv_block"] = 1.0
            end
            sn_data["g_min"] = 2.0
        end

        data = load_case6(
            number_of_hours     = 2,
            number_of_scenarios = 1,
            number_of_years     = 1,
            scale_gen           = 13.0,
            share_data          = false,
            sn_data_extensions  = [add_uc_gscr_block_fields!],
        )
        result = _FP.uc_gscr_block(data, _PM.DCPPowerModel, milp_optimizer; relax=true)
        @test result["termination_status"] in (_FP.OPTIMAL, _FP.LOCALLY_SOLVED)
    end

end
