const _PAPER_A_SEGMENT_KEY="_paper_a_sequential_segment"

struct _PaperASequentialSegment
    payload::Dict{String,Any}
end

_paper_a_segment(data)=get(data,_PAPER_A_SEGMENT_KEY,nothing)
_paper_a_segment_asset(table,id)="$table:$id"
_paper_a_segment_in_service(table,dev)=table=="ne_storage" || get(dev,table=="gen" ? "gen_status" : "status",1)==1

function _paper_a_validate_segment_binding(data)
    segment=_paper_a_segment(data)
    identity=get(data,"paper_a_segment_identity",nothing)
    if segment===nothing && identity===nothing
        return nothing
    end
    segment isa _PaperASequentialSegment && _paper_a_canonical_digest(segment.payload)==identity ||
        _paper_a_identity_mismatch("sequential segment binding does not match its state and installed plan")
    return segment
end

function _paper_a_segment_storage(snapshot)
    return Dict(_paper_a_segment_asset(table,id)=>dev for table in ("storage","ne_storage")
        for (id,dev) in get(snapshot,table,Dict()) if _paper_a_segment_in_service(table,dev))
end

function _paper_a_segment_installed(snapshot)
    return Dict(_paper_a_segment_asset(table,id)=>dev for table in ("gen","storage","ne_storage")
        for (id,dev) in get(snapshot,table,Dict()) if _paper_a_segment_in_service(table,dev) &&
        haskey(dev,"n0") && !_uc_gscr_is_inactive_placeholder_device(dev))
end

function _paper_a_segment_installed_identity(dev)
    return (get(dev,"name",nothing),get(dev,"carrier",nothing),get(dev,"gen_bus",get(dev,"storage_bus",nothing)),
        dev["n0"],dev["nmax"],dev["p_block_max_MW"],get(dev,"e_block",nothing))
end

function _paper_a_segment_thermal(snapshot)
    return Dict(_paper_a_segment_asset("gen",id)=>dev for (id,dev) in get(snapshot,"gen",Dict())
        if get(dev,"gen_status",1)==1 && haskey(dev,"paper_a_carrier_uc"))
end

function _paper_a_segment_plan(snapshot,fixed_installed)
    expected=_paper_a_segment_installed(snapshot)
    fixed_installed isa AbstractDict && keys(fixed_installed)==keys(expected) ||
        throw(ArgumentError("Sequential segment requires the exact installed block roster"))
    plan=Dict{String,Int}()
    for (asset,dev) in expected
        count=_paper_a_owner_count(fixed_installed,asset;existing=true)
        dev["n0"]<=count<=dev["nmax"] || throw(ArgumentError("Sequential installed plan is outside bounds for $asset"))
        plan[asset]=count
    end
    return plan
end

