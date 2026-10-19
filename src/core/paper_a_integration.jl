# Paper-A opt-in bridge. Numerical reference data belongs to ref; JuMP objects
# below belong to the builder and are stored in pm.ext for the AP3 handoff.
function _paper_a_enabled(data::AbstractDict)
    haskey(data,"paper_a_extension") || return false
    marker=data["paper_a_extension"]
    marker isa AbstractDict && get(marker,"name",nothing)=="scientific_physical_data" &&
        get(marker,"version",nothing)=="1.0" && get(marker,"flexplan_ap2_required",nothing)===true ||
        throw(ArgumentError("unsupported/unversioned paper_a_extension"))
    return true
end

function _paper_a_validate_markers(data)
    enabled=_paper_a_enabled(data)
    snapshots=get(data,"multinetwork",false) ? data["nw"] : Dict("1"=>data)
    for sn in values(snapshots)
        _paper_a_enabled(sn)==enabled || throw(ArgumentError("Paper-A root/snapshot extension mismatch"))
        if !enabled && (haskey(sn,"paper_a_network") || haskey(sn,"paper_a_temporal") ||
            any(haskey(dev,"source_class") for table in ("gen","storage","ne_storage") for dev in values(get(sn,table,Dict()))))
            throw(ArgumentError("unversioned Paper-A physical input"))
        end
        if enabled
            schema=get(sn,"block_model_schema",get(data,"block_model_schema",nothing))
            schema isa AbstractDict && get(schema,"name",nothing)=="uc_gscr_block" && get(schema,"version",nothing)=="2.0" || throw(ArgumentError("AP1 requires schema v2 on root and snapshots"))
            for table in ("gen","storage","ne_storage"), dev in values(get(sn,table,Dict()))
                get(dev,"source_class",nothing)=="SC" && throw(ArgumentError("unsupported source case SC: dedicated MVA/Mvar and cost treatment required"))
            end
        end
    end
    return enabled
end

function _paper_a_validate_shared_assets(ref)
    snapshots=sort(collect(values(ref[:it][_PM.pm_it_sym][:nw]));by=x->string(get(x,:name,"")))
    isempty(snapshots) && return
    first_coeff=get(first(snapshots),:paper_a_coefficients,nothing)
    first_coeff===nothing && return
    baseline=Dict((table,id)=>dev for (table,id,dev) in _uc_gscr_block_devices(first(snapshots)))
    fields=("source_class","S_base_MVA","S_block_MVA","p_block_max_MW","b_block","x_src","native_parameter_base",
        "mu_str","mu_fl","region_id","n0","nmax","na0","cost_inv_per_mw")
    for sn in snapshots
        Set(keys(sn[:paper_a_coefficients]))==Set(keys(baseline)) || throw(ArgumentError("AP1 shared asset set changes across snapshots"))
        for (table,id,dev) in _uc_gscr_block_devices(sn),field in fields
            isequal(get(dev,field,nothing),get(baseline[(table,id)],field,nothing)) || throw(ArgumentError("shared AP1 asset field $field changes across snapshots"))
        end
    end
end

