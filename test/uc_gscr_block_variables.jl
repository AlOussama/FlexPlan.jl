"""
    _uc_gscr_block_variable_data(; block=true, hours=2)

Builds a minimal multinetwork fixture for UC/gSCR block variable tests.

The fixture has one generator on a two-bus network and, when `block` is true,
adds the mathematical block fields used by `n_block` and `na_block`. It is
test-only, formulation-independent, and mutates only the local fixture data.
"""
function _uc_gscr_block_variable_data(; block::Bool=true, hours::Int=2)
    gen = Dict{String,Any}(
        "index" => 1,
        "gen_bus" => 1,
        "gen_status" => 1,
        "pmin" => 0.0,
        "pmax" => 10.0,
        "qmin" => -2.0,
        "qmax" => 2.0,
        "vg" => 1.0,
        "mbase" => 1.0,
        "model" => 2,
        "startup" => 0.0,
        "shutdown" => 0.0,
        "ncost" => 2,
        "cost" => [0.0, 0.0],
    )

    if block
        _uc_gscr_add_block_fields!(gen, "gfl"; n0=1, nmax=4, na0=1, p_block_max=10.0, b_block=0.0)
    end

    data = Dict{String,Any}(
        "bus" => Dict{String,Any}(
            "1" => Dict{String,Any}("index" => 1, "bus_i" => 1, "bus_type" => 3, "vmin" => 0.9, "vmax" => 1.1, "va" => 0.0, "vm" => 1.0, "base_kv" => 1.0, "zone" => 1),
            "2" => Dict{String,Any}("index" => 2, "bus_i" => 2, "bus_type" => 1, "vmin" => 0.9, "vmax" => 1.1, "va" => 0.0, "vm" => 1.0, "base_kv" => 1.0, "zone" => 1),
        ),
        "branch" => Dict{String,Any}(),
        "gen" => Dict{String,Any}("1" => gen),
        "load" => Dict{String,Any}(),
        "shunt" => Dict{String,Any}(),
        "storage" => Dict{String,Any}(),
        "switch" => Dict{String,Any}(),
        "dcline" => Dict{String,Any}(),
        "per_unit" => true,
        "operation_weight" => 1.0,
    )
    if block
        data["block_model_schema"] = _uc_gscr_block_schema_v2()
    end

    _FP.add_dimension!(data, :hour, hours)
    return _FP.make_multinetwork(data, Dict{String,Any}())
end

function _uc_gscr_block_variable_test_template()
    return _uc_gscr_common_test_template()
end

"""
    _uc_gscr_block_variable_pm(; block=true, relax=true, hours=2)

Instantiates a minimal PowerModels model and creates UC/gSCR block variables.

The helper validates the block variable equations in tests using DCP reference
data and `ref_add_uc_gscr_block!`. It is test-only and mutates only the model
it creates.
"""
function _uc_gscr_block_variable_pm(; block::Bool=true, relax::Bool=true, hours::Int=2)
    data = _uc_gscr_block_variable_data(; block, hours)
    pm = _PM.instantiate_model(data, _PM.DCPPowerModel, pm -> nothing; ref_extensions=[_FP.ref_add_uc_gscr_block!])
    if block
        _FP.resolve_uc_gscr_block_template!(pm, _uc_gscr_block_variable_test_template())
    end
    for nw in _FP.nw_ids(pm)
        _FP.variable_uc_gscr_block(pm; nw, relax)
    end
    return pm
end

"""
    _add_uc_gscr_block_test_fields!(device, type)

Adds deterministic UC/gSCR block fields to one test device.

The fields define dimensionless installed and active block-count bounds used
by Task 02 tests. This helper is test-only, formulation-independent, and
mutates `device`.
"""
function _add_uc_gscr_block_test_fields!(device, type)
    return _uc_gscr_add_block_fields!(device, type; n0=1, nmax=4, na0=1, p_block_max=10.0, b_block=(type == "gfm" ? 0.5 : 0.0))
