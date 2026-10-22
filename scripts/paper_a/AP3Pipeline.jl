module AP3Pipeline
using LinearAlgebra, JuMP
import FlexPlan as FP, PowerModels as PM, HiGHS, Clarabel, Gurobi, Pajarito, JSON, SHA, TOML, CSV, Pkg
include("NativeG3Solver.jl")
mosek_optimizer() = NativeG3Solver.optimizer()
const D=FP.PaperADiagnostics
const SCHEMA=D.SCHEMA
const SEED=20261020
const SCIENCE="2c2fce769b2ed6ffd4f1ced60c0798776acccc93"
const BASE="e992edc88d39fa0eb2d72e2490e157441223f568"
const CANDIDATES=["BASE","G0","G1","G2_identity","G2_degree","G3","M1","M2_full","M2_neighbor"]
function pajarito_optimizer()
    return JuMP.optimizer_with_attributes(Pajarito.Optimizer,
        # Retain the tiny OA coefficients: the default 1e-9 filter can turn a
        # valid cut into 0 >= positive RHS in the registered 24-snapshot model.
        "oa_solver"=>JuMP.optimizer_with_attributes(HiGHS.Optimizer,"output_flag"=>false,"threads"=>1,"small_matrix_value"=>1e-12,"mip_feasibility_tolerance"=>1e-8,"mip_rel_gap"=>1e-8),
        "conic_solver"=>JuMP.optimizer_with_attributes(Clarabel.Optimizer,"verbose"=>false,"tol_gap_abs"=>1e-10,"tol_gap_rel"=>1e-10,"tol_feas"=>1e-10,"max_iter"=>300),
        "verbose"=>false,"use_iterative_method"=>true,"tol_rel_gap"=>1e-7,"tol_abs_gap"=>1e-8,"tol_feas"=>1e-7,"time_limit"=>120.,"iteration_limit"=>100)
end
writejson(path,x)=open(io->JSON.print(io,x,2),path,"w")
readjson(path)=JSON.parsefile(path)
function newoutput(path)
    ispath(path) && throw(ArgumentError("output exists; use a new run directory: $path"))
    mkpath(path);return abspath(path)
end
safe(f)=try f() catch;nothing end
nonnegative(f)=begin x=safe(f);x isa Real && isfinite(x) && x>=0 ? x : nothing end
head()=strip(read(`git rev-parse HEAD`,String))
function provenance()
    versions=Dict(p.name=>string(p.version) for p in values(Pkg.dependencies()) if p.version!==nothing)
    root=normpath(joinpath(@__DIR__,"..",".."));hashes=Dict{String,String}()
    for folder in ("src","scripts/paper_a"),(dir,_,files) in walkdir(joinpath(root,folder)),file in files
        path=joinpath(dir,file);endswith(file,".jl") && (hashes[relpath(path,root)]=D.hashfile(path))
    end
    for name in ("Project.toml","Manifest-v1.10.toml");hashes[name]=D.hashfile(joinpath(root,name));end
    dirty=!isempty(strip(read(`git status --porcelain -- src scripts Project.toml Manifest-v1.10.toml`,String)))
    return Dict("schema"=>SCHEMA,"seed"=>SEED,"AP3_SHA"=>head(),"source_dirty"=>dirty,"source_sha256"=>hashes,"AP2_SHA"=>BASE,"science_SHA"=>SCIENCE,"julia"=>string(VERSION),"packages"=>versions,"empirical_approved"=>false,"scientific_design"=>"conditional_owner_review_pending","A3_closed"=>false,"AP4_ready"=>false)
end

function template(data,f,scope)
    assignments=Dict{Tuple{Symbol,Any},FP.AbstractBlockDeviceFormulation}()
    for table in ("gen","storage","ne_storage"),d in values(get(data["nw"]["1"],table,Dict()))
        haskey(d,"source_class") || continue
        assignments[(Symbol(table),d["carrier"])]=table!="gen" ? FP.BlockStorageParticipation() : d["source_class"]=="SYN" ? FP.BlockThermalCommitment() : FP.BlockRenewableParticipation()
    end
    return FP.UCGSCRBlockTemplate(assignments,f;paper_a_validation_scope=Symbol(scope),storage_cost_policy=:discharge)
end
function build(data,f,scope;relaxed)
    tpl=template(data,f,scope)
    return PM.instantiate_model(deepcopy(data),PM.DCPPowerModel,
        pm->FP.build_uc_gscr_block_integration(pm;template=tpl,relax_block_variables=relaxed,storage_terminal_policy=:fixed_initial);
        ref_extensions=[FP.ref_add_gen!,FP.ref_add_storage!,FP.ref_add_ne_storage!,
            (r,d)->FP.ref_add_uc_gscr_block!(r,d;paper_a_validation_scope=Symbol(scope))])
end
function prepare(path;registry=nothing,scenarios=nothing)
    raw=readjson(path);data=FP.parse_file(path);n=length(data["nw"])
    FP.add_dimension!(data,:hour,n)
    FP.add_dimension!(data,:scenario,Dict(1=>Dict{String,Any}("probability"=>1.)))
    FP.add_dimension!(data,:year,1;metadata=Dict{String,Any}("scale_factor"=>1))
    scope=raw["paper_a_extension"]["dataset_kind"]=="parametric_study" ? "parametric_study" : "synthetic_regression"
    if scope=="parametric_study"
        registry===nothing && throw(ArgumentError("canonical registry required"))
        scenarios===nothing && throw(ArgumentError("canonical scenarios required"))
        FP.register_paper_a_parameters!(data,registry,scenarios)
    end
    FP.scale_paper_a_costs!(data)
    return raw,data,scope
end

"""Strategies are determined from input topology before any optimization.
The M1 floor is an explicit certificate parameter, not a new physical shunt.
Its lower bound is enforced by InverseBoundGSCR and can make a run infeasible.
"""
function parameters(raw)
    net=raw["paper_a_network"]
    # Raw independent stamp with zero solved block decisions determines B0.
    snaps=Dict{String,Any}()
    for (t,sn) in raw["nw"]
        assets=Dict("$table:$id"=>Dict("online"=>0.,"installed"=>d["n0"],"dispatch_MW"=>0.) for table in ("gen","storage","ne_storage") for (id,d) in get(sn,table,Dict()) if haskey(d,"source_class"))
        snaps[t]=Dict("assets"=>assets)
    end
    rec=D.reconstruct(raw,Dict("snapshots"=>snaps),1);B0=D.matrix(rec["B0"]);n=size(B0,1)
    spectral_floor=max(.01,.01-eigmin(Symmetric(B0)))
    reference_shift=max(1.0,1.0 - eigmin(Symmetric(B0)))
    A=B0+reference_shift*Matrix{Float64}(I,n,n);Z=A\Matrix{Float64}(I,n,n)
    W=max.(0.,Z ./diag(Z));W[diagind(W)].=1.
    Ws=copy(W)
    for i in 1:n,j in 1:n;i!=j && B0[i,j]==0 && (Ws[i,j]=0.);end
    degree=[1.0 + count(j->j!=i && B0[i,j]!=0,1:n) for i in 1:n]
    return Dict("r_identity"=>ones(n),"r_degree"=>degree,"Bmin"=>D.rows(B0+spectral_floor*Matrix{Float64}(I,n,n)),"M1_source_floor_pu"=>spectral_floor,"MIIF_reference_diagonal_pu"=>reference_shift,"W_full"=>D.rows(W),"W_neighbor"=>D.rows(Ws),"provenance"=>"offline_v1:degree_plus_one;MIIF_from_B0_shifted_to_PSD_margin_1;M1_enforced_source_floor_for_PSD_margin_0.01","regions"=>rec["regions"])
end
function formulation(id,p)
    id=="BASE" && return FP.NoGSCR()
    id=="G0" && return FP.ExactPSDGSCR()
    id=="G1" && return FP.GershgorinGSCR()
    id=="G3" && return FP.ExactEdgeSOCGSCR()
    id=="G2_identity" && return FP.FixedScalingGSCR(p["r_identity"];provenance=p["provenance"])
    id=="G2_degree" && return FP.FixedScalingGSCR(p["r_degree"];provenance=p["provenance"])
    id=="M1" && return FP.InverseBoundGSCR(D.matrix(p["Bmin"]);provenance=p["provenance"])
    id=="M2_full" && return FP.InteractionGSCR(D.matrix(p["W_full"]);provenance=p["provenance"])
    id=="M2_neighbor" && return FP.InteractionGSCR(D.matrix(p["W_neighbor"]);provenance=p["provenance"])
    throw(ArgumentError("unknown formulation $id"))
end

function modelstats(m)
    counts=Dict(string(F)*" in "*string(S)=>JuMP.num_constraints(m,F,S) for (F,S) in JuMP.list_of_constraint_types(m))
    return Dict("variables"=>JuMP.num_variables(m),"integer"=>count(v->JuMP.is_integer(v)||JuMP.is_binary(v),JuMP.all_variables(m)),"constraints"=>counts)
