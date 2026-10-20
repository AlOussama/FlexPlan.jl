using JuMP,LinearAlgebra
import JSON,HiGHS,Pajarito
include(joinpath(ARGS[1],"scripts/paper_a/AP3Pipeline.jl"))
const P=AP3Pipeline;const R=ARGS[2];const MOI=JuMP.MOI;mkpath(R)
rows=Any[];root=joinpath(ARGS[1],"reports/ap3_runs/20261020_macro/accepted_suite")
save(n,v)=open(io->JSON.print(io,v,2),joinpath(R,n),"w")
for id in sort([basename(d) for d in readdir(root;join=true) if isdir(d)&&isfile(joinpath(d,"case.json"))])
    dir=joinpath(root,id);raw,data,scope=P.prepare(joinpath(dir,"case.json");registry=joinpath(dir,"parameter_registry.csv"),scenarios=joinpath(dir,"study_scenarios.toml"))
    lp=P.build(data,P.FP.NoGSCR(),scope;relaxed=true);lpstats=P.solve!(lp,HiGHS.Optimizer)
    for (mode,factor,fid) in [("production_costscale",1.,"G3"),("half_costscale",.5,"G3"),("double_costscale",2.,"G3"),("tighter_feasibility",1.,"G3"),("production_costscale",1.,"G0")]
        pm=P.build(data,P.formulation(fid,Dict()),scope;relaxed=false)
        optimizer=P.pajarito_optimizer()
        if mode=="tighter_feasibility"
            optimizer=optimizer_with_attributes(()->MOI.instantiate(P.pajarito_optimizer()),"tol_feas"=>5e-8)
        end
        println("BEGIN ",id," ",fid," ",mode);flush(stdout)
        stats=P.solve!(pm,optimizer;objective_scale=factor*lpstats["objective"])
        row=Dict{String,Any}("case_id"=>id,"formulation"=>fid,"mode"=>mode,"factor"=>factor,"stats"=>stats)
        if primal_status(pm.model)==MOI.FEASIBLE_POINT
            row["max_violation"]=maximum(values(primal_feasibility_report(pm.model;atol=0.));init=0.)
            save(id*"_"*fid*"_"*mode*"_witness.json",Dict("solution"=>P.extract(pm),"all_variables"=>[Dict("name"=>name(v),"index"=>index(v).value,"value"=>value(v)) for v in all_variables(pm.model)]))
        end
        push!(rows,row);save("results.json",rows)
    end
end
