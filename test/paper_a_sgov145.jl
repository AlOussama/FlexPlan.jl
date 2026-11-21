using Test, JuMP, LinearAlgebra
import Gurobi, MosekTools, FlexPlan as FP
include("../scripts/paper_a/WeekStrengthAdmission.jl")
const D145=FP.PaperADiagnostics

@testset "SGOV145 matrix and native domain contracts" begin
    m=Model()
    B=[2. -1.;-1. 2.]
    @test !D145.evaluate(B,[0.5,4/3],1.)["C.M0"]["value"]
    @test D145.evaluate(B,[1.,1.],1.)["C.M0"]["value"]
    @test D145.finite_spectrum(B,[1.,0.])["gamma"]≈1.5
    @test D145.finite_spectrum([1. -1.;-1. 0.],[1.,0.])["status"]=="domain_invalid_range_condition"
    asym=[0. -1.;0. 0.]
    @test_throws ArgumentError FP.add_paper_a_constraints!(m,asym,zeros(2),asym,FP.ExactPSDGSCR();alpha=1.)
    @test D145.finite_spectrum(asym,ones(2))["gamma"]===nothing
    @test D145.finite_spectrum([1e9 -.1;-.1 0.],[1.,0.];tol=1e-9)["status"]=="domain_invalid_range_condition"
    @test D145.finite_spectrum([1. 0.;0. -1e-12],[1.,0.];tol=1e-9)["status"]=="domain_invalid_zero_block"
    singular=D145.finite_spectrum([2. -1. 1.;-1. 1. -1.;1. -1. 1.],[1.,0.,0.])
    @test singular["gamma"]≈1
    @test singular["participation"]≈[2/3,1/6,1/6]
    for scale in (1.,1e8)
        check=D145.evaluate(reshape([scale],1,1),[1.001scale],1.;tol=1e-9)
        @test !check["C.M0"]["value"]
        @test only(check["C.rho_Zp"]["value"])≈1/1.001
    end
    @test isnothing(D145.evaluate(1e10*[1. .8;.8 1.],fill(1e10,2),1.;tol=1e-9)["C.M0"]["value"])
    @test D145.evaluate([0. 1.;1. 0.],zeros(2),1.)["B.G1"]["value"]===nothing
    @test_throws ArgumentError FP.InverseBoundGSCR([1. -0.1;0. 1.];provenance="invalid")
    @test_throws ArgumentError FP.InteractionGSCR([1. Inf;0. 1.];provenance="invalid")
    net=Dict("bus_to_region"=>Dict("1"=>"A","2"=>"B"),"retained_physical_buses"=>["1","2"])
    order_fixture=Dict("paper_a_network"=>net)
    W=[1. 0.5;0.25 1.]
    d1=FP._paper_a_week_parameter_digest(order_fixture,FP.InteractionGSCR(W;provenance="same"))
    @test d1!=FP._paper_a_week_parameter_digest(order_fixture,FP.InteractionGSCR(transpose(W);provenance="same"))
    reverse!(net["retained_physical_buses"])
    @test d1!=FP._paper_a_week_parameter_digest(order_fixture,FP.InteractionGSCR(W;provenance="same"))
    @test !D145.verify_g3(B,Dict("edges"=>[],"q"=>[]))["valid"]
    @test !D145.verify_g3(B,Dict("edges"=>[[1,2]],"q"=>[[3.,1.]]))["valid"]
    @test !MOI.supports_constraint(Gurobi.Optimizer(), MOI.VectorAffineFunction{Float64}, MOI.PositiveSemidefiniteConeTriangle)
    for kind in (FP.ExactPSDGSCR(),FP.ExactEdgeSOCGSCR())
        model=Model(MosekTools.Optimizer);set_silent(model)
        @variable(model,0<=x<=2,Int)
        bb=B+Diagonal([x,x])
        FP.add_paper_a_constraints!(model,bb,[1.5,1.5],bb-1.5I,kind;alpha=1.)
        @objective(model,Min,x)
        relax_integrality(model)
        @test !isempty(WeekStrengthAdmission.inventory(backend(model);continuous=true))
        MOI.Utilities.attach_optimizer(backend(model))
        native=unsafe_backend(model)
        @test !isempty(WeekStrengthAdmission.inventory(native;continuous=true))
        @test WeekStrengthAdmission.native_cost(model,native)["terms"]==1
        if kind isa FP.ExactPSDGSCR
            @test WeekStrengthAdmission.psd_sizes(native)==[2]
        end
        optimize!(model)
        @test unsafe_backend(model)===native
        @test termination_status(model)==MOI.OPTIMAL
        @test value(x)≈0.5 atol=1e-7
        @test minimum(i for i in 0:2 if eigmin(B+i*I-1.5I)>=0)==1
    end
    for (f,expected) in ((FP.InverseBoundGSCR(B;provenance="fixed minimum"),1.),
                         (FP.InteractionGSCR([1. 0.;0. 1.];provenance="identity"),1.),
                         (FP.InteractionGSCR([1. 0.5;0.25 1.];provenance="fixed"),2/3))
        model=Model(Gurobi.Optimizer);set_silent(model)
        @variable(model,0<=u<=3)
        c=FP.add_paper_a_constraints!(model,B,[u,u],B-Diagonal([u,u]),f;alpha=1.)
        @objective(model,Max,u)
        optimize!(model)
        @test termination_status(model)==MOI.OPTIMAL
        @test value(u)≈expected atol=1e-7
    end
    for set in (MOI.ZeroOne(),MOI.Integer(),MOI.Semicontinuous(1.,2.),MOI.Semiinteger(1.,2.))
        raw=MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        MOI.add_constrained_variable(raw,set)
        @test_throws ErrorException WeekStrengthAdmission.inventory(raw;continuous=true)
    end
    for set in (MOI.SOS1([1.,2.]),MOI.SOS2([1.,2.]),MOI.Indicator{MOI.ACTIVATE_ON_ONE}(MOI.LessThan(0.)))
        raw=MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        MOI.add_constraint(raw,MOI.VectorOfVariables(MOI.add_variables(raw,2)),set)
        @test_throws ErrorException WeekStrengthAdmission.inventory(raw;continuous=true)
    end
end

@testset "Historical ratio proxy, fixed and piecewise" begin
    for (boxes,d0,relaxed,expected) in (([(1.,2.)],1.5,false,1.),
            ([(1.,1.),(2.,2.)],2.,false,.5), ([(1.,1.),(2.,2.)],1.5,true,.5))
        model=Model(Gurobi.Optimizer);set_silent(model)
        @variable(model,P==1)
        @variable(model,d==d0)
        burden=FP.paper_a_ratio_majorant!(model,P,d,boxes;Pmax=2.)
        relaxed && relax_integrality(model)
        @objective(model,Min,burden)
        optimize!(model)
        @test termination_status(model)==MOI.OPTIMAL
        @test objective_value(model)≈expected atol=1e-7
        @test (objective_value(model)+1e-7 >= 1/d0)==!relaxed
    end
end
