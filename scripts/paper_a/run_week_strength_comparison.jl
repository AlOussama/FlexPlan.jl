# Reuse the accepted physical/UC/cost workflow; only the strength selector and
# shared added-GFL attachment differ. Original cases and G1 results stay frozen.
using SHA, JSON, Dates
length(ARGS)==5 || error("usage: OUTPUT_ROOT SCIENCE_CASE G0|G2|G3|M1|M2 relaxed|integer prepare|profile|solve|admit_solve")
const root,science=abspath.(ARGS[1:2])
const criterion,mode,phase=ARGS[3:5]
const native_backend=Symbol(get(ENV,"PAPER_A_STRENGTH_BACKEND","gurobi"))
const contract_path=get(ENV,"PAPER_A_WEEK_CONTRACT","")
const reviewed_week=!isempty(contract_path)
criterion in ("G0","G2","G3","M1","M2") && mode in ("relaxed","integer") && phase in ("prepare","profile","solve","admit_solve") || error("Unsupported comparison")
native_backend in (:gurobi,:mosek) || error("Unsupported backend")
criterion=="G0" && (native_backend!=:mosek || mode!="relaxed") && error("G0 requires continuous MOSEK SDP")
!reviewed_week && (criterion in ("G0","M1","M2") || phase=="admit_solve") && error("Reviewed week contract required")
startswith(root,"E:") || error("E: output required")
const parent_study="E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_FIVE_WEEKS_RE50_20261115_01"
const source_case="E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_840H_RE50_GFM_FROZEN_E_20261117_01/AP2_SOURCE_VARIANTS/week_8/derived_case.json"
const source_sha="c03dfc3cd78d68e0aeb8fb6875a3875e71db5d2c2efd8d680ba1904f95a79cfe"
const source_profile="13a242fc5f3e2f8f651d6d0dec2ec8d5cb8fb41e8c543b2daf03beb7879c26c2"
const qref_path="E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE60_70_FROZEN_E_20261118_01/independent_QREF_result_selection.json"
const qref_sha="971c4bac09ed5f859a7a4a07d378a4fa8a8d5314f12284a1ef57290be7f06b34"
const pin=ENV["PAPER_A_PROXY_CONSUMER_COMMIT"]
const budget=parse(Float64,get(ENV,"PAPER_A_STRENGTH_SECONDS","7200"))
0<budget<=7200 || error("Maximum two hours per optimization")
mkpath(root)
function replace_once(s,a,b)
    length(findall(a,s))==1 || error("Existing workflow anchor changed: $a")
    replace(s,a=>b;count=1)
end
const common_path=joinpath(parent_study,"run_common.jl")
common=read(common_path,String)
bytes2hex(sha256(common))=="40eb3f9d55289f031ba2f6ed965b9bb4beee5a5b7dda408cd4b8390cab435d9b" || error("Common workflow changed")
common=replace(common,"\r\n"=>"\n")
common=replace_once(common,"const consumer_pin = \"4a78a9b6afb8e1a192c169073d43fffd8acc7330\"","const consumer_pin = \"$pin\"")
common=replace_once(common,"const annual_factor = 8760/840","const annual_factor = 8760/168")
common=replace_once(common,"data = FP.parse_file(case_path; expected_case_sha256=expected_case_sha)","data = comparison_case()")
common=replace_once(common,"data[\"paper_a_extension\"][\"full37_specification\"] == declared","normalized_parent_spec(data) == declared")
common=replace_once(common,"    f = FP.GershgorinGSCR()","    f = selected_formulation(data)")
common=replace_once(common,"pm;objective=false,template,relax_block_variables=false","pm;objective=false,template,defer_paper_a_strength=true,relax_block_variables=false")
old=join(["    for ((t,region),terms) in coeffs",
          "        row=fp.con(pm,t)[:gscr_gershgorin_sufficient][region]",
          "        for (coef,v) in terms",
          "            JuMP.set_normalized_coefficient(row,v,coef)",
          "        end","    end"],"\n")
