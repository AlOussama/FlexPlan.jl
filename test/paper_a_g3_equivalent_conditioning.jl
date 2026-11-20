module G3EquivalentConditioningTests
using Test, JuMP
include("../scripts/paper_a/G3EquivalentConditioning.jl")
include("../scripts/paper_a/NativeG3Solver.jl")
const C=G3EquivalentConditioning
const N=NativeG3Solver
const MOI=JuMP.MOI

@testset "Invertible G3 conditioning and original result projection" begin
    for integer in (false,true), divisor in (8192.,2.0^20)
        m=Model()
        @variable(m,0<=z<=3,Int)
        protected=Set([z])
        !integer && relax_integrality(m)
        @variable(m,0<=e<=2.0^20)
        @variable(m,e0==2.0^19)
        @variable(m,0<=capacity<=2.0^20)
        @variable(m,q[1:2]>=0)
        @constraint(m,z>=0.1)
        @constraint(m,e-e0==0.125)
        @constraint(m,2.0^-10*capacity>=2.)
        cone=@constraint(m,[q[1],q[2],sqrt(2.)*512.] in RotatedSecondOrderCone())
        @constraint(m,q[1]+q[2]<=1024. + z)
        original=1e8*z+100.0*capacity+123.25
        conditioned,meta=N.condition_objective(original;divisor,
            minimum_coefficient=divisor==8192. ? N.MIN_OBJECTIVE_COEFFICIENT : 2.0^-20)
        @test meta["multiplier"]==1.
        @test meta["effective_divisor"]==divisor
        @test Rational{BigInt}(conditioned.constant)*Rational{BigInt}(divisor)==Rational{BigInt}(original.constant)
        @objective(m,Min,conditioned)
        copy=C.scaled_copy(m;protected,objective_divisor=divisor)
        @test copy.metadata["objective_divisor_unchanged"]==divisor
        @test copy.exponents[z]==0
        @test copy.exponents[e]==copy.exponents[capacity]==7
        @test copy.exponents[q[1]]>0
        @test copy.metadata["original_row_error_amplification_max"]<=64.
        @test all(C.dyadic(C.dyadic(a,k),-k)==a for a in (0.,-1e-8,0.1,2.0^19) for k in -6:7)
        opt=N.optimizer()
        set_optimizer(copy.model,opt);set_silent(copy.model)
        set_optimizer_attribute(copy.model,"FeasibilityTol",1e-9)
        set_optimizer_attribute(copy.model,"BarQCPConvTol",1e-10)
        N.configure_bridges!(copy.model,opt)
        @test N.prepare_backend!(copy.model,opt)["cones"]==1
        optimize!(copy.model)
        @test termination_status(copy.model)==MOI.OPTIMAL
        saved=Dict(v=>C.backmap(copy,v) for v in all_variables(m))
        native=(termination_status(copy.model),primal_status(copy.model),result_count(copy.model),objective_value(copy.model),objective_bound(copy.model))
        C.project_results!(m,copy)
        @test all(value(v)==saved[v] for v in all_variables(m))
        @test (termination_status(m),primal_status(m),result_count(m),objective_value(m),objective_bound(m))==native
        @test dual_status(m)==MOI.NO_SOLUTION
        @test value(z)≈(integer ? 1. : 0.1) atol=1e-7
        @test value(e)-value(e0)≈0.125 atol=1e-7
        @test value(capacity)≈2048. atol=1e-6
        @test N.primal_check(m)["status"]=="passed"
        @test primal_feasibility_report(m;atol=0.)==primal_feasibility_report(m,saved;atol=0.)
        @test MOI.get(unsafe_backend(m),MOI.ConstraintPrimal(),index(cone))≈value.(constraint_object(cone).func)
        @test value(original)≈objective_value(m)*divisor atol=1e-6
        @test N.original_currency_bound(objective_bound(m),divisor)≈value(original) atol=1e-5 rtol=1e-10
        @test num_variables(m)==num_variables(copy.model)
        @test all(start_value(v)===nothing for v in all_variables(copy.model))
    end
    costmodel=Model();@variable(costmodel,a);@variable(costmodel,b)
    actual_min=0.006365094866071429*8192.
    actual_max=4737.052242170494*8192.
    f=actual_min*a+actual_max*b-2.6565906453343933e6*8192.
    legacy,old=N.condition_objective(f;divisor=2.0^20)
    normalized,new=N.condition_objective(f;divisor=2.0^20,minimum_coefficient=2.0^-20)
    @test old["effective_divisor"]==8192.
    @test new["effective_divisor"]==2.0^20 && new["multiplier"]==1.
    @test new["original_currency_coefficient_floor"]==1.
    @test new["minimum_nonzero_coefficient"]>2.0^-20
    @test Rational{BigInt}(coefficient(normalized,a))*2^20==Rational{BigInt}(actual_min)
    @test Rational{BigInt}(coefficient(normalized,b))*2^20==Rational{BigInt}(actual_max)
    @test Rational{BigInt}(normalized.constant)*2^20==Rational{BigInt}(f.constant)
    @test N.original_currency_bound(-1e100,2.0^20)===nothing
    @test N.original_currency_bound(1e100,2.0^20)===nothing
    @test N.original_currency_bound(118.,2.0^20)==118.0*2.0^20
    @test abs((121000.0-120000.0)/121000.0-((121000.0*128)-(120000.0*128))/(121000.0*128))<=eps()
    for invalid in (0.,-1.,Inf,NaN)
        @test_throws N.NumericalInputError N.condition_objective(f;minimum_coefficient=invalid)
    end
    # Direct non-normalized affine objects test symbolic construction only;
    # Gurobi's native interface requires normalized scalar affine constants.
    symbolic=Model();@variable(symbolic,0<=x<=2.0^20)
    row=add_constraint(symbolic,ScalarConstraint(AffExpr(1.25,x=>0.125),MOI.GreaterThan(128.)))
    @objective(symbolic,Min,x)
    copied=C.scaled_copy(symbolic)
    stored=constraint_object(copied.constraints[row])
    @test stored.func.constant==ldexp(1.25,copied.rows[row])
    @test stored.set.lower==ldexp(128.,copied.rows[row])
    @test_throws ErrorException C.dyadic(nextfloat(0.),-1)
    bad=Model();@variable(bad,x>=0);@constraint(bad,x*x<=1.)
    @objective(bad,Min,x)
    @test_throws ErrorException C.scaled_copy(bad)
    badcone=Model();@variable(badcone,x>=0);@variable(badcone,y>=0)
    @constraint(badcone,[x+1.,y,2.] in RotatedSecondOrderCone());@objective(badcone,Min,x+y)
    @test_throws ErrorException C.scaled_copy(badcone)
end
end
