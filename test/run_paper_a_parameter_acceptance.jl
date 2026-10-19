using Test, JuMP, LinearAlgebra, SHA, TOML, CSV
import FlexPlan as FP
import PowerModels as PM
import JSON, HiGHS
length(ARGS)==2 || error("usage: run_paper_a_parameter_acceptance.jl PRODUCER_ROOT OUTPUT_JSON")
producer=abspath(ARGS[1]);root=joinpath(producer,"data","paper_a_study")
registry=joinpath(root,"parameter_registry.csv");scenarios=joinpath(root,"study_scenarios.toml")
config=TOML.parsefile(scenarios)
rows=Any[]
event_value(v,key)=key in (v isa AbstractDict ? keys(v) : axes(v,1)) ? JuMP.value(v[key]) : 0.
function template_for(data,scope)
    assignments=Dict{Tuple{Symbol,Any},FP.AbstractBlockDeviceFormulation}()
    for table in ("gen","storage","ne_storage"),d in values(get(data["nw"]["1"],table,Dict()))
        haskey(d,"source_class") || continue
        f=table!="gen" ? FP.BlockStorageParticipation() : d["source_class"]=="SYN" ? FP.BlockThermalCommitment() : FP.BlockRenewableParticipation()
        assignments[(Symbol(table),d["carrier"])]=f
    end
    FP.UCGSCRBlockTemplate(assignments,FP.GershgorinGSCR();paper_a_validation_scope=scope,storage_cost_policy=:discharge)
end
function build(data,scope;relax=false)
    template=template_for(data,scope)
    PM.instantiate_model(data,PM.DCPPowerModel,
        m->FP.build_uc_gscr_block_integration(m;template,relax_block_variables=relax,storage_terminal_policy=:fixed_initial);
        ref_extensions=[FP.ref_add_gen!,FP.ref_add_storage!,FP.ref_add_ne_storage!,
            (r,d)->FP.ref_add_uc_gscr_block!(r,d;paper_a_validation_scope=scope)])
end
function dimensions!(data,n)
    FP.add_dimension!(data,:hour,n)
    FP.add_dimension!(data,:scenario,Dict(1=>Dict{String,Any}("probability"=>1.)))
    FP.add_dimension!(data,:year,1;metadata=Dict{String,Any}("scale_factor"=>1))
