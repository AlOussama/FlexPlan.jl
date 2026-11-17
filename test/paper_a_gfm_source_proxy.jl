@testset "CoLib/EPRI fixed-E source projection" begin
    @test _FP._paper_a_full37_origin(_FP._PaperAProfileBinding("ap1:sha256:"*repeat("a",64),""),nothing)
    derived=_FP._PaperAProfileBinding("ap2:sha256:"*repeat("a",64),"")
    @test _FP._paper_a_full37_origin(derived,Dict("model"=>_FP._PAPER_A_GFM_PROXY_ID))
    @test !_FP._paper_a_full37_origin(derived,nothing)
    @test !_FP._paper_a_full37_origin(_FP._PaperAProfileBinding("ap2:sha256:"*repeat("a",62),""),Dict())
    beta=25/100*.15/(.15^2+.0015^2)
    @test _FP.PaperARegional.source_b_block(25.,100.,.15,.0015)≈beta
    @test _FP.PaperARegional.source_b_block(25.,100.,.25,0.)==_FP.PaperARegional.source_b_block(25.,100.,.25)==1.0
    @test _FP.PaperARegional.source_b_block(300.,100.,.25)==12.0
    @test_throws ArgumentError _FP.PaperARegional.source_b_block(25.,100.,.15,-.0015)
    d=_ap2_physical!(Dict{String,Any}(),"GFM";S=25.,P=25.)
    merge!(d,Dict("source_equivalent_type"=>"voltage_behind_series_impedance_frozen_E",
        "frozen_internal_voltage"=>true,"source_model_scope"=>"frozen_E_planning_proxy",
        "physical_controller_equivalent_qualified"=>false,"S_base_MVA"=>100.,
        "x_src"=>.15,"r_src"=>.0015,"mu_str"=>1.,"mu_fl"=>0.,"b_block"=>beta))
    @test _FP.PaperARegional.validate_source(d)
    @test _FP._paper_a_validate_gfm_proxy_device(d)===nothing
    for (key,value) in [("frozen_internal_voltage",false),("source_model_scope","physical_EPRI"),
                        ("physical_controller_equivalent_qualified",true),("b_block",1/.15),
                        ("native_source_MVA",100.)]
        bad=deepcopy(d);bad[key]=value
        @test_throws ArgumentError _FP.PaperARegional.validate_source(bad)
    end
    # A factor of two in referred voltage scales both R and X by four.
    voltage=deepcopy(d)
    voltage["native_source_kv_referred"]=40.
    voltage["source_bus_base_kv"]=20.
    voltage["b_block"]=beta/4
    @test _FP.PaperARegional.validate_source(voltage)
    native=deepcopy(d)
    native["native_parameter_base"]="source_MVA"
    native["native_source_MVA"]=100.
    native["b_block"]=4beta
    @test _FP.PaperARegional.validate_source(native)
    proxy=Dict{String,Any}("model"=>_FP._PAPER_A_GFM_PROXY_ID,"scope"=>"frozen_E_planning_proxy",
        "x_device_pu"=>.15,"r_device_pu"=>.0015,"S_block_MVA"=>25,"synchronous_xdpp"=>.25,
        "parent_AP1_sha256"=>repeat("a",64),"owner_decision"=>"2026-11-17: bilde beide modelle gleich ähnlich aus")
    spec=Dict{String,Any}("technical_gfm_source_proxy"=>proxy,"technical_week"=>Dict(
        "kind"=>"technical_independent_week_2013_v1","hours"=>168))
    data=Dict{String,Any}("baseMVA"=>100.,"nw"=>Dict(string(i)=>Dict() for i in 1:168),
        "paper_a_extension"=>Dict("full37_specification"=>spec))
    @test _FP._paper_a_gfm_proxy(data)==proxy
    for (key,value) in [("r_device_pu",0.),("S_block_MVA",100),("synchronous_xdpp",.3),
                        ("parent_AP1_sha256",repeat("a",62))]
        bad=deepcopy(data);bad["paper_a_extension"]["full37_specification"]["technical_gfm_source_proxy"][key]=value
        @test_throws ArgumentError _FP._paper_a_gfm_proxy(bad)
    end
    bad=deepcopy(data);delete!(bad["paper_a_extension"]["full37_specification"],"technical_week")
    @test_throws ArgumentError _FP._paper_a_gfm_proxy(bad)
    bad=deepcopy(data);bad["nw"]=Dict(string(i)=>Dict() for i in 1:8760)
    @test_throws ArgumentError _FP._paper_a_gfm_proxy(bad)
    original=deepcopy(data);delete!(original["paper_a_extension"]["full37_specification"],"technical_gfm_source_proxy")
    @test _FP._paper_a_gfm_proxy(original)===nothing
end

