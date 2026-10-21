using JuMP, Test, LinearAlgebra
import JSON, HiGHS, Pkg, SHA
const MOI=JuMP.MOI
const W=ARGS[1]; const R=ARGS[2]; const A=joinpath(R,"prior")
module Original
    include("D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE/scripts/paper_a/AP3Pipeline.jl")
end
module Corrected
    include(joinpath(Main.W,"scripts/paper_a/AP3Pipeline.jl"))
end
rows=Any[]
function save()
    open(io->JSON.print(io,rows,2),joinpath(R,"solver_review.json"),"w")
end
@testset "Independent HiGHS filter and actual production factories" begin
    a=[4.5830185178677806e-11,4.5830185178677806e-11,1.3046247794859574e-10]; rhs=3.025002202302713e-8
    @test Rational{BigInt}(a[3])*(Rational{BigInt}(rhs)/Rational{BigInt}(a[3]))==Rational{BigInt}(rhs)
    for (mode,threshold,k,expected) in [("default",1e-9,0,MOI.INFEASIBLE),("fix",1e-12,0,MOI.OPTIMAL),("power_two",1e-9,33,MOI.OPTIMAL),("below_fix_threshold",1e-12,-10,MOI.OPTIMAL)]
        # The last row is scaled down together with its RHS; it illustrates that
        # a finite threshold still discards coefficients, even when no false
        # infeasibility is asserted at the fixed 1e-8 feasibility tolerance.
        m=Model(HiGHS.Optimizer); @variable(m,x[1:3]>=0); @variable(m,0<=z<=1,Int)
        aa=ldexp.(a,k); rr=ldexp(rhs,k)
        @constraint(m,sum(aa.*x)>=rr); @objective(m,Min,z)
        for (key,v) in (("threads",1),("mip_feasibility_tolerance",1e-8),("small_matrix_value",threshold)); set_optimizer_attribute(m,key,v); end
        optimize!(m); status=termination_status(m)
        push!(rows,Dict("kind"=>"minimal","mode"=>mode,"status"=>string(status),"coefficient_filter"=>threshold,"power_two"=>k,"row_rhs"=>rr,"primal"=>string(primal_status(m)))); save()
        @test status==expected
        @test all(Rational{BigInt}(aa[i])==Rational{BigInt}(a[i])*Rational{BigInt}(2)^k for i in 1:3)
    end
    for (mode,threshold,expected) in [("original",1e-9,MOI.INFEASIBLE),("corrected",1e-12,MOI.OPTIMAL)]
        m=read_from_file(joinpath(A,"experiments/stages/oa_frozen.mof.json")); set_optimizer(m,HiGHS.Optimizer)
        for (key,v) in (("threads",1),("random_seed",20261020),("mip_feasibility_tolerance",1e-8),("mip_rel_gap",1e-8),("time_limit",120.),("small_matrix_value",threshold)); set_optimizer_attribute(m,key,v); end
        optimize!(m)
        push!(rows,Dict("kind"=>"frozen_oa","mode"=>mode,"status"=>string(termination_status(m)),"primal"=>string(primal_status(m)),"bound"=>Corrected.AP3Pipeline.safe(()->objective_bound(m)))); save()
        @test termination_status(m)==expected
    end
    for (mode,optimizer) in [("original_factory",Original.AP3Pipeline.pajarito_optimizer()),("corrected_factory",Corrected.AP3Pipeline.pajarito_optimizer())]
        m=read_from_file(joinpath(A,"original_01/b1_exact_native.mof.json")); set_optimizer(m,optimizer); optimize!(m)
        push!(rows,Dict("kind"=>"original_native_serialization","mode"=>mode,"status"=>string(termination_status(m)),"primal"=>string(primal_status(m)))); save()
        mode=="original_factory" && @test termination_status(m)==MOI.INFEASIBLE
    end
end
open(io->JSON.print(io,Dict("Julia"=>string(VERSION),"julia_threads"=>Threads.nthreads(),"BLAS_threads"=>BLAS.get_num_threads(),"packages"=>Dict(p.name=>string(p.version) for p in values(Pkg.dependencies()) if p.version!==nothing)),2),joinpath(R,"runtime.json"),"w")
