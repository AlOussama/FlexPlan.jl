using Test, JuMP, Gurobi
include(joinpath(@__DIR__, "..", "scripts", "paper_a", "WeekPortfolioStart.jl"))

@testset "Accepted LP portfolio hint preserves the integer model" begin
    for (cap, expected) in [(3.0, 2.0), (1.75, 1.0)]
        model = Model(Gurobi.Optimizer)
        set_silent(model)
        @variable(model, 0 <= blocks <= 3, Int, start=0)
        @variable(model, 0 <= existing <= 0, Int)
        @variable(model, 0 <= renewable <= 10)
        @variable(model, 0 <= operation <= 3, Int, start=3)
        limit = @constraint(model, blocks + existing <= cap)
        @constraint(model, operation >= 1)
        @objective(model, Min, 7blocks + renewable)
        bounds = all_constraints(model; include_variable_in_set_constraints=true)
        obj = objective_function(model)
        assets = Dict("a"=>blocks, "fixed"=>existing)
        projects = Dict("wind"=>renewable)
        seed = Dict("installed_blocks"=>Dict("a"=>1.5,"fixed"=>0.), "renewable_capacity"=>Dict("wind"=>2.25))
        hint = WeekPortfolioStart.capacity_start!(model, assets, projects, [limit], seed)
        @test hint.cleared == 2 && hint.use_ceiling == (cap == 3)
        @test hint.starts == Dict(blocks=>expected, renewable=>2.25)
        @test start_value(operation) === nothing && start_value(existing) === nothing
        @test all_constraints(model; include_variable_in_set_constraints=true) == bounds
        @test isequal_canonical(objective_function(model), obj)
        JuMP.MOI.Utilities.attach_optimizer(backend(model))
        @test WeekPortfolioStart.verify_capacity_start(unsafe_backend(model), hint.starts) == 2
        @test_throws ErrorException WeekPortfolioStart.verify_capacity_start(unsafe_backend(model), Dict(blocks=>0.))
        seed["installed_blocks"]["a"] = -0.1
        @test_throws ErrorException WeekPortfolioStart.capacity_start!(model, assets, projects, [limit], seed)
        delete!(seed["installed_blocks"],"a")
        @test_throws ErrorException WeekPortfolioStart.capacity_start!(model, assets, projects, [limit], seed)
    end
end
