"""Finite-domain numerical guards for the native Paper-A G3 solver route."""
module NativeG3Solver
using JuMP
import MosekTools, Gurobi
const MOI = JuMP.MOI
const MIN_CONSTRAINT_COEFFICIENT = 1e-9
const MAX_COEFFICIENT = 2.0^40
const MIN_OBJECTIVE_COEFFICIENT = 2.0^-8
const PRIMAL_TOLERANCE = 1e-7

struct NumericalInputError <: Exception
    reason::String
end
Base.showerror(io::IO, e::NumericalInputError) = print(io, e.reason)

mosek_options() = Dict{String,Any}(
    "MSK_IPAR_NUM_THREADS"=>1, "MSK_DPAR_OPTIMIZER_MAX_TIME"=>120.,
    "MSK_DPAR_MIO_TOL_REL_GAP"=>1e-8, "MSK_DPAR_MIO_TOL_ABS_GAP"=>1e-10,
    "MSK_DPAR_MIO_TOL_FEAS"=>1e-8, "MSK_DPAR_MIO_TOL_ABS_RELAX_INT"=>1e-8,
    "MSK_DPAR_INTPNT_CO_TOL_PFEAS"=>1e-10,
    "MSK_DPAR_INTPNT_CO_TOL_DFEAS"=>1e-10,
    "MSK_DPAR_INTPNT_CO_TOL_REL_GAP"=>1e-10)
gurobi_options() = Dict{String,Any}("Threads"=>1,"TimeLimit"=>120.,"MIPGap"=>1e-8,
    "FeasibilityTol"=>1e-8,"IntFeasTol"=>1e-8,"OptimalityTol"=>1e-9,"Seed"=>20261020,
    "NonConvex"=>0)
function optimizer(; backend=:gurobi, tighter_feasibility=false)
    backend in (:gurobi,:mosek) || throw(ArgumentError("unknown native G3 backend"))
    attrs=backend==:mosek ? mosek_options() : gurobi_options()
    if tighter_feasibility
        if backend==:mosek
            attrs["MSK_DPAR_MIO_TOL_FEAS"]=5e-9
            attrs["MSK_DPAR_INTPNT_CO_TOL_PFEAS"]=5e-11
        else
            attrs["FeasibilityTol"]=5e-9
        end
    end
    return optimizer_with_attributes(backend==:mosek ? MosekTools.Optimizer : Gurobi.Optimizer, attrs...)
end
recorded_options(opt) = Dict(attr.name=>value for (attr,value) in opt.params if attr isa MOI.RawOptimizerAttribute)
is_native(opt) = opt isa MOI.OptimizerWithAttributes && opt.optimizer_constructor in (MosekTools.Optimizer,Gurobi.Optimizer)
backend_name(opt) = opt.optimizer_constructor === MosekTools.Optimizer ? "MOSEK" : "Gurobi"