"""Normalize a raw AP1 physical single/multinetwork once. Standard PowerModels
power and polynomial costs, FlexPlan block P/Q/E fields, and candidate storage
are converted on the common base. Already-pu input must carry block units.
No temporal or investment cost weighting is performed here."""
function prepare_paper_a_data!(data::Dict{String,Any})
    _paper_a_validate_markers(data) || throw(ArgumentError("AP1 extension required"))
    snapshots=get(data,"multinetwork",false) ? data["nw"] : Dict("1"=>data)
    base=PaperARegional.number(data,"baseMVA";positive=true)
    if get(data,"per_unit",false)
        all(get(sn,"paper_a_block_units",nothing)=="pu_system" for sn in values(snapshots)) ||
            throw(ArgumentError("already-pu AP1 input requires paper_a_block_units=pu_system"))
        return data
    end
    for sn in values(snapshots)
        get(sn,"baseMVA",base)==base || throw(ArgumentError("snapshot baseMVA mismatch"))
        sn["baseMVA"]=base
        if get(data["paper_a_extension"],"dataset_kind",nothing)=="parametric_study" && haskey(sn,"link")
            # Producer non-DC links are explicitly ignored source metadata.
            # IM treats dictionaries of dictionaries as numbered component
            # tables; retain these descriptions as a list instead.
            sn["paper_a_ignored_link_metadata"]=[Dict("source_name"=>name,"metadata"=>dev) for (name,dev) in pop!(sn,"link")]
        end
        for table in ("gen","bus","branch","load","storage","ne_storage","shunt","switch","dcline")
            get!(sn,table,Dict{String,Any}())
            for (id,component) in sn[table]
                get!(component,"index",parse(Int,id))
            end
        end
        for load in values(sn["load"]);get!(load,"status",1);end
        for br in values(sn["branch"])
            # AP1 only supports unit-tap line primitives; physical consistency
            # and unsupported models are checked again by the Y builder.
            for (field,value) in (("tap",1.0),("shift",0.0),("g_fr",0.0),("g_to",0.0),("transformer",false))
                get!(br,field,value)
            end
        end
        for table in ("storage","ne_storage"),dev in values(sn[table])
            # The AP2 storage abstraction uses exported efficiencies and SOC;
            # extra stationary/electrical loss models are opt-in explicit data.
            for field in ("r","x","p_loss","q_loss","stationary_energy_inflow","stationary_energy_outflow","self_discharge_rate")
                get!(dev,field,0.0)
            end
            get!(dev,"thermal_rating",dev["charge_rating"]+dev["discharge_rating"])
            get!(dev,"qmin",dev["q_block_min"]*dev["nmax"])
            get!(dev,"qmax",dev["q_block_max"]*dev["nmax"])
        end
        get(sn,"per_unit",false)===false || throw(ArgumentError("mixed raw/pu snapshots"))
        _PM.make_per_unit!(sn)
        _add_gen_data!(sn)
        _add_storage_data!(sn)
        sn["paper_a_block_units"]="pu_system"
    end
    data["per_unit"]=true
    return data
end

function _paper_a_temporal(data,nw)
    alltemporal=get(data,"paper_a_temporal",nothing)
    t = alltemporal isa AbstractVector ? alltemporal[nw] :
        alltemporal isa AbstractDict && haskey(alltemporal,"delta_t_h") ? alltemporal :
        alltemporal isa AbstractDict ? alltemporal[string(nw)] : nothing
    t isa AbstractDict || throw(ArgumentError("missing AP1 temporal contract"))
    dt=PaperARegional.number(t,"delta_t_h";positive=true)
    reps=PaperARegional.number(t,"representative_repetitions";nonnegative=true)
    prob=PaperARegional.number(t,"scenario_probability";nonnegative=true)
    events=PaperARegional.number(t,"event_repetitions";nonnegative=true)
    w=PaperARegional.dispatch_event_weights(dt,reps,prob,events)
    isapprox(PaperARegional.number(t,"dispatch_weight"),w.dispatch;atol=1e-9) &&
        isapprox(PaperARegional.number(t,"event_weight"),w.event;atol=1e-9) || throw(ArgumentError("inconsistent dispatch/event weights"))
    return (delta_t_h=dt,dispatch=w.dispatch,event=w.event,probability=prob)
end