end

"""
    _uc_gscr_block_collision_pm(; hours=1)

Builds a model with generator, storage, and candidate storage block devices
sharing numeric id `1`.

The fixture validates that `n_block` and `na_block` use compound keys such as
`(:gen, 1)`, `(:storage, 1)`, and `(:ne_storage, 1)`, so component ids cannot
collide. It is test-only and mutates only the model it creates.
"""
function _uc_gscr_block_collision_pm(; hours::Int=1)
    data = _FP.parse_file(normpath(@__DIR__, "data", "case2", "case2_d_strg.m"))
    _add_uc_gscr_block_test_fields!(data["gen"]["1"], "gfl")
    _add_uc_gscr_block_test_fields!(data["storage"]["1"], "gfm")
    data["storage"]["1"]["e_block"] = 1.0
    _add_uc_gscr_block_test_fields!(data["ne_storage"]["1"], "gfl")
    data["ne_storage"]["1"]["e_block"] = 1.0
    data["block_model_schema"] = _uc_gscr_block_schema_v2()
    data["operation_weight"] = 1.0
    _FP.add_dimension!(data, :hour, hours)

    mn_data = _FP.make_multinetwork(data, Dict{String,Any}())
    pm = _PM.instantiate_model(mn_data, _PM.DCPPowerModel, pm -> nothing; ref_extensions=[_FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!])
    _FP.resolve_uc_gscr_block_template!(pm, _uc_gscr_block_variable_test_template())
    for nw in _FP.nw_ids(pm)
        _FP.variable_uc_gscr_block(pm; nw, relax=true)
    end
    return pm
end