@testset "Independent fixed-E R/X diagnostic reconstruction" begin
    raw=_ap2_fixture(;hours=1)
    sn=raw["nw"]["1"]
    syn=sn["gen"]["2"]
    syn["x_src"]=.25
    syn["mu_str"]=1.
    syn["b_block"]=syn["native_source_MVA"]/(250*.25)
    gfm=sn["storage"]["1"]
    merge!(gfm,Dict("source_equivalent_type"=>"voltage_behind_series_impedance_frozen_E",
        "x_src"=>.15,"r_src"=>.0015,"mu_str"=>1.,"mu_fl"=>0.,"frozen_internal_voltage"=>true,
        "source_model_scope"=>"frozen_E_planning_proxy","physical_controller_equivalent_qualified"=>false))
    assets=Dict{String,Any}("$table:$id"=>Dict("installed"=>1.,"online"=>1.,"dispatch_MW"=>0.)
        for table in ("gen","storage","ne_storage") for id in keys(sn[table]))
    solution=Dict("snapshots"=>Dict("1"=>Dict("assets"=>assets)))
    for resistance in (.0015,0.)
        gfm["r_src"]=resistance
        expected=25/250*.15/(resistance^2+.15^2)
        gfm["b_block"]=expected
        rec=_FP.PaperADiagnostics.reconstruct(raw,solution,1)
        @test rec["source_base_residual"]<1e-12
        @test only(r for r in rec["source_ledger"] if r["class"]=="GFM")["strength"]≈expected
        @test only(r for r in rec["source_ledger"] if r["class"]=="SYN")["strength"]≈.4
        @test rec["b_src"][1]≈.4+expected
    end
    gfm["r_src"]=.0015
    gfm["native_parameter_base"]="source_MVA"
    gfm["native_source_MVA"]=50.
    gfm["native_source_kv_referred"]=40.
    gfm["source_bus_base_kv"]=20.
    expected=50/250*.15/(.0015^2+.15^2)/4
    gfm["b_block"]=expected
    rec=_FP.PaperADiagnostics.reconstruct(raw,solution,1)
    @test rec["source_base_residual"]<1e-12
    @test only(r for r in rec["source_ledger"] if r["class"]=="GFM")["strength"]≈expected
    @test only(r for r in rec["source_ledger"] if r["class"]=="SYN")["strength"]≈.4
    @test rec["b_src"][1]≈.4+expected
end

function _gfm_proxy_api_fixture()
    d=_full37_fixture(;hours=168)
    d["baseMVA"]=100.0
    spec=d["paper_a_extension"]["full37_specification"]
    spec["technical_week"]=Dict("kind"=>"technical_independent_week_2013_v1","hours"=>168)
    for sn in values(d["nw"])
        sn["baseMVA"]=100.0
        for table in ("gen","storage","ne_storage"),dev in values(get(sn,table,Dict()))
            haskey(dev,"source_class") || continue
            dev["S_base_MVA"]=100.0
            dev["b_block"]*=2.5
        end
        for i in 1:35
            dev=deepcopy(sn["ne_storage"]["7"])
            dev["name"]="synthetic extra GFM $i"
            dev["index"]=100+i
            sn["ne_storage"][string(100+i)]=dev
        end
    end
    d[_FP._PAPER_A_PROFILE_KEY]=_FP._PaperAProfileBinding("ap1:sha256:"*repeat("a",64),_FP.paper_a_profile_identity(d))
    return d
end

@testset "GFM source overlay identity and atomic preflight" begin
    d=_gfm_proxy_api_fixture()
    before=deepcopy(d)
    _FP.apply_paper_a_gfm_source_proxy!(d;parent_AP1_sha256=repeat("a",64))
    @test _FP._paper_a_gfm_proxy(d)["model"]==_FP._PAPER_A_GFM_PROXY_ID
    @test _FP._paper_a_profile_binding(d).digest==_FP.paper_a_profile_identity(d)
    @test d[_FP._PAPER_A_PROFILE_KEY].digest!=before[_FP._PAPER_A_PROFILE_KEY].digest
    @test d[_FP._PAPER_A_PROFILE_KEY].run_identity==before[_FP._PAPER_A_PROFILE_KEY].run_identity
    allowed=Set(["source_equivalent_type","source_equivalent_valid","frozen_internal_voltage",
        "source_model_scope","physical_controller_equivalent_qualified","x_src","r_src",
        "S_base_MVA","native_parameter_base","native_source_MVA","native_source_kv_referred",
        "source_bus_base_kv","x_src_block_base","b_block","mu_str","mu_fl",
        "source_parameter_provenance","source_equivalent_time_scale","electrical_interface_evidence",
        "source_b_block_pu_reference","paper_a_full37_online"])
    for (t,sn) in d["nw"]
        changed=0
        for table in ("gen","storage","ne_storage"),(id,dev) in sn[table]
            prior=before["nw"][t][table][id]
            if get(dev,"source_class",nothing)=="GFM"
                @test _FP._paper_a_validate_gfm_proxy_device(dev)===nothing
                @test Dict(k=>v for (k,v) in dev if !(k in allowed))==Dict(k=>v for (k,v) in prior if !(k in allowed))
                changed+=1
            else
                @test dev==prior
            end
        end
        @test changed==37
        for key in ("bus","branch","load","dcline","paper_a_temporal")
            @test sn[key]==before["nw"][t][key]
        end
    end
    @test_throws ArgumentError _FP.apply_paper_a_gfm_source_proxy!(d;parent_AP1_sha256=repeat("a",64))
    for (index,mutate) in enumerate((
        x->nothing,
        x->delete!(x["nw"]["2"]["ne_storage"],"101"),
        x->(x["nw"]["2"]["bus"]["1"]["base_kv"]=0.0),
        x->delete!(x["paper_a_extension"]["full37_specification"],"technical_week"),
    ))
        bad=deepcopy(before);mutate(bad)
        bad[_FP._PAPER_A_PROFILE_KEY]=_FP._PaperAProfileBinding("ap1:sha256:"*repeat("a",64),_FP.paper_a_profile_identity(bad))
        old=deepcopy(bad)
        parent=index==1 ? repeat("b",64) : repeat("a",64)
        @test_throws ArgumentError _FP.apply_paper_a_gfm_source_proxy!(bad;parent_AP1_sha256=parent)
        @test bad==old
    end
    bad=deepcopy(before);old=deepcopy(bad)
    @test_throws ArgumentError _FP.apply_paper_a_gfm_source_proxy!(bad;parent_AP1_sha256=repeat("a",62))
    @test bad==old
end
