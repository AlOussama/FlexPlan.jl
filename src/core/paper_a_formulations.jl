"""Paper-A formulations use only the existing AP2 affine B/S/M interface.
G0/G3 are conic; integer support is a property of the selected optimizer.
"""
abstract type AbstractPaperAFormulation <: AbstractGSCRFormulation end
struct ExactPSDGSCR <: AbstractPaperAFormulation end
struct ExactEdgeSOCGSCR <: AbstractPaperAFormulation end

struct FixedScalingGSCR <: AbstractPaperAFormulation
    r::Vector{Float64}
    provenance::String
    function FixedScalingGSCR(r;provenance)
        all(x->isfinite(x)&&x>0,r) && !isempty(provenance) || throw(ArgumentError("G2 requires positive offline r and provenance"))
        new(Float64.(r),String(provenance))
    end
end
struct InverseBoundGSCR <: AbstractPaperAFormulation
    Bmin::Matrix{Float64}
    provenance::String
    function InverseBoundGSCR(Bmin;provenance)
        B=Matrix{Float64}(Bmin); PaperARegional.symmetric_z(B)
        isposdef(Symmetric(B)) && minimum(B\Matrix{Float64}(I,size(B)...))>=-1e-10 && !isempty(provenance) || throw(ArgumentError("M1 needs a nonsingular M-matrix and provenance"))
        new(B,String(provenance))
    end
end
struct InteractionGSCR <: AbstractPaperAFormulation
    W::Matrix{Float64}
    provenance::String
    function InteractionGSCR(W;provenance)
        W=Matrix{Float64}(W)
        size(W,1)==size(W,2) && all(isfinite,W) && minimum(W)>=0 && all(diag(W).==1) && !isempty(provenance) || throw(ArgumentError("M2 requires nonnegative unit-diagonal fixed W and provenance"))
        new(W,String(provenance))
    end
end

function _validate_paper_a_formulation(pm,f)
    for nw in nw_ids(pm)
        haskey(_PM.ref(pm,nw),:paper_a_regional) || throw(ArgumentError("AP3 requires the AP2 physical regional contract"))
        r=_PM.ref(pm,nw,:paper_a_regional); n=length(r.regions)
        alpha=_uc_gscr_g_min(pm,nw)
        isfinite(alpha) && alpha>=0 || throw(ArgumentError("fixed nonnegative alpha required"))
        PaperARegional.symmetric_z(r.B0)
        f isa FixedScalingGSCR && length(f.r)!=n && throw(DimensionMismatch("G2 region order"))
        if f isa InverseBoundGSCR
            alpha>0 || throw(ArgumentError("M1 requires alpha>0"))
            size(f.Bmin)==(n,n) || throw(DimensionMismatch("M1 region order"))
            # Only diagonal source additions are variable. Offdiagonals must be
            # identical to make the ordered M-matrix construction explicit.
            all(isapprox(f.Bmin[i,j],r.B0[i,j];atol=1e-10,rtol=1e-12) for i in 1:n,j in 1:n if i!=j) || throw(ArgumentError("M1 Bmin must share passive offdiagonals"))
        end
        f isa InteractionGSCR && size(f.W)!=(n,n) && throw(DimensionMismatch("M2 region order"))
    end
end

_paper_a_formulation!(pm,nw,f::GershgorinGSCR)=constraint_gscr_gershgorin_sufficient(pm;nw)
function _paper_a_formulation!(pm,nw,f::AbstractPaperAFormulation)
    x=_paper_a_online_expressions!(pm,nw)
    c=add_paper_a_constraints!(pm.model,x.B,x.p_fl,x.M,f;alpha=_uc_gscr_g_min(pm,nw))
    get!(pm.ext,:paper_a_certificates,Dict{Int,Any}())[nw]=c
    return c
end

"""Finish a deliberately deferred Paper-A build with added GFL exposure.

`additional_gfl[nw][region]` is nonnegative affine available power in case p.u.,
not dispatched MW. Every network and retained region must be present. Create
the renewable capacity/dispatch variables and physical balance terms first;
this function attaches their exposure once before B/S/M or strength rows exist.
The ordinary builder path and all existing formulation equations are retained.
"""
function finalize_paper_a_strength!(pm;additional_gfl)
    get(pm.ext,:paper_a_strength_pending,false)===true ||
        throw(ArgumentError("Paper-A strength was not deferred or is already finalized"))
    isempty(get(pm.ext,:paper_a_online,Dict())) ||
        throw(ArgumentError("Additional GFL exposure must precede the B/S/M cache"))
    networks=collect(nw_ids(pm))
    additional_gfl isa AbstractDict && Set(keys(additional_gfl))==Set(networks) ||
        throw(ArgumentError("Additional GFL network identities differ"))
    prepared=Dict{Int,Dict{Any,JuMP.AffExpr}}()
    # Validate the complete attachment before touching model/cache state.
    for n in networks
        regions=_PM.ref(pm,n,:paper_a_regional).regions
        values=additional_gfl[n]
        values isa AbstractDict && Set(keys(values))==Set(regions) ||
            throw(ArgumentError("Additional GFL region identities differ at $n"))
        current=Dict{Any,JuMP.AffExpr}()
        for region in regions
            value=values[region]
            (value isa Real && !(value isa Bool)) || value isa JuMP.VariableRef || value isa JuMP.AffExpr ||
                throw(ArgumentError("Additional GFL must be affine in renewable capacity"))
            expr=JuMP.AffExpr(0.)+value
            isfinite(expr.constant) && expr.constant>=0 ||
                throw(ArgumentError("Additional GFL constant must be finite and nonnegative"))
            for (variable,coefficient) in expr.terms
                isfinite(coefficient) && coefficient>=0 && JuMP.owner_model(variable)===pm.model ||
                    throw(ArgumentError("Additional GFL has invalid coefficient or foreign variable"))
                coefficient==0 && continue
                lower=JuMP.is_fixed(variable) ? JuMP.fix_value(variable) :
                    JuMP.has_lower_bound(variable) ? JuMP.lower_bound(variable) : -Inf
                isfinite(lower) && lower>=0 ||
                    throw(ArgumentError("Additional GFL capacity must have a nonnegative lower bound"))
            end
            current[region]=expr
        end
        prepared[n]=current
    end
    pm.ext[:paper_a_additional_gfl]=prepared
    for n in networks
        _paper_a_online_expressions!(pm,n)
        if _uc_gscr_block_requires_gscr_constraints(pm,n)
            _paper_a_formulation!(pm,n,_uc_gscr_block_gscr_formulation(pm,n))
        end
    end
    pm.ext[:paper_a_strength_pending]=false
    return pm
