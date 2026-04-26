import JSON
import Printf: @sprintf

const _PYPSA_ACCEPTANCE_ROOT = get(
    ENV,
    "PYPSA_FLEXPLAN_BLOCK_GSCR_ROOT",
    raw"D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr",
)

const _PYPSA_ACCEPTANCE_DATASETS = [
    ("base_s_5_3snap", 3),
    ("base_s_5_6snap", 6),
    ("base_s_5_24snap", 24),
]

const _PYPSA_BLOCK_FIELDS = [
    "type",
    "n_block0",
    "n_block_max",
    "na0",
    "p_block_min",
    "p_block_max",
    "q_block_min",
    "q_block_max",
    "H",
    "b_block",
    "cost_inv_block",
    "startup_block_cost",
    "shutdown_block_cost",
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
    for table in ("gen", "storage")
        for (id, device) in get(nw, table, Dict{String,Any}())
            if haskey(device, "type")
                push!(devices, (table, id, device))
            end
        end
    end
    return devices
end

function _pypsa_check_na0_invariants(data::Dict{String,Any}, dataset_name::String)
    violations = Dict{String,Any}[]
    for (nw_id, nw) in sort(collect(data["nw"]); by=x -> parse(Int, x.first))
        for table in ("gen", "storage", "ne_storage")
            for (component_id, component) in get(nw, table, Dict{String,Any}())
                if !haskey(component, "type")
                    continue
                end
                na0 = component["na0"]
                n_block0 = component["n_block0"]
                n_block_max = component["n_block_max"]
                valid = 0.0 <= na0 <= n_block0 <= n_block_max
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
                            "n_block0" => n_block0,
                            "n_block_max" => n_block_max,
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
                "dataset=$(v["dataset"]) snapshot=$(v["snapshot"]) component_type=$(v["component_type"]) component_id=$(v["component_id"]) carrier=$(v["carrier"]) na0=$(v["na0"]) n_block0=$(v["n_block0"]) n_block_max=$(v["n_block_max"])",
            )
        end
        error(
            "na0 invariant violations found (require 0 <= na0 <= n_block0 <= n_block_max):\n" * join(lines, "\n")
        )
    end
    return nothing
end

function _pypsa_schema_summary(data::Dict{String,Any}, expected_snapshots::Int)
    nw1 = data["nw"]["1"]
    devices = _pypsa_block_devices(nw1)
    gfl_count = count(device -> device[3]["type"] == "gfl", devices)
    gfm_count = count(device -> device[3]["type"] == "gfm", devices)
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

    nw1 = data["nw"]["1"]
    @test length(nw1["bus"]) == 5
    @test length(nw1["branch"]) == 6
    @test length(nw1["gen"]) == 23
    @test length(nw1["storage"]) == 5

    devices = _pypsa_block_devices(nw1)
    @test count(device -> device[3]["type"] == "gfl", devices) == 17
    @test count(device -> device[3]["type"] == "gfm", devices) == 11
    @test all(haskey(bus, "g_min") for bus in values(nw1["bus"]))
    @test all(all(haskey(device, field) for field in _PYPSA_BLOCK_FIELDS) for (_, _, device) in devices)
    @test all(haskey(storage, "e_block") for storage in values(nw1["storage"]))
end

function _pypsa_strip_block_fields!(data::Dict{String,Any})
    fields = Set([_PYPSA_BLOCK_FIELDS; ["p_block_min_pu", "p_block_max_pu", "gscr_rhs_uses_nameplate", "e_block"]])
    for nw in values(data["nw"])
        for table in ("gen", "storage")
            for device in values(get(nw, table, Dict{String,Any}()))
                for field in fields
                    delete!(device, field)
                end
            end
        end
        for bus in values(nw["bus"])
            delete!(bus, "g_min")
        end
    end
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

        for table in ("bus", "branch", "gen", "storage", "load")
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
            if haskey(gen, "n_block0")
                if !(0.0 <= gen["na0"] <= gen["n_block0"] <= gen["n_block_max"])
                    error("Invariant violation in solver adapter for gen $(gen["index"]): require 0 <= na0 <= n_block0 <= n_block_max.")
                end
                # Value-preserving field mapping (except explicit UC-mode nmax override).
                gen["n0"] = gen["n_block0"]
                gen["nmax"] = mode == :uc ? gen["n0"] : gen["n_block_max"]
            end
        end

        for storage in values(nw["storage"])
            if haskey(storage, "n_block0")
                if !(0.0 <= storage["na0"] <= storage["n_block0"] <= storage["n_block_max"])
                    error("Invariant violation in solver adapter for storage $(storage["index"]): require 0 <= na0 <= n_block0 <= n_block_max.")
                end
                # Value-preserving field mapping (except explicit UC-mode nmax override).
                storage["n0"] = storage["n_block0"]
                storage["nmax"] = mode == :uc ? storage["n0"] : storage["n_block_max"]
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

