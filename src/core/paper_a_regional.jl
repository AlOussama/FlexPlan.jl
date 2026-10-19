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
    length(unique(vcat(retained,eliminated))) == n || throw(ArgumentError("retained and eliminated must partition physical AC nodes"))
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
    if cls in ("SYN","GFM") && !get(d,"fixed_strength_already_in_network",false)
        get(d,"source_equivalent_valid",false) === true ||
            throw(ArgumentError("unverified voltage-source equivalent"))
        get(d,"source_equivalent_type",nothing) == "voltage_behind_reactance" ||
            throw(ArgumentError("unsupported source equivalent"))
        for f in ("S_block_MVA","S_base_MVA","x_src","mu_str")
            get(d,f,nothing) isa Real || throw(ArgumentError("missing physical field "*f))
        end
        get(d,"mu_str",0) >= 0 || throw(ArgumentError("negative mu_str"))
    end
    if get(d,"fixed_strength_already_in_network",false)
        get(d,"b_block",NaN) == 0 || throw(ArgumentError("fixed source double counting"))
        get(d,"fixed_source_permanently_connected",false) === true ||
            throw(ArgumentError("fixed source must be permanently connected"))
    end
    cls == "SC" && throw(ArgumentError("SC requires dedicated MVA/Mvar and cost treatment"))
    if cls == "GFL"
        for f in ("P_block_MW","S_base_MVA","mu_fl")
            get(d,f,nothing) isa Real || throw(ArgumentError("missing GFL field "*f))
        end
        get(d,"mu_fl",0) >= 0 || throw(ArgumentError("negative mu_fl"))
    end
    return true
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