function _paper_a_validate_segment_previous(state,expected_sha256,full,identity,plan,start)
    _paper_a_sha256_string(expected_sha256) ||
        _paper_a_origin_unverified("sequential continuation requires the previously captured predecessor state SHA-256")
    state isa AbstractDict && get(state,"schema",nothing)=="paper_a_segment_state_v1" ||
        throw(ArgumentError("Sequential continuation requires previous segment state"))
    payload=get(state,"payload",nothing)
    payload isa AbstractDict && get(state,"sha256",nothing)==expected_sha256 &&
        _paper_a_canonical_digest(payload)==expected_sha256 ||
        _paper_a_identity_mismatch("previous segment state does not match the captured SHA-256")
    get(payload,"source_identity",nothing)==identity && get(payload,"installed",nothing)==plan &&
        get(payload,"baseMVA",nothing)==full["baseMVA"] && get(payload,"end_hour",nothing)==start-1 &&
        get(payload,"last_snapshot_id",nothing)==full["snapshot_ids"][string(start-1)] &&
        get(payload,"next_snapshot_id",nothing)==full["snapshot_ids"][string(start)] &&
        _paper_a_sha256_string(get(payload,"result_sha256",nothing)) ||
        throw(ArgumentError("Sequential state source, plan, base or next snapshot does not match"))
    prior=full["nw"][string(start-1)]
    thermal=_paper_a_segment_thermal(prior)
    history=get(payload,"thermal",nothing)
    history isa AbstractDict && keys(history)==keys(thermal) ||
        throw(ArgumentError("Sequential state has an incomplete thermal roster"))
    for (asset,dev) in thermal
        row=history[asset]
        row isa AbstractDict || throw(ArgumentError("Invalid sequential thermal state for $asset"))
        count=plan[asset]
        active=_paper_a_owner_count(row,"active")
        active<=count || throw(ArgumentError("Sequential active blocks exceed installed plan for $asset"))
        for (field,minimum,available) in (("starts",dev["min_up_block_time"],active),
                                          ("stops",dev["min_down_block_time"],count-active))
            cohort=get(row,field,nothing)
            cohort isa AbstractVector && length(cohort)==min(start-1,max(0,minimum-1)) &&
                all(x->x isa Integer && !(x isa Bool) && 0<=x<=count,cohort) && sum(cohort)<=available ||
                throw(ArgumentError("Invalid or incomplete sequential $field cohorts for $asset"))
        end
        starts,stops=row["starts"],row["stops"]
        for offset in 0:min(length(starts),length(stops))-1
            su,sd=starts[end-offset],stops[end-offset]
            previous=active-su+sd
            0<=previous<=count && su<=count-previous && sd<=previous ||
                throw(ArgumentError("Sequential event history violates active-count transitions for $asset"))
            active=previous
        end
    end
    storage=_paper_a_segment_storage(prior)
    soc=get(payload,"soc_MWh",nothing)
    soc isa AbstractDict && keys(soc)==keys(storage) || throw(ArgumentError("Sequential state has incomplete storage SOC"))
    for (asset,dev) in storage
        maximum=(haskey(plan,asset) ? dev["e_block"]*plan[asset] : dev["energy_rating"])*full["baseMVA"]
        value=PaperARegional.number(soc,asset;nonnegative=true)
        value<=maximum+1e-7 || throw(ArgumentError("Sequential storage SOC exceeds installed energy for $asset"))
    end
    return payload
end

