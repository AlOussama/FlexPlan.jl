"""Actual native API readback of the exact finite G3 SOC attachment; no solve."""
module G3NativeReadback
using JuMP, JSON, SHA
import Gurobi, MosekTools
const MOI=JuMP.MOI
const MSK=MosekTools.Mosek
key(a,c=0.)=(Tuple(sort(collect(a);by=first)),c==0 ? 0. : c)
function coefficients(f,col)
    f isa VariableRef && return Dict(col(f)=>1.),0.
    f isa Real && return Dict{Int,Float64}(),Float64(f)
    return Dict(col(v)=>Float64(a) for (a,v) in linear_terms(f) if a!=0),Float64(f.constant)
end
function writejson(path,data)
    open(io->JSON.print(io,data),path,"w")
    return bytes2hex(sha256(read(path)))
end
ok(code)=code==0 ? nothing : error("Native G3 API failure $code")

function gurobi_data(native)
    ok(Gurobi.GRBupdatemodel(native))
    intattr(n)=begin a=Ref{Cint}();ok(Gurobi.GRBgetintattr(native,n,a));Int(a[]) end
    nr=intattr("NumConstrs");nv=intattr("NumVars");nq=intattr("NumQConstrs")
    darr(n,k)=begin a=zeros(k);k>0 && ok(Gurobi.GRBgetdblattrarray(native,n,0,k,a));a end
    nz=Ref{Cint}(0);ok(Gurobi.GRBgetconstrs(native,nz,C_NULL,C_NULL,C_NULL,0,nr))
    starts=zeros(Cint,nr);cols=zeros(Cint,nz[]);vals=zeros(nz[])
    ok(Gurobi.GRBgetconstrs(native,nz,starts,cols,vals,0,nr))
    senses=zeros(Cchar,nr);ok(Gurobi.GRBgetcharattrarray(native,"Sense",0,nr,senses))
    rows=Any[];rhs=darr("RHS",nr)
    for r in 1:nr
        slots=Int(starts[r])+1:(r==nr ? length(cols) : Int(starts[r+1]))
        push!(rows,Dict("index_zero_based"=>r-1,"columns_zero_based"=>cols[slots],"coefficients"=>vals[slots],"rhs"=>rhs[r],"sense"=>string(Char(senses[r]))))
    end
    qrows=Any[];qrhs=darr("QCRHS",nq);qsenses=zeros(Cchar,nq)
    nq>0 && ok(Gurobi.GRBgetcharattrarray(native,"QCSense",0,nq,qsenses))
    for r in 0:nq-1
        nl=Ref{Cint}(0);nn=Ref{Cint}(0)
        ok(Gurobi.GRBgetqconstr(native,r,nl,C_NULL,C_NULL,nn,C_NULL,C_NULL,C_NULL))
        li=zeros(Cint,nl[]);lv=zeros(nl[]);ii=zeros(Cint,nn[]);jj=zeros(Cint,nn[]);vv=zeros(nn[])
        ok(Gurobi.GRBgetqconstr(native,r,nl,li,lv,nn,ii,jj,vv))
        push!(qrows,Dict("index_zero_based"=>r,"linear_columns_zero_based"=>li,"linear_coefficients"=>lv,
            "quadratic_i_zero_based"=>ii,"quadratic_j_zero_based"=>jj,"quadratic_coefficients"=>vv,"sense"=>string(Char(qsenses[r+1])),"rhs"=>qrhs[r+1]))
    end
    return Dict("backend"=>"Gurobi_actual_C_API","linear_rows"=>rows,"quadratic_rows"=>qrows,"lower_bounds"=>darr("LB",nv),"upper_bounds"=>darr("UB",nv))
end

