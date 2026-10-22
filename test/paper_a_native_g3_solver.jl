using Test, JuMP
include("../scripts/paper_a/AP3Pipeline.jl")
const P = AP3Pipeline
const N = P.NativeG3Solver

@testset "Native G3 finite-domain numerical guards" begin
    m=Model();@variable(m,x>=0)
    f=3.7524903900502144e-9*x + 2.178606398164727e-15
    g,meta=N.condition_objective(f)
    @test meta["power_two_exponent"] == 20
    @test Rational{BigInt}(coefficient(g,x)) == Rational{BigInt}(coefficient(f,x))*2^20
    @test Rational{BigInt}(g.constant) == Rational{BigInt}(f.constant)*2^20
    @test N.is_native(P.mosek_optimizer())
    @test !N.is_native(P.pajarito_optimizer())
    @test_throws N.NumericalInputError N.condition_objective(1e-300*x + 1e300)
    @test_throws N.NumericalInputError N.condition_objective(1e-300*x + 1.)

    # A valid row at each historical threshold must be refused, never filtered.
    for a in (4.5830185178677806e-11,1.2740476362167553e-13)
        tiny=Model();@variable(tiny,z>=0,Int)
        @constraint(tiny,a*z>=3.025002202302713e-8);@objective(tiny,Min,z)
        @test_throws N.NumericalInputError N.input_range(tiny)
        result=P.solve!((model=tiny,),P.mosek_optimizer())
        @test result["termination"] == "OPTIMIZE_NOT_CALLED"
        @test result["numerical_validation"] == "rejected_input"
        @test result["bound"] === nothing
    end

    # The exact integer optimum is five; the physical objective stays tiny.
    native=Model();@variable(native,0<=z<=10,Int);@variable(native,y==1)
    @constraint(native,[z,y,3.] in RotatedSecondOrderCone())
    @objective(native,Min,3.7524903900502144e-9*z + 2.178606398164727e-15)
    result=P.solve!((model=native,),P.mosek_optimizer())
    @test result["termination"] == "OPTIMAL"
    @test result["numerical_validation"] == "passed"
    @test value(z) == 5.
    @test result["objective"] ≈ 5*3.7524903900502144e-9+2.178606398164727e-15 atol=1e-20 rtol=1e-12
    @test result["objective_conditioning"]["exact_binary_scaling_verified"]
    @test result["bound_certification"] == "numerical_only_not_rigorous_currency_bound"
end
