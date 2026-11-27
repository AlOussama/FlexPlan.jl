"""E-only byte and point audits; these functions never optimize a model."""
module G3ConditioningAudit
using JuMP, JSON, CSV, SHA, SparseArrays
import Gurobi
const MOI=JuMP.MOI
sha(path)=bytes2hex(sha256(read(path)))
writejson(path,x)=open(io->JSON.print(io,x),path,"w")
setdata(s::MOI.GreaterThan)=Dict("kind"=>"ge","rhs"=>s.lower)
setdata(s::MOI.LessThan)=Dict("kind"=>"le","rhs"=>s.upper)
setdata(s::MOI.EqualTo)=Dict("kind"=>"eq","rhs"=>s.value)
setdata(s::MOI.Interval)=Dict("kind"=>"interval","lower"=>s.lower,"upper"=>s.upper)
setdata(s::MOI.RotatedSecondOrderCone)=Dict("kind"=>"rsoc","dimension"=>s.dimension)
setdata(s::MOI.SecondOrderCone)=Dict("kind"=>"soc","dimension"=>s.dimension)
setdata(s)=Dict("kind"=>string(typeof(s)))
fdata(v::VariableRef)=Dict("constant"=>0.,"terms"=>[[index(v).value,1.]])
fdata(f::GenericAffExpr)=Dict("constant"=>f.constant,"terms"=>[[index(v).value,c] for (c,v) in linear_terms(f)])
fdata(f::Real)=Dict("constant"=>f,"terms"=>Any[])
fdata(f::AbstractVector)=fdata.(f)
function dump_original_and_copy(path,original,copy)
    open(path,"w") do io
        for (F,S) in list_of_constraint_types(original),ci in all_constraints(original,F,S)
            a=constraint_object(ci);b=constraint_object(copy.constraints[ci])
            JSON.print(io,Dict("original_constraint_index"=>index(ci).value,"original_type"=>string(S),
                "original_function"=>fdata(a.func),"original_set"=>setdata(a.set),
                "scaled_function"=>fdata(b.func),"scaled_set"=>setdata(b.set),
                "row_exponent"=>copy.rows[ci],"variable_bound"=>a.func isa VariableRef))
            println(io)
        end
    end
end
function original_point_check(model,point,path)
    point_values=Dict(v=>point[index(v).value] for v in all_variables(model))
    residuals=primal_feasibility_report(model,point_values;atol=0.)
    violations=sort([(constraint=string(c),violation=r) for (c,r) in residuals];by=x->-x.violation)
    CSV.write(path,violations)
    polynomial=0.
    for (F,S) in list_of_constraint_types(model)
        S <: Union{MOI.RotatedSecondOrderCone,MOI.SecondOrderCone} || continue
        for ci in all_constraints(model,F,S)
            evaluate(z)=z isa VariableRef ? point_values[z] : z isa Real ? z : JuMP.value(v->point_values[v],z)
            y=evaluate.(constraint_object(ci).func)
            violation=S <: MOI.SecondOrderCone ? max(-y[1],sum(abs2,y[2:end])-y[1]^2) : max(-y[1],-y[2],sum(abs2,y[3:end])-2*y[1]*y[2])
            polynomial=max(polynomial,violation)
        end
    end
    maximum_distance=maximum(values(residuals);init=0.)
    return Dict("maximum_original_constraint_distance"=>maximum_distance,
        "violations_over_1e_7"=>count(x->x.violation>1e-7,violations),
        "violations_over_1e_6"=>count(x->x.violation>1e-6,violations),
        "maximum_original_RSOC_polynomial_violation"=>polynomial,
        "maximum_original_SOC_or_RSOC_polynomial_violation"=>polynomial,
        "point_pass_at_unchanged_1e_7"=>max(maximum_distance,polynomial)<=1e-7,
        "all_original_values"=>length(point_values),"residual_csv_sha256"=>sha(path))
