import JSON,TOML
length(ARGS)==2 || error("usage: make_suite_config.jl PRODUCER_ROOT NEW_CONFIG_JSON")
root=joinpath(abspath(ARGS[1]),"data","paper_a_study");out=abspath(ARGS[2])
ispath(out) && error("config exists; choose a new path")
scenariofile=joinpath(root,"study_scenarios.toml");registry=joinpath(root,"parameter_registry.csv")
cases=[Dict("id"=>s["id"],"case"=>relpath(joinpath(root,"cases",s["id"],"study_$(s["snapshots"])snap","case.json"),dirname(out)),"registry"=>relpath(registry,dirname(out)),"scenarios"=>relpath(scenariofile,dirname(out))) for s in TOML.parsefile(scenariofile)["scenarios"]]
open(out,"w") do io
    JSON.print(io,Dict("AP1_SHA"=>"3b8fdb01d931225edc5f8fe1e2c200d0da288a09","cases"=>cases,"relaxations"=>[true,false]),2)
end