end

"""Attach a frozen formulation to supplied affine objects, also used by analytic
fixtures. No import, UC, cost, or physical coefficient calculation occurs here."""
function add_paper_a_constraints!(model,B,p,M,f::AbstractPaperAFormulation;alpha)
    n=length(p); size(B)==size(M)==(n,n) || throw(DimensionMismatch("B/S/M"))
    if f isa ExactPSDGSCR
        affine=[JuMP.AffExpr(0.)+M[i,j] for i in 1:n,j in 1:n]
        return (kind="G0",psd=JuMP.@constraint(model,Symmetric(affine) in JuMP.PSDCone()))
    elseif f isa FixedScalingGSCR
        length(f.r)==n || throw(DimensionMismatch("G2 r"))
        return (kind="G2",rows=[JuMP.@constraint(model,sum(M[i,j]*f.r[j] for j in 1:n)>=0) for i in 1:n])
    elseif f isa ExactEdgeSOCGSCR
        # All offdiagonals must be fixed; an exact zero test retains every
        # structural edge without numerical sparsification.
        edges=Tuple{Int,Int}[]
        for i in 1:n,j in i+1:n
            a=M[i,j]; b=M[j,i]
            av=a isa Number ? a : (isempty(a.terms) ? a.constant : throw(ArgumentError("G3 variable offdiagonal unsupported")))
            bv=b isa Number ? b : (isempty(b.terms) ? b.constant : throw(ArgumentError("G3 variable offdiagonal unsupported")))
            av==bv || throw(ArgumentError("G3 asymmetric edge"))
            av!=0 && push!(edges,(i,j))
        end
        q=JuMP.@variable(model,[1:length(edges),1:2],lower_bound=0,base_name="g3_q")
        cones=[JuMP.@constraint(model,[q[k,1],q[k,2],sqrt(2.)*M[i,j]] in JuMP.RotatedSecondOrderCone()) for (k,(i,j)) in enumerate(edges)]
        residue=[M[i,i]-sum((i==a ? q[k,1] : q[k,2]) for (k,(a,b)) in enumerate(edges) if i==a||i==b;init=0.) for i in 1:n]
        rows=[JuMP.@constraint(model,residue[i]>=0) for i in 1:n]
        return (kind="G3",edges=edges,q=q,cones=cones,residue=residue,rows=rows)
    elseif f isa InverseBoundGSCR
        alpha>0 || throw(ArgumentError("M1 alpha"))
        size(f.Bmin)==(n,n) || throw(DimensionMismatch("Bmin"))
        A=copy(f.Bmin)
        for i in 1:n,j in 1:n
            i==j && continue
            a=B[i,j]
            value=a isa Number ? a : (isempty(a.terms) ? a.constant : throw(ArgumentError("M1 requires fixed passive offdiagonals")))
            isapprox(A[i,j],value;atol=1e-10,rtol=1e-12) || throw(ArgumentError("M1 passive offdiagonal mismatch"))
            A[i,j]=value
        end
        # Independent physical stamps can differ by final-bit roundoff. Bind
        # the minimum to the model's IDENTICAL passive entries, rather than
        # introduce empty constant inequalities such as -1e-13 >= 0.
        isposdef(Symmetric(A)) || throw(ArgumentError("canonical M1 minimum is not PD"))
        Zub=A\Matrix{Float64}(I,n,n)
        lower=[JuMP.@constraint(model,B[i,i]>=A[i,i]) for i in 1:n]
        rows=[JuMP.@constraint(model,sum(Zub[i,j]*p[j] for j in 1:n)<=1/alpha) for i in 1:n]
        return (kind="M1",lower=lower,rows=rows,Bmin=A,passive_stamp_roundoff=maximum(abs.(A-f.Bmin)))
    elseif f isa InteractionGSCR
        size(f.W)==(n,n) || throw(DimensionMismatch("W"))
        return (kind="M2",rows=[JuMP.@constraint(model,sum(B[i,j] for j in 1:n)>=alpha*sum(f.W[i,j]*p[j] for j in 1:n)) for i in 1:n])
    end
    throw(ArgumentError("unsupported AP3 formulation"))
end
