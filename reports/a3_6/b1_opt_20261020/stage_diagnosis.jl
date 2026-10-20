using JuMP,LinearAlgebra,Test,SHA
import HiGHS,Clarabel,Pajarito,JSON
include(joinpath(ARGS[1],"scripts/paper_a/AP3Pipeline.jl"))
const P=AP3Pipeline;const R=ARGS[2];const MOI=JuMP.MOI
mkpath(R)
# Read the exact serialized original, without rebuilding or changing the objective.
m=read_from_file(joinpath(ARGS[3],"b1_exact_native.mof.json"))
set_optimizer(m,P.pajarito_optimizer());unset_silent(m);optimize!(m)
opt=unsafe_backend(m)
w=JSON.parsefile(joinpath(ARGS[3],"b1_exact_full_witness_verification.json"))
byname=Dict(p["name"]=>p["value"] for p in w["point"])
x=zeros(length(opt.c));mapped=Set{Int}();outer=backend(m);bo=outer.optimizer;inner=bo.model
for v in all_variables(m)
    vi=outer.model_to_optimizer_map[index(v)]
    f=MOI.Bridges.bridged_variable_function(bo,vi);target=byname[name(v)]
    if f isa MOI.VariableIndex
        j=inner.model_to_optimizer_map[f].value;x[j]=target;push!(mapped,j)
    else
        terms=[(z.coefficient,inner.model_to_optimizer_map[z.variable].value) for z in f.terms]
        if isempty(terms)
            @assert abs(target-f.constant)<1e-7
        elseif length(terms)==1
            c,j=only(terms);x[j]=(target-f.constant)/c;push!(mapped,j)
        elseif length(terms)==2 && sort(first.(terms))==[-1.,1.]
            y=target-f.constant
            for (c,j) in terms;x[j]=c>0 ? max(0.,y) : max(0.,-y);push!(mapped,j);end
        else
            error("unsupported bridge $f")
        end
    end
end
@assert length(mapped)==length(x)
start=Pajarito.get_oa_start(opt,x)
point=Dict(v=>start[i] for (i,v) in enumerate(opt.oa_vars))
viol=primal_feasibility_report(opt.oa_model,point;atol=0.)
sorted=sort(collect(viol);by=last,rev=true)
summary=Dict{String,Any}("native_status"=>string(termination_status(m)),"oa_status"=>string(termination_status(opt.oa_model)),"relax_status"=>string(termination_status(opt.relax_model)),"oa_max_violation"=>maximum(values(viol);init=0.),"oa_variables"=>length(start),"original_variables"=>length(x),"integer_variables"=>opt.num_int_vars,"top_violations"=>[Dict("constraint"=>string(c),"violation"=>v) for (c,v) in first(sorted,min(20,length(sorted)))])
save(n,v)=open(io->JSON.print(io,v,2),joinpath(R,n),"w")
save("stage_before.json",summary)
save("oa_full_witness.json",[Dict("name"=>name(v),"index"=>index(v).value,"value"=>point[v]) for v in all_variables(opt.oa_model)])
write_to_file(opt.oa_model,joinpath(R,"oa_frozen.mof.json"))
write_to_file(opt.relax_model,joinpath(R,"relax_frozen.mof.json"))
# Re-solve the frozen OA separately to distinguish cut geometry from MIP numerics.
rows=Any[]
for mode in ("mip_presolve_on","mip_presolve_off","lp_presolve_on","lp_presolve_off","integer_fixed_presolve_on")
    oa=read_from_file(joinpath(R,"oa_frozen.mof.json"));set_optimizer(oa,HiGHS.Optimizer)
    for (k,v) in (("threads",1),("random_seed",20261020),("time_limit",120.),("mip_feasibility_tolerance",1e-8),("mip_rel_gap",1e-8),("presolve",endswith(mode,"off") ? "off" : "on"));set_optimizer_attribute(oa,k,v);end
    if startswith(mode,"lp_");relax_integrality(oa);end
    if startswith(mode,"integer_fixed")
        vals=Dict(name(v)=>round(point[v]) for v in all_variables(opt.oa_model) if is_integer(v)||is_binary(v))
        for v in all_variables(oa)
            if haskey(vals,name(v));is_integer(v) && unset_integer(v);is_binary(v) && unset_binary(v);fix(v,vals[name(v)];force=true);end
        end
    end
    optimize!(oa)
    row=Dict{String,Any}("mode"=>mode,"termination"=>string(termination_status(oa)),"primal_status"=>string(primal_status(oa)),"dual_status"=>string(dual_status(oa)),"objective_bound"=>P.safe(()->objective_bound(oa)),"objective"=>P.safe(()->objective_value(oa)))
    if primal_status(oa)==MOI.FEASIBLE_POINT
        row["max_violation"]=maximum(values(primal_feasibility_report(oa;atol=0.));init=0.)
    end
    push!(rows,row);save("frozen_oa_results.json",rows)
end