common=replace_once(common,old,"""    extra=Dict(t=>Dict(region=>JuMP.AffExpr(0.) for region in fp.ref(pm,t,:paper_a_regional).regions) for t in 1:168)
    for p in projects,t in 1:168
        region=fp.ref(pm,t,:paper_a_regional).bus_to_region[p.bus]
        JuMP.add_to_expression!(extra[t][region],p.availability[t]/base,p.installed)
    end
    FP.finalize_paper_a_strength!(pm;additional_gfl=extra)""")
common=replace_once(common,"gscr_rows=[row for t in 1:168 for row in values(fp.con(pm,t)[:gscr_gershgorin_sufficient])]",
    "gscr_rows=[row for t in 1:168 for row in certificate_rows(pm.ext[:paper_a_certificates][t])]")
common=replace_once(common,"length(gscr_rows)==6216","length(gscr_rows)==(criterion==\"G0\" ? 168 : 6216)")
common=replace_once(common,"margins=[let","margins=criterion in (\"G0\",\"M1\",\"M2\") ? nothing : [let")
if reviewed_week
    common=replace_once(common,"get(declared,\"technical_week\",nothing)==current_week[]","FP._paper_a_kw08(data)")
end
certificate_rows(c)=c.kind=="G0" ? (c.psd,) : c.rows
Base.include_string(Main,common,common_path)
include("AP3Pipeline.jl")
include("WeekStrengthAdmission.jl")
const N=AP3Pipeline.NativeG3Solver
const equivalent_conditioning=get(ENV,"PAPER_A_G3_EQUIVALENT_CONDITIONING","0")=="1"
equivalent_conditioning && (criterion!="G3" || native_backend!=:gurobi) && error("Conditioning is qualified only for G3/Gurobi")
const binary_million_cost=get(ENV,"PAPER_A_G3_BINARY_MILLION_COST","0")=="1"
binary_million_cost && !equivalent_conditioning && error("Binary-million cost coordinate requires qualified G3/Gurobi conditioning")
equivalent_conditioning && include("G3EquivalentConditioning.jl")
const out=joinpath(root,criterion,mode)
const case_dir=get(ENV,"PAPER_A_STRENGTH_EXISTING_CASE_DIR",joinpath(root,"CASES",criterion))
const case_path=joinpath(case_dir,"case.json")
writejson(path,obj)=open(io->JSON.print(io,obj,2),path,"w")
function native_attributes(model)
    if native_backend==:mosek
        safe(f)=begin
            x=try f() catch; nothing end
            x isa Real && !isfinite(x) ? nothing : x
        end
        return Dict{String,Any}("backend"=>"MOSEK","termination_status"=>string(JuMP.termination_status(model)),
            "primal_status"=>string(JuMP.primal_status(model)),"dual_status"=>string(JuMP.dual_status(model)),
            "result_count"=>JuMP.result_count(model),"runtime_s"=>safe(()->JuMP.solve_time(model)),
            "barrier_iterations"=>safe(()->JuMP.barrier_iterations(model)),"node_count"=>safe(()->JuMP.node_count(model)),
            "objective_backend"=>safe(()->JuMP.objective_value(model)),"bound_backend"=>safe(()->JuMP.objective_bound(model)),
            "quality_scope"=>"native_MOI_status_and_separate_original_JuMP_primal_check")
    end
    native=JuMP.unsafe_backend(model)
    result=Dict{String,Any}()
    for name in ("Status","SolCount","BarIterCount","IsMIP","NumVars","NumConstrs","NumQConstrs")
        value=Ref{Cint}(0);code=Gurobi.GRBgetintattr(native,name,value)
        result[name]=code==0 ? value[] : nothing
    end
    for name in ("ConstrVio","BoundVio","IntVio","DualVio","IterCount","NodeCount","ObjVal","ObjBound","MIPGap","Runtime")
        value=Ref{Cdouble}(0.);code=Gurobi.GRBgetdblattr(native,name,value)
        result[name]=code==0 && isfinite(value[]) ? value[] : nothing
    end
    return result