@testset "UC/gSCR block variables" begin
    device_key = (:gen, 1)

    @testset "B1 installed block bounds equation" begin
        pm = _uc_gscr_block_variable_pm(; relax=true)
        n = _PM.var(pm, 1, :n_block, device_key)

        @test JuMP.lower_bound(n) == 1.0
        @test JuMP.upper_bound(n) == 4.0
    end

    @testset "B2 active block bounds equation" begin
        pm = _uc_gscr_block_variable_pm(; relax=true)
        n = _PM.var(pm, 1, :n_block, device_key)
        na = _PM.var(pm, 1, :na_block, device_key)
        con = _PM.con(pm, 1)[:active_blocks_le_installed][device_key]

        @test JuMP.lower_bound(na) == 0.0
        @test !JuMP.has_upper_bound(na)
        @test JuMP.normalized_coefficient(con, na) == 1.0
        @test JuMP.normalized_coefficient(con, n) == -1.0
        @test JuMP.normalized_rhs(con) == 0.0
    end

    @testset "B3 relaxed mode uses continuous variables" begin
        pm = _uc_gscr_block_variable_pm(; relax=true)

        @test !JuMP.is_integer(_PM.var(pm, 1, :n_block, device_key))
        @test !JuMP.is_integer(_PM.var(pm, 1, :na_block, device_key))
    end

    @testset "B4 integer mode uses integer variables" begin
        pm = _uc_gscr_block_variable_pm(; relax=false)

        @test JuMP.is_integer(_PM.var(pm, 1, :n_block, device_key))
        @test JuMP.is_integer(_PM.var(pm, 1, :na_block, device_key))
    end

    @testset "Snapshot sharing rule for installed and active block counts" begin
        pm = _uc_gscr_block_variable_pm(; relax=true, hours=2)

        @test _PM.var(pm, 1, :n_block, device_key) === _PM.var(pm, 2, :n_block, device_key)
        @test _PM.var(pm, 1, :na_block, device_key) !== _PM.var(pm, 2, :na_block, device_key)
    end

    @testset "Report argument populates solution reporting fields" begin
        pm = _uc_gscr_block_variable_pm(; relax=true)

        @test _PM.sol(pm, 1, :gen, 1)[:n_block] === _PM.var(pm, 1, :n_block, device_key)
        @test _PM.sol(pm, 1, :gen, 1)[:na_block] === _PM.var(pm, 1, :na_block, device_key)
        @test _PM.sol(pm, 2, :gen, 1)[:n_block] === _PM.var(pm, 2, :n_block, device_key)
        @test _PM.sol(pm, 2, :gen, 1)[:na_block] === _PM.var(pm, 2, :na_block, device_key)

        @test _FP.variable_installed_blocks(pm; nw=1, relax=true) === _PM.var(pm, 1)[:n_block]
        @test _FP.variable_active_blocks(pm; nw=1, relax=true) === _PM.var(pm, 1)[:na_block]
    end

    @testset "Variable constructors return existing and aliased containers consistently" begin
        data = _uc_gscr_block_variable_data(; block=true, hours=2)
        pm = _PM.instantiate_model(data, _PM.DCPPowerModel, pm -> nothing; ref_extensions=[_FP.ref_add_uc_gscr_block!])
        _FP.resolve_uc_gscr_block_template!(pm, _uc_gscr_block_variable_test_template())

        n_alias = _FP.variable_installed_blocks(pm; nw=2, relax=true, report=false)
        @test n_alias === _PM.var(pm, 2)[:n_block]
        @test n_alias === _PM.var(pm, 1)[:n_block]
        @test _FP.variable_installed_blocks(pm; nw=2, relax=true, report=false) === n_alias

        na = _FP.variable_active_blocks(pm; nw=2, relax=true, report=false)
        @test na === _PM.var(pm, 2)[:na_block]
        @test _FP.variable_active_blocks(pm; nw=2, relax=true, report=false) === na

        no_block_pm = _uc_gscr_block_variable_pm(; block=false, relax=true)
        @test isnothing(_FP.variable_installed_blocks(no_block_pm; nw=1, relax=true))
        @test isnothing(_FP.variable_active_blocks(no_block_pm; nw=1, relax=true))
    end

    @testset "Compound keys keep component ids collision-free" begin
        pm = _uc_gscr_block_collision_pm()

        @test Set(axes(_PM.var(pm, 1)[:n_block], 1)) == Set([(:gen, 1), (:storage, 1), (:ne_storage, 1)])
        @test Set(axes(_PM.var(pm, 1)[:na_block], 1)) == Set([(:gen, 1), (:storage, 1), (:ne_storage, 1)])
        @test _PM.var(pm, 1, :n_block, (:gen, 1)) !== _PM.var(pm, 1, :n_block, (:storage, 1))
        @test _PM.var(pm, 1, :n_block, (:gen, 1)) !== _PM.var(pm, 1, :n_block, (:ne_storage, 1))
        @test _PM.var(pm, 1, :na_block, (:gen, 1)) !== _PM.var(pm, 1, :na_block, (:storage, 1))
        @test _PM.var(pm, 1, :na_block, (:gen, 1)) !== _PM.var(pm, 1, :na_block, (:ne_storage, 1))

        @test _PM.sol(pm, 1, :gen, 1)[:n_block] === _PM.var(pm, 1, :n_block, (:gen, 1))
        @test _PM.sol(pm, 1, :storage, 1)[:n_block] === _PM.var(pm, 1, :n_block, (:storage, 1))
        @test _PM.sol(pm, 1, :ne_storage, 1)[:n_block] === _PM.var(pm, 1, :n_block, (:ne_storage, 1))
    end

    @testset "Installed investment variables are shared while active variables are per snapshot" begin
        pm = _uc_gscr_block_collision_pm(; hours=2)
        component_keys = [(:gen, 1), (:storage, 1), (:ne_storage, 1)]

        @test _PM.var(pm, 1)[:n_block] === _PM.var(pm, 2)[:n_block]
        @test _PM.var(pm, 1)[:na_block] !== _PM.var(pm, 2)[:na_block]
        @test Set(axes(_PM.var(pm, 1)[:n_block], 1)) == Set(component_keys)
        @test Set(axes(_PM.var(pm, 2)[:n_block], 1)) == Set(component_keys)
        @test Set(axes(_PM.var(pm, 1)[:na_block], 1)) == Set(component_keys)
        @test Set(axes(_PM.var(pm, 2)[:na_block], 1)) == Set(component_keys)

        for component_key in component_keys
            n = _PM.var(pm, 1, :n_block, component_key)
            na_1 = _PM.var(pm, 1, :na_block, component_key)
            na_2 = _PM.var(pm, 2, :na_block, component_key)
            con_1 = _PM.con(pm, 1)[:active_blocks_le_installed][component_key]
            con_2 = _PM.con(pm, 2)[:active_blocks_le_installed][component_key]

            @test _PM.var(pm, 2, :n_block, component_key) === n
            @test na_1 !== na_2
            @test JuMP.normalized_coefficient(con_1, na_1) == 1.0
            @test JuMP.normalized_coefficient(con_1, n) == -1.0
            @test JuMP.normalized_rhs(con_1) == 0.0
            @test JuMP.normalized_coefficient(con_2, na_2) == 1.0
            @test JuMP.normalized_coefficient(con_2, n) == -1.0
            @test JuMP.normalized_rhs(con_2) == 0.0
        end

        @test length(unique(JuMP.index(_PM.var(pm, 1, :n_block, component_key)) for component_key in component_keys)) == length(component_keys)
        @test Set(JuMP.index(_PM.var(pm, nw, :n_block, component_key)) for nw in (1, 2) for component_key in component_keys) ==
              Set(JuMP.index(_PM.var(pm, 1, :n_block, component_key)) for component_key in component_keys)
    end

    @testset "G backward compatibility rule for cases without block fields" begin
        pm = _uc_gscr_block_variable_pm(; block=false, relax=true)

        @test !haskey(_PM.var(pm, 1), :n_block)
        @test !haskey(_PM.var(pm, 1), :na_block)
        @test !haskey(_PM.con(pm, 1), :active_blocks_le_installed)
    end

    @testset "R1 solution reporting: report=true populates solution dict for n_block" begin
        pm = _uc_gscr_block_variable_pm(; relax=true, hours=2)

        @test haskey(_PM.sol(pm, 1, :gen, 1), :n_block)
        @test haskey(_PM.sol(pm, 2, :gen, 1), :n_block)
        @test _PM.sol(pm, 1, :gen, 1)[:n_block] === _PM.var(pm, 1, :n_block, device_key)
        @test _PM.sol(pm, 2, :gen, 1)[:n_block] === _PM.var(pm, 2, :n_block, device_key)
    end

    @testset "R2 solution reporting: report=true populates solution dict for na_block" begin
        pm = _uc_gscr_block_variable_pm(; relax=true, hours=2)

        @test haskey(_PM.sol(pm, 1, :gen, 1), :na_block)
        @test haskey(_PM.sol(pm, 2, :gen, 1), :na_block)
        @test _PM.sol(pm, 1, :gen, 1)[:na_block] === _PM.var(pm, 1, :na_block, device_key)
        @test _PM.sol(pm, 2, :gen, 1)[:na_block] === _PM.var(pm, 2, :na_block, device_key)
    end

    @testset "R3 solution reporting: report=false leaves solution dict empty" begin
        data = _uc_gscr_block_variable_data(; block=true, hours=2)
        pm = _PM.instantiate_model(data, _PM.DCPPowerModel, pm -> nothing; ref_extensions=[_FP.ref_add_uc_gscr_block!])
        _FP.resolve_uc_gscr_block_template!(pm, _uc_gscr_block_variable_test_template())
        for nw in _FP.nw_ids(pm)
            _FP.variable_uc_gscr_block(pm; nw, relax=true, report=false)
        end

        @test !haskey(_PM.sol(pm, 1, :gen, 1), :n_block)
        @test !haskey(_PM.sol(pm, 1, :gen, 1), :na_block)
    end
end
