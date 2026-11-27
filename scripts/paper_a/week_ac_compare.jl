# Loaded by run_week_strength_comparison.jl after the authenticated weekly
# investment, dispatch, cost and G2 routines have been assembled.
const ac_label = ENV["PAPER_A_AC_FORMULATION"]
criterion!="G2" && pkgversion(PowerModels)!=v"0.21.7" &&
    error("Use the Julia 1.11 project manifest matching the independently checked AC BASE models (PowerModels 0.21.7)")
const ac_type = Dict("LPAC"=>PowerModels.LPACCPowerModel,
                     "SOC-WR"=>PowerModels.SOCWRConicPowerModel,
                     "QCRM"=>PowerModels.QCRMPowerModel)[ac_label]
const ac_solver = get(ENV,"PAPER_A_AC_SOLVER",criterion=="G0" ? "mosek" : "gurobi")
ac_solver in ("gurobi","ipopt","mosek") || error("Unsupported AC solver: $ac_solver")
criterion=="G0" && ac_solver!="mosek" && error("Direct PSD requires the SDP backend")
const ac_out = joinpath(root, get(ENV,"PAPER_A_AC_ATTEMPT",criterion=="G2" ? ac_label : ac_label*"_"*criterion))
const derived_dir = get(ENV,"PAPER_A_AC_CASE_DIR",joinpath(root, "AC_CASE"))
const qratio = 0.4

function confirmed_ac_case()
    file = joinpath(derived_dir, "case.json")
    if isfile(file)
        receipt = JSON.parsefile(joinpath(derived_dir,"receipt.json"))
        parent_receipt=JSON.parsefile(joinpath(dirname(case_path),"receipt.json"))
        parent_receipt["contract_sha256"]==sha_file(contract_path) || error("AC parent contract mismatch")
        sha_file(file)==receipt["case_sha256"]=="66885c9b5d27b21ac1000cf16e8da5d886b7ab50085783957907cebef8a41d3b" &&
            receipt["parent_sha256"]==sha_file(case_path)=="ae0f61e54e6aadfc1b4f3cde60f185bbe62c764fde84c96146d714c172b9d531" ||
            error("AC case identity mismatch")
        data = JSON.parsefile(file;dicttype=Dict{String,Any})
        data[FP._PAPER_A_PROFILE_KEY] = FP._PaperAProfileBinding("ap2:sha256:"*receipt["case_sha256"],receipt["profile_sha256"])
        FP.prepare_paper_a_data!(data)
        if criterion!="G2"
            binding=FP._paper_a_profile_binding(data)
            spec=deepcopy(FP._paper_a_full37(data))
            spec["variant"]["formulation"]=="G2" || error("Expected confirmed common G2 parent")
            spec["variant"]["formulation"]=criterion
            spec["variant_sha256"]=FP._paper_a_full37_variant_digest(spec["variant"])
            data["paper_a_extension"]["full37_specification"]=spec
            for sn in values(data["nw"])
                sn["paper_a_extension"]["full37_specification"]=spec
            end
            FP._paper_a_advance_profile_binding!(data,binding)
            FP.prepare_paper_a_data!(data)
        end
        return data
    end
    criterion=="G2" || error("Set PAPER_A_AC_CASE_DIR to the confirmed AC_CASE directory")
    data = comparison_case()
    parent = sha_file(case_path)
    parent=="ae0f61e54e6aadfc1b4f3cde60f185bbe62c764fde84c96146d714c172b9d531" || error("Wrong prepared G2 input")
    link_file = source_file(joinpath(get(ENV,"PAPER_A_NATIVE_CSV","D:/Projekte/Code/pypsatomatpowerx/data/elec_s_37_csv"),"links.csv"),
        "3f08a3e035797c93be3c2186ddaf0d4313dec0b03b23098bd72e703a64315dbc")
    ratings = Dict(string(link.name)=>Float64(link.p_nom) for link in CSV.File(link_file))
    base = data["baseMVA"]
    data["paper_a_ac_terminal_policy"] = "online_q_box"
    for snapshot in values(data["nw"])
        snapshot["per_unit"] && snapshot["baseMVA"]==base || error("Expected per-unit input")
        for load in values(snapshot["load"])
            iszero(load["qd"]) || error("Existing load Q requires source reconciliation")
            load["qd"] = load["pd"] * tan(acos(0.98))
        end
        for table in ("gen","storage","ne_storage"), dev in values(snapshot[table])
            if haskey(dev, "source_class")
                bound = qratio * dev["p_block_max"]
                dev["q_block_min"],dev["q_block_max"] = -bound,bound
            else
                table=="storage" && dev["carrier"]=="hydro" || error("Unmapped AC device")
                bound = qratio * dev["paper_a_storage_unit"]["p_nom_MW"] / base
                dev["qmin"],dev["qmax"] = -bound,bound
            end
        end
        length(snapshot["dcline"])==length(ratings)==43 || error("Incomplete HVDC roster")
        for line in values(snapshot["dcline"])
            bound = qratio * ratings[line["name"]] / base
            for (lo,hi) in (("qminf","qmaxf"),("qmint","qmaxt"))
                line[lo],line[hi] = -bound,bound
            end
        end
    end
    mkpath(derived_dir)
    open(file,"w") do io
        JSON.print(io,Dict(k=>v for (k,v) in data if k!=FP._PAPER_A_PROFILE_KEY))
    end
    digest = sha_file(file)
    profile = FP.paper_a_profile_identity(data)
    data[FP._PAPER_A_PROFILE_KEY] = FP._PaperAProfileBinding("ap2:sha256:"*digest,profile)
    writejson(joinpath(derived_dir,"receipt.json"),Dict("case_sha256"=>digest,"profile_sha256"=>profile,
        "parent_sha256"=>parent,"hvdc_source_sha256"=>sha_file(link_file),"load_pf"=>0.98,"q_over_online_MW"=>qratio,
        "hours"=>168,"quota_pct"=>70,"branch_fields_changed"=>false))
    FP.prepare_paper_a_data!(data)
    return data
