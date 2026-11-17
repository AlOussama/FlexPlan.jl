# One source variant of the existing workflow; no integer rounding or warm starts.
using SHA, JSON, CSV, Dates
length(ARGS)==4 || error("usage: PARENT_STUDY OUTPUT_ROOT SCIENCE_CASE SOLVER_SECONDS")
const parent_study,output_root,science_case=abspath.(ARGS[1:3])
const solver_seconds=parse(Float64,ARGS[4])
0<solver_seconds<=7200 || error("Solver budget must be in (0,7200] seconds")
const integrality_mode=get(ENV,"PAPER_A_PROXY_INTEGRALITY","relaxed")
integrality_mode in ("relaxed","integer") || error("Unsupported integrality mode")
startswith(output_root,"E:") || error("Large outputs require E:")
const source_variants=Dict{String,Any}()
const candidate_receipt=Ref{Dict{String,Any}}()
const qualified_case_root=get(ENV,"PAPER_A_PROXY_QUALIFIED_CASE_ROOT","")
const selected_iso_week=parse(Int,get(ENV,"PAPER_A_PROXY_SINGLE_WEEK","0"))
const study_hours=selected_iso_week==0 ? 840 : 168
const inherited_byte_review_sha="ca0d3806d96d63422d656e1fd7e2cd66cae0262deb7d26d9ca8d88d4943dac80"
const proxy_fields=Set(["source_equivalent_type","source_equivalent_valid","frozen_internal_voltage",
    "source_model_scope","physical_controller_equivalent_qualified","x_src","r_src","S_base_MVA",
    "native_parameter_base","native_source_MVA","native_source_kv_referred","source_bus_base_kv",
    "x_src_block_base","b_block","mu_str","mu_fl","source_parameter_provenance",
    "source_equivalent_time_scale","electrical_interface_evidence","source_b_block_pu_reference",
    "paper_a_full37_online"])

function matched_replace(s,old,new)
    length(findall(old,s))==1 || error("Nonunique existing workflow anchor: $old")
    return replace(s,old=>new;count=1)
end

function read_qualified_variant(parent_path,parent_sha)
    isempty(qualified_case_root) && return FP.parse_file(parent_path;expected_case_sha256=parent_sha)
    sha_file(parent_path)==parent_sha || error("Original AP1 bytes changed")
    gate_path=joinpath(qualified_case_root,"independent_case_byte_review.json")
    sha_file(gate_path)==inherited_byte_review_sha || error("Unrecognized inherited case-byte review")
    gate=JSON.parsefile(gate_path)
    gate["status"]=="PASS" && gate["source_model"]==FP._PAPER_A_GFM_PROXY_ID || error("Case-byte review not positive")
    week=string(current_week[]["iso_week"])
    dir=joinpath(qualified_case_root,"AP2_SOURCE_VARIANTS","week_"*week)
    receipt=JSON.parsefile(joinpath(dir,"source_variant_receipt.json"))
    actual=sha_file(joinpath(dir,"derived_case.json"))
    receipt["parent_AP1_sha256"]==parent_sha &&
        receipt["derived_AP2_case_sha256"]==actual==gate["derived_AP2_case_sha256_by_week"][week] ||
        error("Derived variant bytes do not match the qualified lineage")
    data=JSON.parsefile(joinpath(dir,"derived_case.json"))
    # This is a consumer-derived byte identity, not a producer AP1 identity.
    data[FP._PAPER_A_PROFILE_KEY]=FP._PaperAProfileBinding("ap2:sha256:"*actual,receipt["derived_profile_sha256"])
    FP.prepare_paper_a_data!(data)
    FP.paper_a_profile_identity(data)==receipt["derived_profile_sha256"] || error("Prepared variant profile changed")
    return data
end

function parent_specification(data)
    spec=copy(FP._paper_a_full37(data))
    pop!(spec,"technical_gfm_source_proxy",nothing)
    return spec
end

function neutral_profile(data)
    copydata=copy(data)
    extension=deepcopy(data["paper_a_extension"])
    pop!(extension["full37_specification"],"technical_gfm_source_proxy",nothing)
    copydata["paper_a_extension"]=extension
    copydata["nw"]=Dict{String,Any}()
    for (t,sn) in data["nw"]
        projected=copy(sn)
        for table in ("storage","ne_storage")
            projected[table]=Dict(id=>(get(dev,"source_class",nothing)=="GFM" ?
                Dict(k=>v for (k,v) in dev if !(k in proxy_fields)) : dev) for (id,dev) in sn[table])
        end
        copydata["nw"][t]=projected
    end
    return FP.paper_a_profile_identity(copydata)
