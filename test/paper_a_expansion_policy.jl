function _ap2_expansion_fixture()
    data=_ap2_fixture()
    data["paper_a_extension"]["expansion_policy"]=Dict(
        "id"=>"gas_bess_3x_bus_peak_v1","peak_load_MW_by_bus"=>Dict{String,Any}("A"=>90.0,"B"=>0.0))
    for (t,sn) in data["nw"]
        demand=only(values(sn["load"]))
        demand["pd"]=t=="1" ? 45.0/250 : 50.0/250
        second=deepcopy(demand)
        second["index"]=2
        second["pd"]=t=="1" ? 35.0/250 : 20.0/250
        sn["load"]["2"]=second

        ccgt=sn["gen"]["2"]
        ccgt["carrier"]="CCGT"
        ccgt["n0"]=2
        ccgt["na0"]=2
        ccgt["nmax"]=18
        ocgt=deepcopy(ccgt)
        ocgt["index"]=3
        ocgt["name"]="OCGT"
        ocgt["carrier"]="OCGT"
        ocgt["n0"]=1
        ocgt["na0"]=1
        for field in ("p_block_max","p_block_max_MW","S_block_MVA","native_source_MVA","b_block")
            ocgt[field]*=40/25
        end
        sn["gen"]["3"]=ocgt

        bess=sn["storage"]["1"]
        bess["carrier"]="BESS-GFM"
        bess["nmax"]=18
        bess["e_block"]=4*bess["p_block_max"]
        sn["dcline"]["1"]=Dict{String,Any}(
            "index"=>1,"f_bus"=>1,"t_bus"=>2,"br_status"=>1,
            "pminf"=>-0.4,"pmaxf"=>0.4,"pmint"=>-0.4,"pmaxt"=>0.4,
            "loss0"=>0.0,"loss1"=>0.0,"pf"=>0.0,"pt"=>0.0)
    end
    return data
end

function _ap2_expansion_model(data;device_formulations=Dict())
    template=_FP.UCGSCRBlockTemplate(Dict(
        (:gen,"GFL")=>_FP.BlockRenewableParticipation(),
        (:gen,"CCGT")=>_FP.BlockThermalCommitment(),
        (:gen,"OCGT")=>_FP.BlockThermalCommitment(),
        (:storage,"BESS-GFM")=>_FP.BlockStorageParticipation(),
        (:ne_storage,"battery")=>_FP.BlockStorageParticipation()),_FP.NoGSCR();
        device_formulations,paper_a_validation_scope=:synthetic_regression)
    return _ap2_model(data;template,objective=false)
end

function _ap2_expansion_prepared(data)
    digest=_FP.paper_a_profile_identity(data)
    _FP.prepare_paper_a_data!(data;expected_profile_sha256=digest)
    _FP.scale_paper_a_costs!(data)
    return data
end