end
@testset "Strang B registered AP1 to AP2 parametric acceptance" begin
    for scenario in config["scenarios"]
        id=scenario["id"];n=scenario["snapshots"]
        folder=joinpath(root,"cases",id,"study_$(n)snap");path=joinpath(folder,"case.json")
        manifest=JSON.parsefile(joinpath(folder,"case_manifest.json"))
        raw=JSON.parsefile(path)
        @test bytes2hex(sha256(read(path)))==manifest["case_sha256"]
        @test manifest["parameter_qualification"]["parameter_registry_sha256"]==bytes2hex(sha256(read(registry)))
        @test manifest["parameter_qualification"]["scenario_config_sha256"]==bytes2hex(sha256(read(scenarios)))
        data=FP.parse_file(path);dimensions!(data,n)
        @test_throws ArgumentError FP.scale_paper_a_costs!(deepcopy(data))
        @test FP.register_paper_a_parameters!(data,registry,scenarios)===data
        if id=="reference_3snap"
            for field in ("mu_fl","nmax","cost_inv_per_mw","a_conn")
                bad=deepcopy(data);d=first(filter(d->field!="mu_fl" || d["source_class"]=="GFL",collect(values(bad["nw"]["1"]["gen"]))))
                d[field]=get(d,field,0.) isa Real ? get(d,field,0.)+1 : 2.
                @test_throws ArgumentError FP._paper_a_validate_registered!(bad)
            end
            for field in ("parameter_registry_sha256","scenario_config_sha256","version","qualification_scope","qualification_status","evidence_class","parameter_registry_id","scenario_id")
                bad=deepcopy(data);bad["paper_a_parameter_qualification"][field]="invalid"
                @test_throws ArgumentError FP.register_paper_a_parameters!(bad,registry,scenarios)
            end
            bad=deepcopy(data);bad["paper_a_network"]["passive_domain_issues"]=["noninductive_or_invalid_branch:injected"]
            @test_throws ArgumentError FP.register_paper_a_parameters!(bad,registry,scenarios)
            bad=deepcopy(data);delete!(bad,"_paper_a_parameter_registration")
            @test_throws ArgumentError build(bad,:parametric_study)
            @test_throws ArgumentError build(data,:strict)
            @test_throws ArgumentError build(data,:synthetic_regression)
            mktempdir() do dir
                canonical=collect(CSV.File(registry;types=String))
                missing_path=joinpath(dir,"incomplete.csv")
                CSV.write(missing_path,filter(r->!(r.study_scenario==id && r.field=="mu_fl"),canonical))
                bad=deepcopy(data);bad["paper_a_parameter_qualification"]["parameter_registry_sha256"]=bytes2hex(sha256(read(missing_path)))
                @test_throws ArgumentError FP.register_paper_a_parameters!(bad,missing_path,scenarios)
            end
        end
        FP.scale_paper_a_costs!(data)
        @test_throws ArgumentError FP.scale_paper_a_costs!(data)
        @test FP._paper_a_validate_registered!(data)
        if id=="reference_3snap"
            bad=deepcopy(data);first(values(bad["nw"]["1"]["gen"]))["startup_cost_per_mw"]+=1
            @test_throws ArgumentError build(bad,:parametric_study)
        end
        for relax in (false,true)
            pm=build(deepcopy(data),:parametric_study;relax)
            JuMP.set_optimizer(pm.model,HiGHS.Optimizer)
            JuMP.set_optimizer_attribute(pm.model,"mip_rel_gap",1e-8)
            JuMP.set_optimizer_attribute(pm.model,"time_limit",120.)
            JuMP.set_silent(pm.model);JuMP.optimize!(pm.model)
            status=JuMP.termination_status(pm.model)
            row=Dict{String,Any}("scenario_id"=>id,"snapshots"=>n,"physical_hours"=>3n,"relaxed"=>relax,
                "case_sha256"=>manifest["case_sha256"],"registry_sha256"=>bytes2hex(sha256(read(registry))),
                "scenario_config_sha256"=>bytes2hex(sha256(read(scenarios))),"termination"=>string(status),
                "primal"=>string(JuMP.primal_status(pm.model)),"validation_scope"=>"parametric_study","empirical_approved"=>false)
            @test status==JuMP.MOI.OPTIMAL
            @test JuMP.primal_status(pm.model)==JuMP.MOI.FEASIBLE_POINT
            if status!=JuMP.MOI.OPTIMAL
                push!(rows,row);continue
            end
            power=0.;soc=0.;g1=0.;srcres=0.;expres=0.;connection=0.;integer=0.;bounds=0.
            dispatch=0.;events=0.;investment=0.;min_eig=Inf;schur=0.;terminal=0.
            installed=Dict{String,Any}()
            for (table,i) in keys(PM.ref(pm,1,:paper_a_coefficients))
                d=raw["nw"]["1"][String(table)][string(i)]
                ni=JuMP.value(PM.var(pm,1,:n_block,(table,i)))
                investment+=d["cost_inv_per_mw"]*scenario["investment_period_fraction"]*d["p_block_max_MW"]*(ni-d["n0"])
                installed[d["name"]]=Dict("n0"=>d["n0"],"installed"=>ni,"nmax"=>d["nmax"],"new_MW"=>(ni-d["n0"])*d["p_block_max_MW"])
                bounds=max(bounds,max(0.,d["n0"]-ni,ni-d["nmax"]))
                relax || (integer=max(integer,abs(ni-round(ni))))
            end
            for t in 1:n
                r=PM.ref(pm,t,:paper_a_regional);base=raw["baseMVA"]
                bs=zeros(length(r.regions));pfl=zeros(length(r.regions))
                schur=max(schur,r.B0_reference_residual)
                @test !r.theorem_domain_valid
                for (table,i) in keys(PM.ref(pm,t,:paper_a_coefficients))
                    d=raw["nw"][string(t)][String(table)][string(i)]
                    on=JuMP.value(PM.var(pm,t,:na_block,(table,i)))
                    ni=JuMP.value(PM.var(pm,t,:n_block,(table,i)))
                    region=findfirst(==(d["region_id"]),r.regions)
                    if d["source_class"]=="GFL";pfl[region]+=d["mu_fl"]*d["p_block_max_MW"]/base*on
                    else;bs[region]+=d["mu_str"]*d["native_source_MVA"]/(base*d["x_src"])*on;end
                    connection=max(connection,max(0.,on-d["a_conn"]*ni))
                    relax || (integer=max(integer,abs(on-round(on))))
                    su=get(PM.var(pm,t),:su_block,Dict());sd=get(PM.var(pm,t),:sd_block,Dict())
                    events+=d["p_block_max_MW"]*(d["startup_cost_per_mw"]*event_value(su,(table,i))+
                        d["shutdown_cost_per_mw"]*event_value(sd,(table,i)))
                    if table==:gen
                        dispatch+=3*d["marginal_cost"]*base*JuMP.value(PM.var(pm,t,:pg,i))
                    else
                        scsym=table==:storage ? :sc : :sc_ne;sdsym=table==:storage ? :sd : :sd_ne;sesym=table==:storage ? :se : :se_ne
                        se=base*JuMP.value(PM.var(pm,t,sesym,i));sc=base*JuMP.value(PM.var(pm,t,scsym,i));sdv=base*JuMP.value(PM.var(pm,t,sdsym,i))
                        prev=t==1 ? raw["nw"]["1"][String(table)][string(i)]["energy"] : base*JuMP.value(PM.var(pm,t-1,sesym,i))
                        soc=max(soc,abs(se-prev-3*(d["charge_efficiency"]*sc-sdv/d["discharge_efficiency"])))
                        dispatch+=3*d["marginal_cost"]*sdv
                        t==n && (terminal=max(terminal,abs(se-raw["nw"]["1"][String(table)][string(i)]["energy"])))
                    end
                end
                srcres=max(srcres,maximum(abs.(bs-JuMP.value.(pm.ext[:paper_a_online][t].b_src))))
                expres=max(expres,maximum(abs.(pfl-JuMP.value.(pm.ext[:paper_a_online][t].p_fl))))
                for i in eachindex(bs)
                    sigma=r.B0[i,i]-sum(abs(r.B0[i,j]) for j in eachindex(bs) if i!=j;init=0.)
                    g1=max(g1,max(0.,scenario["g_min"]*pfl[i]-sigma-bs[i]))
                end
                min_eig=min(min_eig,eigmin(Symmetric(r.B0+Diagonal(bs-scenario["g_min"]*pfl))))
                ref=PM.ref(pm,t)
                for bus in keys(ref[:bus])
                    flow=sum(JuMP.value(PM.var(pm,t,:p,a)) for a in ref[:bus_arcs][bus];init=0.)+
                        sum(JuMP.value(PM.var(pm,t,:p_dc,a)) for a in ref[:bus_arcs_dc][bus];init=0.)
                    generation=sum(JuMP.value(PM.var(pm,t,:pg,g)) for g in ref[:bus_gens][bus];init=0.)
                    consumption=sum(JuMP.value(PM.var(pm,t,:ps,s)) for s in ref[:bus_storage][bus];init=0.)
                    load=sum(ref[:load][l]["pd"] for l in ref[:bus_loads][bus];init=0.)
                    power=max(power,abs(flow-generation+consumption+load)*base)
                end
            end
            costres=abs(JuMP.objective_value(pm.model)-investment-dispatch-events)
            @test power<1e-6 && soc<1e-6 && terminal<1e-6
            @test g1<1e-7 && srcres<1e-8 && expres<1e-8 && schur<1e-10
            @test connection<1e-7 && integer<1e-6 && bounds<1e-7
            @test costres<max(1e-5,1e-9*abs(JuMP.objective_value(pm.model)))
            merge!(row,Dict("objective"=>JuMP.objective_value(pm.model),"investment"=>investment,"dispatch"=>dispatch,"events"=>events,
                "cost_residual"=>costres,"power_balance_MW_residual"=>power,"soc_MWh_residual"=>soc,"terminal_MWh_residual"=>terminal,
                "G1_violation"=>g1,"source_expression_residual"=>srcres,"exposure_expression_residual"=>expres,"B0_residual"=>schur,
                "connection_violation"=>connection,"integrality_residual"=>integer,"block_bound_violation"=>bounds,"minimum_M_eigenvalue"=>min_eig,
                "relative_gap"=>relax ? nothing : JuMP.relative_gap(pm.model),"installed_assets"=>installed,"theorem_domain_valid"=>false))
            push!(rows,row)
            # Preserve completed solves even if a later sensitivity fails.
            open(ARGS[2],"w") do io;JSON.print(io,Dict("cases"=>rows,"registry_sha256"=>bytes2hex(sha256(read(registry))),"scenario_config_sha256"=>bytes2hex(sha256(read(scenarios)))),2);end
        end
    end
end