end

function apply_and_record_proxy!(data,parent_sha)
    if !isempty(qualified_case_root)
        week=string(current_week[]["iso_week"])
        receipt=JSON.parsefile(joinpath(qualified_case_root,"AP2_SOURCE_VARIANTS","week_"*week,"source_variant_receipt.json"))
        FP.paper_a_profile_identity(data)==receipt["derived_profile_sha256"] || error("Reused source profile mismatch")
        source_variants[week]=receipt
        report("reused_qualified_source_variant",receipt)
        return
    end
    preserved=neutral_profile(data)
    FP.apply_paper_a_gfm_source_proxy!(data;parent_AP1_sha256=parent_sha)
    neutral_profile(data)==preserved || error("Source overlay changed non-source data")
    week=string(current_week[]["iso_week"])
    out=joinpath(output_root,"AP2_SOURCE_VARIANTS","week_"*week)
    mkpath(out)
    path=joinpath(out,"derived_case.json")
    isfile(path) && error("Preserve existing derived case; select a new output root")
    public=Dict(k=>v for (k,v) in data if k!=FP._PAPER_A_PROFILE_KEY)
    open(io->JSON.print(io,public),path,"w")
    receipt=Dict("schema"=>"paper_a_consumer_source_variant_v1","parent_AP1_sha256"=>parent_sha,
        "derived_AP2_case_sha256"=>sha_file(path),"derived_profile_sha256"=>FP.paper_a_profile_identity(data),
        "unchanged_non_source_profile_sha256"=>preserved,"consumer_commit"=>consumer_pin,
        "variant"=>FP._paper_a_full37(data)["technical_gfm_source_proxy"],"week"=>week,
        "snapshot_count"=>168,"stage"=>"prepared_pu_before_dimensions_and_cost_weights")
    open(io->JSON.print(io,receipt,2),joinpath(out,"source_variant_receipt.json"),"w")
    source_variants[week]=receipt
    report("positive_source_variant_bytes",receipt)
end

function native_attribute(model,name;integer=false)
    backend=JuMP.unsafe_backend(model)
    result=integer ? Ref{Cint}(0) : Ref{Cdouble}(0.)
    code=integer ? Gurobi.GRBgetintattr(backend,name,result) : Gurobi.GRBgetdblattr(backend,name,result)
    code==0 || error("Gurobi attribute $name returned $code")
    return result[]
end

function await_case_byte_review!()
    gate=joinpath(output_root,"independent_case_byte_review.json")
    length(source_variants)==study_hours÷168 || error("Missing source variant receipts")
    report("awaiting_independent_case_byte_review",Dict("receipt"=>gate,"source_variants"=>source_variants))
    deadline=time()+900
    while !isfile(gate) && time()<deadline
        sleep(2)
    end
    isfile(gate) || error("Independent source-variant byte review is still pending; solver not started")
    review=JSON.parsefile(gate)
    get(review,"status",nothing)=="PASS" && get(review,"consumer_commit",nothing)==consumer_pin &&
        get(review,"source_model",nothing)==FP._PAPER_A_GFM_PROXY_ID &&
        get(review,"derived_AP2_case_sha256_by_week",nothing)==
            Dict(week=>r["derived_AP2_case_sha256"] for (week,r) in source_variants) ||
        error("Independent case-byte review did not qualify these exact variants")
    report("independent_case_byte_review_pass",Dict("sha256"=>sha_file(gate)))
end

