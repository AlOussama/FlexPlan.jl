# Deterministic consumer fixtures: these numbers are test inputs, never prices
# or reactance evidence for a real study.
function _ap2_marker()
    Dict{String,Any}("name"=>"scientific_physical_data","version"=>"1.0","flexplan_ap2_required"=>true)
end

function _ap2_primitive(a,b;name=a*b,x=0.1,r=0.0,base=250.0,kv=20.0,bc=0.0)
    z=kv^2/base
    Dict{String,Any}("name"=>name,"source_component"=>"lines","bus0"=>a,"bus1"=>b,
        "status"=>1,"r_phys"=>r*z,"x_phys"=>x*z,"b_siemens"=>bc/z,
        "v_base_kv"=>kv,"z_base"=>z,"r_pu"=>r,"x_pu"=>x,"b_pu"=>bc)
end

function _ap2_physical!(d,cls;P=25.0,S=P,n0=0,nmax=8,na0=n0,mu=1.5,conn=1.0,res=1.0)
    mode=cls=="GFL" ? "gfl" : cls=="GFM" ? "gfm" : "not_applicable"
    _uc_gscr_add_block_fields!(d,mode;carrier=cls,n0,nmax,na0,p_block_max=P,
        b_block=cls=="GFL" ? 0.0 : S/250/0.2,p_min_pu=cls=="SYN" ? 0.1 : 0.0,
        cost_inv_per_mw=10.0,startup_cost_per_mw=2.0,shutdown_cost_per_mw=3.0)
    merge!(d,Dict{String,Any}("source_class"=>cls,"source_class_evidence"=>"synthetic_declared_interface",
        "electrical_interface_evidence"=>"synthetic_declared_interface",
        "source_equivalent_type"=>"voltage_behind_reactance","source_equivalent_valid"=>true,
        "source_equivalent_time_scale"=>"synthetic_static_equivalent","source_parameter_provenance"=>"synthetic_fixture",
        "native_parameter_base"=>"block_MVA","native_source_MVA"=>S,"S_block_MVA"=>S,"S_base_MVA"=>250.0,
        "p_block_max_MW"=>P,"x_src"=>0.2,"mu_str"=>mu,"mu_fl"=>0.8,
        "fixed_strength_already_in_network"=>false,"a_conn"=>conn,"a_res"=>res,
        "a_conn_provenance"=>"synthetic_declared_connection","region_id"=>"R1"))
    d
end

function _ap2_fixture(;hours=2,alpha=4.0,conn=1.0,res=1.0)
    d=_FP.parse_file(joinpath(@__DIR__,"data","case2","case2_d_strg.m"))
    # Reconstruct raw physical data from the existing operational fixture.
    _PM.make_mixed_units!(d)
    d["baseMVA"]=250.0;d["per_unit"]=false
    d["block_model_schema"]=_uc_gscr_block_schema_v2();d["paper_a_extension"]=_ap2_marker()
    d["uc_gscr_block_cost_convention"]=Dict("capex_basis"=>"annualized_per_mw_year")
    d["operation_weight"]=1.0;d["time_elapsed"]=3.0;d["g_min"]=alpha
    d["ne_storage"]=Dict{String,Any}();d["shunt"]=Dict{String,Any}()
    d["bus"]["1"]["name"]="A";d["bus"]["2"]["name"]="B"
    br=d["branch"]["1"];br["br_r"]=0.0;br["br_x"]=0.1;br["rate_a"]=500.0
    for l in values(d["load"]); l["pd"]=100.0;l["qd"]=0.0;end
    pv=d["gen"]["1"];pv["name"]="PV";pv["cost"]=[1.0,0.0]
    pv["pmax"]=100.0;pv["pmin"]=0.0
    _ap2_physical!(pv,"GFL";P=100.0,S=100.0,n0=1,nmax=1,conn,res)
    syn=deepcopy(pv);syn["index"]=2;syn["name"]="SYN";syn["cost"]=[20.0,0.0]
    _ap2_physical!(syn,"SYN");d["gen"]["2"]=syn
    s=d["storage"]["1"];s["name"]="BESS";s["energy"]=75.0;s["energy_rating"]=150.0
    s["charge_rating"]=25.0;s["discharge_rating"]=25.0;s["thermal_rating"]=50.0
    s["self_discharge_rate"]=0.0
    _ap2_physical!(s,"GFM";n0=1,nmax=1,mu=0.2)
    s["e_block"]=150.0
    # Region R2 has no sources and remains in the strength matrix.
    d["paper_a_network"]=Dict{String,Any}("physical_ac_bus_order"=>["A","B"],
        "retained_physical_buses"=>["A","B"],"eliminated_physical_buses"=>String[],
        "bus_to_region"=>Dict("A"=>"R1","B"=>"R2"),"network_islands"=>[["A","B"]],
        "reference_buses"=>["A"],"fixed_shunts"=>Dict{String,Any}(),
        "branch_primitives"=>[_ap2_primitive("A","B")],"fixed_sources_in_network"=>String[],
        "passive_domain_issues"=>String[],"B0_reference_pu"=>[[10.0,-10.0],[-10.0,10.0]])
    temporal=[Dict{String,Any}("snapshot_id"=>string(t),"delta_t_h"=>3.0,
        "representative_repetitions"=>2.0,"event_repetitions"=>4.0,"scenario_probability"=>0.5,
        "dispatch_weight"=>3.0,"event_weight"=>2.0) for t in 1:hours]
    _FP.add_dimension!(d,:hour,hours)
    _FP.add_dimension!(d,:scenario,Dict(1=>Dict{String,Any}("probability"=>0.5)))
    _FP.add_dimension!(d,:year,1;metadata=Dict{String,Any}("scale_factor"=>1))
    mn=_FP.make_multinetwork(d,Dict{String,Any}();share_data=false)
    mn["paper_a_temporal"]=temporal
    _FP.prepare_paper_a_data!(mn)
    return mn
end

function _ap2_template(;gscr=_FP.GershgorinGSCR(),fixed_gfl=false)
    _FP.UCGSCRBlockTemplate(Dict(
        (:gen,"GFL")=>(fixed_gfl ? _FP.BlockFixedInstalled() : _FP.BlockRenewableParticipation()),
        (:gen,"SYN")=>_FP.BlockThermalCommitment(),
        (:storage,"GFM")=>_FP.BlockStorageParticipation()),gscr)
end

function _ap2_model(data;template=_ap2_template(),kwargs...)
    _PM.instantiate_model(data,_PM.DCPPowerModel,
        pm->_FP.build_uc_gscr_block_integration(pm;template,kwargs...);
        ref_extensions=[_FP.ref_add_gen!,_FP.ref_add_storage!,_FP.ref_add_ne_storage!,_FP.ref_add_uc_gscr_block!])
end

function _ap2_solve!(pm)
    JuMP.set_optimizer(pm.model,HiGHS.Optimizer);JuMP.set_silent(pm.model);JuMP.optimize!(pm.model)
    @test JuMP.termination_status(pm.model)==JuMP.MOI.OPTIMAL
    @test JuMP.primal_status(pm.model)==JuMP.MOI.FEASIBLE_POINT
    return pm
end
