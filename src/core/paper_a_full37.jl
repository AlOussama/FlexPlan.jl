# Full37's owner-approved selectors are scoped to one frozen operating specification.
const _PAPER_A_FULL37_PINS = (
    "case_manifest_sha256"=>"ec4986d4de0853f6a8188c0add991a139d014c247adee6cb960fae29416a4e9a",
    "scenario_sha256"=>"4050d788a635ea9b6f4749923ad8cf49c5689d33191974a09d3a195b9a68da81",
    "source_mapping_sha256"=>"07c544132d61e4098271e5a06985585bbf38f96ecca52e8614eecab654119bcf",
    "parameter_sha256"=>"cfb38932479a57051d33fe8055ceed037256bc53d682f1be36e9e4251808b6d3",
    "online_selector_sha256"=>"55a39318a595c275925a8f8e1c62b169097c3d0172a56e909417077f028398e9",
    "phs_mode_sha256"=>"fb7fd61891eb2bed828f8e54b1ac022f30f4592bd9ee33bc90f6c808dc758add",
)
const _PAPER_A_SELECTIVE_SYN = Dict("hydro"=>0.3,"ror"=>0.3,"biomass"=>0.5,"oil"=>0.2)
const _PAPER_A_FULL37_DISPATCH_POLICY = "reservoir_no_gscr_oil_coal_minimum_v1"
const _PAPER_A_FULL37_NON_RESERVOIR_SELECTORS_SHA = "b1ea9cc64f4e2e94667737d9bacc591bb5106faee0b9d99e1d60665fb01351fe"
# SHA of the ordered rational vector rounded once to Float64, represented as
# newline-delimited sixteen-digit hexadecimal IEEE-754 bit patterns.
const _PAPER_A_FULL37_G2_NUMERIC_SHA="5fee28dc98c8384c4c4c35edeef29a59210e1f84629428db6ff845036e390939"
const _PAPER_A_FULL37_G2_ORDERED_SHA="92804d711119cb0af0cd768232bc3186ef68c29bcbe48976d2894f469102f9f7"
const _PAPER_A_FULL37_G2_FILE_SHA="8dc5b0f29038a5c2775e2b91252bd9e9e5b3e4658c4e284c802e25bc920f6926"
const _PAPER_A_FULL37_SOURCE_ROLES_SHA="e43afdd45bbbec8e6e7e75957d6e9db24a0a3cd5466fd3d624f7eea9fb01c6f5"
const _PAPER_A_FULL37_ROSTER_SHA = Dict(
    "SELECTIVE_SYN"=>"536da2362da0fd88e489c1d5681e02880ee295c57e6f9f32f302bef95a12785c",
    "PHS_SYN"=>"fcd44db91997d52e26006cba999ae3d3cffe1af9ba84faf6b3fc9c8dbe818695",
    "GFL"=>"bf40e0c061526f56b59d4a02fa220b3705af8add36514f22b277973d8c7ea5d6",
    "GFM"=>"db8b8621eb8436c087cd88d6e78fd16e7fd17f0c470e4341630e975c6db6c62d",
)

_paper_a_full37_lines_sha(lines)=bytes2hex(SHA.sha256(join(lines,'\n')))

_paper_a_full37(data)=get(get(data,"paper_a_extension",Dict()),"full37_specification",nothing)
_paper_a_full37_mode(dev)=get(get(dev,"paper_a_full37_online",Dict()),"mode",nothing)
_paper_a_full37_minimum(dev)=dev["paper_a_full37_online"]["strength_minimum_pu"]

const _PAPER_A_GFM_PROXY_ID="colib_epri_frozen_E_blocks_v1"

function _paper_a_gfm_proxy(data)
    spec=_paper_a_full37(data)
    spec===nothing && return nothing
    proxy=get(spec,"technical_gfm_source_proxy",nothing)
    proxy===nothing && return nothing
    week=get(spec,"technical_week",Dict())
    get(week,"kind",nothing)=="technical_independent_week_2013_v1" &&
        get(week,"hours",nothing)==168 && length(get(data,"nw",Dict()))==168 &&
        data["baseMVA"]==100 && get(proxy,"model",nothing)==_PAPER_A_GFM_PROXY_ID &&
        get(proxy,"scope",nothing)=="frozen_E_planning_proxy" &&
        get(proxy,"x_device_pu",nothing)==0.15 && get(proxy,"r_device_pu",nothing)==0.0015 &&
        get(proxy,"S_block_MVA",nothing)==25 && get(proxy,"synchronous_xdpp",nothing)==0.25 &&
        _paper_a_sha256_string(get(proxy,"parent_AP1_sha256",nothing)) &&
        get(proxy,"owner_decision",nothing)=="2026-11-17: bilde beide modelle gleich ähnlich aus" ||
        throw(ArgumentError("GFM proxy is restricted to the separately identified owner-selected 168h technical case"))
    return proxy
