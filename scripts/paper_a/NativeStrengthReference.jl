"""New native reference transmission evidence. Never calls optimize!."""
module NativeStrengthReference
using JuMP, JSON, SHA
import MosekTools, Mosek, Gurobi
const MOI=JuMP.MOI
sha(path)=open(io->bytes2hex(sha256(io)),path)
writejson(path,obj)=open(io->JSON.print(io,obj),path,"w")

"""Force exact unscaled PSD matrix variables plus scalar equality links.
The default scaled-PSD bridge contains rounded sqrt(2) coefficients.
"""
function configure_g0!(model)
    remove_bridge(model,MOI.Bridges.Constraint.SetDotScalingBridge)
    return
end

function task_readback(task)
    n,row,bar,i,j,value=Mosek.getbarablocktriplet(task)
    afebar=Mosek.getafebarfblocktriplet(task)
    barobj=Mosek.getbarcblocktriplet(task)
    first(afebar)==0 || error("Unexpected AFE coupling of PSD bar variables")
    first(barobj)==0 || error("Unexpected objective coupling of PSD bar variables")
    rows=Any[]
    for r in sort!(unique(row))
        _,cols,vals=Mosek.getarow(task,r)
        key,lo,hi=Mosek.getconbound(task,r)
        push!(rows,Dict("row"=>r,"columns"=>cols,"values"=>vals,
            "bound_key"=>key==Mosek.MSK_BK_FX ? "MSK_BK_FX" : sprint(show,key),"lower"=>isfinite(lo) ? lo : nothing,
            "upper"=>isfinite(hi) ? hi : nothing))
    end
    return Dict("bar_dimensions"=>[Mosek.getdimbarvarj(task,k) for k in 1:Mosek.getnumbarvar(task)],
        "bar_triplets"=>Dict("row"=>row,"bar"=>bar,"i"=>i,"j"=>j,"value"=>value),
        "rows"=>rows,"bar_triplet_count"=>n,"native_variable_count"=>Mosek.getnumvar(task),
        "afe_bar_triplet_count"=>first(afebar),"bar_objective_triplet_count"=>first(barobj),
        "native_row_count"=>Mosek.getnumcon(task),"native_ACC_count"=>Mosek.getnumacc(task))
end

function export_g0!(dir,model,matrices;metadata=Dict())
    MOI.Utilities.state(backend(model))==MOI.Utilities.EMPTY_OPTIMIZER &&
        MOI.Utilities.attach_optimizer(backend(model))
    native=unsafe_backend(model)
    native isa MosekTools.Optimizer || error("G0 reference requires MOSEK")
    columns=Dict{VariableRef,Int}()
    for v in all_variables(model)
        idx=MosekTools.mosek_index(native,optimizer_index(v))
        idx isa MosekTools.ColumnIndex || error("Original scalar mapped to matrix variable")
        columns[v]=idx.value
    end
    blocks=Any[]
    for (hour,M) in sort!(collect(matrices);by=first)
        n=size(M,1)
        entries=Any[]
        for j in 1:n,i in 1:j
            f=AffExpr(0.)+M[i,j]
            push!(entries,Dict("i"=>i,"j"=>j,"constant"=>f.constant,
                "terms"=>sort!([[columns[v],c] for (c,v) in linear_terms(f)];by=first)))
        end
        push!(blocks,Dict("hour"=>hour,"dimension"=>n,"entries"=>entries))
    end
    expected=Dict("expected_blocks"=>blocks,
        "original_variables"=>[Dict("jump_index"=>index(v).value,"native_column"=>columns[v]) for v in all_variables(model)])
    writejson(joinpath(dir,"expected_psd.json"),expected)
    path=joinpath(dir,"native.task.gz")
    Mosek.writedata(native.task,path)
    # Reopen the actual persisted solver task; do not report cached MOI rows.
    reopened=Mosek.maketask()
    Mosek.readdata(reopened,path)
    actual=task_readback(reopened)
    actual["native_task_sha256"]=sha(path)
    actual["expected_psd_sha256"]=sha(joinpath(dir,"expected_psd.json"))
    actual["metadata"]=metadata
    writejson(joinpath(dir,"native_psd_readback.json"),actual)
    return Dict("optimized"=>false,"route"=>"unscaled_bar_variables_scalar_equality_links",
        "native_task_sha256"=>sha(path),"expected_psd_sha256"=>sha(joinpath(dir,"expected_psd.json")),
        "native_readback_sha256"=>sha(joinpath(dir,"native_psd_readback.json")),
        "historical_native_identity"=>"UNVERIFIED")
end
end
