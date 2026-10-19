using Test, TOML, LinearAlgebra, SHA
import FlexPlan as FP
import JSON
length(ARGS)==2 || error("usage: run_paper_a_parameter_network_audit.jl PRODUCER_ROOT OUTPUT_JSON")
root=joinpath(ARGS[1],"data","paper_a_study")
rows=Any[]
matrix(v)=reduce(vcat,permutedims.(v))
@testset "Strang B physical Y L B0 and Schur audit" begin
    for s in TOML.parsefile(joinpath(root,"study_scenarios.toml"))["scenarios"]
        path=joinpath(root,"cases",s["id"],"study_$(s["snapshots"])snap","case.json")
        data=FP.parse_file(path)
        FP.register_paper_a_parameters!(data,joinpath(root,"parameter_registry.csv"),joinpath(root,"study_scenarios.toml"))
        net=data["paper_a_network"]
        r=FP.PaperARegional.network_reference(net,data["nw"]["1"]["bus"],data["baseMVA"];diagnostic_only=true)
        yr=norm(real.(r.Y)-matrix(net["Y_positive_real_pu"]),Inf)
        yi=norm(imag.(r.Y)-matrix(net["Y_positive_imag_pu"]),Inf)
        lr=norm(r.L-matrix(net["L_neg_imag_Y_pu"]),Inf)
        @test yr<1e-10
        @test yi<1e-10
        @test lr<1e-10
        @test r.B0_reference_residual<1e-10
        @test r.schur_residual<1e-10
        @test !r.theorem_domain_valid
        push!(rows,Dict("scenario_id"=>s["id"],"case_sha256"=>bytes2hex(sha256(read(path))),
            "Y_real_residual"=>yr,"Y_imag_residual"=>yi,"L_residual"=>lr,"B0_residual"=>r.B0_reference_residual,
            "Schur_elimination_residual"=>r.schur_residual,"eliminated_nodes"=>length(r.eliminated),
            "passive_domain_issues"=>r.passive_domain_issues,"theorem_domain_valid"=>false))
    end
end
open(ARGS[2],"w") do io;JSON.print(io,Dict("network_audit"=>rows),2);end
