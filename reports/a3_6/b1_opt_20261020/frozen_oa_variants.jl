using JuMP,Test
import HiGHS,JSON
const MOI=JuMP.MOI;R=ARGS[1]
inp=joinpath(R,"experiments/stages");out=joinpath(R,"experiments/frozen_variants");mkpath(out)
w=JSON.parsefile(joinpath(inp,"oa_full_witness.json"));byindex=Dict(p["index"]=>p["value"] for p in w)
rows=Any[]
save(n,v)=open(io->JSON.print(io,v,2),joinpath(out,n),"w")
for (mode,options) in [
    ("original",Dict()),
    ("small_matrix_1e-12",Dict("small_matrix_value"=>1e-12)),
    ("mip_feas_1e-7",Dict("mip_feasibility_tolerance"=>1e-7)),
    ("mip_feas_1e-6",Dict("mip_feasibility_tolerance"=>1e-6)),
    ("fixed_integers_by_index",Dict()),
    ("fixed_witness_by_index",Dict()),
    ("zero_objective",Dict()),
    ("cost_scaled_1e6",Dict()),
    ("mip_presolve_off_small_matrix",Dict("presolve"=>"off","small_matrix_value"=>1e-12))]
    m=read_from_file(joinpath(inp,"oa_frozen.mof.json"));vars=all_variables(m)
    @assert length(vars)==length(w)
    point=Dict(v=>byindex[index(v).value] for v in vars)
    row=Dict{String,Any}("mode"=>mode,"options"=>options,"input_witness_max_violation"=>maximum(values(primal_feasibility_report(m,point;atol=0.));init=0.))
    if startswith(mode,"fixed_")
        for v in vars
            int=is_integer(v)||is_binary(v)
            if int||mode=="fixed_witness_by_index"
                is_integer(v)&&unset_integer(v);is_binary(v)&&unset_binary(v)
                # Keep original domain bounds as constraints when adding equalities.
                @constraint(m,v==(int ? round(point[v]) : point[v]))
            end
        end
    end
    mode=="zero_objective" && set_objective_function(m,AffExpr(0.))
    mode=="cost_scaled_1e6" && set_objective_function(m,1e6*objective_function(m))
    set_optimizer(m,HiGHS.Optimizer)
    for (k,v) in (("threads",1),("random_seed",20261020),("time_limit",90.),("mip_rel_gap",1e-8),("mip_feasibility_tolerance",1e-8));set_optimizer_attribute(m,k,v);end
    for (k,v) in options;set_optimizer_attribute(m,k,v);end
    println("BEGIN VARIANT ",mode);flush(stdout);optimize!(m)
    row["termination"]=string(termination_status(m));row["primal_status"]=string(primal_status(m))
    if primal_status(m)==MOI.FEASIBLE_POINT
        row["max_violation"]=maximum(values(primal_feasibility_report(m;atol=0.));init=0.)
        row["objective"]=objective_value(m);row["bound"]=objective_bound(m)
    end
    if mode=="original" && termination_status(m)==MOI.INFEASIBLE
        try
            compute_conflict!(m);row["conflict_status"]=string(MOI.get(backend(m),MOI.ConflictStatus()))
            conflict=copy_conflict(m);write_to_file(conflict.model,joinpath(out,"iis.mof.json"))
        catch e;row["conflict_error"]=sprint(showerror,e);end
    end
    push!(rows,row);save("results.json",rows)
end