end

function _paper_a_validate_gfm_proxy_device(dev)
    get(dev,"source_equivalent_type",nothing)=="voltage_behind_series_impedance_frozen_E" &&
        dev["x_src"]==0.15 && dev["r_src"]==0.0015 &&
        dev["S_block_MVA"]==dev["native_source_MVA"]==25 &&
        dev["native_parameter_base"]=="block_MVA" && dev["S_base_MVA"]==100 &&
        dev["mu_str"]==1 && dev["mu_fl"]==0 &&
        dev["fixed_strength_already_in_network"]===false &&
        get(dev,"native_source_kv_referred",nothing)==get(dev,"source_bus_base_kv",nothing) ||
        throw(ArgumentError("GFM proxy source coefficients or bases differ from the qualified component"))
    PaperARegional.validate_source(dev)
    return nothing
end

"""Create a separately identified technical source variant after authenticated AP1 parsing.
Original AP1 files remain unchanged; callers must save/hash the derived AP2 bytes.
Only GFM source fields change. No physical EPRI controller qualification is asserted."""
function apply_paper_a_gfm_source_proxy!(data;parent_AP1_sha256)
    _paper_a_sha256_string(parent_AP1_sha256) || throw(ArgumentError("invalid parent AP1 SHA-256"))
    binding=_paper_a_profile_binding(data;allow_unverified=_paper_a_synthetic_case(data))
    spec=_paper_a_full37(data)
    spec isa AbstractDict && !haskey(spec,"technical_gfm_source_proxy") ||
        throw(ArgumentError("GFM proxy requires an unmodified technical parent case"))
    _paper_a_validate_full37(data,binding)
    binding===nothing || binding.run_identity=="ap1:sha256:"*parent_AP1_sha256 ||
        throw(ArgumentError("GFM proxy parent bytes do not match the authenticated AP1 identity"))
    proxy=Dict{String,Any}("model"=>_PAPER_A_GFM_PROXY_ID,"scope"=>"frozen_E_planning_proxy",
        "x_device_pu"=>0.15,"r_device_pu"=>0.0015,"S_block_MVA"=>25,
        "synchronous_xdpp"=>0.25,"parent_AP1_sha256"=>parent_AP1_sha256,
        "owner_decision"=>"2026-11-17: bilde beide modelle gleich ähnlich aus")
    # Stage the complete source delta, including bus bases, before modifying input.
    new_spec=merge(spec,Dict("technical_gfm_source_proxy"=>proxy))
    scoped=merge(data,Dict("paper_a_extension"=>merge(data["paper_a_extension"],
        Dict("full37_specification"=>new_spec))))
    _paper_a_gfm_proxy(scoped)
    proposed=Tuple{Any,Any}[]
    for sn in values(data["nw"])
        count_gfm=0
        for table in ("storage","ne_storage"),dev in values(get(sn,table,Dict()))
            get(dev,"source_class",nothing)=="GFM" || continue
            PaperARegional.validate_source(dev;zero_strength_gfm=true)
            kv=PaperARegional.number(sn["bus"][string(dev["storage_bus"])],"base_kv";positive=true)
            candidate=merge(dev,Dict("source_equivalent_type"=>"voltage_behind_series_impedance_frozen_E",
                "source_equivalent_valid"=>true,"frozen_internal_voltage"=>true,
                "source_model_scope"=>"frozen_E_planning_proxy","physical_controller_equivalent_qualified"=>false,
                "x_src"=>0.15,"r_src"=>0.0015,"S_base_MVA"=>100.0,"native_parameter_base"=>"block_MVA",
                "native_source_MVA"=>25.0,"native_source_kv_referred"=>kv,"source_bus_base_kv"=>kv,
                "x_src_block_base"=>0.15,"b_block"=>PaperARegional.source_b_block(25.,100.,.15,.0015),
                "mu_str"=>1.0,"mu_fl"=>0.0,"source_parameter_provenance"=>"EPRI_3002021403_2021_Table2-1_and_A3.5_fixed_E_owner_proxy",
                "source_equivalent_time_scale"=>"frozen_internal_E_component_at_each_hourly_operating_point",
                "electrical_interface_evidence"=>"EPRI_3002021403_voltage_source_series_RX_interface_fixed_E_proxy_only"))
            candidate["source_b_block_pu_reference"]=candidate["b_block"]
            candidate["paper_a_full37_online"]=Dict("mode"=>"GFM_FROZEN_E_PROXY","strength_minimum_pu"=>0.0)
            _paper_a_validate_gfm_proxy_device(candidate)
            push!(proposed,(dev,candidate))
            count_gfm+=1
        end
        count_gfm==37 || throw(ArgumentError("GFM proxy requires exactly 37 original candidates per snapshot"))
    end
    for (dev,candidate) in proposed
        merge!(dev,candidate)
    end
    data["paper_a_extension"]["full37_specification"]=new_spec
    for sn in values(data["nw"])
        sn["paper_a_extension"]["full37_specification"]=new_spec
    end
    _paper_a_advance_profile_binding!(data,binding)
    return data
