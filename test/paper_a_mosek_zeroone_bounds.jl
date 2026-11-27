# Targeted admission for the newly installed MosekTools native ZeroOne route.
using Test, JuMP, LinearAlgebra
import FlexPlan as FP
include("../scripts/paper_a/NativeG3Solver.jl")
const NZ=NativeG3Solver
@testset "Native MOSEK binary bounds with existing G3 cones" begin
    for (lower,upper,feasible) in ((0.,1.,true),(.2,1.4,true),(0.,.8,false))
        m=Model();@variable(m,z)
        set_lower_bound(z,lower);set_upper_bound(z,upper);set_binary(z)
        B=[2.0+z -1.;-1. 2.0+z];p=[1.1,1.1];M=B-Diagonal(p)
        certificate=FP.add_paper_a_constraints!(m,B,p,M,FP.ExactEdgeSOCGSCR();alpha=1.)
        @objective(m,Min,z)
        opt=NZ.optimizer(;backend=:mosek)
        set_optimizer(m,opt);set_silent(m);NZ.configure_bridges!(m,opt)
        @test NZ.prepare_backend!(m,opt)["status"]=="native_SOC_and_RSOC_supported"
        @test all(start_value(v)===nothing for v in all_variables(m))
        optimize!(m)
        if feasible
            @test termination_status(m)==MOI.OPTIMAL
            @test primal_status(m)==MOI.FEASIBLE_POINT
            @test abs(value(z)-1.)<=1e-7
            @test NZ.primal_check(m)["status"]=="passed"
            witness=Dict("edges"=>[[1,2]],"q"=>[[value(certificate.q[1,1]),value(certificate.q[1,2])]])
            @test FP.PaperADiagnostics.verify_g3(value.(M),witness;tol=1e-7)["valid"]
        else
            # G3 requires z>=0.1, while binary with upper0.8 allows only zero.
            @test termination_status(m)==MOI.INFEASIBLE
            # The adapter can retain an UNKNOWN result record for this infeasible
            # MIP; it must never advertise a feasible primal plan.
            @test primal_status(m) ∉ (MOI.FEASIBLE_POINT,MOI.NEARLY_FEASIBLE_POINT)
        end
    end
end