end
function solve!(pm,optimizer;objective_scale=nothing)
    m=pm.model;original=JuMP.AffExpr(0.)+JuMP.objective_function(m)
    native_g3=NativeG3Solver.is_native(optimizer)
    solver_objective=original;rebased=0
    if optimizer!==HiGHS.Optimizer && optimizer!==Clarabel.Optimizer && optimizer!==Gurobi.Optimizer
        # Pajarito's relative gap excludes its affine objective offset. Express
        # installed-minus-initial costs in nonnegative increment coordinates,
        # retaining the exact frozen objective and every physical decision.
        solver_objective=JuMP.AffExpr(original.constant)
        for (c,v) in JuMP.linear_terms(original)
            if c>0 && JuMP.has_lower_bound(v) && JuMP.lower_bound(v)>0
                lower=JuMP.lower_bound(v)
                increment=JuMP.@variable(m,lower_bound=0.,base_name="objective_increment")
                JuMP.@constraint(m,increment==v-lower)
                JuMP.add_to_expression!(solver_objective,c,increment)
                JuMP.add_to_expression!(solver_objective,c*lower);rebased+=1
            else
                JuMP.add_to_expression!(solver_objective,c,v)
            end
        end
    end
    scale=optimizer!==HiGHS.Optimizer && optimizer!==Gurobi.Optimizer ? max(1.,maximum((abs(c) for (c,v) in JuMP.linear_terms(original) if !JuMP.is_fixed(v));init=1.)) : 1.
    objective_scale===nothing || (scale=Float64(objective_scale))
    isfinite(scale) && scale>0 || throw(ArgumentError("positive objective conditioning factor required"))
    emitted_objective=solver_objective/scale
    native_range=nothing;conditioning=nothing;multiplier=1.
    if native_g3
        try
            native_range=NativeG3Solver.input_range(m)
            emitted_objective,conditioning=NativeG3Solver.condition_objective(emitted_objective)
            multiplier=conditioning["multiplier"]
        catch e
            e isa NativeG3Solver.NumericalInputError || rethrow()
            return Dict{String,Any}("termination"=>"OPTIMIZE_NOT_CALLED","primal_status"=>"NO_SOLUTION",
                "dual_status"=>"NO_SOLUTION","objective"=>nothing,"bound"=>nothing,"relative_gap"=>nothing,
                "numerical_validation"=>"rejected_input","numerical_reason"=>sprint(showerror,e),
                "solver"=>"MOSEK","solve_wall_s"=>0.,"model"=>modelstats(m))
        end
    end
    JuMP.set_objective_function(m,emitted_objective)
    JuMP.set_optimizer(m,optimizer);JuMP.set_silent(m)
    if optimizer===HiGHS.Optimizer
        JuMP.set_optimizer_attribute(m,"threads",1)
        JuMP.set_optimizer_attribute(m,"mip_rel_gap",1e-8);JuMP.set_optimizer_attribute(m,"time_limit",120.)
        JuMP.set_optimizer_attribute(m,"random_seed",SEED)
    elseif optimizer===Clarabel.Optimizer
        for (k,v) in (("tol_gap_abs",1e-10),("tol_gap_rel",1e-10),("tol_feas",1e-10),("max_iter",300));JuMP.set_optimizer_attribute(m,k,v);end
    end
    wall=@elapsed JuMP.optimize!(m)
    feasible=JuMP.primal_status(m)==JuMP.MOI.FEASIBLE_POINT
    effective_scale=scale/multiplier
    obj=feasible ? JuMP.value(original) : nothing;bound=safe(()->JuMP.objective_bound(m)*effective_scale)
    if !(bound isa Real && isfinite(bound)) && JuMP.has_duals(m)
        bound=safe(()->JuMP.dual_objective_value(m)*effective_scale)
    end
    gap=obj isa Real && bound isa Real && isfinite(bound) ? abs(obj-bound)/max(1.,abs(obj)) : nothing
    result=Dict{String,Any}("termination"=>string(JuMP.termination_status(m)),"primal_status"=>string(JuMP.primal_status(m)),"dual_status"=>string(JuMP.dual_status(m)),"objective"=>obj,"objective_solver_scaling"=>effective_scale,"bound"=>bound,"relative_gap"=>gap,"raw_solver_relative_gap"=>nonnegative(()->JuMP.relative_gap(m)),"solve_wall_s"=>wall,"solver_time_s"=>nonnegative(()->JuMP.solve_time(m)),"solver"=>JuMP.solver_name(m),"optimizer_configuration"=>native_g3 ? "MOSEK: native G3, exact power-of-two objective conditioning; recorded options" : optimizer===HiGHS.Optimizer ? "HiGHS: threads=1,seed=20261020,mip_rel_gap=1e-8,time_limit=120s" : optimizer===Clarabel.Optimizer ? "Clarabel: tol_gap_abs=tol_gap_rel=tol_feas=1e-10,max_iter=300,objective_scaled_by_recorded_positive_factor" : "Pajarito: iterative,HiGHS+Clarabel,tol_rel_gap=tol_feas=1e-7,tol_abs_gap=1e-8,time_limit=120s,iteration_limit=100","barrier_iterations"=>nonnegative(()->JuMP.barrier_iterations(m)),"simplex_iterations"=>nonnegative(()->JuMP.simplex_iterations(m)),"nodes"=>nonnegative(()->JuMP.node_count(m)),"model"=>modelstats(m))
    if native_g3
        check=NativeG3Solver.primal_check(m)
        merge!(result,Dict("objective_requested_divisor"=>scale,"objective_conditioning"=>conditioning,
            "native_input_range"=>native_range,"optimizer_options"=>NativeG3Solver.recorded_options(optimizer),
            "numerical_validation"=>check["status"],"original_primal_check"=>check,
            "objective_backend"=>safe(()->JuMP.objective_value(m)),
            "bound_backend_numerical"=>safe(()->JuMP.objective_bound(m)),
            "bound_certification"=>"numerical_only_not_rigorous_currency_bound",
            "bound_coordinate"=>"nominal_original_objective; affine_rounding_delta_not_globally_bounded"))
    end
    return result
end
function extract(pm)
    snaps=Dict{String,Any}()
    for t in sort(collect(keys(pm.ext[:paper_a_online])))
        assets=Dict{String,Any}();base=PM.ref(pm,t,:paper_a_regional).S_base_MVA
        for (table,id) in keys(PM.ref(pm,t,:paper_a_coefficients))
            key=(table,id);vv=PM.var(pm,t);d=PM.ref(pm,t,table,id)
            event(sym)=haskey(vv,sym) && key in (vv[sym] isa AbstractDict ? keys(vv[sym]) : axes(vv[sym],1)) ? JuMP.value(vv[sym][key]) : 0.
            a=Dict{String,Any}("installed"=>JuMP.value(PM.var(pm,t,:n_block,key)),"online"=>JuMP.value(PM.var(pm,t,:na_block,key)),"startup"=>event(:su_block),"shutdown"=>event(:sd_block),"dispatch_MW"=>base*JuMP.value(PM.var(pm,t,table==:gen ? :pg : table==:storage ? :sd : :sd_ne,id)))
            if table!=:gen
                a["charge_MW"]=base*JuMP.value(PM.var(pm,t,table==:storage ? :sc : :sc_ne,id))
                a["energy_MWh"]=base*JuMP.value(PM.var(pm,t,table==:storage ? :se : :se_ne,id))
            end
            assets["$table:$id"]=a
        end
        x=pm.ext[:paper_a_online][t]
        affine=Dict("B"=>D.rows(JuMP.value.(x.B)),"M"=>D.rows(JuMP.value.(x.M)),"p"=>JuMP.value.(x.p_fl))
        flows=Dict{String,Any}()
        for (i,br) in PM.ref(pm,t,:branch)
            flows[string(i)]=[base*JuMP.value(PM.var(pm,t,:p,(i,br["f_bus"],br["t_bus"]))),base*JuMP.value(PM.var(pm,t,:p,(i,br["t_bus"],br["f_bus"])))]
        end
        sn=Dict{String,Any}("assets"=>assets,"affine"=>affine,"branch_flows_MW"=>flows)
        cert=get(get(pm.ext,:paper_a_certificates,Dict()),t,nothing)
        if cert!==nothing && cert.kind=="G3"
            sn["witness"]=Dict("edges"=>[[i,j] for (i,j) in cert.edges],"q"=>[[JuMP.value(cert.q[k,1]),JuMP.value(cert.q[k,2])] for k in eachindex(cert.edges)])
        end
        dual=Dict{String,Any}("status"=>"not_available_integer_or_no_dual_solution","dual_cone_violation"=>nothing,"complementarity_residual"=>nothing)
        if cert!==nothing && JuMP.has_duals(pm.model) && cert.kind in ("G0","G3")
            if cert.kind=="G0"
                Z=JuMP.dual(cert.psd);MM=JuMP.value.(x.M)
                dual=Dict("status"=>"valid","dual_cone_violation"=>max(0.,-eigmin(Symmetric(Z))),"complementarity_residual"=>abs(sum(MM.*Z)))
            else
                violation=0.;complement=0.
                for (k,(i,j)) in enumerate(cert.edges)
                    z=JuMP.dual(cert.cones[k]);v=[JuMP.value(cert.q[k,1]),JuMP.value(cert.q[k,2]),sqrt(2.)*JuMP.value(x.M[i,j])]
                    violation=max(violation,-z[1],-z[2],z[3]^2-2z[1]*z[2]);complement=max(complement,abs(dot(v,z)))
                end
                dual=Dict("status"=>"valid","dual_cone_violation"=>violation,"complementarity_residual"=>complement)
            end
        end
        sn["conic_dual"]=dual
        snaps[string(t)]=sn
    end
    return Dict("snapshots"=>snaps)
