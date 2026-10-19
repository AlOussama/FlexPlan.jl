using Test, LinearAlgebra
include(joinpath(@__DIR__,"..","src","core","paper_a_regional.jl"))
using .PaperARegional
@testset "AP2 standalone regional scientific primitives (NOT optimization integration)" begin
    L=[4.0 -2.0 0.0; -2.0 5.0 -1.0; 0.0 -1.0 2.0]
    R=reduced_strength(L,[1,3],[2])
    @test isapprox(R,[3.2 -0.4; -0.4 1.8]; atol=1e-12)
    @test reduced_strength(L,[1,2,3],Int[]) == L
    @test_throws ArgumentError reduced_strength([1.0 -1; -1 1],[1],[2])
    @test_throws ArgumentError reduced_strength([1.0 2; 0 1],[1],[2])
    @test source_b_block(250,250,0.25) ≈ 4.0
    @test source_b_block(100,250,0.2) ≈ 2.0
    @test_throws ArgumentError source_b_block(100,250,0)
    B=regional_strength(R,[0.2,0.0],[(region=1,mu_str=1.5,b_block=2.0,n_on=2)])
    @test B ≈ [9.4 -0.4; -0.4 1.8]
    @test online_exposure(2,[(region=1,mu_fl=0.8,P_block_MW=100.0,S_base_MVA=250.0,n_on=2)]) ≈ [0.64,0]
    @test assert_connection(2,2,1.0,0.0)
    @test_throws ArgumentError assert_connection(1,2,0.0,1.0)
    @test dispatch_event_weights(3,24,0.5,4) == (dispatch=36.0,event=2.0)
    @test validate_source(Dict("source_class"=>"SYN","grid_control_mode"=>"not_applicable","source_equivalent_valid"=>true,"source_equivalent_type"=>"voltage_behind_reactance","S_block_MVA"=>100,"S_base_MVA"=>250,"x_src"=>0.2,"mu_str"=>1))
    @test_throws ArgumentError validate_source(Dict("source_class"=>"SYN","grid_control_mode"=>"gfm"))
    @test_throws ArgumentError validate_source(Dict("source_class"=>"SC","grid_control_mode"=>"not_applicable"))
    @test_throws ArgumentError validate_source(Dict("source_class"=>"GFM","grid_control_mode"=>"gfm","fixed_strength_already_in_network"=>true,"b_block"=>1))
end
