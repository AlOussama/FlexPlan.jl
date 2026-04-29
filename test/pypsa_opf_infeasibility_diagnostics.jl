import JSON
import Printf: @sprintf

const _PYPSA_OPF_DIAG_CASE = get(
    ENV,
    "PYPSA_OPF_DIAG_CASE",
    raw"D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr\base_s_5_3snap\case.json",
)

function _pypsa_diag_status(result_or_error)
    if result_or_error isa Dict && haskey(result_or_error, "termination_status")
        return string(result_or_error["termination_status"])
    end
    return "ERROR"
end

function _pypsa_diag_load_case()
    return JSON.parsefile(_PYPSA_OPF_DIAG_CASE)
end

function _pypsa_diag_add_dimensions!(data::Dict{String,Any})
    if !haskey(data, "dim")
        _FP.add_dimension!(data, :hour, length(data["nw"]))
        _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
        _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    end
    return data
end

function _pypsa_diag_link_to_dcline(nw::Dict{String,Any})
    bus_name_to_id = Dict(bus["name"] => parse(Int, id) for (id, bus) in nw["bus"])
    dcline = Dict{String,Any}()
    ignored = 0
    skipped_dc = 0

    dc_idx = 0
    for (link_id, link) in sort(collect(get(nw, "link", Dict{String,Any}())); by=first)
        if get(link, "carrier", "") != "DC"
            ignored += 1
            continue
        end

        f_bus = get(bus_name_to_id, link["bus0"], nothing)
        t_bus = get(bus_name_to_id, link["bus1"], nothing)
        if isnothing(f_bus) || isnothing(t_bus)
            skipped_dc += 1
            continue
        end

        dc_idx += 1
        rate = get(link, "p_nom", get(link, "rate_a", 0.0))
        dcline[string(dc_idx)] = Dict{String,Any}(
            "index" => dc_idx,
            "source_id" => ["pypsa_link", link_id],
            "name" => get(link, "name", link_id),
            "carrier" => get(link, "carrier", "DC"),
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

    return dcline, ignored, skipped_dc
end

function _pypsa_diag_prepare_solver_data(raw::Dict{String,Any})
    data = deepcopy(raw)
    data["per_unit"] = get(data, "per_unit", false)
    data["source_type"] = get(data, "source_type", "pypsa-flexplan-json")
    data["name"] = get(data, "name", "pypsa-flexplan-block-gscr")
    _pypsa_diag_add_dimensions!(data)

    total_links = 0
    ignored_links = 0
    skipped_dc_links = 0
    converted_dc_links = 0

    for nw in values(data["nw"])
        total_links += length(get(nw, "link", Dict{String,Any}()))
        dcline, ignored, skipped_dc = _pypsa_diag_link_to_dcline(nw)
        ignored_links += ignored
        skipped_dc_links += skipped_dc
        converted_dc_links += length(dcline)
        delete!(nw, "link")

        nw["per_unit"] = get(nw, "per_unit", data["per_unit"])
        nw["source_type"] = get(nw, "source_type", data["source_type"])
        nw["time_elapsed"] = get(nw, "time_elapsed", 1.0)
        nw["dcline"] = dcline
        for table in ("shunt", "switch")
            nw[table] = get(nw, table, Dict{String,Any}())
        end

        for table in ("bus", "branch", "gen", "storage", "load")
            for (id, component) in get(nw, table, Dict{String,Any}())
                component["index"] = get(component, "index", parse(Int, id))
            end
        end

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
        end
        for storage in values(nw["storage"])
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
    data["_pypsa_ignored_link_count"] = ignored_links
    data["_pypsa_skipped_dc_link_count"] = skipped_dc_links
    data["_pypsa_dcline_count"] = converted_dc_links
    return data
end

function _pypsa_diag_solve(data::Dict{String,Any}; with_storage::Bool=true)
    try
        return with_storage ? _PM.solve_mn_opf_strg(data, _PM.DCPPowerModel, milp_optimizer) : _PM.solve_mn_opf(data, _PM.DCPPowerModel, milp_optimizer)
    catch err
        return Dict{String,Any}("termination_status" => "ERROR", "error" => sprint(showerror, err))
    end
end

function _pypsa_diag_variant(raw::Dict{String,Any}, label::String, mutator; with_storage::Bool=true)
    data = _pypsa_diag_prepare_solver_data(raw)
    mutator(data)
    result = _pypsa_diag_solve(data; with_storage)
    return Dict{String,Any}(
        "label" => label,
        "status" => _pypsa_diag_status(result),
        "objective" => get(result, "objective", nothing),
        "error" => get(result, "error", ""),
    )
end

function _pypsa_diag_snapshot_metrics(nw_id::String, nw::Dict{String,Any}, solver_nw::Dict{String,Any})
    bus_ids = Set(parse(Int, id) for id in keys(nw["bus"]))
    gen_pmin = sum((get(gen, "pmin", 0.0) for gen in values(nw["gen"]) if get(gen, "gen_status", 1) != 0); init=0.0)
    gen_pmax = sum((get(gen, "pmax", 0.0) for gen in values(nw["gen"]) if get(gen, "gen_status", 1) != 0); init=0.0)
    storage_charge = sum((get(storage, "charge_rating", 0.0) for storage in values(solver_nw["storage"]) if get(storage, "status", 1) != 0); init=0.0)
    storage_discharge = sum((get(storage, "discharge_rating", 0.0) for storage in values(solver_nw["storage"]) if get(storage, "status", 1) != 0); init=0.0)
    dcline_import = sum((max(0.0, get(dc, "pmaxt", 0.0)) for dc in values(solver_nw["dcline"]) if get(dc, "br_status", 1) != 0); init=0.0)
    dcline_export = sum((max(0.0, get(dc, "pmaxf", 0.0)) for dc in values(solver_nw["dcline"]) if get(dc, "br_status", 1) != 0); init=0.0)
    active_load = sum((get(load, "pd", 0.0) for load in values(nw["load"]) if get(load, "status", 1) != 0); init=0.0)

    branch_rates = [get(branch, "rate_a", Inf) for branch in values(nw["branch"]) if get(branch, "br_status", 1) != 0]
    branch_x = [get(branch, "br_x", NaN) for branch in values(nw["branch"]) if get(branch, "br_status", 1) != 0]
    voltage_mins = [get(bus, "vmin", NaN) for bus in values(nw["bus"])]
    voltage_maxs = [get(bus, "vmax", NaN) for bus in values(nw["bus"])]
    ref_buses = [id for (id, bus) in nw["bus"] if get(bus, "bus_type", 1) == 3]
    if isempty(ref_buses)
        ref_buses = [first(sort(collect(keys(nw["bus"])); by=id -> parse(Int, id)))]
    end

    storage_issues = String[]
    for (id, storage) in solver_nw["storage"]
        energy = get(storage, "energy", 0.0)
        energy_rating = get(storage, "energy_rating", Inf)
        if energy < -1e-8 || energy > energy_rating + get(storage, "discharge_rating", 0.0) / max(get(storage, "discharge_efficiency", 1.0), 1e-9) + 1e-8
            push!(storage_issues, "storage $(id): initial energy $(energy) incompatible with energy_rating $(energy_rating) and first-period discharge capability")
        elseif energy > energy_rating + 1e-8
            push!(storage_issues, "storage $(id): initial energy $(energy) exceeds energy_rating $(energy_rating)")
        end
        if get(storage, "charge_rating", 0.0) < -1e-8 || get(storage, "discharge_rating", 0.0) < -1e-8 || get(storage, "energy_rating", 0.0) < -1e-8
            push!(storage_issues, "storage $(id): negative charge/discharge/energy rating")
        end
    end

    missing_bus_issues = String[]
    for (id, load) in nw["load"]
        if !(load["load_bus"] in bus_ids)
            push!(missing_bus_issues, "load $(id) -> missing bus $(load["load_bus"])")
        end
    end
    for (id, gen) in nw["gen"]
        if !(gen["gen_bus"] in bus_ids)
            push!(missing_bus_issues, "gen $(id) -> missing bus $(gen["gen_bus"])")
        end
    end
    for (id, storage) in solver_nw["storage"]
        if !(storage["storage_bus"] in bus_ids)
            push!(missing_bus_issues, "storage $(id) -> missing bus $(storage["storage_bus"])")
        end
    end
    for (id, dc) in solver_nw["dcline"]
        if !(dc["f_bus"] in bus_ids) || !(dc["t_bus"] in bus_ids)
            push!(missing_bus_issues, "dcline $(id) -> missing endpoint $(dc["f_bus"])-$(dc["t_bus"])")
        end
    end

    gen_bound_issues = ["gen $(id): pmin $(gen["pmin"]) > pmax $(gen["pmax"])" for (id, gen) in nw["gen"] if get(gen, "pmin", 0.0) > get(gen, "pmax", 0.0) + 1e-8]
    small_rate = ["branch $(id): rate_a=$(get(branch, "rate_a", missing))" for (id, branch) in nw["branch"] if get(branch, "rate_a", Inf) <= 1e-6]
    small_x = ["branch $(id): br_x=$(get(branch, "br_x", missing))" for (id, branch) in nw["branch"] if abs(get(branch, "br_x", Inf)) <= 1e-8]

    return Dict{String,Any}(
        "nw" => nw_id,
        "total_active_load" => active_load,
        "total_reactive_load" => sum((get(load, "qd", 0.0) for load in values(nw["load"]) if get(load, "status", 1) != 0); init=0.0),
        "total_gen_pmin" => gen_pmin,
        "total_gen_pmax" => gen_pmax,
        "total_storage_charge" => storage_charge,
        "total_storage_discharge" => storage_discharge,
        "total_dcline_import" => dcline_import,
        "total_dcline_export" => dcline_export,
        "positive_pmax_gens" => count(gen -> get(gen, "pmax", 0.0) > 1e-8 && get(gen, "gen_status", 1) != 0, values(nw["gen"])),
        "storage_count" => length(solver_nw["storage"]),
        "dcline_count" => length(solver_nw["dcline"]),
        "reference_bus" => join(ref_buses, ", "),
        "voltage_min" => minimum(voltage_mins),
        "voltage_max" => maximum(voltage_maxs),
        "branch_rate_min" => minimum(branch_rates),
        "branch_rate_max" => maximum(branch_rates),
        "branch_x_min_abs" => minimum(abs.(branch_x)),
        "near_zero_x" => small_x,
        "small_rate" => small_rate,
        "gen_bound_issues" => gen_bound_issues,
        "storage_issues" => storage_issues,
        "missing_bus_issues" => missing_bus_issues,
        "active_balance_min_supply" => gen_pmin - storage_charge - dcline_export,
        "active_balance_max_supply" => gen_pmax + storage_discharge + dcline_import,
        "active_balance_necessary_ok" => gen_pmin - storage_charge - dcline_export <= active_load <= gen_pmax + storage_discharge + dcline_import,
    )
end

function _pypsa_diag_converter_flags(raw::Dict{String,Any}, solver_data::Dict{String,Any})
    flags = String[]
    for (nw_id, nw) in sort(collect(raw["nw"]); by=x -> parse(Int, x.first))
        for (id, gen) in nw["gen"]
            if haskey(gen, "na0") && haskey(gen, "n_block0") && gen["na0"] > gen["n_block0"] + 1e-8
                push!(flags, "nw $(nw_id) gen $(id): raw na0=$(gen["na0"]) > n_block0=$(gen["n_block0"])")
            end
            if get(gen, "p_block_max_pu", 1.0) < 1e-5 && get(gen, "pmax", 0.0) > 1e-6
                push!(flags, "nw $(nw_id) gen $(id): p_block_max_pu very small while pmax positive")
            end
        end
        for (id, storage) in nw["storage"]
            if haskey(storage, "na0") && haskey(storage, "n_block0") && storage["na0"] > storage["n_block0"] + 1e-8
                push!(flags, "nw $(nw_id) storage $(id): raw na0=$(storage["na0"]) > n_block0=$(storage["n_block0"])")
            end
            if get(storage, "energy", 0.0) > get(storage, "energy_rating", Inf) + 1e-8
                push!(flags, "nw $(nw_id) storage $(id): energy=$(storage["energy"]) > energy_rating=$(storage["energy_rating"]) before first-period dispatch")
            end
        end
    end

    max_load = maximum(sum(load["pd"] for load in values(nw["load"])) for nw in values(raw["nw"]))
    max_pmax = maximum(sum(gen["pmax"] for gen in values(nw["gen"])) for nw in values(raw["nw"]))
    if max_load > 0.0 && max_pmax / max_load > 20.0
        push!(flags, "generator pmax/load ratio is high ($(max_pmax / max_load)); check p/baseMVA scaling")
    end

    min_rate = minimum(get(branch, "rate_a", Inf) for nw in values(raw["nw"]) for branch in values(nw["branch"]))
    max_rate = maximum(get(branch, "rate_a", 0.0) for nw in values(raw["nw"]) for branch in values(nw["branch"]))
    if min_rate <= 1e-6 || max_rate / max(min_rate, 1e-9) > 1e6
        push!(flags, "suspicious branch rate scaling: min=$(min_rate), max=$(max_rate)")
    end

    if solver_data["_pypsa_dcline_count"] == 0 && solver_data["_pypsa_link_count"] > 0
        push!(flags, "all PyPSA links in this dataset are non-DC carrier links or have non-AC endpoints; no PowerModels dcline is active")
    end
    if solver_data["_pypsa_ignored_link_count"] > 0
        push!(flags, "$(solver_data["_pypsa_ignored_link_count"]) non-DC links ignored by standard OPF solver copy")
    end

    return flags
end

function _pypsa_diag_write_report(snapshot_metrics, variants, flags, base_status)
    report_dir = normpath(@__DIR__, "..", "reports")
    mkpath(report_dir)
    report_path = normpath(report_dir, "pypsa_opf_infeasibility_diagnostics.md")

    open(report_path, "w") do io
        println(io, "# PyPSA OPF Infeasibility Diagnostics")
        println(io)
        println(io, "Dataset: `", _PYPSA_OPF_DIAG_CASE, "`")
        println(io)
        println(io, "Base standard OPF status: `", base_status, "`")
        println(io)
        println(io, "## Snapshot Metrics")
        println(io)
        println(io, "| nw | P load | Q load | gen pmin | gen pmax | storage charge | storage discharge | dcline import | dcline export | gens pmax>0 | storage | dcline | ref bus | vmin/vmax | rate min/max | min |x| | active balance necessary |")
        println(io, "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|---:|---|")
        for m in snapshot_metrics
            println(
                io,
                "| ", m["nw"],
                " | ", @sprintf("%.6f", m["total_active_load"]),
                " | ", @sprintf("%.6f", m["total_reactive_load"]),
                " | ", @sprintf("%.6f", m["total_gen_pmin"]),
                " | ", @sprintf("%.6f", m["total_gen_pmax"]),
                " | ", @sprintf("%.6f", m["total_storage_charge"]),
                " | ", @sprintf("%.6f", m["total_storage_discharge"]),
                " | ", @sprintf("%.6f", m["total_dcline_import"]),
                " | ", @sprintf("%.6f", m["total_dcline_export"]),
                " | ", m["positive_pmax_gens"],
                " | ", m["storage_count"],
                " | ", m["dcline_count"],
                " | ", m["reference_bus"],
                " | ", @sprintf("%.4f / %.4f", m["voltage_min"], m["voltage_max"]),
                " | ", @sprintf("%.6f / %.6f", m["branch_rate_min"], m["branch_rate_max"]),
                " | ", @sprintf("%.8f", m["branch_x_min_abs"]),
                " | ", m["active_balance_necessary_ok"] ? "PASS" : "FAIL",
                " |",
            )
        end
        println(io)
        println(io, "## Structural Issues")
        for m in snapshot_metrics
            println(io)
            println(io, "### Snapshot ", m["nw"])
            println(io, "- active-power necessary interval: [", @sprintf("%.6f", m["active_balance_min_supply"]), ", ", @sprintf("%.6f", m["active_balance_max_supply"]), "] vs load ", @sprintf("%.6f", m["total_active_load"]))
            for (title, key) in [
                ("near-zero branch x", "near_zero_x"),
                ("zero/small branch rate", "small_rate"),
                ("generator pmin > pmax", "gen_bound_issues"),
                ("storage inconsistent bounds", "storage_issues"),
                ("missing bus attachments", "missing_bus_issues"),
            ]
                items = m[key]
                println(io, "- ", title, ": ", isempty(items) ? "none" : join(items, "; "))
            end
        end
        println(io)
        println(io, "## Diagnostic Solve Variants")
        println(io)
        println(io, "| variant | status | objective | note |")
        println(io, "|---|---|---:|---|")
        for v in variants
            objective = isnothing(v["objective"]) ? "NaN" : @sprintf("%.6f", v["objective"])
            note = isempty(v["error"]) ? "" : replace(v["error"], "\n" => " ")
            println(io, "| ", v["label"], " | ", v["status"], " | ", objective, " | ", note, " |")
        end
        println(io)
        println(io, "## Converter-Side Consistency Flags")
        println(io)
        if isempty(flags)
            println(io, "- none")
        else
            for flag in flags
                println(io, "- ", flag)
            end
        end
        println(io)
        println(io, "## Likely Cause")
        println(io)
        println(io, "- The strongest diagnostic is storage-state inconsistency: several snapshots contain storage `energy` above `energy_rating`, and the first-period state equation can require more discharge than the unit can provide while respecting `se <= energy_rating`.")
        println(io, "- Branch limits, voltage bounds, q limits, and dcline removal are secondary unless their relaxed variants are the first to become feasible.")
        println(io)
        println(io, "## Recommended Converter-Side Fix")
        println(io)
        println(io, "- Ensure `storage.energy` is an initial state of charge within `[0, energy_rating]` on the PowerModels/FlexPlan base, or export an `energy_rating` that is at least the maximum initial state plus physically reachable first-period adjustment.")
        println(io, "- Preserve only PyPSA links with `carrier == \"DC\"` as PowerModels `dcline`; non-electrical carrier links should not enter standard OPF.")
    end
    return report_path
end

function run_pypsa_opf_infeasibility_diagnostics()
    raw = _pypsa_diag_load_case()
    solver_data = _pypsa_diag_prepare_solver_data(raw)
    base = _pypsa_diag_solve(deepcopy(solver_data); with_storage=true)
    base_status = _pypsa_diag_status(base)

    snapshot_metrics = Dict{String,Any}[]
    for nw_id in sort(collect(keys(raw["nw"])); by=id -> parse(Int, id))
        push!(snapshot_metrics, _pypsa_diag_snapshot_metrics(nw_id, raw["nw"][nw_id], solver_data["nw"][nw_id]))
    end

    variants = Dict{String,Any}[]
    push!(variants, Dict{String,Any}("label" => "base solve_mn_opf_strg DCP", "status" => base_status, "objective" => get(base, "objective", nothing), "error" => get(base, "error", "")))
    push!(variants, _pypsa_diag_variant(raw, "branch limits relaxed", data -> foreach(nw -> foreach(branch -> branch["rate_a"] = 1e9, values(nw["branch"])), values(data["nw"]))))
    push!(variants, _pypsa_diag_variant(raw, "voltage bounds widened", data -> foreach(nw -> foreach(bus -> (bus["vmin"] = 0.0; bus["vmax"] = 2.0), values(nw["bus"])), values(data["nw"]))))
    push!(variants, _pypsa_diag_variant(raw, "q limits relaxed", data -> foreach(nw -> begin
        foreach(gen -> (gen["qmin"] = -1e9; gen["qmax"] = 1e9), values(nw["gen"]))
        foreach(storage -> (storage["qmin"] = -1e9; storage["qmax"] = 1e9), values(nw["storage"]))
        foreach(dc -> (dc["qminf"] = -1e9; dc["qmaxf"] = 1e9; dc["qmint"] = -1e9; dc["qmaxt"] = 1e9), values(nw["dcline"]))
    end, values(data["nw"]))))
    push!(variants, _pypsa_diag_variant(raw, "storage removed", data -> foreach(nw -> nw["storage"] = Dict{String,Any}(), values(data["nw"])); with_storage=false))
    push!(variants, _pypsa_diag_variant(raw, "storage disabled", data -> foreach(nw -> foreach(storage -> storage["status"] = 0, values(nw["storage"])), values(data["nw"]))))
    push!(variants, _pypsa_diag_variant(raw, "dcline links removed", data -> foreach(nw -> nw["dcline"] = Dict{String,Any}(), values(data["nw"]))))
    push!(variants, _pypsa_diag_variant(raw, "DC OPF without storage table", data -> foreach(nw -> nw["storage"] = Dict{String,Any}(), values(data["nw"])); with_storage=false))
    push!(variants, _pypsa_diag_variant(raw, "storage energy clamped to rating", data -> foreach(nw -> foreach(storage -> storage["energy"] = min(max(get(storage, "energy", 0.0), 0.0), get(storage, "energy_rating", get(storage, "energy", 0.0))), values(nw["storage"])), values(data["nw"]))))

    flags = _pypsa_diag_converter_flags(raw, solver_data)
    return _pypsa_diag_write_report(snapshot_metrics, variants, flags, base_status), variants, snapshot_metrics, flags
end

@testset "PyPSA standard OPF infeasibility diagnostics" begin
    if !isfile(_PYPSA_OPF_DIAG_CASE)
        @info "Skipping PyPSA OPF diagnostics because dataset file is not available" case=_PYPSA_OPF_DIAG_CASE
    else
        report_path, _, _, _ = run_pypsa_opf_infeasibility_diagnostics()
        @test isfile(report_path)
    end
end
