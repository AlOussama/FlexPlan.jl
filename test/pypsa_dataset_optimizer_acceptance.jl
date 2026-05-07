using Test
import JSON
import Printf: @sprintf
import FlexPlan as _FP
import PowerModels as _PM
import PowerModelsACDC as _PMACDC
import InfrastructureModels as _IM
using JuMP
using Memento
import HiGHS

if !@isdefined(milp_optimizer)
    milp_optimizer = _FP.optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false)
end

const _PYPSA_ACCEPTANCE_DIRECT_RUN = abspath(PROGRAM_FILE) == abspath(@__FILE__)

const _PYPSA_ACCEPTANCE_ROOT = get(
    ENV,
    "PYPSA_FLEXPLAN_BLOCK_GSCR_ROOT",
    raw"D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr",
)

if _PYPSA_ACCEPTANCE_DIRECT_RUN
    @info "Running PyPSA dataset optimizer acceptance directly" root=_PYPSA_ACCEPTANCE_ROOT
end

const _PYPSA_ACCEPTANCE_DATASETS = [
    ("base_s_5_3snap", 3),
    ("base_s_5_6snap", 6),
    ("base_s_5_24snap", 24),
]

const _PYPSA_BLOCK_FIELDS = [
    "carrier",
    "grid_control_mode",
    "n0",
    "nmax",
    "na0",
    "p_block_max",
    "q_block_min",
    "q_block_max",
    "b_block",
    "cost_inv_per_mw",
    "p_min_pu",
    "p_max_pu",
    "startup_cost_per_mw",
    "shutdown_cost_per_mw",
]

const _PYPSA_COST_PROVENANCE_FIELDS = [
    "lifetime",
    "discount_rate",
    "fixed_om_percent",
]

const _PYPSA_ALLOWED_CAPEX_BASES = Set(["overnight_per_mw", "annualized_per_mw_year"])

# PyPSA acceptance consumes schema-v2 converted data directly. These v1 and
# policy fields are rejected; no silent test adapter translates them.
# This test intentionally fails against old schema-v1 external fixtures until
# pypsatomatpowerx regenerates schema-v2 case.json files.
const _PYPSA_REJECTED_BLOCK_FIELDS = [
    "type",
    "cost_inv_block",
    "startup_block_cost",
    "shutdown_block_cost",
    "activation_policy",
    "uc_policy",
    "gscr_exposure_policy",
]

const _PYPSA_ACTIVE_OK_STATUSES = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL"])
const _PYPSA_DOCUMENTED_STATUSES = Set(["OPTIMAL", "LOCALLY_SOLVED", "ALMOST_OPTIMAL", "INFEASIBLE"])

function _pypsa_dataset_path(name::String)
    return normpath(_PYPSA_ACCEPTANCE_ROOT, name, "case.json")
end

function _pypsa_load_case(name::String)
    return JSON.parsefile(_pypsa_dataset_path(name))
end

function _pypsa_status_string(status)
    return string(status)
end

function _pypsa_block_devices(nw::Dict{String,Any})
    devices = Tuple{String,String,Any}[]
    for table in ("gen", "storage", "ne_storage")
        for (id, device) in get(nw, table, Dict{String,Any}())
            if haskey(device, "grid_control_mode")
                push!(devices, (table, id, device))
            end
        end
    end
    return devices
end

function _pypsa_convention_capex_basis(convention)
    if !(convention isa Dict) || !haskey(convention, "capex_basis")
        return nothing
    end
    basis = string(convention["capex_basis"])
    return basis in _PYPSA_ALLOWED_CAPEX_BASES ? basis : "__invalid__:$(basis)"
end

function _pypsa_capex_basis(data::Dict{String,Any}, nw::Dict{String,Any})
    top_basis = _pypsa_convention_capex_basis(get(data, "uc_gscr_block_cost_convention", nothing))
    nw_basis = _pypsa_convention_capex_basis(get(nw, "uc_gscr_block_cost_convention", nothing))
    if !isnothing(top_basis) && !isnothing(nw_basis) && top_basis != nw_basis
        return "__conflict__:top=$(top_basis),nw=$(nw_basis)"
    end
    return isnothing(nw_basis) ? top_basis : nw_basis
end

function _pypsa_assert_cost_convention(data::Dict{String,Any}, dataset_name::String)
    basis_by_nw = Dict{String,String}()
    for (nw_id, nw) in sort(collect(data["nw"]); by=x -> parse(Int, x.first))
        basis = _pypsa_capex_basis(data, nw)
        @test !isnothing(basis)
        @test basis in _PYPSA_ALLOWED_CAPEX_BASES
        basis_by_nw[nw_id] = isnothing(basis) ? "" : basis
    end
    unique_basis = unique(values(basis_by_nw))
    @test length(unique_basis) == 1
    if any(!(basis in _PYPSA_ALLOWED_CAPEX_BASES) for basis in unique_basis) || length(unique_basis) != 1
        error("Invalid UC/gSCR block CAPEX basis in dataset $(dataset_name): $(basis_by_nw)")
    end
    return first(unique_basis)
