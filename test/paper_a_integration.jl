using LinearAlgebra
import JSON
const _AP2_EVIDENCE=Dict{String,Any}()

@testset "AP2 parser network and matrix" begin
    d=_ap2_fixture();sn=d["nw"]["1"];net=d["paper_a_network"]
    nr=PaperARegional.network_reference(net,sn["bus"],250.0)
    @test nr.Y ≈ [-10im 10im;10im -10im]
    @test nr.B0 ≈ [10.0 -10; -10 10]
    @test nr.B0_reference_residual<1e-12
    @test isempty(nr.eliminated) && nr.schur_residual==0
    # Genuine 3-bus passive elimination, with physical shunts before Schur.
    buses=deepcopy(sn["bus"]);buses["3"]=deepcopy(buses["2"])
    buses["3"]["name"]="E";buses["3"]["index"]=3
    n3=deepcopy(net);n3["physical_ac_bus_order"]=["A","E","B"]
    n3["retained_physical_buses"]=["A","B"];n3["eliminated_physical_buses"]=["E"]
    n3["bus_to_region"]["E"]="R1";n3["network_islands"]=[["A","E","B"]]
    n3["branch_primitives"]=[_ap2_primitive("A","E";x=0.5),_ap2_primitive("E","B";x=1.0)]
    n3["fixed_shunts"]=Dict("A"=>Dict("gs_pu"=>0.0,"bs_pu"=>-2.0),
        "E"=>Dict("gs_pu"=>0.0,"bs_pu"=>-2.0),"B"=>Dict("gs_pu"=>0.0,"bs_pu"=>-1.0))
    n3["B0_reference_pu"]=[[3.2,-0.4],[-0.4,1.8]]
    r3=PaperARegional.network_reference(n3,buses,250.0)
    @test r3.L ≈ [4.0 -2 0;-2 5 -1;0 -1 2]
    @test r3.B0 ≈ [3.2 -0.4;-0.4 1.8]
    @test r3.schur_residual < 1e-12
    @test r3.B0_reference_residual < 1e-12
    _AP2_EVIDENCE["schur_residual_inf"]=r3.schur_residual
    _AP2_EVIDENCE["B0_AP2_minus_AP1_inf"]=r3.B0_reference_residual
    for (field,value) in (("source_component","transformers"),("tap_ratio",1.1),("phase_shift",0.1),("x_pu",0.3),("bus1","DC_unknown"))
        bad=deepcopy(net);bad["branch_primitives"][1][field]=value
        @test_throws ArgumentError PaperARegional.network_reference(bad,sn["bus"],250.0)
    end
    for issues in (["grounding_reference_unverified"],["fixed_shunt_inventory_unverified"],["baseline_source_accounting_unverified"])
        bad=deepcopy(net);bad["passive_domain_issues"]=issues
        @test_throws ArgumentError PaperARegional.network_reference(bad,sn["bus"],250.0)
    end
    @test_throws ArgumentError PaperARegional.symmetric_z([1.0 0.1;0.1 1])
    @test_throws ArgumentError PaperARegional.symmetric_z([1.0 -1;-2 1])
    bad=deepcopy(net);bad["network_islands"]=[["A"],["B"]]
    @test_throws ArgumentError PaperARegional.network_reference(bad,sn["bus"],250.0)
    # Two genuine AC islands, each with a distinct reference, no slack grounding.
    isolated=deepcopy(net);isolated["branch_primitives"]=[];isolated["network_islands"]=[["A"],["B"]]
    isolated["reference_buses"]=["A","B"];isolated["B0_reference_pu"]=[[0.,0.],[0.,0.]]
    ib=deepcopy(sn["bus"]);ib["2"]["bus_type"]=3
    @test PaperARegional.network_reference(isolated,ib,250.).B0==zeros(2,2)
    for mutate in (x->(x["paper_a_extension"]["version"]="2.0"),
                   x->delete!(x["paper_a_extension"],"version"),
                   x->delete!(x["nw"]["1"],"paper_a_extension"))
        bad=deepcopy(d);mutate(bad)
        @test_throws ArgumentError _FP._paper_a_validate_markers(bad)
    end
    original=deepcopy(d);_FP.prepare_paper_a_data!(d)
    @test d==original
    @test sn["gen"]["1"]["p_block_max"] ≈ 0.4
    @test sn["gen"]["2"]["b_block"] ≈ 0.5