end
sha_file(qref_path)==qref_sha || error("QREF receipt changed")
reviewed_week || initialize_week_validators()
config=JSON.parsefile(joinpath(parent_study,"week_selection.json"))
sha_file(joinpath(parent_study,"week_selection.json"))==selection_sha || error("Selection changed")
chosen=only(filter(w->w["iso_week"]==8,config["selected"]))
current_week[]=merge(Dict{String,Any}(k=>chosen[k] for k in ("first","last","source_first","source_last","iso_week")),
    Dict("kind"=>"technical_independent_week_2013_v1","hours"=>168,"operation_factor"=>(reviewed_week ? 8760/168 : 8760/840),"investment_factor"=>1))

function normalized_parent_spec(data)
    spec=deepcopy(FP._paper_a_full37(data));pop!(spec,"technical_gfm_source_proxy",nothing)
    spec["variant"]["formulation"]="G1"
    if reviewed_week
        spec["variant"]["hours"]=8760 # restore the parent metadata for the lineage comparison
        spec["technical_week"]["operation_factor"]=8760/840
        pop!(spec,"strength_register_sha256",nothing)
    end
    spec["variant_sha256"]=FP._paper_a_full37_variant_digest(spec["variant"])
    return spec
end
function selected_formulation(data)
    spec=FP._paper_a_full37(data)
    criterion=="G0" && return FP.ExactPSDGSCR()
    criterion=="G2" && return FP.FixedScalingGSCR(spec["g2_r"];provenance=spec["g2_r_sha256"])
    criterion=="G3" && return FP.ExactEdgeSOCGSCR()
    path=ENV["PAPER_A_STRENGTH_REGISTER"]
    digest=sha_file(path)
    digest==spec["strength_register_sha256"] || error("Strength register bytes differ")
    register=JSON.parsefile(path)
    net=data["paper_a_network"]
    regions=[net["bus_to_region"][b] for b in net["retained_physical_buses"]]
    register["method"]==criterion && register["regions"]==regions || error("Strength register method/order mismatch")
    criterion=="M1" && return FP.InverseBoundGSCR(FP.PaperADiagnostics.matrix(register["Bmin"]);provenance=digest)
    return FP.InteractionGSCR(FP.PaperADiagnostics.matrix(register["W"]);provenance=digest)
end

function comparison_case()
    receipt=JSON.parsefile(joinpath(case_dir,"receipt.json"))
    reviewed_week && receipt["contract_sha256"]!=sha_file(contract_path) && error("Case contract mismatch")
    actual=sha_file(case_path)
    receipt["parent_sha256"]==source_sha && receipt["case_sha256"]==actual || error("Comparison lineage mismatch")
    data=JSON.parsefile(case_path;dicttype=Dict{String,Any})
    FP._paper_a_full37(data)["variant"]["formulation"]==criterion || error("Wrong criterion bytes")
    data[FP._PAPER_A_PROFILE_KEY]=FP._PaperAProfileBinding("ap2:sha256:"*actual,receipt["profile_sha256"])
    FP.prepare_paper_a_data!(data)
    FP.paper_a_profile_identity(data)==receipt["profile_sha256"] || error("Comparison profile mismatch")
    return data
end