end

function _pypsa_explicit_assumption(data::Dict{String,Any}, field::String)
    assumptions = get(data, "uc_gscr_block_cost_assumptions", Dict{String,Any}())
    return assumptions isa Dict && haskey(assumptions, field)
end

function _pypsa_is_nonnegative_number(value)
    return value isa Real && isfinite(value) && value >= 0
end

function _pypsa_is_positive_number(value)
    return value isa Real && isfinite(value) && value > 0
end

function _pypsa_assert_block_cost_fields(data::Dict{String,Any}, dataset_name::String, capex_basis::String)
    for (nw_id, nw) in sort(collect(data["nw"]); by=x -> parse(Int, x.first))
        for (table, component_id, device) in _pypsa_block_devices(nw)
            @test _pypsa_is_nonnegative_number(device["cost_inv_per_mw"])
            @test _pypsa_is_nonnegative_number(device["startup_cost_per_mw"])
            @test _pypsa_is_nonnegative_number(device["shutdown_cost_per_mw"])

            if device["nmax"] > device["n0"]
                @test device["p_block_max"] > 0
            end

            for field in _PYPSA_COST_PROVENANCE_FIELDS
                if haskey(device, field)
                    if field == "lifetime"
                        @test _pypsa_is_positive_number(device[field])
                    else
                        @test _pypsa_is_nonnegative_number(device[field])
                    end
                end
            end

            if capex_basis == "overnight_per_mw" && device["nmax"] > device["n0"]
                @test haskey(device, "lifetime")
                @test haskey(device, "discount_rate") || _pypsa_explicit_assumption(data, "discount_rate")
                @test haskey(device, "fixed_om_percent") || _pypsa_explicit_assumption(data, "fixed_om_percent")
            elseif capex_basis == "annualized_per_mw_year"
                # cost_inv_per_mw is interpreted as already annualized PyPSA/PyPSA-Eur capital_cost.
                @test true
            else
                error("Unsupported CAPEX basis $(capex_basis) in dataset $(dataset_name), snapshot $(nw_id), $(table) $(component_id).")
            end
        end
    end
    return nothing
end

function _pypsa_assert_operation_time_fields(data::Dict{String,Any})
    for (_, nw) in sort(collect(data["nw"]); by=x -> parse(Int, x.first))
        @test get(nw, "operation_weight", nothing) == 1.0
        @test haskey(nw, "pypsa_snapshot_weight_objective")
        @test get(nw, "time_elapsed", 0.0) > 0
    end
    return nothing
end

function _pypsa_assert_no_rejected_block_fields(data::Dict{String,Any}, dataset_name::String)
    violations = String[]
    for (nw_id, nw) in sort(collect(data["nw"]); by=x -> parse(Int, x.first))
        for table in ("gen", "storage", "ne_storage")
            for (component_id, component) in get(nw, table, Dict{String,Any}())
                rejected = String[field for field in _PYPSA_REJECTED_BLOCK_FIELDS if haskey(component, field)]
                if !isempty(rejected)
                    push!(
                        violations,
                        "dataset=$(dataset_name) snapshot=$(nw_id) component_type=$(table) component_id=$(component_id) rejected_fields=$(join(rejected, ","))",
                    )
                end
            end
        end
    end
    if !isempty(violations)
        shown = first(violations, min(length(violations), 20))
        omitted = length(violations) - length(shown)
        details = join(shown, "\n")
        if omitted > 0
            details *= "\n... $(omitted) additional rejected-field rows omitted"
        end
        error(
            "UC/gSCR block schema v2 validation failed: PyPSA acceptance data contains rejected v1/policy fields. " *
            "Use grid_control_mode, cost_inv_per_mw, startup_cost_per_mw, and shutdown_cost_per_mw. " *
            "No v1 acceptance adapter is applied.\n" * details,
        )
    end
    return nothing
end

function _pypsa_check_na0_invariants(data::Dict{String,Any}, dataset_name::String)
    violations = Dict{String,Any}[]
    for (nw_id, nw) in sort(collect(data["nw"]); by=x -> parse(Int, x.first))
        for table in ("gen", "storage", "ne_storage")
            for (component_id, component) in get(nw, table, Dict{String,Any}())
                if !haskey(component, "grid_control_mode")
                    continue
                end
                na0 = component["na0"]
                n0 = component["n0"]
                nmax = component["nmax"]
                valid = 0.0 <= na0 <= n0 <= nmax
                if !valid
                    push!(
                        violations,
                        Dict{String,Any}(
                            "dataset" => dataset_name,
                            "snapshot" => nw_id,
                            "component_type" => table,
                            "component_id" => component_id,
                            "carrier" => get(component, "carrier", ""),
                            "na0" => na0,
                            "n0" => n0,
                            "nmax" => nmax,
                        ),
                    )
                end
            end
        end
    end
    return violations