function native_certificate_readback!(dir,model,certs;copy=nothing)
    started=time_ns()
    backend(model) isa MOI.Utilities.CachingOptimizer && MOI.Utilities.state(backend(model))==MOI.Utilities.EMPTY_OPTIMIZER &&
        MOI.Utilities.attach_optimizer(backend(model))
    native=unsafe_backend(model);gurobi=native isa Gurobi.Optimizer
    mapped(c)=copy===nothing ? c : copy.constraints[c]
    variable(v)=copy===nothing ? v : copy.variables[v]
    col(v)=gurobi ? Int(Gurobi.c_column(native,optimizer_index(v))) : Int(MosekTools.column(native,optimizer_index(v)).value)
    certlist=collect(values(certs));raw=gurobi ? gurobi_data(native) : Dict{String,Any}("backend"=>"MOSEK_actual_Task_API","cones"=>Any[],"node_rows"=>Any[],"q_bounds"=>Any[])
    ledger=Any[];ncones=nrows=nqbound=0
    if gurobi
        # Each affine SOC coordinate is retained by a native equality. Build
        # definitions from actual rows, restricted to native cone auxiliaries.
        socs=MOI.get(native,MOI.ListOfConstraintIndices{MOI.VectorOfVariables,MOI.SecondOrderCone}())
        cone_cols=[Int.(Gurobi.c_column.(Ref(native),MOI.get(native,MOI.ConstraintFunction(),ci).variables)) for ci in socs]
        cone_by_head=Dict(first(cs)=>cs for cs in cone_cols)
        aux=Set(Iterators.flatten(cone_cols));defs=Dict{Any,Vector{Int}}()
        for row in raw["linear_rows"]
            row["sense"]=="=" || continue
            a=Dict(Int(i)=>v for (i,v) in zip(row["columns_zero_based"],row["coefficients"]) if v!=0)
            for c in intersect(Set(keys(a)),aux)
                abs(a[c])==1. || continue
                others=Dict(i=>-v/a[c] for (i,v) in a if i!=c)
                push!(get!(defs,key(others,row["rhs"]/a[c]),Int[]),c)
            end
        end
        quad=Dict{Any,Any}()
        for r in raw["quadratic_rows"]
            isempty(r["linear_columns_zero_based"]) && r["sense"]==">" && r["rhs"]==0. || continue
            r["quadratic_i_zero_based"]==r["quadratic_j_zero_based"] || continue
            a=Dict(Int(i)=>v for (i,v) in zip(r["quadratic_i_zero_based"],r["quadratic_coefficients"]))
            quad[key(a)]=r["index_zero_based"]
        end
        rows=Set((key(Dict(Int(i)=>v for (i,v) in zip(r["columns_zero_based"],r["coefficients"]) if v!=0)),r["sense"],r["rhs"]) for r in raw["linear_rows"])
        for cert in certlist
            for cone in cert.cones
                object=constraint_object(mapped(cone));object.set isa MOI.SecondOrderCone || error("G3 readback requires exact standard SOC")
                targets=[get(defs,key(coefficients(f,col)...),Int[]) for f in object.func]
                all(!isempty,targets) || error("Missing actual native SOC affine-coordinate equality")
                matches=[cone_by_head[c] for c in targets[1] if haskey(cone_by_head,c) &&
                    all(cone_by_head[c][k] in targets[k] for k in 2:3)]
                length(matches)==1 || error("Native SOC coordinate match is not unique")
                cs=only(matches);signature=Dict(cs[1]=>1.,cs[2]=>-1.,cs[3]=>-1.)
                haskey(quad,key(signature)) || error("Actual native G3 QC differs from exact unit diagonal")
                raw["lower_bounds"][cs[1]+1]==0. && raw["upper_bounds"][cs[1]+1]==Gurobi.GRB_INFINITY || error("Actual native SOC head bounds differ")
                push!(ledger,Dict("native_quadratic_row_zero_based"=>quad[key(signature)],"native_coordinate_columns_zero_based"=>cs,"actual_affine_equalities_exact"=>true))
                ncones+=1
            end
            for row in cert.rows
                o=constraint_object(mapped(row));a,c=coefficients(o.func,col)
                (key(a),">",o.set.lower-c) in rows || error("Actual native G3 node budget differs")
                nrows+=1
            end
            for q in cert.q
                column=col(variable(q))+1
                raw["lower_bounds"][column]==0. && raw["upper_bounds"][column]==Gurobi.GRB_INFINITY || error("Actual native q bounds differ")
                nqbound+=1
            end
        end
    else
        task=native.task
        MSK.getnumbarvar(task)==0 || error("G3 native task unexpectedly contains matrix variables")
        for cert in certlist
            for cone in cert.cones
                mappedcone=mapped(cone);ci=optimizer_index(mappedcone);o=constraint_object(mappedcone)
                ci isa MOI.ConstraintIndex{MOI.VectorAffineFunction{Float64},MOI.SecondOrderCone} || error("Expected native MOSEK affine SOC ACC")
                domain=MSK.getaccdomain(task,ci.value)
                MSK.getdomaintype(task,domain)==MSK.MSK_DOMAIN_QUADRATIC_CONE || error("Actual MOSEK domain is not SOC")
                afes=MSK.getaccafeidxlist(task,ci.value);b=MSK.getaccb(task,ci.value)
                length(afes)==3 || error("Actual native G3 SOC dimension differs")
                actual=Any[]
                for (k,afe) in enumerate(afes)
                    nn,cols,vals=MSK.getafefrow(task,afe);a,c=coefficients(o.func[k],col);g=MSK.getafeg(task,afe)
                    Dict(Int(i)=>v for (i,v) in zip(cols,vals) if v!=0)==a && g==0. && -b[k]==c || error("Actual MOSEK ACC affine coordinate differs")
                    push!(actual,Dict("afe_index_one_based"=>afe,"columns_one_based"=>cols,"coefficients"=>vals,"afe_g"=>g,"acc_b"=>b[k],"constant"=>-b[k]))
                end
                push!(raw["cones"],Dict("acc_index_one_based"=>ci.value,"domain_type"=>"MSK_DOMAIN_QUADRATIC_CONE","coordinates"=>actual))
                ncones+=1
            end
            for row in cert.rows
                r=mapped(row);ci=optimizer_index(r);ri=MosekTools.row(native,ci);nn,cols,vals=MSK.getarow(task,ri)
                bk,lo,up=MSK.getconbound(task,ri);o=constraint_object(r);a,c=coefficients(o.func,col)
                Dict(Int(i)=>v for (i,v) in zip(cols,vals) if v!=0)==a && bk==MSK.MSK_BK_LO && lo==o.set.lower-c || error("Actual MOSEK node row differs")
                push!(raw["node_rows"],Dict("row_one_based"=>ri,"columns_one_based"=>cols,"coefficients"=>vals,"bound_key"=>"MSK_BK_LO","lower"=>lo,"upper"=>up));nrows+=1
            end
            for q in cert.q
                column=col(variable(q));bk,lo,up=MSK.getvarbound(task,column)
                bk==MSK.MSK_BK_LO && lo==0. || error("Actual MOSEK q bounds differ")
                label=bk==MSK.MSK_BK_LO ? "MSK_BK_LO" : bk==MSK.MSK_BK_RA ? "MSK_BK_RA" : "MSK_BK_FX"
                push!(raw["q_bounds"],Dict("column_one_based"=>column,"bound_key"=>label,"lower"=>lo,"upper"=>up));nqbound+=1
            end
        end
    end
    nativepath=joinpath(dir,gurobi ? "g3_actual_native.mps" : "g3_actual_native.task.gz")
    if gurobi
        code=Gurobi.GRBwrite(native,nativepath)
        code==0 || error("Gurobi native write $code: "*unsafe_string(Gurobi.GRBgeterrormsg(Gurobi.GRBgetenv(native))))
    else
        MSK.writedata(native.task,nativepath)
    end
    rawhash=writejson(joinpath(dir,"g3_actual_native_readback.json"),raw)
    result=Dict("status"=>"PASS","backend"=>raw["backend"],"native_cones_exact"=>ncones,"native_node_rows_exact"=>nrows,
        "native_q_nonnegative_bounds"=>nqbound,"coefficient_identity"=>"(q1+q2)^2-(q1-q2)^2-(2Mij)^2=4(q1*q2-Mij^2)",
        "raw_readback_sha256"=>rawhash,"persisted_native_model"=>basename(nativepath),
        "persisted_native_model_sha256"=>bytes2hex(sha256(read(nativepath))),
        "exporter_source_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "native_coordinate_ledger"=>ledger,"optimization_performed"=>false,
        "readback_elapsed_seconds"=>(time_ns()-started)/1e9)
    writejson(joinpath(dir,"g3_actual_native_verdict.json"),result)
    return result
end
end
