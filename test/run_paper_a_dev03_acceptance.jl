using Test, JuMP, SHA
import FlexPlan as FP
import PowerModels as PM
import JSON, HiGHS

length(ARGS)==2 || error("usage: run_paper_a_dev03_acceptance.jl GENERATED_ROOT OUTPUT_JSON")
cases = ARGS[1]
read_raw(n;cyclic=false) = JSON.parsefile(joinpath(cases,cyclic ? "cyclic_ap1_$(n)snap" :
                                                  "reservoir_ap1_$(n)snap","case.json"))
function prepare(raw)
    data = FP.prepare_paper_a_data!(raw)
    FP.add_dimension!(data,:hour,length(data["nw"]))
    FP.add_dimension!(data,:scenario,Dict(1=>Dict{String,Any}("probability"=>0.5)))
    FP.add_dimension!(data,:year,1;metadata=Dict{String,Any}("scale_factor"=>1))
    return data
end
function model(data; intertemporal_constraints=true)
    scope = :synthetic_regression
    template = FP.UCGSCRBlockTemplate(Dict((:gen,"CCGT")=>FP.BlockThermalCommitment(),
        (:gen,"onwind")=>FP.BlockRenewableParticipation(),(:storage,"hydro")=>FP.BlockStorageParticipation()),
        FP.NoGSCR();paper_a_validation_scope=scope)
    return PM.instantiate_model(data,PM.DCPPowerModel,
        m->FP.build_uc_gscr_block_integration(m;template,relax_block_variables=true,intertemporal_constraints);
        ref_extensions=[FP.ref_add_gen!,FP.ref_add_storage!,FP.ref_add_ne_storage!,
            (r,d)->FP.ref_add_uc_gscr_block!(r,d;paper_a_validation_scope=scope)])
end
function solve!(pm)
    set_optimizer(pm.model,HiGHS.Optimizer)
    set_silent(pm.model)
    optimize!(pm.model)
    return termination_status(pm.model)
end
function assert_rejected(f, data, diagnostic)
    err = try
        f(data)
        nothing
    catch err
        err
    end
    @test err isa ArgumentError && occursin(diagnostic,sprint(showerror,err))
end

