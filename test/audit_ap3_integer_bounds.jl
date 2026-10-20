include("../scripts/paper_a/AP3Pipeline.jl")
const P=AP3Pipeline
length(ARGS)==1 || error("usage: audit_ap3_integer_bounds.jl RUN_ROOT")
root=abspath(ARGS[1]);output=joinpath(root,"integer_bound_audit.json")
isfile(output) && error("audit exists")
folders=["suite_final","conditioned_conic_suite","rebased_conic_suite","integer_rechecks","integer_rechecks_roundoff"]
allruns=Any[]
for folder in folders
    path=joinpath(root,folder,"runs.json");isfile(path) || continue
    for r in P.readjson(path)["runs"]
        !r["relaxed"] && r["formulation"] in ("G0","G3") || continue
        push!(allruns,(folder,r))
    end
end
result=Any[]
for id in sort(unique(r["case_id"] for (_,r) in allruns))
    lower=Any[];points=Any[];attempts=Any[]
    raw=P.readjson(joinpath(root,"suite_final",id,"case.json"))
    casehash=P.D.hashfile(joinpath(root,"suite_final",id,"case.json"))
    for (folder,r) in filter(x->x[2]["case_id"]==id,allruns)
        r["case_sha256"]==casehash || error("cross-formulation bound input hash mismatch")
        push!(attempts,Dict("folder"=>folder,"formulation"=>r["formulation"],"termination"=>r["termination"],"status"=>r["status"],"objective"=>get(r,"objective",nothing),"bound"=>get(r,"bound",nothing),"reported_gap"=>get(r,"raw_solver_relative_gap",get(r,"relative_gap",nothing))))
        bound=get(r,"bound",nothing)
        if bound isa Real && isfinite(bound) && r["termination"] in ("OPTIMAL","ITERATION_LIMIT","TIME_LIMIT")
            push!(lower,Dict("value"=>bound,"folder"=>folder,"formulation"=>r["formulation"]))
        end
        file=joinpath(root,folder,r["solution_file"])
        isfile(file) && get(r,"primal_status",nothing)=="FEASIBLE_POINT" || continue
        solution=P.readjson(file);domain=true;worst=0.
        for t in keys(solution["snapshots"])
            rec=P.D.reconstruct(raw,solution,parse(Int,t));B=P.D.matrix(rec["B"])
            domain &= all(B[i,j]<=0 for i in axes(B,1),j in axes(B,2) if i!=j)
            m=P.D.evaluate(B,rec["p"],rec["alpha"])
            domain &= m["B.G0"]["value"]===true && m["B.G3"]["value"]===true
            worst=max(worst,max(0.,-m["B.G0_eigmin"]["value"]))
        end
        econ=P.planning(raw,solution,r)
        domain &= econ["objective_residual"]<1 && econ["bounds_violation_blocks"]<1e-5 && econ["integrality_residual"]<1e-5 && econ["power_balance_MW"]<1e-3 && econ["SOC_residual_MWh"]<1e-3 && econ["terminal_residual_MWh"]<1e-3
        value=sum(econ[k] for k in ("investment","generation","storage","events","no_load"))
        push!(points,Dict("folder"=>folder,"formulation"=>r["formulation"],"solution_sha256"=>P.D.hashfile(file),"independent_cost"=>value,"domain_and_operating_residuals_pass"=>domain,"minimum_PSD_violation"=>worst,"objective_residual"=>econ["objective_residual"]))
    end
    valid=filter(p->p["domain_and_operating_residuals_pass"],points)
    upper=isempty(valid) ? nothing : minimum(p["independent_cost"] for p in valid)
    bound=isempty(lower) ? nothing : maximum(b["value"] for b in lower)
    gap=upper===nothing || bound===nothing ? nothing : abs(upper-bound)/max(1.,abs(upper))
    certified=gap!==nothing && gap<=1e-6
    push!(result,Dict("case_id"=>id,"case_sha256"=>casehash,"status"=>certified ? "numerically_verified_reference" : "numerical_inconclusive","shared_G0_G3_upper_bound"=>upper,"shared_lower_bound"=>bound,"original_currency_relative_gap"=>gap,"tolerance"=>1e-6,"integer_optimum_certified"=>certified,"method"=>"independent feasible point and global solver bounds on identical fixed symmetric Z projection; frozen T018-T020; not interval arithmetic or independent A3.5 acceptance","bounds"=>lower,"points"=>points,"native_attempts"=>attempts))
end
P.writejson(output,Dict("schema"=>P.SCHEMA,"records"=>result,"provenance"=>P.provenance()))
