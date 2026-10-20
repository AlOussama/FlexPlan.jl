using JuMP,LinearAlgebra
import JSON,HiGHS,SHA
include(joinpath(ARGS[1],"scripts/paper_a/AP3Pipeline.jl"))
const P=AP3Pipeline;const R=ARGS[2];const MOI=JuMP.MOI
mkpath(R)
save(n,v)=open(io->JSON.print(io,v,2),joinpath(R,n),"w")
summary=Any[]
root=joinpath(ARGS[1],"reports/ap3_runs/20261020_macro/accepted_suite")
for id in sort([basename(d) for d in readdir(root;join=true) if isdir(d)&&isfile(joinpath(d,"case.json"))])
    dir=joinpath(root,id);raw,data,scope=P.prepare(joinpath(dir,"case.json");registry=joinpath(dir,"parameter_registry.csv"),scenarios=joinpath(dir,"study_scenarios.toml"))
    pm=P.build(data,P.FP.NoGSCR(),scope;relaxed=true);m=pm.model;stats=P.solve!(pm,HiGHS.Optimizer)
    write_to_file(m,joinpath(R,id*"_BASE_LP.mof.json"))
    rows=Any[]
    for (F,S) in list_of_constraint_types(m),c in all_constraints(m,F,S)
        co=constraint_object(c);f=co.func
        if f isa VariableRef
            terms=[Dict("index"=>index(f).value,"coefficient"=>1.)];constant=0.
        elseif f isa AffExpr
            terms=[Dict("index"=>index(v).value,"coefficient"=>a) for (a,v) in linear_terms(f)];constant=f.constant
        else;error("nonlinear LP row");end
        s=co.set
        lower=s isa MOI.EqualTo ? s.value : s isa MOI.GreaterThan ? s.lower : s isa MOI.Interval ? s.lower : nothing
        upper=s isa MOI.EqualTo ? s.value : s isa MOI.LessThan ? s.upper : s isa MOI.Interval ? s.upper : nothing
        push!(rows,Dict("constraint"=>string(c),"set_type"=>string(typeof(s)),"constant"=>constant,"terms"=>terms,"lower"=>lower,"upper"=>upper,"dual"=>dual(c),"primal"=>value(f)))
    end
    obj=objective_function(m)
    save(id*"_dual_input.json",Dict("case_id"=>id,"case_sha256"=>bytes2hex(SHA.sha256(read(joinpath(dir,"case.json")))) ,"variables"=>[Dict("index"=>index(v).value,"name"=>name(v),"value"=>value(v)) for v in all_variables(m)],"objective"=>Dict("constant"=>obj.constant,"terms"=>[Dict("index"=>index(v).value,"coefficient"=>a) for (a,v) in linear_terms(obj)]),"rows"=>rows,"stats"=>stats))
    push!(summary,Dict("case_id"=>id,"stats"=>stats));save("summary.json",summary);println(id," LP dual exported");flush(stdout)
end
