function _carrier_fixture(;hours=8,kwargs...)
    data=_owner_fixture(;hours,kwargs...)
    data["dim"][:prop][:scenario][1]["probability"]=1.0
    merge!(_owner_marker(data),Dict{String,Any}(
        "uc_tariff_mode"=>"CSV_CARRIER_EUR2025_REFERENCE",
        "uc_csv_commit"=>"d02406c44bf8aad9c2979521b8f393cf98b26262",
        "uc_csv_sha256"=>"22eddbe84d01160e22b0755b9b9774c3a389ad5ca5eede9d527b9c98ea37b801",
        "uc_shutdown_factor"=>0.2,"uc_price_year"=>2025,"uc_price_conversion_factor"=>1,
        "uc_initial_boundary"=>"INITIAL_ACTIVE_ZERO_WITH_FREE_END",
        "uc_initial_min_down"=>"ASSUME_MIN_DOWN_SATISFIED_BEFORE_GLOBAL_START",
        "uc_ramp_scope"=>"RAMP_CONSTRAINTS_NOT_ENFORCED"))
    refs=Dict("CCGT"=>[60,4,2,0.45,1,1,0.5,0.5],"OCGT"=>[24,0,0,0.2,1,1,0.8,0.8])
    fields=("start_up_cost","min_up_time","min_down_time","p_min_pu","ramp_limit_up","ramp_limit_down",
        "ramp_limit_start_up","ramp_limit_shut_down")
    for t in 1:hours
        key=string(t)
        sn=data["nw"][key]
        stamp=string(Dates.DateTime(2013,3,1)+Dates.Hour(t-1))
        time=Dict{String,Any}(field=>1.0 for field in keys(sn["paper_a_temporal"]) if field!="snapshot_id")
        time["snapshot_id"]=stamp
        sn["paper_a_temporal"]=time
        data["paper_a_temporal"][t]=copy(time)
        sn["snapshot_id"]=data["snapshot_ids"][key]=stamp
        sn["time_elapsed"]=data["snapshot_elapsed_hours"][key]=1.0
        sn["pypsa_snapshot_weight_objective"]=data["snapshot_weights"][key]=1.0
        for (id,dev) in sn["gen"]
            if id=="1"
                # Preserve the original 100 MW with two renewable blocks.
                dev["n0"]=dev["nmax"]=dev["na0"]=2
                for field in ("p_block_max","p_block_max_MW","S_block_MVA","native_source_MVA")
                    dev[field]/=2
                end
            elseif id=="3"
                dev["n0"]=2
                dev["nmax"]=8
            end
            p=dev["p_block_max_MW"]
            capacity=Dict("original_p_nom_MW"=>dev["n0"]*p,"original_p_nom_max_MW"=>dev["nmax"]*p)
            dev["paper_a_block_capacity"]=capacity
            carrier=dev["carrier"]
            haskey(refs,carrier) || continue
            delete!(dev,"paper_a_native_uc")
            row=refs[carrier]
            dev["na0"]=0.0
            dev["startup_cost_per_mw"]=row[1]
            dev["shutdown_cost_per_mw"]=row[1]/5
            dev["min_up_block_time"]=Int(row[2])
            dev["min_down_block_time"]=Int(row[3])
            dev["p_min_pu"]=row[4]
            dev["paper_a_carrier_uc"]=merge(Dict{String,Any}("generator_id"=>dev["name"],"carrier"=>carrier,
                "block_id"=>"generator:$id","P_block_MW"=>p,"csv_reference"=>Dict(zip(fields,row)),
                "native_startup_control"=>99999.0,"native_ramp_control"=>Dict("ramp_limit_start_up"=>0.5)),capacity)
        end
    end
    return data
end

function _segment_plan(data)
    plan=Dict("$table:$id"=>Int(dev["n0"]) for table in ("gen","storage","ne_storage")
        for (id,dev) in get(data["nw"]["1"],table,Dict()))
    plan["gen:2"]=4
    plan["gen:3"]=2
    return plan
end

function _segment_event(pm,t,variable,id)
    return _PM.var(pm,t,variable,(:gen,id))
end

