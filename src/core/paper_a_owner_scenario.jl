function _paper_a_owner_scenario(data)
    marker=get(data,"paper_a_extension",nothing)
    marker isa AbstractDict && haskey(marker,"owner_scenario") || return nothing
    owner=marker["owner_scenario"]
    owner isa AbstractDict && get(owner,"id",nothing)=="PAPER_A_OWNER_DKGPUN_V1" ||
        throw(ArgumentError("Unsupported AP1 owner scenario"))
    return owner
end

const _PAPER_A_CARRIER_UC_MODE="CSV_CARRIER_EUR2025_REFERENCE"
const _PAPER_A_UC_RAMP_FIELDS=("ramp_limit_up","ramp_limit_down","ramp_limit_start_up","ramp_limit_shut_down")
# Columns from the SHA-pinned PyPSA-Eur unit_commitment.csv.
const _PAPER_A_CARRIER_UC_FIELDS=("start_up_cost","min_up_time","min_down_time","p_min_pu",_PAPER_A_UC_RAMP_FIELDS...)
const _PAPER_A_CARRIER_UC=Dict(
    "OCGT"=>(24,0,0,0.2,1,1,0.8,0.8),"CCGT"=>(60,4,2,0.45,1,1,0.5,0.5),
    "coal"=>(49,8,8,0.38,0.9,0.9,0.4,0.4),"lignite"=>(49,8,8,0.5,0.6,0.6,0.4,0.4),
    "nuclear"=>(250,10,10,0.5,0.3,0.3,0.2,0.2))

_paper_a_carrier_uc(data)=get(something(_paper_a_owner_scenario(data),Dict()),"uc_tariff_mode",nothing)==_PAPER_A_CARRIER_UC_MODE

function _paper_a_validate_carrier_scope(owner)
    for (field,expected) in (("uc_csv_commit","d02406c44bf8aad9c2979521b8f393cf98b26262"),
        ("uc_csv_sha256","22eddbe84d01160e22b0755b9b9774c3a389ad5ca5eede9d527b9c98ea37b801"),
        ("uc_initial_boundary","INITIAL_ACTIVE_ZERO_WITH_FREE_END"),
        ("uc_initial_min_down","ASSUME_MIN_DOWN_SATISFIED_BEFORE_GLOBAL_START"),
        ("uc_ramp_scope","RAMP_CONSTRAINTS_NOT_ENFORCED"))
        get(owner,field,nothing)==expected || throw(ArgumentError("Owner carrier UC requires $field=$expected"))
    end
    for (field,expected) in (("uc_shutdown_factor",0.2),("uc_price_year",2025),("uc_price_conversion_factor",1))
        PaperARegional.number(owner,field)==expected || throw(ArgumentError("Owner carrier UC requires $field=$expected"))
    end
end

function _paper_a_validate_block_capacity(dev)
    capacity=get(dev,"paper_a_block_capacity",nothing)
    capacity isa AbstractDict || throw(ArgumentError("Missing original generator block capacity provenance"))
    nominal=PaperARegional.number(capacity,"original_p_nom_MW";nonnegative=true)
    maximum=PaperARegional.number(capacity,"original_p_nom_max_MW";nonnegative=true)
    p=PaperARegional.number(dev,"p_block_max_MW";positive=true)
    n0=_paper_a_owner_count(dev,"n0";existing=true)
    nmax=_paper_a_owner_count(dev,"nmax";existing=true)
    upper=nmax*p
    0<=nominal<=maximum && n0<=nmax && (iszero(nominal) ? n0==0 : n0>=2) &&
        isapprox(n0*p,nominal;atol=1e-8,rtol=1e-9) &&
        (upper<=maximum || isapprox(upper,maximum;atol=1e-8,rtol=1e-9)) ||
        throw(ArgumentError("Generator block counts do not preserve original installed MW or the investment cap"))
    return (nominal,maximum,p,n0,nmax)
end