end
_paper_a_dispatch_reservoir(data,dev)=get(something(_paper_a_full37(data),Dict()),"dispatch_policy",nothing)==
    _PAPER_A_FULL37_DISPATCH_POLICY && get(dev,"carrier",nothing)=="hydro"

function _paper_a_full37_variant_digest(v)
    lines = (
        "battery_mode=" * v["battery_mode"],
        "bess_duration_h=" * string(Int(v["bess_duration_h"])),
        "bess_gfm_premium=" * string(Float64(v["bess_gfm_premium"])),
        "dc_construction_mode=" * v["dc_construction_mode"],
        "formulation=" * v["formulation"],
        "alpha=" * string(Float64(v["alpha"])),
        "hours=" * string(Int(v["hours"])),
    )
    return _paper_a_full37_lines_sha(lines)
end

function _paper_a_full37_reservoir(dev, table)
    native = get(dev,"paper_a_storage_unit",nothing)
    table=="storage" && native isa AbstractDict && native["p_min_pu"]==0 &&
        get(dev,"status",nothing)==1 && get(dev,"committable",false)===false &&
        get(dev,"fixed_strength_already_in_network",false)===false &&
        all(k->!haskey(dev,k),("source_class","grid_control_mode","paper_a_full37_online",
            "paper_a_annual_cyclic","paper_a_carrier_uc","paper_a_native_uc",
            "n0","nmax","na0","p_block_max","p_block_max_MW","e_block","b_block","a_conn","mu_str","mu_fl")) &&
        PaperARegional.number(dev,"marginal_cost";nonnegative=true)>=0 ||
        throw(ArgumentError("Full37 reservoir $(dev["name"]) requires native non-pumping storage without block or source parameters"))
    return native
end

function _paper_a_full37_oil_minimum(dev)
    source=get(dev,"p_min_pu_source",nothing)
    lo=PaperARegional.number(dev,"p_min_pu")
    hi=PaperARegional.number(dev,"p_max_pu")
    coal_min=_PAPER_A_CARRIER_UC["coal"][4]
    0<=lo<=hi<=1 && (source=="pypsa_generator_time_series" || (source=="owner_coal_proxy" && lo==coal_min)) ||
        throw(ArgumentError("Full37 oil minimum must use its time series or the owner-approved coal proxy"))
end

function _paper_a_validate_full37_g2(spec,buses,synthetic)
    ordered_sha=get(spec,"g2_r_sha256",nothing)
    expected=synthetic ? ordered_sha : _PAPER_A_FULL37_G2_NUMERIC_SHA
    direction=get(spec,"g2_r",nothing)
    _paper_a_sha256_string(expected) && _paper_a_sha256_string(ordered_sha) &&
        (synthetic || (ordered_sha==_PAPER_A_FULL37_G2_ORDERED_SHA &&
            get(spec,"g2_r_file_sha256",nothing)==_PAPER_A_FULL37_G2_FILE_SHA)) &&
        get(spec,"g2_bus_order",nothing)==buses &&
        direction isa AbstractVector && length(direction)==length(buses) &&
        all(x->x isa Real && !(x isa Bool) && isfinite(x) && x>0,direction) &&
        _paper_a_full37_lines_sha(string(reinterpret(UInt64,Float64(x));base=16,pad=16) for x in direction)==expected ||
        throw(ArgumentError("Full37 requires the bound ordered G2 vector"))
    return nothing
