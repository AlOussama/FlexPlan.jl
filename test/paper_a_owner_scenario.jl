_owner_marker(data)=data["paper_a_extension"]["owner_scenario"]

function _owner_bess_price!(dev,duration,premium)
    power=19758.59100216229
    energy=10128.316776565933
    cost=(1+premium)*(power+duration*energy)
    dev["cost_inv_per_mw"]=cost
    dev["paper_a_bess_cost"]=Dict{String,Any}("duration_h"=>duration,"gfm_premium"=>premium,
        "power_cost_per_mw_year"=>power,"energy_cost_per_mwh_year"=>energy,
        "cost_per_mw_year"=>cost,"source"=>"frozen_2040_EUR2025_P_plus_E")
end

function _owner_fixture(;phs_mode="MAIN",dc_mode="REFERENCE_2040",bess_hours=4,hours=3)
    data=_ap2_expansion_fixture(;hours)
    main=phs_mode=="MAIN"
    dc_off=dc_mode=="CONSTRUCTION_OFF"
    names=["synthetic PHS $i" for i in 1:5]
    data["paper_a_extension"]["owner_scenario"]=Dict{String,Any}(
        "id"=>"PAPER_A_OWNER_DKGPUN_V1","phs_mode"=>phs_mode,"phs_assets"=>names,
        "phs_roster"=>Dict(name=>Dict{String,Any}("bus"=>"A","carrier"=>"PHS","p_nom_MW"=>25.0,
            "native_max_hours"=>0.0,"effective_max_hours"=>main ? nothing : 3.0,
            "effective_energy_MWh"=>main ? nothing : 75.0,"fixed_E0_MWh"=>nothing,
            "disposition"=>main ? "PHS_STORAGE_OPERATION_EXCLUDED_IN_MAIN_CASE" : phs_mode) for name in names),
        "bess_duration_h"=>bess_hours,"bess_gfm_premium"=>0.2,"dc_construction_mode"=>dc_mode,
        "uc_tariff_mode"=>"QUALIFIED_NATIVE","source_snapshot_count"=>hours)
    main || (data["paper_a_extension"]["storage_duration_overrides"]=Dict(name=>Dict("effective_max_hours"=>3) for name in names))
    for sn in values(data["nw"])
        for (id,na0,min_time,unit,start,stop) in (("2",1,2,"EUR_per_block_event",200.0,75.0),
                                                  ("3",0,0,"EUR_per_generator_event",120.0,30.0))
            dev=sn["gen"][id]
            dev["na0"]=Float64(na0)
            id=="3" && (dev["nmax"]=1)
            dev["min_up_block_time"]=dev["min_down_block_time"]=min_time
            dev["committable"]=true
            p=dev["p_block_max_MW"]
            dev["paper_a_native_uc"]=Dict{String,Any}(
                "generator_id"=>dev["name"],"carrier"=>dev["carrier"],"block_id"=>"synthetic-$id",
                "P_block_MW"=>p,"startup_original_value"=>start,"shutdown_original_value"=>stop,
                "startup_unit"=>unit,"shutdown_unit"=>unit,"original_currency"=>"EUR",
                "original_price_year"=>2018,"factor_to_EUR2025"=>1.25,"evidence_sha256"=>repeat("a",64),
                "na0"=>na0,"min_up_block_time"=>min_time,"min_down_block_time"=>min_time,
                "prior_uptime_h"=>Int(na0>0),"prior_downtime_h"=>1)
            dev["startup_cost_per_mw"]=1.25*start/p
            dev["shutdown_cost_per_mw"]=1.25*stop/p
        end
        dc=sn["dcline"]["1"]
        dc["name"]="synthetic under construction"
        dc["paper_a_native_dc"]=Dict{String,Any}(
            "p_nom_MW"=>50.0,"under_construction"=>true,"native_active"=>true,"native_status"=>true,
            "native_availability"=>1.0,"effective_availability"=>dc_off ? 0.0 : 1.0,
            "p_min_pu"=>-0.6,"p_max_pu"=>1.0,"construction_mode"=>dc_mode,"native_efficiency"=>0.95)
        lo,hi=dc_off ? (0.0,0.0) : (-0.12,0.2)
        for (field,value) in (("pminf",lo),("pmaxf",hi),("pmint",-hi),("pmaxt",-lo),("br_status",Int(!dc_off)))
            dc[field]=value
        end
        zero=deepcopy(dc)
        zero["index"]=2
        zero["name"]="synthetic zero rating"
        zero["br_status"]=1
        for field in ("pminf","pmaxf","pmint","pmaxt");zero[field]=0.0;end
        merge!(zero["paper_a_native_dc"],Dict("p_nom_MW"=>0.0,"under_construction"=>false,"effective_availability"=>1.0))
        sn["dcline"]["2"]=zero

        battery=sn["storage"]["1"]
        merge!(battery,Dict("energy_rating"=>0.4,"charge_efficiency"=>0.9,"discharge_efficiency"=>0.9))
        battery["paper_a_storage_unit"]=Dict{String,Any}("p_nom_MW"=>25.0,"max_hours"=>4.0,
            "cyclic_state_of_charge"=>false,"state_of_charge_initial_MWh"=>75.0,"p_min_pu"=>-1.0,
            "p_max_pu"=>1.0,"inflow_MW"=>0.0,"inflow_unit"=>"MW","standing_loss"=>0.0,
            "efficiency_store"=>0.9,"efficiency_dispatch"=>0.9)
        _owner_bess_price!(battery,4,0.2)
        candidate=deepcopy(battery)
        delete!(candidate,"paper_a_storage_unit")
        merge!(candidate,Dict{String,Any}("index"=>7,"name"=>"synthetic GFM candidate","n0"=>0,"na0"=>0,
            "e_block"=>0.1*bess_hours,"energy_rating"=>0.0,"energy"=>0.0,"candidate_added_by_converter"=>true))
        _owner_bess_price!(candidate,bess_hours,0.2)
        sn["storage"]["7"]=candidate

        if !main
            dev=deepcopy(sn["storage"]["1"])
            delete!(dev,"paper_a_bess_cost")
            merge!(dev,Dict{String,Any}("index"=>2,"name"=>first(names),"carrier"=>"PHS","status"=>1,
                "source_class"=>"SYN","grid_control_mode"=>"not_applicable","n0"=>1,"nmax"=>1,"na0"=>1,
                "energy"=>0.0,"energy_rating"=>0.3,"e_block"=>0.3,"charge_rating"=>0.1,"discharge_rating"=>0.1,
                "stationary_energy_inflow"=>0.004,"stationary_energy_outflow"=>0.0,
                "charge_efficiency"=>0.9,"discharge_efficiency"=>0.9,"self_discharge_rate"=>0.0))
            dev["paper_a_storage_unit"]=Dict{String,Any}("p_nom_MW"=>25.0,"max_hours"=>3.0,
                "cyclic_state_of_charge"=>true,"state_of_charge_initial_MWh"=>nothing,"p_min_pu"=>-1.0,
                "p_max_pu"=>1.0,"inflow_MW"=>1.0,"inflow_unit"=>"MW","standing_loss"=>0.0,
                "efficiency_store"=>0.9,"efficiency_dispatch"=>0.9)
            for (i,name) in enumerate(names)
                sn["storage"][string(i+1)]=merge(deepcopy(dev),Dict("index"=>i+1,"name"=>name))
            end
        end
    end
    return data
