include("../../../scripts/paper_a/AP3Pipeline.jl")
const P=AP3Pipeline
root=@__DIR__;readj(p)=P.readjson(joinpath(root,p))
metrics=readj("metrics_final/metrics.json")["metrics"]
maxmetric(id)=begin a=[m["value"] for m in metrics if m["metric_id"]==id && m["value"] isa Real && isfinite(m["value"])];isempty(a) ? nothing : maximum(a) end
status=Dict{String,Int}();for m in metrics;status[m["status"]]=get(status,m["status"],0)+1;end
plans=readj("planning_final/planning.json")["records"];comparisons=readj("comparisons_final/comparisons.json")["records"]
resids=Dict(k=>maximum(r[k] for r in plans if r[k] isa Real) for k in ("objective_residual","power_balance_MW","SOC_residual_MWh","terminal_residual_MWh","UC_transition_residual","thermal_violation_MW","bounds_violation_blocks","integrality_residual"))
portfolios=Any[]
for r in plans
 r["case_id"]=="reference_3snap" && r["relaxed"] || continue
 region=Dict{String,Float64}();cls=Dict{String,Float64}()
 for a in r["portfolio"];region[a["region"]]=get(region,a["region"],0.)+a["new_MW"];cls[a["source_class"]]=get(cls,a["source_class"],0.)+a["new_MW"];end
 push!(portfolios,Dict("formulation"=>r["formulation"],"investment"=>r["investment"],"new_MW_by_region"=>region,"new_MW_by_class"=>cls))
end
ge=[abs(r["relative_delta"]) for r in comparisons if r["relaxed"] && r["formulation"]=="G3" && r["relative_delta"]!==nothing]
g1=[r["relative_delta"] for r in comparisons if r["relaxed"] && r["formulation"]=="G1" && r["relative_delta"]!==nothing]
m0=Dict{String,Int}();for m in metrics;if m["metric_id"]=="C.M0" && m["value"]===false;m0[m["formulation_id"]]=get(m0,m["formulation_id"],0)+1;end;end
bounds=readj("integer_bound_audit.json")["records"]
maxima=Dict(id=>maxmetric(id) for id in ("A.affine_reconstruction_residual","A.producer_B0_residual","A.schur_residual","A.source_base_residual","A.connection_violation","A.exposure_roundoff_correction","C.solve_residual","B.G3_reconstruction_residual","F.dual_cone_violation","F.complementarity_residual"))
summary=Dict("schema"=>P.SCHEMA,"metrics_count"=>length(metrics),"metric_ids"=>length(unique(m["metric_id"] for m in metrics)),"snapshot_records"=>length(readj("matrices_final/matrices.json")["records"]),"planning_records"=>length(plans),"status_counts"=>status,"max_metric_residuals"=>maxima,"planning_max_residuals"=>resids,"G0_G3_continuous_max_relative_objective_difference"=>maximum(ge),"G1_continuous_premium_range"=>[minimum(g1),maximum(g1)],"M0_false_states_by_formulation"=>m0,"integer_reference_pass"=>count(r->r["integer_optimum_certified"],bounds),"integer_reference_total"=>length(bounds),"integer_reference_gaps"=>Dict(r["case_id"]=>r["original_currency_relative_gap"] for r in bounds),"reference_3snap_continuous_portfolios"=>portfolios,"packages"=>readj("dual_audit_suite/provenance.json")["packages"])
P.writejson(joinpath(root,"validation_summary.json"),summary)
