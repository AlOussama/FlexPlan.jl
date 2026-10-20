using JuMP,LinearAlgebra,Test
import FlexPlan as FP, HiGHS,JSON
include(joinpath(ARGS[1],"scripts/paper_a/AP3Pipeline.jl"))
const P=AP3Pipeline;const R=ARGS[2]
evidence=Any[]
@testset "Independent G1 G2 M1 M2 actual affine constraints" begin
    for f in (FP.FixedScalingGSCR([1.,1.];provenance="independent_fixed"),FP.FixedScalingGSCR([2.,1.];provenance="independent_fixed"),FP.InteractionGSCR([1. .2;.3 1.];provenance="independent_fixed"),FP.InverseBoundGSCR([.6 -.5;-.5 .6];provenance="independent_fixed"))
        m=Model(HiGHS.Optimizer);set_silent(m);@variable(m,x[1:2]>=0)
        B=[.5 -.5;-.5 .5]+Diagonal(x);p=[.1,.1];M=B-Diagonal(p)
        c=FP.add_paper_a_constraints!(m,B,p,M,f;alpha=1.)
        @objective(m,Min,x[1]+3x[2]);optimize!(m)
        @test termination_status(m)==JuMP.MOI.OPTIMAL
        @test maximum(values(primal_feasibility_report(m;atol=0.));init=0.)<1e-7
        if f isa FP.InverseBoundGSCR
            @test minimum(value.(B)-f.Bmin)>=-1e-7
            @test maximum(inv(f.Bmin)*p)<=1+1e-7
            @test maximum(inv(value.(B))*p)<=1+1e-7
            @test isapprox(objective_value(m),.4;atol=1e-8)
            @test length(c.lower)==2 && length(c.rows)==2
        else
            for i in 1:2
                co=constraint_object(c.rows[i]);expected=f isa FP.FixedScalingGSCR ? sum(M[i,j]*f.r[j] for j in 1:2) : sum(B[i,j] for j in 1:2)-sum(f.W[i,j]*p[j] for j in 1:2)
                @test co.func-co.set.lower≈expected
            end
        end
        push!(evidence,Dict("formulation"=>string(typeof(f)),"objective"=>objective_value(m),"B"=>[value.(B[i,:]) for i in 1:2],"rows"=>string.(c.rows)))
    end
    # Inspect every actual G1 row and each variable coefficient against the
    # common affine M row, rather than checking only a solved point.
    root=joinpath(ARGS[1],"reports/ap3_runs/20261020_macro/accepted_suite/reference_3snap")
    raw,data,scope=P.prepare(joinpath(root,"case.json");registry=joinpath(root,"parameter_registry.csv"),scenarios=joinpath(root,"study_scenarios.toml"))
    pm=P.build(data,FP.GershgorinGSCR(),scope;relaxed=true)
    for nw in sort(collect(keys(pm.ext[:paper_a_online])))
        x=pm.ext[:paper_a_online][nw];cons=P.PM.con(pm,nw,:gscr_gershgorin_sufficient)
        for (i,region) in enumerate(x.regions)
            co=constraint_object(cons[region]);expected=sum(x.M[i,j] for j in eachindex(x.regions))
            delta=co.func-co.set.lower-expected
            residual=max(abs(delta.constant),maximum((abs(a) for (a,v) in linear_terms(delta));init=0.))
            @test residual<1e-10
            push!(evidence,Dict("formulation"=>"G1","snapshot"=>nw,"region"=>region,"affine_coefficient_and_constant_residual"=>residual))
        end
    end
end
open(io->JSON.print(io,evidence,2),joinpath(R,"independent_linear_certificate_results.json"),"w")
