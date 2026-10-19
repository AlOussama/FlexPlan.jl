# Paper A AP2 physical regional model: standalone pure-Julia input layer.
# This file deliberately does not change PowerModels operational DC flow.
module PaperARegional
using LinearAlgebra
export reduced_strength, source_b_block, regional_strength, online_exposure,
       dispatch_event_weights, validate_source, assert_connection

"""Compute the passive fixed regional matrix using explicit retained/eliminated
node positions. Endogenous sources must NOT be present in L."""
function reduced_strength(L::AbstractMatrix{<:Real}, retained::AbstractVector{<:Integer},
                          eliminated::AbstractVector{<:Integer}; tol=1e-9)
    n = size(L,1)
    size(L) == (n,n) || throw(ArgumentError("L must be square"))
    all(isfinite,L) || throw(ArgumentError("nonfinite passive network"))
    norm(L-transpose(L),Inf) <= tol || throw(ArgumentError("asymmetric positive-sequence L"))
    all(i->1<=i<=n, vcat(retained,eliminated)) || throw(ArgumentError("invalid AC node index"))
    length(vcat(retained,eliminated)) == n && length(unique(vcat(retained,eliminated))) == n || throw(ArgumentError("retained and eliminated must partition physical AC nodes"))
    isempty(retained) && throw(ArgumentError("at least one retained regional node required"))
    R = Matrix{Float64}(L[retained,retained])
    isempty(eliminated) && return R
    E = Matrix{Float64}(L[eliminated,eliminated])
    minimum(svdvals(E)) > tol || throw(ArgumentError("singular passive eliminated-node block"))
    return R - L[retained,eliminated] * (E \ Matrix(L[eliminated,retained]))
end

"""Compute a voltage-source-behind-reactance contribution on the system base.
x_src must be per-unit on the explicit S_block_MVA native rating."""
function source_b_block(S_block_MVA::Real,S_base_MVA::Real,x_src::Real)
    all(z->isfinite(z) && z>0, (S_block_MVA,S_base_MVA,x_src)) ||
        throw(ArgumentError("positive finite ratings, common base and source reactance required"))
    return S_block_MVA/(S_base_MVA*x_src)
end

"""Validate the AP1 physical class, converter control mode and provenance.
SC is purposefully rejected as an unpriced active-power planning option here."""
function validate_source(d::AbstractDict)
    cls = get(d,"source_class",nothing)
    cls in ("GFL","GFM","SYN","SC") || throw(ArgumentError("unknown physical source_class"))
    mode = get(d,"grid_control_mode",nothing)
    expected = cls == "GFL" ? "gfl" : cls == "GFM" ? "gfm" : "not_applicable"
    mode == expected || throw(ArgumentError("source_class/control_mode mismatch"))
    cls == "SC" && throw(ArgumentError("unsupported source case SC: dedicated MVA/Mvar and cost treatment required"))
    for f in ("source_class_evidence", "electrical_interface_evidence", "a_conn_provenance")
        evidence(get(d,f,nothing)) || throw(ArgumentError("missing/unverified "*f))
    end
    for f in ("S_base_MVA", "p_block_max_MW")
        number(d,f;positive=true)
    end
    for f in ("a_conn", "a_res")
        0 <= number(d,f) <= 1 || throw(ArgumentError("invalid "*f))
    end
    number(d,"b_block";nonnegative=true)
    fixed = get(d,"fixed_strength_already_in_network",nothing)
    fixed isa Bool || throw(ArgumentError("missing fixed source accounting flag"))
    if cls in ("SYN","GFM") && !fixed
        get(d,"source_equivalent_valid",false) === true ||
            throw(ArgumentError("unverified voltage-source equivalent"))
        get(d,"source_equivalent_type",nothing) == "voltage_behind_reactance" ||
            throw(ArgumentError("unsupported source equivalent"))
        s = number(d,"S_block_MVA";positive=true)
        x = number(d,"x_src";positive=true)
        native = get(d,"native_parameter_base",nothing)
        native in ("block_MVA","source_MVA","device_MVA") || throw(ArgumentError("unsupported native_parameter_base"))
        sn = native == "block_MVA" ? get(d,"native_source_MVA",s) : get(d,"native_source_MVA",nothing)
        sn isa Real && isfinite(sn) && sn > 0 || throw(ArgumentError("numerical native_source_MVA required"))
        native != "block_MVA" || isapprox(sn,s;rtol=1e-9) || throw(ArgumentError("block native MVA mismatch"))
        for f in ("source_equivalent_time_scale", "source_parameter_provenance")
            evidence(get(d,f,nothing)) || throw(ArgumentError("missing/unverified "*f))
        end
        b = source_b_block(s,d["S_base_MVA"],x*s/sn)
        if get(d,"x_src_block_base",nothing)!==nothing
            isapprox(number(d,"x_src_block_base";positive=true),x*s/sn;atol=1e-9,rtol=1e-9) || throw(ArgumentError("producer x_src_block_base mismatch"))
        end
        isapprox(b,d["b_block"];atol=1e-9,rtol=1e-9) || throw(ArgumentError("b_block native-base normalization mismatch"))
        number(d,"mu_str";nonnegative=true)
        if get(d,"source_b_block_pu_reference",nothing)!==nothing
            isapprox(number(d,"source_b_block_pu_reference"),b;atol=1e-9,rtol=1e-9) || throw(ArgumentError("producer source normalization reference mismatch"))
        end
    end
    if get(d,"fixed_strength_already_in_network",false)
        get(d,"b_block",NaN) == 0 || throw(ArgumentError("fixed source double counting"))
        get(d,"fixed_source_permanently_connected",false) === true ||
            throw(ArgumentError("fixed source must be permanently connected"))
    end
    if cls == "GFL"
        !fixed || throw(ArgumentError("GFL cannot be a fixed voltage source in Y"))
        number(d,"mu_fl";nonnegative=true)
        d["b_block"] == 0 || throw(ArgumentError("GFL cannot add source strength"))
    end
    return true
