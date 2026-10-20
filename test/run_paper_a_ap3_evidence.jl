using Test,LinearAlgebra
import JSON,CSV,SHA
import FlexPlan
const D=FlexPlan.PaperADiagnostics
length(ARGS)==1 || error("usage: run_paper_a_ap3_evidence.jl RUN_ROOT")
root=abspath(ARGS[1]);load(path)=JSON.parsefile(joinpath(root,path))
@testset "AP3 saved input solution independent CLI evidence" begin
    runs=load("accepted_suite/runs.json")["runs"]
    @test length(runs)==9*9*2
    @test all(r->r["status"]!="execution_error",runs)
    @test length(unique(r["case_id"] for r in runs))==9
    for r in runs
        case=joinpath(root,"accepted_suite",r["case_id"],"case.json")
        @test D.hashfile(case)==r["case_sha256"]
        if r["status"]=="optimal"
            @test r["primal_status"]=="FEASIBLE_POINT"
            @test isfile(joinpath(root,"accepted_suite",r["solution_file"]))
        elseif r["status"]!="numerical_inconclusive"
            @test get(r,"objective",nothing)===nothing
        end
    end
    recs=load("matrices_final/matrices.json")["records"]
    @test !isempty(recs)
    for rec in recs
        @test rec["affine_reconstruction_residual"]<1e-7
        @test rec["source_base_residual"]<1e-7
        @test rec["producer_B0_residual"]<1e-7
        @test rec["connection_violation"]<1e-5
    end
    metrics=load("metrics_final/metrics.json")["metrics"]
    csv=collect(CSV.File(joinpath(root,"metrics_final","metrics.csv")))
    @test length(metrics)==length(csv)
    @test all(JSON.parse(String(c.value_or_null_json))==m["value_or_null"] for (c,m) in zip(csv,metrics))
    registry=load("metrics_final/metric_registry.json")
    @test Set(keys(registry))==Set(m["metric_id"] for m in metrics)
    @test all(m->all(haskey(m,k) for k in ("validity_status","unit","base","tolerance","equation_reference","independent_method","domain_predicates","AP1_SHA","AP2_SHA","AP3_SHA","parameter_registry_sha256")),metrics)
    coverage=Dict{String,Any}()
    for id in sort(collect(keys(registry)))
        rows=filter(m->m["metric_id"]==id,metrics)
        states=sort(unique(m["validity_status"] for m in rows))
        computed=count(m->m["value_or_null"]!==nothing,rows)
        @test !isempty(registry[id]["formula"]) && !isempty(registry[id]["unit"])
        # Missing conventions/attributes must remain visibly non-successful.
        @test all(m->m["value_or_null"]!==nothing || m["validity_status"]!="valid",rows)
        coverage[id]=Dict("records"=>length(rows),"computed"=>computed,"statuses"=>states)
    end
    # Positive and rejected M1 domains complement the infeasible study runs.
    B=[1. -.5;-.5 1.]; p=[.1,.1]
    positive=D.evaluate(B,p,1.;Bmin=[.6 -.5;-.5 .6])
    negative=D.evaluate(B,p,1.;Bmin=2B)
    @test positive["C.M1"]["status"]=="valid" && positive["C.M1"]["value"]
    @test negative["C.M1"]["status"]=="domain_invalid_unenforced_Bmin"
    update=D.inverse_updates(B,.01Matrix{Float64}(I,2,2))
    outside=D.inverse_updates(B,3Matrix{Float64}(I,2,2))
    @test update["remainder_bound"]!==nothing && update["actual_error"]<=update["remainder_bound"]
    @test outside["remainder_bound"]===nothing && !outside["trust_region_norm_valid"]
    if haskey(ENV,"AP3_METRIC_COVERAGE_OUTPUT")
        path=ENV["AP3_METRIC_COVERAGE_OUTPUT"];ispath(path) && error("coverage output exists")
        open(path,"w") do io
            JSON.print(io,Dict("schema"=>D.SCHEMA,"metrics"=>coverage,"M1_positive_and_negative_fixture_verified"=>true,"D_remainder_bound_inside_and_outside_fixtures_verified"=>true),2)
        end
    end
    for group in ('A','B','C','D','E','F')
        @test any(startswith(id,string(group)*".") for id in keys(registry))
    end
    economics=load("planning_final/planning.json")["records"]
    @test !isempty(economics)
    horizon_events=filter(m->m["metric_id"]=="E.events",metrics)
    @test length(horizon_events)==length(economics)
    @test all(m->m["snapshot_id"]=="all" && m["scope"]=="case_or_horizon",horizon_events)
    for r in economics
        # Independent conic/mixed-integer numerical accuracy; report raw values.
        @test r["objective_residual"]<1.
        @test r["power_balance_MW"]<1e-3
        @test r["SOC_residual_MWh"]<1e-3
        @test r["terminal_residual_MWh"]<1e-3
        @test r["bounds_violation_blocks"]<1e-5
    end
    comp=load("comparisons_final/comparisons.json")["records"]
    for r in comp
        if r["formulation"]=="G3" && r["status"]=="optimal" && r["relative_delta"]!==nothing
            @test abs(r["relative_delta"])<1e-5
            @test r["cross_G0"] && r["cross_G3"]
        end
    end
    cert=load("certificates_final/certificates.json")["records"]
    @test length(cert)==length(recs)
    bench=load("benchmarks_final/benchmark.json")["records"]
    @test length(bench)==8
    @test all(r->r["termination"]=="OPTIMAL",bench)
    enum=load("enumeration_final/integer_enumeration.json")["certificate"]
    @test all(enum[k]["complete"] for k in ("G0","G3","M0"))
    @test enum["G0"]["optimum"]==enum["G3"]["optimum"]
    # Semantic replay is independent of serialization order and timing.
    @test load("matrices_final/matrices.json")==load("matrices_replay/matrices.json")
    @test D.hashfile(joinpath(root,"matrices_final","matrices.json"))==D.hashfile(joinpath(root,"matrices_replay","matrices.json"))
end