function save_complete_candidate!(model,weeks,output,scenario)
    native=Dict{String,Any}()
    for name in ("Status","SolCount","BarIterCount")
        native[name]=try native_attribute(model,name;integer=true) catch e; sprint(showerror,e) end
    end
    for name in ("ConstrVio","BoundVio","DualVio","IterCount","ObjVal","ObjBound")
        native[name]=try native_attribute(model,name) catch e; sprint(showerror,e) end
    end
    discrete=filter(v->JuMP.is_integer(v) || JuMP.is_binary(v),JuMP.all_variables(model))
    if !isempty(discrete)
        native["IntVio"]=try native_attribute(model,"IntVio") catch e; sprint(showerror,e) end
    end
    receipt=Dict{String,Any}("source_model"=>FP._PAPER_A_GFM_PROXY_ID,"claim"=>"frozen_E_planning_proxy",
        "derived_source_variants"=>source_variants,"native_solver_attributes"=>native,
        "integrality_mode"=>integrality_mode,"discrete_variable_count"=>length(discrete),
        "model_variable_count"=>JuMP.num_variables(model),
        "integer_rounding_performed"=>false,"full_primal_saved"=>false,"strength_constraints_active"=>scenario=="with_gscr")
    if JuMP.has_values(model)
        value=JuMP.value
        open(joinpath(output,"full_primal.csv"),"w") do io
            println(io,"variable_index,value,lower_bound,upper_bound,is_integer,is_binary")
            for variable in JuMP.all_variables(model)
                println(io,JuMP.index(variable).value,',',value(variable),',',
                    JuMP.has_lower_bound(variable) ? JuMP.lower_bound(variable) : -Inf,',',
                    JuMP.has_upper_bound(variable) ? JuMP.upper_bound(variable) : Inf,',',
                    JuMP.is_integer(variable),',',JuMP.is_binary(variable))
            end
        end
        # Retain symbolic container coordinates for every stored VariableRef.
        open(joinpath(output,"variable_coordinates.csv"),"w") do io
            println(io,"period,snapshot,container,coordinate,variable_index")
            for (period,w) in enumerate(weeks),t in 1:168,(symbol,container) in fp.var(w.pm,t)
                entries=container isa JuMP.Containers.DenseAxisArray ?
                    ((repr(key),container[key...]) for key in Iterators.product(axes(container)...)) :
                    container isa AbstractDict || container isa AbstractArray ?
                    ((repr(key),variable) for (key,variable) in pairs(container)) : ()
                for (coordinate,variable) in entries
                    variable isa JuMP.VariableRef || continue
                    escaped="\""*replace(coordinate,"\""=>"\"\"")*"\""
                    println(io,period,',',t,',',symbol,',',escaped,',',JuMP.index(variable).value)
                end
            end
            for (period,w) in enumerate(weeks),project in w.projects
                println(io,period,",0,renewable_capacity,\"",replace(project.name,"\""=>"\"\""),"\",",JuMP.index(project.installed).value)
                for t in 1:168
                    println(io,period,',',t,",renewable_dispatch,\"",replace(project.name,"\""=>"\"\""),"\",",JuMP.index(project.gen[t]).value)
                end
            end
        end
        g1=[]
        for (period,w) in enumerate(weeks)
          margins=Dict(row=>margin for (row,margin) in zip(w.gscr_rows,w.margins))
          for t in 1:168,(region,row) in fp.con(w.pm,t)[:gscr_gershgorin_sufficient]
            f=margins[row]
            lhs=f.constant+sum(c*value(v) for (c,v) in JuMP.linear_terms(f) if c>0;init=0.0)
            rhs=sum(-c*value(v) for (c,v) in JuMP.linear_terms(f) if c<0;init=0.0)
            push!(g1,(;period,snapshot=t,region,lhs_pu=lhs,rhs_pu=rhs,slack_pu=value(f)))
          end
        end
        CSV.write(joinpath(output,"g1_all_bus_hours.csv"),g1)
        violations=JuMP.primal_feasibility_report(model;atol=1e-6)
        open(joinpath(output,"primal_violations.csv"),"w") do io
            println(io,"constraint_index,violation")
            for (constraint,violation) in violations
                println(io,JuMP.index(constraint).value,',',violation)
            end
        end
        slack=minimum(r.slack_pu for r in g1)
        native_ok=all(get(native,k,nothing) isa Number && native[k]<=1e-6 for k in ("ConstrVio","BoundVio"))
        integer_error=maximum((abs(value(v)-round(value(v))) for v in discrete);init=0.0)
        integer_ok=isempty(discrete) || (integer_error<=1e-6 && get(native,"IntVio",Inf) isa Number && native["IntVio"]<=1e-6)
        merge!(receipt,Dict("full_primal_saved"=>true,"primal_violation_count_at_1e_6"=>length(violations),
            "saved_discrete_max_residual"=>integer_error,
            "minimum_g1_slack_pu"=>slack,"g1_row_count"=>length(g1),
            "numerically_accepted"=>isempty(violations) && (scenario!="with_gscr" || slack>=-1e-6) && native_ok && integer_ok))
    end
    candidate_receipt[]=receipt
    open(io->JSON.print(io,receipt,2),joinpath(output,"complete_candidate_receipt.json"),"w")
end

common_path=joinpath(parent_study,"run_common.jl")
bytes=read(common_path)
bytes2hex(sha256(bytes))=="40eb3f9d55289f031ba2f6ed965b9bb4beee5a5b7dda408cd4b8390cab435d9b" || error("Existing common workflow changed")
common=String(bytes)
runtime_commit=ENV["PAPER_A_PROXY_CONSUMER_COMMIT"]
common=matched_replace(common,"const consumer_pin = \"4a78a9b6afb8e1a192c169073d43fffd8acc7330\"","const consumer_pin = \"$runtime_commit\"")
common=matched_replace(common,"const annual_factor = 8760/840","const annual_factor = 8760/study_hours")
common=matched_replace(common,"data = FP.parse_file(case_path; expected_case_sha256=expected_case_sha)",
    "data = read_qualified_variant(case_path,expected_case_sha)")