end

@testset "AP2 physical sources and planning" begin
    syn=_ap2_physical!(Dict{String,Any}(),"SYN")
    @test validate_source(syn)
    syn["native_parameter_base"]="device_MVA";syn["native_source_MVA"]=50.0
    syn["x_src"]=0.4 # x_block=.2 on 25 MVA: same strength .5.
    @test validate_source(syn)
    for (field,value) in (("native_source_MVA",nothing),("mu_str",nothing),("source_equivalent_time_scale","unverified"),
                          ("grid_control_mode","gfm"),("b_block",5.0),("source_class_evidence","unverified"),("x_src_block_base",0.9))
        bad=deepcopy(syn);bad[field]=value
        @test_throws ArgumentError validate_source(bad)
    end
    @test_throws ArgumentError validate_source(_ap2_physical!(Dict{String,Any}(),"SC"))
    d=_ap2_fixture();_FP.scale_paper_a_costs!(d)
    pm=_ap2_model(d)
    @test JuMP.is_integer(_PM.var(pm,1,:na_block,(:gen,2)))
    relaxed=_ap2_model(d;relax_block_variables=true)
    @test !JuMP.is_integer(_PM.var(relaxed,1,:na_block,(:gen,2)))
    @test _PM.ref(pm,1,:paper_a_coefficients)[(:gen,2)].strength≈0.75
    @test _PM.ref(pm,1,:paper_a_coefficients)[(:gen,1)].exposure≈0.32
    @test _PM.ref(pm,1,:paper_a_coefficients)[(:storage,1)].strength≈0.1
    @test haskey(_PM.ref(pm,1,:syn_devices),(:gen,2))
    @test !haskey(_PM.ref(pm,1,:gfm_devices),(:gen,2))
    @test_throws Exception _ap2_model(d;template=_FP.UCGSCRBlockTemplate(Dict((:gen,"SYN")=>_FP.BlockThermalCommitment())))
    for (conn,res) in ((1.0,0.0),(0.0,1.0))
        data=_ap2_fixture(;conn,res);_FP.scale_paper_a_costs!(data)
        model=_ap2_model(data;template=_ap2_template(fixed_gfl=true))
        _ap2_solve!(model)
        @test JuMP.value(_PM.var(model,1,:na_block,(:gen,1)))≈conn
        @test JuMP.value(model.ext[:paper_a_online][1].p_fl[1])≈0.32*conn
        @test JuMP.value(_PM.var(model,1,:pg,1))≈0.0 atol=1e-8
    end
    data=_ap2_fixture(;conn=0.5);_FP.scale_paper_a_costs!(data)
    @test_throws ArgumentError _ap2_model(data;template=_ap2_template(fixed_gfl=true))
    model=_ap2_solve!(_ap2_model(data))
    @test JuMP.value(_PM.var(model,1,:na_block,(:gen,1)))≈0.0 atol=1e-8
    # Fractional availability remains the exact inequality; integer counts
    # cannot use half of a single connected converter. No input rounding.
    @test data["nw"]["1"]["gen"]["1"]["a_conn"]==0.5
    relaxed=_ap2_model(data;relax_block_variables=true)
    _ap2_solve!(relaxed)
    @test JuMP.value(_PM.var(relaxed,1,:na_block,(:gen,1)))<=0.5+1e-8
    @test JuMP.objective_value(relaxed.model)<JuMP.objective_value(model.model)
    bad=_ap2_fixture();s=bad["nw"]["1"]["gen"]["2"]
    s["fixed_strength_already_in_network"]=true;s["b_block"]=0.5
    _FP.scale_paper_a_costs!(bad)
    @test_throws ArgumentError _ap2_model(bad)
    # Candidate BESS-GFM in :storage participates in actual investment and G1.
    candidate=_ap2_fixture()
    for sn in values(candidate["nw"])
        s=sn["storage"]["1"];s["n0"]=0;s["na0"]=0;s["nmax"]=4
        s["energy"]=0.0;s["mu_str"]=2.0;s["cost_inv_per_mw"]=0.1
    end
    _FP.scale_paper_a_costs!(candidate)
    model=_ap2_solve!(_ap2_model(candidate;storage_terminal_policy=:fixed_initial))
    @test JuMP.value(_PM.var(model,1,:n_block,(:storage,1)))>=1
    @test JuMP.value(_PM.var(model,1,:n_block,(:gen,2)))≈0 atol=1e-8
    @test !haskey(_PM.var(model,1),:z_strg_ne)
    # Permanent fixed source is included in Y exactly once, with no online
    # diagonal term and an explicit fixed-installed template override.
    fixed=_ap2_fixture(;alpha=1.0)
    fixed["paper_a_network"]["fixed_sources_in_network"]=["SYN"]
    fixed["paper_a_network"]["fixed_shunts"]=Dict("A"=>Dict("gs_pu"=>0.0,"bs_pu"=>-0.75))
    fixed["paper_a_network"]["fixed_source_shunt_by_asset"]=Dict("SYN"=>Dict("bus"=>"A","bs_pu"=>-0.75))
    fixed["paper_a_network"]["B0_reference_pu"]=[[10.75,-10.0],[-10.0,10.0]]
    for sn in values(fixed["nw"])
        s=sn["gen"]["2"];s["n0"]=1;s["nmax"]=1;s["na0"]=1
        s["fixed_strength_already_in_network"]=true;s["fixed_source_permanently_connected"]=true;s["b_block"]=0.0
    end
    _FP.scale_paper_a_costs!(fixed);template=_ap2_template()
    template.device_formulations[(:gen,2)]=_FP.BlockFixedInstalled()
    fm=_ap2_solve!(_ap2_model(fixed;template,storage_terminal_policy=:fixed_initial))
    @test _PM.ref(fm,1,:paper_a_coefficients)[(:gen,2)].strength==0
    @test _PM.ref(fm,1,:paper_a_regional).B0[1,1]≈10.75
    @test JuMP.value(_PM.var(fm,1,:na_block,(:gen,2)))≈1
