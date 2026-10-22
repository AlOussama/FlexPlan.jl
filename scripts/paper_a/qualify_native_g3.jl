#= Fresh finite-domain G3 qualification; always use a new external output directory.
Usage: julia --project=. scripts/paper_a/qualify_native_g3.jl REPO OUT PRIOR
PRIOR is the hash-verified extracted A3.6 witness archive. No historical file is written.
=#
using JuMP, JSON, SHA
import Mosek, Pkg
include("AP3Pipeline.jl")
const P=AP3Pipeline
const W=abspath(ARGS[1]);const R=P.newoutput(ARGS[2]);const A=abspath(ARGS[3])
save(path,data)=open(io->JSON.print(io,data,2),path,"w")
hash(path)=bytes2hex(sha256(read(path)))
rows=Any[]
function export_result(m,dir,row)
    path=joinpath(dir,"solver_input.mof.json");write_to_file(m,path)
    row["solver_input_sha256"]=hash(path)
    if has_values(m)
        # MOF makes duplicate auxiliary names unique while retaining variable order.
        serialized=JSON.parsefile(path)["variables"]
        vs=all_variables(m);@assert length(vs)==length(serialized)
        save(joinpath(dir,"point.json"),Dict(serialized[i]["name"]=>value(v) for (i,v) in enumerate(vs)))
        row["point_sha256"]=hash(joinpath(dir,"point.json"))
    end
    if P.NativeG3Solver.is_native(get(row,"_optimizer",nothing))
        Mosek.writedata(unsafe_backend(m).task,joinpath(dir,"actual_backend.ptf"))
        row["native_backend_sha256"]=hash(joinpath(dir,"actual_backend.ptf"))
        row["native_backend_type"]=string(typeof(unsafe_backend(m)))
    end
    pop!(row,"_optimizer",nothing)
end

save(joinpath(R,"runtime.json"),Dict("julia"=>string(VERSION),"packages"=>Dict(p.name=>string(p.version) for p in values(Pkg.dependencies()) if p.version!==nothing)))
root=joinpath(W,"reports/ap3_runs/20261020_macro/accepted_suite")
for id in sort([basename(d) for d in readdir(root;join=true) if isdir(d)&&isfile(joinpath(d,"case.json"))])
    source=joinpath(root,id)
    raw,data,scope=P.prepare(joinpath(source,"case.json");registry=joinpath(source,"parameter_registry.csv"),scenarios=joinpath(source,"study_scenarios.toml"))
    lp=P.build(data,P.FP.NoGSCR(),scope;relaxed=true);lpstats=P.solve!(lp,P.HiGHS.Optimizer)
    save(joinpath(R,id*"_BASE_LP.json"),lpstats)
    @assert lpstats["termination"]=="OPTIMAL" && lpstats["objective"]>0
    for (mode,factor,fid) in [("production_costscale",1.,"G3"),("half_costscale",.5,"G3"),
        ("double_costscale",2.,"G3"),("tighter_feasibility",1.,"G3"),("production_costscale",1.,"G0")]
        println("BEGIN ",id," ",fid," ",mode);flush(stdout)
        dir=joinpath(R,id*"_"*fid*"_"*mode);mkpath(dir)
        pm=P.build(data,P.formulation(fid,Dict()),scope;relaxed=false)
        original=joinpath(dir,"original_model.mof.json");write_to_file(pm.model,original)
        optimizer=fid=="G3" ? P.NativeG3Solver.optimizer(;tighter_feasibility=mode=="tighter_feasibility") : P.pajarito_optimizer()
        row=Dict{String,Any}("case_id"=>id,"formulation"=>fid,"mode"=>mode,"factor"=>factor,
            "case_sha256"=>hash(joinpath(source,"case.json")),"original_model_sha256"=>hash(original),
            "directory"=>basename(dir),"_optimizer"=>optimizer)
        try
            row["stats"]=P.solve!(pm,optimizer;objective_scale=factor*lpstats["objective"])
            export_result(pm.model,dir,row)
        catch e
            row["error"]=sprint(showerror,e,catch_backtrace());pop!(row,"_optimizer",nothing)
        end
        push!(rows,row);save(joinpath(R,"results.json"),rows)
        println("END ",id," ",mode," ",get(get(row,"stats",Dict()),"termination","ERROR"));flush(stdout)
    end
end

# Run the literal historical default-coordinate model through the production route.
dir=joinpath(R,"reference_24snap_G3_original_serialized_default");mkpath(dir)
input=joinpath(A,"original_01/b1_exact_native.mof.json")
@assert hash(input)=="fcd52695238591d6c6019385d64e4407e1ea480849ca4125e1191b992581ab07"
m=read_from_file(input);optimizer=P.mosek_optimizer()
row=Dict{String,Any}("case_id"=>"reference_24snap","formulation"=>"G3",
    "mode"=>"original_serialized_default","input_sha256"=>hash(input),
    "directory"=>basename(dir),"_optimizer"=>optimizer,"objective_coordinate"=>"literal_serialized_normalized_objective")
row["stats"]=P.solve!((model=m,),optimizer)
export_result(m,dir,row);push!(rows,row);save(joinpath(R,"results.json"),rows)
