"""Finite-domain numerical guards for the native Paper-A G3 solver route."""
module NativeG3Solver
using JuMP
import MosekTools
const MOI = JuMP.MOI
const MIN_CONSTRAINT_COEFFICIENT = 1e-9
const MAX_COEFFICIENT = 2.0^40
const MIN_OBJECTIVE_COEFFICIENT = 2.0^-8
const PRIMAL_TOLERANCE = 1e-7

struct NumericalInputError <: Exception
    reason::String
end
Base.showerror(io::IO, e::NumericalInputError) = print(io, e.reason)

options() = Dict{String,Any}(
    "MSK_IPAR_NUM_THREADS"=>1, "MSK_DPAR_OPTIMIZER_MAX_TIME"=>120.,
    "MSK_DPAR_MIO_TOL_REL_GAP"=>1e-8, "MSK_DPAR_MIO_TOL_ABS_GAP"=>1e-10,
    "MSK_DPAR_MIO_TOL_FEAS"=>1e-8, "MSK_DPAR_MIO_TOL_ABS_RELAX_INT"=>1e-8,
    "MSK_DPAR_INTPNT_CO_TOL_PFEAS"=>1e-10,
    "MSK_DPAR_INTPNT_CO_TOL_DFEAS"=>1e-10,
    "MSK_DPAR_INTPNT_CO_TOL_REL_GAP"=>1e-10)
function optimizer(; tighter_feasibility=false)
    attrs=options()
    if tighter_feasibility
        attrs["MSK_DPAR_MIO_TOL_FEAS"]=5e-9
        attrs["MSK_DPAR_INTPNT_CO_TOL_PFEAS"]=5e-11
    end
    return optimizer_with_attributes(MosekTools.Optimizer, attrs...)
end
recorded_options(opt) = Dict(attr.name=>value for (attr,value) in opt.params if attr isa MOI.RawOptimizerAttribute)
is_native(opt) = opt isa MOI.OptimizerWithAttributes && opt.optimizer_constructor === MosekTools.Optimizer

function input_range(model)
    magnitudes = Float64[]
    for (F, S) in list_of_constraint_types(model)
        S <: MOI.PositiveSemidefiniteConeTriangle && throw(NumericalInputError("native_G3_route_does_not_qualify_MISDP"))
        for constraint in all_constraints(model, F, S)
            f = constraint_object(constraint).func
            expressions = f isa AbstractVector ? f : (f,)
            for expression in expressions
                if expression isa GenericAffExpr
                    append!(magnitudes, (abs(c) for (c, _) in linear_terms(expression) if c != 0))
                    isfinite(expression.constant) || throw(NumericalInputError("nonfinite_constraint_constant"))
                elseif !(expression isa VariableRef || expression isa Real)
                    throw(NumericalInputError("unsupported_native_G3_constraint_function"))
                end
            end
        end
    end
    lo = minimum(magnitudes; init=Inf)
    hi = maximum(magnitudes; init=0.)
    all(isfinite, magnitudes) && lo >= MIN_CONSTRAINT_COEFFICIENT && hi <= MAX_COEFFICIENT ||
        throw(NumericalInputError("native_G3_constraint_coefficient_range_outside_declared_domain: [$lo,$hi]"))
    return Dict("minimum_nonzero_coefficient"=>isfinite(lo) ? lo : nothing,
        "maximum_coefficient"=>hi, "coefficient_floor"=>MIN_CONSTRAINT_COEFFICIENT)
end

"""Scale the entire emitted affine objective by an exactly checked power of two.
The existing rebase/division precedes this operation; its rounding is separate.
"""
function condition_objective(f::GenericAffExpr)
    cs = [abs(c) for (c, _) in linear_terms(f) if c != 0]
    all(isfinite, cs) && isfinite(f.constant) || throw(NumericalInputError("nonfinite_objective"))
    lo = minimum(cs; init=Inf)
    exponent = isfinite(lo) && lo < MIN_OBJECTIVE_COEFFICIENT ?
        ceil(Int, log2(MIN_OBJECTIVE_COEFFICIENT) - log2(lo)) : 0
    0 <= exponent <= 1023 || throw(NumericalInputError("objective_multiplier_out_of_range"))
    multiplier = ldexp(1., exponent)
    g = f * multiplier
    # Checking the actual Float64 bits catches subnormal rounding and overflow.
    original = Dict(v=>c for (c,v) in linear_terms(f))
    isfinite(g.constant) && Rational{BigInt}(g.constant) == Rational{BigInt}(f.constant)*Rational{BigInt}(multiplier) ||
        throw(NumericalInputError("inexact_or_nonfinite_objective_constant_scaling"))
    for (c, v) in linear_terms(g)
        isfinite(c) && Rational{BigInt}(c) == Rational{BigInt}(original[v])*Rational{BigInt}(multiplier) ||
            throw(NumericalInputError("inexact_or_nonfinite_objective_term_scaling"))
    end
    largest = maximum((abs(c) for (c,_) in linear_terms(g)); init=0.)
    smallest = minimum((abs(c) for (c,_) in linear_terms(g) if c != 0); init=Inf)
    largest <= MAX_COEFFICIENT && abs(g.constant) <= MAX_COEFFICIENT && (!isfinite(smallest) || smallest >= MIN_OBJECTIVE_COEFFICIENT) ||
        throw(NumericalInputError("conditioned_objective_outside_declared_range"))
    return g, Dict("power_two_exponent"=>exponent, "multiplier"=>multiplier,
        "minimum_nonzero_coefficient"=>isfinite(smallest) ? smallest : nothing,
        "maximum_coefficient"=>largest, "exact_binary_scaling_verified"=>true)
end

function primal_check(model)
    has_values(model) || return Dict("status"=>"no_primal_point", "tolerance"=>PRIMAL_TOLERANCE)
    all(v->isfinite(value(v)), all_variables(model)) || return Dict("status"=>"nonfinite_primal_point")
    residual = maximum(values(primal_feasibility_report(model; atol=0.)); init=0.)
    return Dict("status"=>residual <= PRIMAL_TOLERANCE ? "passed" : "failed_original_primal_check",
        "maximum_constraint_distance"=>residual, "tolerance"=>PRIMAL_TOLERANCE,
        "interpretation"=>"numerical_original_model_check_not_exact_feasibility")
end
end