end

function capability_probe()
    result=Any[]
    for (name,opt) in (("HiGHS",HiGHS.Optimizer),("Clarabel",Clarabel.Optimizer),("Pajarito",pajarito_optimizer()))
        for kind in ("LP","MILP","SDP","SOCP","MISOCP","MISDP")
            row=Dict{String,Any}("solver"=>name,"kind"=>kind)
            try
                m=JuMP.Model(opt);JuMP.set_silent(m);x=JuMP.@variable(m,lower_bound=0.)
                name=="HiGHS" && JuMP.set_optimizer_attribute(m,"threads",1)
                kind in ("MILP","MISOCP","MISDP") && JuMP.set_integer(x)
                if kind in ("SDP","MISDP");JuMP.@constraint(m,[x 1.;1. x] in JuMP.PSDCone())
                elseif kind in ("SOCP","MISOCP");JuMP.@constraint(m,[x,x,sqrt(2.)] in JuMP.RotatedSecondOrderCone())
                else;JuMP.@constraint(m,x>=1.);end
                JuMP.@objective(m,Min,x);JuMP.optimize!(m)
                row["termination"]=string(JuMP.termination_status(m));row["objective"]=JuMP.has_values(m) ? JuMP.objective_value(m) : nothing
                row["status"]=JuMP.termination_status(m)==JuMP.MOI.OPTIMAL ? "supported_runtime_verified" : "numerical_inconclusive"
                row["backend"]=string(typeof(JuMP.backend(m)));row["bridge_policy"]="JuMP_default_bridges"
                row["MOI_affine_PSD_support"]=safe(()->JuMP.MOI.supports_constraint(JuMP.backend(m),JuMP.MOI.VectorAffineFunction{Float64},JuMP.MOI.PositiveSemidefiniteConeTriangle))
                row["MOI_affine_RSOC_support"]=safe(()->JuMP.MOI.supports_constraint(JuMP.backend(m),JuMP.MOI.VectorAffineFunction{Float64},JuMP.MOI.RotatedSecondOrderCone))
            catch e
                row["status"]="solver_unsupported";row["error"]=sprint(showerror,e)
            end
            push!(result,row)
        end
    end
    # A locally usable license is established by a real cone/integer solve.
    for (solver_name,optimizer) in (("Gurobi",Gurobi.Optimizer),("MOSEK",mosek_optimizer()))
      try
        m=JuMP.Model(optimizer);JuMP.set_silent(m)
        x=JuMP.@variable(m,lower_bound=0,integer=true)
        JuMP.@constraint(m,[x,x,sqrt(2.)] in JuMP.RotatedSecondOrderCone())
        JuMP.@objective(m,Min,x);JuMP.optimize!(m)
        push!(result,Dict("solver"=>solver_name,"kind"=>"MISOCP","status"=>JuMP.termination_status(m)==JuMP.MOI.OPTIMAL ? "supported_runtime_verified" : "numerical_inconclusive","termination"=>string(JuMP.termination_status(m)),"objective"=>JuMP.has_values(m) ? JuMP.objective_value(m) : nothing))
      catch e
        push!(result,Dict("solver"=>solver_name,"kind"=>"MISOCP","status"=>"solver_unavailable","error"=>sprint(showerror,e)))
      end
    end
    return result
end

function run_suite(configpath,out)
    cfg=readjson(configpath);out=newoutput(out);writejson(joinpath(out,"provenance.json"),provenance())
    cp(configpath,joinpath(out,"suite_config.json"))
    caps=capability_probe();writejson(joinpath(out,"capabilities.json"),caps)
    mosek=any(r->r["solver"]=="MOSEK" && r["status"]=="supported_runtime_verified",caps)
    pajsdp=any(r->r["solver"]=="Pajarito" && r["kind"]=="MISDP" && r["status"]=="supported_runtime_verified",caps)
    runs=Any[]
    for item in cfg["cases"]
        item=copy(item)
        for key in ("case","registry","scenarios")
            haskey(item,key) && !isabspath(item[key]) && (item[key]=normpath(joinpath(dirname(configpath),item[key])))
        end
        id=item["id"];casedir=joinpath(out,id);mkpath(casedir)
        manifestpath=joinpath(dirname(item["case"]),"case_manifest.json")
        if isfile(manifestpath)
            get(readjson(manifestpath),"case_sha256",nothing)==D.hashfile(item["case"]) || throw(ArgumentError("producer case manifest hash mismatch: $id"))
        end
        raw,data,scope=prepare(item["case"];registry=get(item,"registry",nothing),scenarios=get(item,"scenarios",nothing))
        cp(item["case"],joinpath(casedir,"case.json"));p=parameters(raw);writejson(joinpath(casedir,"parameters.json"),p)
        baseline_scale=nothing
        if get(cfg,"condition_on_baseline_LP",false)
            conditioning=solve!(build(data,FP.NoGSCR(),scope;relaxed=true),HiGHS.Optimizer)
            conditioning["termination"]=="OPTIMAL" && conditioning["objective"]>0 || throw(ArgumentError("BASE LP conditioning unavailable"))
            baseline_scale=conditioning["objective"]
            writejson(joinpath(casedir,"objective_conditioning.json"),Dict("purpose"=>"positive numerical objective scaling only; same physical objective and feasible set","factor"=>baseline_scale,"BASE_LP"=>conditioning))
        end
        for (key,filename) in (("registry","parameter_registry.csv"),("scenarios","study_scenarios.toml"));haskey(item,key) && cp(item[key],joinpath(casedir,filename));end
        isfile(joinpath(dirname(item["case"]),"case_manifest.json")) && cp(joinpath(dirname(item["case"]),"case_manifest.json"),joinpath(casedir,"case_manifest.json"))
        for relaxed in get(cfg,"relaxations",[true,false]),fid in get(cfg,"formulations",CANDIDATES)
            row=Dict{String,Any}("schema"=>SCHEMA,"case_id"=>id,"formulation"=>fid,"relaxed"=>relaxed,"exposure"=>"S_on_v1","validation_scope"=>scope,"case_sha256"=>D.hashfile(item["case"]),"registry_sha256"=>haskey(item,"registry") ? D.hashfile(item["registry"]) : nothing,"scenario_config_sha256"=>haskey(item,"scenarios") ? D.hashfile(item["scenarios"]) : nothing,"parameters"=>p,"source_producer_sha"=>get(cfg,"AP1_SHA",nothing))
            name=fid*(relaxed ? "_continuous" : "_integer");row["solution_file"]="$id/$name.json"
            if !relaxed && fid=="G0" && !pajsdp
                row["status"]="solver_unsupported";row["reason"]="no_native_MISDP; complete finite enumeration separately verified on tiny bounded fixture"
            elseif !relaxed && fid=="G3" && !mosek
                row["status"]="numerical_inconclusive";row["reason"]="selected_native_MOSEK_G3_backend_unavailable"
            else
                try
                    compile=@elapsed pm=build(data,formulation(fid,p),scope;relaxed)
                    opt=fid in ("G0","G3") ? (relaxed ? Clarabel.Optimizer : fid=="G3" ? mosek_optimizer() : pajarito_optimizer()) : HiGHS.Optimizer
                    result=solve!(pm,opt;objective_scale=fid in ("G0","G3") ? baseline_scale : nothing);merge!(row,result);row["build_wall_s"]=compile
                    row["status"]=result["termination"]=="OPTIMAL" ? "optimal" : result["termination"]=="INFEASIBLE" ? "infeasible" : "numerical_inconclusive"
                    if NativeG3Solver.is_native(opt) && get(result,"numerical_validation",nothing)!="passed"
                        row["status"]="numerical_inconclusive";row["reason"]="native_G3_original_model_validation_failed_or_unavailable"
                    end
                    if !relaxed && fid in ("G0","G3") && result["termination"]=="INFEASIBLE"
                        row["status"]="numerical_inconclusive"
                        row["reason"]="native_conic_infeasibility_requires_independent_crosscheck"
                    end
                    if row["status"]=="optimal" && row["relative_gap"] isa Real && row["relative_gap"]>1e-6
                        row["status"]="numerical_inconclusive";row["reason"]="original_currency_primal_bound_gap_exceeds_1e-6"
                    end
                    if result["primal_status"]=="FEASIBLE_POINT"
                        solution=extract(pm);writejson(joinpath(casedir,name*".json"),solution)
                    end
                catch e
                    row["status"]="execution_error";row["error"]=sprint(showerror,e,catch_backtrace())
                end
            end
            push!(runs,row);writejson(joinpath(out,"runs.json"),Dict("schema"=>SCHEMA,"runs"=>runs))
            println(id," ",name," ",row["status"]," ",get(row,"objective",""));flush(stdout)
        end
    end
    return runs