end

function build_ac_week()
    m=JuMP.Model()
    JuMP.set_string_names_on_creation(m,false)
    signed=JSON.parsefile(joinpath(parent_study,"AP1_EXPORT/week_8/case_manifest.json"))
    pm=build_week(joinpath(parent_study,"AP1_EXPORT/week_8/case.json"),signed["case_sha256"],science,parent_pin,m)
    input=renewable_inputs(chosen["source_first"]:chosen["source_last"],config)
    w=add_week!(pm,input,Dict{String,JuMP.VariableRef}())
    bus_ids=Dict(b["name"]=>id for (id,b) in fp.ref(pm,1,:bus))
    new_q=Dict{Tuple{Int,String},JuMP.VariableRef}()
    for project in w.projects, n in 1:168
        q=JuMP.@variable(m)
        limit=qratio*project.installed/w.base
        JuMP.@constraint(m,q<=limit)
        JuMP.@constraint(m,q>=-limit)
        JuMP.set_normalized_coefficient(fp.con(pm,n,:uc_gscr_block_bus_reactive_balance,bus_ids[project.bus]),q,-1.)
        new_q[(n,project.name)]=q
    end
    JuMP.@constraint(m,w.quota>=0.70*w.demand)
    objective=FP.calc_uc_gscr_block_investment_cost(pm)+w.cap+annual_factor*(w.gen+w.storage+w.events)
    # Exact power-of-two rescaling keeps original EUR2025 accounting.
    scale=2.0^20
    JuMP.@objective(m,Min,objective/scale)
    JuMP.relax_integrality(m)
    return (;m,pm,w,new_q,objective,scale)
end