@testset "Pinned carrier UC multi-start/stop counts and free end" begin
    data=_ap2_expansion_prepared(_carrier_fixture())
    pm=_owner_model(data)
    x(id)=_PM.var(pm,1,:n_block,(:gen,id))
    JuMP.fix(x(2),4;force=true)
    JuMP.fix(x(3),5;force=true)
    for (t,id,value) in ((1,2,1),(2,2,4),(1,3,5),(2,3,2),(8,3,1))
        JuMP.fix(_segment_event(pm,t,:na_block,id),value;force=true)
    end
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
    @test JuMP.value(_segment_event(pm,1,:su_block,2))≈1
    @test JuMP.value(_segment_event(pm,2,:su_block,2))≈3
    @test JuMP.value(_segment_event(pm,2,:sd_block,2))≈0
    @test JuMP.value(_segment_event(pm,2,:sd_block,3))≈3
    @test JuMP.value(_segment_event(pm,2,:su_block,3))≈0
    @test JuMP.value(_segment_event(pm,8,:na_block,3))≈1
    objective=JuMP.objective_function(pm.model)
    @test JuMP.coefficient(objective,_segment_event(pm,2,:su_block,2))≈1500
    @test JuMP.coefficient(objective,_segment_event(pm,2,:sd_block,2))≈300
    @test JuMP.coefficient(objective,_segment_event(pm,2,:sd_block,3))≈192
    @test _PM.ref(pm,1,:gen,1,"na0")==2
    @test _PM.ref(pm,1,:gen,2,"na0")==0
    pg=_PM.var(pm,2,:pg,2)
    below=JuMP.@constraint(pm.model,pg<=44/250)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.INFEASIBLE
    JuMP.delete(pm.model,below)
end