end

evidence(x) = x isa AbstractString && !isempty(strip(x)) && !(lowercase(strip(x)) in ("unverified","missing","none","n/a","na","unknown","carrier_assumption_unverified")) && !occursin("unverified",lowercase(x))

function number(d, f; positive=false, nonnegative=false)
    x = get(d,f,nothing)
    x isa Real && !(x isa Bool) && isfinite(x) || throw(ArgumentError("missing/nonfinite physical field "*f))
    (!positive || x>0) && (!nonnegative || x>=0) || throw(ArgumentError("invalid physical field "*f))
    return Float64(x)
end

function symmetric_z(B;tol=1e-9)
    all(isfinite,B) && norm(B-transpose(B),Inf)<=tol || throw(ArgumentError("asymmetric/nonfinite strength matrix"))
    all(B[i,j]<=tol for i in axes(B,1), j in axes(B,2) if i!=j) || throw(ArgumentError("non-Z strength offdiagonal"))
    return true
end

"""Assemble passive positive-sequence AC admittance from physical primitives.
Producer matrices are diagnostics only. Unit-tap lines are the bounded supported
primitive; native transformer models need a separate validated conversion."""
function network_reference(net::AbstractDict, buses::AbstractDict, base::Real;tol=1e-9, diagnostic_only=false)
    isfinite(base) && base>0 || throw(ArgumentError("invalid baseMVA"))
    issues = get(net,"passive_domain_issues",nothing)
    issues isa AbstractVector || throw(ArgumentError("missing passive-domain inventory status"))
    soft_issues=("fixed_shunt_inventory_unverified","baseline_source_accounting_unverified","grounding_reference_unverified")
    isempty(issues) || (diagnostic_only && all(i in soft_issues for i in issues)) || throw(ArgumentError("unverified passive domain: $(issues)"))
    names = String.(net["physical_ac_bus_order"])
    physical = Dict(string(b["name"]) => b for b in values(buses))
    length(physical)==length(buses)==length(names)==length(unique(names)) && Set(names)==Set(keys(physical)) || throw(ArgumentError("ambiguous physical AC bus mapping"))
    idx=Dict(b=>i for (i,b) in enumerate(names))
    N=length(names); Y=zeros(ComplexF64,N,N)
    adjacency=Dict(b=>String[] for b in names)
    seen=Set{String}()
    for br in net["branch_primitives"]
        br["status"] in (0,1) || throw(ArgumentError("invalid branch status"))
        br["status"]==0 && continue
        id=string(br["name"])
        id in seen && throw(ArgumentError("duplicate passive branch $id")); push!(seen,id)
        get(br,"source_component",nothing) == "lines" || throw(ArgumentError("unsupported transformer/DC physical primitive $id"))
        get(br,"unsupported_physical_model",false)===false && get(br,"tap_ratio",1.0)==1.0 && get(br,"phase_shift",0.0)==0.0 || throw(ArgumentError("unsupported asymmetric tap/phase primitive $id"))
        a,b=string(br["bus0"]),string(br["bus1"])
        haskey(idx,a) && haskey(idx,b) && a!=b || throw(ArgumentError("unknown/invalid AC branch endpoints"))
        v=number(physical[a],"base_kv";positive=true)
        isapprox(v,number(physical[b],"base_kv";positive=true);rtol=tol) || throw(ArgumentError("unequal-voltage line"))
        z=v^2/base
        isapprox(z,number(br,"z_base";positive=true);rtol=tol) && isapprox(v,number(br,"v_base_kv";positive=true);rtol=tol) || throw(ArgumentError("primitive system base mismatch"))
        r=number(br,"r_phys";nonnegative=true)/z
        x=number(br,"x_phys";positive=true)/z
        bc=number(br,"b_siemens")*z
        all(isapprox(u,w;atol=tol,rtol=tol) for (u,w) in ((r,number(br,"r_pu")),(x,number(br,"x_pu")),(bc,number(br,"b_pu")))) || throw(ArgumentError("physical/pu branch mismatch"))
        i,j=idx[a],idx[b]; y=inv(complex(r,x))
        Y[i,i]+=y+im*bc/2; Y[j,j]+=y+im*bc/2
        Y[i,j]-=y; Y[j,i]-=y
        push!(adjacency[a],b); push!(adjacency[b],a)
    end
    for (bus,sh) in net["fixed_shunts"]
        haskey(idx,bus) || throw(ArgumentError("unknown fixed shunt AC bus"))
        Y[idx[bus],idx[bus]]+=complex(number(sh,"gs_pu";nonnegative=true),number(sh,"bs_pu"))
    end
    islands=Vector{Vector{String}}(); visited=Set{String}()
    for bus in names
        bus in visited && continue
        stack=[bus]; component=String[]
        while !isempty(stack)
            b=pop!(stack); b in visited && continue
            push!(visited,b);push!(component,b);append!(stack,adjacency[b])
        end
        push!(islands,sort(component))
    end
    Set(Tuple(sort(String.(i))) for i in net["network_islands"]) == Set(Tuple(i) for i in islands) || throw(ArgumentError("AC island metadata mismatch"))
    refs=Set(string(b["name"]) for b in values(buses) if b["bus_type"]==3)
    refs==Set(String.(net["reference_buses"])) || throw(ArgumentError("reference bus metadata mismatch"))
    all(!isempty(intersect(refs,Set(i))) for i in islands) || throw(ArgumentError("AC island without operational reference"))
    # Empty producer issues confirms its grounding inventory; no slack admittance
    # is added here. A floating passive island is allowed, but Lee must be valid.
    L=-imag.(Y); symmetric_z(L;tol)
    r=String.(net["retained_physical_buses"]);e=String.(net["eliminated_physical_buses"])
    all(haskey(idx,b) for b in vcat(r,e)) || throw(ArgumentError("unknown reduction bus"))
    rr=[idx[b] for b in r];ee=[idx[b] for b in e]
    B0=reduced_strength(L,rr,ee;tol); symmetric_z(B0;tol)
    mapping=net["bus_to_region"]
    Set(keys(mapping))==Set(names) || throw(ArgumentError("incomplete AC bus to region map"))
    regions=String[mapping[b] for b in r]
    length(unique(regions))==length(regions) && all(v isa AbstractString && !isempty(v) for v in values(mapping)) || throw(ArgumentError("invalid retained regional mapping"))
    fixmap=get(net,"fixed_strength_by_region_pu",Dict())
    all(k in regions for k in keys(fixmap)) || throw(ArgumentError("unknown fixed strength region"))
    if !isempty(fixmap)
        evidence(get(net,"fixed_strength_by_region_provenance",nothing)) && get(net,"fixed_strength_permanently_connected",false)===true || throw(ArgumentError("unverified permanent fixed regional strength"))
    end
    bfix=[haskey(fixmap,r) ? number(fixmap,r;nonnegative=true) : 0.0 for r in regions]
    schur_residual=isempty(ee) ? 0.0 : norm(L[ee,ee]*(L[ee,ee]\L[ee,rr])-L[ee,rr],Inf)
    supplied=get(net,"B0_reference_pu",nothing)
    difference = if supplied===nothing
        nothing
    else
        B=reduce(vcat,permutedims.(supplied))
        size(B)==size(B0) && all(isfinite,B) || throw(ArgumentError("invalid B0 reference dimensions"))
        norm(B0-B,Inf)
    end
    return (ac_order=names,retained=r,eliminated=e,regions=regions,bus_to_region=mapping,
            Y=Y,L=L,B0=B0,b_fix=bfix,islands=islands,schur_residual=schur_residual,
            B0_reference_residual=difference,theorem_domain_valid=isempty(issues))
