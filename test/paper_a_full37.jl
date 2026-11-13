function _full37_selector!(device,mode,minimum)
    device["paper_a_full37_online"]=Dict("mode"=>mode,"strength_minimum_pu"=>minimum)
    return device
end

function _full37_fixture(;hours=3)
    d=_carrier_fixture(;hours)
    spec=Dict{String,Any}(key=>bytes2hex(_FP.SHA.sha256(key)) for (key,_) in _FP._PAPER_A_FULL37_PINS)
    spec["schema"]="paper_a_full37_frozen_v1"
    spec["variant"]=Dict("battery_mode"=>"GFM_ONLY","bess_duration_h"=>4,"bess_gfm_premium"=>0.2,
        "dc_construction_mode"=>"REFERENCE_2040","formulation"=>"G1","alpha"=>0.5,"hours"=>8760)
    spec["variant_sha256"]=_FP._paper_a_full37_variant_digest(spec["variant"])
    d["paper_a_extension"]["full37_specification"]=spec
    for (t,sn) in d["nw"]
        sn["paper_a_extension"]=deepcopy(d["paper_a_extension"])
        sn["g_min"]=0.5
        !haskey(sn["load"]["1"],"flex") || delete!(sn["load"]["1"],"flex")
        if t=="3"
            sn["gen"]["1"]["a_res"]=0.0
        end
        biomass=deepcopy(sn["gen"]["2"])
        delete!(biomass,"paper_a_carrier_uc")
        biomass["index"]=4
        biomass["name"]="synthetic biomass"
        biomass["carrier"]="biomass"
        biomass["committable"]=false
        biomass["p_min_pu"]=0.0
        biomass["a_res"]=t=="2" ? 0.25 : 1.0
        biomass["nmax"]=biomass["n0"]
        biomass["paper_a_block_capacity"]["original_p_nom_max_MW"]=biomass["n0"]*biomass["p_block_max_MW"]
        sn["gen"]["4"]=_full37_selector!(biomass,"SELECTIVE_SYN",0.5)

        existing=sn["storage"]["1"]
        existing["paper_a_storage_unit"]["cyclic_state_of_charge"]=true
        existing["paper_a_storage_unit"]["state_of_charge_initial_MWh"]=nothing
        existing["energy"]=0.0
        candidate=pop!(sn["storage"],"7")
        sn["ne_storage"]["7"]=candidate
        for battery in (existing,candidate)
            battery["paper_a_annual_cyclic"]=true
            battery["b_block"]=battery["mu_str"]=battery["mu_fl"]=0.0
            delete!(battery,"x_src")
            battery["source_equivalent_valid"]=false
            _full37_selector!(battery,"GFM_ZERO_STRENGTH",0.0)
        end
        phs=deepcopy(existing)
        for key in ("paper_a_annual_cyclic","paper_a_bess_cost","max_energy_absorption")
            pop!(phs,key,nothing)
        end
        merge!(phs,Dict("index"=>8,"name"=>"synthetic modelled PHS","carrier"=>"PHS","source_class"=>"SYN",
            "grid_control_mode"=>"not_applicable","e_block"=>0.1,"energy_rating"=>0.2,
            "charge_rating"=>0.2,"discharge_rating"=>0.2,"n0"=>2,"nmax"=>2,"na0"=>0,
            "mu_str"=>1.0,"x_src"=>0.2,"b_block"=>0.5,"source_equivalent_valid"=>true))
        merge!(phs["paper_a_storage_unit"],Dict("p_nom_MW"=>50.0,"max_hours"=>1.0))
        sn["storage"]["8"]=_full37_selector!(phs,"PHS_SYN",0.2)
    end
    return d
end

function _full37_model(d;gscr=_FP.GershgorinGSCR(),biomass_form=_FP.BlockRenewableParticipation(),objective=false)
    template=_FP.UCGSCRBlockTemplate(Dict(
        (:gen,"GFL")=>_FP.BlockRenewableParticipation(),(:gen,"CCGT")=>_FP.BlockThermalCommitment(),
        (:gen,"OCGT")=>_FP.BlockThermalCommitment(),(:gen,"biomass")=>biomass_form,
        (:storage,"BESS-GFM")=>_FP.BlockStorageParticipation(),(:ne_storage,"BESS-GFM")=>_FP.BlockStorageParticipation(),
        (:storage,"PHS")=>_FP.BlockStorageParticipation()),gscr;
        paper_a_validation_scope=:synthetic_regression,storage_cost_policy=:discharge)
    return _ap2_model(d;template,objective)
end