end

function reconstruct_runs(input,out)
    newoutput(out);records=Any[]
    for run in readjson(joinpath(input,"runs.json"))["runs"]
        run["status"]=="optimal" || continue
        casepath=joinpath(input,run["case_id"],"case.json")
        D.hashfile(casepath)==run["case_sha256"] || throw(ArgumentError("saved raw case hash mismatch"))
        raw=readjson(casepath);s=readjson(joinpath(input,run["solution_file"]))
        for t in sort(collect(keys(s["snapshots"]));by=x->parse(Int,x))
            rec=D.reconstruct(raw,s,parse(Int,t));rec["run"]=run;rec["snapshot_id"]=t
            rec["witness"]=get(s["snapshots"][t],"witness",nothing)
            rec["planning"]=planning(raw,s,run)
            rec["input_solution_sha256"]=D.hashfile(joinpath(input,run["solution_file"]))
            rec["conic_dual"]=get(s["snapshots"][t],"conic_dual",Dict("status"=>"not_recorded_in_earlier_attempt","dual_cone_violation"=>nothing,"complementarity_residual"=>nothing))
            rec["network_domain"]=Dict(k=>raw["paper_a_network"][k] for k in ("network_islands","reference_buses","retained_physical_buses","eliminated_physical_buses","fixed_shunts","fixed_sources_in_network"))
            push!(records,rec)
        end
    end
    writejson(joinpath(out,"matrices.json"),Dict("schema"=>SCHEMA,"records"=>records));return records
end

function evaluate_record(rec)
    p=rec["run"]["parameters"];r=rec["run"]["formulation"]=="G2_degree" ? p["r_degree"] : p["r_identity"]
    W=D.matrix(rec["run"]["formulation"]=="M2_neighbor" ? p["W_neighbor"] : p["W_full"])
    m=D.evaluate(D.matrix(rec["B"]),rec["p"],rec["alpha"];r,W,Bmin=D.matrix(p["Bmin"]),witness=rec["witness"])
    for (id,key) in (("A.Y_real","Y_real"),("A.Y_imag","Y_imag"),("A.L","L"),("A.B0","B0"),("A.B","B"),("A.S_diag","p"),("A.M","M"),("A.source_ledger","source_ledger"),("A.schur_residual","schur_residual"),("A.source_base_residual","source_base_residual"),("A.connection_violation","connection_violation"),("A.producer_B0_residual","producer_B0_residual"),("A.affine_reconstruction_residual","affine_reconstruction_residual"),("E.S_nom_v1","S_nom_v1"),("E.S_on_v1","S_on_v1"),("E.S_op_magnitude_v1","S_op_magnitude_v1"))
        m[id]=D.entry(rec[key];method="independent_raw_stamp_and_solved_blocks")
    end
    m["E.S_I_v1"]=D.undefined("blocked_missing_current_capability_voltage_convention")
    m["A.network_domain"]=D.entry(rec["network_domain"];method="raw_island_reference_inventory")
    for k in ("dual_cone_violation","complementarity_residual")
        dual=get(rec,"conic_dual",Dict("status"=>"not_recorded","dual_cone_violation"=>nothing,"complementarity_residual"=>nothing))
        m["F.$k"]=D.entry(dual[k];status=dual["status"],unit=k=="complementarity_residual" ? "scaled_objective" : "dual_cone_coordinates",method="solver_dual_cone_eigen_or_RSOC_product_and_primal_dual_inner_product")
    end
    for (k,v) in rec["planning"]
        k in ("schema","case_id","formulation","relaxed","unit") && continue
        status=v===nothing ? (k=="integrality_residual" && rec["run"]["relaxed"] ? "not_applicable_continuous_relaxation" : "not_available_from_saved_solution") : "valid"
        m["E.$k"]=D.entry(v;status,unit=occursin("MWh",k) ? "MWh" : occursin("MW",k) ? "MW" : "declared_currency_or_explicit_ledger",method="independent_raw_prices_durations_and_solved_quantities")
    end
    for k in ("model","build_wall_s","solve_wall_s","solver_time_s","relative_gap","bound","barrier_iterations","simplex_iterations","nodes","primal_status","dual_status","termination","solver")
        v=get(rec["run"],k,nothing)
        m["F.$k"]=D.entry(v;status=v===nothing ? "not_available_from_solver" : "valid",unit=endswith(k,"_s") ? "s" : "solver_metadata",method="recorded_runtime_solver_attribute")
    end
    U=D.inverse_updates(D.matrix(p["Bmin"]),D.matrix(rec["B"])-D.matrix(p["Bmin"]);order=1)
    for (k,v) in U;m["D.$k"]=D.entry(v;status=U["status"],theorem="T-C2A-025:028");end
    for k in ("woodbury_residual","E_norm_inf","spectral_radius","series_converges","order","truncation","actual_error","exact_remainder_residual","remainder_bound","trust_region_norm_valid","one_sided_safety_certified","E2_false_acceptance","E2_conservative_rejection")
        haskey(m,"D.$k") || (m["D.$k"]=D.undefined(U["status"]))
    end
    v=m["C.equivalent_strength"]["value"]
    m["C.equivalent_strength_MVA"]=D.entry(v===nothing ? nothing : rec["base_MVA"].*v;status=m["C.equivalent_strength"]["status"],unit="MVA_model_Thevenin_equivalent_not_fault_qualification")
    if haskey(U,"truncation") && rec["alpha"]>0
        estimated=D.matrix(U["truncation"])*rec["p"]
        exact=m["C.M0"]["value"]
        m["D.E2_false_acceptance"]=D.entry(exact===nothing ? nothing : maximum(estimated)<=1/rec["alpha"] && !exact;status=exact===nothing ? "undefined_inverse_domain" : "exploratory_noncertifying",unit="boolean")
        m["D.E2_conservative_rejection"]=D.entry(exact===nothing ? nothing : maximum(estimated)>1/rec["alpha"] && exact;status=exact===nothing ? "undefined_inverse_domain" : "exploratory_noncertifying",unit="boolean")
    end
    for (id,v) in m;v["unit"]=metric_unit(id,v["unit"]);end
    return m
end
function metric_unit(id,default)
    id=="A.connection_violation" && return "count_or_index"
    id in ("B.G3_edges_complete","B.G3_valid") && return "boolean"
    id in ("B.gamma","B.gamma_margin","B.participation","C.rho_diag","C.rho_Zp","C.MIIF","C.M0_slack","C.Zp","C.M1_upper_burden","D.E_norm_inf","D.spectral_radius") && return "dimensionless"
    id in ("C.M0","D.series_converges","D.trust_region_norm_valid","D.one_sided_safety_certified") && return "boolean"
    id in ("C.Z","C.Z_diag","C.inverse_min","C.M1_order_violation","D.truncation","D.actual_error","D.remainder_bound","D.woodbury_residual","D.exact_remainder_residual") && return "pu_impedance"
    id in ("C.Wp","A.S_diag","E.S_nom_v1","E.S_on_v1","E.S_op_magnitude_v1","A.exposure_roundoff_correction") && return "MW_per_system_MVA"
    id in ("A.source_ledger","E.portfolio","E.FOM","A.network_domain") && return "explicit_field_ledger"
    id in ("E.investment","E.generation","E.events","E.storage","E.no_load","E.objective_residual","F.bound") && return "declared_currency_per_represented_horizon"
    id in ("E.bounds_violation_blocks","E.integrality_residual","E.UC_transition_residual","D.order","F.nodes","F.barrier_iterations","F.simplex_iterations","B.multiplicity","B.G3_edges") && return "count_or_index"
    startswith(id,"B.G3_cone_product") && return "pu_admittance_squared"
    id in ("B.G3_q","B.G3_minimum_q","B.G3_node_budget","C.equivalent_strength","C.LOCAL_eigmin","C.M2_rows","C.M1_lower_violation") && return "pu_admittance"
    id in ("B.G3_status","D.status","F.termination","F.primal_status","F.dual_status","F.solver") && return "status"
    id=="F.relative_gap" && return "dimensionless"
    return default