end

@testset "AP2 real G1 optimization and independent residuals" begin
    objectives=Float64[];installed=Float64[]
    for alpha in (0.1,4.0)
        d=_ap2_fixture(;alpha);_FP.scale_paper_a_costs!(d)
        pm=_ap2_solve!(_ap2_model(d;storage_terminal_policy=:fixed_initial))
        push!(objectives,JuMP.objective_value(pm.model))
        push!(installed,JuMP.value(_PM.var(pm,1,:n_block,(:gen,2))))
        maxres=0.0;maxsoc=0.0;maxbalance=0.0
        invest=250.0*installed[end];dispatch=0.0;events=0.0
        for t in 1:2
            on=JuMP.value(_PM.var(pm,t,:na_block,(:gen,2)))
            fl=JuMP.value(_PM.var(pm,t,:na_block,(:gen,1)))
            st=JuMP.value(_PM.var(pm,t,:na_block,(:storage,1)))
            # Independent coefficients from physical fixture, not JuMP rows.
            B=[10.0+0.75*on+0.1*st -10.0;-10.0 10.0]
            p=[0.8*100/250*fl,0.0]
            @test [JuMP.value(x) for x in pm.ext[:paper_a_online][t].B] ≈ B
            @test JuMP.value.(pm.ext[:paper_a_online][t].S_diag)≈p
            slack=B[1,1]-10-alpha*p[1];@test slack>=-1e-8
            maxres=max(maxres,max(0.0,-slack))
            pg1=JuMP.value(_PM.var(pm,t,:pg,1));pg2=JuMP.value(_PM.var(pm,t,:pg,2))
            sc=JuMP.value(_PM.var(pm,t,:sc,1));sd=JuMP.value(_PM.var(pm,t,:sd,1))
            se=JuMP.value(_PM.var(pm,t,:se,1))
            prev=t==1 ? 75/250 : JuMP.value(_PM.var(pm,t-1,:se,1))
            maxsoc=max(maxsoc,abs(se-prev-3*(0.9*sc-sd/0.9)))
            maxbalance=max(maxbalance,abs(pg1+pg2+sd-sc-0.4))
            dispatch+=3*250*(pg1+20*pg2)
            su=JuMP.value(_PM.var(pm,t,:su_block,(:gen,2)));ss=JuMP.value(_PM.var(pm,t,:sd_block,(:gen,2)))
            events+=2*25*(2*su+3*ss)
            @test JuMP.coefficient(pm.ext[:paper_a_online][t].b_src[1],_PM.var(pm,t,:pg,2))==0
        end
        @test JuMP.objective_value(pm.model)≈invest+dispatch+events atol=1e-7
        @test maxsoc<1e-9 && maxbalance<1e-9
        _AP2_EVIDENCE["alpha_$(alpha)"]=Dict("termination"=>string(JuMP.termination_status(pm.model)),
            "primal"=>string(JuMP.primal_status(pm.model)),"dual"=>string(JuMP.dual_status(pm.model)),
            "objective"=>objectives[end],"investment"=>invest,"dispatch"=>dispatch,"events"=>events,
            "cost_residual"=>abs(objectives[end]-invest-dispatch-events),"soc_residual"=>maxsoc,
            "power_balance_residual"=>maxbalance,"G1_violation"=>maxres,
            "installed_SYN"=>installed[end],"relative_gap"=>JuMP.relative_gap(pm.model))
    end
    @test installed[2]>installed[1]
    @test objectives[2]>objectives[1]
    d=_ap2_fixture();_FP.scale_paper_a_costs!(d)
    result=_FP.uc_gscr_block_integration(d,_PM.DCPPowerModel,milp_optimizer;template=_ap2_template())
    @test result["termination_status"]==JuMP.MOI.OPTIMAL
    # The solved builder also supports a real passive elimination, rather
    # than only testing an isolated algebraic Schur helper.
    reduced=_ap2_fixture()
    net=reduced["paper_a_network"]
    net["physical_ac_bus_order"]=["A","E","B"]
    net["eliminated_physical_buses"]=["E"];net["bus_to_region"]["E"]="R1"
    net["network_islands"]=[["A","E","B"]]
    net["branch_primitives"]=[_ap2_primitive("A","E";x=.5),_ap2_primitive("E","B";x=1.)]
    net["B0_reference_pu"]=[[2/3,-2/3],[-2/3,2/3]]
    for sn in values(reduced["nw"])
        sn["bus"]["3"]=deepcopy(sn["bus"]["2"])
        sn["bus"]["3"]["name"]="E";sn["bus"]["3"]["index"]=3;sn["bus"]["3"]["bus_i"]=3
        a=sn["branch"]["1"];a["t_bus"]=3;a["br_x"]=.5
        b=deepcopy(a);b["f_bus"]=3;b["t_bus"]=2;b["index"]=2;b["br_x"]=1.;sn["branch"]["2"]=b
    end
    _FP.scale_paper_a_costs!(reduced);rm=_ap2_solve!(_ap2_model(reduced))
    @test _PM.ref(rm,1,:paper_a_regional).B0≈[2/3 -2/3;-2/3 2/3]
    @test _PM.ref(rm,1,:paper_a_regional).eliminated==["E"]
