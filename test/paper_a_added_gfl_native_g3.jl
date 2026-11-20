using Test, JuMP, LinearAlgebra
import FlexPlan as FP
include("../scripts/paper_a/NativeG3Solver.jl")

@testset "Added GFL exact RSOC profile and original witness" begin
    N=NativeG3Solver
    for integer in (false,true)
        m=Model();@variable(m,0<=z<=3);integer && set_integer(z)
        @variable(m,c==50.)
        p=[0.6+c/100,0.6+c/100]
        B=[2.0+z -1.;-1. 2.0+z];M=B-Diagonal(p)
        cert=FP.add_paper_a_constraints!(m,B,p,M,FP.ExactEdgeSOCGSCR();alpha=1.)
        original_cost=1e8*z+123.25
        emitted,conditioning=N.condition_objective(original_cost;divisor=8192.)
        @test conditioning["exact_binary_division_verified"]
        @test conditioning["effective_divisor"]==8192.
        @test Rational{BigInt}(coefficient(emitted,z))*8192==Rational{BigInt}(coefficient(original_cost,z))
        @test Rational{BigInt}(emitted.constant)*8192==Rational{BigInt}(original_cost.constant)
        @test num_variables(m)==4
        @test all(start_value(v)===nothing for v in all_variables(m))
        @objective(m,Min,emitted)
        @test N.input_range(m)["minimum_nonzero_coefficient"]==0.01
        opt=N.optimizer()
        set_optimizer(m,opt);set_silent(m)
        set_optimizer_attribute(m,"BarQCPConvTol",1e-10)
        set_optimizer_attribute(m,"FeasibilityTol",1e-9)
        set_optimizer_attribute(m,"OptimalityTol",1e-9)
        set_optimizer_attribute(m,"ScaleFlag",2)
        set_optimizer_attribute(m,"Aggregate",0)
        N.configure_bridges!(m,opt)
        bridge=N.prepare_backend!(m,opt)
        @test bridge["cones"]==1 && bridge["nonconvex_parameter"]==0
        optimize!(m)
        @test termination_status(m)==MOI.OPTIMAL
        @test value(z)≈(integer ? 1. : 0.1) atol=1e-7
        @test N.primal_check(m)["status"]=="passed"
        @test value(original_cost)≈objective_value(m)*conditioning["effective_divisor"] atol=1e-6 rtol=1e-12
        witness=Dict("edges"=>[[1,2]],"q"=>[[value(cert.q[1,1]),value(cert.q[1,2])]])
        @test FP.PaperADiagnostics.verify_g3(value.(M),witness;tol=1e-7)["valid"]
        @test !FP.PaperADiagnostics.verify_g3(value.(M),Dict("edges"=>Any[],"q"=>Any[]))["valid"]
    end
    psd=Model();@variable(psd,x);@constraint(psd,[x 1.;1. x] in PSDCone())
    @test_throws N.NumericalInputError N.input_range(psd)
    triangle=Model();@variable(triangle,x);@constraint(triangle,Symmetric([x 1.;1. x]) in PSDCone())
    @test_throws N.NumericalInputError N.input_range(triangle)
    tiny=Model();@variable(tiny,x>=0);@constraint(tiny,1e-12*x>=1.)
    @test_throws N.NumericalInputError N.input_range(tiny)
    f=2*x+1.
    a,am=N.condition_objective(f);b,bm=N.condition_objective(f;divisor=1.)
    @test isequal_canonical(a,b) && am==bm
    @test_throws N.NumericalInputError N.condition_objective(f;divisor=3.)
    @test N.original_currency_bound(-1e100,8192.)===nothing
    @test N.original_currency_bound(1e100,8192.)===nothing
    @test N.original_currency_bound(nothing,8192.)===nothing
    @test N.original_currency_bound(1234.,8192.)==1234*8192
end
