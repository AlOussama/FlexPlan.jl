# Explicit, externally pinned parameter permission. It is per data object and
# checked again when constructing a reference, including after cost scaling.
const _PAPER_A_QUALIFICATION_VERSION="paper_a_parameter_qualification/1.0"

function _paper_a_qualification_bindings(data,registry_path,scenarios_path)
    q=get(data,"paper_a_parameter_qualification",nothing)
    q isa AbstractDict || throw(ArgumentError("missing parameter qualification annex"))
    for (key,value) in (("version",_PAPER_A_QUALIFICATION_VERSION),("qualification_scope","parametric_study"),
                       ("qualification_status","qualified_parametric"),("evidence_class","explicit_study_assumption"),("parameter_registry_id","paper_a_strang_b_v1"))
        get(q,key,nothing)==value || throw(ArgumentError("unsupported qualification $key"))
    end
    get(data["paper_a_extension"],"dataset_kind",nothing)=="parametric_study" || throw(ArgumentError("parametric registry requires matching dataset kind"))
    for (path,key) in ((registry_path,"parameter_registry_sha256"),(scenarios_path,"scenario_config_sha256"))
        isfile(path) && bytes2hex(SHA.sha256(read(path)))==get(q,key,nothing) || throw(ArgumentError("qualification hash mismatch: $key"))
    end
    scenario_config=TOML.parsefile(scenarios_path)
    get(scenario_config,"version",nothing)==_PAPER_A_QUALIFICATION_VERSION || throw(ArgumentError("scenario version mismatch"))
    get(scenario_config,"source_baseline_sha",nothing)==get(q,"source_baseline_sha",nothing) || throw(ArgumentError("source baseline mismatch"))
    matches=filter(s->s["id"]==q["scenario_id"],scenario_config["scenarios"])
    length(matches)==1 || throw(ArgumentError("unknown/duplicate scenario"))
    scenario=only(matches)
    scenario["snapshots"]==length(data["nw"]) || throw(ArgumentError("scenario snapshot count mismatch"))
    assumptions=Set(scenario["network_assumptions"])
    assumptions==Set(["no_additional_fixed_shunts","no_sources_embedded_in_passive_Y","floating_network_no_grounding_shunt"]) || throw(ArgumentError("unsupported network assumptions"))
    bindings=Dict{Tuple{String,String},Any}()
    for r in CSV.File(registry_path;types=String)
        r.study_scenario==q["scenario_id"] || continue
        r.qualification_status=="qualified_parametric" && !ismissing(r.value) || throw(ArgumentError("blocked/missing scenario parameter"))
        r.evidence_class in ("legacy_default","derived_from_legacy","explicit_study_assumption","literature_supported") || throw(ArgumentError("unqualified evidence class"))
        key=(String(r.asset_id),String(r.field))
        haskey(bindings,key) && throw(ArgumentError("duplicate parameter binding $key"))
        bindings[key]=r.value_type=="number" ? parse(Float64,r.value) : String(r.value)
    end
    isempty(bindings) && throw(ArgumentError("empty registry scenario"))
    return bindings,scenario
end

function _paper_a_compare(actual,expected,label)
    ok=expected isa Real ? actual isa Real && isfinite(actual) && isapprox(actual,expected;atol=1e-8,rtol=1e-9) : actual==expected
    ok || throw(ArgumentError("canonical parameter mismatch: $label"))
end

