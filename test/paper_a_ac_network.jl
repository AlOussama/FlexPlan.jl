using Test, JuMP
import FlexPlan as _FP, PowerModels as _PM, Clarabel, HiGHS
# Running this file directly also exercises the licensed mixed-integer backend.
const _AC_TEST_GUROBI = abspath(PROGRAM_FILE) == @__FILE__
if _AC_TEST_GUROBI
    import Gurobi
    include("uc_gscr_block_test_utils.jl")
    include("paper_a_fixtures.jl")
end

function _ac_network_fixture()
    data = _ap2_fixture()
    for sn in values(data["nw"])
        for table in ("gen", "storage"), device in values(sn[table])
            device["terminal_rating_block_MVA"] = device["S_block_MVA"]
            device["terminal_pq_halfspaces"] = [[0., 1., 0.4]]
        end
        # Demand at the far bus exercises both branch flows on the lossless two-bus case.
        sn["load"]["1"]["load_bus"] = 2
        sn["load"]["1"]["qd"] = 0.005
    end
    _FP.scale_paper_a_costs!(data)
    return data
end

function _ac_network_model(data, T; template=_ap2_template())
    _PM.instantiate_model(data, T, pm -> _FP.build_paper_a_ac_network(pm; template);
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!,
            (r,d) -> _FP.ref_add_uc_gscr_block!(r,d; paper_a_validation_scope=template.paper_a_validation_scope)])
end

@testset "Online Q box preserves branch ratings and drops device MVA circles" begin
    data = _ac_network_fixture()
    rated = _ac_network_model(data, _PM.LPACCPowerModel)
    data["paper_a_ac_terminal_policy"] = "online_q_box"
    for sn in values(data["nw"]), table in ("gen", "storage"), d in values(sn[table])
        delete!(d, "terminal_rating_block_MVA")
        delete!(d, "terminal_pq_halfspaces")
        d["q_block_max"] = 0.4*d["p_block_max"]
        d["q_block_min"] = -d["q_block_max"]
    end
    pm = _ac_network_model(data, _PM.LPACCPowerModel)
    block_hours = 0
    for n in _FP.nw_ids(pm), key in _FP._uc_gscr_block_all_device_keys(pm,n)
        block_hours += 1
        lo,hi = _PM.con(pm,n,:uc_gscr_block_reactive_dispatch_bounds,key)
        na = _PM.var(pm,n,:na_block,key)
        q = _FP._uc_gscr_block_dispatch_variable(pm,n,key,:q)
        cap = 0.4*_PM.ref(pm,n,key...)["p_block_max"]
        @test JuMP.normalized_coefficient(lo,na) ≈ cap
        @test JuMP.normalized_coefficient(hi,na) ≈ -cap
        @test JuMP.normalized_coefficient(lo,q) == JuMP.normalized_coefficient(hi,q) == 1
    end
    @test JuMP.num_constraints(rated.model,Vector{JuMP.AffExpr},JuMP.MOI.SecondOrderCone) -
          JuMP.num_constraints(pm.model,Vector{JuMP.AffExpr},JuMP.MOI.SecondOrderCone) == block_hours
    @test JuMP.num_constraints(rated.model,JuMP.QuadExpr,JuMP.MOI.LessThan{Float64}) ==
          JuMP.num_constraints(pm.model,JuMP.QuadExpr,JuMP.MOI.LessThan{Float64})
end

