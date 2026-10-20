include("../../../scripts/paper_a/AP3Pipeline.jl")
const P=AP3Pipeline
root=@__DIR__;rows=P.readjson(joinpath(root,"suite_final","runs.json"))["runs"];rr=P.readjson(joinpath(root,"integer_rechecks_roundoff","runs.json"))["runs"]
result=Any[]
for recheck in rr
 source=only(filter(r->r["case_id"]==recheck["case_id"]&&!r["relaxed"]&&r["formulation"]==recheck["reference_formulation"],rows))
 raw=P.readjson(joinpath(root,"suite_final",source["case_id"],"case.json"))
 a=P.planning(raw,P.readjson(joinpath(root,"suite_final",source["solution_file"])),source)
 b=P.planning(raw,P.readjson(joinpath(root,"integer_rechecks_roundoff",recheck["solution_file"])),recheck)
 push!(result,Dict("source"=>a,"fixed"=>b,"gap"=>recheck["relative_gap"]))
end
P.writejson(joinpath(root,"integer_recheck_diagnostics.json"),result)

