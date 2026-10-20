using JuMP
import HiGHS,JSON
const MOI=JuMP.MOI;const R=ARGS[1];mkpath(joinpath(R,"experiments/reduced"))
src=read_from_file(joinpath(R,"experiments/stages/oa_frozen.mof.json"))
m=Model();vars=@variable(m,[1:num_variables(src)])
mapping=Dict(v=>vars[index(v).value] for v in all_variables(src))
aff(f::VariableRef)=mapping[f]
aff(f::AffExpr)=AffExpr(f.constant,[mapping[v]=>a for (a,v) in linear_terms(f)])
for (F,S) in list_of_constraint_types(src),c in all_constraints(src,F,S)
    co=constraint_object(c)
    if co.set isa MOI.Nonnegatives
        for f in co.func;@constraint(m,aff(f)>=0.);end
    elseif co.set isa MOI.Zeros
        for f in co.func;@constraint(m,aff(f)==0.);end
    else
        add_constraint(m,ScalarConstraint(aff(co.func),co.set))
    end
end
set_objective_sense(m,objective_sense(src));set_objective_function(m,aff(objective_function(src)))
set_optimizer(m,HiGHS.Optimizer)
for (k,v) in (("threads",1),("mip_feasibility_tolerance",1e-8),("time_limit",120.));set_optimizer_attribute(m,k,v);end
optimize!(m);compute_conflict!(m)
result=Dict{String,Any}("scalarized_status"=>string(termination_status(m)),"conflict_status"=>string(MOI.get(backend(m),MOI.ConflictStatus())))
try
    cm,refmap=copy_conflict(m)
    write_to_file(cm,joinpath(R,"experiments/reduced/conflict.mof.json"))
    result["variables"]=num_variables(cm);result["constraints"]=num_constraints(cm;count_variable_in_set_constraints=true)
    # Recheck the reduced model under the two coefficient ingestion thresholds.
    for v in (1e-9,1e-12)
        set_optimizer(cm,HiGHS.Optimizer)
        set_optimizer_attribute(cm,"threads",1);set_optimizer_attribute(cm,"mip_feasibility_tolerance",1e-8);set_optimizer_attribute(cm,"small_matrix_value",v)
        optimize!(cm);result[string(v)]=Dict("status"=>string(termination_status(cm)),"primal"=>string(primal_status(cm)))
    end
catch e;result["error"]=sprint(showerror,e);end
open(io->JSON.print(io,result,2),joinpath(R,"experiments/reduced/result.json"),"w")
