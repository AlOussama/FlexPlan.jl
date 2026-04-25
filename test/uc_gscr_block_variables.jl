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
        merge!(gen, Dict{String,Any}(
            "type" => "gfl",
            "n0" => 1,
            "nmax" => 4,
            "p_block_min" => 0.0,
            "p_block_max" => 10.0,
            "q_block_min" => -2.0,
            "q_block_max" => 2.0,
            "b_block" => 0.0,
        ))
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
    )

    _FP.add_dimension!(data, :hour, hours)
    return _FP.make_multinetwork(data, Dict{String,Any}())
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
    for nw in _FP.nw_ids(pm)
        _FP.variable_uc_gscr_block(pm; nw, relax)
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
        for nw in _FP.nw_ids(pm)
            _FP.variable_uc_gscr_block(pm; nw, relax=true, report=false)
        end

        @test !haskey(_PM.sol(pm, 1, :gen, 1), :n_block)
        @test !haskey(_PM.sol(pm, 1, :gen, 1), :na_block)
    end
end