function _paper_a_add_reference!(nw_ref,data,nw;validation_scope=:strict)
    sn=get(data,"multinetwork",false) ? data["nw"][string(nw)] : data
    base=PaperARegional.number(data,"baseMVA";positive=true)
    get(sn,"baseMVA",base)==base || throw(ArgumentError("AP1 snapshot base mismatch"))
    get(data,"per_unit",false) && get(sn,"paper_a_block_units",nothing)=="pu_system" || throw(ArgumentError("call prepare_paper_a_data! before model construction"))
    net=get(data,"paper_a_network",get(sn,"paper_a_network",nothing))
    net isa AbstractDict || throw(ArgumentError("missing physical paper_a_network"))
    synthetic=validation_scope==:synthetic_regression
    parametric=validation_scope==:parametric_study
    validation_scope in (:strict,:synthetic_regression,:parametric_study) || throw(ArgumentError("unsupported validation scope"))
    if parametric
        _paper_a_validate_registered!(data)
    elseif haskey(data,"paper_a_parameter_qualification") || get(data["paper_a_extension"],"dataset_kind",nothing)=="parametric_study"
        throw(ArgumentError("parametric data requires explicit parametric_study scope"))
    end
    if synthetic
        get(data["paper_a_extension"],"dataset_kind",nothing)=="synthetic_regression_only" || throw(ArgumentError("synthetic regression scope cannot be used on real/unclassified input"))
        all(i=="grounding_reference_unverified" for i in net["passive_domain_issues"]) || throw(ArgumentError("synthetic regression still requires verified shunt/source inventories"))
    end
    regional=PaperARegional.network_reference(net,nw_ref[:bus],base;diagnostic_only=synthetic || parametric)
    temporal=_paper_a_temporal(data,nw)
    if haskey(data,"dim")
        isapprox(dim_prop(data,nw,:scenario,"probability"),temporal.probability;atol=1e-9) || throw(ArgumentError("AP1 scenario dimension/temporal probability mismatch"))
        dim_length(data,:year)==1 || throw(ArgumentError("AP1 bounded builder supports one represented planning year"))
    end
    isapprox(PaperARegional.number(sn,"time_elapsed";positive=true),temporal.delta_t_h;atol=1e-9) || throw(ArgumentError("physical duration mismatch"))
    get(sn,"operation_weight",nothing)==1 || throw(ArgumentError("AP1 operation_weight must be neutral; use explicit temporal weights"))
    state=get(sn,"paper_a_cost_state","raw_hourly")
    state in ("raw_hourly","weighted") || throw(ArgumentError("unknown AP1 cost state"))
    if state=="weighted"
        get(sn,"paper_a_applied_weights",nothing)==[temporal.dispatch,temporal.event] || throw(ArgumentError("scaled AP1 cost weights mismatch"))
    end
    get(sn,"paper_a_capex_scaled",false)===true || throw(ArgumentError("AP1 CAPEX must pass scale_data! or scale_paper_a_costs! once"))
    coeff=Dict{Tuple{Symbol,Any},Any}()
    fixed_assets=String[]
    for (table,id,dev) in _uc_gscr_block_devices(nw_ref)
        PaperARegional.validate_source(dev;synthetic_regression=synthetic)
        if dev["nmax"]>dev["n0"]
            PaperARegional.number(dev,"cost_inv_per_mw";positive=true)
            get(dev,"investment_data_status",nothing)!="blocked_missing_cost" || throw(ArgumentError("blocked/unpriced AP1 asset cannot expand"))
        end
        for f in ("n0","nmax","na0")
            x=PaperARegional.number(dev,f;nonnegative=true)
            isinteger(x) || throw(ArgumentError("physical AP1 $f must be an integer count even for LP relaxation"))
        end
        dev["S_base_MVA"]==base || throw(ArgumentError("source system base mismatch"))
        P=dev["p_block_max_MW"]
        isapprox(dev["p_block_max"]*base,P;atol=1e-8,rtol=1e-9) || throw(ArgumentError("block MW/pu mismatch"))
        bus=nw_ref[:bus][_uc_gscr_device_bus(table,dev)]["name"]
        bus in regional.retained || throw(ArgumentError("nonpassive source on eliminated AC node"))
        region=dev["region_id"]
        region==regional.bus_to_region[bus] || throw(ArgumentError("device regional mapping mismatch"))
        i=findfirst(==(region),regional.regions)
        fixed=dev["fixed_strength_already_in_network"]
        if fixed
            asset=string(dev["name"]);push!(fixed_assets,asset)
            bindings=get(net,"fixed_source_shunt_by_asset",Dict())
            binding=get(bindings,asset,nothing)
            binding isa AbstractDict && get(binding,"bus",nothing)==bus || throw(ArgumentError("fixed source lacks explicit Y shunt binding"))
            sh=get(net["fixed_shunts"],bus,nothing)
            sh isa AbstractDict && get(binding,"bs_pu",nothing)==sh["bs_pu"] && sh["bs_pu"]<0 || throw(ArgumentError("fixed source binding mismatch"))
            count(v->get(v,"bus",nothing)==bus,values(bindings))==1 && regional.b_fix[i]==0 || throw(ArgumentError("fixed source counted more than once"))
            dev["a_conn"]==1 && dev["na0"]==dev["n0"]==dev["nmax"] || throw(ArgumentError("fixed-in-Y source must remain permanently connected without expansion"))
        end
        cls=dev["source_class"]
        strength=cls in ("SYN","GFM") && !fixed ? dev["mu_str"]*dev["b_block"] : 0.0
        exposure=cls=="GFL" ? dev["mu_fl"]*P/base : 0.0
        coeff[(table,id)]=(region=i,strength=strength,exposure=exposure)
    end
    length(unique(fixed_assets))==length(fixed_assets) && Set(fixed_assets)==Set(String.(net["fixed_sources_in_network"])) || throw(ArgumentError("unaccounted/duplicate fixed network source"))
    # Elimination must be passive, including any source without block fields.
    for table in (:gen,:storage,:ne_storage), dev in values(get(nw_ref,table,Dict()))
        nw_ref[:bus][_uc_gscr_device_bus(table,dev)]["name"] in regional.eliminated && throw(ArgumentError("source cannot be eliminated"))
    end
    nw_ref[:paper_a_regional]=regional
    nw_ref[:paper_a_coefficients]=coeff
    nw_ref[:paper_a_temporal]=temporal
    nw_ref[:paper_a_cost_state]=state
    nw_ref[:paper_a_validation_scope]=validation_scope
    return nothing