"""Derive a contiguous 1–24 hour sequential case from verified, normalized,
weighted full-horizon owner input. `fixed_installed` maps `"gen:1"` (and the
corresponding storage keys) to fixed installed counts. When a segment solve
completes, call `paper_a_segment_state(pm)` and capture its `sha256` separately
in the run record. To continue, pass the state as `previous` and that captured
digest as `expected_previous_state_sha256`. The digest binds the expected
predecessor state bytes to the continuation.
Segment builds require `storage_terminal_policy=:none`. Cyclic storage and
cumulative energy budgets require the jointly optimized horizon. Sequential
feasibility with a fixed plan does not establish the joint annual optimum.
"""
function prepare_paper_a_segment(full::Dict{String,Any},hours::UnitRange{Int},fixed_installed;
        previous=nothing,expected_previous_state_sha256=nothing)
    _paper_a_segment(full)===nothing && !haskey(full,"paper_a_segment_identity") && _paper_a_carrier_uc(full) ||
        throw(ArgumentError("Sequential segments require the full owner carrier UC case"))
    binding=_paper_a_profile_binding(full)
    _paper_a_validate_chronology(full)
    _paper_a_validate_owner_case(full,binding)
    _paper_a_validate_native_storage(full)
    total=length(full["nw"])
    _paper_a_owner_scenario(full)["phs_mode"]=="MAIN" ||
        throw(ArgumentError("Sequential segments support the main PHS roster; the cyclic PHS sensitivity requires joint chronology"))
    1<=length(hours)<=24 && first(hours)>=1 && last(hours)<=total ||
        throw(ArgumentError("Sequential segment must cover 1–24 contiguous original hours"))
    get(full,"per_unit",false) && all(get(s,"paper_a_cost_state",nothing)=="weighted" for s in values(full["nw"])) ||
        throw(ArgumentError("Prepare and weight the full owner case before deriving segments"))
    first_snapshot=full["nw"]["1"]
    plan=_paper_a_segment_plan(first_snapshot,fixed_installed)
    original_installed=Dict(asset=>_paper_a_segment_installed_identity(dev) for (asset,dev) in _paper_a_segment_installed(first_snapshot))
    original_storage=_paper_a_segment_storage(first_snapshot)
    original_thermal=_paper_a_segment_thermal(first_snapshot)
    for sn in values(full["nw"])
        Dict(asset=>_paper_a_segment_installed_identity(dev) for (asset,dev) in _paper_a_segment_installed(sn))==original_installed &&
            keys(_paper_a_segment_thermal(sn))==keys(original_thermal) ||
            throw(ArgumentError("Sequential block roster or availability changes within the full case"))
        storage=_paper_a_segment_storage(sn)
        keys(storage)==keys(original_storage) && all(get(storage[a],"e_block",get(storage[a],"energy_rating",nothing))==
            get(original_storage[a],"e_block",get(original_storage[a],"energy_rating",nothing)) for a in keys(storage)) ||
            throw(ArgumentError("Sequential storage roster, status or capacity changes within the full case"))
        for dev in values(storage)
            native=get(dev,"paper_a_storage_unit",nothing)
            (native===nothing || native["cyclic_state_of_charge"]===false) &&
                get(dev,"max_energy_absorption",Inf)==Inf ||
                throw(ArgumentError("Sequential cyclic storage and cumulative absorption budgets require joint chronology"))
        end
        # The integrated DCP balance itself has fixed demand and no flex states.
        all(get(l,"flex",0)==0 for l in values(get(sn,"load",Dict()))) ||
            throw(ArgumentError("Sequential flexible-demand states require joint chronology"))
    end
    identity=Dict("run"=>binding.run_identity,"profile_sha256"=>binding.digest)
    start=first(hours)
    inbound=if start==1
        previous===nothing && expected_previous_state_sha256===nothing ||
            throw(ArgumentError("The first sequential segment cannot take predecessor state or SHA-256"))
        nothing
    else
        _paper_a_validate_segment_previous(previous,expected_previous_state_sha256,full,identity,plan,start)
    end
    payload=Dict{String,Any}("source_identity"=>identity,"installed"=>plan,"first_hour"=>start,
        "end_hour"=>last(hours),"baseMVA"=>full["baseMVA"],"inbound"=>deepcopy(inbound),
        "next_snapshot_id"=>get(full["snapshot_ids"],string(last(hours)+1),nothing))
    replaced=("nw","dim","snapshot_ids","snapshot_weights","snapshot_elapsed_hours","paper_a_temporal",_PAPER_A_PROFILE_KEY)
    data=Dict{String,Any}(key=>deepcopy(value) for (key,value) in full if key ∉ replaced)
    for field in ("nw","snapshot_ids","snapshot_weights","snapshot_elapsed_hours")
        data[field]=Dict(string(i)=>deepcopy(full[field][string(t)]) for (i,t) in enumerate(hours))
    end
    data["paper_a_temporal"]=deepcopy(full["paper_a_temporal"][hours])
    add_dimension!(data,:hour,length(hours))
    add_dimension!(data,:scenario,Dict(1=>Dict{String,Any}("probability"=>1.0)))
    add_dimension!(data,:year,1;metadata=Dict{String,Any}("scale_factor"=>1))
    data[_PAPER_A_SEGMENT_KEY]=_PaperASequentialSegment(payload)
    data["paper_a_segment_identity"]=_paper_a_canonical_digest(payload)
    _paper_a_advance_profile_binding!(data,binding)
    return data
end

function _paper_a_segment_history(pm,nw,key,minimum;online)
    segment=_paper_a_segment(pm.data)
    segment===nothing && return 0
    inbound=segment.payload["inbound"]
    inbound===nothing && return 0
    row=inbound["thermal"][_paper_a_segment_asset(key...)]
    cohorts=row[online ? "starts" : "stops"]
    remaining=min(length(cohorts),max(0,minimum-coord(pm,nw,:hour)))
    return sum(view(cohorts,length(cohorts)-remaining+1:length(cohorts));init=0)
end

function _paper_a_segment_initial_active(pm,nw,key)
    segment=_paper_a_segment(pm.data)
    inbound=segment===nothing ? nothing : segment.payload["inbound"]
    inbound===nothing && return _PM.ref(pm,nw,key...,"na0")
    return inbound["thermal"][_paper_a_segment_asset(key...)]["active"]
end

function _paper_a_segment_initial_soc(pm,nw,table,id)
    segment=_paper_a_segment(pm.data)
    inbound=segment===nothing ? nothing : segment.payload["inbound"]
    inbound===nothing && return _PM.ref(pm,nw,table,id,"energy")
    return inbound["soc_MWh"][_paper_a_segment_asset(table,id)]/pm.data["baseMVA"]