end

function _pypsa_assert_no_na0_invariant_violations(data::Dict{String,Any}, dataset_name::String)
    violations = _pypsa_check_na0_invariants(data, dataset_name)
    if !isempty(violations)
        lines = String[]
        for v in violations
            push!(
                lines,
                "dataset=$(v["dataset"]) snapshot=$(v["snapshot"]) component_type=$(v["component_type"]) component_id=$(v["component_id"]) carrier=$(v["carrier"]) na0=$(v["na0"]) n0=$(v["n0"]) nmax=$(v["nmax"])",
            )
        end
        error(
            "na0 invariant violations found (require 0 <= na0 <= n0 <= nmax):\n" * join(lines, "\n")
        )
    end
    return nothing
end

function _pypsa_has_schema_v2(data::Dict{String,Any})
    expected = Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
    if get(data, "block_model_schema", nothing) == expected
        return true
    end
    return all(get(nw, "block_model_schema", nothing) == expected for nw in values(data["nw"]))
end

function _pypsa_schema_summary(data::Dict{String,Any}, expected_snapshots::Int)
    nw1 = data["nw"]["1"]
    devices = _pypsa_block_devices(nw1)
    gfl_count = count(device -> device[3]["grid_control_mode"] == "gfl", devices)
    gfm_count = count(device -> device[3]["grid_control_mode"] == "gfm", devices)
    return Dict{String,Any}(
        "multinetwork" => data["multinetwork"],
        "snapshots" => length(data["nw"]),
        "expected_snapshots" => expected_snapshots,
        "bus_count" => length(nw1["bus"]),
        "branch_count" => length(nw1["branch"]),
        "gen_count" => length(nw1["gen"]),
        "storage_count" => length(nw1["storage"]),
        "gfl_count" => gfl_count,
        "gfm_count" => gfm_count,
    )
end

function _pypsa_assert_schema(data::Dict{String,Any}, expected_snapshots::Int)
    @test data["multinetwork"] == true
    @test length(data["nw"]) == expected_snapshots
    @test _pypsa_has_schema_v2(data)
    _pypsa_assert_operation_time_fields(data)
    capex_basis = _pypsa_assert_cost_convention(data, get(data, "name", "pypsa-flexplan-block-gscr"))

    nw1 = data["nw"]["1"]
    @test length(nw1["bus"]) == 5
    @test length(nw1["branch"]) == 6
    @test length(nw1["gen"]) == 23
    @test length(nw1["storage"]) == 5

    devices = _pypsa_block_devices(nw1)
    @test count(device -> device[3]["grid_control_mode"] == "gfl", devices) == 17
    @test count(device -> device[3]["grid_control_mode"] == "gfm", devices) == 11
    @test all(haskey(bus, "g_min") for bus in values(nw1["bus"]))
    @test all(all(haskey(device, field) for field in _PYPSA_BLOCK_FIELDS) for (_, _, device) in devices)
    @test all(all(!haskey(device, field) for field in _PYPSA_REJECTED_BLOCK_FIELDS) for (_, _, device) in devices)
    @test all(haskey(device, "e_block") for (table, _, device) in devices if table in ("storage", "ne_storage"))
    _pypsa_assert_block_cost_fields(data, get(data, "name", "pypsa-flexplan-block-gscr"), capex_basis)
end

function _pypsa_strip_block_fields!(data::Dict{String,Any})
    fields = Set([_PYPSA_BLOCK_FIELDS; _PYPSA_COST_PROVENANCE_FIELDS; _PYPSA_REJECTED_BLOCK_FIELDS; ["p_block_min", "H", "s_block", "gscr_rhs_uses_nameplate", "e_block"]])
    for nw in values(data["nw"])
        for table in ("gen", "storage", "ne_storage")
            for device in values(get(nw, table, Dict{String,Any}()))
                for field in fields
                    delete!(device, field)
                end
            end
        end
        for bus in values(nw["bus"])
            delete!(bus, "g_min")
        end
        delete!(nw, "operation_weight")
        delete!(nw, "block_model_schema")
    end
    delete!(data, "block_model_schema")
    return data
end

