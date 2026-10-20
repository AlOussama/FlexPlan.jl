# Build unchanged production models; independently audit every generated constraint.
# Historical point is only an integer assignment seed. Fresh solves supply full witnesses.
using JuMP,LinearAlgebra
import FlexPlan as FP, PowerModels as PM, Clarabel, HiGHS, Pajarito, JSON
include(joinpath(ARGS[1],"scripts","paper_a","AP3Pipeline.jl"))
const P=AP3Pipeline; const R=abspath(ARGS[2]);const B=abspath(ARGS[1]);const MOI=JuMP.MOI
mkpath(R)
load(p)=JSON.parsefile(p); save(n,x)=open(io->JSON.print(io,x,2),joinpath(R,n),"w")
function full_report(m)
    violations=JuMP.primal_feasibility_report(m;atol=0.)
    bytype=Dict{String,Float64}()
    for (c,v) in violations
        typ=string(typeof(JuMP.constraint_object(c).set));bytype[typ]=max(get(bytype,typ,0.),v)
    end
    return Dict("max_violation"=>maximum(values(violations);init=0.),"violations_by_set"=>bytype,"primal"=>string(primal_status(m)),"dual"=>string(dual_status(m)))
end
function fix_decisions!(pm,sol)
    fixed=Set{VariableRef}()
    for (t,sn) in sol["snapshots"],(key,a) in sn["assets"]
        table,id=split(key,":");asset=(Symbol(table),parse(Int,id));vv=PM.var(pm,parse(Int,t))
        for (sym,field) in ((:n_block,"installed"),(:na_block,"online"),(:su_block,"startup"),(:sd_block,"shutdown"))
            haskey(vv,sym) || continue
            asset in (vv[sym] isa AbstractDict ? keys(vv[sym]) : axes(vv[sym],1)) || continue
            v=vv[sym][asset];v in fixed && continue
            abs(a[field]-round(a[field]))<1e-5 || error("noninteger assignment")
            is_integer(v) && unset_integer(v);is_binary(v) && unset_binary(v)
            # Preserve bounds explicitly before fixing. Integer-fixing does not relax physical domains.
            x=round(a[field]);has_lower_bound(v) && x<lower_bound(v)-1e-8 && error("lower bound")
            has_upper_bound(v) && x>upper_bound(v)+1e-8 && error("upper bound")
            fix(v,x;force=true);push!(fixed,v)
        end
    end
    any(v->is_integer(v)||is_binary(v),all_variables(pm.model)) && error("unfixed integer")
    return length(fixed)
end
historical=joinpath(B,"reports/ap3_runs/20261020_macro/accepted_suite");runs=load(joinpath(historical,"runs.json"))["runs"];out=Any[]
for id in sort(unique(r["case_id"] for r in runs))
    dir=joinpath(historical,id);raw,data,scope=P.prepare(joinpath(dir,"case.json");registry=joinpath(dir,"parameter_registry.csv"),scenarios=joinpath(dir,"study_scenarios.toml"))
    source=first(filter(r->r["case_id"]==id && !r["relaxed"] && r["formulation"] in ("G0","G3") && get(r,"primal_status",nothing)=="FEASIBLE_POINT" && isfile(joinpath(historical,r["solution_file"])),runs))
    solpath=joinpath(historical,source["solution_file"])
    if length(ARGS)>=3 && ARGS[3]=="fixed_only_best_historical_seed"
        ledger=load(joinpath(dirname(historical),"integer_bound_audit.json"))
        claim=only(r for r in ledger["records"] if r["case_id"]==id)
        choice=first(sort(filter(p->p["domain_and_operating_residuals_pass"],claim["points"]);by=p->p["independent_cost"]))
        folder=joinpath(dirname(historical),choice["folder"])
        source=only(r for r in load(joinpath(folder,"runs.json"))["runs"] if r["case_id"]==id && !r["relaxed"] && r["formulation"]==choice["formulation"])
        solpath=joinpath(folder,source["solution_file"])
        P.D.hashfile(solpath)==choice["solution_sha256"] || error("selected seed hash mismatch")
    end
    sol=load(solpath);params=source["parameters"];points=Any[]
    for fid in ("G0","G3")
        pm=P.build(data,P.formulation(fid,params),scope;relaxed=false);nfixed=fix_decisions!(pm,sol)
        stats=P.solve!(pm,Clarabel.Optimizer)
        row=Dict{String,Any}("formulation"=>fid,"fixed_integer_decisions"=>nfixed,"stats"=>stats)
        if primal_status(pm.model)==MOI.FEASIBLE_POINT
            row["full_model_report"]=full_report(pm.model)
            row["point_file"]="full_witness_$(id)_$(fid).json"
            save(row["point_file"],Dict("solution"=>P.extract(pm),"all_variables"=>[Dict("name"=>name(v),"value"=>value(v),"index"=>index(v).value) for v in all_variables(pm.model)],"report"=>row["full_model_report"]))
            write_to_file(pm.model,joinpath(R,"fixed_$(id)_$(fid).mof.json"))
        end
        push!(points,row)
    end
    lp=P.build(data,FP.NoGSCR(),scope;relaxed=true);lpstats=P.solve!(lp,HiGHS.Optimizer)
    push!(out,Dict("case_id"=>id,"case_sha256"=>P.D.hashfile(joinpath(dir,"case.json")),"seed_path"=>solpath,"seed_sha256"=>P.D.hashfile(solpath),"points"=>points,"BASE_LP_lower_bound"=>lpstats,"historical_integer_bound_claims"=>[r for r in runs if r["case_id"]==id && !r["relaxed"] && r["formulation"] in ("G0","G3")]))
    save("independent_integer_fixed_checks.json",out)
    println(id," fixed G0/G3 complete");flush(stdout)