@testset "Full37 reservoir dispatch without blocks and oil minimum" begin
    d=_full37_fixture()
    spec=d["paper_a_extension"]["full37_specification"]
    spec["dispatch_policy"]=_FP._PAPER_A_FULL37_DISPATCH_POLICY
    for sn in values(d["nw"])
        sn["paper_a_extension"]["full37_specification"]["dispatch_policy"]=spec["dispatch_policy"]
        sn["storage"]["9"]=Dict{String,Any}(
            "name"=>"synthetic reservoir","carrier"=>"hydro","index"=>9,"storage_bus"=>1,"status"=>1,
            "energy"=>0.,"energy_rating"=>.8,"charge_rating"=>0.,"discharge_rating"=>.2*nextfloat(1.),
            "charge_efficiency"=>0.,"discharge_efficiency"=>.8,"stationary_energy_inflow"=>.01,
            "stationary_energy_outflow"=>0.,"self_discharge_rate"=>0.,"thermal_rating"=>.2*nextfloat(1.),
            "r"=>0.,"x"=>0.,"qmin"=>0.,"qmax"=>0.,"p_loss"=>0.,"q_loss"=>0.,"marginal_cost"=>7.,
            "paper_a_storage_unit"=>Dict("p_nom_MW"=>50.,"max_hours"=>4.,"p_min_pu"=>0.,"p_max_pu"=>nextfloat(1.),
                "cyclic_state_of_charge"=>true,"state_of_charge_initial_MWh"=>nothing,
                "inflow_MW"=>2.5,"inflow_unit"=>"MW","standing_loss"=>0.,"efficiency_store"=>0.,"efficiency_dispatch"=>.8))
        oil=sn["gen"]["4"]
        oil["carrier"]="oil"
        oil["p_min_pu"]=.38
        oil["p_min_pu_source"]="owner_coal_proxy"
        oil["a_res"]=1.
        oil["p_max_pu"]=1.
        oil["paper_a_full37_online"]["strength_minimum_pu"]=.2
    end
    bad=deepcopy(d)
    bad["nw"]["2"]["gen"]["4"]["p_min_pu"]=.5
    @test_throws ArgumentError _ap2_expansion_prepared(bad)
    bad=deepcopy(d)
    bad["nw"]["2"]["storage"]["9"]["n0"]=1
    @test_throws ArgumentError _ap2_expansion_prepared(bad)
    template=_FP.UCGSCRBlockTemplate(Dict(
        (:gen,"GFL")=>_FP.BlockRenewableParticipation(),(:gen,"CCGT")=>_FP.BlockThermalCommitment(),
        (:gen,"OCGT")=>_FP.BlockThermalCommitment(),(:gen,"oil")=>_FP.BlockRenewableParticipation(),
        (:storage,"BESS-GFM")=>_FP.BlockStorageParticipation(),(:ne_storage,"BESS-GFM")=>_FP.BlockStorageParticipation(),
        (:storage,"PHS")=>_FP.BlockStorageParticipation()),_FP.GershgorinGSCR();
        paper_a_validation_scope=:synthetic_regression,storage_cost_policy=:discharge)
    pm=_ap2_model(_ap2_expansion_prepared(d);template,objective=true)
    @test !haskey(_PM.ref(pm,1,:paper_a_coefficients),(:storage,9))
    @test !((:storage,9) in axes(_PM.var(pm,1,:n_block),1))
    @test !haskey(_PM.var(pm,1,:paper_a_strength_blocks),(:storage,9))
    @test !((:gen,4) in axes(_PM.var(pm,1,:su_block),1))
    @test JuMP.upper_bound(_PM.var(pm,1,:sc,9))==0
    @test JuMP.upper_bound(_PM.var(pm,1,:sd,9))==.2*nextfloat(1.)
    @test JuMP.coefficient(JuMP.objective_function(pm.model),_PM.var(pm,1,:sd,9))==7*250
    lower=first(_PM.con(pm,1,:uc_gscr_block_active_dispatch_bounds)[(:gen,4)])
    @test JuMP.normalized_coefficient(lower,_PM.var(pm,1,:na_block,(:gen,4))) ≈ -.38*_PM.ref(pm,1,:gen,4)["p_block_max"]
    for t in 1:3
        JuMP.fix(_PM.var(pm,t,:sd,9),t==3 ? .024 : 0.;force=true)
        JuMP.fix(_PM.var(pm,t,:paper_a_storage_spill,9),0.;force=true)
    end
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
    @test JuMP.value(_PM.var(pm,2,:se,9))-JuMP.value(_PM.var(pm,3,:se,9)) ≈ .02
end