function _paper_a_validate_carrier_uc(dev,capacity,weight)
    carrier=get(dev,"carrier",nothing)
    uc=get(dev,"paper_a_carrier_uc",nothing)
    haskey(dev,"paper_a_native_uc") && throw(ArgumentError("Carrier UC cannot use the native tariff contract"))
    if !haskey(_PAPER_A_CARRIER_UC,carrier)
        uc===nothing && get(dev,"committable",false)===false ||
            throw(ArgumentError("No pinned UC CSV reference for thermal carrier $carrier"))
        return nothing
    end
    capacity!==nothing && uc isa AbstractDict && get(dev,"committable",nothing)===true && get(dev,"gen_status",nothing)==1 ||
        throw(ArgumentError("Missing carrier UC reference for thermal generator $carrier"))
    nominal,maximum,p=capacity
    name=get(dev,"name",nothing)
    block=get(uc,"block_id",nothing)
    name isa AbstractString && !isempty(name) && get(uc,"generator_id",nothing)==name &&
        get(uc,"carrier",nothing)==carrier && block isa AbstractString && !isempty(strip(block)) ||
        throw(ArgumentError("Carrier UC generator, carrier or block identity mismatch"))
    for (field,expected) in (("original_p_nom_MW",nominal),("original_p_nom_max_MW",maximum),("P_block_MW",p))
        PaperARegional.number(uc,field;nonnegative=true)==expected ||
            throw(ArgumentError("Carrier UC block capacity metadata disagrees with the generator"))
    end
    ref=get(uc,"csv_reference",nothing)
    values=_PAPER_A_CARRIER_UC[carrier]
    ref isa AbstractDict && Set(keys(ref))==Set(_PAPER_A_CARRIER_UC_FIELDS) &&
        all(PaperARegional.number(ref,key)==value for (key,value) in zip(_PAPER_A_CARRIER_UC_FIELDS,values)) ||
        throw(ArgumentError("Carrier UC reference differs from the pinned CSV for $carrier"))
    _paper_a_owner_count(dev,"na0";existing=true)==0 && _paper_a_owner_count(dev,"min_up_block_time")==values[2] &&
        _paper_a_owner_count(dev,"min_down_block_time")==values[3] && PaperARegional.number(dev,"p_min_pu")==values[4] &&
        PaperARegional.number(dev,"p_max_pu")>=values[4] ||
        throw(ArgumentError("Carrier UC thermal initial state, minimum times or minimum output disagree for $carrier"))
    for (field,expected) in (("startup_cost_per_mw",values[1]*weight),("shutdown_cost_per_mw",values[1]*weight/5))
        isapprox(PaperARegional.number(dev,field;nonnegative=true),expected;atol=1e-9,rtol=1e-9) ||
            throw(ArgumentError("Carrier UC runtime $field disagrees with the CSV/Owner tariff"))
    end
    haskey(uc,"native_startup_control") || throw(ArgumentError("Missing carrier UC native startup audit slot"))
    uc["native_startup_control"]===nothing || PaperARegional.number(uc,"native_startup_control";nonnegative=true)>=0 ||
        throw(ArgumentError("Invalid carrier UC startup audit slot"))
    ramp=get(uc,"native_ramp_control",nothing)
    ramp isa AbstractDict && all(k->k in _PAPER_A_UC_RAMP_FIELDS,keys(ramp)) &&
        all(isfinite(PaperARegional.number(ramp,k)) for k in keys(ramp)) &&
        all(get(dev,k,nothing)===nothing for k in _PAPER_A_UC_RAMP_FIELDS) &&
        get(uc,"ramp_required",false)===false && get(dev,"ramp_required",false)===false ||
        throw(ArgumentError("Owner carrier UC does not enforce ramp constraints"))
    return block
end

function _paper_a_owner_count(data,field;existing=false)
    value=get(data,field,nothing)
    if value isa Integer && !(value isa Bool) && 0<=value<=typemax(Int)
        return Int(value)
    end
    if existing && value isa AbstractFloat && isfinite(value) && isinteger(value) && 0<=value<Float64(typemax(Int))
        return Int(value)
    end
    throw(ArgumentError("Owner scenario requires a nonnegative integer $field"))
end

function _paper_a_native_uc_price(native,event,p,n0,nmax)
    value=PaperARegional.number(native,"$(event)_original_value";positive=event=="startup",nonnegative=true)
    unit=get(native,"$(event)_unit",nothing)
    if unit=="EUR_per_generator_event"
        n0==nmax==1 || throw(ArgumentError("Native per-generator UC tariff requires one original block"))
    elseif !(unit in ("EUR_per_MW_event","EUR_per_block_event"))
        throw(ArgumentError("Unsupported native UC $event event unit"))
    end
    factor=PaperARegional.number(native,"factor_to_EUR2025";positive=true)
    price=value*factor/(unit=="EUR_per_MW_event" ? 1.0 : p)
    isfinite(price) || throw(ArgumentError("Nonfinite native UC $event tariff in EUR2025"))
    return price