end

@testset "AP2 economic coefficients time and block events" begin
    d=_ap2_fixture();_FP.scale_paper_a_costs!(d);pm=_ap2_model(d)
    obj=JuMP.objective_function(pm.model)
    @test JuMP.coefficient(obj,_PM.var(pm,1,:pg,2))≈20*250*3
    @test JuMP.coefficient(obj,_PM.var(pm,1,:su_block,(:gen,2)))≈25*2*2
    @test JuMP.coefficient(obj,_PM.var(pm,1,:sd_block,(:gen,2)))≈25*3*2
    @test JuMP.coefficient(obj,_PM.var(pm,1,:n_block,(:gen,2)))≈25*10
    @test_throws ArgumentError _FP.scale_paper_a_costs!(d)
    overnight=_ap2_fixture()
    for sn in values(overnight["nw"])
        sn["uc_gscr_block_cost_convention"]["capex_basis"]="overnight_per_mw"
        dev=sn["gen"]["2"];dev["lifetime"]=20.0;dev["discount_rate"]=0.0;dev["fixed_om_percent"]=2.0
    end
    _FP.scale_paper_a_costs!(overnight)
    opm=_ap2_model(overnight)
    @test JuMP.coefficient(JuMP.objective_function(opm.model),_PM.var(opm,1,:n_block,(:gen,2)))≈25*10*(1/20+0.02)
    # Exact scale_data! path and 24 x 3h conditional annual representation.
    d=_ap2_fixture(;hours=24)
    _FP.dim_prop(d,:scenario,1)["probability"]=1.0
    for t in d["paper_a_temporal"]
        t["representative_repetitions"]=8760/72;t["event_repetitions"]=8760/72
        t["scenario_probability"]=1.0;t["dispatch_weight"]=365.0;t["event_weight"]=8760/72
    end
    for (id,sn) in d["nw"]
        sn["paper_a_temporal"]=d["paper_a_temporal"][parse(Int,id)]
        _FP.scale_data!(sn;number_of_hours=24)
    end
    pm=_ap2_model(d)
    obj=JuMP.objective_function(pm.model)
    @test JuMP.coefficient(obj,_PM.var(pm,1,:pg,2))≈20*250*365
    @test JuMP.coefficient(obj,_PM.var(pm,1,:su_block,(:gen,2)))≈25*2*(8760/72)
    @test JuMP.coefficient(obj,_PM.var(pm,1,:n_block,(:gen,2)))≈250
    @test_throws ArgumentError _FP.scale_data!(d["nw"]["1"];number_of_hours=24)
    # Starts and stops are three blocks for 1->4 and 5->2, respectively.
    data=_ap2_fixture()
    for sn in values(data["nw"]);sn["gen"]["2"]["n0"]=5;sn["gen"]["2"]["nmax"]=5;sn["gen"]["2"]["na0"]=1;end
    _FP.scale_paper_a_costs!(data);model=_ap2_model(data)
    JuMP.fix(_PM.var(model,1,:na_block,(:gen,2)),4;force=true)
    JuMP.fix(_PM.var(model,2,:na_block,(:gen,2)),5;force=true)
    _ap2_solve!(model)
    @test JuMP.value(_PM.var(model,1,:su_block,(:gen,2)))≈3.0
    data=_ap2_fixture()
    for sn in values(data["nw"]);sn["gen"]["2"]["n0"]=5;sn["gen"]["2"]["nmax"]=5;sn["gen"]["2"]["na0"]=5;end
    _FP.scale_paper_a_costs!(data);model=_ap2_model(data)
    JuMP.fix(_PM.var(model,1,:na_block,(:gen,2)),2;force=true)
    _ap2_solve!(model)
    @test JuMP.value(_PM.var(model,1,:sd_block,(:gen,2)))≈3.0
    # An actual charge/discharge trajectory checks physical 3h SOC and both
    # efficiencies, independently of representative dispatch-hour weights.
    storage=_ap2_fixture()
    _FP.scale_paper_a_costs!(storage)
    model=_ap2_model(storage;template=_ap2_template(gscr=_FP.NoGSCR()),storage_terminal_policy=:none)
    JuMP.fix(_PM.var(model,1,:sc,1),.02;force=true)
    JuMP.fix(_PM.var(model,1,:sd,1),0.0;force=true)
    JuMP.fix(_PM.var(model,2,:sc,1),0.0;force=true)
    JuMP.fix(_PM.var(model,2,:sd,1),.018;force=true)
    _ap2_solve!(model)
    @test JuMP.value(_PM.var(model,1,:se,1))≈.3+3*.9*.02
    @test JuMP.value(_PM.var(model,2,:se,1))≈.3+3*.9*.02-3*.018/.9
    # Candidate storage cannot inject unbalanced power outside the bus balance.
    candidate=_ap2_fixture()
    for sn in values(candidate["nw"])
        s=pop!(sn["storage"],"1");s["n0"]=0;s["na0"]=0;s["nmax"]=2;s["energy"]=0.0
        sn["ne_storage"]["1"]=s
    end
    _FP.scale_paper_a_costs!(candidate)
    tmpl=_ap2_template(gscr=_FP.NoGSCR())
    tmpl.carrier_formulations[(:ne_storage,"GFM")]=_FP.BlockStorageParticipation()
    model=_ap2_model(candidate;template=tmpl,storage_terminal_policy=:none)
    JuMP.fix(_PM.var(model,1,:sc_ne,1),.02;force=true)
    JuMP.fix(_PM.var(model,1,:sd_ne,1),0.0;force=true)
    _ap2_solve!(model)
    @test sum(JuMP.value(_PM.var(model,1,:pg,g)) for g in (1,2))≈.42
    priced=_ap2_fixture()
    for sn in values(priced["nw"]);sn["storage"]["1"]["marginal_cost"]=2.0;end
    _FP.scale_paper_a_costs!(priced)
    @test_throws ArgumentError _ap2_model(priced)
    model=_ap2_model(priced;template=_ap2_template(gscr=_FP.NoGSCR(),storage_cost_policy=:discharge),storage_terminal_policy=:none)
    JuMP.fix(_PM.var(model,1,:sc,1),.02;force=true)
    JuMP.fix(_PM.var(model,1,:sd,1),0.0;force=true)
    JuMP.fix(_PM.var(model,2,:sc,1),0.0;force=true)
    JuMP.fix(_PM.var(model,2,:sd,1),.018;force=true)
    _ap2_solve!(model)
    @test JuMP.coefficient(JuMP.objective_function(model.model),_PM.var(model,2,:sd,1))≈2*250*3
    @test JuMP.value(_FP._paper_a_storage_operation_cost(model,2))≈27.0
    _AP2_EVIDENCE["nonzero_storage_variable_cost"]=27.0
    _AP2_EVIDENCE["storage_cost_rule"]="AC_side_discharge_MWh_only_charge_not_billed"
    unpriced=_ap2_fixture()
    for sn in values(unpriced["nw"]);sn["gen"]["2"]["cost_inv_per_mw"]=0.0;end
    _FP.scale_paper_a_costs!(unpriced)
    @test_throws ArgumentError _ap2_model(unpriced)
    # A synthetic test scope cannot be applied to a real/unclassified dataset.
    template=_ap2_template();scoped=_FP.UCGSCRBlockTemplate(template.carrier_formulations,template.gscr_formulation;paper_a_validation_scope=:synthetic_regression)
    @test_throws ArgumentError _ap2_model(priced;template=scoped)
end

if haskey(ENV,"PAPER_A_AP2_EVIDENCE")
    open(ENV["PAPER_A_AP2_EVIDENCE"],"w") do io
        JSON.print(io,_AP2_EVIDENCE,2)
    end
end