end

function _owner_model(data;device_formulations=Dict(),kwargs...)
    template=_FP.UCGSCRBlockTemplate(Dict(
        (:gen,"GFL")=>_FP.BlockRenewableParticipation(),
        (:gen,"CCGT")=>_FP.BlockThermalCommitment(),
        (:gen,"OCGT")=>_FP.BlockThermalCommitment(),
        (:storage,"BESS-GFM")=>_FP.BlockStorageParticipation(),
        (:ne_storage,"BESS-GFM")=>_FP.BlockStorageParticipation(),
        (:storage,"PHS")=>_FP.BlockStorageParticipation()),_FP.NoGSCR();
        device_formulations,paper_a_validation_scope=:synthetic_regression)
    return _ap2_model(data;template,kwargs...)
end

@testset "Owner scenario qualified native UC" begin
    data=_ap2_expansion_prepared(_owner_fixture())
    pm=_owner_model(data)
    ccgt,ocgt=(:gen,2),(:gen,3)
    x=_PM.var(pm,1,:n_block,ccgt)
    na(t)=_PM.var(pm,t,:na_block,ccgt)
    su(t)=_PM.var(pm,t,:su_block,ccgt)
    sd(t)=_PM.var(pm,t,:sd_block,ccgt)
    cost=JuMP.objective_function(pm.model)
    @test JuMP.is_integer(x) && JuMP.is_integer(su(1)) && JuMP.is_integer(sd(1))
    @test JuMP.coefficient(cost,su(1))≈200*1.25*2
    @test JuMP.coefficient(cost,sd(1))≈75*1.25*2
    @test JuMP.coefficient(cost,_PM.var(pm,1,:su_block,ocgt))≈120*1.25*2
    @test JuMP.coefficient(cost,_PM.var(pm,1,:sd_block,ocgt))≈30*1.25*2
    JuMP.@constraint(pm.model,x==3)
    JuMP.@constraint(pm.model,na(1)==2)
    JuMP.@constraint(pm.model,na(2)==2)
    JuMP.@constraint(pm.model,na(3)==0)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
    @test JuMP.value(su(1))≈1
    @test JuMP.value(sd(1))≈0
    @test JuMP.value(sd(3))≈2
    too_many=JuMP.@constraint(pm.model,su(1)==2)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.INFEASIBLE
    JuMP.delete(pm.model,too_many)
    JuMP.@constraint(pm.model,_PM.var(pm,1,:sd_block,ocgt)==1)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.INFEASIBLE
    @test_throws ArgumentError _owner_model(data;relax_block_variables=true)
    @test_throws ArgumentError _owner_model(data;intertemporal_constraints=false)
    @test_throws ArgumentError _owner_model(data;device_formulations=Dict(ccgt=>_FP.BlockRenewableParticipation()))
    @test_throws ArgumentError _owner_model(data;device_formulations=Dict((:gen,1)=>_FP.BlockThermalCommitment()))