end

function _paper_a_validate_native_uc(dev,native,event_weight)
    native isa AbstractDict || throw(ArgumentError("Invalid native UC metadata"))
    carrier=get(dev,"carrier",nothing)
    carrier isa AbstractString && get(native,"carrier",nothing)==carrier ||
        throw(ArgumentError("Native UC carrier does not match the generator"))
    generator=get(dev,"name",nothing)
    generator isa AbstractString && !isempty(generator) && get(native,"generator_id",nothing)==generator ||
        throw(ArgumentError("Native UC generator identity mismatch"))
    get(dev,"committable",nothing)===true || throw(ArgumentError("Native UC generator must be committable"))
    block=get(native,"block_id",nothing)
    block isa AbstractString && !isempty(strip(block)) || throw(ArgumentError("Native UC requires block_id"))
    _paper_a_sha256_string(get(native,"evidence_sha256",nothing)) ||
        throw(ArgumentError("Native UC requires an evidence SHA-256"))
    get(native,"original_currency",nothing)=="EUR" && _paper_a_owner_count(native,"original_price_year")>0 ||
        throw(ArgumentError("Native UC requires explicit original EUR currency and price year"))
    p=PaperARegional.number(native,"P_block_MW";positive=true)
    isapprox(p,PaperARegional.number(dev,"p_block_max_MW";positive=true);atol=1e-9,rtol=1e-9) ||
        throw(ArgumentError("Native UC block MW disagrees with the generator block"))
    n0=_paper_a_owner_count(dev,"n0";existing=true)
    nmax=_paper_a_owner_count(dev,"nmax";existing=true)
    _paper_a_owner_count(native,"na0")==_paper_a_owner_count(dev,"na0";existing=true) ||
        throw(ArgumentError("Native UC na0 disagrees with the generator block"))
    for field in ("min_up_block_time","min_down_block_time")
        _paper_a_owner_count(native,field)==_paper_a_owner_count(dev,field) ||
            throw(ArgumentError("Native UC $field disagrees with the generator block"))
    end
    prior_up=_paper_a_owner_count(native,"prior_uptime_h")
    prior_down=_paper_a_owner_count(native,"prior_downtime_h")
    na0=native["na0"]
    na0<=n0 && (na0>0 || prior_up==0) && (na0<n0 || prior_down==0) ||
        throw(ArgumentError("Native UC prehistory disagrees with the initial block counts"))
    get(native,"ramp_required",false)===false && all(get(d,k,nothing)===nothing for d in (native,dev)
        for k in ("ramp_limit_up","ramp_limit_down","ramp_limit_start_up","ramp_limit_shut_down")) ||
        throw(ArgumentError("Owner scenario native UC ramp constraints are unsupported"))
    for event in ("startup","shutdown")
        expected=_paper_a_native_uc_price(native,event,p,n0,nmax)*event_weight
        actual=PaperARegional.number(dev,"$(event)_cost_per_mw";nonnegative=true)
        isfinite(expected) && isapprox(actual,expected;atol=1e-8,rtol=1e-9) ||
            throw(ArgumentError("Native UC $event tariff disagrees with its evidence or event weight"))
    end
    return block
end