end

"""Apply explicit dispatch/event weights and existing CAPEX convention once.
Accepts raw or prepared AP1 single/multinetwork input; changes only costs.
Already scaled inputs carry exact applied factors and are rejected on repeat."""
function scale_paper_a_costs!(data::Dict{String,Any}; cost_scale_factor::Real=1.0)
    _paper_a_validate_markers(data) || throw(ArgumentError("AP1 extension required"))
    isfinite(cost_scale_factor) && cost_scale_factor>0 || throw(ArgumentError("invalid currency scale"))
    snapshots=get(data,"multinetwork",false) ? data["nw"] : Dict("1"=>data)
    for sn in values(snapshots)
        get(sn,"paper_a_cost_state","raw_hourly")=="raw_hourly" && !get(sn,"paper_a_capex_scaled",false) || throw(ArgumentError("AP1 costs already scaled"))
    end
    for (id,sn) in snapshots
        t=_paper_a_temporal(data,parse(Int,id))
        for key in ("uc_gscr_block_cost_convention","uc_gscr_block_cost_assumptions")
            if !haskey(sn,key) && haskey(data,key);sn[key]=deepcopy(data[key]);end
        end
        parametric=get(data["paper_a_extension"],"dataset_kind",nothing)=="parametric_study"
        parametric && _paper_a_validate_registered!(data)
        fraction=parametric ? data["investment_period_fraction"] : 1.
        _scale_uc_gscr_block_investment_cost_data!(sn,fraction,cost_scale_factor,:from_data)
        for gen in values(sn["gen"])
            get(gen,"model",nothing)==2 && length(gen["cost"])==2 && gen["cost"][end]==0 || throw(ArgumentError("AP1 supports linear hourly generation cost with zero constant only"))
            _PM._apply_func!(gen,"cost",x->x*t.dispatch*cost_scale_factor)
        end
        for table in ("gen","storage","ne_storage"),dev in values(get(sn,table,Dict()))
            _scale_uc_gscr_block_operational_cost_fields!(dev,x->x*t.event*cost_scale_factor)
            if table!="gen" && haskey(dev,"marginal_cost")
                price=PaperARegional.number(dev,"marginal_cost";nonnegative=true)
                dev["marginal_cost"]=price*t.dispatch*cost_scale_factor
            end
        end
        sn["paper_a_cost_state"]="weighted"
        sn["paper_a_applied_weights"]=[t.dispatch,t.event]
        sn["paper_a_capex_scaled"]=true
        sn["paper_a_investment_fraction_applied"]=fraction
        sn["paper_a_currency_factor"]=cost_scale_factor
    end
    return data
end

