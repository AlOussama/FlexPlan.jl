using Test, JuMP, LinearAlgebra
import FlexPlan as FP, MosekTools
include("../scripts/paper_a/G3EquivalentConditioning.jl")
include("../scripts/paper_a/WeekStrengthAdmission.jl")

@testset "MOSEK native signed G3 dyadic readback" begin
    model=Model()
    @variable(model,0<=x<=2048)
    B=[4.0+x -4.;-4. 2.]
    cert=FP.add_paper_a_constraints!(model,B,zeros(2),B,FP.ExactEdgeSOCGSCR();alpha=1.)
    @objective(model,Min,4*x+12)
    copy=G3EquivalentConditioning.scaled_copy(model;objective_divisor=8192.)
    set_optimizer(copy.model,MosekTools.Optimizer);set_silent(copy.model)
    MOI.Utilities.attach_optimizer(backend(copy.model))
    attached=unsafe_backend(copy.model)
    pm=(;ext=Dict(:paper_a_certificates=>Dict(1=>cert)))
    @test WeekStrengthAdmission.native_strength_rows(pm,copy,attached)==
        Dict("native_RSOC_exact_readbacks"=>1,"native_node_row_exact_readbacks"=>2)
    @test copy.exponents[x]!=0
    @test WeekStrengthAdmission.native_cost(copy.model,attached)["constant"]==12
    optimize!(copy.model)
    @test unsafe_backend(copy.model)===attached
    @test termination_status(copy.model)==MOI.OPTIMAL
    @test G3EquivalentConditioning.backmap(copy,x)≈4 atol=1e-7
    @test objective_value(copy.model)≈28 atol=1e-7
end