function _paper_a_validate_owner_roster(data,owner)
    mode=get(owner,"phs_mode",nothing)
    mode in ("MAIN","HYPOTHETICAL_PHS_3H") || throw(ArgumentError("Unsupported owner PHS mode"))
    main=mode=="MAIN"
    names=get(owner,"phs_assets",nothing)
    roster=get(owner,"phs_roster",nothing)
    names isa AbstractVector && all(n->n isa AbstractString && !isempty(n),names) &&
        allunique(names) && roster isa AbstractDict && Set(names)==Set(keys(roster)) ||
        throw(ArgumentError("Owner scenario PHS assets and roster differ or duplicate an identity"))
    length(names)==5 || throw(ArgumentError("Owner PHS roster must contain five assets"))
    _paper_a_synthetic_case(data) || Set(names)==Set(("LU1 0 PHS","ME1 0 PHS","RS1 0 PHS","SI1 0 PHS","SK1 0 PHS")) ||
        throw(ArgumentError("Owner PHS roster differs from the five ratified Full37 assets"))
    overrides=get(data["paper_a_extension"],"storage_duration_overrides",Dict())
    if main
        overrides isa AbstractDict && isempty(overrides) || throw(ArgumentError("Main-case storage duration overrides are forbidden"))
    else
        overrides isa AbstractDict && Set(keys(overrides))==Set(names) &&
            all(v->v isa AbstractDict && get(v,"effective_max_hours",nothing)==3,values(overrides)) ||
            throw(ArgumentError("Hypothetical PHS duration overrides must match the three-hour roster"))
    end
    for (name,row) in roster
        row isa AbstractDict || throw(ArgumentError("Invalid owner PHS roster row $name"))
        bus=get(row,"bus",nothing)
        get(row,"carrier",nothing)=="PHS" && bus isa AbstractString && !isempty(bus) ||
            throw(ArgumentError("Owner PHS roster row $name requires its original bus and carrier"))
        p=PaperARegional.number(row,"p_nom_MW";positive=true)
        all(haskey(row,key) for key in ("native_max_hours","effective_max_hours","effective_energy_MWh","fixed_E0_MWh")) ||
            throw(ArgumentError("Incomplete owner PHS roster row $name"))
        native_hours=row["native_max_hours"]
        (native_hours===nothing || (native_hours isa Real && !(native_hours isa Bool) && iszero(native_hours))) &&
            row["fixed_E0_MWh"]===nothing || throw(ArgumentError("Owner PHS roster $name must preserve missing native duration and no fixed E0"))
        if main
            get(row,"disposition",nothing)=="PHS_STORAGE_OPERATION_EXCLUDED_IN_MAIN_CASE" &&
                row["effective_max_hours"]===row["effective_energy_MWh"]===nothing ||
                throw(ArgumentError("Main-case PHS $name cannot have an effective capacity"))
        else
            get(row,"disposition",nothing)==mode && row["effective_max_hours"]==3 &&
                isapprox(PaperARegional.number(row,"effective_energy_MWh";positive=true),3*p;atol=1e-8,rtol=1e-9) ||
                throw(ArgumentError("Hypothetical PHS $name must have three-hour capacity"))
        end
    end
    return nothing
end

function _paper_a_validate_owner_phs(sn,net,owner)
    roster=owner["phs_roster"]
    main=owner["phs_mode"]=="MAIN"
    bindings=get(net,"fixed_source_shunt_by_asset",Dict())
    fixed=get(net,"fixed_sources_in_network",String[])
    any(name->name in fixed || haskey(bindings,name),keys(roster)) &&
        throw(ArgumentError("Owner PHS roster assets cannot be fixed sources or source shunts"))
    seen=Set{String}()
    for table in ("gen","storage","ne_storage"), dev in values(get(sn,table,Dict()))
        name=get(dev,"name",nothing)
        haskey(roster,name) || continue
        !main && table=="storage" && !(name in seen) ||
            throw(ArgumentError("Excluded or duplicated owner PHS asset $name in operational $table"))
        push!(seen,name)
        row=roster[name]
        native=get(dev,"paper_a_storage_unit",nothing)
        bus=get(sn["bus"],string(dev["storage_bus"]),Dict())
        native isa AbstractDict && get(dev,"carrier",nothing)=="PHS" &&
            get(bus,"name",nothing)==row["bus"] && get(dev,"status",nothing)==1 &&
            get(native,"p_nom_MW",nothing)==row["p_nom_MW"] && get(native,"max_hours",nothing)==3 &&
            get(native,"cyclic_state_of_charge",nothing)===true && haskey(native,"state_of_charge_initial_MWh") &&
            native["state_of_charge_initial_MWh"]===nothing && get(dev,"fixed_strength_already_in_network",false)===false ||
            throw(ArgumentError("Hypothetical PHS $name must preserve its native bus, power and cyclic boundary"))
    end
    main || seen==Set(keys(roster)) || throw(ArgumentError("Hypothetical PHS roster is incomplete in a snapshot"))
    return nothing
end