function _ap2_expansion_solve!(pm)
    JuMP.set_optimizer(pm.model,HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    JuMP.optimize!(pm.model)
    return JuMP.termination_status(pm.model)
end

@testset "Paper A aggregate expansion policy" begin
    @testset "Coincident peak, shared gas budget, BESS and lossless HGÜ" begin
        d=_ap2_expansion_prepared(_ap2_expansion_fixture())
        pm=_ap2_expansion_model(d)
        caps=_PM.con(pm,1,:paper_a_expansion_limits)
        @test Set(keys(caps))==Set([("A",:gas),("A",:bess)])
        @test !haskey(_PM.con(pm,2),:paper_a_expansion_limits)
        x=_PM.var(pm,1,:n_block)
        @test x===_PM.var(pm,2,:n_block)
        @test JuMP.is_integer(x[(:gen,2)])
        @test JuMP.normalized_coefficient(caps[("A",:gas)],x[(:gen,2)])==25.0
        @test JuMP.normalized_coefficient(caps[("A",:gas)],x[(:gen,3)])==40.0
        @test JuMP.normalized_coefficient(caps[("A",:gas)],x[(:storage,1)])==0.0
        @test JuMP.normalized_rhs(caps[("A",:gas)])==270+2*25+40
        @test JuMP.normalized_coefficient(caps[("A",:bess)],x[(:storage,1)])==25.0
        @test JuMP.normalized_rhs(caps[("A",:bess)])==270+25
        # Independent source horizon peak exceeds the two represented snapshots.
        @test d["paper_a_extension"]["expansion_policy"]["peak_load_MW_by_bus"]["A"]==90
        JuMP.@constraint(pm.model,x[(:gen,2)]==2+6)
        ocgt=JuMP.@constraint(pm.model,x[(:gen,3)]==1+3)
        bess=JuMP.@constraint(pm.model,x[(:storage,1)]==1+10)
        for (n,flow) in ((1,-0.04),(2,0.04))
            JuMP.@constraint(pm.model,_PM.var(pm,n,:p_dc,(1,1,2))==flow)
        end
        @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
        for (n,flow) in ((1,-0.04),(2,0.04))
            @test JuMP.value(_PM.var(pm,n,:p_dc,(1,1,2)))≈flow
            @test JuMP.value(_PM.var(pm,n,:p_dc,(1,2,1)))≈-flow
        end
        JuMP.set_normalized_rhs(ocgt,1+4)
        @test _ap2_expansion_solve!(pm)==JuMP.MOI.INFEASIBLE
        JuMP.set_normalized_rhs(ocgt,1+3)
        JuMP.set_normalized_rhs(bess,1+11)
        @test _ap2_expansion_solve!(pm)==JuMP.MOI.INFEASIBLE
    end

    @testset "Zero peak permits no new capacity" begin
        d=_ap2_expansion_fixture()
        for sn in values(d["nw"])
            gas=sn["gen"]["3"]
            gas["gen_bus"]=2
            gas["region_id"]="R2"
        end
        pm=_ap2_expansion_model(_ap2_expansion_prepared(d))
        @test haskey(_PM.con(pm,1,:paper_a_expansion_limits),("B",:gas))
        x=_PM.var(pm,1,:n_block,(:gen,3))
        JuMP.@objective(pm.model,Max,x)
        @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
        @test JuMP.value(x)≈1.0
    end

    @testset "Existing and candidate batteries share the BESS cap" begin
        d=_ap2_expansion_fixture()
        for sn in values(d["nw"])
            candidate=deepcopy(sn["storage"]["1"])
            candidate["name"]="New battery"
            candidate["carrier"]="battery"
            candidate["n0"]=0
            candidate["na0"]=0
            candidate["energy"]=0.0
            sn["ne_storage"]["1"]=candidate
        end
        pm=_ap2_expansion_model(_ap2_expansion_prepared(d))
        x=_PM.var(pm,1,:n_block)
        cap=_PM.con(pm,1,:paper_a_expansion_limits)[("A",:bess)]
        @test JuMP.normalized_coefficient(cap,x[(:storage,1)])==25.0
        @test JuMP.normalized_coefficient(cap,x[(:ne_storage,1)])==25.0
        @test JuMP.normalized_rhs(cap)==270+25
        JuMP.@constraint(pm.model,x[(:storage,1)]==1+6)
        JuMP.@objective(pm.model,Max,x[(:ne_storage,1)])
        @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
        @test JuMP.value(x[(:ne_storage,1)])≈4
    end

    @testset "Reject malformed, unauthorized or tampered planning inputs" begin
        original=_ap2_expansion_fixture()
        policy(d)=d["paper_a_extension"]["expansion_policy"]
        peaks(d)=policy(d)["peak_load_MW_by_bus"]
        first_snapshot(d)=d["nw"]["1"]
        for mutate in (d->(policy(d)["id"]="bad"),
                       d->delete!(peaks(d),"B"),
                       d->(peaks(d)["C"]=0.0),
                       d->(peaks(d)["A"]=79.0),
                       d->(peaks(d)["B"]=-1.0),
                       d->(peaks(d)["B"]=true),
                       d->(peaks(d)["A"]=floatmax(Float64)),
                       d->(first_snapshot(d)["bus"]["1"]["vmax"]=1.1),
                       d->(first_snapshot(d)["dcline"]["1"]["loss0"]=0.01),
                       d->(first_snapshot(d)["dcline"]["1"]["loss1"]=0.01),
                       d->foreach(sn->(sn["gen"]["1"]["nmax"]=2),values(d["nw"])),
                       d->(d["nw"]["2"]["gen"]["3"]["carrier"]="onwind"))
            d=deepcopy(original)
            mutate(d)
            @test_throws ArgumentError _ap2_expansion_model(_ap2_expansion_prepared(d))
        end

        conflicting=deepcopy(original)
        conflicting["nw"]["1"]["paper_a_extension"]=deepcopy(_ap2_marker())
        conflicting["nw"]["1"]["paper_a_extension"]["expansion_policy"]=Dict("id"=>"different")
        @test_throws ArgumentError _FP.prepare_paper_a_data!(conflicting)

        d=_ap2_expansion_prepared(deepcopy(original))
        peaks(d)["A"]=180.0
        err=try
            _ap2_expansion_model(d)
            nothing
        catch ex
            ex
        end
        @test err isa ArgumentError
        @test occursin("AP1_PROFILE_CONTENT_IDENTITY_MISMATCH",sprint(showerror,err))
    end

    @testset "UC event coefficients and profile identity" begin
        data=_ap2_expansion_fixture()
        for sn in values(data["nw"]), id in ("2","3")
            gen=sn["gen"][id]
            gen["na0"]=0
            gen["startup_cost_per_mw"]=800.0
            gen["shutdown_cost_per_mw"]=0.0
        end
        data=_ap2_expansion_prepared(data)
        pm=_ap2_expansion_model(data)
        for nw in (1,2)
            events=_FP.calc_uc_gscr_block_startup_shutdown_cost(pm,nw)
            @test _PM.ref(pm,nw,:gen,2,"na0")==0
            @test JuMP.coefficient(events,_PM.var(pm,nw,:su_block,(:gen,2)))≈25*800*2
            @test JuMP.coefficient(events,_PM.var(pm,nw,:sd_block,(:gen,2)))==0.0
        end
        for field in ("startup_cost_per_mw","shutdown_cost_per_mw","na0")
            changed=deepcopy(data)
            changed["nw"]["1"]["gen"]["2"][field]+=1
            err=try
                _ap2_expansion_model(changed)
                nothing
            catch ex
                ex
            end
            @test err isa ArgumentError
            @test occursin("AP1_PROFILE_CONTENT_IDENTITY_MISMATCH",sprint(showerror,err))
        end
    end

    @testset "Opt-in gas requires thermal commitment after device overrides" begin
        data=_ap2_expansion_fixture()
        for sn in values(data["nw"])
            sn["gen"]["3"]["nmax"]=sn["gen"]["3"]["n0"]
        end
        override=Dict((:gen,3)=>_FP.BlockRenewableParticipation())
        err=try
            _ap2_expansion_model(_ap2_expansion_prepared(deepcopy(data));device_formulations=override)
            nothing
        catch ex
            ex
        end
        @test err isa ArgumentError
        @test occursin("requires BlockThermalCommitment for gas device 3",sprint(showerror,err))

        delete!(data["paper_a_extension"],"expansion_policy")
        pm=_ap2_expansion_model(_ap2_expansion_prepared(data);device_formulations=override)
        @test (:gen,3) ∉ axes(_PM.var(pm,1,:su_block),1)
    end
end

@testset "Independent source matrix reconstruction on a referred voltage base" begin
    data=_ap2_expansion_fixture()
    for sn in values(data["nw"])
        source=sn["gen"]["2"]
        source["native_source_kv_referred"]=16.0
        source["source_bus_base_kv"]=20.0
        source["b_block"]=0.78125
    end
    pm=_ap2_expansion_model(_ap2_expansion_prepared(data))
    JuMP.@constraint(pm.model,_PM.var(pm,1,:na_block,(:gen,2))==1)
    @test _ap2_expansion_solve!(pm)==JuMP.MOI.OPTIMAL
    affine=pm.ext[:paper_a_online][1]
    assets=Dict(
        "$table:$id"=>Dict("online"=>JuMP.value(_PM.var(pm,1,:na_block,(Symbol(table),parse(Int,id)))),
            "installed"=>JuMP.value(_PM.var(pm,1,:n_block,(Symbol(table),parse(Int,id)))),
            "dispatch_MW"=>0.0)
        for table in ("gen","storage") for id in keys(data["nw"]["1"][table]))
    diagnostic=_FP.PaperADiagnostics
    solution=Dict("snapshots"=>Dict("1"=>Dict("assets"=>assets,"affine"=>Dict(
        "B"=>diagnostic.rows(JuMP.value.(affine.B)),"M"=>diagnostic.rows(JuMP.value.(affine.M)),
        "p"=>JuMP.value.(affine.p_fl)))))
    result=diagnostic.reconstruct(data,solution,1)
    ccgt=only(filter(x->x["asset"]=="gen:2",result["source_ledger"]))
    @test ccgt["strength"]≈1.5*0.78125
    @test result["source_base_residual"]<1e-12
    @test result["affine_reconstruction_residual"]<1e-12

    changed=deepcopy(data)
    changed["nw"]["1"]["gen"]["2"]["b_block"]=0.5
    counter=diagnostic.reconstruct(changed,solution,1)
    @test counter["B"]==result["B"]
    @test counter["M"]==result["M"]
    @test counter["source_base_residual"]≈0.78125-0.5
end
