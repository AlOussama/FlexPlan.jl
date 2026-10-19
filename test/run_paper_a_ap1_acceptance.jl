using Test, JuMP, LinearAlgebra, SHA
import FlexPlan as FP
import PowerModels as PM
import JSON, HiGHS

length(ARGS)==2 || error("usage: run_paper_a_ap1_acceptance.jl PINNED_PRODUCER_DATA_ROOT OUTPUT_JSON")
rows=Any[]
@testset "Pinned AP1 synthetic producer to AP2 solver" begin
    for n in (3,6,24)
        folder=joinpath(ARGS[1],"paper_a_ap1_synthetic","synthetic_ap1_$(n)snap")
        path=joinpath(folder,"case.json")
        isfile(path) || error("BLOCKED: required pinned AP1 fixture missing: $path")
        manifest=JSON.parsefile(joinpath(folder,"case_manifest.json");dicttype=Dict{String,Any})
        @test bytes2hex(sha256(read(path)))==manifest["case_sha256"]
        for relax in (false,true)
            data=FP.parse_file(path)
            FP.add_dimension!(data,:hour,n)
            FP.add_dimension!(data,:scenario,Dict(1=>Dict{String,Any}("probability"=>.5)))
            FP.add_dimension!(data,:year,1;metadata=Dict{String,Any}("scale_factor"=>1))
            FP.scale_paper_a_costs!(data)
            for sn in values(data["nw"]);sn["g_min"]=3.0;end
            template=FP.UCGSCRBlockTemplate(Dict((:gen,"CCGT")=>FP.BlockThermalCommitment(),
                (:gen,"onwind")=>FP.BlockRenewableParticipation(),(:storage,"battery")=>FP.BlockStorageParticipation()),
                FP.GershgorinGSCR();paper_a_validation_scope=:synthetic_regression,storage_cost_policy=:discharge)
            pm=PM.instantiate_model(data,PM.DCPPowerModel,
                m->FP.build_uc_gscr_block_integration(m;template,relax_block_variables=relax,storage_terminal_policy=:fixed_initial);
                ref_extensions=[FP.ref_add_gen!,FP.ref_add_storage!,FP.ref_add_ne_storage!,
                    (r,d)->FP.ref_add_uc_gscr_block!(r,d;paper_a_validation_scope=template.paper_a_validation_scope)])
            JuMP.set_optimizer(pm.model,HiGHS.Optimizer);JuMP.set_silent(pm.model);JuMP.optimize!(pm.model)
            status=JuMP.termination_status(pm.model)
            row=Dict{String,Any}("snapshots"=>n,"relaxed"=>relax,"case_sha256"=>manifest["case_sha256"],
                "termination"=>string(status),"primal"=>string(JuMP.primal_status(pm.model)),
                "dual"=>string(JuMP.dual_status(pm.model)),"validation_scope"=>"synthetic_regression",
                "external_study_domain_approved"=>false,"B0_reference_residual"=>PM.ref(pm,1,:paper_a_regional).B0_reference_residual)
            @test PM.ref(pm,1,:paper_a_regional).B0≈[.5 -.5;-.5 .5]
            @test PM.ref(pm,1,:paper_a_regional).S_base_MVA==200.0
            @test PM.ref(pm,1,:paper_a_regional).regions==["A","C"]
            @test !PM.ref(pm,1,:paper_a_regional).theorem_domain_valid
            @test all(sn["gen"]["1"]["electrical_interface_evidence"]=="unverified" for sn in values(data["nw"]))
            if relax
                @test status==JuMP.MOI.OPTIMAL
                @test JuMP.primal_status(pm.model)==JuMP.MOI.FEASIBLE_POINT
                residual=0.0;socres=0.0;g1res=0.0;source_res=0.0;exposure_res=0.0
                dispatch=0.0;events=0.0;investment=0.0
                for (table,id) in keys(PM.ref(pm,1,:paper_a_coefficients))
                    dev=PM.ref(pm,1,table,id)
                    investment+=dev["cost_inv_per_mw"]*dev["p_block_max_MW"]*(JuMP.value(PM.var(pm,1,:n_block,(table,id)))-dev["n0"])
                end
                for t in 1:n
                    online=JuMP.value(PM.var(pm,t,:na_block,(:gen,1)))
                    pg=JuMP.value(PM.var(pm,t,:pg,1))
                    ps=JuMP.value(PM.var(pm,t,:ps,1))
                    wind=JuMP.value(PM.var(pm,t,:pg,2))
                    sc=JuMP.value(PM.var(pm,t,:sc,1));sd=JuMP.value(PM.var(pm,t,:sd,1));se=JuMP.value(PM.var(pm,t,:se,1))
                    prev=t==1 ? 25/200 : JuMP.value(PM.var(pm,t-1,:se,1))
                    residual=max(residual,abs(pg+wind-ps-10/200))
                    socres=max(socres,abs(se-prev-3*(.95*sc-sd/.9)))
                    expected_source=1.25*(256.5/200/.2)*online
                    source_res=max(source_res,abs(JuMP.value(pm.ext[:paper_a_online][t].b_src[1])-expected_source))
                    exp_fl=1.5*(18/200)*JuMP.value(PM.var(pm,t,:na_block,(:gen,2)))+.7*(25/200)*JuMP.value(PM.var(pm,t,:na_block,(:storage,1)))
                    exposure_res=max(exposure_res,abs(JuMP.value(pm.ext[:paper_a_online][t].p_fl[2])-exp_fl))
                    g1res=max(g1res,max(0.,3*exp_fl),max(0.,-expected_source))
                    dispatch+=182.5*40*200*pg
                    events+=(8760/72*.5)*256.5*(2*JuMP.value(PM.var(pm,t,:su_block,(:gen,1)))+3*JuMP.value(PM.var(pm,t,:sd_block,(:gen,1))))
                end
                costres=abs(JuMP.objective_value(pm.model)-investment-dispatch-events)
                @test residual<1e-8 && socres<1e-8 && g1res<1e-8 && source_res<1e-8 && exposure_res<1e-8
                @test costres<1e-5
                @test events>0
                merge!(row,Dict("objective"=>JuMP.objective_value(pm.model),"investment"=>investment,"dispatch"=>dispatch,"events"=>events,
                    "power_balance_residual"=>residual,"soc_residual"=>socres,"G1_violation"=>g1res,
                    "source_expression_residual"=>source_res,"exposure_expression_residual"=>exposure_res,"cost_residual"=>costres,
                    "relative_gap"=>JuMP.relative_gap(pm.model)))
            else
                # No local source at region C: positive G1 forces both GFL
                # devices offline. One integer SYN block has minimum 128.25 MW
                # versus 10 MW load, so the published integer case is infeasible.
                @test status==JuMP.MOI.INFEASIBLE
                row["infeasibility_explanation"]="G1 forces region-C GFL offline; integer SYN minimum 128.25 MW exceeds 10 MW load"
            end
            push!(rows,row)
        end
    end
end
open(ARGS[2],"w") do io;JSON.print(io,Dict("synthetic_producer_cases"=>rows),2);end
