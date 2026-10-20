using Test,LinearAlgebra
import FlexPlan as FP,JSON
const R=ARGS[1]
raw=JSON.parsefile(joinpath(ARGS[2],"reports/ap3_runs/20261020_macro/accepted_suite/reference_3snap/case.json"))
net=raw["paper_a_network"];sn=raw["nw"]["1"];base=raw["baseMVA"]
@testset "Independent raw-domain adversarial probes" begin
    @test_throws ArgumentError FP.PaperARegional.network_reference(net,sn["bus"],base)
    ref=FP.PaperARegional.network_reference(net,sn["bus"],base;diagnostic_only=true)
    @test norm(ref.B0-ref.B0',Inf)<1e-10
    for change in (br->(br["tap_ratio"]=1.1),br->(br["phase_shift"]=.17),br->(br["source_component"]="transformers"))
        n=deepcopy(net);change(n["branch_primitives"][1]);@test_throws ArgumentError FP.PaperARegional.network_reference(n,sn["bus"],base;diagnostic_only=true)
    end
    n=deepcopy(net);push!(n["branch_primitives"],deepcopy(n["branch_primitives"][1]));@test_throws ArgumentError FP.PaperARegional.network_reference(n,sn["bus"],base;diagnostic_only=true)
    n=deepcopy(net);n["reference_buses"]=String[];@test_throws ArgumentError FP.PaperARegional.network_reference(n,sn["bus"],base;diagnostic_only=true)
    @test_throws ArgumentError FP.PaperARegional.symmetric_z([1. .8;.8 1.])
    @test_throws ArgumentError FP.PaperARegional.symmetric_z([1. -.4;-.2 1.])
    L=[1. -1.;-1. 1.];@test FP.PaperARegional.reduced_strength(L,[1],[2])≈zeros(1,1)
    @test FP.PaperARegional.reduced_strength([2. -1.;-1. -1.],[1],[2])==fill(3.,1,1) # algebraic only, NOT PSD approval
    @test FP.PaperARegional.source_b_block(30,100,.2)==1.5
    @test FP.PaperARegional.source_b_block(30,100,.2*30/60)==3.
    # At fixed online count, changing resource availability cannot change p.
    src=(region=1,mu_fl=.8,P_block_MW=100.,S_base_MVA=250.,n_on=1.)
    @test FP.PaperARegional.online_exposure(2,[src])≈[.32,0.]
    @test_throws ArgumentError FP.PaperARegional.online_exposure(2,[(;src...,n_on=-1.)])
    @test FP.PaperARegional.dispatch_event_weights(3.,2.,.5,4.)==(dispatch=3.,event=2.)
end
