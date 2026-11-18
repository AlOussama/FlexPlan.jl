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
        @objective(m,Min,z)
        @test N.input_range(m)["minimum_nonzero_coefficient"]==0.01
        opt=N.optimizer()
        set_optimizer(m,opt);set_silent(m)
        N.configure_bridges!(m,opt)
        bridge=N.prepare_backend!(m,opt)
        @test bridge["cones"]==1 && bridge["nonconvex_parameter"]==0
        optimize!(m)
        @test termination_status(m)==MOI.OPTIMAL
        @test value(z)≈(integer ? 1. : 0.1) atol=1e-7
        @test N.primal_check(m)["status"]=="passed"
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
end
