ENV["GKSwstype"]="100"
using Plots
import JSON,CSV
length(ARGS)==2 || error("usage: plot_ap3_results.jl RUN_ROOT NEW_PLOTS_DIRECTORY")
root,out=abspath.(ARGS);ispath(out) && error("output exists");mkpath(out)
rows=JSON.parsefile(joinpath(root,"comparisons_final","comparisons.json"))["records"]
cases=sort(unique(r["case_id"] for r in rows));ids=["G1","G2_identity","G3","M2_full","M2_neighbor"]
values=fill(NaN,length(cases),length(ids))
for r in rows
    r["relaxed"] && r["status"]=="optimal" && r["relative_delta"]!==nothing && r["formulation"] in ids || continue
    values[findfirst(==(r["case_id"]),cases),findfirst(==(r["formulation"]),ids)]=100r["relative_delta"]
end
p=plot(cases,values;label=permutedims(ids),markershape=:circle,ylabel="Cost difference to G0 (%)",xlabel="Registered parametric scenario",xrotation=35,size=(1200,650),bottom_margin=12Plots.mm,title="Conditional parametric continuous formulation comparison",legend=:outertopright)
savefig(p,joinpath(out,"cost_conservatism.png"));savefig(p,joinpath(out,"cost_conservatism.svg"))
economics=JSON.parsefile(joinpath(root,"planning_final","planning.json"))["records"]
CSV.write(joinpath(out,"planning_cost_table.csv"),[(case_id=r["case_id"],formulation=r["formulation"],relaxed=r["relaxed"],investment=r["investment"],generation=r["generation"],storage=r["storage"],events=r["events"],no_load=r["no_load"],objective_residual=r["objective_residual"]) for r in economics])
