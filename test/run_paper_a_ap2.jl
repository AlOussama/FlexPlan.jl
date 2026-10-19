# Executable grouped AP2 target; full legacy coverage remains in runtests.jl.
using Test,JuMP
import FlexPlan as _FP
import PowerModels as _PM
import InfrastructureModels as _IM
import HiGHS
const milp_optimizer=_FP.optimizer_with_attributes(HiGHS.Optimizer,"output_flag"=>false)
include("uc_gscr_block_test_utils.jl")
include("paper_a_fixtures.jl")
@testset "Paper A AP2" begin
    include("paper_a_regional.jl")
    include("paper_a_integration.jl")
end