function _pypsa_link_dcline_conversion(nw::Dict{String,Any})
    bus_name_to_id = Dict(bus["name"] => parse(Int, id) for (id, bus) in nw["bus"])
    dcline = Dict{String,Any}()
    skipped = 0
    ignored = 0

    for (idx, (link_id, link)) in enumerate(sort(collect(get(nw, "link", Dict{String,Any}())); by=first))
        if get(link, "carrier", "") != "DC"
            ignored += 1
            continue
        end

        f_bus = get(bus_name_to_id, link["bus0"], nothing)
        t_bus = get(bus_name_to_id, link["bus1"], nothing)
        if isnothing(f_bus) || isnothing(t_bus)
            skipped += 1
            continue
        end

        rate = get(link, "p_nom", get(link, "rate_a", 0.0))
        dcline[string(idx)] = Dict{String,Any}(
            "index" => idx,
            "source_id" => ["pypsa_link", link_id],
            "name" => get(link, "name", link_id),
            "carrier" => get(link, "carrier", "dc"),
            "f_bus" => f_bus,
            "t_bus" => t_bus,
            "br_status" => get(link, "status", 1),
            "pf" => get(link, "pf", 0.0),
            "pt" => get(link, "pt", 0.0),
            "qf" => get(link, "qf", 0.0),
            "qt" => get(link, "qt", 0.0),
            "pminf" => get(link, "pminf", -rate),
            "pmaxf" => get(link, "pmaxf", rate),
            "pmint" => get(link, "pmint", -rate),
            "pmaxt" => get(link, "pmaxt", rate),
            "qminf" => get(link, "qminf", 0.0),
            "qmaxf" => get(link, "qmaxf", 0.0),
            "qmint" => get(link, "qmint", 0.0),
            "qmaxt" => get(link, "qmaxt", 0.0),
            "loss0" => get(link, "loss0", 0.0),
            "loss1" => get(link, "loss1", 0.0),
            "vf" => get(link, "vf", 1.0),
            "vt" => get(link, "vt", 1.0),
            "model" => get(link, "model", 2),
            "cost" => get(link, "cost", [0.0, 0.0]),
        )
    end

    return dcline, skipped, ignored
end

function _pypsa_add_dimensions!(data::Dict{String,Any})
    snapshots = length(data["nw"])
    if !haskey(data, "dim")
        _FP.add_dimension!(data, :hour, snapshots)
        _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
        _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    end
    return data
end

function _pypsa_prepare_solver_data(raw_data::Dict{String,Any}; mode::Symbol=:opf, strip_blocks::Bool=false, g_min_override=nothing)
    data = deepcopy(raw_data)
    _pypsa_assert_no_rejected_block_fields(data, get(data, "name", "pypsa-flexplan-block-gscr"))
    data["per_unit"] = get(data, "per_unit", false)
    data["source_type"] = get(data, "source_type", "pypsa-flexplan-json")
    data["name"] = get(data, "name", "pypsa-flexplan-block-gscr")
    _pypsa_add_dimensions!(data)

    if strip_blocks
        _pypsa_strip_block_fields!(data)
    end

    total_links = sum(length(get(nw, "link", Dict{String,Any}())) for nw in values(data["nw"]))
    total_converted_links = 0
    total_skipped_links = 0
    total_ignored_links = 0

    for nw in values(data["nw"])
        dcline, skipped_links, ignored_links = _pypsa_link_dcline_conversion(nw)
        total_converted_links += length(dcline)
        total_skipped_links += skipped_links
        total_ignored_links += ignored_links
        delete!(nw, "link")
        nw["per_unit"] = get(nw, "per_unit", data["per_unit"])
        nw["source_type"] = get(nw, "source_type", data["source_type"])
        nw["time_elapsed"] = get(nw, "time_elapsed", 1.0)
        nw["ne_storage"] = get(nw, "ne_storage", Dict{String,Any}())
        nw["dcline"] = dcline
        for table in ("shunt", "switch")
            nw[table] = get(nw, table, Dict{String,Any}())
        end

        for table in ("bus", "branch", "gen", "storage", "ne_storage", "load")
            for (id, component) in get(nw, table, Dict{String,Any}())
                component["index"] = get(component, "index", parse(Int, id))
            end
        end

        g_min = isnothing(g_min_override) ? maximum([get(bus, "g_min", 0.0) for bus in values(nw["bus"])]) : g_min_override
        nw["g_min"] = g_min

        for bus in values(nw["bus"])
            bus["zone"] = get(bus, "zone", 1)
        end

        for branch in values(nw["branch"])
            branch["tap"] = get(branch, "tap", 1.0)
            branch["shift"] = get(branch, "shift", 0.0)
            branch["transformer"] = get(branch, "transformer", false)
            branch["g_fr"] = get(branch, "g_fr", 0.0)
            branch["g_to"] = get(branch, "g_to", 0.0)
        end

        for load in values(nw["load"])
            load["status"] = get(load, "status", 1)
        end

        for gen in values(nw["gen"])
            gen["status"] = get(gen, "status", get(gen, "gen_status", 1))
            gen["dispatchable"] = get(gen, "dispatchable", true)
            gen["model"] = get(gen, "model", 2)
            gen["cost"] = get(gen, "cost", [0.0, 0.0])
            if haskey(gen, "grid_control_mode")
                if !(0.0 <= gen["na0"] <= gen["n0"] <= gen["nmax"])
                    error("Invariant violation in PyPSA schema-v2 data for gen $(gen["index"]): require 0 <= na0 <= n0 <= nmax.")
                end
                if mode == :uc
                    gen["nmax"] = gen["n0"]
                end
            end
        end

        for storage in values(nw["storage"])
            if haskey(storage, "grid_control_mode")
                if !(0.0 <= storage["na0"] <= storage["n0"] <= storage["nmax"])
                    error("Invariant violation in PyPSA schema-v2 data for storage $(storage["index"]): require 0 <= na0 <= n0 <= nmax.")
                end
                if mode == :uc
                    storage["nmax"] = storage["n0"]
                end
            end
            storage["r"] = get(storage, "r", 0.0)
            storage["x"] = get(storage, "x", 0.0)
            storage["p_loss"] = get(storage, "p_loss", 0.0)
            storage["q_loss"] = get(storage, "q_loss", 0.0)
            storage["stationary_energy_inflow"] = get(storage, "stationary_energy_inflow", 0.0)
            storage["stationary_energy_outflow"] = get(storage, "stationary_energy_outflow", 0.0)
            storage["thermal_rating"] = get(storage, "thermal_rating", max(get(storage, "charge_rating", 0.0), get(storage, "discharge_rating", 0.0), 1.0))
            storage["qmin"] = get(storage, "qmin", get(storage, "q_block_min", -1.0))
            storage["qmax"] = get(storage, "qmax", get(storage, "q_block_max", 1.0))
            storage["energy_rating"] = get(storage, "energy_rating", get(storage, "energy", 1.0))
            storage["max_energy_absorption"] = get(storage, "max_energy_absorption", Inf)
            storage["self_discharge_rate"] = get(storage, "self_discharge_rate", 0.0)
        end

        for storage in values(nw["ne_storage"])
            if haskey(storage, "grid_control_mode")
                if !(0.0 <= storage["na0"] <= storage["n0"] <= storage["nmax"])
                    error("Invariant violation in PyPSA schema-v2 data for ne_storage $(storage["index"]): require 0 <= na0 <= n0 <= nmax.")
                end
                if mode == :uc
                    storage["nmax"] = storage["n0"]
                end
            end
        end
    end

    data["_pypsa_link_count"] = total_links
    data["_pypsa_dcline_count"] = total_converted_links
    data["_pypsa_skipped_link_count"] = total_skipped_links
    data["_pypsa_ignored_link_count"] = total_ignored_links
    return data