if phase=="prepare"
    ispath(case_path) && error("Preserve existing case")
    sha_file(source_case)==source_sha || error("Frozen source bytes changed")
    data=JSON.parsefile(source_case;dicttype=Dict{String,Any})
    data[FP._PAPER_A_PROFILE_KEY]=FP._PaperAProfileBinding("ap2:sha256:"*source_sha,source_profile)
    reviewed_week || FP.prepare_paper_a_data!(data)
    binding=FP._paper_a_profile_binding(data)
    spec=deepcopy(FP._paper_a_full37(data));spec["variant"]["formulation"]=criterion
    if reviewed_week
        spec["variant"]["hours"]=168
        spec["technical_week"]=current_week[]
        if criterion in ("M1","M2")
            spec["strength_register_sha256"]=sha_file(ENV["PAPER_A_STRENGTH_REGISTER"])
        end
    end
    spec["variant_sha256"]=FP._paper_a_full37_variant_digest(spec["variant"])
    data["paper_a_extension"]["full37_specification"]=spec
    for sn in values(data["nw"]);sn["paper_a_extension"]["full37_specification"]=spec;end
    FP._paper_a_advance_profile_binding!(data,binding)
    FP.prepare_paper_a_data!(data)
    selected_formulation(data)
    mkpath(case_dir)
    open(io->JSON.print(io,Dict(k=>v for (k,v) in data if k!=FP._PAPER_A_PROFILE_KEY)),case_path,"w")
    writejson(joinpath(case_dir,"receipt.json"),Dict("parent_sha256"=>source_sha,"case_sha256"=>sha_file(case_path),
        "profile_sha256"=>FP.paper_a_profile_identity(data),"consumer_commit"=>pin,"criterion"=>criterion,
        "QREF_sha256"=>qref_sha,"quota_pct"=>70,"hours"=>168,"contract_sha256"=>(reviewed_week ? sha_file(contract_path) : nothing),
        "changed_fields"=>(reviewed_week ? ["variant.formulation","variant.hours","variant_sha256","technical_week.operation_factor","strength_register_sha256_if_applicable"] : ["variant.formulation","variant_sha256"])))