end
function metric_rows(records)
    output=Any[];ap3_sha=head();seen_runs=Set{String}()
    for rec in records
        run=rec["run"]
        first_of_run=!(run["solution_file"] in seen_runs);push!(seen_runs,run["solution_file"])
        measured=evaluate_record(rec)
        domain=Dict("empirical"=>false,"passive_issues"=>rec["passive_domain_issues"],"symmetry_residual"=>measured["A.symmetry"]["value"],"positive_offdiagonal"=>measured["A.positive_offdiagonal"]["value"],"B_minimum_eigenvalue"=>minimum(measured["A.B_eigenvalues"]["value"]),"minimum_inverse_entry"=>measured["C.inverse_min"]["value"],"G3_witness_valid"=>measured["B.G3"]["value"],"range_residual"=>measured["B.range_residual"]["value"],"affine_reconstruction_residual"=>rec["affine_reconstruction_residual"])
        for (id,v) in sort(collect(measured);by=first)
            scope=metric_scope(id);scope=="case_or_horizon" && !first_of_run && continue
            residual=v["residual"]
            if residual===nothing && (occursin("residual",id)||occursin("violation",id)||id=="A.symmetry") && v["value"] isa Real && !(v["value"] isa Bool)
                residual=v["value"]
            end
            public=Dict("value_or_null"=>v["value"],"validity_status"=>v["status"],"unit"=>v["unit"],"independent_method"=>v["method"],"equation_reference"=>v["theorem"],"residual"=>residual)
            push!(output,merge(Dict("schema"=>SCHEMA,"run_id"=>run["solution_file"],"case_id"=>run["case_id"],"dataset_kind"=>run["validation_scope"],"AP1_SHA"=>run["source_producer_sha"],"AP2_SHA"=>BASE,"AP3_SHA"=>ap3_sha,"science_SHA"=>SCIENCE,"parameter_registry_sha256"=>run["registry_sha256"],"scenario_id"=>run["case_id"],"snapshot_id"=>scope=="case_or_horizon" ? "all" : rec["snapshot_id"],"scope"=>scope,"formulation_id"=>run["formulation"],"exposure_variant"=>run["exposure"],"region_or_edge"=>rec["regions"],"metric_id"=>id,"base"=>rec["base_MVA"],"tolerance"=>D.DEFAULT_TOL,"domain_predicates"=>domain,"solver_status"=>get(run,"termination",nothing)),public))
        end
    end
    return output
end
metric_scope(id)=startswith(id,"E.") && !(id in ("E.S_nom_v1","E.S_on_v1","E.S_op_magnitude_v1","E.S_I_v1")) || startswith(id,"F.") && !(id in ("F.dual_cone_violation","F.complementarity_residual")) ? "case_or_horizon" : "snapshot_region_or_edge"
function write_metrics(input,out)
    newoutput(out);records=readjson(joinpath(input,"matrices.json"))["records"];m=metric_rows(records)
    open(joinpath(out,"metrics.json"),"w") do io
        JSON.print(io,Dict("schema"=>SCHEMA,"metrics"=>m))
    end
    flat=[(schema=SCHEMA,run_id=x["run_id"],case_id=x["case_id"],dataset_kind=x["dataset_kind"],parameter_registry_sha256=x["parameter_registry_sha256"],AP1_SHA=x["AP1_SHA"],AP2_SHA=x["AP2_SHA"],AP3_SHA=x["AP3_SHA"],science_SHA=x["science_SHA"],formulation_id=x["formulation_id"],exposure_variant=x["exposure_variant"],snapshot_id=x["snapshot_id"],scenario_id=x["scenario_id"],scope=x["scope"],region_or_edge_json=JSON.json(x["region_or_edge"]),metric_id=x["metric_id"],value_or_null_json=JSON.json(x["value_or_null"]),unit=x["unit"],base=x["base"],validity_status=x["validity_status"],domain_predicates_json=JSON.json(x["domain_predicates"]),equation_reference=x["equation_reference"],independent_method=x["independent_method"],tolerance=x["tolerance"],residual=x["residual"],solver_status=x["solver_status"]) for x in m]
    CSV.write(joinpath(out,"metrics.csv"),flat;transform=(col,value)->value===nothing ? missing : value)
    registry=Dict{String,Any}();typed=Set{String}()
    for x in m
        x["metric_id"] in typed && continue
        haskey(registry,x["metric_id"]) && x["value_or_null"]===nothing && continue
        x["value_or_null"]===nothing || push!(typed,x["metric_id"])
        registry[x["metric_id"]]=merge(Dict(k=>x[k] for k in ("unit","independent_method","equation_reference","tolerance")),Dict("shape"=>x["value_or_null"] isa Vector ? "vector_or_matrix_or_ledger" : x["value_or_null"] isa AbstractDict ? "record" : "scalar_or_status","scope"=>metric_scope(x["metric_id"]),"formula"=>metric_formula(x["metric_id"]),"domain"=>"per_record_status_and_frozen_theorem_assumptions"))
    end
    writejson(joinpath(out,"metric_registry.json"),registry);return m