include("week_ac_audit.jl")
include("NativeStrengthReference.jl")
function scale_ac_angle_rows!(m;original_snapshot=nothing)
    original=JuMP.AffExpr[]
    for S in (JuMP.MOI.LessThan{Float64},JuMP.MOI.GreaterThan{Float64})
        for row in JuMP.all_constraints(m,JuMP.AffExpr,S)
            expr=JuMP.constraint_object(row).func
            length(expr.terms)==2 && any(c->abs(c)==tan(pi/2),values(expr.terms)) || continue
            sort(abs.(collect(values(expr.terms))))==[1.,tan(pi/2)] && JuMP.normalized_rhs(row)==0 ||
                error("Unexpected native angle row")
            push!(original,S==JuMP.MOI.LessThan{Float64} ? copy(expr) : -expr)
            original_snapshot===nothing || preserve_ac_original_constraint!(original_snapshot,row)
            for (c,v) in JuMP.linear_terms(expr)
                scaled=ldexp(c,-26)
                ldexp(scaled,26)==c || error("Angle scaling failed round trip")
                JuMP.set_normalized_coefficient(row,v,scaled)
            end
        end
    end
    length(original)==17472 || error("Incomplete signed angle row inventory")
    return original
end

function conify_qcrm_currents!(m;original_snapshot=nothing)
    originals=JuMP.QuadExpr[]
    for row in JuMP.all_constraints(m,JuMP.QuadExpr,JuMP.MOI.LessThan{Float64})
        expr=JuMP.constraint_object(row).func
        terms=collect(JuMP.quad_terms(expr))
        length(terms)==3 || continue
        cross=[(a,b) for (c,a,b) in terms if a!=b && c == -1]
        squared=[a for (c,a,b) in terms if a==b && c == 1]
        length(cross)==1 && length(squared)==2 || continue
        u,v=only(cross)
        all(t->JuMP.has_lower_bound(t) && JuMP.lower_bound(t)>=0,(u,v)) &&
            isempty(expr.aff.terms) && iszero(expr.aff.constant) && iszero(JuMP.normalized_rhs(row)) ||
            error("QCRM current cone requires nonnegative factors and a zero affine residual")
        p,q=squared
        original_snapshot===nothing || preserve_ac_original_constraint!(original_snapshot,row)
        JuMP.@constraint(m,[0.5*u,v,p,q] in JuMP.RotatedSecondOrderCone())
        push!(originals,expr)
        JuMP.delete(m,row)
    end
    length(originals)==8736 || error("Incomplete QCRM rotated-current conversion")
    return originals
end
if ac_solver == "ipopt"
    import Ipopt
end