end
length(ARGS)>=3 && ARGS[3]=="fixed_only_best_historical_seed" && exit()
# Native problematic 24-snapshot instance: replicate objective rebase, vary ONLY scale.
id="reference_24snap";dir=joinpath(historical,id);raw,data,scope=P.prepare(joinpath(dir,"case.json");registry=joinpath(dir,"parameter_registry.csv"),scenarios=joinpath(dir,"study_scenarios.toml"))
params=first(r for r in runs if r["case_id"]==id)["parameters"];native=Any[]
for mode in ("original_rebase","baseline_conditioned")
    pm=P.build(data,FP.ExactEdgeSOCGSCR(),scope;relaxed=false);m=pm.model;original=objective_function(m);rebased=AffExpr(original.constant)
    for (c,v) in linear_terms(original)
        if c>0 && has_lower_bound(v) && lower_bound(v)>0
            low=lower_bound(v);inc=@variable(m,lower_bound=0.);@constraint(m,inc==v-low);add_to_expression!(rebased,c,inc);add_to_expression!(rebased,c*low)
        else
            add_to_expression!(rebased,c,v)
        end
    end
    scale=mode=="original_rebase" ? max(1.,maximum(abs(c) for (c,v) in linear_terms(original) if !is_fixed(v))) : only(filter(r->r["case_id"]==id,out))["BASE_LP_lower_bound"]["objective"]
    set_objective_function(m,rebased/scale)
    opt=optimizer_with_attributes(Pajarito.Optimizer,"oa_solver"=>optimizer_with_attributes(HiGHS.Optimizer,"output_flag"=>true,"threads"=>1,"mip_rel_gap"=>1e-8),"conic_solver"=>optimizer_with_attributes(Clarabel.Optimizer,"verbose"=>true,"tol_gap_abs"=>1e-10,"tol_gap_rel"=>1e-10,"tol_feas"=>1e-10),"use_iterative_method"=>true,"tol_rel_gap"=>1e-7,"tol_abs_gap"=>1e-8,"tol_feas"=>1e-7,"time_limit"=>120.,"iteration_limit"=>100,"verbose"=>true)
    set_optimizer(m,opt);write_to_file(m,joinpath(R,"native24_$(mode).mof.json"));optimize!(m)
    row=Dict{String,Any}("mode"=>mode,"termination"=>string(termination_status(m)),"primal"=>string(primal_status(m)),"dual"=>string(dual_status(m)),"scale"=>scale,"bound_currency"=>P.safe(()->objective_bound(m)*scale),"objective_constant_currency"=>original.constant,"backend"=>string(typeof(backend(m))),"unsafe_backend"=>string(typeof(unsafe_backend(m))))
    if primal_status(m)==MOI.FEASIBLE_POINT
        row["objective_currency"]=value(original);row["full_model_report"]=full_report(m)
        save("native24_$(mode)_witness.json",Dict("solution"=>P.extract(pm),"all_variables"=>[Dict("name"=>name(v),"value"=>value(v)) for v in all_variables(m)]))
    end
    try
        solver=MOI.get(unsafe_backend(m),MOI.RawSolver());row["raw_oa_status"]=string(MOI.get(solver.oa_opt,MOI.TerminationStatus()))
        row["raw_conic_status"]=string(MOI.get(solver.conic_opt,MOI.TerminationStatus()))
    catch e;row["raw_status_access_error"]=sprint(showerror,e);end
    push!(native,row);save("b1_native_attempts.json",native)
end