else
    mkpath(out)
    model=JuMP.Model();JuMP.set_string_names_on_creation(model,false)
    signed=JSON.parsefile(joinpath(parent_study,"AP1_EXPORT/week_8/case_manifest.json"))
    pm=build_week(joinpath(parent_study,"AP1_EXPORT/week_8/case.json"),signed["case_sha256"],science,parent_pin,model)
    input=renewable_inputs(chosen["source_first"]:chosen["source_last"],config)
    w=add_week!(pm,input,Dict{String,JuMP.VariableRef}())
    investment=FP.calc_uc_gscr_block_investment_cost(pm)+w.cap
    JuMP.@constraint(model,w.quota>=0.70*w.demand)
    original_objective=investment+annual_factor*(w.gen+w.storage+w.events)
    JuMP.@objective(model,Min,original_objective)
    objective_divisor=criterion=="G3" ? (binary_million_cost ? 2.0^20 : 8192.) : 1.
    discrete=filter(v->JuMP.is_integer(v)||JuMP.is_binary(v),JuMP.all_variables(model))
    before_domains=WeekStrengthAdmission.inventory(JuMP.backend(model);continuous=false)
    mode=="relaxed" && JuMP.relax_integrality(model)
    after_domains=WeekStrengthAdmission.inventory(JuMP.backend(model);continuous=mode=="relaxed")
    params=Dict{String,Any}("Threads"=>4,"Method"=>2,"TimeLimit"=>budget,"NumericFocus"=>3,
        "Seed"=>1,"FeasibilityTol"=>1e-8,"OptimalityTol"=>1e-8,"NodefileDir"=>out,"NodefileStart"=>0.5)
    if mode=="integer"
        merge!(params,Dict("MIPGap"=>0.005,"IntFeasTol"=>1e-8,"MIPFocus"=>1,"NoRelHeurTime"=>120.))
    else
        merge!(params,Dict("Crossover"=>1,"BarHomogeneous"=>1,"BarConvTol"=>1e-8))
    end
    if native_backend==:mosek
        params=N.mosek_options()
        params["MSK_IPAR_NUM_THREADS"]=4
        params["MSK_DPAR_OPTIMIZER_MAX_TIME"]=budget
        params["MSK_DPAR_MIO_TOL_REL_GAP"]=0.005
    end
    profile=Dict{String,Any}("consumer_commit"=>pin,"runner_sha256"=>sha_file(@__FILE__),"criterion"=>criterion,
        "native_backend"=>string(native_backend),
        "mode"=>mode,"case_sha256"=>sha_file(case_path),"hours"=>168,"quota_pct"=>70,"annual_factor"=>annual_factor,
        "variables"=>JuMP.num_variables(model),"original_discrete_count"=>length(discrete),"attributes"=>params,
        "strength_rows"=>length(w.gscr_rows),"domains_before"=>before_domains,"domains_after"=>after_domains,
        "solver_class"=>(criterion=="G0" ? "SDP" : criterion=="G3" ? (mode=="integer" ? "MISOCP" : "SOCP") : (mode=="integer" ? "MILP" : "LP")))
    if reviewed_week
        profile["contract_sha256"]=sha_file(contract_path)
        profile["input_profile_sha256"]=JSON.parsefile(joinpath(case_dir,"receipt.json"))["profile_sha256"]
        profile["exposure_attachment_complete"]=!pm.ext[:paper_a_strength_pending] && length(pm.ext[:paper_a_certificates])==168 && length(w.projects)==74
        profile["exposure_attachment_complete"] || error("Incomplete week attachment")
    end
    conditioned_copy=nothing
    if criterion=="G3"
        if native_backend==:gurobi
            params["NonConvex"]=0
            params["BarQCPConvTol"]=1e-10
            params["FeasibilityTol"]=1e-9
            params["OptimalityTol"]=1e-9
        end
        try
            profile["input_range"]=N.input_range(model)
            conditioned,meta=N.condition_objective(original_objective;divisor=objective_divisor,
                minimum_coefficient=binary_million_cost ? 2.0^-20 : N.MIN_OBJECTIVE_COEFFICIENT)
            meta["multiplier"]==1 || error("Explicit objective coordinate qualification required")
            profile["objective_conditioning"]=meta
            profile["objective_backend_divisor"]=objective_divisor
            JuMP.set_objective_function(model,conditioned)
            if equivalent_conditioning
                global conditioned_copy=G3EquivalentConditioning.scaled_copy(model;protected=Set(discrete),objective_divisor)
                profile["equivalent_conditioning"]=conditioned_copy.metadata
                profile["conditioning_source_sha256"]=sha_file(joinpath(@__DIR__,"G3EquivalentConditioning.jl"))
                profile["conditioned_input_range"]=N.input_range(conditioned_copy.model)
            end
            profile["status"]="PROFILE_READY"
        catch e
            profile["status"]="OPTIMIZE_NOT_CALLED";profile["reason"]=sprint(showerror,e)
        end
    else
        profile["status"]="PROFILE_READY"
    end
    if equivalent_conditioning && profile["status"]=="PROFILE_READY"
        conditioned_copy!==nothing && conditioned_copy.model!==model || error("Conditioned copy missing; optimize not called")
    end
    if phase=="profile"
        writejson(joinpath(out,"profile.json"),profile)
        report("model_profile",profile)
    else
        if phase=="admit_solve"
            profile["status"]=="PROFILE_READY" || error("Unqualified original model")
        else
        expected=JSON.parsefile(joinpath(out,"profile.json"))
        profile==expected && profile["status"]=="PROFILE_READY" || error("Actual profile is not qualified/identical")
        gate=JSON.parsefile(joinpath(root,"INDEPENDENT_REVIEW/admission.json"))
        gate["status"]=="PASS" && gate["consumer_commit"]==pin &&
            gate["profiles"]["$criterion/$mode"]==sha_file(joinpath(out,"profile.json")) &&
            gate["cases"][criterion]==sha_file(case_path) || error("Independent actual case/profile admission missing")
        end
        constructor=native_backend==:mosek ? N.MosekTools.Optimizer : Gurobi.Optimizer
        opt=JuMP.optimizer_with_attributes(constructor,params...)
        solver_model=conditioned_copy===nothing ? model : conditioned_copy.model
        if equivalent_conditioning
            solver_model===conditioned_copy.model && solver_model!==model || error("Wrong conditioned solver model; optimize not called")
            N.input_range(solver_model)==profile["conditioned_input_range"] || error("Actual conditioned input range differs from profile; optimize not called")
        end
        JuMP.set_optimizer(solver_model,opt)
        criterion=="G3" && N.configure_bridges!(solver_model,opt)
        bridge=criterion=="G3" ? N.prepare_backend!(solver_model,opt) : nothing
        native_backend==:gurobi && JuMP.set_optimizer_attribute(solver_model,"LogFile",joinpath(out,"gurobi.log"))
        if phase=="admit_solve"
            JuMP.MOI.Utilities.attach_optimizer(JuMP.backend(solver_model))
            attached=JuMP.unsafe_backend(solver_model)
            profile["native_type"]=string(typeof(attached))
            profile["native_variables"]=JuMP.MOI.get(attached,JuMP.MOI.NumberOfVariables())
            profile["native_domains"]=WeekStrengthAdmission.inventory(attached;continuous=mode=="relaxed" && !(criterion=="G3" && native_backend==:gurobi))
            profile["native_objective"]=WeekStrengthAdmission.native_cost(solver_model,attached)
            if criterion=="G0"
                for source in (JuMP.backend(model),attached)
                    WeekStrengthAdmission.psd_sizes(source)==fill(37,168) || error("Expected 168 full 37-bus PSD cones")
                end
                profile["PSD_blocks"]=168
                profile["PSD_side_dimension"]=37
            end
            profile["native_instance"]=string(getpid(),"/",objectid(attached))
            profile["native_time_limit"]=JuMP.time_limit_sec(solver_model)
            writejson(joinpath(out,"live_profile.json"),profile)
            gatepath=joinpath(out,"live_admission.json")
            timedwait(()->isfile(gatepath),1200.;pollint=0.5)==:ok || error("Independent native admission timed out")
            gate=JSON.parsefile(gatepath)
            gate["status"]=="PASS" && gate["profile_sha256"]==sha_file(joinpath(out,"live_profile.json")) &&
                JuMP.unsafe_backend(solver_model)===attached || error("Live native profile not independently admitted")
        end
        report("solve_enter",profile)
        started=time()
        writejson(joinpath(out,"native_optimization_window.json"),Dict("status"=>"running",
            "backend"=>string(native_backend),"started_epoch_s"=>started))
        JuMP.optimize!(solver_model)
        writejson(joinpath(out,"native_optimization_window.json"),Dict("status"=>"finished",
            "backend"=>string(native_backend),"started_epoch_s"=>started,"finished_epoch_s"=>time(),
            "reported_solver_time_s"=>JuMP.solve_time(solver_model)))
        native=native_attributes(solver_model)
        writejson(joinpath(out,"native_outcome.json"),native)
        if conditioned_copy!==nothing
            if JuMP.has_values(solver_model)
                CSV.write(joinpath(out,"scaled_primal_backmap.csv"),[(original_index=JuMP.index(v).value,
                    scaled_index=JuMP.index(conditioned_copy.variables[v]).value,exponent=conditioned_copy.exponents[v],
                    scaled_value=JuMP.value(conditioned_copy.variables[v]),original_value=G3EquivalentConditioning.backmap(conditioned_copy,v))
                    for v in JuMP.all_variables(model)])
            end
            G3EquivalentConditioning.project_results!(model,conditioned_copy)
        end
        reported_bound=try JuMP.objective_bound(model) catch; nothing end
        currency_bound=N.original_currency_bound(reported_bound,objective_divisor)
        result=merge(copy(profile),Dict("status"=>string(JuMP.termination_status(model)),"primal_status"=>string(JuMP.primal_status(model)),
            "result_count"=>JuMP.result_count(model),"solve_time_s"=>JuMP.solve_time(model),"bound_certification"=>"numerical_only_not_rigorous_currency_bound",
            "best_bound_EUR2025"=>currency_bound,"native_objective_cost_divisor"=>objective_divisor,
            "native_cost_coordinate"=>"original_EUR2025_divided_by_native_objective_cost_divisor",
            "native_bridge_validation"=>bridge,"native_solver_attributes"=>native,"warm_start_from_other_run"=>false))
        point_status=JuMP.primal_status(model)
        if point_status in (JuMP.MOI.FEASIBLE_POINT,JuMP.MOI.NEARLY_FEASIBLE_POINT,JuMP.MOI.UNKNOWN_RESULT_STATUS,JuMP.MOI.INFEASIBLE_POINT) && JuMP.has_values(model)
            v=JuMP.value;capex=v(investment);op=Dict("generation"=>v(w.gen),"storage"=>v(w.storage),"startup_shutdown"=>v(w.events))
            open(joinpath(out,"full_primal.csv"),"w") do io
                println(io,"variable_index,value,lower_bound,upper_bound,is_integer,is_binary")
                for x in JuMP.all_variables(model)
                    println(io,JuMP.index(x).value,',',v(x),',',JuMP.has_lower_bound(x) ? JuMP.lower_bound(x) : -Inf,',',
                        JuMP.has_upper_bound(x) ? JuMP.upper_bound(x) : Inf,',',JuMP.is_integer(x),',',JuMP.is_binary(x))
                end
            end
            coords=NamedTuple[]
            for t in 1:168,(sym,container) in fp.var(pm,t)
                entries=container isa JuMP.Containers.DenseAxisArray ? ((repr(k),container[k...]) for k in Iterators.product(axes(container)...)) :
                    container isa AbstractDict || container isa AbstractArray ? ((repr(k),x) for (k,x) in pairs(container)) : ()
                for (coord,x) in entries
                    x isa JuMP.VariableRef && push!(coords,(;snapshot=t,container=string(sym),coordinate=coord,variable_index=JuMP.index(x).value))
                end
            end
            for p in w.projects
                push!(coords,(;snapshot=0,container="renewable_capacity",coordinate=p.name,variable_index=JuMP.index(p.installed).value))
                for t in 1:168;push!(coords,(;snapshot=t,container="renewable_dispatch",coordinate=p.name,variable_index=JuMP.index(p.gen[t]).value));end
            end
            if criterion=="G3"
                for t in 1:168
                    cert=pm.ext[:paper_a_certificates][t]
                    for k in eachindex(cert.edges),side in 1:2
                        push!(coords,(;snapshot=t,container="G3_edge_q",coordinate=repr((cert.edges[k],side)),variable_index=JuMP.index(cert.q[k,side]).value))
                    end
                end
            end
            CSV.write(joinpath(out,"variable_coordinates.csv"),coords)
            if point_status in (JuMP.MOI.UNKNOWN_RESULT_STATUS,JuMP.MOI.INFEASIBLE_POINT)
                result["vector_role"]="diagnostic_only_unqualified_primal"
                writejson(joinpath(out,"run_summary.json"),result)
                exit(0)
            end
            point=AP3Pipeline.extract(pm)
            point["renewable_capacity_MW"]=Dict(p.name=>v(p.installed) for p in w.projects)
            projects=[Dict("name"=>p.name,"bus"=>p.bus,"carrier"=>p.carrier,"availability"=>p.availability,
                "snapshot_ids"=>input.stamps,"existing_MW"=>p.exist,"native_cap_MW"=>p.limit,
                "capex_EUR_per_MW"=>p.price.cost_inv_per_mw) for p in w.projects]
            for t in 1:168
                point["snapshots"][string(t)]["renewable_dispatch_MW"]=Dict(p.name=>w.base*v(p.gen[t]) for p in w.projects)
            end
            writejson(joinpath(out,"physical_point.json"),point)
            writejson(joinpath(out,"renewable_projects.json"),projects)
            checks=Dict{String,Any}()
            study_formulation=selected_formulation(pm.data)
            for t in 1:168
                rec=FP.PaperADiagnostics.reconstruct(pm.data,point,t;renewable_projects=projects)
                sn=point["snapshots"][string(t)]
                metrics=FP.PaperADiagnostics.evaluate(FP.PaperADiagnostics.matrix(rec["B"]),rec["p"],1.;
                    r=FP._paper_a_full37(pm.data)["g2_r"],W=criterion=="M2" ? study_formulation.W : Matrix{Float64}(FP.I,length(rec["p"]),length(rec["p"])),
                    Bmin=criterion=="M1" ? pm.ext[:paper_a_certificates][t].Bmin : nothing,witness=get(sn,"witness",nothing))
                checks[string(t)]=Dict("reconstruction"=>rec,"metrics"=>metrics)
            end
            writejson(joinpath(out,"strength_reconstruction.json"),checks)
            residuals=JuMP.primal_feasibility_report(model;atol=1e-6)
            CSV.write(joinpath(out,"primal_violations.csv"),[(;constraint=string(c),violation=r) for (c,r) in residuals])
            int_error=mode=="integer" ? maximum(abs(v(x)-round(v(x))) for x in discrete) : nothing
            original_check=criterion in ("G0","G3") ? N.primal_check(model) : Dict("status"=>isempty(residuals) ? "passed" : "failed","tolerance"=>1e-6)
            if criterion=="G3"
                legacy_poly=0.
                for cert in values(pm.ext[:paper_a_certificates]),k in eachindex(cert.edges)
                    y=JuMP.value.(JuMP.constraint_object(cert.cones[k]).func)
                    legacy_poly=max(legacy_poly,(sqrt(2.)*y[3])^2-2*(2*y[1])*y[2])
                end
                original_check["historical_raw_cone_polynomial_violation"]=legacy_poly
                legacy_poly>N.PRIMAL_TOLERANCE && (original_check["status"]="failed_original_primal_check")
            end
            native_ok=native_backend==:mosek ? JuMP.primal_status(model)==JuMP.MOI.FEASIBLE_POINT :
                all(get(native,k,nothing) isa Number && native[k]<=1e-6 for k in ("ConstrVio","BoundVio")) &&
                (mode=="relaxed" || (get(native,"IntVio",nothing) isa Number && native["IntVio"]<=1e-6))
            original_value=v(original_objective)
            merge!(result,Dict("objective_EUR2025"=>original_value,"annualized_capex_EUR2025"=>capex,
                "operation_168h_components_EUR2025"=>op,"annualized_opex_EUR2025"=>annual_factor*sum(values(op)),
                "objective_replay_residual_EUR2025"=>abs(original_value-capex-annual_factor*sum(values(op))),
                "native_objective_backmap_residual_EUR2025"=>abs(original_value-JuMP.objective_value(model)*objective_divisor),
                "wind_pv_MWh"=>v(w.quota),"load_MWh"=>w.demand,"wind_pv_share_pct"=>100*v(w.quota)/w.demand,
                "relative_gap"=>mode!="integer" || currency_bound===nothing || int_error===nothing || int_error>1e-6 || !native_ok || original_check["status"]!="passed" ? nothing : abs(original_value-currency_bound)/max(1.,abs(original_value)),
                "primal_violation_count_at_1e_6"=>length(residuals),"max_integer_residual"=>int_error,
                "original_primal_check"=>original_check,"numerically_accepted"=>native_ok && isempty(residuals) && original_check["status"]=="passed" && (mode=="relaxed" || int_error<=1e-6)))
            roster=fp.var(pm,1,:n_block)
            CSV.write(joinpath(out,"block_expansion.csv"),[(;name=d["name"],carrier=d["carrier"],existing_blocks=d["n0"],added_blocks=v(roster[key])-d["n0"],
                block_MW=d["p_block_max_MW"],capex_EUR2025=(v(roster[key])-d["n0"])*d["p_block_max_MW"]*d["cost_inv_per_mw"])
                for key in axes(roster,1) for d in (fp.ref(pm,1,key...),)])
            CSV.write(joinpath(out,"renewable_expansion.csv"),[(;p.name,p.bus,p.carrier,existing_MW=p.exist,native_cap_MW=p.limit,added_MW=v(p.installed),capex_EUR2025=v(p.installed)*p.price.cost_inv_per_mw) for p in w.projects])
            fill_dispatch(pm,w.projects,w.base,out)
        end
        writejson(joinpath(out,"run_summary.json"),result)
        report("completed",result)
    end
end
