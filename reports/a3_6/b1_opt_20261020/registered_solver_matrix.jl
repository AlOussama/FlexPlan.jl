using JuMP,LinearAlgebra
import JSON,HiGHS,Clarabel,Pajarito,SHA
include(joinpath(ARGS[1],"scripts/paper_a/AP3Pipeline.jl"))
const P=AP3Pipeline;const R=ARGS[2];const MOI=JuMP.MOI
mkpath(R);save(n,v)=open(io->JSON.print(io,v,2),joinpath(R,n),"w")
rows=Any[];root=joinpath(ARGS[1],"reports/ap3_runs/20261020_macro/accepted_suite")
for id in sort([basename(d) for d in readdir(root;join=true) if isdir(d)&&isfile(joinpath(d,"case.json"))])
    dir=joinpath(root,id);raw,data,scope=P.prepare(joinpath(dir,"case.json");registry=joinpath(dir,"parameter_registry.csv"),scenarios=joinpath(dir,"study_scenarios.toml"))
    lp=P.build(data,P.FP.NoGSCR(),scope;relaxed=true);lpstats=P.solve!(lp,HiGHS.Optimizer)
    for (fid,mode) in [("G3","original"),("G3","preserve_small_matrix"),("G3","preserve_small_matrix_costscale"),("G0","preserve_small_matrix"),("G3","continuous"),("G0","continuous")]
        mmodel=P.build(data,P.formulation(fid,Dict()),scope;relaxed=mode=="continuous")
        optimizer=mode=="continuous" ? Clarabel.Optimizer : P.pajarito_optimizer()
        if startswith(mode,"preserve_small_matrix")
            optimizer=optimizer_with_attributes(Pajarito.Optimizer,
                "oa_solver"=>optimizer_with_attributes(HiGHS.Optimizer,"output_flag"=>false,"threads"=>1,"random_seed"=>20261020,"mip_feasibility_tolerance"=>1e-8,"mip_rel_gap"=>1e-8,"small_matrix_value"=>1e-12),
                "conic_solver"=>optimizer_with_attributes(Clarabel.Optimizer,"verbose"=>false,"tol_gap_abs"=>1e-10,"tol_gap_rel"=>1e-10,"tol_feas"=>1e-10,"max_iter"=>300),
                "verbose"=>true,"use_iterative_method"=>true,"tol_rel_gap"=>1e-7,"tol_abs_gap"=>1e-8,"tol_feas"=>1e-7,"time_limit"=>120.,"iteration_limit"=>100)
        end
        println("BEGIN ",id," ",fid," ",mode);flush(stdout)
        stats=P.solve!(mmodel,optimizer;objective_scale=mode=="preserve_small_matrix_costscale" ? lpstats["objective"] : nothing)
        row=Dict{String,Any}("case_id"=>id,"formulation"=>fid,"mode"=>mode,"stats"=>stats,"case_sha256"=>bytes2hex(SHA.sha256(read(joinpath(dir,"case.json")))))
        if primal_status(mmodel.model)==MOI.FEASIBLE_POINT
            row["max_violation"]=maximum(values(primal_feasibility_report(mmodel.model;atol=0.));init=0.)
            save(id*"_"*fid*"_"*mode*"_witness.json",Dict("solution"=>P.extract(mmodel),"all_variables"=>[Dict("name"=>name(v),"index"=>index(v).value,"value"=>value(v)) for v in all_variables(mmodel.model)]))
        end
        push!(rows,row);save("results.json",rows)
    end
end
