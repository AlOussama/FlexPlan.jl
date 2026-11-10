using Test, JuMP, SHA
import FlexPlan as FP
import PowerModels as PM
import JSON

length(ARGS)==2 || error("usage: run_paper_a_dev04_acceptance.jl PRODUCER_ROOT OUTPUT_JSON")
root,out=ARGS
folder(generation,n)=joinpath(root,generation,"reservoir_ap1_$(n)snap")
case_path(generation,n)=joinpath(folder(generation,n),"case.json")
manifest_path(generation,n)=joinpath(folder(generation,n),"case_manifest.json")
read_raw(generation,n)=JSON.parsefile(case_path(generation,n))

# Record the producer's expectations once, before any consumer call or mutation.
runs=Dict((g,n)=>JSON.parsefile(manifest_path(g,n)) for g in ("original","changed") for n in (3,6,24))
expected(g,n)=runs[(g,n)]["case_sha256"]
read_case(g,n)=FP.parse_file(case_path(g,n);expected_case_sha256=expected(g,n))

function dims!(data)
    FP.add_dimension!(data,:hour,length(data["nw"]))
    FP.add_dimension!(data,:scenario,Dict(1=>Dict{String,Any}("probability"=>0.5)))
    FP.add_dimension!(data,:year,1;metadata=Dict{String,Any}("scale_factor"=>1))
    return data
end

function model(data;scope=:synthetic_regression,before_ref=(ref,data)->nothing,after_ref=(ref,data)->nothing)
    template=FP.UCGSCRBlockTemplate(Dict((:gen,"CCGT")=>FP.BlockThermalCommitment(),
        (:gen,"onwind")=>FP.BlockRenewableParticipation(),(:storage,"hydro")=>FP.BlockStorageParticipation()),
        FP.NoGSCR();paper_a_validation_scope=scope)
    return PM.instantiate_model(data,PM.DCPPowerModel,
        m->FP.build_uc_gscr_block_integration(m;template,relax_block_variables=true);
        ref_extensions=[FP.ref_add_gen!,FP.ref_add_storage!,FP.ref_add_ne_storage!,before_ref,
            (r,d)->FP.ref_add_uc_gscr_block!(r,d;paper_a_validation_scope=scope),after_ref])
end

function swap_profiles!(a,b)
    for table in ("gen","storage","load")
        (a[table],b[table])=(b[table],a[table])
    end
end

function rejects(f,reason)
    err=try
        f()
        nothing
    catch ex
        ex
    end
    @test err isa ArgumentError
    @test occursin(reason,sprint(showerror,err))
end

mismatch="AP1_PROFILE_CONTENT_IDENTITY_MISMATCH"
unverified="PROFILE_ORIGIN_UNVERIFIED"