end

function _paper_a_validate_full37(data,binding)
    spec=_paper_a_full37(data)
    source_proxy=_paper_a_gfm_proxy(data)
    snapshots=get(data,"multinetwork",false) ? data["nw"] : Dict("1"=>data)
    if spec===nothing
        get(data["paper_a_extension"],"dataset_kind",nothing)!="full37_frozen_study" ||
            throw(ArgumentError("Full37 dataset kind requires the frozen case specification"))
        any(haskey(dev,"paper_a_full37_online") || haskey(dev,"paper_a_annual_cyclic")
            for sn in values(snapshots) for table in ("gen","storage","ne_storage")
            for dev in values(get(sn,table,Dict()))) &&
            throw(ArgumentError("Full37 asset selector or cycle requires its case specification"))
        return nothing
    end
    synthetic=_paper_a_synthetic_case(data)
    spec isa AbstractDict && get(spec,"schema",nothing)=="paper_a_full37_frozen_v1" &&
        all(_paper_a_sha256_string(get(spec,key,nothing)) &&
            (synthetic ? spec[key]!=sha : spec[key]==sha) for (key,sha) in _PAPER_A_FULL37_PINS) ||
        throw(ArgumentError("Full37 scientific input identity mismatch"))
    dispatch_policy=get(spec,"dispatch_policy",nothing)
    dispatch_policy in (nothing,_PAPER_A_FULL37_DISPATCH_POLICY) ||
        throw(ArgumentError("Unsupported Full37 dispatch policy"))
    revised_dispatch=dispatch_policy==_PAPER_A_FULL37_DISPATCH_POLICY
    owner=_paper_a_owner_scenario(data)
    owner!==nothing && owner["phs_mode"]=="MAIN" && _paper_a_carrier_uc(data) ||
        throw(ArgumentError("Full37 requires the main PHS and carrier UC scenario"))
    v=get(spec,"variant",nothing)
    v isa AbstractDict && get(v,"battery_mode",nothing) in ("GFL_ONLY","GFM_ONLY","MIXED") &&
        get(v,"formulation",nothing) in ("G0","G1","G2","G3") &&
        PaperARegional.number(v,"alpha") in (0.5,1,2) &&
        all(get(v,k,nothing)==owner[k] for k in ("bess_duration_h","bess_gfm_premium","dc_construction_mode")) &&
        (v["battery_mode"]!="GFL_ONLY" || iszero(v["bess_gfm_premium"])) &&
        get(v,"hours",nothing)==8760 && get(spec,"variant_sha256",nothing)==_paper_a_full37_variant_digest(v) ||
        throw(ArgumentError("Full37 variant identity or owner scenario mismatch"))
    synthetic || (data["paper_a_extension"]["dataset_kind"]=="full37_frozen_study" &&
        length(snapshots)==8760 && data["baseMVA"]==100) ||
        throw(ArgumentError("Full37 requires 8760 snapshots on the 100 MVA case base"))
    if !synthetic || v["formulation"]=="G2" || haskey(spec,"g2_r")
        _paper_a_validate_full37_g2(spec,data["paper_a_network"]["retained_physical_buses"],synthetic)
    end

    if !synthetic
        binding!==nothing && startswith(binding.run_identity,"ap1:sha256:") ||
            _paper_a_origin_unverified("Full37 requires a pinned AP1 JSON and producer manifest")
        net=data["paper_a_network"]
        isempty(net["eliminated_physical_buses"]) && isempty(net["fixed_shunts"]) &&
            isempty(net["fixed_sources_in_network"]) && isempty(get(net,"fixed_strength_by_region_pu",Dict())) &&
            length(net["branch_primitives"])==52 && length(net["network_islands"])==7 &&
            net["retained_physical_buses"]==net["physical_ac_bus_order"] &&
            _paper_a_full37_lines_sha(net["physical_ac_bus_order"])==
                "cf564d60086e9e3c3ff4b87e47874b7657a6a7429ff7fb4694cedefbb82fdba6" &&
            _paper_a_full37_lines_sha(sort(net["reference_buses"]))==
                "4067999ded60f5f5914c5300af4f483fd4c8f175089bc097151ca7f9a5db283b" ||
            throw(ArgumentError("Full37 passive network and angle references differ from the frozen model"))
        for (key,sha) in (("original_netcdf_sha256","b0db326f4e01c7c4df363c692831102ac042e07cb6156af70f01f9addd9706dc"),
            ("original_csv_bundle_sha256","0182938d2f494789a07f8e5752a3cf0d9530ed03c576e2d1081035958edc871a"),
            ("cost_receipt_sha256","f5b1a0fd4054fb992c99c784f15064340e57418407ebf63ac3f7dd77ab70a5af"),
            ("uc_receipt_sha256","92727d1b56d4a269291da4a5566b8b254bdb456644ca74a2734d87e65ad6f9f8"),
            ("time_index_sha256","1dbf7e7d9522f6e43223b21a9e3a4a9a1c9314ef4866897a632c26512d95ddd4"))
            get(spec,key,nothing)==sha || throw(ArgumentError("Full37 input pin mismatch for $key"))
        end
        source=owner["source_binding"]
        get(source,"source_attribution_evidence_sha256",nothing)=="f5054f45d17d2df400a11d064657491bfd9dd741f34d8e121c03a5bbdffa16d0" &&
            get(source,"csv_derivation_evidence_sha256",nothing)=="8de4e0265bbef045db74afcfe6578a3bb0a844e7739b94fe2aa3f5e45a0e0a34" &&
            get(source,"derived_csv_bundle_sha256",nothing)=="0182938d2f494789a07f8e5752a3cf0d9530ed03c576e2d1081035958edc871a" ||
            throw(ArgumentError("Full37 source binding differs from the frozen attribution and derivation"))
    end
    baseline=nothing
    for sn in values(snapshots)
        get(sn,"g_min",nothing)==v["alpha"] || throw(ArgumentError("Full37 snapshot alpha mismatch"))
        # Renewable curtailment is represented by dispatch below the resource
        # envelope. This case has no separately qualified curtailment tariff.
        for dev in Iterators.flatten((values(get(sn,"ndgen",Dict())),values(get(sn,"gen",Dict()))))
            price=get(dev,"cost_curt",0)
            price isa Real && iszero(price) ||
                throw(ArgumentError("Full37 does not admit a separate curtailment cost"))
        end
        roster=Dict{Tuple{String,String},Tuple}()
        sources=String[]
        counts=Dict("hydro"=>0,"ror"=>0,"oil"=>0,"biomass"=>0,"phs"=>0,"gfl"=>0,"gfm"=>0)
        for table in ("gen","storage","ne_storage"), (id,dev) in get(sn,table,Dict())
            carrier=lowercase(dev["carrier"])
            if revised_dispatch && carrier=="hydro"
                native=_paper_a_full37_reservoir(dev,table)
                bus=sn["bus"][string(dev["storage_bus"])]["name"]
                roster[(table,id)]=(dev["name"],dev["carrier"],nothing,nothing,false,bus,
                    nothing,nothing,native["p_nom_MW"],nothing,dev["status"])
                counts[carrier]+=1
                if !synthetic && baseline===nothing
                    # Original physical source-class roster remains bound even
                    # when this reservoir earns no modelled source credit.
                    push!(sources,join((dev["name"],dev["carrier"],"SYN",bus),'\t'))
                end
                continue
            end
            revised_dispatch && carrier=="oil" && table=="gen" && _paper_a_full37_oil_minimum(dev)
            if !haskey(dev,"source_class")
                !haskey(dev,"paper_a_full37_online") && !haskey(dev,"paper_a_annual_cyclic") ||
                    throw(ArgumentError("A Full37 selector requires a block source"))
                synthetic || throw(ArgumentError("Full37 operating roster contains a non-block asset"))
                continue
            end
            cls=dev["source_class"]
            selective=cls=="SYN" && haskey(_PAPER_A_SELECTIVE_SYN,carrier)
            phs=cls=="SYN" && carrier=="phs"
            battery=table!="gen" && carrier in ("battery","bess-gfm")
            gfm=battery && cls=="GFM"
            if !synthetic
                dev["a_conn"]==1 && (cls!="GFM" || gfm) && (cls!="GFL" || dev["mu_fl"]==1) &&
                    (cls!="SYN" || (dev["mu_str"]==1 && dev["fixed_strength_already_in_network"]===false)) ||
                    throw(ArgumentError("Full37 source participation coefficients differ from the case"))
            end
            mode=selective ? "SELECTIVE_SYN" : phs ? "PHS_SYN" :
                gfm ? (source_proxy===nothing ? "GFM_ZERO_STRENGTH" : "GFM_FROZEN_E_PROXY") : nothing
            gfm && source_proxy!==nothing && _paper_a_validate_gfm_proxy_device(dev)
            if (selective && carrier=="hydro") || phs
                table=="storage" && get(dev,"paper_a_storage_unit",nothing) isa AbstractDict ||
                    throw(ArgumentError("Full37 hydro and PHS require native storage physics"))
            elseif selective
                table=="gen" || throw(ArgumentError("Full37 oil, biomass and RoR must be generator blocks"))
            end
            marker=get(dev,"paper_a_full37_online",nothing)
            if mode===nothing
                marker===nothing || throw(ArgumentError("Unexpected Full37 online selector on $(dev["name"])"))
            else
                threshold=selective ? _PAPER_A_SELECTIVE_SYN[carrier] : phs ? 0.2 : 0.0
                marker isa AbstractDict && get(marker,"mode",nothing)==mode &&
                    PaperARegional.number(marker,"strength_minimum_pu")==threshold ||
                    throw(ArgumentError("Invalid Full37 online selector on $(dev["name"])"))
                if selective || phs
                    dev["fixed_strength_already_in_network"]===false ||
                        throw(ArgumentError("A Full37 dispatch-qualified source may not be in the passive stamp"))
                    counts[carrier]+=1
                end
                selective && get(dev,"committable",false) &&
                    throw(ArgumentError("Full37 selective SYN must use non-UC participation"))
            end
            if battery
                cls in ("GFL","GFM") && get(dev,"paper_a_annual_cyclic",nothing)===true ||
                    throw(ArgumentError("Full37 BESS requires a GFL/GFM class and an outer SOC cycle"))
                dev["p_block_max_MW"]==dev["S_block_MVA"]==25 &&
                    (cls!="GFL" || dev["mu_fl"]==1) ||
                    throw(ArgumentError("Full37 BESS requires the named 25 MW/MVA blocks and nameplate exposure"))
                if table=="storage"
                    native=get(dev,"paper_a_storage_unit",nothing)
                    native isa AbstractDict && get(native,"cyclic_state_of_charge",nothing)===true ||
                        throw(ArgumentError("Full37 BESS StorageUnit requires the native cyclic boundary"))
                end
                if !synthetic
                    get(dev,"candidate_added_by_converter",false)===true && dev["n0"]==dev["na0"]==0 &&
                        dev["a_conn"]==1 &&
                        dev["paper_a_bess_cost"]["duration_h"]==v["bess_duration_h"] ||
                        throw(ArgumentError("Full37 BESS must use the frozen new investment and duration role"))
                end
                counts[lowercase(cls)]+=1
            elseif haskey(dev,"paper_a_annual_cyclic")
                throw(ArgumentError("Unexpected explicit Full37 BESS cycle marker"))
            end
            if !synthetic || marker!==nothing || battery
                bus=sn["bus"][string(dev[table=="gen" ? "gen_bus" : "storage_bus"])]["name"]
                roster[(table,id)]=(dev["name"],dev["carrier"],cls,mode,battery,bus,
                    dev["n0"],dev["nmax"],dev["p_block_max_MW"],dev["S_block_MVA"],
                    get(dev,"status",get(dev,"gen_status",1)))
                last(roster[(table,id)])==1 || throw(ArgumentError("Full37 selector asset was removed from operation"))
                if !synthetic && baseline===nothing && !battery
                    push!(sources,join((dev["name"],dev["carrier"],cls,bus),'\t'))
                end
            end
        end
        if !synthetic && baseline===nothing
            expected_gfl=v["battery_mode"]=="GFM_ONLY" ? 0 : 37
            expected_gfm=v["battery_mode"]=="GFL_ONLY" ? 0 : 37
            counts==Dict("hydro"=>27,"ror"=>28,"oil"=>10,"biomass"=>12,"phs"=>20,
                "gfl"=>expected_gfl,"gfm"=>expected_gfm) || throw(ArgumentError("Full37 selector asset roster mismatch"))
            length(sources)==306 && _paper_a_full37_lines_sha(sort!(sources))==_PAPER_A_FULL37_SOURCE_ROLES_SHA ||
                throw(ArgumentError("Full37 original operating identities or source roles differ from the frozen roster"))
            ids=Dict(group=>String[] for group in keys(_PAPER_A_FULL37_ROSTER_SHA))
            for (name,_,cls,mode,battery) in values(roster)
                group=battery ? cls : mode
                group===nothing || push!(ids[group],name)
            end
            for (group,roster_sha) in _PAPER_A_FULL37_ROSTER_SHA
                names=ids[group]
                isempty(names) && continue
                sort!(names)
                expected_sha=revised_dispatch && group=="SELECTIVE_SYN" ?
                    _PAPER_A_FULL37_NON_RESERVOIR_SELECTORS_SHA : roster_sha
                _paper_a_full37_lines_sha(names)==expected_sha ||
                    throw(ArgumentError("Full37 $group asset IDs differ from the frozen roster"))
            end
        end
        baseline===nothing && (baseline=roster)
        baseline==roster || throw(ArgumentError("Full37 selector asset identity changes across snapshots"))
    end
    return nothing