function run_ac_week()
    if get(ENV,"PAPER_A_AC_REPLAY","0") == "1"
        return replay_ac_week(ac_out,build_ac_week())
    end
    ispath(ac_out) && error("Use a fresh output folder")
    mkpath(ac_out)
    (;m,pm,w,new_q,objective,scale) = build_ac_week()
    receipt=JSON.parsefile(joinpath(derived_dir,"receipt.json"))
    profile=Dict{String,Any}("formulation"=>ac_label,"model_type"=>string(ac_type),"case"=>receipt,
        "solver"=>ac_solver,"strength_method"=>criterion,"strength_profile_sha256"=>FP.paper_a_profile_identity(pm.data),
        "variables"=>JuMP.num_variables(m),"G2_rows"=>(criterion=="G2" ? length(w.gscr_rows) : 0),"added_project_Q_rows"=>2length(new_q),
        "discrete_after_relaxation"=>count(v->JuMP.is_binary(v)||JuMP.is_integer(v),JuMP.all_variables(m)),
        "native_network_physics"=>"PowerModels","power_models_version"=>string(pkgversion(PowerModels)),
        "annualization"=>annual_factor,"objective_divisor"=>scale,"runner_sha256"=>sha_file(@__FILE__),
        "audit_source_sha256"=>sha_file(joinpath(@__DIR__,"week_ac_audit.jl")),
        "integration_sha256"=>sha_file(joinpath(dirname(pathof(FP)),"prob","uc_gscr_block_integration.jl")),
        "network_source_sha256"=>sha_file(joinpath(dirname(pathof(FP)),"prob","paper_a_ac_network.jl")))
    certs=pm.ext[:paper_a_certificates]
    @assert length(certs)==168 && all(c->c.kind==criterion,values(certs))
    profile["strength_rows"]=length(w.gscr_rows)
    profile["strength_edge_cones"]=criterion=="G3" ? sum(length(c.cones) for c in values(certs)) : 0
    @assert profile["discrete_after_relaxation"]==0 && length(w.gscr_rows)==(criterion=="G0" ? 168 : 6216) && length(new_q)==12432
    writejson(joinpath(ac_out,"profile.json"),profile)
    original_snapshot=freeze_ac_original_model(m)
    if get(ENV,"PAPER_A_AC_EXPORT_NATIVE","0") == "1"
        criterion=="G0" && error("PSD blocks require the MOSEK solve path")
        JuMP.set_optimizer(m,Gurobi.Optimizer)
        export_ac_coordinates(ac_out,(;m,pm,w,new_q,objective,scale))
        JuMP.MOI.Utilities.attach_optimizer(JuMP.backend(m))
        native = JuMP.unsafe_backend(m)
        Gurobi.GRBupdatemodel(native)==0 || error("Native update failed")
        count_native = Ref{Cint}(0)
        Gurobi.GRBgetintattr(native,"NumVars",count_native)==0 || error("Native size unavailable")
        for i in 0:(count_native[]-1)
            Gurobi.GRBsetstrattrelement(native,"VarName",i,"V$i")==0 || error("Column name failed")
        end
        open(joinpath(ac_out,"native_columns.csv"),"w") do io
            println(io,"index,native")
            for v in JuMP.all_variables(m)
                println(io,JuMP.index(v).value,",",Int(Gurobi.c_column(native,JuMP.optimizer_index(v))))
            end
        end
        file = joinpath(ac_out,"native.mps")
        Gurobi.GRBwrite(native,file)==0 || error("Native MPS write failed")
        writejson(joinpath(ac_out,"export.json"),Dict("case_sha256"=>receipt["case_sha256"],
            "native_mps_sha256"=>sha_file(file),"variables"=>count_native[],"demand_MWh"=>w.demand,
            "solver_library"=>abspath(Gurobi.libgurobi),"solver_version"=>string(Gurobi._GUROBI_VERSION),
            "base_MVA"=>w.base,"objective_divisor"=>scale,"profile_sha256"=>sha_file(joinpath(ac_out,"profile.json")),
            "native_columns_sha256"=>sha_file(joinpath(ac_out,"native_columns.csv"))))
        return
    end
    if ac_solver == "mosek"
        JuMP.set_optimizer(m,N.MosekTools.Optimizer)
        criterion=="G0" && NativeStrengthReference.configure_g0!(m)
        JuMP.set_optimizer_attribute(m,"MSK_IPAR_NUM_THREADS",2)
        JuMP.set_optimizer_attribute(m,"MSK_DPAR_OPTIMIZER_MAX_TIME",budget)
        for parameter in ("MSK_DPAR_INTPNT_CO_TOL_PFEAS","MSK_DPAR_INTPNT_CO_TOL_DFEAS","MSK_DPAR_INTPNT_CO_TOL_REL_GAP")
            JuMP.set_optimizer_attribute(m,parameter,1e-10)
        end
    elseif ac_solver == "ipopt"
        JuMP.set_optimizer(m,Ipopt.Optimizer)
        JuMP.add_bridge(m,JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)
        JuMP.add_bridge(m,JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
        for (k,v) in (("max_wall_time",budget),("tol",1e-8),("constr_viol_tol",1e-8),
                      ("bound_relax_factor",0.0),("nlp_scaling_min_value",1e-20),("mumps_mem_percent",30))
            JuMP.set_optimizer_attribute(m,k,v)
        end
        if haskey(ENV,"PAPER_A_AC_START_FROM")
            set_ac_terminal_starts!(ac_out,(;m,pm,w,new_q,objective,scale),
                joinpath(root,ENV["PAPER_A_AC_START_FROM"]),receipt["case_sha256"])
            for option in ("bound_push","bound_frac","slack_bound_push","slack_bound_frac")
                JuMP.set_optimizer_attribute(m,option,1e-8)
            end
        end
    else
        JuMP.set_optimizer(m,Gurobi.Optimizer)
        criterion=="G3" && N.configure_bridges!(m,N.optimizer(;backend=:gurobi))
        criterion=="G3" && JuMP.set_optimizer_attribute(m,"NonConvex",0)
        for (k,v) in (("Threads",4),("TimeLimit",budget),("LogFile",joinpath(ac_out,"gurobi.log")),
                      ("NumericFocus",2),("BarHomogeneous",1),("BarQCPConvTol",1e-7),("Seed",1))
            JuMP.set_optimizer_attribute(m,k,v)
        end
    end
    original_angles=ac_solver=="mosek" && ac_label in ("SOC-WR","QCRM") ? scale_ac_angle_rows!(m;original_snapshot) : JuMP.AffExpr[]
    original_currents=ac_solver=="mosek" && ac_label=="QCRM" ? conify_qcrm_currents!(m;original_snapshot) : JuMP.QuadExpr[]
    if get(ENV,"PAPER_A_AC_REFERENCE_ONLY","0")=="1"
        profile["optimization_performed"]=false
        profile["original_audit_snapshot_rows"]=length(original_snapshot.rows)
        profile["dyadically_scaled_angle_rows"]=length(original_angles)
        profile["qcrm_converted_current_rows"]=length(original_currents)
        profile["native_reference_source_sha256"]=sha_file(joinpath(@__DIR__,"NativeStrengthReference.jl"))
        profile["g3_native_readback_source_sha256"]=sha_file(joinpath(@__DIR__,"G3NativeReadback.jl"))
        profile["requested_parameters"]=ac_solver=="mosek" ? Dict(
            "MSK_IPAR_NUM_THREADS"=>2,"MSK_DPAR_OPTIMIZER_MAX_TIME"=>budget,
            "MSK_DPAR_INTPNT_CO_TOL_PFEAS"=>1e-10,"MSK_DPAR_INTPNT_CO_TOL_DFEAS"=>1e-10,
            "MSK_DPAR_INTPNT_CO_TOL_REL_GAP"=>1e-10) : Dict(
            "Threads"=>4,"TimeLimit"=>budget,"NumericFocus"=>2,"BarHomogeneous"=>1,
            "BarQCPConvTol"=>1e-7,"Seed"=>1,"NonConvex"=>0)
        writejson(joinpath(ac_out,"profile.json"),profile)
        export_ac_coordinates(ac_out,(;m,pm,w,new_q,objective,scale))
        JuMP.MOI.Utilities.attach_optimizer(JuMP.backend(m))
        if criterion=="G0"
            matrices=Dict(n=>FP._paper_a_online_expressions!(pm,n).M for n in 1:168)
            report=NativeStrengthReference.export_g0!(ac_out,m,matrices;metadata=profile)
            writejson(joinpath(ac_out,"reference_export.json"),report)
        elseif criterion=="G3"
            report=N.native_certificate_readback!(ac_out,m,certs)
            writejson(joinpath(ac_out,"reference_export.json"),report)
        else
            error("Reference-only route requires G0 or G3")
        end
        return
    end
    if criterion=="G0"
        JuMP.MOI.Utilities.attach_optimizer(JuMP.backend(m))
        dims=WeekStrengthAdmission.psd_sizes(JuMP.unsafe_backend(m))
        dims==fill(37,168) || error("Expected 168 native hourly PSD blocks of order 37")
        writejson(joinpath(ac_out,"native_psd.json"),Dict("dimensions"=>dims,"case_sha256"=>receipt["case_sha256"],
            "dyadically_scaled_angle_rows"=>length(original_angles),"angle_exponent"=>-26,
            "qcrm_rotated_currents"=>length(original_currents)))
    end
    JuMP.optimize!(m)
    result=Dict{String,Any}("formulation"=>ac_label,"strength_method"=>criterion,"case_sha256"=>receipt["case_sha256"],
        "termination"=>string(JuMP.termination_status(m)),"primal_status"=>string(JuMP.primal_status(m)),
        "raw_status"=>JuMP.raw_status(m),"seconds"=>JuMP.solve_time(m),"result_count"=>JuMP.result_count(m))
    for (label,attribute) in (("native_dual_objective",JuMP.dual_objective_value),("native_objective_bound",JuMP.objective_bound))
        value=try attribute(m) catch; nothing end
        value isa Real && isfinite(value) && (result[label*"_EUR2025"]=value*scale)
    end
    writejson(joinpath(ac_out,"outcome.json"),result)
    if JuMP.has_values(m) && JuMP.primal_status(m) in (JuMP.MOI.FEASIBLE_POINT,JuMP.MOI.NEARLY_FEASIBLE_POINT,JuMP.MOI.UNKNOWN_RESULT_STATUS)
        val=JuMP.value
        isempty(original_angles) || (result["max_original_angle_violation"]=max(0.,maximum(val.(original_angles))))
        isempty(original_currents) || (result["max_original_qcrm_current_violation"]=max(0.,maximum(val.(original_currents))))
        open(joinpath(ac_out,"primal.csv"),"w") do io
            println(io,"index,value")
            for v in JuMP.all_variables(m);println(io,JuMP.index(v).value,",",val(v));end
        end
        result["annualized_EUR2025"]=val(objective)
        result["demand_MWh"]=w.demand
        result["wind_pv_MWh"]=val(w.quota)
        result["wind_pv_pct"]=100val(w.quota)/w.demand
        if criterion=="G2"
            result["min_G2_margin"]=minimum(val.(w.margins))
        else
            eigenvalues=[FP.eigmin(FP.Symmetric(val.(FP._paper_a_online_expressions!(pm,n).M))) for n in 1:168]
            result["hourly_min_strength_eigenvalue"]=eigenvalues
            result["min_strength_eigenvalue"]=minimum(eigenvalues)
        end
        branch_excess=0.; kcl_residual=0.; qexcess=0.
        for n in 1:168
            for (i,b) in fp.ref(pm,n,:branch), (f,t) in ((b["f_bus"],b["t_bus"]),(b["t_bus"],b["f_bus"]))
                arc=(i,f,t)
                branch_excess=max(branch_excess,hypot(val(fp.var(pm,n,:p,arc)),val(fp.var(pm,n,:q,arc)))-b["rate_a"])
            end
            for k in (:uc_gscr_block_bus_active_balance,:uc_gscr_block_bus_reactive_balance), row in values(fp.con(pm,n,k))
                kcl_residual=max(kcl_residual,abs(val(JuMP.constraint_object(row).func)-JuMP.normalized_rhs(row)))
            end
            for key in FP._uc_gscr_block_all_device_keys(pm,n)
                q=val(FP._uc_gscr_block_dispatch_variable(pm,n,key,:q))
                bound=qratio*fp.ref(pm,n,key...)["p_block_max"]*val(fp.var(pm,n,:na_block,key))
                qexcess=max(qexcess,abs(q)-bound)
            end
            for project in w.projects
                qexcess=max(qexcess,abs(val(new_q[(n,project.name)]))-qratio*val(project.installed)/w.base)
            end
            for (i,b) in fp.ref(pm,n,:dcline), (f,t,hi) in ((b["f_bus"],b["t_bus"],"qmaxf"),(b["t_bus"],b["f_bus"],"qmaxt"))
                qexcess=max(qexcess,abs(val(fp.var(pm,n,:q_dc,(i,f,t))))-b[hi])
            end
        end
        result["max_branch_excess_MVA"]=w.base*branch_excess
        result["max_bus_residual_pu"]=kcl_residual
        result["max_q_box_excess_MVAr"]=w.base*qexcess
        writejson(joinpath(ac_out,"outcome.json"),result)
        audit_ac_point(ac_out,(;m,pm,w,new_q,objective,scale),val)
    end
    report("AC_week_outcome",result)
end

run_ac_week()
