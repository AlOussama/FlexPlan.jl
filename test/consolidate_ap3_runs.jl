# Evidence-only consolidation: retain all original attempts; replace complete
# continuous G0/G3 run+solution records with the later dual-audited repetitions.
import JSON,SHA
length(ARGS)==1 || error("usage: consolidate_ap3_runs.jl RUN_ROOT")
root=abspath(ARGS[1]);old=joinpath(root,"suite_final");new=joinpath(root,"dual_audit_suite");out=joinpath(root,"accepted_suite")
ispath(out) && error("accepted output already exists")
readj(p)=JSON.parsefile(p)
runs=readj(joinpath(old,"runs.json"))["runs"];repeats=readj(joinpath(new,"runs.json"))["runs"]
length(runs)==162 && length(repeats)==18 || error("incomplete source suite")
all(r->r["status"]=="optimal",repeats) || error("dual audit has inconclusive runs")
for repeat in repeats;repeat["source_run_directory"]="dual_audit_suite";end
m1=joinpath(root,"m1_audit_suite")
if isdir(m1)
    rr=readj(joinpath(m1,"runs.json"))["runs"];length(rr)==18 || error("incomplete M1 audit")
    for r in rr;r["source_run_directory"]="m1_audit_suite";end
    append!(repeats,rr)
end
cp(old,out)
for r in runs
    r["source_run_directory"]="suite_final";r["source_AP3_SHA"]=readj(joinpath(old,"provenance.json"))["AP3_SHA"]
end
for repeat in repeats
    index=findall(r->r["case_id"]==repeat["case_id"]&&r["formulation"]==repeat["formulation"]&&r["relaxed"]==repeat["relaxed"],runs)
    length(index)==1 || error("ambiguous repetition")
    prior=runs[only(index)]
    all(prior[k]==repeat[k] for k in ("case_sha256","parameters","registry_sha256","scenario_config_sha256","exposure")) || error("repetition changed comparison scope")
    repeatroot=joinpath(root,repeat["source_run_directory"])
    repeat["source_AP3_SHA"]=readj(joinpath(repeatroot,"provenance.json"))["AP3_SHA"]
    runs[only(index)]=repeat
    repeat["status"]=="optimal" && cp(joinpath(repeatroot,repeat["solution_file"]),joinpath(out,repeat["solution_file"]);force=true)
end
recheck=joinpath(root,isdir(joinpath(root,"integer_rechecks_conditioned")) ? "integer_rechecks_conditioned" : "integer_rechecks")
if isdir(recheck)
    for row in readj(joinpath(recheck,"runs.json"))["runs"]
        index=only(findall(r->r["case_id"]==row["case_id"]&&r["formulation"]==row["formulation"]&&!r["relaxed"],runs))
        row["case_sha256"]==runs[index]["case_sha256"] && row["parameters"]==runs[index]["parameters"] || error("integer recheck scope mismatch")
        row["source_run_directory"]=basename(recheck);runs[index]=row
        cp(joinpath(recheck,row["solution_file"]),joinpath(out,row["solution_file"]);force=true)
    end
end
open(joinpath(out,"runs.json"),"w") do io;JSON.print(io,Dict("schema"=>"paper_a_ap3/1.0","runs"=>runs),2);end
open(joinpath(out,"consolidation.json"),"w") do io
    JSON.print(io,Dict("scope"=>"evidence_only_no_new_solve","original_suite"=>"suite_final","dual_repetition"=>"dual_audit_suite","policy"=>"complete continuous G0/G3 record and solution replacement after identical case/parameter/exposure/hash checks","source_provenance"=>[readj(joinpath(p,"provenance.json")) for p in (old,new)]),2)
end