end

function _pypsa_instantiate_standard_opf(data::Dict{String,Any})
    return _PM.instantiate_model(data, _PM.DCPPowerModel, _PM.build_mn_opf_strg)
end

function _pypsa_solve_standard_opf(data::Dict{String,Any})
    return _PM.solve_mn_opf_strg(data, _PM.DCPPowerModel, milp_optimizer)
end

function _pypsa_uc_gscr_template()
    return _FP.UCGSCRBlockTemplate(
        Dict(
            (:gen, "CCGT") => _FP.BlockThermalCommitment(),
            (:gen, "biomass") => _FP.BlockThermalCommitment(),
            (:gen, "nuclear") => _FP.BlockThermalCommitment(),
            (:gen, "oil") => _FP.BlockThermalCommitment(),
            (:gen, "onwind") => _FP.BlockRenewableParticipation(),
            (:gen, "offwind-ac") => _FP.BlockRenewableParticipation(),
            (:gen, "offwind-dc") => _FP.BlockRenewableParticipation(),
            (:gen, "solar") => _FP.BlockRenewableParticipation(),
            (:storage, "battery") => _FP.BlockFixedInstalled(),
        ),
        _FP.GershgorinGSCR(_FP.OnlineNameplateExposure()),
    )
end

function _pypsa_build_active_pm(data::Dict{String,Any})
    return _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        pm -> _FP.build_uc_gscr_block_integration(pm; template=_pypsa_uc_gscr_template());
        ref_extensions=[_FP.ref_add_gen!, _FP.ref_add_storage!, _FP.ref_add_ne_storage!, _FP.ref_add_uc_gscr_block!],
    )
end

function _pypsa_solve_active_pm(data::Dict{String,Any})
    pm = _pypsa_build_active_pm(data)
    JuMP.set_optimizer(pm.model, HiGHS.Optimizer)
    JuMP.set_silent(pm.model)
    JuMP.optimize!(pm.model)
    return pm
end

