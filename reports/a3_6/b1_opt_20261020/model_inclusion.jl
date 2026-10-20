using JuMP,Test,SHA
import JSON
include(joinpath(ARGS[1],"scripts/paper_a/AP3Pipeline.jl"))
const P=AP3Pipeline;const R=ARGS[2];mkpath(R);rows=Any[]
root=joinpath(ARGS[1],"reports/ap3_runs/20261020_macro/accepted_suite")
for id in sort([basename(d) for d in readdir(root;join=true) if isdir(d)&&isfile(joinpath(d,"case.json"))])
    dir=joinpath(root,id);raw,data,scope=P.prepare(joinpath(dir,"case.json");registry=joinpath(dir,"parameter_registry.csv"),scenarios=joinpath(dir,"study_scenarios.toml"))
    for fid in ("BASE","G0","G3")
        pm=P.build(data,P.formulation(fid,Dict()),scope;relaxed=fid=="BASE")
        file=id*"_"*fid*".mof.json";write_to_file(pm.model,joinpath(R,file))
        push!(rows,Dict("case_id"=>id,"formulation"=>fid,"file"=>file,"sha256"=>bytes2hex(SHA.sha256(read(joinpath(R,file))))))
    end
    open(io->JSON.print(io,rows,2),joinpath(R,"manifest.json"),"w");println(id," common-model exports complete");flush(stdout)
end