end
function metric_formula(id)
    explicit=Dict("B.gamma"=>"lambda_min(Sa^-1/2*(Baa-Baz*Bzz_dagger*Bza)*Sa^-1/2), with PSD and range tests", "B.G0_eigmin"=>"eigmin(B-alpha*Diagonal(p))","B.G1_rows"=>"(B-alpha*Diagonal(p))*ones(n)","B.G2_rows"=>"(B-alpha*Diagonal(p))*r_offline","C.Zp"=>"B\\p","C.rho_diag"=>"1/(Zii*pi), positive denominator only","C.rho_Zp"=>"1/(B\\p)i, positive denominator only","C.M0_slack"=>"1/alpha-B\\p, PD inverse-positive B, alpha>0","C.M2_rows"=>"B*1-alpha*W*p","C.M1_upper_burden"=>"(Bmin\\I)*p, enforced B>=Bmin","A.symmetry"=>"norm(B-transpose(B),Inf)","A.affine_reconstruction_residual"=>"max(norm(Braw-Baff),norm(Mraw-Maff),norm(praw-paff))","B.G3_cone_product_slacks"=>"qij*qji-mij^2","B.G3_node_budget"=>"mii-sum_j(qij)","D.remainder_bound"=>"norm(E)^(m+1)*norm(inv(A))/(1-norm(E)), norm(E)<1")
    haskey(explicit,id) && return explicit[id]
    exact=Dict(
        "A.Y_real"=>"Re(Y) from reciprocal physical series and terminal charging/shunt stamps",
        "A.Y_imag"=>"Im(Y) from reciprocal physical series and terminal charging/shunt stamps",
        "A.L"=>"-Im(Y)","A.B0"=>"Lrr-Lre*(Lee\\Ler)","A.B"=>"B0+Diagonal(b_fix+sum(mu_str*n_on*native_MVA/(base*x_native)))",
        "A.S_diag"=>"sum_GFL(mu_fl*P_block_MW*n_on/base_MVA) by region","A.M"=>"B-alpha*Diagonal(p)",
        "A.B_eigenvalues"=>"eigvals(Symmetric(B))","A.M_eigenvalues"=>"eigvals(Symmetric(B-alpha*Diagonal(p)))",
        "A.condition"=>"cond(B,2)","A.rank"=>"count(abs(lambda_B)>scaled_tolerance)","A.nullity"=>"count(abs(lambda_B)<=scaled_tolerance)",
        "A.inertia"=>"counts(lambda_B<-tau,abs(lambda_B)<=tau,lambda_B>tau)","A.positive_offdiagonal"=>"max(0,max_{i!=j} Bij)","A.Z_class"=>"max_{i!=j} Bij<=tolerance",
        "A.connection_violation"=>"max(0,n_on-a_conn*n_inst,-n_on)","A.exposure_roundoff_correction"=>"max(0,-min(raw_p)); only negative solver roundoff <= tolerance projected to zero",
        "A.producer_B0_residual"=>"norm(B0_independent-B0_producer,Inf)","A.schur_residual"=>"norm(Lee*(Lee\\Ler)-Ler,Inf)",
        "A.source_base_residual"=>"max(abs(b_block_declared-native_MVA/(base_MVA*x_native)))",
        "A.source_ledger"=>"per-asset independent installed/online/source/exposure/MW/MVA/MWh quantities","A.network_domain"=>"raw islands, references, retained/eliminated buses and fixed-shunt/source inventories",
        "B.eigen_residual"=>"norm(B*V-Diagonal(p)*V*gamma,Inf)","B.eigenspace"=>"positive-support scaled eigenvectors lifted through exact zero-support Schur solve",
        "B.G0"=>"eigmin(M)>=-scaled_tolerance","B.G1"=>"min(M*ones(n))>=-scaled_tolerance","B.G2"=>"min(M*r_offline)>=-scaled_tolerance",
        "B.G1_binding"=>"abs.(M*ones(n))<=scaled_tolerance","B.G2_binding"=>"abs.(M*r_offline)<=scaled_tolerance","B.G1_false_rejection"=>"G0 && !G1",
        "B.G3"=>"complete signed edges && nonnegative q/cone products/node residues && exact reconstruction within tolerance",
        "B.G3_valid"=>"complete signed edges && nonnegative q/cone products/node residues && reconstruction within tolerance",
        "B.G3_edges"=>"all exact nonzero undirected pairs (i,j), i<j","B.G3_edges_complete"=>"unique witness edge set equals all nonzero offdiagonal pairs",
        "B.G3_q"=>"both oriented endpoint allocations qij,qji for every signed edge","B.G3_minimum_q"=>"minimum endpoint allocation, undefined for no edges",
        "B.G3_reconstruction_residual"=>"norm(M-sum(embedded edge Q)-Diagonal(node_residue),Inf)","B.G3_status"=>"edge/witness domain and verification status",
        "B.gamma_margin"=>"smallest finite generalized eigenvalue minus alpha","B.multiplicity"=>"count(abs(finite_eigenvalue-gamma)<=scaled_tolerance)",
        "B.participation"=>"row sums of squared critical lifted modes divided by total squared mode magnitude","B.range_residual"=>"norm(Bzz*(Bzz_dagger*Bza)-Bza,Inf)",
        "C.Z"=>"B\\I, only on PD sufficiently conditioned B","C.Z_diag"=>"diag(B\\I)","C.inverse_min"=>"minimum(B\\I)","C.solve_residual"=>"norm(B*(B\\p)-p,Inf)",
        "C.equivalent_strength"=>"1/Zii","C.equivalent_strength_MVA"=>"base_MVA/Zii (model equivalent, not fault-qualified)",
        "C.M0"=>"max(B\\p)<=1/alpha, requiring PD/inverse-positive B and alpha>0","C.MIIF"=>"Zij/Zii with model Thevenin normalization",
        "C.M1"=>"B>=Bmin && inv(B)<=inv(Bmin) && inv(Bmin)*p<=1/alpha",
        "C.M1_lower_violation"=>"max(0,max(Bmin-B))","C.M1_order_violation"=>"max(0,max(inv(B)-inv(Bmin)))",
        "C.M2"=>"min(B*ones(n)-alpha*W*p)>=-scaled_tolerance","C.Wp"=>"W_offline*p",
        "C.LOCAL_eigmin"=>"[eigmin(B-alpha*pi*ei*ei') for each i]","C.LOCAL"=>"all local rank-one PSD tests pass",
        "D.woodbury_residual"=>"norm(inv(A)-inv(A)*Delta*(I+inv(A)*Delta)^-1*inv(A)-inv(A+Delta),Inf)",
        "D.E_norm_inf"=>"opnorm(A^-1*Delta,Inf)","D.spectral_radius"=>"max(abs(eigvals(A^-1*Delta)))","D.series_converges"=>"spectral_radius(E)<1",
        "D.order"=>"declared truncation order m","D.truncation"=>"sum_{k=0}^m (-A^-1*Delta)^k * A^-1",
        "D.actual_error"=>"opnorm(truncation-inv(A+Delta),Inf)","D.exact_remainder_residual"=>"norm(inv(A+Delta)-truncation-(-E)^(m+1)*(I+E)^-1*A^-1,Inf)",
        "D.trust_region_norm_valid"=>"opnorm(E,Inf)<1","D.one_sided_safety_certified"=>"false: diagnostic does not enforce a one-sided planning margin",
        "D.E2_false_acceptance"=>"estimated row burden passes while exact M0 fails","D.E2_conservative_rejection"=>"estimated row burden fails while exact M0 passes","D.status"=>"exploratory_noncertifying or explicit inverse-domain failure",
        "E.investment"=>"sum(price_inv_per_MW*P_block*(n_inst-n0)*investment_fraction), once",
        "E.generation"=>"sum(delta_t*repetitions*probability*marginal_price*PG_MW)","E.storage"=>"sum(dispatch_weight*storage_price*AC_discharge_MW)",
        "E.events"=>"sum(event_repetitions*probability*P_block*(startup_price*SU+shutdown_price*SD)); no delta_t",
        "E.no_load"=>"sum(dispatch_weight*declared constant generation-cost term)","E.FOM"=>"separate amount not identifiable; declared annualized price attribution retained",
        "E.objective_residual"=>"abs(reported_objective-investment-generation-storage-events-no_load)",
        "E.portfolio"=>"per-asset n0,n_inst,n_new,MW,MVA,MWh,source class,carrier,region",
        "E.curtailment_MWh"=>"sum(dispatch_weight*max(0,P_block*n_on*a_res-PG_MW))",
        "E.power_balance_MW"=>"max_bus_snapshot abs(outgoing flows-generation+storage net consumption+load)",
        "E.SOC_residual_MWh"=>"max abs(E_t-E_prev-delta_t*(eta_charge*charge-discharge/eta_discharge))",
        "E.terminal_residual_MWh"=>"max abs(final energy-declared initial energy)","E.thermal_violation_MW"=>"max(0,abs(branch flow)-rating)",
        "E.UC_transition_residual"=>"max abs(n_on_t-n_on_prev-SU+SD)","E.bounds_violation_blocks"=>"max(0,n0-n_inst,n_inst-nmax,n_on-a_conn*n_inst,-n_on)",
        "E.integrality_residual"=>"max abs(block/event count-round(count)), undefined in continuous relaxation",
        "E.S_nom_v1"=>"sum_GFL mu_fl*P_block*n_inst/base","E.S_on_v1"=>"sum_GFL mu_fl*P_block*n_on/base",
        "E.S_op_magnitude_v1"=>"sum_GFL mu_fl*abs(AC_discharge_or_generation-AC_charge)/base","E.S_I_v1"=>"undefined without current capability and voltage normalization",
        "F.model"=>"actual JuMP variable/integer/typed-constraint counts","F.dual_cone_violation"=>"max PSD-dual negative eigenvalue or rotated-dual cone product/sign violation",
        "F.complementarity_residual"=>"abs(<primal cone point,dual cone point>) in scaled objective units")
    haskey(exact,id) && return exact[id]
    endswith(id,"_external") && return "not_comparable: source-specific fault/compensation/denominator convention is not supplied"
    startswith(id,"F.") && return "actual runtime attribute "*id[3:end]*"; unsupported values explicitly null"
    startswith(id,"E.") && return "raw quantity/price/duration/event ledger; planning() is executable definition; event weight excludes delta_t"
    startswith(id,"F.") && return "runtime solver/model attribute; missing values are not replaced"
    startswith(id,"A.") && return "independent raw physical stamp/reduction or matrix-class diagnostic in reconstruct()/evaluate()"
    startswith(id,"D.") && return "T025 Woodbury or T027/T028 induced-infinity-norm truncation/remainder in inverse_updates(); no one-sided certification"
    return "independent evaluate()/verify_g3() definition; prerequisite status included; theorem T001-T028"
end
function certificates(input,out)
    newoutput(out);result=Any[]
    for rec in readjson(joinpath(input,"matrices.json"))["records"]
        m=evaluate_record(rec)
        getv(k)=haskey(m,k) ? m[k]["value"] : nothing
        push!(result,Dict("case_id"=>rec["run"]["case_id"],"formulation"=>rec["run"]["formulation"],"relaxed"=>rec["run"]["relaxed"],"snapshot"=>rec["snapshot_id"],"P001"=>getv("A.symmetry"),"P002"=>getv("A.positive_offdiagonal"),"P003"=>getv("A.B_eigenvalues"),"P004"=>getv("C.inverse_min"),"P005"=>getv("B.G1_rows"),"P006"=>rec["affine_reconstruction_residual"],"P007"=>minimum(rec["p"]),"P008"=>getv("B.G3_valid"),"P009"=>getv("B.range_residual"),"P010"=>getv("B.G0_eigmin"),"G0"=>getv("B.G0"),"G1"=>getv("B.G1"),"G2"=>getv("B.G2"),"M0"=>getv("C.M0"),"M1"=>getv("C.M1"),"M2"=>getv("C.M2"),"LOCAL"=>getv("C.LOCAL"),"scoped_worker_verification"=>true,"independent_review_accepted"=>false))
    end
    writejson(joinpath(out,"certificates.json"),Dict("schema"=>SCHEMA,"records"=>result));return result
end

