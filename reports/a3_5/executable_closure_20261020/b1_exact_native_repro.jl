# Invoke the ORIGINAL solve! implementation, changing only log verbosity through a hook.
using JuMP
include(joinpath(ARGS[1],"scripts/paper_a/AP3Pipeline.jl"))
const P=AP3Pipeline; const R=ARGS[2]
root=joinpath(ARGS[1],"reports/ap3_runs/20261020_macro/accepted_suite/reference_24snap")
raw,data,scope=P.prepare(joinpath(root,"case.json");registry=joinpath(root,"parameter_registry.csv"),scenarios=joinpath(root,"study_scenarios.toml"))
pm=P.build(data,P.FP.ExactEdgeSOCGSCR(),scope;relaxed=false)
set_optimize_hook(pm.model,(m;kwargs...)->begin
    unset_silent(m)
    write_to_file(m,joinpath(R,"b1_exact_native.mof.json"))
    optimize!(m;ignore_optimize_hook=true)
end)
stats=P.solve!(pm,P.pajarito_optimizer())
if primal_status(pm.model)==JuMP.MOI.FEASIBLE_POINT
    P.writejson(joinpath(R,"b1_exact_native_witness.json"),P.extract(pm))
    stats["max_all_constraint_violation"]=maximum(values(primal_feasibility_report(pm.model;atol=0.));init=0.)
end
P.writejson(joinpath(R,"b1_exact_native_result.json"),stats)
opt=unsafe_backend(pm.model)
write_to_file(opt.oa_model,joinpath(R,"b1_generated_OA_model.mof.json"))
write_to_file(opt.relax_model,joinpath(R,"b1_bridged_conic_relaxation.mof.json"))
wp=joinpath(R,"b1_exact_full_witness_verification.json")
if isfile(wp)
    witness=P.readjson(wp);byindex=Dict(p["index"]=>p["value"] for p in witness["point"])
    x=zeros(length(opt.c));mapped=Set{Int}();outer=backend(pm.model);bo=outer.optimizer;inner=bo.model
    for v in all_variables(pm.model)
        vi=outer.model_to_optimizer_map[index(v)]
        f=JuMP.MOI.Bridges.bridged_variable_function(bo,vi)
        target=byindex[index(v).value]
        if f isa JuMP.MOI.VariableIndex
            j=inner.model_to_optimizer_map[f].value;x[j]=target;push!(mapped,j)
        else
            terms=[(z.coefficient,inner.model_to_optimizer_map[z.variable].value) for z in f.terms]
            if isempty(terms)
                abs(target-f.constant)<1e-7 || error("fixed variable bridge mismatch")
            elseif length(terms)==1
                c,j=only(terms);x[j]=(target-f.constant)/c;push!(mapped,j)
            elseif length(terms)==2 && sort(first.(terms))==[-1.,1.]
                y=target-f.constant
                for (c,j) in terms;x[j]=c>0 ? max(0.,y) : max(0.,-y);push!(mapped,j);end
            else
                error("unsupported multivariate variable bridge: $f")
            end
        end
    end
    length(mapped)==length(x) || error("bridged auxiliary variables not mapped")
    slack=opt.h-opt.G*x
    cone_distances=[JuMP.MOI.Utilities.distance_to_set(slack[idxs],cone) for (cone,idxs) in zip(opt.cones,opt.cone_idxs)]
    summary=Dict("variables"=>length(x),"integer_variables"=>opt.num_int_vars,"linear_equality_residual"=>maximum(abs.(opt.A*x-opt.b);init=0.),"maximum_bridged_cone_distance"=>maximum(cone_distances;init=0.),"cone_types"=>string.(opt.cones),"original_objective_offset_scaled"=>opt.obj_offset,"bridged_scaled_objective"=>sum(opt.c.*x)+opt.obj_offset,"OA_status"=>string(termination_status(opt.oa_model)),"relaxation_status"=>string(termination_status(opt.relax_model)))
    P.writejson(joinpath(R,"b1_bridged_full_witness_check.json"),summary)
end