end
ok(c)=c==0 ? nothing : error("Gurobi model audit API error $c")
function native_dump(model,path)
    native=unsafe_backend(model)
    intattr(name)=begin a=Ref{Cint}();ok(Gurobi.GRBgetintattr(native,name,a));Int(a[]) end
    nr=intattr("NumConstrs");nv=intattr("NumVars");nq=intattr("NumQConstrs")
    nz=Ref{Cint}(0)
    ok(Gurobi.GRBgetconstrs(native,nz,C_NULL,C_NULL,C_NULL,0,nr))
    starts=zeros(Cint,nr);columns=zeros(Cint,nz[]);coefficients=zeros(Float64,nz[])
    ok(Gurobi.GRBgetconstrs(native,nz,starts,columns,coefficients,0,nr))
    function darr(name,n)
        n==0 && return Float64[]
        a=zeros(Float64,n);ok(Gurobi.GRBgetdblattrarray(native,name,0,n,a));a
    end
    senses=zeros(Cchar,nr);ok(Gurobi.GRBgetcharattrarray(native,"Sense",0,nr,senses))
    qrows=Any[]
    for k in 0:nq-1
        nl=Ref{Cint}(0);nqz=Ref{Cint}(0)
        ok(Gurobi.GRBgetqconstr(native,k,nl,C_NULL,C_NULL,nqz,C_NULL,C_NULL,C_NULL))
        li=zeros(Cint,nl[]);lv=zeros(Float64,nl[]);qi=zeros(Cint,nqz[]);qj=zeros(Cint,nqz[]);qv=zeros(Float64,nqz[])
        ok(Gurobi.GRBgetqconstr(native,k,nl,li,lv,nqz,qi,qj,qv))
        push!(qrows,Dict("linear_columns_zero_based"=>li,"linear_coefficients"=>lv,
            "quadratic_i_zero_based"=>qi,"quadratic_j_zero_based"=>qj,"quadratic_coefficients"=>qv))
    end
    result=Dict("rows"=>nr,"variables"=>nv,"quadratics"=>nq,"row_starts_zero_based"=>starts,
        "columns_zero_based"=>columns,"coefficients"=>coefficients,"rhs"=>darr("RHS",nr),
        "senses"=>string.(Char.(senses)),"lower_bounds"=>darr("LB",nv),"upper_bounds"=>darr("UB",nv),
        "objective_coefficients"=>darr("Obj",nv),"quadratic_rows"=>qrows,
        "quadratic_rhs"=>darr("QCRHS",nq))
    writejson(path,result)
    return result
end
function native_reference(model,copy,reference,dump,path)
    native=unsafe_backend(model);ys=fill(NaN,dump["variables"])
    for (v,y) in copy.variables
        col=Int(Gurobi.c_column(native,optimizer_index(y)))+1
        ys[col]=ldexp(reference[index(v).value],-copy.exponents[v])
    end
    starts=Int.(dump["row_starts_zero_based"]).+1
    stops=vcat(starts[2:end].-1,length(dump["coefficients"]))
    # Every auxiliary is defined by an actual equality: vector-slack or
    # interval-slack. Do not assume a fixed number of auxiliaries per cone.
    for iteration in 1:4
        missing_before=count(isnan,ys)
        for i in eachindex(starts)
            dump["senses"][i]=="=" || continue
            slots=starts[i]:stops[i];unknown=[k for k in slots if isnan(ys[Int(dump["columns_zero_based"][k])+1])]
            length(unknown)==1 || continue
            k=only(unknown)
            known=sum(dump["coefficients"][j]*ys[Int(dump["columns_zero_based"][j])+1] for j in slots if j!=k;init=0.)
            ys[Int(dump["columns_zero_based"][k])+1]=(dump["rhs"][i]-known)/dump["coefficients"][k]
        end
        count(isnan,ys)==0 && break
        count(isnan,ys)<missing_before || error("Undetermined actual native auxiliary")
    end
    all(isfinite,ys) || error("Incomplete native reference mapping")
    CSV.write(path,[(native_column_zero_based=k-1,value=ys[k]) for k in eachindex(ys)])
    return ys
end
end