end

@testset "Owner PHS roster and lossless HGÜ with construction off" begin
    main=_owner_fixture()
    @test all(length(sn["storage"])==2 for sn in values(main["nw"]))
    off=_ap2_expansion_prepared(_owner_fixture(;dc_mode="CONSTRUCTION_OFF"))
    @test all(sn["dcline"]["1"]["br_status"]==0 for sn in values(off["nw"]))
    pm=_owner_model(off)
    @test Set(keys(_PM.ref(pm,1,:dcline)))==Set([2])
    @test all(iszero(_PM.ref(pm,1,:dcline,2,field)) for field in ("pminf","pmaxf","pmint","pmaxt"))
    sensitivity=_ap2_expansion_prepared(_owner_fixture(;phs_mode="HYPOTHETICAL_PHS_3H"))
    pm=_owner_model(sensitivity)
    @test _PM.ref(pm,1,:storage,2,"energy_rating")*250≈75
    @test length(_PM.con(pm,1,:paper_a_native_uc_event_bounds))==2
    for t in 1:3
        JuMP.fix(_PM.var(pm,t,:sc,2),0.0;force=true)
        JuMP.fix(_PM.var(pm,t,:sd,2),0.0;force=true)
    end
    JuMP.fix(_PM.var(pm,3,:se,2),0.15;force=true)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
    for t in 1:3
        @test JuMP.value(_PM.var(pm,t,:se,2))*250≈37.5
        @test JuMP.value(_PM.var(pm,t,:paper_a_storage_spill,2))*250≈1.0
    end
end

@testset "Owner BESS annualized cost is applied once" begin
    prices=Float64[]
    for d in (4,6)
        pm=_owner_model(_ap2_expansion_prepared(_owner_fixture(;bess_hours=d)))
        price=JuMP.objective_function(pm.model)
        @test _PM.ref(pm,1,:storage,1,"paper_a_storage_unit")["max_hours"]==4
        push!(prices,JuMP.coefficient(price,_PM.var(pm,1,:n_block,(:storage,7))))
        @test prices[end]≈25*1.2*(19758.59100216229+d*10128.316776565933)
    end
    @test prices[2]-prices[1]≈25*1.2*2*10128.316776565933
end

@testset "Owner passive eliminated block must be positive definite" begin
    data=_ap2_expansion_fixture()
    net=data["paper_a_network"]
    buses=data["nw"]["1"]["bus"]
    net["retained_physical_buses"]=["A"]
    net["eliminated_physical_buses"]=["B"]
    delete!(net,"B0_reference_pu")
    R=_FP.PaperARegional
    @test only(R.network_reference(net,buses,250;require_positive_eliminated=true).B0)≈0 atol=1e-12
    tol=_FP.PaperADiagnostics.DEFAULT_TOL
    net["fixed_shunts"]["B"]=Dict("gs_pu"=>0.0,"bs_pu"=>10.0-tol/10)
    @test_throws ArgumentError R.network_reference(net,buses,250;require_positive_eliminated=true)
    net["fixed_shunts"]["B"]["bs_pu"]=10.0-2tol
    @test isfinite(only(R.network_reference(net,buses,250;require_positive_eliminated=true).B0))
    net["fixed_shunts"]["B"]=Dict("gs_pu"=>0.0,"bs_pu"=>11.0)
    @test only(R.network_reference(net,buses,250).B0)≈110.0
    @test_throws ArgumentError R.network_reference(net,buses,250;require_positive_eliminated=true)
