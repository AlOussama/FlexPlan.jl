include("../scripts/paper_a/AP3Pipeline.jl")
using .AP3Pipeline,JuMP,LinearAlgebra
import JSON
length(ARGS)==1 || error("usage: recheck_ap3_integer_conic.jl RUN_ROOT")
root=abspath(ARGS[1]);input=joinpath(root,"suite_final");out=joinpath(root,"integer_rechecks")
AP3Pipeline.newoutput(out)
runs=AP3Pipeline.readjson(joinpath(input,"runs.json"))["runs"];length(runs)==162 || error("source suite incomplete")
result=Any[]
for target in runs
    target["relaxed"] && continue
    target["formulation"] in ("G0","G3") || continue
    target["status"]=="optimal" && continue
    other=target["formulation"]=="G0" ? "G3" : "G0"
    source=filter(r->r["case_id"]==target["case_id"]&&!r["relaxed"]&&r["formulation"]==other&&r["status"]=="optimal",runs)
    isempty(source) && continue;source=only(source)
    id=target["case_id"];dir=joinpath(input,id)
    raw,data,scope=AP3Pipeline.prepare(joinpath(dir,"case.json");registry=joinpath(dir,"parameter_registry.csv"),scenarios=joinpath(dir,"study_scenarios.toml"))
    p=target["parameters"];solution=AP3Pipeline.readjson(joinpath(input,source["solution_file"]))
    pm=AP3Pipeline.build(data,AP3Pipeline.formulation(target["formulation"],p),scope;relaxed=false)
    # Fix EVERY integer block decision from the independently checked other
    # exact formulation. No alpha, physics, cost or capacity bound is relaxed.
    fixed=Set{JuMP.VariableRef}()
    for (t,sn) in solution["snapshots"],(key,a) in sn["assets"]
        table,idstr=split(key,":");asset=(Symbol(table),parse(Int,idstr));nw=parse(Int,t)
        for (sym,field) in ((:n_block,"installed"),(:na_block,"online"),(:su_block,"startup"),(:sd_block,"shutdown"))
            vars=AP3Pipeline.PM.var(pm,nw)
            haskey(vars,sym) || continue
            asset in (vars[sym] isa AbstractDict ? keys(vars[sym]) : axes(vars[sym],1)) || continue
            v=vars[sym][asset];v in fixed && continue
            abs(a[field]-round(a[field]))<1e-5 || error("nonintegral source decision")
            JuMP.is_integer(v) && JuMP.unset_integer(v)
            JuMP.fix(v,round(a[field]);force=true);push!(fixed,v)
        end
    end
    any(v->JuMP.is_integer(v)||JuMP.is_binary(v),JuMP.all_variables(pm.model)) && error("unfixed integer decision")
    stats=AP3Pipeline.solve!(pm,AP3Pipeline.Clarabel.Optimizer)
    stats["termination"]=="OPTIMAL" && stats["primal_status"]=="FEASIBLE_POINT" || error("fixed conic recheck failed")
    solved=AP3Pipeline.extract(pm);domain=true;violation=0.
    for t in keys(solved["snapshots"])
        rec=AP3Pipeline.D.reconstruct(raw,solved,parse(Int,t));B=AP3Pipeline.D.matrix(rec["B"])
        domain &= all(B[i,j]<=0 for i in axes(B,1),j in axes(B,2) if i!=j)
        met=AP3Pipeline.D.evaluate(B,rec["p"],rec["alpha"];witness=get(solved["snapshots"][t],"witness",nothing))
        domain &= met["B.G0"]["value"]===true && met["B.G3"]["value"]===true
        violation=max(violation,max(0.,-met["B.G0_eigmin"]["value"]))
    end
    lower=source["bound"];upper=stats["objective"]
    lower isa Real && isfinite(lower) || error("missing global reference bound")
    gap=abs(upper-lower)/max(1.,abs(upper));certified=domain && gap<=1e-6
    row=merge(copy(target),stats,Dict("native_integer_status"=>target["status"],"native_integer_termination"=>target["termination"],"native_integer_objective"=>get(target,"objective",nothing),"status"=>certified ? "optimal" : "numerical_inconclusive","integer_optimum_certified"=>certified,"integer_certificate_method"=>"fixed_all_integer_conic_recheck_plus_global_bound_of_other_exact_formulation_T020","reference_formulation"=>other,"reference_lower_bound"=>lower,"bound"=>lower,"relative_gap"=>gap,"maximum_independent_PSD_violation"=>violation,"fixed_integer_decisions"=>length(fixed),"source_AP3_SHA"=>AP3Pipeline.head(),"solver"=>"Clarabel fixed assignment + Pajarito other-formulation global bound","scope"=>"conditional_parametric_symmetric_Z_complete_G3; numerical certificate within 1e-6 relative gap"))
    mkpath(joinpath(out,id));AP3Pipeline.writejson(joinpath(out,row["solution_file"]),solved)
    push!(result,row)
end
AP3Pipeline.writejson(joinpath(out,"runs.json"),Dict("schema"=>AP3Pipeline.SCHEMA,"runs"=>result))
AP3Pipeline.writejson(joinpath(out,"provenance.json"),AP3Pipeline.provenance())