function planning(raw,solution,run)
    investment=0.;generation=0.;storage=0.;event=0.;noload=0.;soc=0.;terminal=0.;power=0.;thermal=0.;uc=0.;bounds=0.;curtail=0.;integer=0.;ledger=Any[]
    base=raw["baseMVA"];fraction=get(raw,"investment_period_fraction",1.)
    times=sort(collect(keys(raw["nw"]));by=x->parse(Int,x));sn1=raw["nw"][first(times)]
    for (kt,t) in enumerate(times)
        sn=raw["nw"][t];ss=solution["snapshots"][t];temp=raw["paper_a_temporal"][parse(Int,t)]
        dt=temp["delta_t_h"];dw=dt*temp["representative_repetitions"]*temp["scenario_probability"];ew=temp["event_repetitions"]*temp["scenario_probability"]
        balance=Dict(string(id)=>0. for id in keys(sn["bus"]))
        for (id,l) in sn["load"];balance[string(l["load_bus"])]+=l["pd"];end
        for (id,br) in sn["branch"]
            get(br,"br_status",1)==0 && continue
            f,to=ss["branch_flows_MW"][id];balance[string(br["f_bus"])]+=f;balance[string(br["t_bus"])]+=to
            thermal=max(thermal,max(0.,abs(f)-get(br,"rate_a",Inf),abs(to)-get(br,"rate_a",Inf)))
        end
        for table in ("gen","storage","ne_storage"),(id,d) in get(sn,table,Dict())
            haskey(d,"source_class") || continue
            v=ss["assets"]["$table:$id"];inst=v["installed"];on=v["online"];P=d["p_block_max_MW"]
            bounds=max(bounds,max(0.,d["n0"]-inst,inst-d["nmax"],on-d["a_conn"]*inst,-on))
            integer=max(integer,abs(inst-round(inst)),abs(on-round(on)),abs(v["startup"]-round(v["startup"])),abs(v["shutdown"]-round(v["shutdown"])))
            if kt==1
                investment+=d["cost_inv_per_mw"]*P*(inst-d["n0"])*fraction
                push!(ledger,Dict("asset"=>d["name"],"carrier"=>d["carrier"],"region"=>d["region_id"],"source_class"=>d["source_class"],"initial_blocks"=>d["n0"],"installed_blocks"=>inst,"new_blocks"=>inst-d["n0"],"new_MW"=>P*(inst-d["n0"]),"new_MVA"=>d["S_block_MVA"]*(inst-d["n0"]),"new_MWh"=>table=="gen" ? nothing : d["e_block"]*(inst-d["n0"])))
            end
            event+=P*ew*(d["startup_cost_per_mw"]*v["startup"]+d["shutdown_cost_per_mw"]*v["shutdown"])
            prev=kt==1 ? d["na0"] : solution["snapshots"][times[kt-1]]["assets"]["$table:$id"]["online"]
            if d["source_class"]=="SYN" && table=="gen"
                uc=max(uc,abs(on-prev-v["startup"]+v["shutdown"]))
            end
            if table=="gen"
                generation+=dw*d["marginal_cost"]*v["dispatch_MW"]
                noload+=dw*get(d,"cost",[0.,0.])[end]
                balance[string(d["gen_bus"]) ]-=v["dispatch_MW"]
                if d["source_class"]=="GFL";curtail+=dw*max(0.,P*on*d["a_res"]-v["dispatch_MW"]);end
            else
                storage+=dw*d["marginal_cost"]*v["dispatch_MW"]
                balance[string(d["storage_bus"])]+=v["charge_MW"]-v["dispatch_MW"]
                prevE=kt==1 ? d["energy"] : solution["snapshots"][times[kt-1]]["assets"]["$table:$id"]["energy_MWh"]
                soc=max(soc,abs(v["energy_MWh"]-prevE-dt*(d["charge_efficiency"]*v["charge_MW"]-v["dispatch_MW"]/d["discharge_efficiency"])))
                kt==length(times) && (terminal=max(terminal,abs(v["energy_MWh"]-sn1[table][id]["energy"])))
            end
        end
        power=max(power,maximum(abs.(collect(values(balance)))))
    end
    return Dict("schema"=>SCHEMA,"case_id"=>run["case_id"],"formulation"=>run["formulation"],"relaxed"=>run["relaxed"],"unit"=>"declared_input_currency_per_represented_horizon","investment"=>investment,"generation"=>generation,"storage"=>storage,"events"=>event,"no_load"=>noload,"FOM"=>Dict("status"=>"included_in_registered_annualized_price_when_declared","separately_identifiable"=>false),"objective_residual"=>abs(run["objective"]-investment-generation-storage-event-noload),"power_balance_MW"=>power,"thermal_violation_MW"=>thermal,"SOC_residual_MWh"=>soc,"terminal_residual_MWh"=>terminal,"UC_transition_residual"=>uc,"bounds_violation_blocks"=>bounds,"integrality_residual"=>run["relaxed"] ? nothing : integer,"curtailment_MWh"=>curtail,"portfolio"=>ledger)
end
function assess(input,out)
    newoutput(out);a=Any[]
    for run in readjson(joinpath(input,"runs.json"))["runs"]
        run["status"]=="optimal" || continue
        push!(a,planning(readjson(joinpath(input,run["case_id"],"case.json")),readjson(joinpath(input,run["solution_file"])),run))
    end
    writejson(joinpath(out,"planning.json"),Dict("schema"=>SCHEMA,"records"=>a));return a
end
function compare(input,out)
    newoutput(out);runs=readjson(joinpath(input,"runs.json"))["runs"];a=Any[]
    function effective_bound(r)
        get(r,"bound_certification",nothing)=="numerical_only_not_rigorous_currency_bound" && return nothing
        b=get(r,"bound",nothing);b isa Real && isfinite(b) && return b
        base=filter(x->x["case_id"]==r["case_id"]&&x["relaxed"]==r["relaxed"]&&x["formulation"]=="BASE"&&x["status"]=="optimal",runs)
        isempty(base) && return nothing
        b=get(only(base),"bound",nothing);return b isa Real && isfinite(b) ? b : nothing
    end
    gapok(r)=get(r,"objective",nothing) isa Real && effective_bound(r)!==nothing && abs(r["objective"]-effective_bound(r))/max(1.,abs(r["objective"]))<=1e-6
    for run in runs
        reference=filter(x->x["case_id"]==run["case_id"]&&x["relaxed"]==run["relaxed"]&&x["formulation"]=="G0"&&x["status"]=="optimal"&&gapok(x),runs)
        ref=isempty(reference) ? nothing : only(reference)
        row=Dict{String,Any}("case_id"=>run["case_id"],"formulation"=>run["formulation"],"relaxed"=>run["relaxed"],"status"=>run["status"],"objective"=>get(run,"objective",nothing),"reference"=>"G0_same_case_and_relaxation","absolute_delta"=>ref!==nothing&&run["status"]=="optimal" ? run["objective"]-ref["objective"] : nothing,"relative_delta"=>ref!==nothing&&run["status"]=="optimal"&&ref["objective"]!=0 ? (run["objective"]-ref["objective"])/abs(ref["objective"]) : nothing,"denominator"=>"abs(G0_objective)","same_input_hash"=>ref===nothing ? nothing : ref["case_sha256"]==run["case_sha256"],"portfolio_identity_required"=>false)
        row["original_currency_bound_gap_pass"]=gapok(run)
        row["effective_global_lower_bound"]=effective_bound(run)
        row["bound_source"]=get(run,"bound",nothing) isa Real ? "native_solver" : "BASE_same_scope_relaxation"
        if haskey(run,"bound_certification")
            row["bound_certification"]=run["bound_certification"]
            row["bound_source"]="unaccepted_native_numerical_bound"
        end
        if run["status"]=="optimal" && !gapok(run)
            row["status"]="numerical_inconclusive";row["reason"]="original_currency_gap_not_certified";row["absolute_delta"]=nothing;row["relative_delta"]=nothing
        end
        if run["status"]=="optimal"
            raw=readjson(joinpath(input,run["case_id"],"case.json"));s=readjson(joinpath(input,run["solution_file"]))
            mets=[evaluate_record(merge(D.reconstruct(raw,s,parse(Int,t)),Dict("run"=>run,"snapshot_id"=>t,"witness"=>get(s["snapshots"][t],"witness",nothing),"planning"=>planning(raw,s,run),"network_domain"=>Dict()))) for t in keys(s["snapshots"])]
            row["cross_G0"]=all(m->m["B.G0"]["value"]===true,mets)
            row["cross_G3"]=all(m->m["B.G3"]["value"]===true,mets)
            row["cross_G1"]=all(m->m["B.G1"]["value"]===true,mets)
            row["M0_failed_states"]=count(m->m["C.M0"]["value"]===false,mets)
            row["G1_false_rejected_states"]=count(m->m["B.G1_false_rejection"]["value"]===true,mets)
            row["worst_M_eigenvalue"]=minimum(m["B.G0_eigmin"]["value"] for m in mets)
            row["worst_G1_row"]=minimum(minimum(m["B.G1_rows"]["value"]) for m in mets)
            row["G1_binding_frequency_by_region"]=vec(sum(reduce(hcat,[Float64.(m["B.G1_binding"]["value"]) for m in mets]);dims=2))./length(mets)
            if ref!==nothing
                rs=readjson(joinpath(input,ref["solution_file"]));firstt=first(keys(s["snapshots"]))
                row["portfolio_delta_blocks"]=Dict(k=>v["installed"]-rs["snapshots"][firstt]["assets"][k]["installed"] for (k,v) in s["snapshots"][firstt]["assets"])
            end
        end
        push!(a,row)
    end
    writejson(joinpath(out,"comparisons.json"),Dict("schema"=>SCHEMA,"records"=>a))
    auditpath=joinpath(dirname(input),"integer_bound_audit.json")
    if isfile(auditpath)
        certificate_rows=Any[]
        for cert in readjson(auditpath)["records"],run in runs
            run["case_id"]==cert["case_id"] && !run["relaxed"] || continue
            get(cert,"case_sha256",nothing)==run["case_sha256"] || throw(ArgumentError("integer reference case hash mismatch"))
            obj=get(run,"objective",nothing)
            available=get(run,"primal_status",nothing)=="FEASIBLE_POINT" && obj isa Real && cert["integer_optimum_certified"]
            lo=cert["shared_lower_bound"];hi=cert["shared_G0_G3_upper_bound"]
            push!(certificate_rows,Dict("case_id"=>run["case_id"],"formulation"=>run["formulation"],"native_status"=>run["status"],"native_termination"=>get(run,"termination",nothing),"candidate_objective"=>obj,"reference_lower"=>lo,"reference_upper"=>hi,"reference_gap"=>cert["original_currency_relative_gap"],"reference_certified"=>cert["integer_optimum_certified"],"additional_cost_interval"=>available ? [obj-hi,obj-lo] : nothing,"relative_to_reference_upper"=>available && hi!=0 ? (obj-hi)/abs(hi) : nothing,"unit"=>"declared_currency_per_represented_horizon","reference_method"=>cert["method"]))
        end
        writejson(joinpath(out,"integer_reference_comparisons.json"),Dict("schema"=>SCHEMA,"records"=>certificate_rows))
    end
    return a