function _paper_a_validate_registered!(data)
    permission=get(data,"_paper_a_parameter_registration",nothing)
    permission isa AbstractDict || throw(ArgumentError("call register_paper_a_parameters! with canonical files before using parametric_study"))
    bindings,scenario=_paper_a_qualification_bindings(data,permission["registry_path"],permission["scenarios_path"])
    binding(asset,field)=haskey(bindings,(asset,field)) ? bindings[(asset,field)] : throw(ArgumentError("missing canonical binding $asset/$field"))
    for assumption in scenario["network_assumptions"]
        binding("@scenario",assumption)=="declared_parametric_assumption" || throw(ArgumentError("missing declared network assumption"))
    end
    fraction=PaperARegional.number(data,"investment_period_fraction";positive=true)
    _paper_a_compare(fraction,scenario["investment_period_fraction"],"scenario investment fraction")
    _paper_a_compare(fraction,binding("@scenario","investment_period_fraction"),"registry investment fraction")
    _paper_a_compare(data["baseMVA"],binding("@scenario","baseMVA"),"baseMVA")
    for (t,sn) in data["nw"]
        get(sn["paper_a_extension"],"dataset_kind",nothing)=="parametric_study" || throw(ArgumentError("snapshot scope mismatch"))
        weighted=get(sn,"paper_a_cost_state","raw_hourly")=="weighted"
        weights=_paper_a_temporal(data,parse(Int,t))
        currency=weighted ? sn["paper_a_currency_factor"] : 1.
        if weighted
            sn["paper_a_investment_fraction_applied"]==fraction || throw(ArgumentError("CAPEX fraction changed after scaling"))
        end
        _paper_a_compare(sn["g_min"],binding("@scenario","g_min"),"g_min")
        _paper_a_compare(sn["g_min"],scenario["g_min"],"scenario g_min")
        for table in ("gen","storage","ne_storage"),d in values(get(sn,table,Dict()))
            haskey(d,"source_class") || continue
            asset=String(d["name"])
            fields=["source_class","p_block_max_MW","S_block_MVA","n0","nmax","na0","p_min_pu","a_conn"]
            append!(fields,d["source_class"]=="GFL" ? ["mu_fl"] : ["mu_str","x_src","native_source_MVA","b_block"])
            table=="gen" || append!(fields,["e_block","charge_efficiency","discharge_efficiency"])
            for field in fields
                expected=binding(asset,field)
                field=="e_block" && get(data,"per_unit",false) && (expected/=data["baseMVA"])
                _paper_a_compare(d[field],expected,"$asset/$field")
            end
            profile=JSON.parse(binding(asset,"a_res_profile"))
            _paper_a_compare(d["a_res"],profile[parse(Int,t)],"$asset/a_res")
            expandable=d["nmax"]>d["n0"]
            for field in ("cost_inv_per_mw","marginal_cost","startup_cost_per_mw","shutdown_cost_per_mw")
                factor = !weighted ? 1. : field=="cost_inv_per_mw" ? (expandable ? fraction*currency : 1.) :
                    field=="marginal_cost" ? (table=="gen" ? 1. : weights.dispatch*currency) : weights.event*currency
                _paper_a_compare(d[field],binding(asset,field)*factor,"$asset/$field")
            end
            if table=="gen"
                factor=get(data,"per_unit",false) ? data["baseMVA"] : 1.
                weighted && (factor*=weights.dispatch*currency)
                _paper_a_compare(d["cost"][1],binding(asset,"marginal_cost")*factor,"$asset/dispatch polynomial")
                _paper_a_compare(d["cost"][end],0.,"constant dispatch cost")
            end
        end
        temporal=data["paper_a_temporal"][parse(Int,t)]
        for field in ("delta_t_h","representative_repetitions","scenario_probability","event_repetitions")
            _paper_a_compare(temporal[field],binding("@scenario",field),field)
        end
    end
    net=data["paper_a_network"]
    all(i in ("fixed_shunt_inventory_unverified","baseline_source_accounting_unverified","grounding_reference_unverified") for i in net["passive_domain_issues"]) || throw(ArgumentError("parametric scope cannot waive physical network defects"))
    isempty(net["fixed_sources_in_network"]) && isempty(net["fixed_shunts"]) || throw(ArgumentError("declared no-fixed-source/shunt assumption violated"))
    return true
end

"""Register canonical external files for this data object, without changing any
physical parameter or granting empirical permission. Hashes and values are
rechecked at model construction; no process-wide permission is retained."""
function register_paper_a_parameters!(data::Dict{String,Any},registry_path::AbstractString,scenarios_path::AbstractString)
    data["_paper_a_parameter_registration"]=Dict("registry_path"=>abspath(registry_path),"scenarios_path"=>abspath(scenarios_path))
    try
        _paper_a_validate_registered!(data)
    catch
        delete!(data,"_paper_a_parameter_registration")
        rethrow()
    end
    return data
end