end

function _paper_a_segment_fix_plan!(pm,nw)
    segment=_paper_a_segment(pm.data)
    segment===nothing && return nothing
    installed=_PM.var(pm,nw,:n_block)
    plan=segment.payload["installed"]
    model_keys=collect(_uc_gscr_block_all_device_keys(pm,nw))
    Set(_paper_a_segment_asset(k...) for k in model_keys)==keys(plan) ||
        throw(ArgumentError("Sequential installed plan does not match resolved model block roster"))
    for key in model_keys
        count=plan[_paper_a_segment_asset(key...)]
        variable=installed[key]
        JuMP.lower_bound(variable)<=count<=JuMP.upper_bound(variable) ||
            throw(ArgumentError("Sequential installed plan is outside model bounds for $key"))
        JuMP.fix(variable,count;force=true)
    end
    return nothing
end

function _paper_a_segment_count(x)
    value=JuMP.value(x)
    isfinite(value) || throw(ArgumentError("Nonfinite solved sequential block count"))
    count=round(Int,value)
    isapprox(value,count;atol=1e-6,rtol=0) && count>=0 || throw(ArgumentError("Invalid solved sequential block count"))
    return count
end

"""Extract the SHA-bound predecessor state from an optimal sequential model."""
function paper_a_segment_state(pm)
    segment=_paper_a_validate_segment_binding(pm.data)
    segment!==nothing && JuMP.termination_status(pm.model)==JuMP.MOI.OPTIMAL &&
        JuMP.primal_status(pm.model)==JuMP.MOI.FEASIBLE_POINT ||
        throw(ArgumentError("Sequential state requires an optimal segment with a feasible primal result"))
    prior=segment.payload["inbound"]
    ids=nw_ids(pm)
    n=last(ids)
    plan=segment.payload["installed"]
    thermal=Dict{String,Any}()
    results=Dict{String,Any}()
    for key in _uc_gscr_block_startup_shutdown_device_keys(pm,n)
        asset=_paper_a_segment_asset(key...)
        dev=_PM.ref(pm,n,key...)
        active=[_paper_a_segment_count(_PM.var(pm,t,:na_block,key)) for t in ids]
        row=Dict{String,Any}("active"=>last(active))
        record=Dict{String,Any}("active"=>active)
        for (field,var,minimum) in (("starts",:su_block,"min_up_block_time"),("stops",:sd_block,"min_down_block_time"))
            counts=[_paper_a_segment_count(_PM.var(pm,t,var,key)) for t in ids]
            record[field]=counts
            combined=prior===nothing ? counts : vcat(prior["thermal"][asset][field],counts)
            row[field]=last(combined,min(length(combined),max(0,dev[minimum]-1)))
        end
        thermal[asset]=row
        results[asset]=record
    end
    soc=Dict{String,Float64}()
    for (table,var) in ((:storage,:se),(:ne_storage,:se_ne))
        vars=get(_PM.var(pm,n),var,nothing)
        vars===nothing && continue
        for id in axes(vars,1)
            value=JuMP.value(vars[id])*pm.data["baseMVA"]
            isfinite(value) && value>=-1e-7 || throw(ArgumentError("Invalid solved sequential SOC"))
            soc[_paper_a_segment_asset(table,id)]=max(0.0,value)
        end
    end
    result_sha=_paper_a_canonical_digest(Dict("segment_identity"=>pm.data["paper_a_segment_identity"],
        "thermal_counts"=>results,"soc_MWh"=>soc,"objective"=>JuMP.objective_value(pm.model)))
    payload=Dict{String,Any}("source_identity"=>deepcopy(segment.payload["source_identity"]),"installed"=>copy(plan),
        "baseMVA"=>pm.data["baseMVA"],"end_hour"=>segment.payload["end_hour"],
        "last_snapshot_id"=>pm.data["snapshot_ids"][string(n)],"next_snapshot_id"=>segment.payload["next_snapshot_id"],
        "thermal"=>thermal,"soc_MWh"=>soc,"result_sha256"=>result_sha)
    return Dict("schema"=>"paper_a_segment_state_v1","payload"=>payload,"sha256"=>_paper_a_canonical_digest(payload))
end
