module WeekStrengthAdmission
using JuMP
using SHA
const MOI=JuMP.MOI

"""Count every MOI constraint and admit only the reviewed continuous affine and conic domains."""
function inventory(model; continuous)
    counts=Dict{String,Int}()
    for (F,S) in MOI.get(model,MOI.ListOfConstraintTypesPresent())
        n=MOI.get(model,MOI.NumberOfConstraints{F,S}())
        n==0 && continue
        if continuous
            scalar=F <: Union{MOI.VariableIndex,MOI.ScalarAffineFunction} &&
                S <: Union{MOI.EqualTo,MOI.LessThan,MOI.GreaterThan,MOI.Interval}
            vector=F <: Union{MOI.VectorOfVariables,MOI.VectorAffineFunction} &&
                S <: Union{MOI.Zeros,MOI.Nonnegatives,MOI.Nonpositives,MOI.Reals,MOI.RotatedSecondOrderCone,
                    MOI.SecondOrderCone,MOI.PositiveSemidefiniteConeSquare,MOI.PositiveSemidefiniteConeTriangle,
                    MOI.Scaled{MOI.PositiveSemidefiniteConeTriangle}}
            scalar || vector || error("Unqualified continuous domain: $F in $S ($n)")
        end
        counts["$F in $S"]=n
    end
    return counts
end

"""Compare the attached native cost coefficients in their mapped variable coordinates."""
function native_cost(model,native)
    MOI.get(native,MOI.ObjectiveSense())==MOI.MIN_SENSE || error("native objective sense")
    f=MOI.get(native,MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    c=Dict(t.variable=>t.coefficient for t in MOI.Utilities.canonical(f).terms if t.coefficient!=0)
    original=AffExpr(0.)+objective_function(model)
    mapped=Dict(optimizer_index(v)=>a for (a,v) in linear_terms(original) if a!=0)
    c==mapped && f.constant==original.constant || error("native objective coefficient mismatch")
    io=IOBuffer()
    write(io,f.constant)
    for (v,a) in sort!(collect(c);by=t->first(t).value)
        write(io,v.value,a)
    end
    return Dict("constant"=>f.constant,"terms"=>length(c),"sha256"=>bytes2hex(sha256(take!(io))))
end

function psd_sizes(model)
    dims=Int[]
    for (F,S) in MOI.get(model,MOI.ListOfConstraintTypesPresent())
        S <: Union{MOI.PositiveSemidefiniteConeTriangle,MOI.PositiveSemidefiniteConeSquare,
                   MOI.Scaled{MOI.PositiveSemidefiniteConeTriangle}} || continue
        for i in MOI.get(model,MOI.ListOfConstraintIndices{F,S}())
            set=MOI.get(model,MOI.ConstraintSet(),i)
            push!(dims,MOI.side_dimension(set isa MOI.Scaled ? set.set : set))
        end
    end
    return dims
end

"""Read every mapped fixed-edge cone and node budget back from the attached MOSEK task."""
function native_strength_rows(pm,copy,native)
    m=copy.model
    idx=Dict(index(v)=>optimizer_index(v) for v in all_variables(m))
    ncone=nrows=0
    for cert in values(pm.ext[:paper_a_certificates])
        for original in Iterators.flatten((cert.cones,cert.rows))
            mapped=copy.constraints[original]
            ci=optimizer_index(mapped)
            object=constraint_object(mapped)
            expected=MOI.Utilities.map_indices(v->idx[v],JuMP.moi_function(object.func))
            actual=MOI.get(native,MOI.ConstraintFunction(),ci)
            isapprox(actual,expected;rtol=0,atol=0) &&
                MOI.get(native,MOI.ConstraintSet(),ci)==object.set || error("Native G3 strength row differs at $ci")
        end
        ncone+=length(cert.cones)
        nrows+=length(cert.rows)
    end
    return Dict("native_RSOC_exact_readbacks"=>ncone,"native_node_row_exact_readbacks"=>nrows)
end
end
