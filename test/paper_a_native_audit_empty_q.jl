module NativeAuditEmptyQTests
using Test, JuMP
import Gurobi
include("../scripts/paper_a/G3ConditioningAudit.jl")
const A=G3ConditioningAudit
@testset "Zero-Q native MIP audit and start-only metadata" begin
    m=Model(Gurobi.Optimizer);set_silent(m)
    @variable(m,0<=x<=5,Int);@constraint(m,x<=4);@objective(m,Min,x)
    JuMP.MOI.Utilities.attach_optimizer(backend(m))
    native=unsafe_backend(m);@test Gurobi.GRBupdatemodel(native)==0
    mktempdir() do folder
        before=A.native_dump(m,joinpath(folder,"before.json"))
        @test before["quadratics"]==0 && isempty(before["quadratic_rhs"])
        set_start_value(x,3.)
        @test Gurobi.GRBupdatemodel(native)==0
        after=A.native_dump(m,joinpath(folder,"after.json"))
        @test before==after
        start=zeros(1);@test Gurobi.GRBgetdblattrarray(native,"Start",0,1,start)==0
        @test only(start)==3.
        kind=zeros(Cchar,1);@test Gurobi.GRBgetcharattrarray(native,"VType",0,1,kind)==0
        @test Char(only(kind))=='I'
        @test termination_status(m)==JuMP.MOI.OPTIMIZE_NOT_CALLED
    end
end
end