function _pypsa_build_active_pm(data::Dict{String,Any})
    return _PM.instantiate_model(
        data,
        _PM.DCPPowerModel,
        _FP.build_uc_gscr_block_integration;
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
        metrics["investment_cost"] += device["cost_inv_block"] * device["p_block_max"] * (n_val - device["n0"])
        if device["type"] == "gfm"
            metrics["gfm_installed"] += n_val
        end
    end

    for nw in nws
        for key in keys
            device = _PM.ref(pm, nw, key[1], key[2])
            n_val = JuMP.value(_PM.var(pm, nw, :n_block, key))
            na_val = JuMP.value(_PM.var(pm, nw, :na_block, key))
            su_val = JuMP.value(_PM.var(pm, nw, :su_block, key))
            sd_val = JuMP.value(_PM.var(pm, nw, :sd_block, key))
            prev_na = _FP.is_first_id(pm, nw, :hour) ? device["na0"] : JuMP.value(_PM.var(pm, _FP.prev_id(pm, nw, :hour), :na_block, key))

            metrics["startup_shutdown_cost"] += device["startup_block_cost"] * su_val + device["shutdown_block_cost"] * sd_val
            metrics["max_transition_residual"] = max(metrics["max_transition_residual"], abs((na_val - prev_na) - (su_val - sd_val)))
            metrics["max_active_bound_violation"] = max(metrics["max_active_bound_violation"], max(0.0, -na_val, na_val - n_val))
            if device["type"] == "gfm"
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
        println(io, "| dataset | test | snapshots | status | objective | min gSCR margin | near-binding | startup/shutdown | investment | warnings |")
        println(io, "|---|---|---:|---|---:|---:|---:|---:|---:|---|")
        for rec in records
            objective = isnothing(rec["objective"]) ? "NaN" : @sprintf("%.6f", rec["objective"])
            margin = !haskey(rec, "min_gscr_margin") || !isfinite(rec["min_gscr_margin"]) ? "NaN" : @sprintf("%.6f", rec["min_gscr_margin"])
            near = string(get(rec, "near_binding_count", 0))
            su_sd = isnothing(get(rec, "startup_shutdown_cost", nothing)) ? "NaN" : @sprintf("%.6f", rec["startup_shutdown_cost"])
            inv = isnothing(get(rec, "investment_cost", nothing)) ? "NaN" : @sprintf("%.6f", rec["investment_cost"])
            println(io, "| ", rec["dataset"], " | ", rec["test"], " | ", rec["snapshots"], " | ", rec["status"], " | ", objective, " | ", margin, " | ", near, " | ", su_sd, " | ", inv, " | ", get(rec, "warnings", ""), " |")
        end
        println(io)
        println(io, "## Warnings and Unresolved Issues")
        println(io)
        println(io, "- The raw PyPSA JSON uses `n_block0`/`n_block_max`; the current optimizer formulation reads `n0`/`nmax`, so the tests apply a solver-copy adapter.")
        println(io, "- `na0` invariants are validated on raw data for every block-enabled component and snapshot: `0 <= na0 <= n_block0 <= n_block_max`.")
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
            "Multinetwork cases are identified by `multinetwork=true` and processed through `data[\"nw\"]`; the active path receives explicit `:hour`, `:scenario`, and `:year` dimensions.",
            "Raw block fields are schema-checked as `n_block0`/`n_block_max`; solver copies map them to the formulation fields `n0`/`nmax`.",
            "Raw block-count invariants are hard-validated before solver-copy mapping: `0 <= na0 <= n_block0 <= n_block_max`.",
            "PyPSA `link` records are mapped to PowerModels `dcline` only when `carrier == \"DC\"`; non-DC link carriers are ignored.",
            "gSCR constraints are activated only through `ref_add_uc_gscr_block!` and `constraint_gscr_gershgorin_sufficient` in `build_uc_gscr_block_integration`.",
            "UC/scheduling mode is selected in the test adapter by fixing `nmax=n0`; CAPEXP mode allows `nmax>n0` where available.",
            "Results expose `n_block`, `na_block`, `su_block`, and `sd_block` through the active model variables and solution reporting hooks.",
        ]

        @testset "Load-only schema" begin
            for (name, snapshots) in _PYPSA_ACCEPTANCE_DATASETS
                data = _pypsa_load_case(name)
                _pypsa_assert_schema(data, snapshots)
                _pypsa_assert_no_na0_invariant_violations(data, name)
                summary = _pypsa_schema_summary(data, snapshots)
                push!(records, Dict{String,Any}(
                    "dataset" => name,
                    "test" => "load/schema",
                    "snapshots" => summary["snapshots"],
                    "status" => "PASS",
                    "objective" => nothing,
                    "warnings" => "",
                ))
            end
        end

        raw_3 = _pypsa_load_case("base_s_5_3snap")

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
                "status" => stripped_status,
                "objective" => get(stripped_result, "objective", nothing),
                "warnings" => "block metadata ignored by standard OPF",
            ))
        end

        for (name, snapshots) in _PYPSA_ACCEPTANCE_DATASETS[1:2]
            raw = _pypsa_load_case(name)
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
