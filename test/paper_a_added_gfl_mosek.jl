# Targeted backend admission after the concrete full-case Gurobi rejection.
using Test, JuMP, LinearAlgebra
import FlexPlan as FP
include("../scripts/paper_a/NativeG3Solver.jl")
@testset "Existing native MOSEK G3 class and cost coordinates" begin
    N=NativeG3Solver
    for discrete in (false,true)
        m=Model();@variable(m,0<=z<=3);discrete && set_integer(z)
        @variable(m,c==50.)
        p=[0.6+c/100,0.6+c/100]
        B=[2.0+z -1.;-1. 2.0+z];M=B-Diagonal(p)
        cert=FP.add_paper_a_constraints!(m,B,p,M,FP.ExactEdgeSOCGSCR();alpha=1.)
        original=1e8*z+123.25
        objective,meta=N.condition_objective(original;divisor=8192.)
        @objective(m,Min,objective)
        @test num_variables(m)==4
        @test all(start_value(v)===nothing for v in all_variables(m))
        @test N.input_range(m)["coefficient_floor"]==1e-9
        opt=N.optimizer(;backend=:mosek)
        set_optimizer(m,opt);set_silent(m)
        N.configure_bridges!(m,opt)
        @test N.prepare_backend!(m,opt)["status"]=="native_SOC_and_RSOC_supported"
        optimize!(m)
        @test termination_status(m)==MOI.OPTIMAL
        @test primal_status(m)==MOI.FEASIBLE_POINT
        @test value(z)≈(discrete ? 1. : .1) atol=1e-7
        @test N.primal_check(m)["status"]=="passed"
        @test value(original)≈objective_value(m)*meta["effective_divisor"] rtol=1e-12
        bound=N.original_currency_bound(objective_bound(m),meta["effective_divisor"])
        @test bound!==nothing && abs(value(original)-bound)/max(1.,abs(value(original)))<=1e-6
        witness=Dict("edges"=>[[1,2]],"q"=>[[value(cert.q[1,1]),value(cert.q[1,2])]])
        @test FP.PaperADiagnostics.verify_g3(value.(M),witness;tol=1e-7)["valid"]
    end
end
