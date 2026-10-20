using JuMP,Test,LinearAlgebra
import HiGHS,JSON,Gurobi,SHA,Pkg
const MOI=JuMP.MOI;const R=ARGS[1];mkpath(joinpath(R,"tests_new"))
results=Any[]
@testset "A3.6 actual coefficient ingestion and exact transformations" begin
    # Measured affine OA cut. An exact rational witness is x3=rhs/c3,
    # x1=x2=0, with integer dummy z=0; no inferred feasibility epsilon.
    a=[4.5830185178677806e-11,4.5830185178677806e-11,1.3046247794859574e-10]
    rhs=3.025002202302713e-8
    @test all(0 .< abs.(a) .<= 1e-9)
    @test Rational{BigInt}(a[3])*(Rational{BigInt}(rhs)/Rational{BigInt}(a[3]))==Rational{BigInt}(rhs)
    @test 0. < rhs
    for (mode,threshold,k) in [("default_filter",1e-9,0),("preserved_coefficients",1e-12,0),("exact_power_two_scaling",1e-9,33)]
        aa=ldexp.(a,k);rr=ldexp(rhs,k)
        @test all(Rational{BigInt}(aa[i])==big(2)^k*Rational{BigInt}(a[i]) for i in 1:3)
        @test Rational{BigInt}(rr)==big(2)^k*Rational{BigInt}(rhs)
        m=Model(HiGHS.Optimizer);@variable(m,x[1:3]>=0);@variable(m,0<=z<=1,Int)
        @constraint(m,sum(aa.*x)>=rr);@objective(m,Min,z)
        for (key,value) in (("threads",1),("random_seed",0),("mip_feasibility_tolerance",1e-8),("small_matrix_value",threshold));set_optimizer_attribute(m,key,value);end
        optimize!(m)
        push!(results,Dict("mode"=>mode,"threshold"=>threshold,"power_two_exponent"=>k,"status"=>string(termination_status(m)),"primal_status"=>string(primal_status(m))))
        if mode!="default_filter"
            @test termination_status(m)==MOI.OPTIMAL
            @test maximum(values(primal_feasibility_report(m;atol=0.));init=0.)<1e-7
        end
    end
    # Exact objective offset and scale tests include a nonzero negative constant.
    C0=-big(10)^12//1;c=7//3;lower=2//1;x=5//1;s=11//2
    C=C0+c*x;inc=x-lower;rebased=C0+c*lower+c*inc
    @test C==rebased
    @test (rebased/s)*s==C
    @test C0+(C-C0)/s*s==C
    @test (10//1-11//1)<0
    @test (10//1-11//1)!=abs(10//1-11//1)
end
license=Dict{String,Any}()
try
    m=Model(Gurobi.Optimizer);@variable(m,x>=0,Int);@constraint(m,[x,x,sqrt(2.)] in RotatedSecondOrderCone());@objective(m,Min,x);optimize!(m)
    license["Gurobi"]=Dict("status"=>string(termination_status(m)),"primal"=>string(primal_status(m)))
catch e;license["Gurobi"]=Dict("available"=>false,"error"=>sprint(showerror,e));end
open(io->JSON.print(io,Dict("minimal_counterexample_results"=>results,"licenses"=>license,"Julia"=>string(VERSION),"julia_threads"=>Threads.nthreads(),"BLAS_threads"=>BLAS.get_num_threads(),"BLAS"=>string(BLAS.get_config()),"packages"=>Dict(p.name=>string(p.version) for p in values(Pkg.dependencies()) if p.version!==nothing)),2),joinpath(R,"tests_new/results.json"),"w")
