using Test
include(joinpath(ARGS[1],"scripts","paper_a","AP3Pipeline.jl"))
@testset "EXEC-UNIT-001 export units" begin
    @test AP3Pipeline.metric_unit("A.connection_violation","pu")=="count_or_index"
    @test AP3Pipeline.metric_unit("B.G3_edges_complete","pu")=="boolean"
    @test AP3Pipeline.metric_unit("B.G3_valid","pu")=="boolean"
    @test AP3Pipeline.metric_unit("B.G3_cone_product_slacks","pu")=="pu_admittance_squared"
end
