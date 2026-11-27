"""Invertible dyadic conditioning of the fixed G3 solver copy.

The original JuMP model remains the acceptance model. Integer coordinates are
never rescaled, including when the submitted problem is its relaxation.
"""
module G3EquivalentConditioning
using JuMP
const MOI = JuMP.MOI

function dyadic(x::Float64, exponent::Int)
    isfinite(x) || error("Nonfinite original conditioning coefficient")
    y = ldexp(x, exponent)
    isfinite(y) && ldexp(y, -exponent) == x || error("Inexact dyadic conditioning")
    return y
end

column_exponent(magnitude) = clamp(ceil(Int, log2(max(1., magnitude) / 128.)), 0, 7)
row_exponent(magnitude) = magnitude == 0. ? 0 : clamp(-round(Int, log2(magnitude)), -6, 20)

function finite_magnitude(v)
    a = Float64[1.]
    is_fixed(v) && push!(a, abs(fix_value(v)))
    has_lower_bound(v) && isfinite(lower_bound(v)) && push!(a, abs(lower_bound(v)))
    has_upper_bound(v) && isfinite(upper_bound(v)) && push!(a, abs(upper_bound(v)))
    return maximum(a)
end

scaled_set(s::MOI.GreaterThan{Float64}, e) = MOI.GreaterThan(dyadic(s.lower,e))
scaled_set(s::MOI.LessThan{Float64}, e) = MOI.LessThan(dyadic(s.upper,e))
scaled_set(s::MOI.EqualTo{Float64}, e) = MOI.EqualTo(dyadic(s.value,e))
scaled_set(s::MOI.Interval{Float64}, e) = MOI.Interval(dyadic(s.lower,e),dyadic(s.upper,e))
scaled_set(s::Union{MOI.Integer,MOI.ZeroOne}, e) = (e==0 || error("Integer lattice changed"); s)
scaled_set(s,e) = error("Unsupported conditioning set $(typeof(s))")

function affine(f, variables, exponents, row=0)
    f isa VariableRef && return AffExpr(0.,variables[f]=>dyadic(1.,exponents[f]+row))
    f isa Real && return AffExpr(dyadic(Float64(f),row))
    f isa GenericAffExpr || error("Only original affine G3 functions are qualified")
    a=AffExpr(dyadic(f.constant,row))
    for (coefficient,v) in linear_terms(f)
        add_to_expression!(a,dyadic(coefficient,exponents[v]+row),variables[v])
    end
    return a
end

function coefficient_max(f, exponents; constants=false)
    f isa VariableRef && return ldexp(1.,exponents[f])
    f isa Real && return constants ? abs(f) : 0.
    f isa GenericAffExpr || error("Unsupported original conditioning function")
    return max(constants ? abs(f.constant) : 0.,
        maximum((abs(dyadic(c,exponents[v])) for (c,v) in linear_terms(f));init=0.))
end