end

function _paper_a_validate_full37_template(pm,template)
    spec=_paper_a_full37(pm.data)
    spec===nothing && return nothing
    get(pm.setting,"add_co2_cost",false)===false ||
        throw(ArgumentError("Full37 carbon cost belongs to the approved generation price"))
    f=template.gscr_formulation
    id=f isa ExactPSDGSCR ? "G0" : f isa GershgorinGSCR ? "G1" :
        f isa FixedScalingGSCR ? "G2" : f isa ExactEdgeSOCGSCR ? "G3" : nothing
    id==spec["variant"]["formulation"] || throw(ArgumentError("Full37 template formulation mismatch"))
    if id=="G2"
        f.r==get(spec,"g2_r",nothing) && f.provenance==get(spec,"g2_r_sha256",nothing) ||
            throw(ArgumentError("Full37 G2 template must use the bound ordered vector and provenance"))
    end
    for nw in nw_ids(pm), (key,formulation) in pm.ext[:uc_gscr_block_formulations][nw]
        table,id=key
        dev=_PM.ref(pm,nw,table,id)
        expected=table!=:gen ? BlockStorageParticipation :
            haskey(dev,"paper_a_carrier_uc") ? BlockThermalCommitment : BlockRenewableParticipation
        formulation isa expected || throw(ArgumentError("Full37 block template changes the operating mode of $key"))
    end
    return nothing
