# Read-only reconciliation of externally generated AP1 cases. A blocked input
# is recorded as BLOCKED, never as a passing synthetic consumer solve.
import FlexPlan as FP
import JSON
using SHA

length(ARGS)==2 || error("usage: paper_a_producer_gate.jl PRODUCER_DATA_ROOT OUTPUT_JSON")
rows=Any[]
for (family,prefix) in (("paper_a_ap1","base_s_5_ap1"),("paper_a_ap1_synthetic","synthetic_ap1")), n in (3,6,24)
    folder=joinpath(ARGS[1],family,"$(prefix)_$(n)snap")
    path=joinpath(folder,"case.json")
    row=Dict{String,Any}("case"=>path,"family"=>family,"snapshots"=>n,"status"=>"NOT_EXECUTED")
    if !isfile(path)
        row["status"]="BLOCKED";row["reason"]="missing producer fixture"
        push!(rows,row);continue
    end
    row["case_sha256"]=bytes2hex(sha256(read(path)))
    raw=JSON.parsefile(path;dicttype=Dict{String,Any})
    mf=joinpath(folder,"case_manifest.json")
    if isfile(mf)
        row["manifest_sha256"]=bytes2hex(sha256(read(mf)))
        row["manifest"]=JSON.parsefile(mf;dicttype=Dict{String,Any})
    end
    reasons=String[]
    try
        FP.prepare_paper_a_data!(raw)
        row["parser_status"]="PASSED"
        sn=raw["nw"]["1"]
        r=FP.PaperARegional.network_reference(raw["paper_a_network"],sn["bus"],raw["baseMVA"])
        row["B0_comparison_inf"]=r.B0_reference_residual
        row["regional_reference_status"]="PASSED"
    catch e
        row["regional_reference_status"]="BLOCKED"
        push!(reasons,sprint(showerror,e))
    end
    # A passive numerical comparison is still informative when inventory or
    # grounding is unverified. Its predicate remains false and it cannot enter
    # the optimization reference builder, which always uses strict validation.
    try
        sn=raw["nw"]["1"]
        r=FP.PaperARegional.network_reference(raw["paper_a_network"],sn["bus"],raw["baseMVA"];diagnostic_only=true)
        row["diagnostic_B0_comparison_inf"]=r.B0_reference_residual
        row["diagnostic_schur_residual_inf"]=r.schur_residual
        row["diagnostic_theorem_domain_valid"]=r.theorem_domain_valid
    catch e
        row["diagnostic_matrix_error"]=sprint(showerror,e)
    end
    for (t,sn) in raw["nw"], table in ("gen","storage","ne_storage"), (id,dev) in get(sn,table,Dict())
        haskey(dev,"source_class") || continue
        try
            FP.PaperARegional.validate_source(dev)
        catch e
            msg="$table/$id: "*sprint(showerror,e)
            msg in reasons || push!(reasons,msg)
        end
    end
    try
        FP.scale_paper_a_costs!(raw)
        row["cost_preparation_status"]="PASSED"
    catch e
        row["cost_preparation_status"]="BLOCKED"
        push!(reasons,sprint(showerror,e))
    end
    row["status"]=isempty(reasons) ? "REFERENCE_READY_SOLVE_NOT_EXECUTED" : "BLOCKED"
    row["consumer_solve_status"]="NOT_EXECUTED"
    row["blockers"]=reasons
    push!(rows,row)
    println(family,"/",n," ",row["status"]," ",join(reasons,"; "))
end
open(ARGS[2],"w") do io
    JSON.print(io,Dict("producer_consumer_gate"=>"BLOCKED","cases"=>rows),2)
end
