using JuMP
import JSON
include(joinpath(ARGS[1],"scripts/paper_a/AP3Pipeline.jl"))
const P=AP3Pipeline;const R=ARGS[2];mkpath(R)
struct SnapshotComplete <: Exception end
root=joinpath(ARGS[1],"reports/ap3_runs/20261020_macro/accepted_suite")
for id in sort([basename(d) for d in readdir(root;join=true) if isdir(d)&&isfile(joinpath(d,"case.json"))])
    dir=joinpath(root,id);raw,data,scope=P.prepare(joinpath(dir,"case.json");registry=joinpath(dir,"parameter_registry.csv"),scenarios=joinpath(dir,"study_scenarios.toml"))
    for (mode,scale) in [("default",nothing),("cost_conditioned",JSON.parsefile(joinpath(ARGS[3],"lp_bounds",id*"_dual_input.json"))["stats"]["objective"])]
        pm=P.build(data,P.FP.ExactEdgeSOCGSCR(),scope;relaxed=false)
        set_optimize_hook(pm.model,(m;kwargs...)->begin
            write_to_file(m,joinpath(R,id*"_"*mode*".mof.json"))
            throw(SnapshotComplete())
        end)
        try P.solve!(pm,P.pajarito_optimizer();objective_scale=scale);error("snapshot hook did not execute")
        catch e;e isa SnapshotComplete || rethrow();end
    end
    println(id," objective-construction snapshots only; no solve claimed");flush(stdout)
end