@testset verbose=true "DEV04 negative cases before HiGHS" begin
    original=read_raw("changed",3)
    pin=expected("changed",3)
    changed=deepcopy(original)
    swap_profiles!(changed["nw"]["1"],changed["nw"]["2"])
    @test changed["nw"]["1"]["storage"]["1"]["stationary_energy_inflow"] !=
        original["nw"]["1"]["storage"]["1"]["stationary_energy_inflow"]
    @test all(changed["nw"]["1"][key]==original["nw"]["1"][key] for key in
        ("snapshot_id","paper_a_temporal","time_elapsed","pypsa_snapshot_weight_objective"))
    mktempdir() do tmp
        file=joinpath(tmp,"case.json")
        sidecar=joinpath(tmp,"case_manifest.json")
        write(file,JSON.json(changed))
        manifest=deepcopy(runs[("changed",3)])
        write(sidecar,JSON.json(manifest))
        rejects(()->FP.parse_file(file;expected_case_sha256=pin),mismatch)
        fake=bytes2hex(sha256(read(file)))
        manifest["case_sha256"]=fake
        manifest["case_run_identity"]="ap1:sha256:"*fake
        write(sidecar,JSON.json(manifest))
        rejects(()->FP.parse_file(file;expected_case_sha256=pin),mismatch)
        rejects(()->FP.parse_file(file;case_manifest=sidecar),unverified)

        for alter in (d->(d["nw"]["2"]["load"]["1"]["pd"]+=1),
                      d->(d["nw"]["2"]["storage"]["1"]["stationary_energy_inflow"]+=1),
                      d->(d["nw"]["2"]["gen"]["2"]["a_res"]+=.01),
                      d->(d["nw"]["2"]["gen"]["2"]["name"]="foreign_asset"),
                      d->(d["nw"]["2"]["snapshot_id"]="2013-03-06T00:00:00"),
                      d->(d["nw"]["2"]["storage"]["1"]["paper_a_storage_unit"]["inflow_unit"]="MWh"),
                      d->(d["baseMVA"]=300.0))
            copy=deepcopy(original)
            alter(copy)
            write(file,JSON.json(copy))
            rejects(()->FP.parse_file(file;expected_case_sha256=pin),mismatch)
        end
        cp(case_path("changed",3),joinpath(tmp,"without_manifest.json"))
        rejects(()->FP.parse_file(case_path("changed",3);expected_case_sha256=pin,
            case_manifest=joinpath(tmp,"missing.json")),unverified)
        rejects(()->FP.parse_file(case_path("changed",3);expected_case_sha256=pin,
            case_manifest=manifest_path("original",3)),mismatch)
    end

    profile=FP.paper_a_profile_identity(original)
    # Different iteration order of the actual nested objects, same digest.
    sn=original["nw"]["1"]
    devices=sn["gen"]
    ids=collect(keys(devices))
    order=Base.ImmutableDict{String,Any}()
    for key in ids
        order=Base.ImmutableDict(order,key=>devices[key])
    end
    @test collect(keys(order))==reverse(ids)
    reordered=deepcopy(original)
    reordered["nw"]["1"]["gen"]=order
    @test FP.paper_a_profile_identity(reordered)==profile
    rejects(()->FP.prepare_paper_a_data!(deepcopy(changed);expected_profile_sha256=profile),mismatch)
    for bad in (NaN,Inf,missing)
        copy=deepcopy(original)
        copy["nw"]["2"]["load"]["1"]["pd"]=bad
        rejects(()->FP.prepare_paper_a_data!(copy;expected_profile_sha256=profile),unverified)
    end

    data=dims!(FP.prepare_paper_a_data!(deepcopy(original);expected_profile_sha256=profile))
    @test data["per_unit"]
    dirty=deepcopy(data)
    swap_profiles!(dirty["nw"]["1"],dirty["nw"]["2"])
    rejects(()->FP.scale_paper_a_costs!(dirty),mismatch)
    FP.scale_paper_a_costs!(data)
    dirty=deepcopy(data)
    swap_profiles!(dirty["nw"]["1"],dirty["nw"]["2"])
    rejects(()->model(dirty),mismatch)
    late(r,d)=begin
        nw=r[:it][PM.pm_it_sym][:nw]
        for t in (:gen,:storage,:load)
            (nw[1][t],nw[2][t])=(nw[2][t],nw[1][t])
        end
    end
    rejects(()->model(data;before_ref=late),mismatch)
    rejects(()->model(data;after_ref=late),mismatch)
    @test PM.ref(model(data),1,:paper_a_profile_origin)=="PROFILE_CONTENT_IDENTITY_VERIFIED"

    for mutate in (d->((d["nw"]["1"],d["nw"]["2"])=(d["nw"]["2"],d["nw"]["1"])),
                   d->(d["nw"]["2"]["snapshot_id"]=d["nw"]["1"]["snapshot_id"]),
                   d->delete!(d["nw"]["2"],"snapshot_id"))
        dirty=deepcopy(original)
        mutate(dirty)
        rejects(()->FP.prepare_paper_a_data!(dirty;expected_profile_sha256=profile),mismatch)
    end
    unbound=dims!(FP.parse_file(case_path("changed",3)))
    FP.scale_paper_a_costs!(unbound)
    @test PM.ref(model(unbound),1,:paper_a_profile_origin)=="PROFILE_ORIGIN_UNVERIFIED"
    rejects(()->model(unbound;scope=:strict),unverified)
    strict=deepcopy(original)
    strict["paper_a_extension"]["dataset_kind"]="real_pypsa_input_unverified"
    rejects(()->FP.prepare_paper_a_data!(strict),unverified)
    @test !any(p->p.name=="HiGHS",keys(Base.loaded_modules))