@testset "Bound sequential UC history and SOC" begin
    full=_carrier_fixture(;hours=27)
    for sn in values(full["nw"])
        for l in values(sn["load"]); delete!(l,"flex"); end
        delete!(sn["storage"]["1"],"max_energy_absorption")
        candidate=pop!(sn["storage"],"7")
        delete!(candidate,"max_energy_absorption")
        sn["ne_storage"]["7"]=candidate
    end
    full=_ap2_expansion_prepared(full)
    plan=_segment_plan(full)
    plan["ne_storage:7"]=1
    first_data=_FP.prepare_paper_a_segment(full,1:24,plan)
    @test_throws ArgumentError _owner_model(first_data)
    a=_owner_model(first_data;storage_terminal_policy=:none)
    for t in 1:24
        JuMP.fix(_segment_event(a,t,:na_block,2),t==24 ? 2 : 1;force=true)
    end
    JuMP.fix(_segment_event(a,24,:sd_block,2),1;force=true)
    JuMP.fix(_PM.var(a,24,:se,1),0.2;force=true)
    JuMP.fix(_PM.var(a,24,:se_ne,7),0.04;force=true)
    @test_throws ArgumentError _FP.paper_a_segment_state(a)
    @test _ap2_expansion_solve!(a)==JuMP.MOI.OPTIMAL
    state=_FP.paper_a_segment_state(a)
    previous_pin=state["sha256"]
    @test state["payload"]["thermal"]["gen:2"]==Dict("active"=>2,"starts"=>[0,0,2],"stops"=>[1])
    @test state["payload"]["soc_MWh"]["storage:1"]≈50
    @test state["payload"]["soc_MWh"]["ne_storage:7"]≈10
    capex=_FP.calc_uc_gscr_block_investment_cost(a)
    first_cost=JuMP.value(capex)
    expected=sum((plan[asset]-dev["n0"])*dev["p_block_max_MW"]*dev["cost_inv_per_mw"] for (asset,dev) in
        _FP._paper_a_segment_installed(full["nw"]["1"]))
    @test first_cost≈expected
    @test first_cost>0
    next=_FP.prepare_paper_a_segment(full,25:27,plan;previous=state,expected_previous_state_sha256=previous_pin)
    @test first(next["paper_a_temporal"])["snapshot_id"]==full["snapshot_ids"]["25"]
    b=_owner_model(next;storage_terminal_policy=:none)
    @test iszero(_FP.calc_uc_gscr_block_investment_cost(b))
    JuMP.fix(_PM.var(b,1,:sc,1),0.0;force=true)
    JuMP.fix(_PM.var(b,1,:sd,1),0.0;force=true)
    JuMP.fix(_PM.var(b,1,:sc_ne,7),0.0;force=true)
    JuMP.fix(_PM.var(b,1,:sd_ne,7),0.0;force=true)
    @test JuMP.is_fixed(_PM.var(b,1,:n_block,(:gen,2)))
    shut=JuMP.@constraint(b.model,_segment_event(b,1,:na_block,2)<=1)
    @test _ap2_expansion_solve!(b)==JuMP.MOI.INFEASIBLE
    JuMP.delete(b.model,shut)
    restart=JuMP.@constraint(b.model,_segment_event(b,1,:su_block,2)>=2)
    @test _ap2_expansion_solve!(b)==JuMP.MOI.INFEASIBLE
    JuMP.delete(b.model,restart)
    JuMP.fix(_segment_event(b,1,:na_block,2),3;force=true)
    @test _ap2_expansion_solve!(b)==JuMP.MOI.OPTIMAL
    @test JuMP.value(_segment_event(b,1,:su_block,2))≈1
    @test JuMP.value(_PM.var(b,1,:se,1))*250≈50
    @test JuMP.value(_PM.var(b,1,:se_ne,7))*250≈10
    @test JuMP.coefficient(JuMP.objective_function(b.model),_segment_event(b,1,:su_block,2))≈1500
    @test _FP.paper_a_segment_state(b)["payload"]["next_snapshot_id"]===nothing

    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,25:27,plan)
    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,25:27,plan;previous=state)
    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,1:24,plan;expected_previous_state_sha256=previous_pin)
    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,24:27,plan;previous=state,expected_previous_state_sha256=previous_pin)
    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,26:27,plan;previous=state,expected_previous_state_sha256=previous_pin)
    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,1:25,plan)
    changed_plan=copy(plan); changed_plan["gen:2"]=3
    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,25:27,changed_plan;previous=state,expected_previous_state_sha256=previous_pin)
    altered=deepcopy(state); altered["payload"]["soc_MWh"]["storage:1"]=0.0
    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,25:27,plan;previous=altered,expected_previous_state_sha256=previous_pin)
    altered["sha256"]=_FP._paper_a_canonical_digest(altered["payload"])
    @test altered["payload"]["result_sha256"]==state["payload"]["result_sha256"]
    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,25:27,plan;previous=altered,expected_previous_state_sha256=previous_pin)
    altered["payload"]["thermal"]["gen:2"]["starts"]=[1]
    altered["sha256"]=_FP._paper_a_canonical_digest(altered["payload"])
    @test_throws ArgumentError _FP.prepare_paper_a_segment(full,25:27,plan;previous=altered,expected_previous_state_sha256=altered["sha256"])
    tamper=deepcopy(next); tamper["_paper_a_sequential_segment"].payload["first_hour"]=26
    @test_throws ArgumentError _owner_model(tamper;storage_terminal_policy=:none)
    cyclic=_ap2_expansion_prepared(_carrier_fixture(;phs_mode="HYPOTHETICAL_PHS_3H"))
    @test_throws ArgumentError _FP.prepare_paper_a_segment(cyclic,1:5,_segment_plan(cyclic))
    absorption=_ap2_expansion_prepared(_carrier_fixture())
    @test_throws ArgumentError _FP.prepare_paper_a_segment(absorption,1:5,_segment_plan(absorption))
end

@testset "Reject invalid carrier UC pricing and capacity provenance" begin
    gen(d)=d["nw"]["1"]["gen"]["2"]
    for mutate in (d->(_owner_marker(d)["uc_ramp_scope"]="ENFORCED"),
                   d->(_owner_marker(d)["uc_csv_sha256"]=repeat("0",64)),
                   d->(_owner_marker(d)["uc_shutdown_factor"]=0.25),
                   d->delete!(gen(d),"paper_a_carrier_uc"),
                   d->(gen(d)["carrier"]="unknown thermal"),
                   d->(gen(d)["na0"]=1),d->(gen(d)["n0"]=1),
                   d->(gen(d)["nmax"]+=1),d->(gen(d)["startup_cost_per_mw"]=99999.0),
                   d->(gen(d)["p_min_pu"]=0.1),d->(gen(d)["min_up_block_time"]=1),
                   d->(gen(d)["paper_a_carrier_uc"]["csv_reference"]["ramp_limit_up"]=0.9),
                   d->(gen(d)["paper_a_carrier_uc"]["block_id"]=""),
                   d->(gen(d)["ramp_limit_up"]=0.9),d->(gen(d)["gen_status"]=0))
        data=_carrier_fixture()
        mutate(data)
        @test_throws ArgumentError _ap2_expansion_prepared(data)
    end
end