function _paper_a_validate_owner_dc(sn,owner,base)
    mode=owner["dc_construction_mode"]
    rows=Dict{String,Any}()
    for (id,line) in get(sn,"dcline",Dict())
        native=get(line,"paper_a_native_dc",nothing)
        native isa AbstractDict && get(native,"construction_mode",nothing)==mode ||
            throw(ArgumentError("Missing owner HGÜ metadata or construction mode for dcline $id"))
        name=get(line,"name",nothing)
        name isa AbstractString && !isempty(name) && !haskey(rows,name) ||
            throw(ArgumentError("Missing or duplicate original HGÜ identity $id"))
        nominal=PaperARegional.number(native,"p_nom_MW";nonnegative=true)
        under_construction=get(native,"under_construction",nothing)
        active=get(native,"native_active",nothing)
        status=get(native,"native_status",nothing)
        under_construction isa Bool && active isa Bool && status isa Bool ||
            throw(ArgumentError("Invalid native HGÜ availability flags for $name"))
        availability=PaperARegional.number(native,"native_availability";nonnegative=true)
        effective=PaperARegional.number(native,"effective_availability";nonnegative=true)
        haskey(native,"native_efficiency") || throw(ArgumentError("Missing native HGÜ efficiency provenance for $name"))
        efficiency=native["native_efficiency"]
        efficiency===nothing || PaperARegional.number(native,"native_efficiency";nonnegative=true)<=1 ||
            throw(ArgumentError("Invalid native HGÜ efficiency for $name"))
        pmin=PaperARegional.number(native,"p_min_pu")
        pmax=PaperARegional.number(native,"p_max_pu")
        -1<=pmin<=pmax<=1 && availability in (0,1) || throw(ArgumentError("Invalid native HGÜ limits or availability for $name"))
        expected=active && status && !(under_construction && mode=="CONSTRUCTION_OFF") ? availability : 0.0
        effective==expected && get(line,"br_status",nothing)==Int(effective>0) ||
            throw(ArgumentError("Owner HGÜ availability/status mismatch for $name"))
        lo,hi=nominal*effective*pmin,nominal*effective*pmax
        for (field,value) in (("pminf",lo),("pmaxf",hi),("pmint",-hi),("pmaxt",-lo))
            isapprox(PaperARegional.number(line,field)*base,value;atol=1e-8,rtol=1e-9) ||
                throw(ArgumentError("Owner HGÜ signed $field mismatch for $name"))
        end
        all(iszero(PaperARegional.number(line,field)) for field in ("loss0","loss1")) ||
            throw(ArgumentError("Owner HGÜ requires lossless operation for $name"))
        rows[name]=(id,line["f_bus"],line["t_bus"],nominal,under_construction,active,efficiency)
    end
    return rows
end

function _paper_a_validate_owner_bess(sn,owner,base)
    for table in ("storage","ne_storage"),dev in values(get(sn,table,Dict()))
        carrier=get(dev,"carrier",nothing)
        carrier isa AbstractString && _paper_a_expansion_group(Symbol(table),carrier)===:bess || continue
        name=get(dev,"name",nothing)
        record=get(dev,"paper_a_bess_cost",nothing)
        record isa AbstractDict && get(record,"source",nothing)=="frozen_2040_EUR2025_P_plus_E" ||
            throw(ArgumentError("Missing owner BESS cost provenance for $name"))
        power=PaperARegional.number(record,"power_cost_per_mw_year";positive=true)
        energy=PaperARegional.number(record,"energy_cost_per_mwh_year";positive=true)
        power==19758.59100216229 && energy==10128.316776565933 ||
            throw(ArgumentError("Owner BESS $name requires frozen 2040/EUR2025 P/E components"))
        cls=get(dev,"source_class",nothing)
        cls in ("GFL","GFM") || throw(ArgumentError("Owner BESS $name requires GFL or GFM classification"))
        premium=cls=="GFM" ? owner["bess_gfm_premium"] : 0.0
        native=get(dev,"paper_a_storage_unit",nothing)
        if native===nothing
            get(dev,"candidate_added_by_converter",false)===true && cls=="GFM" &&
                get(dev,"n0",nothing)==get(dev,"na0",nothing)==0 ||
                throw(ArgumentError("Owner BESS $name lacks native storage or derived GFM candidate identity"))
        end
        duration=native===nothing ? owner["bess_duration_h"] : native["max_hours"]
        duration in (4,6) && PaperARegional.number(record,"duration_h")==duration &&
            PaperARegional.number(record,"gfm_premium";nonnegative=true)==premium ||
            throw(ArgumentError("Owner BESS $name duration or GFM premium mismatch"))
        block_p=PaperARegional.number(dev,"p_block_max_MW";positive=true)
        e=PaperARegional.number(dev,"e_block";positive=true)*base
        isapprox(e,duration*block_p;atol=1e-8,rtol=1e-9) || throw(ArgumentError("Owner BESS $name block energy mismatch"))
        expected=(1+premium)*(power+duration*energy)
        for (row,field) in ((record,"cost_per_mw_year"),(dev,"cost_inv_per_mw"))
            isapprox(PaperARegional.number(row,field;positive=true),expected;atol=1e-8,rtol=1e-9) ||
                throw(ArgumentError("Owner BESS $name annualized P/E cost or one-time GFM premium mismatch"))
        end
    end
    return nothing
