using Pkg, JSON, SHA, LinearAlgebra
import JuMP, Gurobi, Mosek, MosekTools, PowerModels
length(ARGS)==1 || error("usage: OUTPUT_JSON")
packages=Dict(string(id)=>Dict("name"=>p.name,"version"=>string(p.version),
    "tree_hash"=>string(p.tree_hash),"source"=>p.source) for (id,p) in Pkg.dependencies())
digest(p)=isfile(p) ? bytes2hex(sha256(read(p))) : nothing
result=Dict("julia_version"=>string(VERSION),"julia_executable"=>joinpath(Sys.BINDIR,Base.julia_exename()),
    "machine"=>Sys.MACHINE,"threads"=>Threads.nthreads(),"word_size"=>Sys.WORD_SIZE,
    "blas"=>sprint(show,BLAS.get_config()),"project_path"=>Base.active_project(),
    "project_sha256"=>digest(Base.active_project()),"Manifest.toml_sha256"=>digest("Manifest.toml"),
    "Manifest-v1.11.toml_sha256"=>digest("Manifest-v1.11.toml"),"packages"=>packages,
    "mosek_runtime_version"=>Mosek.getversion(),"gurobi_runtime_version"=>string(Gurobi._GUROBI_VERSION),
    "gurobi_library"=>abspath(Gurobi.libgurobi),"gurobi_library_sha256"=>digest(abspath(Gurobi.libgurobi)),
    "mosek_source"=>pathof(Mosek),"mosektools_source"=>pathof(MosekTools),
    "no_week_optimization"=>true)
open(io->JSON.print(io,result,2),only(ARGS),"w")