end

function _paper_a_full37_variables!(pm,nw)
    _paper_a_full37(pm.data)===nothing && return nothing
    vars=_PM.var(pm,nw)
    counts=Dict{Tuple{Symbol,Int},JuMP.VariableRef}()
    pump_counts=empty(counts)
    credit_power=empty(counts)
    for key in keys(_PM.ref(pm,nw,:paper_a_coefficients))
        mode=_paper_a_full37_mode(_PM.ref(pm,nw,key...))
        if mode=="SELECTIVE_SYN"
            counts[key]=JuMP.@variable(pm.model,lower_bound=0,integer=true)
            credit_power[key]=JuMP.@variable(pm.model,lower_bound=0)
        elseif mode=="PHS_SYN"
            counts[key]=JuMP.@variable(pm.model,lower_bound=0,integer=true)
            pump_counts[key]=JuMP.@variable(pm.model,lower_bound=0,integer=true)
        end
    end
    vars[:paper_a_strength_blocks]=counts
    vars[:paper_a_pump_blocks]=pump_counts
    vars[:paper_a_credited_power]=credit_power
    return nothing
end

function _paper_a_strength_count(pm,nw,key,active)
    counts=get(_PM.var(pm,nw),:paper_a_strength_blocks,nothing)
    return counts===nothing ? active : get(counts,key,active)
end

function _paper_a_full37_selective_constraints!(pm,nw,key,dispatch,active,pmax,pblock)
    dev=_PM.ref(pm,nw,key...)
    _paper_a_full37_mode(dev)=="SELECTIVE_SYN" || return nothing
    count=_PM.var(pm,nw,:paper_a_strength_blocks,key)
    credited=_PM.var(pm,nw,:paper_a_credited_power,key)
    other=dispatch-credited
    upper=pmax*pblock
    lower=_paper_a_full37_minimum(dev)*pblock
    JuMP.@constraint(pm.model,count<=active)
    JuMP.@constraint(pm.model,credited>=lower*count)
    JuMP.@constraint(pm.model,credited<=upper*count)
    JuMP.@constraint(pm.model,other>=0)
    JuMP.@constraint(pm.model,other<=upper*(active-count))
    return nothing
end