end

function _paper_a_validate_owner_case(data,binding)
    owner=_paper_a_owner_scenario(data)
    owner===nothing && return nothing
    binding!==nothing || _paper_a_origin_unverified("owner scenario requires a case or profile SHA-256")
    _paper_a_expansion_peaks(data)!==nothing || throw(ArgumentError("Owner scenario requires nodal expansion limits"))
    mode=get(owner,"uc_tariff_mode",nothing)
    carrier_mode=mode==_PAPER_A_CARRIER_UC_MODE
    mode in ("QUALIFIED_NATIVE",_PAPER_A_CARRIER_UC_MODE) || throw(ArgumentError("Unsupported owner UC tariff mode"))
    carrier_mode && _paper_a_validate_carrier_scope(owner)
    get(owner,"dc_construction_mode",nothing) in ("REFERENCE_2040","CONSTRUCTION_OFF") ||
        throw(ArgumentError("Unsupported owner HGÜ construction mode"))
    PaperARegional.number(owner,"bess_duration_h") in (4,6) || throw(ArgumentError("Unsupported owner BESS duration"))
    PaperARegional.number(owner,"bess_gfm_premium";nonnegative=true) in (0,0.1,0.2,0.3) ||
        throw(ArgumentError("Unsupported owner BESS GFM premium"))
    _paper_a_validate_owner_roster(data,owner)
    get(data,"multinetwork",false) || throw(ArgumentError("Owner scenario requires a chronological multinetwork"))
    snapshots=data["nw"]
    temporal=data["paper_a_temporal"]
    segment=_paper_a_validate_segment_binding(data)
    segment===nothing || carrier_mode || throw(ArgumentError("Daily segments require owner carrier UC"))
    dt=PaperARegional.number(first(temporal),"delta_t_h";positive=true)
    synthetic=_paper_a_synthetic_case(data)
    if segment===nothing && haskey(owner,"source_snapshot_count")
        length(temporal)==_paper_a_owner_count(owner,"source_snapshot_count") ||
            throw(ArgumentError("Owner scenario chronology was cropped"))
    end
    if !synthetic
        if segment===nothing
            length(temporal)==8760 && dt==1 &&
                tryparse(Dates.DateTime,replace(first(temporal)["snapshot_id"],' '=>'T'))==Dates.DateTime(2013,1,1) ||
                throw(ArgumentError("Owner scenario requires the full hourly 2013 chronology"))
        end
        source=get(owner,"source_binding",nothing)
        source isa AbstractDict && get(source,"original_netcdf_sha256",nothing)=="b0db326f4e01c7c4df363c692831102ac042e07cb6156af70f01f9addd9706dc" &&
            all(_paper_a_sha256_string(get(source,key,nothing)) for key in ("source_attribution_evidence_sha256",
                "csv_derivation_evidence_sha256","derived_csv_bundle_sha256")) ||
            throw(ArgumentError("Owner Full37 scenario requires the pinned NetCDF and attribution/derivation evidence SHA-256s"))
        owner["phs_mode"]=="MAIN" || _paper_a_sha256_string(get(source,"phs_boundary_evidence_sha256",nothing)) ||
            throw(ArgumentError("Real hypothetical PHS scenario requires boundary evidence SHA-256"))
    end
    base=get(data,"per_unit",false) ? data["baseMVA"] : 1.0
    baseline_uc=baseline_dc=baseline_cap=nothing
    for t in eachindex(temporal)
        time=temporal[t]
        time["delta_t_h"]==dt || throw(ArgumentError("Owner scenario UC requires uniform snapshot duration"))
        (synthetic && !carrier_mode) || all(time[k]==1 for k in ("event_weight","event_repetitions","scenario_probability",
            "dispatch_weight","representative_repetitions","delta_t_h")) ||
            throw(ArgumentError("Owner scenario requires unit chronological dispatch and event weights"))
        sn=snapshots[string(t)]
        _paper_a_validate_owner_phs(sn,data["paper_a_network"],owner)
        weighted=get(sn,"paper_a_cost_state","raw_hourly")=="weighted"
        convention=get(sn,"uc_gscr_block_cost_convention",get(data,"uc_gscr_block_cost_convention",Dict()))
        convention isa AbstractDict && get(convention,"capex_basis",nothing)=="annualized_per_mw_year" &&
            get(data,"investment_period_fraction",1)==1 || throw(ArgumentError("Owner scenario requires one annualized CAPEX year"))
        !weighted || (get(sn,"paper_a_currency_factor",nothing)==1 && get(sn,"paper_a_investment_fraction_applied",nothing)==1) ||
            throw(ArgumentError("Owner scenario requires one EUR2025 CAPEX year and no currency rescaling"))
        _paper_a_validate_owner_bess(sn,owner,base)
        uc=Dict{String,Any}()
        capacities=Dict{String,Any}()
        blocks=Set{String}()
        for (id,dev) in get(sn,"gen",Dict())
            weight=weighted ? time["event_weight"] : 1.0
            if carrier_mode
                capacity=haskey(dev,"n0") ? _paper_a_validate_block_capacity(dev) : nothing
                capacity!==nothing || !any(PaperARegional.number(dev,k)>0 for k in ("pmin","pmax")) ||
                    throw(ArgumentError("Positive generator $id requires the carrier scenario block capacity record"))
                capacity===nothing || (capacities[id]=(dev["name"],dev["carrier"],dev["gen_bus"],capacity))
                block=_paper_a_validate_carrier_uc(dev,capacity,weight)
                block===nothing && continue
                block in blocks && throw(ArgumentError("Duplicate carrier UC block identity $block"))
                push!(blocks,block)
                uc[id]=(dev["name"],dev["paper_a_carrier_uc"])
                continue
            end
            native=get(dev,"paper_a_native_uc",nothing)
            gas=haskey(dev,"carrier") && _paper_a_expansion_group(:gen,dev["carrier"])===:gas
            if native===nothing
                (gas || get(dev,"committable",false)===true) &&
                    throw(ArgumentError("Owner scenario generator $id lacks qualified native UC tariffs"))
                continue
            end
            block=_paper_a_validate_native_uc(dev,native,weight)
            block in blocks && throw(ArgumentError("Duplicate native UC block identity $block"))
            push!(blocks,block)
            uc[id]=(get(dev,"name",nothing),native)
        end
        baseline_uc===nothing && (baseline_uc=uc)
        isequal(uc,baseline_uc) || throw(ArgumentError("Native UC block evidence changes across snapshots"))
        baseline_cap===nothing && (baseline_cap=capacities)
        isequal(capacities,baseline_cap) || throw(ArgumentError("Generator block capacity or identity changes across snapshots"))
        dc=_paper_a_validate_owner_dc(sn,owner,base)
        synthetic || (length(dc)==43 && count(row->row[5],values(dc))==17 &&
            Set(name for (name,row) in dc if iszero(row[4]))==Set(("14804+1",))) ||
            throw(ArgumentError("Owner HGÜ roster requires 43 links, 17 construction cases and the original zero-rating identity"))
        baseline_dc===nothing && (baseline_dc=dc)
        isequal(dc,baseline_dc) || throw(ArgumentError("Owner HGÜ identity, terminals or original rating changed across snapshots"))
    end
    return nothing
end

function _paper_a_native_uc_history_lock(pm,nw,device_key,minimum;online)
    _paper_a_owner_scenario(pm.data)===nothing && return 0
    if _paper_a_carrier_uc(pm.data)
        return _paper_a_segment_history(pm,nw,device_key,minimum;online)
    end
    dev=_PM.ref(pm,nw,device_key...)
    dt=_PM.ref(pm,nw,:paper_a_temporal).delta_t_h
    elapsed=(coord(pm,nw,:hour)-1)*dt
    prior=dev["paper_a_native_uc"][online ? "prior_uptime_h" : "prior_downtime_h"]
    prior+elapsed+1e-9<minimum*dt || return 0
    # Only legacy blocks have an observed pre-horizon offline duration.
    return online ? dev["na0"] : dev["n0"]-dev["na0"]
end