end

@testset "Owner case and manifest agree on scenario and derived CSV identity" begin
    data=_owner_fixture()
    owner=_owner_marker(data)
    pin=repeat("a",64)
    derived=repeat("b",64)
    owner["source_binding"]=Dict("derived_csv_bundle_sha256"=>derived)
    manifest=Dict{String,Any}("schema"=>"paper_a_ap1_manifest_1.0",
        "case_content_identity"=>"sha256_raw_json_bytes_v1","case_sha256"=>pin,
        "case_run_identity"=>"ap1:sha256:"*pin,"selected_snapshots"=>[data["snapshot_ids"][string(i)] for i in 1:3],
        "owner_scenario"=>deepcopy(owner),"source_dataset_identity_sha256"=>derived)
    mktempdir() do dir
        function write_manifest(name)
            path=joinpath(dir,name*".json")
            open(io->_FP.JSON.print(io,manifest),path,"w")
            return path
        end
        @test _FP._paper_a_validate_case_manifest(data,write_manifest("matching"),pin)=="ap1:sha256:"*pin
        manifest["owner_scenario"]["bess_duration_h"]=6
        @test_throws ArgumentError _FP._paper_a_validate_case_manifest(data,write_manifest("different-duration"),pin)
        manifest["owner_scenario"]["bess_duration_h"]=4
        manifest["source_dataset_identity_sha256"]=repeat("c",64)
        @test_throws ArgumentError _FP._paper_a_validate_case_manifest(data,write_manifest("different-source"),pin)
        # Release JSON's mapped file buffers before Windows removes the fixture directory.
        Sys.iswindows() && GC.gc()
    end
end

@testset "Reject inconsistent owner scenario inputs before model assembly" begin
    native(d)=d["nw"]["1"]["gen"]["2"]["paper_a_native_uc"]
    gen(d)=d["nw"]["1"]["gen"]["2"]
    dc(d)=d["nw"]["1"]["dcline"]["1"]
    phs(d)=_owner_marker(d)["phs_roster"]["synthetic PHS 1"]
    for mutate in (d->delete!(gen(d),"paper_a_native_uc"),d->delete!(native(d),"shutdown_original_value"),
                   d->delete!(native(d),"prior_uptime_h"),d->(native(d)["startup_unit"]="unknown"),
                   d->(native(d)["evidence_sha256"]="unknown"),d->(native(d)["generator_id"]="wrong"),
                   d->(native(d)["ramp_required"]=true),d->(gen(d)["startup_cost_per_mw"]=800.0),
                   d->(native(d)["startup_unit"]="EUR_per_generator_event"),d->(native(d)["na0"]=0),
                   d->(gen(d)["na0"]=0.5),d->(native(d)["na0"]=1.0),
                   d->(dc(d)["pmint"]=0.2),d->(dc(d)["br_status"]=0),d->(dc(d)["loss1"]=0.1),
                   d->delete!(d["nw"]["2"]["dcline"],"1"),d->(phs(d)["effective_max_hours"]=6.0),
                   d->push!(_owner_marker(d)["phs_assets"],"synthetic PHS 1"),
                   d->(_owner_marker(d)["source_snapshot_count"]=4),
                   d->(d["nw"]["1"]["storage"]["1"]["name"]="synthetic PHS 1"),
                   d->push!(d["paper_a_network"]["fixed_sources_in_network"],"synthetic PHS 1"),
                   d->(d["paper_a_network"]["fixed_source_shunt_by_asset"]=Dict("synthetic PHS 1"=>Dict("bus"=>"A"))),
                   d->(dc(d)["paper_a_native_dc"]["native_availability"]=0.5),
                   d->(_owner_marker(d)["bess_gfm_premium"]=0.4),
                   d->(d["nw"]["1"]["storage"]["7"]["cost_inv_per_mw"]*=1.2),
                   d->delete!(d["nw"]["1"]["storage"]["7"],"paper_a_bess_cost"))
        data=_owner_fixture()
        mutate(data)
        @test_throws ArgumentError _ap2_expansion_prepared(data)
    end
    data=_owner_fixture(;phs_mode="HYPOTHETICAL_PHS_3H")
    delete!(data["nw"]["2"]["storage"],"2")
    @test_throws ArgumentError _ap2_expansion_prepared(data)
    data=_owner_fixture()
    @test_throws ArgumentError _FP.prepare_paper_a_data!(data)
    data=_ap2_expansion_prepared(data)
    gen(data)["paper_a_native_uc"]["factor_to_EUR2025"]=1.3
    @test_throws ArgumentError _owner_model(data)
end