end

import HiGHS
receipts=Any[]
@testset "DEV04 original and new producer runs with actual AP2 solves" begin
    for n in (3,6,24)
        @test expected("original",n)!=expected("changed",n)
        outcomes=Dict{String,Any}()
        for generation in ("original","changed")
            new=generation=="changed"
            data=dims!(read_case(generation,n))
            @test data["nw"]["1"]["storage"]["1"]["energy"]*200 ≈ 37.0
            @test data["nw"]["1"]["storage"]["1"]["charge_rating"]==0
            initial_online=data["nw"]["1"]["gen"]["1"]["na0"]
            FP.scale_paper_a_costs!(data)
            pm=model(data)
            for t in 1:n
                @test PM.ref(pm,t,:paper_a_profile_origin)=="PROFILE_CONTENT_IDENTITY_VERIFIED"
                @constraint(pm.model,PM.var(pm,t,:pg,2)==0)
                @constraint(pm.model,PM.var(pm,t,:sd,1)==0)
                @constraint(pm.model,PM.var(pm,t,:paper_a_storage_spill,1)==0)
                @constraint(pm.model,PM.var(pm,t,:na_block,(:gen,1))==0.05)
            end
            set_optimizer(pm.model,HiGHS.Optimizer)
            set_silent(pm.model)
            optimize!(pm.model)
            @test termination_status(pm.model)==MOI.OPTIMAL
            @test primal_status(pm.model)==MOI.FEASIBLE_POINT
            dt=[isodd(t) ? 1.0 : 2.0 for t in 1:n]
            rates=[new ? (isodd(t) ? 0.75 : 1.5) : 1.0 for t in 1:n]
            demand=[new ? (isodd(t) ? 9.0 : 12.0) : 10.0 for t in 1:n]
            energies=[value(PM.var(pm,t,:se,1))*200 for t in 1:n]
            @test all(t->abs(value(PM.var(pm,t,:sc,1)))<1e-10,1:n)
            @test [value(PM.var(pm,t,:pg,1))*200 for t in 1:n] ≈ demand
            @test energies ≈ 37 .+ cumsum(dt.*rates)
            reps=8760/72*0.5
            dispatch=sum(40 .* demand .* dt .* reps)
            events=256.5*reps*(2*max(0.05-initial_online,0)+3*max(initial_online-0.05,0))
            @test objective_value(pm.model) ≈ dispatch+events atol=1e-7
            outcomes[generation]=Dict("case_sha256"=>expected(generation,n),
                "termination"=>string(termination_status(pm.model)),"end_energy_MWh"=>last(energies),
                "first_two_energy_MWh"=>energies[1:2],"objective"=>objective_value(pm.model),
                "dispatch"=>dispatch,"events"=>events)
        end
        @test !isapprox(outcomes["original"]["end_energy_MWh"],outcomes["changed"]["end_energy_MWh"])
        @test !isapprox(outcomes["original"]["dispatch"],outcomes["changed"]["dispatch"])
        push!(receipts,Dict("snapshots"=>n,"outcomes"=>outcomes))
    end
end
open(out,"w") do io
    JSON.print(io,receipts,2)
end
