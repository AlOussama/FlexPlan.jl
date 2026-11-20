module G3ConditionedRunnerScopeTests
using Test

@testset "Noninteractive actual runner try-scope and fail-closed routing" begin
    repo=normpath(joinpath(@__DIR__,".."))
    runner=read(joinpath(repo,"scripts/paper_a/run_week_strength_comparison.jl"),String)
    start="    conditioned_copy=nothing\n    if criterion==\"G3\"\n"
    stop="    if phase==\"profile\""
    @test length(findall(start,runner))==length(findall(stop,runner))==1
    body=split(split(runner,start)[2],stop)[1]
    body=start*body
    fresh=Module(:G3ActualTopLevelScope)
    preamble="""
    using JuMP,SHA
    include(p)=Base.include(@__MODULE__,p)
    include($(repr(joinpath(repo,"scripts/paper_a/NativeG3Solver.jl"))))
    include($(repr(joinpath(repo,"scripts/paper_a/G3EquivalentConditioning.jl"))))
    const N=NativeG3Solver
    sha_file(p)=bytes2hex(sha256(read(p)))
    const criterion="G3"
    const native_backend=:gurobi
    const equivalent_conditioning=true
    const objective_divisor=8192.
    params=Dict{String,Any}()
    model=JuMP.Model()
    JuMP.@variable(model,0<=z<=3,Int)
    discrete=[z]
    JuMP.@variable(model,0<=capacity<=2.0^20)
    JuMP.@constraint(model,z+capacity/1024.0 >= 2.0)
    original_objective=1e8*z+100.0*capacity+123.25
    profile=Dict{String,Any}()
    """
    Base.include_string(fresh,preamble*body,joinpath(repo,"scripts/paper_a/top_level_scope_fixture.jl"))
    @test fresh.profile["status"]=="PROFILE_READY"
    @test fresh.conditioned_copy!==nothing
    @test fresh.conditioned_copy.model!==fresh.model
    @test fresh.conditioned_copy.exponents[fresh.z]==0
    @test fresh.conditioned_copy.exponents[fresh.capacity]==7
    @test fresh.N.input_range(fresh.conditioned_copy.model)==fresh.profile["conditioned_input_range"]
    @test fresh.N.input_range(fresh.model)!=fresh.profile["conditioned_input_range"]
    old_scope=Module(:G3OldTryScopeRegression)
    oldbody=replace(body,"global conditioned_copy="=>"conditioned_copy=")
    scope_error=try
        Base.include_string(old_scope,preamble*oldbody,joinpath(repo,"scripts/paper_a/old_scope_fixture.jl"))
        nothing
    catch e
        e
    end
    @test scope_error isa LoadError
    @test occursin("Conditioned copy missing",sprint(showerror,scope_error))
    # Execute the actual preopt identity/range guard, without attaching a
    # backend or calling optimize! in any variant.
    selection="        solver_model=conditioned_copy===nothing ? model : conditioned_copy.model\n"
    finish="        JuMP.set_optimizer(solver_model,opt)"
    @test length(findall(selection,runner))==length(findall(finish,runner))==1
    guard=selection*split(split(runner,selection)[2],finish)[1]
    Base.include_string(fresh,guard,"actual_preopt_guard")
    @test fresh.solver_model===fresh.conditioned_copy.model
    expected=fresh.profile["conditioned_input_range"]
    fresh.profile["conditioned_input_range"]=fresh.N.input_range(fresh.model)
    @test_throws LoadError Base.include_string(fresh,guard,"negative_actual_range_mismatch")
    fresh.profile["conditioned_input_range"]=expected
    Base.include_string(fresh,"conditioned_copy=nothing","negative_missing_copy")
    @test_throws LoadError Base.include_string(fresh,guard,"negative_preopt_guard")
end
end
