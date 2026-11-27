using Test, JuMP, JSON, SHA, CSV
sha_file(path)=open(io->bytes2hex(SHA.sha256(io)),path)
include(joinpath(@__DIR__,"..","scripts","paper_a","week_ac_audit.jl"))

@testset "Original unscaled rows survive solver transformations" begin
    m=Model()
    @variable(m, angle)
    @constraint(m, original_angle, angle <= 0)
    snapshot=freeze_ac_original_model(m)
    preserve_ac_original_constraint!(snapshot,original_angle)
    set_normalized_coefficient(original_angle,angle,1e-12)
    val(x)=value(_->1e-3,x)
    @test isempty(primal_feasibility_report(_->1e-3,m;atol=1e-8))
    @test original_ac_distances(snapshot,val)[original_angle] ≈ 1e-3
    @testset "Deleted current row remains original" begin
        @constraint(m, current, angle >= 2)
        s=freeze_ac_original_model(m)
        preserve_ac_original_constraint!(s,current)
        delete(m,current)
        @test original_ac_distances(s,val)[current] ≈ 1.999
    end
    @testset "Unregistered deletion fails closed" begin
        s=freeze_ac_original_model(m)
        delete(m,original_angle)
        @test_throws ErrorException original_ac_distances(s,val)
    end
end

@testset "Julia replay requires expected bytes and separate output" begin
    withenv("PAPER_A_AC_REPLAY_MANIFEST"=>nothing,"PAPER_A_AC_REPLAY_OUTPUT"=>nothing) do
        @test_throws ErrorException replay_ac_week("missing_input",nothing)
    end
    mktempdir() do dir
        m=Model()
        @variable(m,x[1:2])
        pointpath=joinpath(dir,"point.csv")
        for body in ("1,0\n1,1\n2,0\n","1,NaN\n1,1\n2,0\n","1,0\n3,0\n","1,0\n")
            write(pointpath,"index,value\n"*body)
            @test_throws ErrorException read_ac_replay_point(pointpath,x)
        end
        paths=Dict("primal"=>"primal.csv","outcome"=>"outcome.json","audit_terms"=>"audit_terms.csv",
                   "terminal_coordinates"=>"terminal_coordinates.csv","case"=>"case.json","export_metadata"=>"export.json")
        for name in values(paths)
            write(joinpath(dir,name),"original")
        end
        write(joinpath(dir,"export.json"),JSON.json(Dict("case_sha256"=>sha_file(joinpath(dir,"case.json")))))
        inputs=Dict(role=>Dict("path"=>joinpath(dir,name),"bytes"=>filesize(joinpath(dir,name)),
                              "sha256"=>sha_file(joinpath(dir,name))) for (role,name) in paths)
        evaluator=joinpath(@__DIR__,"..","scripts","paper_a","week_ac_audit.jl")
        inputs["evaluator_program"]=Dict("path"=>abspath(evaluator),"bytes"=>filesize(evaluator),"sha256"=>sha_file(evaluator))
        manifest=joinpath(dir,"manifest.json")
        write(manifest,JSON.json(Dict("schema"=>"paper_a_julia_replay_inputs/1","inputs"=>inputs)))
        @test verify_ac_replay_manifest(manifest,dir)["schema"]=="paper_a_julia_replay_inputs/1"
        write(joinpath(dir,"audit_terms.csv"),"tampered")
        @test_throws ErrorException verify_ac_replay_manifest(manifest,dir)
        rm(joinpath(dir,"primal.csv"))
        @test_throws ErrorException verify_ac_replay_manifest(manifest,dir)
    end
end
