using LinearAlgebra
import Clarabel
const AP3D=_FP.PaperADiagnostics

function _ap3_conic(B,p,alpha,f;cost=nothing)
    m=JuMP.Model(Clarabel.Optimizer);JuMP.set_silent(m)
    JuMP.set_optimizer_attribute(m,"tol_gap_abs",1e-9)
    JuMP.set_optimizer_attribute(m,"tol_feas",1e-9)
    if cost===nothing
        BB=B
        JuMP.@objective(m,Min,0.)
    else
        x=JuMP.@variable(m,[1:length(p)],lower_bound=0.,upper_bound=4.)
        BB=B+Diagonal(x);JuMP.@objective(m,Min,sum(cost[i]*x[i] for i in eachindex(p)))
    end
    cert=_FP.add_paper_a_constraints!(m,BB,p,BB-alpha*Diagonal(p),f;alpha)
    JuMP.optimize!(m)
    return m,cert
end

@testset "AP3 complete integer conic reference in existing planning model" begin
    results=Dict{String,Any}();allrows=Any[]
    for (name,f) in (("G0",_FP.ExactPSDGSCR()),("G3",_FP.ExactEdgeSOCGSCR()))
        d=_ap2_fixture(;hours=1);d["nw"]["1"]["gen"]["2"]["nmax"]=4
        _FP.scale_paper_a_costs!(d)
        tpl=_FP.UCGSCRBlockTemplate(Dict((:gen,"GFL")=>_FP.BlockFixedInstalled(),(:gen,"SYN")=>_FP.BlockFixedInstalled(),(:storage,"GFM")=>_FP.BlockFixedInstalled()),f)
        feasible=Any[]
        for k in 0:4
            pm=_ap2_model(deepcopy(d);template=tpl,relax_block_variables=false,storage_terminal_policy=:fixed_initial)
            # All independent installed choices: PV=1, BESS=1, SYN=0:4.
            # FixedInstalled fixes every online count to installed; no event
            # variables exist in this fixture. Hence this exhausts the integers.
            for v in JuMP.all_variables(pm.model);JuMP.is_integer(v) && JuMP.unset_integer(v);end
            for key in ((:gen,1),(:storage,1),(:gen,2))
                val=key==(:gen,2) ? k : 1
                JuMP.fix(_PM.var(pm,1,:n_block,key),val;force=true)
                JuMP.fix(_PM.var(pm,1,:na_block,key),val;force=true)
            end
            @test all(v->!JuMP.is_integer(v),JuMP.all_variables(pm.model))
            JuMP.set_optimizer(pm.model,Clarabel.Optimizer);JuMP.set_silent(pm.model);JuMP.optimize!(pm.model)
            status=JuMP.termination_status(pm.model)
            @test status in (JuMP.MOI.OPTIMAL,JuMP.MOI.INFEASIBLE)
            row=Dict("formulation"=>name,"assignment_SYN"=>k,"termination"=>string(status),"objective"=>status==JuMP.MOI.OPTIMAL ? JuMP.objective_value(pm.model) : nothing)
            push!(allrows,row);status==JuMP.MOI.OPTIMAL && push!(feasible,row)
        end
        @test length(feasible)>0
        results[name]=minimum(r["objective"] for r in feasible)
    end
    @test isapprox(results["G0"],results["G3"];atol=1e-4)
    if haskey(ENV,"AP3_EVIDENCE_DIR")
        open(joinpath(ENV["AP3_EVIDENCE_DIR"],"integrated_integer_enumeration.json"),"w") do io
            _FP.JSON.print(io,Dict("expected_assignments_per_formulation"=>5,"executed"=>allrows,"certificate"=>"complete_all_independent_integer_choices; all_online_equal_installed; no_event_variables","optima"=>results),2)
        end
    end
end