function _pypsa_active_metrics(pm)
    status = JuMP.termination_status(pm.model)
    metrics = Dict{String,Any}(
        "status" => _pypsa_status_string(status),
        "objective" => status == JuMP.MOI.OPTIMAL ? JuMP.objective_value(pm.model) : nothing,
        "min_gscr_margin" => Inf,
        "near_binding_count" => 0,
        "startup_shutdown_cost" => nothing,
        "investment_cost" => nothing,
        "max_transition_residual" => nothing,
        "max_active_bound_violation" => nothing,
        "gfm_installed" => nothing,
        "gfm_online" => nothing,
    )

    if !(metrics["status"] in _PYPSA_ACTIVE_OK_STATUSES)
        return metrics
    end

    tol = 1e-6
    nws = sort(collect(_FP.nw_ids(pm)))
    first_nw = first(nws)
    keys = _FP._uc_gscr_block_device_keys(pm, first_nw)
    metrics["startup_shutdown_cost"] = 0.0
    metrics["investment_cost"] = 0.0
    metrics["max_transition_residual"] = 0.0
    metrics["max_active_bound_violation"] = 0.0
    metrics["gfm_installed"] = 0.0
    metrics["gfm_online"] = 0.0

    for key in keys
        device = _PM.ref(pm, first_nw, key[1], key[2])
        n_val = JuMP.value(_PM.var(pm, first_nw, :n_block, key))
        metrics["investment_cost"] += device["cost_inv_per_mw"] * device["p_block_max"] * (n_val - device["n0"])
        if device["grid_control_mode"] == "gfm"
            metrics["gfm_installed"] += n_val
        end
    end

    for nw in nws
        startup_shutdown_keys = Set(_FP._uc_gscr_block_startup_shutdown_device_keys(pm, nw))
        for key in keys
            device = _PM.ref(pm, nw, key[1], key[2])
            n_val = JuMP.value(_PM.var(pm, nw, :n_block, key))
            na_val = JuMP.value(_PM.var(pm, nw, :na_block, key))
            prev_na = _FP.is_first_id(pm, nw, :hour) ? device["na0"] : JuMP.value(_PM.var(pm, _FP.prev_id(pm, nw, :hour), :na_block, key))

            if key in startup_shutdown_keys
                su_val = JuMP.value(_PM.var(pm, nw, :su_block, key))
                sd_val = JuMP.value(_PM.var(pm, nw, :sd_block, key))
                metrics["startup_shutdown_cost"] += device["p_block_max"] * (device["startup_cost_per_mw"] * su_val + device["shutdown_cost_per_mw"] * sd_val)
                metrics["max_transition_residual"] = max(metrics["max_transition_residual"], abs((na_val - prev_na) - (su_val - sd_val)))
            end
            metrics["max_active_bound_violation"] = max(metrics["max_active_bound_violation"], max(0.0, -na_val, na_val - n_val))
            if device["grid_control_mode"] == "gfm"
                metrics["gfm_online"] += na_val
            end
        end

        for bus_id in sort(collect(_PM.ids(pm, nw, :bus)))
            sigma0 = _PM.ref(pm, nw, :gscr_sigma0_gershgorin_margin, bus_id)
            g_min = _PM.ref(pm, nw, :g_min)
            lhs = sigma0 + sum(
                _PM.ref(pm, nw, key[1], key[2], "b_block") * JuMP.value(_PM.var(pm, nw, :na_block, key))
                for key in _PM.ref(pm, nw, :bus_gfm_devices, bus_id);
                init=0.0,
            )
            rhs = g_min * sum(
                _PM.ref(pm, nw, key[1], key[2], "p_block_max") * JuMP.value(_PM.var(pm, nw, :na_block, key))
                for key in _PM.ref(pm, nw, :bus_gfl_devices, bus_id);
                init=0.0,
            )
            margin = lhs - rhs
            metrics["min_gscr_margin"] = min(metrics["min_gscr_margin"], margin)
            if margin <= tol
                metrics["near_binding_count"] += 1
            end
        end
    end

    return metrics
end

function _pypsa_write_report(records::Vector{Dict{String,Any}}, context::Vector{String})
    report_dir = normpath(@__DIR__, "..", "reports")
    mkpath(report_dir)
    report_path = normpath(report_dir, "pypsa_dataset_optimizer_acceptance.md")

    open(report_path, "w") do io
        println(io, "# PyPSA Dataset Optimizer Acceptance")
        println(io)
        println(io, "Generated by `test/pypsa_dataset_optimizer_acceptance.jl`.")
        println(io)
        println(io, "## Implementation Context")
        for item in context
            println(io, "- ", item)
        end
        println(io)
        println(io, "## Results")
        println(io)
        println(io, "| dataset | test | snapshots | capex_basis | status | objective | min gSCR margin | near-binding | startup/shutdown | investment | warnings |")
        println(io, "|---|---|---:|---|---|---:|---:|---:|---:|---:|---|")
        for rec in records
            objective = isnothing(rec["objective"]) ? "NaN" : @sprintf("%.6f", rec["objective"])
            margin = !haskey(rec, "min_gscr_margin") || !isfinite(rec["min_gscr_margin"]) ? "NaN" : @sprintf("%.6f", rec["min_gscr_margin"])
            near = string(get(rec, "near_binding_count", 0))
            su_sd = isnothing(get(rec, "startup_shutdown_cost", nothing)) ? "NaN" : @sprintf("%.6f", rec["startup_shutdown_cost"])
            inv = isnothing(get(rec, "investment_cost", nothing)) ? "NaN" : @sprintf("%.6f", rec["investment_cost"])
            println(io, "| ", rec["dataset"], " | ", rec["test"], " | ", rec["snapshots"], " | ", get(rec, "capex_basis", ""), " | ", rec["status"], " | ", objective, " | ", margin, " | ", near, " | ", su_sd, " | ", inv, " | ", get(rec, "warnings", ""), " |")
        end
        println(io)
        println(io, "## Warnings and Unresolved Issues")
        println(io)
        println(io, "- PyPSA JSON is required to be UC/gSCR block schema v2; v1 block fields are rejected and no v1 solver-copy adapter is applied.")
        println(io, "- `uc_gscr_block_cost_convention.capex_basis` is required and must be either `annualized_per_mw_year` or `overnight_per_mw`; regenerated PyPSA-Eur `capital_cost` datasets use `annualized_per_mw_year`.")
        println(io, "- `operation_weight` is compatibility/diagnostic only and is required to be `1.0`; PyPSA objective snapshot weights are kept in `pypsa_snapshot_weight_objective` for diagnostics.")
        println(io, "- `time_elapsed` must be positive and may reflect multi-hour snapshot spacing, for example 3-hour `base_s_5` fixtures.")
        println(io, "- `na0` invariants are validated on raw data for every block-enabled component and snapshot: `0 <= na0 <= n0 <= nmax`.")
        println(io, "- PyPSA `link` entries with `carrier == \"DC\"` are mapped to PowerModels `dcline`; all other link carriers are ignored in solver copies.")
        println(io, "- Standard OPF is run through `solve_mn_opf_strg` because the datasets include storage.")
        println(io, "- Min-up/min-down, ramping, no-load costs, binary UC commitment variables, SDP/LMI constraints, and new gSCR formulations are not activated.")
    end
    return report_path