common=matched_replace(common,"data[\"paper_a_extension\"][\"full37_specification\"] == declared",
    "parent_specification(data) == declared")
common=matched_replace(common,"    FP.add_dimension!(data, :hour, 168)",
    "    apply_and_record_proxy!(data,expected_case_sha)\n    FP.add_dimension!(data, :hour, 168)")
Base.include_string(Main,common,common_path)
legacy_path=joinpath(parent_study,"run_joint_weeks_crossover.jl")
bytes=read(legacy_path)
bytes2hex(sha256(bytes))=="37cbb440910d9f0b80ecab9cc5a7cc2b080298c3c05e898d85ca5c5ad7120cb3" || error("Existing joint workflow changed")
legacy=first(split(String(bytes),"\nlength(ARGS)==6";limit=2))
legacy=matched_replace(legacy,"include(\"run_common.jl\")","")
# The input marker describes its authenticated five-week parent cohort. It is
# not the annual factor used by this run's objective or results.
legacy=matched_replace(legacy,"\"operation_factor\"=>annual_factor,\"investment_factor\"=>1",
    "\"operation_factor\"=>8760/840,\"investment_factor\"=>1")
legacy=matched_replace(legacy,"selected_file=joinpath(root,\"week_selection.json\")","selected_file=joinpath(parent_study,\"week_selection.json\")")
legacy=matched_replace(legacy,"length(rows)==4length(reference)","length(rows)==(length(weeks)-1)*length(reference)")
legacy=matched_replace(legacy,"    model=JuMP.Model()",
    "    if selected_iso_week!=0\n        chosen=filter(w->w[\"iso_week\"]==selected_iso_week,chosen)\n        length(chosen)==1 || error(\"Requested week is not in the qualified selection\")\n    end\n    model=JuMP.Model()")
legacy=matched_replace(legacy,"length(gscr)==840*37","length(gscr)==study_hours*37")
length(findall("\"hours\"=>840",legacy))==2 || error("Study hours anchors changed")
legacy=replace(legacy,"\"hours\"=>840"=>"\"hours\"=>study_hours")
legacy=matched_replace(legacy,"    terms=(investment,gen,storage,events,quota,demand)",
    "    terms=(investment,gen,storage,events,quota,demand)\n    await_case_byte_review!()")
legacy=matched_replace(legacy,"    status=JuMP.termination_status(model)","    status=JuMP.termination_status(model)\n    save_complete_candidate!(model,weeks,output,scenario)")
legacy=matched_replace(legacy,"    open(io->JSON.print(io,result,2),joinpath(output,\"run_summary.json\"),\"w\")",
    "    merge!(result,candidate_receipt[])\n    open(io->JSON.print(io,result,2),joinpath(output,\"run_summary.json\"),\"w\")")
legacy=matched_replace(legacy,"(\"NumericFocus\",1)","(\"NumericFocus\",3)")
legacy=matched_replace(legacy,"(\"Crossover\",1)","(\"Crossover\",1),(\"BarHomogeneous\",1)")
# Reuse the existing integer branch and skip its automatic LP fallback. Dropping
# the optimizer and clearing starts gives the second variant the same cold start.
legacy=matched_replace(legacy,
    "            status=summarize(model,weeks,variant,\"integer\",terms,observed,target,integer_vars)",
    "            status=summarize(model,weeks,variant,\"integer\",terms,observed,target,integer_vars)\n"*
    "            if integrality_mode==\"integer\"\n"*
    "                JuMP.MOI.Utilities.drop_optimizer(model)\n"*
    "                for variable in JuMP.all_variables(model)\n"*
    "                    JuMP.set_start_value(variable,nothing)\n"*
    "                end\n"*
    "                continue\n"*
    "            end")
# Match the existing 1e-6 independent acceptance threshold for integer witnesses.
legacy=matched_replace(legacy,"(\"MIPGap\",0.005)","(\"MIPGap\",0.005),(\"IntFeasTol\",1e-8)")
Base.include_string(Main,legacy,legacy_path)
initialize_week_validators()
run_study(output_root,joinpath(parent_study,"AP1_EXPORT"),science_case,
    integrality_mode=="integer" ? solver_seconds : 0.,solver_seconds;
    solver_mode=selected_iso_week==0 ? "with_gscr" : "both")