end

"""Complete finite integer reference. Every bounded strengthening assignment
is fixed and its remaining continuous SDP/SOCP solved; no sampling or pruning.
M0 is exact here because fixed decisions fully determine B and p.
"""
function enumerate_tiny(out)
    newoutput(out);nmax=3;step=.5;p=[.25,2/3];alpha=1.;B0=[.5 -.5;-.5 .5];cost=[1.,3.];records=Any[];best=Dict{String,Any}()
    for fid in ("G0","G3","M0"),i in 0:nmax,j in 0:nmax
        B=B0+Diagonal(step.*[i,j]);row=Dict{String,Any}("formulation"=>fid,"assignment"=>[i,j],"cost"=>dot(cost,[i,j]),"B"=>D.rows(B),"p"=>p)
        if fid=="M0"
            met=D.evaluate(B,p,alpha);ok=met["C.M0"]["value"]===true
            row["status"]=ok ? "feasible_exact_inverse" : "infeasible_or_inverse_domain_invalid";row["feasible"]=ok
        else
            m=JuMP.Model(Clarabel.Optimizer);JuMP.set_silent(m)
            FP.add_paper_a_constraints!(m,B,p,B-alpha*Diagonal(p),fid=="G0" ? FP.ExactPSDGSCR() : FP.ExactEdgeSOCGSCR();alpha)
            JuMP.@objective(m,Min,0.);JuMP.optimize!(m)
            row["status"]=string(JuMP.termination_status(m));row["feasible"]=JuMP.termination_status(m)==JuMP.MOI.OPTIMAL
            row["minimum_M_eigenvalue"]=eigmin(Symmetric(B-alpha*Diagonal(p)))
        end
        push!(records,row)
    end
    for fid in ("G0","G3","M0")
        rr=filter(x->x["formulation"]==fid,records);feas=filter(x->x["feasible"],rr)
        conclusive=all(x->x["status"] in ("OPTIMAL","INFEASIBLE","feasible_exact_inverse","infeasible_or_inverse_domain_invalid"),rr)
        best[fid]=Dict("expected_assignments"=>(nmax+1)^2,"executed_assignments"=>length(rr),"complete"=>length(rr)==(nmax+1)^2&&conclusive,"optimum"=>isempty(feas) ? nothing : minimum(x["cost"] for x in feas),"optimal_assignments"=>isempty(feas) ? [] : [x["assignment"] for x in feas if x["cost"]==minimum(y["cost"] for y in feas)])
    end
    writejson(joinpath(out,"integer_enumeration.json"),Dict("schema"=>SCHEMA,"scope"=>"tiny_2_region_integer_strengthening_reference_not_full_UC","bounds"=>[0,nmax],"step_pu"=>step,"cost_per_block"=>cost,"alpha"=>alpha,"records"=>records,"certificate"=>best));return best
end
function benchmark(configpath,out)
    cfg=readjson(configpath);newoutput(out);a=Any[]
    for n in get(cfg,"sizes",[2,4,8,16]),fid in ("G0","G3")
        B=zeros(n,n)
        for i in 1:n-1;B[i,i]+=1;B[i+1,i+1]+=1;B[i,i+1]=-1;B[i+1,i]=-1;end
        m=JuMP.Model(Clarabel.Optimizer);JuMP.set_silent(m)
        wall=@elapsed begin
            x=JuMP.@variable(m,[1:n],lower_bound=0.);BB=B+Diagonal(x);p=fill(.1,n)
            FP.add_paper_a_constraints!(m,BB,p,BB-Diagonal(p),fid=="G0" ? FP.ExactPSDGSCR() : FP.ExactEdgeSOCGSCR();alpha=1.)
            JuMP.@objective(m,Min,sum(x))
        end
        solve=@timed JuMP.optimize!(m)
        push!(a,Dict("n"=>n,"edges"=>n-1,"formulation"=>fid,"build_wall_s"=>wall,"solve_wall_s"=>solve.time,"allocated_bytes"=>solve.bytes,"peak_memory_bytes"=>nothing,"termination"=>string(JuMP.termination_status(m)),"objective"=>JuMP.has_values(m) ? JuMP.objective_value(m) : nothing,"model"=>modelstats(m)))
    end
    writejson(joinpath(out,"benchmark.json"),Dict("schema"=>SCHEMA,"seed"=>SEED,"records"=>a));return a
end
function export_evidence(input,out)
    newoutput(out);index=Any[]
    for (root,dirs,files) in walkdir(input),file in sort(files)
        path=joinpath(root,file);push!(index,Dict("path"=>relpath(path,input),"bytes"=>filesize(path),"sha256"=>D.hashfile(path)))
    end
    writejson(joinpath(out,"evidence_index.json"),Dict("schema"=>SCHEMA,"files"=>index,"provenance"=>provenance()))
    CSV.write(joinpath(out,"evidence_index.csv"),[(path=x["path"],bytes=x["bytes"],sha256=x["sha256"]) for x in index])
    open(joinpath(out,"evidence_report.md"),"w") do io
        println(io,"# Paper A AP3 — Evidenzexport\n")
        println(io,"Schema: $SCHEMA. Indizierte Dateien: $(length(index)); Rohbytes: $(sum(x["bytes"] for x in index)). Der Index prüft die gespeicherten Bytes; er ist keine unabhängige wissenschaftliche Abnahme.\n")
        println(io,"Empirische Freigabe=false; A3_closed=false; AP4_ready=false. Native Solverstatus und separate Referenzintervalle bleiben getrennt.\n")
        summary=joinpath(input,"validation_summary.json")
        if isfile(summary)
            s=readjson(summary)
            println(io,"| Aus gespeicherten Ergebnissen | Wert |\n|---|---:|")
            for key in ("snapshot_records","planning_records","metric_ids","metrics_count","integer_reference_pass","integer_reference_total","G0_G3_continuous_max_relative_objective_difference")
                haskey(s,key) && println(io,"| $key | $(s[key]) |")
            end
            println(io)
        end
        println(io,"| Artefakt | Relativer Pfad |\n|---|---|")
        for rel in ("README.md","parametric_comparison.md","validation_summary.json","blocker_register.json","metric_archive_verification.json","accepted_suite/runs.json","metrics_final/metric_registry.json","comparisons_final/integer_reference_comparisons.json","planning_final/planning.json","plots_final/cost_conservatism.png")
            path=joinpath(input,rel);isfile(path) || continue
            link=replace(relpath(path,out),'\\'=>'/')
            println(io,"| $rel | [$rel]($link) |")
        end
        println(io,"\nGroße metrics.json/metrics.csv vor vollständiger Prüfung aus den benachbarten ZIPs extrahieren. Archivinhalt und Rohdatei sind separat SHA256-geprüft. Die neu erzeugten Exportdateien selbst werden nicht selbstreferenziell indiziert.")
    end
    return index
end
function main(args)
    length(args)==3 || throw(ArgumentError("usage: ap3.jl ACTION INPUT_PATH NEW_OUTPUT_DIRECTORY"))
    action,input,out=args
    actions=Dict("run_formulation_suite"=>run_suite,"reconstruct_strength_matrices"=>reconstruct_runs,"evaluate_strength_metrics"=>write_metrics,"verify_certificates"=>certificates,"compare_formulations"=>compare,"assess_planning_results"=>assess,"benchmark_conic_scaling"=>benchmark,"export_paper_a_evidence"=>export_evidence)
    haskey(actions,action) || throw(ArgumentError("unknown action $action"))
    ispath(input) || throw(ArgumentError("missing input $input"))
    actions[action](abspath(input),abspath(out))
    isfile(joinpath(out,"provenance.json")) || writejson(joinpath(out,"provenance.json"),provenance())
end
end