function _paper_a_storage_operation_cost(pm,nw)
    haskey(_PM.ref(pm,nw),:paper_a_regional) || return JuMP.AffExpr(0.0)
    template=pm.ext[:uc_gscr_block_template]
    cost=JuMP.AffExpr(0.0)
    for table in (:storage,:ne_storage), (id,dev) in get(_PM.ref(pm,nw),table,Dict())
        haskey(dev,"marginal_cost") || continue
        price=PaperARegional.number(dev,"marginal_cost";nonnegative=true)
        price==0 && continue
        template.storage_cost_policy==:discharge || throw(ArgumentError("nonzero AP1 storage cost requires explicit storage_cost_policy=:discharge in UCGSCRBlockTemplate"))
        weight=_PM.ref(pm,nw,:paper_a_cost_state)=="raw_hourly" ? _PM.ref(pm,nw,:paper_a_temporal).dispatch : 1.0
        # sd is AC-side discharged MW on system pu base; charge is not billed.
        sd=_PM.var(pm,nw,table==:storage ? :sd : :sd_ne,id)
        JuMP.add_to_expression!(cost,price*dev["S_base_MVA"]*weight,sd)
    end
    return cost
end

function _paper_a_online_expressions!(pm,nw)
    haskey(_PM.ref(pm,nw),:paper_a_regional) || return nothing
    allsnap=get!(pm.ext,:paper_a_online,Dict{Int,Any}())
    haskey(allsnap,nw) && return allsnap[nw]
    ref=_PM.ref(pm,nw,:paper_a_regional); na=_PM.var(pm,nw,:na_block)
    b=[JuMP.AffExpr(x) for x in ref.b_fix]
    p=[JuMP.AffExpr(0.0) for _ in ref.regions]
    for (key,c) in _PM.ref(pm,nw,:paper_a_coefficients)
        JuMP.add_to_expression!(b[c.region],c.strength,na[key])
        JuMP.add_to_expression!(p[c.region],c.exposure,na[key])
    end
    B=[JuMP.AffExpr(ref.B0[i,j]) for i in eachindex(b),j in eachindex(b)]
    for i in eachindex(b);JuMP.add_to_expression!(B[i,i],b[i]);end
    alpha=get(_PM.ref(pm,nw),:g_min,nothing)
    M=alpha isa Real ? [B[i,j]-(i==j ? alpha*p[i] : 0.0) for i in eachindex(b),j in eachindex(b)] : nothing
    allsnap[nw]=(regions=ref.regions,b_src=b,p_fl=p,B=B,S_diag=p,M=M)
    return allsnap[nw]
end

function _paper_a_g1!(pm,nw)
    r=_PM.ref(pm,nw,:paper_a_regional);x=_paper_a_online_expressions!(pm,nw)
    alpha=_uc_gscr_g_min(pm,nw)
    PaperARegional.symmetric_z(r.B0)
    constraints=_PM.con(pm,nw)[:gscr_gershgorin_sufficient]=Dict{Any,JuMP.ConstraintRef}()
    for (i,region) in enumerate(r.regions)
        sigma=r.B0[i,i]-sum(abs(r.B0[i,j]) for j in eachindex(r.regions) if i!=j;init=0.0)
        constraints[region]=JuMP.@constraint(pm.model,sigma+x.b_src[i]>=alpha*x.p_fl[i])
    end
    return constraints
end

function _paper_a_candidate_storage_balance(pm,nw,i)
    # Same lossless active-power balance as PowerModels' AbstractActivePowerModel,
    # extended only by block-native candidate storage. DC lines retain PM signs.
    r=_PM.ref(pm,nw)
    p=_PM.var(pm,nw,:p);pdc=_PM.var(pm,nw,:p_dc);pg=_PM.var(pm,nw,:pg)
    ps=_PM.var(pm,nw,:ps);psne=_PM.var(pm,nw,:ps_ne)
    return JuMP.@constraint(pm.model,
        sum(p[a] for a in r[:bus_arcs][i];init=0.0)+sum(pdc[a] for a in r[:bus_arcs_dc][i];init=0.0) ==
        sum(pg[g] for g in r[:bus_gens][i];init=0.0)-sum(ps[s] for s in r[:bus_storage][i];init=0.0)-
        sum(psne[s] for s in r[:bus_storage_ne][i];init=0.0)-
        sum(r[:load][l]["pd"] for l in r[:bus_loads][i];init=0.0)-
        sum(r[:shunt][s]["gs"] for s in r[:bus_shunts][i];init=0.0))
end