@testset "Full37 thermal minimum-output time series takes precedence" begin
    d=_full37_fixture()
    for (t,pmin) in zip(1:3,(0.20,0.25,0.30))
        gen=d["nw"][string(t)]["gen"]["2"]
        gen["p_min_pu"]=pmin
        gen["paper_a_p_min_pu_time_series"]=true
    end
    pm=_full37_model(_ap2_expansion_prepared(deepcopy(d)))
    for (t,pmin) in zip(1:3,(0.20,0.25,0.30))
        active=_PM.var(pm,t,:na_block,(:gen,2))
        lower=first(_PM.con(pm,t,:uc_gscr_block_active_dispatch_bounds)[(:gen,2)])
        @test JuMP.normalized_coefficient(lower,active) ≈ -pmin*_PM.ref(pm,t,:gen,2)["p_block_max"]
    end
    bad=deepcopy(d)
    delete!(bad["nw"]["2"]["gen"]["2"],"paper_a_p_min_pu_time_series")
    @test_throws ArgumentError _ap2_expansion_prepared(bad)
    bad=deepcopy(d)
    bad["nw"]["2"]["gen"]["2"]["p_max_pu"]=0.1
    @test_throws ArgumentError _ap2_expansion_prepared(bad)
end

@testset "Full37 thermal boundary and qualified multiple-block event cost" begin
    d=_ap2_expansion_prepared(_full37_fixture(;hours=6))
    pm=_full37_model(d;objective=true)
    key=(:gen,2)
    JuMP.fix(_PM.var(pm,1,:n_block,key),2;force=true)
    for (t,n) in enumerate((2,2,2,2,1,1))
        JuMP.fix(_PM.var(pm,t,:na_block,key),n;force=true)
    end
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
    startup=_PM.var(pm,1,:su_block,key)
    shutdown=_PM.var(pm,5,:sd_block,key)
    @test JuMP.value(startup)≈2
    @test JuMP.value(shutdown)≈1
    objective=JuMP.objective_function(pm.model)
    @test sum(JuMP.value(v)*JuMP.coefficient(objective,v) for v in (startup,shutdown))≈3300.0
end

@testset "Full37 selector and cyclic storage contract" begin
    pm=_full37_model(_ap2_expansion_prepared(_full37_fixture()))
    active(t,k)=_PM.var(pm,t,:na_block,k)
    credit(t,k)=_PM.var(pm,t,:paper_a_strength_blocks,k)
    power(t,k)=_PM.var(pm,t,:paper_a_credited_power,k)
    pump(t,k)=_PM.var(pm,t,:paper_a_pump_blocks,k)
    biomass=(:gen,4)
    phs=(:storage,8)
    @test JuMP.is_integer(credit(1,biomass))
    @test JuMP.is_integer(credit(1,phs))
    @test JuMP.is_integer(pump(1,phs))
    @test pm.ext[:paper_a_online][1].B===pm.ext[:paper_a_online][1].M===nothing
    @test JuMP.coefficient(pm.ext[:paper_a_online][1].b_src[1],credit(1,biomass))>0
    @test JuMP.coefficient(pm.ext[:paper_a_online][1].b_src[1],active(1,biomass))==0
    @test JuMP.coefficient(pm.ext[:paper_a_online][1].b_src[1],credit(1,phs))≈0.5
    @test JuMP.coefficient(pm.ext[:paper_a_online][1].b_src[1],pump(1,phs))==0
    for key in ((:storage,1),(:ne_storage,7))
        @test JuMP.coefficient(pm.ext[:paper_a_online][1].b_src[1],active(1,key))==0
        @test JuMP.coefficient(pm.ext[:paper_a_online][1].S_diag[1],active(1,key))==0
    end

    # Separate native mode counts permit simultaneous but lossy gross operation.
    for (variable,value) in ((active(1,phs),2),(credit(1,phs),1),(pump(1,phs),1),
        (_PM.var(pm,1,:sd,8),5/250),(_PM.var(pm,1,:sc,8),5/(0.9^2*250)))
        JuMP.fix(variable,value;force=true)
    end
    JuMP.fix(active(1,biomass),2;force=true)
    JuMP.fix(credit(1,biomass),1;force=true)
    JuMP.fix(power(1,biomass),12.5/250;force=true)
    JuMP.fix(_PM.var(pm,1,:pg,4),20/250;force=true)
    JuMP.fix(_PM.var(pm,2,:pg,4),5/250;force=true)
    JuMP.fix(active(3,(:gen,1)),1;force=true)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
    @test JuMP.value(credit(2,biomass))≈0
    @test JuMP.value(_PM.var(pm,3,:pg,1))≈0
    @test JuMP.coefficient(pm.ext[:paper_a_online][3].S_diag[1],active(3,(:gen,1)))≈0.16
    @test JuMP.value(_PM.var(pm,1,:se,8))≈JuMP.value(_PM.var(pm,3,:se,8))
    JuMP.fix(credit(2,biomass),1;force=true)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.INFEASIBLE
    JuMP.fix(credit(2,biomass),0;force=true)
    JuMP.fix(power(1,biomass),26/250;force=true)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.INFEASIBLE
    JuMP.fix(power(1,biomass),12.5/250;force=true)
    JuMP.fix(active(1,phs),1;force=true)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.INFEASIBLE

    # Candidate E_T is the input of hour 1, so nonzero first charging increases E_1.
    fresh=_full37_model(_ap2_expansion_prepared(_full37_fixture()))
    JuMP.fix(_PM.var(fresh,1,:n_block,(:ne_storage,7)),1;force=true)
    JuMP.fix(_PM.var(fresh,1,:sc_ne,7),5/250;force=true)
    JuMP.fix(_PM.var(fresh,1,:sd_ne,7),0;force=true)
    @test _ap2_expansion_solve!(fresh)==JuMP.MOI.OPTIMAL
    @test JuMP.value(_PM.var(fresh,1,:se_ne,7))-JuMP.value(_PM.var(fresh,3,:se_ne,7))≈4.5/250