@testset "Paper-A P/Q network and unchanged strength rows" begin
    data = _ac_network_fixture()
    dc = _ap2_solve!(_ap2_model(data))
    @test !haskey(_PM.var(dc, 1), :qg)
    for T in (_PM.LPACCPowerModel, _PM.SOCWRPowerModel, _PM.QCRMPowerModel)
        pm = _ac_network_model(data, T)
        for n in _FP.nw_ids(pm)
            rows = _PM.con(pm, n, :gscr_gershgorin_sufficient)
            for (region, dcrow) in _PM.con(dc, n, :gscr_gershgorin_sufficient)
                @test string(JuMP.constraint_object(rows[region])) == string(JuMP.constraint_object(dcrow))
            end
            qrow = _PM.con(pm, n, :uc_gscr_block_bus_reactive_balance, 2)
            @test JuMP.normalized_rhs(qrow) ≈ -0.005
        end
        _AC_TEST_GUROBI || continue
        JuMP.set_optimizer(pm.model, Gurobi.Optimizer)
        JuMP.set_silent(pm.model)
        JuMP.optimize!(pm.model)
        @test JuMP.termination_status(pm.model) == JuMP.MOI.OPTIMAL
        @test JuMP.primal_status(pm.model) == JuMP.MOI.FEASIBLE_POINT
        for n in _FP.nw_ids(pm)
            @test JuMP.value(_PM.var(pm,n,:p,(1,2,1))) ≈ -0.4 atol=2e-6
            @test JuMP.value(_PM.var(pm,n,:q,(1,2,1))) ≈ -0.005 atol=2e-6
            for key in _FP._uc_gscr_block_all_device_keys(pm,n)
                p = JuMP.value(_FP._uc_gscr_block_dispatch_variable(pm,n,key,:p))
                q = JuMP.value(_FP._uc_gscr_block_dispatch_variable(pm,n,key,:q))
                dev = _PM.ref(pm,n,key...)
                limit = dev["terminal_rating_block_MVA"] / data["baseMVA"] * JuMP.value(_PM.var(pm,n,:na_block,key))
                @test hypot(p,q) <= limit + 2e-6
            end
        end
    end
    invalid = deepcopy(data)
    delete!(invalid["nw"]["1"]["gen"]["1"], "terminal_rating_block_MVA")
    @test_throws ArgumentError _ac_network_model(invalid, _PM.LPACCPowerModel)
    invalid = deepcopy(data)
    invalid["nw"]["1"]["storage"]["1"]["x"] = 0.01
    @test_throws ArgumentError _ac_network_model(invalid, _PM.SOCWRPowerModel)
end

@testset "Paper-A strength selection and P/Q solve entry" begin
    data = _ac_network_fixture()
    methods = (
        ("G0", _FP.ExactPSDGSCR()),
        ("G2", _FP.FixedScalingGSCR([1.,1.]; provenance="synthetic")),
        ("G3", _FP.ExactEdgeSOCGSCR()),
        ("M1", _FP.InverseBoundGSCR([10.5 -10.; -10. 10.]; provenance="synthetic")),
        ("M2", _FP.InteractionGSCR([1. 0.2; 0.1 1.]; provenance="synthetic")),
    )
    for T in (_PM.LPACCPowerModel, _PM.SOCWRPowerModel, _PM.QCRMPowerModel)
        for (kind, method) in methods
            pm = _ac_network_model(data, T; template=_ap2_template(; gscr=method))
            @test all(c.kind == kind for c in values(pm.ext[:paper_a_certificates]))
        end
        # The remote load has no local generation or shunt. Its reactive
        # demand alone now exceeds the receiving-end branch MVA limit.
        _AC_TEST_GUROBI || continue
        overload = deepcopy(data)
        overload["nw"]["1"]["load"]["1"]["qd"] = 3.0
        result = _FP.paper_a_ac_network(overload, T,
            JuMP.optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag"=>0, "DualReductions"=>0);
            template=_ap2_template())
        @test result["termination_status"] == JuMP.MOI.INFEASIBLE
    end
end

@testset "Conic AC network, G0 and candidate storage" begin
    data = _ac_network_fixture()
    for sn in values(data["nw"])
        storage = pop!(sn["storage"], "1")
        storage["n0"] = storage["na0"] = 0
        storage["energy"] = 0.
        storage["nmax"] = 2
        sn["ne_storage"]["1"] = storage
    end
    tpl = _ap2_template(; gscr=_FP.ExactPSDGSCR())
    tpl.carrier_formulations[(:ne_storage,"GFM")] = _FP.BlockStorageParticipation()
    result = _FP.paper_a_ac_network(data, _PM.SOCWRConicPowerModel,
        JuMP.optimizer_with_attributes(Clarabel.Optimizer, "verbose"=>false);
        template=tpl, build_options=(; relax_block_variables=true))
    @test result["termination_status"] == JuMP.MOI.OPTIMAL
    @test result["primal_status"] == JuMP.MOI.FEASIBLE_POINT
    pm = _ac_network_model(data, _PM.SOCWRConicPowerModel; template=tpl)
    for (row, var) in ((:uc_gscr_block_bus_active_balance,:ps_ne),
                       (:uc_gscr_block_bus_reactive_balance,:qs_ne))
        @test JuMP.normalized_coefficient(_PM.con(pm,1,row,1), _PM.var(pm,1,var,1)) == 1.
    end
end