@testset "AP3 frozen mathematics, conic and domain regressions" begin
    B=[1. -.5;-.5 1.];p=[1/4,2/3];M=B-Diagonal(p)
    a=AP3D.evaluate(B,p,1.)
    @test a["B.G0"]["value"]
    @test !a["B.G1"]["value"] && !a["C.M0"]["value"]
    @test a["C.Zp"]["value"]≈[7/9,19/18]
    w=Dict("edges"=>[[1,2]],"q"=>[[3/4,1/3]])
    @test AP3D.verify_g3(M,w)["valid"]
    @test !AP3D.verify_g3(M,Dict("edges"=>[],"q"=>[]))["valid"]
    @test !AP3D.verify_g3(M,Dict("edges"=>[[1,2],[1,2]],"q"=>[[.75,1/3],[.75,1/3]]))["valid"]
    @test !AP3D.verify_g3(M,Dict("edges"=>[[1,2]],"q"=>[[.75,1/6]]))["valid"] # missing sqrt2 would admit this
    b=AP3D.evaluate(B,[.75,.75],1.)
    @test b["C.LOCAL"]["value"] && !b["B.G0"]["value"]
    for (M,g1,g2) in (([1. -.6;-.6 1.],true,false),([.4 -.6;-.6 1.2],false,true))
        a=AP3D.evaluate(M,zeros(2),0.;r=[2.,1.])
        @test a["B.G1"]["value"]==g1
        @test a["B.G2"]["value"]==g2
    end
    for M in ([1. -1.;-1. 1.],[1. -1. 0.;-1. 1. 0.;0. 0. 0.])
        a=AP3D.evaluate(M,zeros(size(M,1)),1.)
        @test a["B.G0"]["value"] && a["C.M0"]["value"]===nothing
        @test a["C.LOCAL"]["value"] && a["C.rho_diag"]["value"]===nothing
        m,c=_ap3_conic(M,zeros(size(M,1)),1.,_FP.ExactEdgeSOCGSCR())
        @test JuMP.termination_status(m)==JuMP.MOI.OPTIMAL
        w=Dict("edges"=>[[i,j] for (i,j) in c.edges],"q"=>[[JuMP.value(c.q[k,1]),JuMP.value(c.q[k,2])] for k in eachindex(c.edges)])
        @test AP3D.verify_g3(M,w)["valid"]
    end
    @test AP3D.finite_spectrum([2. -1.;-1. 2.],[1.,0.])["gamma"]≈1.5
    @test AP3D.finite_spectrum([2. 0.;0. 0.],[1.,0.])["gamma"]≈2.
    @test AP3D.finite_spectrum([1. 1.;1. 0.],[1.,0.])["status"]=="domain_invalid_range_condition"
    @test AP3D.finite_spectrum(B,zeros(2))["gamma"]===nothing
    @test AP3D.evaluate(B,[-1e-12,0.],1.)["A.exposure_roundoff_correction"]["value"]==1e-12
    @test_throws ArgumentError AP3D.evaluate(B,[-.01,0.],1.)
    @test AP3D.finite_spectrum([1. 0.;0. -1.],[1.,0.])["status"]=="domain_invalid_zero_block"
    @test AP3D.evaluate(Diagonal([1.,1e-14]),ones(2),1.)["C.M0"]["value"]===nothing
    @test AP3D.evaluate([1. .2;.2 1.],ones(2),1.)["C.M0"]["status"]=="domain_invalid_inverse_sign"
    @test AP3D.evaluate(B,ones(2),0.)["C.M0"]["status"]=="undefined_alpha_zero"
    @test AP3D.evaluate(B,ones(2),0.;Bmin=B)["C.M1"]["status"]=="undefined_alpha_zero"
    @test_throws ArgumentError AP3D.evaluate([1. 1.;0. 1.],ones(2),1.)
    @test_throws ArgumentError _FP.FixedScalingGSCR([0.,1.];provenance="fixture")
    @test_throws ArgumentError _FP.InteractionGSCR([1. -.1;0. 1.];provenance="fixture")
    @test_throws ArgumentError _FP.InteractionGSCR(ones(2,2)*2;provenance="fixture")
    @test_throws ArgumentError _FP.InverseBoundGSCR([1. -1.;-1. 1.];provenance="fixture")
    bad=AP3D.evaluate(B,[.6,.6],1.;Bmin=2B)
    @test bad["C.M1"]["status"]=="domain_invalid_unenforced_Bmin"
    @test maximum((2B)\[.6,.6])<1 && maximum(B\[.6,.6])>1 # false M1 without enforced bound
    for f in (_FP.ExactPSDGSCR(),_FP.ExactEdgeSOCGSCR())
        m,c=_ap3_conic(B,p,1.,f)
        @test JuMP.termination_status(m)==JuMP.MOI.OPTIMAL
    end
    m,c=_ap3_conic(ones(3,3),zeros(3),0.,_FP.ExactPSDGSCR())
    @test JuMP.termination_status(m)==JuMP.MOI.OPTIMAL
    m,c=_ap3_conic(ones(3,3),zeros(3),0.,_FP.ExactEdgeSOCGSCR())
    @test JuMP.termination_status(m)==JuMP.MOI.INFEASIBLE
    u=AP3D.inverse_updates(B,Diagonal([.1,0.]);order=2)
    @test u["woodbury_residual"]<1e-12 && u["exact_remainder_residual"]<1e-12
    @test u["actual_error"]<=u["remainder_bound"] && !u["one_sided_safety_certified"]
    @test !AP3D.inverse_updates(B,3Matrix{Float64}(I,2,2))["trust_region_norm_valid"]
    @test AP3D.inverse_updates(B,3Matrix{Float64}(I,2,2))["remainder_bound"]===nothing
    @test maximum([.6,.6])<1 && maximum(B\[.6,.6])>1 # frozen false inverse-I certificate
    objs=Float64[]
    for f in (_FP.ExactPSDGSCR(),_FP.ExactEdgeSOCGSCR())
        m,c=_ap3_conic([.5 -.5;-.5 .5],[.25,2/3],1.,f;cost=[1.,3.])
        @test JuMP.termination_status(m)==JuMP.MOI.OPTIMAL
        push!(objs,JuMP.objective_value(m))
    end
    @test isapprox(objs[1],objs[2];atol=1e-7)
    d=_ap2_fixture(;hours=1);d["nw"]["1"]["storage"]["1"]["source_class"]="GFL"
    assets=Dict("$table:$id"=>Dict("online"=>1.,"installed"=>1.,"dispatch_MW"=>0.,"charge_MW"=>table=="storage" ? 5. : 0.) for table in ("gen","storage","ne_storage") for (id,dev) in get(d["nw"]["1"],table,Dict()) if haskey(dev,"source_class"))
    rec=AP3D.reconstruct(d,Dict("snapshots"=>Dict("1"=>Dict("assets"=>assets))),1)
    @test rec["S_op_magnitude_v1"][1]≈.8*5/250
    A=[.5 -.5;-.5 .5]
    m,c=_ap3_conic(A,[.1,.1],1.,_FP.InverseBoundGSCR([.6 -.5;-.5 .6];provenance="offline_fixture");cost=[1.,3.])
    @test JuMP.termination_status(m)==JuMP.MOI.OPTIMAL
    @test isapprox(JuMP.objective_value(m),.4;atol=1e-6)
    m,c=_ap3_conic(A,[.1,.1],1.,_FP.InverseBoundGSCR([.6 -.5000000000000001;-.5000000000000001 .6];provenance="independent_stamp_roundoff");cost=[1.,3.])
    @test JuMP.termination_status(m)==JuMP.MOI.OPTIMAL
    @test c.Bmin[1,2]==-.5 && c.passive_stamp_roundoff>0
    m,c=_ap3_conic(A,p,1.,_FP.InteractionGSCR(ones(2,2);provenance="offline_full");cost=[1.,3.])
    full=JuMP.objective_value(m)
    m,c=_ap3_conic(A,p,1.,_FP.InteractionGSCR(Matrix{Float64}(I,2,2);provenance="offline_sparse");cost=[1.,3.])
    @test full>JuMP.objective_value(m)
    @test AP3D.verify_g3(B-Diagonal(p),AP3D.closed_sdd_witness(B-Diagonal(p)))["valid"]