end

"""Check physical technical connection separately from renewable availability."""
function assert_connection(n_on::Real,n_inst::Real,a_conn::Real,a_res::Real;tol=1e-9)
    0 <= a_conn <= 1 && 0 <= a_res <= 1 || throw(ArgumentError("invalid availability"))
    n_inst>=0 && n_on>=-tol && n_on<=a_conn*n_inst+tol ||
        throw(ArgumentError("online blocks exceed connected installed blocks"))
    return true
end

"""Build fixed-plus-online source matrix from pre-reduced passive B0.
src is a collection of named tuples with (region, mu_str, b_block, n_on).
Region indices refer to the retained regional bus order."""
function regional_strength(B0::AbstractMatrix{<:Real}, b_fix::AbstractVector{<:Real}, src)
    n=size(B0,1)
    size(B0)==(n,n) && length(b_fix)==n || throw(ArgumentError("regional matrix dimension mismatch"))
    B=Matrix{Float64}(B0)
    for i in 1:n
        b_fix[i]>=0 || throw(ArgumentError("negative fixed strength"))
        B[i,i]+=b_fix[i]
    end
    for s in src
        1<=s.region<=n || throw(ArgumentError("source outside region"))
        all(z->isfinite(z)&&z>=0,(s.mu_str,s.b_block,s.n_on)) ||
            throw(ArgumentError("invalid source contribution"))
        B[s.region,s.region]+=s.mu_str*s.b_block*s.n_on
    end
    return B
end

"""Online GFL nameplate exposure on common system base, not dispatched MW."""
function online_exposure(n::Integer, src)
    p=zeros(Float64,n)
    for s in src
        1<=s.region<=n || throw(ArgumentError("GFL outside region"))
        all(z->isfinite(z)&&z>=0,(s.mu_fl,s.P_block_MW,s.S_base_MVA,s.n_on)) &&
          s.S_base_MVA>0 || throw(ArgumentError("invalid GFL normalization"))
        p[s.region]+=s.mu_fl*(s.P_block_MW/s.S_base_MVA)*s.n_on
    end
    return p
end

"""Distinct representative dispatch-energy and UC-event objective weights."""
function dispatch_event_weights(delta_t_h::Real,repetitions::Real,
                                scenario_probability::Real,event_repetitions::Real)
    all(z->isfinite(z)&&z>=0,(delta_t_h,repetitions,scenario_probability,event_repetitions)) &&
      delta_t_h>0 || throw(ArgumentError("invalid temporal metadata"))
    scenario_probability<=1 || throw(ArgumentError("invalid scenario probability"))
    return (dispatch=delta_t_h*repetitions*scenario_probability,
            event=event_repetitions*scenario_probability)
end
end