end

@testset "Full37 rejects broken source binding" begin
    mutated=_full37_fixture()
    delete!(mutated["nw"]["2"]["gen"]["4"],"paper_a_full37_online")
    @test_throws ArgumentError _ap2_expansion_prepared(mutated)
    wrong_alpha=_full37_fixture()
    wrong_alpha["nw"]["2"]["g_min"]=1.0
    @test_throws ArgumentError _ap2_expansion_prepared(wrong_alpha)
    no_cycle=_full37_fixture()
    no_cycle["nw"]["2"]["ne_storage"]["7"]["paper_a_annual_cyclic"]=false
    @test_throws ArgumentError _ap2_expansion_prepared(no_cycle)
    wrong_pin=_full37_fixture()
    for sn in [wrong_pin;collect(values(wrong_pin["nw"]))]
        _FP._paper_a_full37(sn)["online_selector_sha256"]=Dict(_FP._PAPER_A_FULL37_PINS)["online_selector_sha256"]
    end
    @test_throws ArgumentError _ap2_expansion_prepared(wrong_pin)
    wrong_g2=_full37_fixture()
    for sn in [wrong_g2;collect(values(wrong_g2["nw"]))]
        spec=_FP._paper_a_full37(sn)
        spec["g2_r"]=[1.0,2.0]
        spec["g2_r_sha256"]="92804d711119cb0af0cd768232bc3186ef68c29bcbe48976d2894f469102f9f7"
        spec["g2_bus_order"]=["A","B"]
    end
    @test_throws ArgumentError _ap2_expansion_prepared(wrong_g2)
    curtailment=_full37_fixture()
    curtailment["nw"]["2"]["gen"]["1"]["cost_curt"]=1
    @test_throws ArgumentError _ap2_expansion_prepared(curtailment)
    wrong_role=_ap2_expansion_prepared(_full37_fixture())
    @test_throws ArgumentError _full37_model(wrong_role;biomass_form=_FP.BlockFixedInstalled())
    @test_throws ArgumentError _full37_model(wrong_role;gscr=_FP.NoGSCR())
    invalid_gfm=_full37_fixture()
    invalid_gfm["nw"]["1"]["storage"]["1"]["x_src"]=0.2
    @test_throws ArgumentError _full37_model(_ap2_expansion_prepared(invalid_gfm))
end

@testset "Independent Full37 reconstruction consumes gross mode and credit evidence" begin
    raw=_full37_fixture()
    snapshot=raw["nw"]["1"]
    assets=Dict{String,Any}()
    for table in ("gen","storage","ne_storage"), (id,dev) in snapshot[table]
        assets["$table:$id"]=Dict{String,Any}("online"=>0,"installed"=>dev["n0"],"dispatch_MW"=>0.0,
            "strength_blocks"=>0,"pump_blocks"=>0,"credited_dispatch_MW"=>0.0,"charge_MW"=>0.0)
    end
    merge!(assets["gen:4"],Dict("online"=>2,"strength_blocks"=>1,"credited_dispatch_MW"=>12.5,"dispatch_MW"=>20.0))
    merge!(assets["storage:8"],Dict("online"=>2,"strength_blocks"=>1,"pump_blocks"=>1,
        "dispatch_MW"=>5.0,"charge_MW"=>5/0.9^2))
    merge!(assets["ne_storage:7"],Dict("online"=>1,"installed"=>1))
    result=Dict("snapshots"=>Dict("1"=>Dict("assets"=>assets)))
    rec=_FP.PaperADiagnostics.reconstruct(raw,result,1)
    @test rec["online_selector_violation"]==0
    @test rec["b_src"][1]≈1.25
    @test rec["p"]==[0.0,0.0]
    @test only(r for r in rec["source_ledger"] if r["asset"]=="ne_storage:7")["class"]=="GFM"
    assets["gen:4"]["credited_dispatch_MW"]=12.0
    @test _FP.PaperADiagnostics.reconstruct(raw,result,1)["online_selector_violation"]≈0.5/250
end