function configure_bridges!(model,opt)
    if backend_name(opt)=="Gurobi"
        # Keep the binary-rational RSOC model: the default variable rotation
        # introduces rounded 1/sqrt(2) coefficients. The existing MOI bridge
        # instead emits w^2 - 2*u*v <= 0 and u,v >= 0 using exact coefficients.
        remove_bridge(model,MOI.Bridges.Variable.RSOCtoSOCBridge)
        remove_bridge(model,MOI.Bridges.Constraint.RSOCtoSOCBridge)
        add_bridge(model,MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    end
    return
end

function prepare_backend!(model,opt)
    backend_name(opt)=="Gurobi" || return Dict("status"=>"native_RSOC_supported")
    MOI.Utilities.attach_optimizer(backend(model))
    native=unsafe_backend(model)
    # MOI's quadratic bridge emits nonnegativity as affine rows. Gurobi's
    # convexity detector requires variable bounds; add only bounds proved by
    # those exact existing rows. The feasible set is therefore unchanged.
    proved=Set{MOI.VariableIndex}()
    for ci in MOI.get(native,MOI.ListOfConstraintIndices{MOI.ScalarAffineFunction{Float64},MOI.GreaterThan{Float64}}())
        f=MOI.get(native,MOI.ConstraintFunction(),ci);s=MOI.get(native,MOI.ConstraintSet(),ci)
        length(f.terms)==1 && f.terms[1].coefficient==1. && f.constant==0. && s.lower==0. &&
            push!(proved,f.terms[1].variable)
    end
    bounds=Dict(MOI.get(native,MOI.ConstraintFunction(),ci)=>ci for ci in
        MOI.get(native,MOI.ListOfConstraintIndices{MOI.VariableIndex,MOI.GreaterThan{Float64}}()))
    ledger=Any[]
    for ci in MOI.get(native,MOI.ListOfConstraintIndices{MOI.ScalarQuadraticFunction{Float64},MOI.LessThan{Float64}}())
        f=MOI.get(native,MOI.ConstraintFunction(),ci);s=MOI.get(native,MOI.ConstraintSet(),ci)
        cross=filter(t->t.variable_1!=t.variable_2,f.quadratic_terms)
        diag=filter(t->t.variable_1==t.variable_2,f.quadratic_terms)
        length(cross)==1 && only(cross).coefficient==-2. && !isempty(diag) &&
            all(t->t.coefficient==2.,diag) && isempty(f.affine_terms) && f.constant==0. && s.upper==0. ||
            throw(NumericalInputError("unverified_native_rotated_quadratic_form"))
        ends=(only(cross).variable_1,only(cross).variable_2)
        for v in ends
            v in proved || throw(NumericalInputError("native_RSOC_endpoint_nonnegativity_not_proved"))
            if haskey(bounds,v)
                old=MOI.get(native,MOI.ConstraintSet(),bounds[v]).lower
                old<0. && MOI.set(native,MOI.ConstraintSet(),bounds[v],MOI.GreaterThan(0.))
            else
                bounds[v]=MOI.add_constraint(native,v,MOI.GreaterThan(0.))
            end
        end
        push!(ledger,Dict("quadratic_constraint_index"=>ci.value,
            "nonnegative_endpoint_indices"=>[v.value for v in ends],
            "nonnegativity_proof"=>"existing_exact_1_times_variable_ge_0_affine_row",
            "quad_form"=>"sum(w_squared)-2*u*v<=0; exact coefficients"))
    end
    return Dict("status"=>"exact_RSOC_quadratic_bridge_with_proved_redundant_bounds",
        "cones"=>length(ledger),"ledger"=>ledger,"nonconvex_parameter"=>0)
end

function input_range(model)
    magnitudes = Float64[]
    for (F, S) in list_of_constraint_types(model)
        S <: MOI.PositiveSemidefiniteConeTriangle && throw(NumericalInputError("native_G3_route_does_not_qualify_MISDP"))
        for constraint in all_constraints(model, F, S)
            object=constraint_object(constraint);f=object.func
            if object.set isa MOI.Interval
                s=object.set
                isfinite(s.lower) && isfinite(s.upper) && isfinite(s.upper-s.lower) &&
                    Rational{BigInt}(s.upper-s.lower)==Rational{BigInt}(s.upper)-Rational{BigInt}(s.lower) ||
                    throw(NumericalInputError("inexact_native_range_slack_width"))
            end
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
    polynomial=0.
    for (F,S) in list_of_constraint_types(model)
        S <: MOI.RotatedSecondOrderCone || continue
        for ci in all_constraints(model,F,S)
            y=value.(constraint_object(ci).func)
            polynomial=max(polynomial,-y[1],-y[2],sum(abs2,y[3:end])-2*y[1]*y[2])
        end
    end
    return Dict("status"=>max(residual,polynomial) <= PRIMAL_TOLERANCE ? "passed" : "failed_original_primal_check",
        "maximum_constraint_distance"=>residual, "tolerance"=>PRIMAL_TOLERANCE,
        "maximum_polynomial_RSOC_violation"=>polynomial,
        "interpretation"=>"numerical_original_model_check_not_exact_feasibility")
end

function seed_primal_start!(model,opt)
    backend_name(opt)=="Gurobi" || return Dict("status"=>"not_used")
    # The default floating rotation is only a candidate-generating heuristic.
    # Its bounds never enter the final result. The final optimizer uses the
    # exact quadratic RSOC bridge, and independently re-solves the original set.
    heuristic,mapping=copy_model(model)
    set_optimizer(heuristic,opt)
    set_optimizer_attribute(heuristic,"TimeLimit",30.)
    set_silent(heuristic)
    wall=@elapsed optimize!(heuristic)
    check=primal_check(heuristic)
    result=Dict{String,Any}("status"=>"no_valid_seed","heuristic_wall_s"=>wall,
        "heuristic_termination"=>string(termination_status(heuristic)),
        "original_primal_check"=>check,"heuristic_bound_used"=>false,
        "heuristic_time_limit_s"=>30.,
        "scope"=>"temporary_default_bridge_for_primal_start_only; no bound or model-equivalence acceptance")
    if check["status"]=="passed"
        values=[value(mapping[v]) for v in all_variables(model)]
        for (v,x) in zip(all_variables(model),values);set_start_value(v,x);end
        result["status"]="checked_primal_start_applied"
        result["values_in_original_variable_order"]=values
    end
    return result
end
end
