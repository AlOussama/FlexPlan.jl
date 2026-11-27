# Re-read an already persisted reference task without rebuilding or optimizing.
include("NativeStrengthReference.jl")
using .NativeStrengthReference
const R=NativeStrengthReference
length(ARGS)==1 || error("usage: REFERENCE_DIRECTORY")
dir=abspath(only(ARGS))
taskfile=joinpath(dir,"native.task.gz")
expected=joinpath(dir,"expected_psd.json")
task=R.Mosek.maketask()
R.Mosek.readdata(task,taskfile)
actual=R.task_readback(task)
actual["native_task_sha256"]=R.sha(taskfile)
actual["expected_psd_sha256"]=R.sha(expected)
R.writejson(joinpath(dir,"native_psd_readback.json"),actual)
R.writejson(joinpath(dir,"reference_export.json"),Dict("optimized"=>false,
    "route"=>"unscaled_bar_variables_scalar_equality_links",
    "native_task_sha256"=>actual["native_task_sha256"],
    "expected_psd_sha256"=>actual["expected_psd_sha256"],
    "native_readback_sha256"=>R.sha(joinpath(dir,"native_psd_readback.json")),
    "historical_native_identity"=>"UNVERIFIED"))