end

@testset "AP3 integrated AP2 common physical model" begin
    for f in (_FP.NoGSCR(),_FP.GershgorinGSCR(),_FP.ExactPSDGSCR(),_FP.ExactEdgeSOCGSCR(),
              _FP.FixedScalingGSCR(ones(2);provenance="offline_identity"),
              _FP.InverseBoundGSCR([10.1 -10.;-10. 10.1];provenance="offline_fixture_floor"),
              _FP.InteractionGSCR(Matrix{Float64}(I,2,2);provenance="offline_identity"))
        d=_ap2_fixture();_FP.scale_paper_a_costs!(d)
        pm=_ap2_model(d;template=_ap2_template(;gscr=f),relax_block_variables=true,storage_terminal_policy=:fixed_initial)
        JuMP.set_optimizer(pm.model, f isa _FP.ExactPSDGSCR || f isa _FP.ExactEdgeSOCGSCR ? Clarabel.Optimizer : HiGHS.Optimizer)
        JuMP.set_silent(pm.model);JuMP.optimize!(pm.model)
        # M1 enforces minimum strength at source-free R2: genuinely infeasible.
        @test JuMP.termination_status(pm.model)==(f isa _FP.InverseBoundGSCR ? JuMP.MOI.INFEASIBLE : JuMP.MOI.OPTIMAL)
        JuMP.has_values(pm.model) || continue
        x=pm.ext[:paper_a_online][1]; B=JuMP.value.(x.B);p=JuMP.value.(x.p_fl)
        @test maximum(abs.(JuMP.value.(x.M)-(B-4Diagonal(p))))<1e-8
        !(f isa _FP.NoGSCR) && @test eigmin(Symmetric(JuMP.value.(x.M)))>=-1e-5
    end
end
