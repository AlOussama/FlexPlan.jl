using Pkg, LinearAlgebra, InteractiveUtils
import HiGHS
import JuMP
println("Julia executable: ",joinpath(Sys.BINDIR,Base.julia_exename()))
versioninfo(;verbose=true)
println("BLAS: ",BLAS.get_config())
println("HiGHS solver: ",JuMP.MOI.get(HiGHS.Optimizer(),JuMP.MOI.SolverVersion()))
Pkg.status(;mode=Pkg.PKGMODE_MANIFEST)