receipts = Any[]
@testset verbose=true "DEV03 snapshot and reservoir cross-repo acceptance" begin
    @testset "fresh 3/6/24 AP1→AP2 solves with physical intervals" begin
        for n in (3,6,24)
            folder = joinpath(cases,"reservoir_ap1_$(n)snap")
            case_hash = bytes2hex(sha256(read(joinpath(folder,"case.json"))))
            @test case_hash==JSON.parsefile(joinpath(folder,"case_manifest.json"))["case_sha256"]
            raw = read_raw(n)
            for (t,r) in enumerate(raw["paper_a_temporal"])
                sn = raw["nw"][string(t)]
                @test sn["snapshot_id"]==r["snapshot_id"]==raw["snapshot_ids"][string(t)]
                @test sn["gen"]["2"]["a_res"] ≈ (t-1)/24
                @test sn["storage"]["1"]["energy"] == 37.0
                @test sn["storage"]["1"]["energy_rating"] == 200.0
                @test sn["storage"]["1"]["charge_rating"] == 0.0
                @test sn["storage"]["1"]["stationary_energy_inflow"] == 1.0
            end
            data = prepare(raw)
            weights = [copy(data["nw"][string(t)]["paper_a_temporal"]) for t in 1:n]
            raw_cost = [data["nw"][string(t)]["gen"]["1"]["cost"][1] for t in 1:n]
            raw_event = [data["nw"][string(t)]["gen"]["1"]["startup_cost_per_mw"] for t in 1:n]
            FP.scale_paper_a_costs!(data)
            pm = model(data)
            for t in 1:n
                @constraint(pm.model, PM.var(pm,t,:sd,1)==0)
                @constraint(pm.model, PM.var(pm,t,:paper_a_storage_spill,1)==0)
            end
            @test solve!(pm)==MOI.OPTIMAL
            @test primal_status(pm.model)==MOI.FEASIBLE_POINT
            energy = [value(PM.var(pm,t,:se,1))*200 for t in 1:n]
            increments = diff(vcat(37.0,energy))
            physical_hours = [isodd(t) ? 1.0 : 2.0 for t in 1:n]
            @test increments ≈ physical_hours
            costs = Dict{String,Any}()
            for t in 1:n
                id = weights[t]["snapshot_id"]
                @test PM.ref(pm,t,:paper_a_temporal).snapshot_id==id
                @test FP.coord(pm,t,:hour)==t
                @test value(PM.var(pm,t,:sc,1))≈0 atol=1e-10
                @test PM.ref(pm,t,:storage,1)["stationary_energy_inflow"] ≈ 1/200
                w = physical_hours[t]*(8760/72)*0.5
                @test weights[t]["dispatch_weight"] ≈ w
                op = coefficient(objective_function(pm.model),PM.var(pm,t,:pg,1))
                evt = coefficient(objective_function(pm.model),PM.var(pm,t,:su_block,(:gen,1)))
                @test op ≈ raw_cost[t]*w
                @test evt ≈ raw_event[t]*256.5*(8760/72)*0.5
                costs[id] = (dispatch_weight=w,dispatch_coefficient=op,startup_coefficient=evt)
            end
            push!(receipts,Dict("snapshots"=>n,"case_sha256"=>case_hash,"termination"=>string(termination_status(pm.model)),
                "objective"=>objective_value(pm.model),"energy_MWh"=>energy,"delta_MWh"=>increments,
                "weighted_dispatch_by_snapshot_id"=>costs))
        end
    end

    @testset "reject unbound snapshot profiles, time and weights before use" begin
        edits = (
            (d->reverse!(d["paper_a_temporal"]), "temporal record mismatch"),
            (d->(d["paper_a_temporal"][2]["snapshot_id"]=d["paper_a_temporal"][1]["snapshot_id"]), "temporal record mismatch"),
            (d->delete!(d["paper_a_temporal"][2],"snapshot_id"), "temporal record mismatch"),
            (d->(d["paper_a_temporal"][2]["snapshot_id"]="2013-03-05T04:00:00"), "temporal record mismatch"),
            (d->(d["nw"]["1"]["snapshot_id"]=d["snapshot_ids"]["2"]), "snapshot_id must match"),
            (d->delete!(d["nw"]["1"],"snapshot_id"), "snapshot_id must match"),
            (d->((d["nw"]["1"],d["nw"]["2"])=(d["nw"]["2"],d["nw"]["1"])), "snapshot_id must match"),
            (d->(d["nw"]["1"]["time_elapsed"]=d["nw"]["2"]["time_elapsed"]), "physical duration mismatch"),
            (d->(d["snapshot_weights"]["1"]=100.0), "objective weight mismatch"),
            (d->delete!(d["snapshot_ids"],"2"), "index domain mismatch"),
            (d->(d["snapshot_ids"]["4"]="2013-03-05T04:00:00"), "index domain mismatch"),
            (d->begin
                d["paper_a_temporal"][2]["representative_repetitions"]*=2
                d["paper_a_temporal"][2]["dispatch_weight"]*=2
            end, "temporal record mismatch"),
            (d->begin
                d["paper_a_temporal"][2]["event_repetitions"]*=2
                d["paper_a_temporal"][2]["event_weight"]*=2
            end, "temporal record mismatch"),
        )
        for (mutate,message) in edits
            for f in (FP.prepare_paper_a_data!,FP.scale_paper_a_costs!)
                raw = read_raw(3); mutate(raw)
                original = deepcopy(raw)
                assert_rejected(f,raw,message)
                @test isequal(raw,original)
            end
            data = prepare(read_raw(3)); FP.scale_paper_a_costs!(data); mutate(data)
            assert_rejected(model,data,message)
        end
        # Even consistently relabeled copies must represent strictly increasing time.
        for stamp in ("2013-03-01T00:00:00","2013-02-28T23:00:00","2013-03-01T00:30:00")
            raw = read_raw(3)
            raw["snapshot_ids"]["2"] = raw["nw"]["2"]["snapshot_id"] = stamp
            raw["paper_a_temporal"][2]["snapshot_id"] = raw["nw"]["2"]["paper_a_temporal"]["snapshot_id"] = stamp
            assert_rejected(FP.prepare_paper_a_data!,raw,"AP1")
        end
        # Changing a genuinely bound event weight affects only its own event term.
        raw = read_raw(3)
        for t in (raw["paper_a_temporal"][2],raw["nw"]["2"]["paper_a_temporal"])
            t["event_repetitions"]*=2
            t["event_weight"]*=2
        end
        data=prepare(raw); FP.scale_paper_a_costs!(data); pm=model(data)
        obj=objective_function(pm.model)
        @test coefficient(obj,PM.var(pm,2,:su_block,(:gen,1)))≈2*coefficient(obj,PM.var(pm,1,:su_block,(:gen,1)))
        @test coefficient(obj,PM.var(pm,3,:su_block,(:gen,1)))≈coefficient(obj,PM.var(pm,1,:su_block,(:gen,1)))
    end

    @testset "native pump, inflow units, spill and cyclic boundary" begin
        for mutate in (dev->delete!(dev,"stationary_energy_inflow"),
                       dev->(dev["stationary_energy_inflow"]=1/200),
                       dev->(dev["paper_a_storage_unit"]["inflow_unit"]="MWh"))
            raw = read_raw(3)
            mutate(raw["nw"]["1"]["storage"]["1"])
            assert_rejected(FP.prepare_paper_a_data!,raw,"inflow")
        end
        data=prepare(read_raw(3)); FP.scale_paper_a_costs!(data)
        assert_rejected(d->model(d;intertemporal_constraints=false),data,"intertemporal energy balance")
        pm=model(data)
        @constraint(pm.model,PM.var(pm,1,:sc,1)>=1/200)
        @test solve!(pm)==MOI.INFEASIBLE

        pumped=read_raw(3)
        for sn in values(pumped["nw"])
            dev=sn["storage"]["1"]
            dev["paper_a_storage_unit"]["p_min_pu"]=-0.4
            dev["paper_a_storage_unit"]["inflow_MW"]=0.0
            dev["charge_rating"]=20.0
            dev["stationary_energy_inflow"]=0.0
        end
        data=prepare(pumped); FP.scale_paper_a_costs!(data)
        pm=model(data)
        @constraint(pm.model,PM.var(pm,1,:sc,1)==10/200)
        @constraint(pm.model,PM.var(pm,1,:sd,1)==0)
        @test solve!(pm)==MOI.OPTIMAL
        @test !haskey(PM.var(pm,1),:paper_a_storage_spill)
        @test value(PM.var(pm,1,:se,1))*200 ≈ 37+0.95*10

        saturated=read_raw(3)
        for sn in values(saturated["nw"])
            dev=sn["storage"]["1"]
            dev["paper_a_storage_unit"]["state_of_charge_initial_MWh"]=200.0
            dev["energy"]=200.0
        end
        data=prepare(saturated); FP.scale_paper_a_costs!(data); pm=model(data)
        for t in 1:3
            @constraint(pm.model,PM.var(pm,t,:sd,1)==0)
        end
        @test solve!(pm)==MOI.OPTIMAL
        @test all(t->isapprox(value(PM.var(pm,t,:paper_a_storage_spill,1))*200,1.0),1:3)

        data=prepare(read_raw(24;cyclic=true)); FP.scale_paper_a_costs!(data); pm=model(data)
        @test PM.ref(pm,1,:storage,1)["paper_a_storage_unit"]["state_of_charge_initial_MWh"]===nothing
        for t in 1:24
            @constraint(pm.model,PM.var(pm,t,:sd,1)==0)
            @constraint(pm.model,PM.var(pm,t,:se,1)==55/200)
        end
        @test solve!(pm)==MOI.OPTIMAL
        @test value(PM.var(pm,1,:paper_a_storage_spill,1))*200 ≈ 1.0
        push!(receipts,Dict("controls"=>Dict("no_pump"=>"INFEASIBLE","pump_without_inflow"=>"OPTIMAL",
            "spill_at_capacity"=>"OPTIMAL","cyclic_nonzero_state"=>"OPTIMAL")))
    end
end
open(ARGS[2],"w") do io
    JSON.print(io,receipts,2)
end