"""Create x=D*y and R*f(D*y) in a separate model, without optimizing it."""
function scaled_copy(original; protected=Set{VariableRef}(), objective_divisor=8192.)
    divisor=Float64(objective_divisor)
    isfinite(divisor) && divisor>0 && significand(divisor)==1. || error("Unqualified objective coordinate divisor")
    variables_original=all_variables(original)
    exponents=Dict(v=>(v in protected || is_integer(v) || is_binary(v) ? 0 : column_exponent(finite_magnitude(v))) for v in variables_original)
    # q has no finite upper bound. Its scale uses only the fixed original edge
    # constant, never a candidate point or an assumed physical capacity.
    for (F,S) in list_of_constraint_types(original)
        S <: Union{MOI.RotatedSecondOrderCone,MOI.SecondOrderCone} || continue
        for ci in all_constraints(original,F,S)
            f=constraint_object(ci).func
            length(f)==3 || error("Only fixed-edge three-coordinate RSOC qualified")
            c=f[3] isa Real ? f[3] : isempty(f[3].terms) ? f[3].constant : error("Variable edge constant")
            if S <: MOI.SecondOrderCone
                all(z isa GenericAffExpr && z.constant==0. for z in f[1:2]) || error("Offset SOC endpoint")
                plus=Dict(v=>a for (a,v) in linear_terms(f[1]));minus=Dict(v=>a for (a,v) in linear_terms(f[2]))
                length(plus)==2 && Set(keys(plus))==Set(keys(minus)) && all(==(1.),values(plus)) &&
                    sort(collect(values(minus)))==[-1.,1.] || error("Noncanonical original SOC endpoints")
                for v in keys(plus)
                    v in protected && error("Discrete G3 cone endpoint")
                    exponents[v]=column_exponent(abs(c/2))
                end
                continue
            end
            for endpoint in f[1:2]
                endpoint isa GenericAffExpr && endpoint.constant!=0. && error("Offset RSOC endpoint")
                terms=endpoint isa VariableRef ? [(1.,endpoint)] : collect(linear_terms(endpoint))
                length(terms)==1 && only(terms)[1] in (0.5,1.) || error("Noncanonical original RSOC endpoint")
                v=only(terms)[2]
                v in protected && error("Discrete G3 cone endpoint")
                exponents[v]=column_exponent(abs(c))
            end
        end
    end
    all(exponents[v]==0 for v in protected) || error("Original integer coordinates rescaled")
    transformed=Model();set_string_names_on_creation(transformed,false)
    ys=@variable(transformed,[1:length(variables_original)])
    variables=Dict(v=>ys[k] for (k,v) in enumerate(variables_original))
    constraints=Dict{ConstraintRef,ConstraintRef}();rows=Dict{ConstraintRef,Int}()
    for (F,S) in list_of_constraint_types(original),ci in all_constraints(original,F,S)
        object=constraint_object(ci);f=object.func;s=object.set
        if f isa VariableRef
            e=-exponents[f];new=ScalarConstraint(variables[f],scaled_set(s,e))
        elseif f isa GenericAffExpr
            e=row_exponent(coefficient_max(f,exponents))
            new=ScalarConstraint(affine(f,variables,exponents,e),scaled_set(s,e))
        elseif f isa AbstractVector && s isa Union{MOI.RotatedSecondOrderCone,MOI.SecondOrderCone}
            e=row_exponent(maximum(coefficient_max(z,exponents;constants=true) for z in f))
            new=VectorConstraint([affine(z,variables,exponents,e) for z in f],s)
        else
            error("Unqualified conditioning constraint $(typeof(f)) in $(typeof(s))")
        end
        constraints[ci]=add_constraint(transformed,new);rows[ci]=e
        stored=constraint_object(constraints[ci])
        same = new.func isa AbstractVector ? all(isequal_canonical(a,b) for (a,b) in zip(stored.func,new.func)) : isequal_canonical(stored.func,new.func)
        same && stored.set==new.set || error("JuMP changed the checked dyadic constraint")
    end
    set_objective_sense(transformed,objective_sense(original))
    set_objective_function(transformed,affine(objective_function(original),variables,exponents))
    metadata=Dict("method"=>"invertible_positive_dyadic_columns_and_rows_v1",
        "column_exponent_min"=>minimum(values(exponents)),"column_exponent_max"=>maximum(values(exponents)),
        "row_exponent_min"=>minimum(values(rows)),"row_exponent_max"=>maximum(values(rows)),
        "protected_original_discrete_count"=>length(protected),"protected_columns_unchanged"=>true,
        "variables"=>length(variables),"constraints"=>length(constraints),
        "original_row_error_amplification_max"=>maximum(ldexp(1.,-e) for (c,e) in rows if !(constraint_object(c).func isa VariableRef)),
        "original_bound_error_amplification_max"=>maximum(ldexp(1.,e) for e in values(exponents)),
        "exact_dyadic_coefficient_roundtrip"=>true,"objective_divisor_unchanged"=>divisor,
        "acceptance"=>"Unchanged original NativeG3Solver.primal_check, not scaled-native residuals")
    return (;model=transformed,variables,exponents,constraints,rows,metadata)
end

backmap(copy,v::VariableRef) = ldexp(value(copy.variables[v]),copy.exponents[v])

"""Read-only result projection. This adapter never calls an optimizer.

All status, bound and objective queries come from the actual scaled solver.
Only primal coordinates are mapped back. Duals are deliberately unavailable.
"""
mutable struct OriginalResults <: MOI.AbstractOptimizer
    original::Model
    copy::Any
    attached::Bool
end
MOI.supports_incremental_interface(::OriginalResults)=false
MOI.is_empty(p::OriginalResults)=!p.attached
MOI.empty!(p::OriginalResults)=(p.attached=false;nothing)
MOI.supports_constraint(::OriginalResults,::Type{F},::Type{S}) where {F,S}=true
function MOI.copy_to(p::OriginalResults,src::MOI.ModelLike)
    map=MOI.Utilities.IndexMap()
    indices=MOI.get(src,MOI.ListOfVariableIndices())
    Set(indices)==Set(index(v) for v in keys(p.copy.variables)) || error("Incomplete original result projection")
    for v in indices;map[v]=v;end
    for (F,S) in MOI.get(src,MOI.ListOfConstraintTypesPresent()),c in MOI.get(src,MOI.ListOfConstraintIndices{F,S}())
        map[c]=c
    end
    p.attached=true
    return map
end
MOI.optimize!(::OriginalResults)=nothing # No native optimizer invocation.
MOI.get(p::OriginalResults,a::MOI.AbstractModelAttribute)=MOI.get(backend(p.copy.model),a)
MOI.get(p::OriginalResults,a::MOI.AbstractOptimizerAttribute)=MOI.get(backend(p.copy.model),a)
MOI.get(::OriginalResults,::MOI.DualStatus)=MOI.NO_SOLUTION
function MOI.get(p::OriginalResults,a::MOI.VariablePrimal,v::MOI.VariableIndex)
    original=VariableRef(p.original,v)
    return ldexp(MOI.get(backend(p.copy.model),a,index(p.copy.variables[original])),p.copy.exponents[original])
end
function MOI.get(p::OriginalResults,a::MOI.ConstraintPrimal,c::MOI.ConstraintIndex)
    f=MOI.get(backend(p.original).model_cache,MOI.ConstraintFunction(),c)
    return MOI.Utilities.eval_variables(v->MOI.get(p,MOI.VariablePrimal(a.result_index),v),f)
end

function project_results!(original,copy)
    projection=OriginalResults(original,copy,false)
    set_optimizer(original,()->projection;add_bridges=false)
    optimize!(original) # Attach the read-only projection, not a second solve.
    return projection
end
end