end

@testset "PyPSA-derived FlexPlan dataset optimizer acceptance" begin
    if !all(isfile(_pypsa_dataset_path(name)) for (name, _) in _PYPSA_ACCEPTANCE_DATASETS)
        @info "Skipping PyPSA dataset optimizer acceptance tests because dataset files are not available" root=_PYPSA_ACCEPTANCE_ROOT
    else
        records = Dict{String,Any}[]
        context = [
            "JSON datasets are loaded with JSON.parsefile as PowerModels-style dictionaries.",
            "Dataset root: `$(_PYPSA_ACCEPTANCE_ROOT)`.",
            "Multinetwork cases are identified by `multinetwork=true` and processed through `data[\"nw\"]`; the active path receives explicit `:hour`, `:scenario`, and `:year` dimensions.",
            "Raw block fields are schema-checked with v2 names (`grid_control_mode`, `n0`, `nmax`, `cost_inv_per_mw`, `startup_cost_per_mw`, `shutdown_cost_per_mw`); v1 converted data is no longer accepted.",
            "`uc_gscr_block_cost_convention.capex_basis` is hard-validated. `annualized_per_mw_year` interprets `cost_inv_per_mw` as annualized PyPSA/PyPSA-Eur `capital_cost`; `overnight_per_mw` interprets it as raw overnight CAPEX.",
            "`operation_weight` must be `1.0`; `pypsa_snapshot_weight_objective` is required as a diagnostic field; `time_elapsed` must be positive and is not assumed to be `1.0`.",
            "Raw block-count invariants are hard-validated before solver execution: `0 <= na0 <= n0 <= nmax`.",
            "PyPSA `link` records are mapped to PowerModels `dcline` only when `carrier == \"DC\"`; non-DC link carriers are ignored.",
            "gSCR constraints are activated only through `ref_add_uc_gscr_block!` and `constraint_gscr_gershgorin_sufficient` in `build_uc_gscr_block_integration`.",
            "UC/scheduling mode is selected in the test adapter by fixing `nmax=n0`; CAPEXP mode allows `nmax>n0` where available.",
            "Results expose `n_block`, `na_block`, `su_block`, and `sd_block` through the active model variables and solution reporting hooks.",
        ]

        @testset "Load-only schema" begin
            for (name, snapshots) in _PYPSA_ACCEPTANCE_DATASETS
                data = _pypsa_load_case(name)
                _pypsa_assert_no_rejected_block_fields(data, name)
                capex_basis = _pypsa_assert_cost_convention(data, name)
                _pypsa_assert_schema(data, snapshots)
                _pypsa_assert_no_na0_invariant_violations(data, name)
                summary = _pypsa_schema_summary(data, snapshots)
                push!(records, Dict{String,Any}(
                    "dataset" => name,
                    "test" => "load/schema",
                    "snapshots" => summary["snapshots"],
                    "capex_basis" => capex_basis,
                    "status" => "PASS",
                    "objective" => nothing,
                    "warnings" => "",
                ))
            end
        end

        raw_3 = _pypsa_load_case("base_s_5_3snap")
        raw_3_capex_basis = _pypsa_assert_cost_convention(raw_3, "base_s_5_3snap")

        @testset "3-snapshot standard OPF and passive metadata" begin
            opf_data = _pypsa_prepare_solver_data(raw_3; mode=:opf)
            opf_pm = _pypsa_instantiate_standard_opf(opf_data)
            @test all(!haskey(_PM.var(opf_pm, nw), :n_block) for nw in _FP.nw_ids(opf_data))
            @test all(!haskey(_PM.con(opf_pm, nw), :gscr_gershgorin_sufficient) for nw in _FP.nw_ids(opf_data))

            opf_result = _pypsa_solve_standard_opf(opf_data)
            opf_status = _pypsa_status_string(opf_result["termination_status"])
            @test opf_status in _PYPSA_DOCUMENTED_STATUSES
            push!(records, Dict{String,Any}(
                "dataset" => "base_s_5_3snap",
                "test" => "standard OPF",
                "snapshots" => 3,
                "capex_basis" => raw_3_capex_basis,
                "status" => opf_status,
                "objective" => get(opf_result, "objective", nothing),
                "warnings" => opf_status == "INFEASIBLE" ? "documented infeasible standard OPF status" : "",
            ))

            stripped_result = _pypsa_solve_standard_opf(_pypsa_prepare_solver_data(raw_3; mode=:opf, strip_blocks=true))
            stripped_status = _pypsa_status_string(stripped_result["termination_status"])
            @test stripped_status == opf_status
            @test get(stripped_result, "objective", 0.0) ≈ get(opf_result, "objective", 0.0) atol=1e-6
            push!(records, Dict{String,Any}(
                "dataset" => "base_s_5_3snap",
                "test" => "passive metadata",
                "snapshots" => 3,
                "capex_basis" => raw_3_capex_basis,
                "status" => stripped_status,
                "objective" => get(stripped_result, "objective", nothing),
                "warnings" => "block metadata ignored by standard OPF",
            ))
        end

        for (name, snapshots) in _PYPSA_ACCEPTANCE_DATASETS[1:2]
            raw = _pypsa_load_case(name)
            capex_basis = _pypsa_assert_cost_convention(raw, name)
            @testset "$(snapshots)-snapshot active UC/CAPEXP" begin
                uc_pm = _pypsa_solve_active_pm(_pypsa_prepare_solver_data(raw; mode=:uc))
                uc_metrics = _pypsa_active_metrics(uc_pm)
                @test uc_metrics["status"] in _PYPSA_DOCUMENTED_STATUSES
                if uc_metrics["status"] in _PYPSA_ACTIVE_OK_STATUSES
                    @test uc_metrics["max_transition_residual"] <= 1e-6
                    @test uc_metrics["min_gscr_margin"] >= -1e-6
                end
                push!(records, merge(uc_metrics, Dict{String,Any}(
                    "dataset" => name,
                    "test" => "active UC/gSCR",
                    "snapshots" => snapshots,
                    "capex_basis" => capex_basis,
                    "warnings" => uc_metrics["status"] == "INFEASIBLE" ? "active UC/gSCR infeasible; reconstruction unavailable" : "",
                )))

                cap_pm = _pypsa_solve_active_pm(_pypsa_prepare_solver_data(raw; mode=:capexp))
                cap_metrics = _pypsa_active_metrics(cap_pm)
                @test cap_metrics["status"] in _PYPSA_DOCUMENTED_STATUSES
                if cap_metrics["status"] in _PYPSA_ACTIVE_OK_STATUSES
                    @test cap_metrics["max_active_bound_violation"] <= 1e-6
                    @test cap_metrics["min_gscr_margin"] >= -1e-6
                end
                push!(records, merge(cap_metrics, Dict{String,Any}(
                    "dataset" => name,
                    "test" => "active CAPEXP/gSCR",
                    "snapshots" => snapshots,
                    "capex_basis" => capex_basis,
                    "warnings" => cap_metrics["status"] == "INFEASIBLE" ? "active CAPEXP/gSCR infeasible; reconstruction unavailable" : "",
                )))

                sweep = Dict{String,Any}[]
                for (label, g_min) in [("low", 0.0), ("medium", 0.5), ("high", 1.0)]
                    sweep_pm = _pypsa_solve_active_pm(_pypsa_prepare_solver_data(raw; mode=:capexp, g_min_override=g_min))
                    sweep_metrics = _pypsa_active_metrics(sweep_pm)
                    sweep_metrics["label"] = label
                    sweep_metrics["g_min"] = g_min
                    push!(sweep, sweep_metrics)
                end
                feasible_flags = [item["status"] in _PYPSA_ACTIVE_OK_STATUSES for item in sweep]
                @test !any(feasible_flags[i] && !feasible_flags[i - 1] for i in 2:length(feasible_flags))
                push!(records, Dict{String,Any}(
                    "dataset" => name,
                    "test" => "CAPEXP g_min sweep",
                    "snapshots" => snapshots,
                    "capex_basis" => capex_basis,
                    "status" => join([item["label"] * "=" * item["status"] for item in sweep], ", "),
                    "objective" => nothing,
                    "warnings" => "monotone feasibility checked over low/medium/high g_min",
                ))
            end
        end

        report_path = _pypsa_write_report(records, context)
        @test isfile(report_path)
    end
end
