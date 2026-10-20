# Check a freshly solved full G3 witness against the exact serialized native model,
# including original integrality/bounds and all objective-increment equalities.
using JuMP,Test
import JSON
R=ARGS[1];m=read_from_file(joinpath(R,"b1_exact_native.mof.json"))
w=JSON.parsefile(joinpath(R,"integer_final/full_witness_reference_24snap_G3.json"))
vals=Dict{Int,Float64}(x["index"]=>x["value"] for x in w["all_variables"])
originalcount=length(vals)
for _ in 1:3
    for (F,S) in list_of_constraint_types(m)
        S <: JuMP.MOI.EqualTo || continue
        for c in all_constraints(m,F,S)
            co=constraint_object(c);co.func isa AffExpr || continue
            unknown=[(a,v) for (a,v) in linear_terms(co.func) if !haskey(vals,index(v).value)]
            length(unknown)==1 || continue
            a,v=only(unknown);known=co.func.constant+sum(b*vals[index(u).value] for (b,u) in linear_terms(co.func) if haskey(vals,index(u).value);init=0.)
            vals[index(v).value]=(co.set.value-known)/a
        end
    end
end
@test length(vals)==num_variables(m)
point=Dict(v=>vals[index(v).value] for v in all_variables(m))
viol=primal_feasibility_report(m,point;atol=0.);worst=maximum(values(viol);init=0.)
@test worst<1e-7
byset=Dict{String,Float64}()
for (c,v) in viol
    k=string(typeof(constraint_object(c).set));byset[k]=max(get(byset,k,0.),v)
end
result=Dict("native_model_variables"=>num_variables(m),"original_full_witness_variables"=>originalcount,"objective_auxiliary_values_reconstructed"=>length(vals)-originalcount,"max_violation_including_integer_and_rebase_constraints"=>worst,"violations_by_set"=>byset,"scaled_objective_value"=>value(v->point[v],objective_function(m)),"point"=>[Dict("index"=>index(v).value,"name"=>name(v),"value"=>point[v]) for v in all_variables(m)])
open(io->JSON.print(io,result,2),joinpath(R,"b1_exact_full_witness_verification.json"),"w")
println("Native exact-model full witness verified: ",worst)
