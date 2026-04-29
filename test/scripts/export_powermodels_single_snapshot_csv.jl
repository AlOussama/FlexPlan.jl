import FlexPlan as _FP
import JSON
using CSV
using DataFrames
using Dates

const _DEFAULT_CASE_PATH = get(
    ENV,
    "PYPSA_ELEC_S37_24H_SMALL_CASE",
    raw"D:\Projekte\Code\pypsatomatpowerx_clean_battery_policy\data\flexplan_block_gscr\elec_s_37_24h_from_0301\case.json",
)

const _DEFAULT_OUT_ROOT = normpath(@__DIR__, "..", "..", "results", "powermodels_single_snapshot_exports")
const _EPS = 1e-9

_as_float(x) = x isa Real ? float(x) : try parse(Float64, string(x)) catch; 0.0 end

function _add_dimensions_if_missing!(data::Dict{String,Any})
    if !haskey(data, "dim")
        _FP.add_dimension!(data, :hour, length(data["nw"]))
        _FP.add_dimension!(data, :scenario, Dict(1 => Dict{String,Any}("probability" => 1.0)))
        _FP.add_dimension!(data, :year, 1; metadata=Dict{String,Any}("scale_factor" => 1))
    end
    return data
end

function _normalize_dcline_entry!(dc::Dict{String,Any}, idx::Int)
    rate = get(dc, "pmaxf", get(dc, "pmaxt", get(dc, "rate_a", 0.0)))
    dc["index"] = get(dc, "index", idx)
    dc["carrier"] = lowercase(String(get(dc, "carrier", "dc")))
    dc["br_status"] = get(dc, "br_status", 1)
    dc["pf"] = get(dc, "pf", 0.0)
    dc["pt"] = get(dc, "pt", 0.0)
    dc["qf"] = get(dc, "qf", 0.0)
    dc["qt"] = get(dc, "qt", 0.0)
    dc["pminf"] = get(dc, "pminf", -rate)
    dc["pmaxf"] = get(dc, "pmaxf", rate)
    dc["pmint"] = get(dc, "pmint", -rate)
    dc["pmaxt"] = get(dc, "pmaxt", rate)
    dc["qminf"] = get(dc, "qminf", 0.0)
    dc["qmaxf"] = get(dc, "qmaxf", 0.0)
    dc["qmint"] = get(dc, "qmint", 0.0)
    dc["qmaxt"] = get(dc, "qmaxt", 0.0)
    dc["loss0"] = get(dc, "loss0", 0.0)
    dc["loss1"] = get(dc, "loss1", 0.0)
    dc["vf"] = get(dc, "vf", 1.0)
    dc["vt"] = get(dc, "vt", 1.0)
    dc["model"] = get(dc, "model", 2)
    dc["cost"] = get(dc, "cost", [0.0, 0.0])
    return dc
end

function _convert_links_to_dcline(nw::Dict{String,Any})
    out = Dict{String,Any}()
    links = get(nw, "link", Dict{String,Any}())
    if isempty(links)
        return out
    end
    bus_name_to_id = Dict{String,Int}()
    for (id, bus) in get(nw, "bus", Dict{String,Any}())
        if haskey(bus, "name")
            bus_name_to_id[String(bus["name"])] = parse(Int, id)
        end
    end
    idx = 0
    for (lid, link) in sort(collect(links); by=first)
        if lowercase(String(get(link, "carrier", ""))) != "dc"
            continue
        end
        f_bus = get(bus_name_to_id, String(get(link, "bus0", "")), nothing)
        t_bus = get(bus_name_to_id, String(get(link, "bus1", "")), nothing)
        if isnothing(f_bus) || isnothing(t_bus)
            continue
        end
        idx += 1
        rate = get(link, "p_nom", get(link, "rate_a", 0.0))
        out[string(idx)] = Dict{String,Any}(
            "index" => idx,
            "source_id" => ["pypsa_link", lid],
            "name" => get(link, "name", lid),
            "carrier" => "dc",
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
    return out
end

function _ensure_dcline!(nw::Dict{String,Any})
    existing = deepcopy(get(nw, "dcline", Dict{String,Any}()))
    converted = isempty(existing) ? _convert_links_to_dcline(nw) : Dict{String,Any}()
    merged = Dict{String,Any}()
    idx = 0
    for (_, dc) in sort(collect(existing); by=x -> parse(Int, x.first))
        idx += 1
        merged[string(idx)] = _normalize_dcline_entry!(deepcopy(dc), idx)
    end
    for (_, dc) in sort(collect(converted); by=x -> parse(Int, x.first))
        idx += 1
        merged[string(idx)] = _normalize_dcline_entry!(deepcopy(dc), idx)
    end
    nw["dcline"] = merged
    if haskey(nw, "link")
        delete!(nw, "link")
    end
    return nw
end

function _make_single_snapshot_network(raw::Dict{String,Any}, snapshot_id::Int)
    if !haskey(raw, "nw") || !haskey(raw["nw"], string(snapshot_id))
        error("Snapshot $(snapshot_id) not found in case data.")
    end
    out = deepcopy(raw)
    out["nw"] = Dict{String,Any}("1" => deepcopy(raw["nw"][string(snapshot_id)]))
    if haskey(out, "dim")
        delete!(out, "dim")
    end
    out["multinetwork"] = true
    out["per_unit"] = get(out, "per_unit", false)
    out["source_type"] = get(out, "source_type", "pypsa-flexplan-json")
    out["name"] = get(out, "name", "pypsa-elec-s37-single-snapshot")
    _add_dimensions_if_missing!(out)

    nw = out["nw"]["1"]
    _ensure_dcline!(nw)
    nw["ne_storage"] = get(nw, "ne_storage", Dict{String,Any}())
    nw["shunt"] = get(nw, "shunt", Dict{String,Any}())
    nw["switch"] = get(nw, "switch", Dict{String,Any}())
    for table in ("bus", "branch", "gen", "storage", "load", "dcline", "ne_storage", "shunt", "switch")
        for (id, comp) in get(nw, table, Dict{String,Any}())
            comp["index"] = get(comp, "index", try parse(Int, id) catch; 1 end)
        end
    end
    return out, nw
end

function _is_generator_candidate(g::Dict{String,Any})
    n0 = _as_float(get(g, "n_block0", get(g, "n0", 0.0)))
    nmax = _as_float(get(g, "n_block_max", get(g, "nmax", n0)))
    return nmax > n0 + _EPS
end

function _is_storage_candidate(st::Dict{String,Any})
    n0 = _as_float(get(st, "n_block0", get(st, "n0", 0.0)))
    nmax = _as_float(get(st, "n_block_max", get(st, "nmax", n0)))
    carrier = lowercase(String(get(st, "carrier", "")))
    return nmax > n0 + _EPS || carrier == "battery_gfl" || carrier == "battery_gfm"
end

function _normalize_cell(v)
    if v isa Dict || v isa AbstractVector || v isa Tuple
        return JSON.json(v)
    elseif v isa Bool || v isa Number || v isa Missing
        return v
    elseif isnothing(v)
        return missing
    else
        return string(v)
    end
end

function _dict_rows_to_dataframe(rows::Vector{Dict{String,Any}})
    if isempty(rows)
        return DataFrame()
    end
    cols = sort!(collect(Set(vcat((collect(keys(r)) for r in rows)...))))
    df = DataFrame()
    for c in cols
        df[!, Symbol(c)] = [_normalize_cell(get(r, c, missing)) for r in rows]
    end
    return df
end

function _table_rows(nw::Dict{String,Any}, table::String; predicate::Function=(id, comp) -> true)
    rows = Dict{String,Any}[]
    entries = get(nw, table, Dict{String,Any}())
    for (id, comp) in sort(collect(entries); by=x -> try parse(Int, x.first) catch; typemax(Int) end)
        if !predicate(id, comp)
            continue
        end
        row = Dict{String,Any}("id" => id)
        for (k, v) in comp
            row[string(k)] = v
        end
        push!(rows, row)
    end
    return rows
end

function _write_csv(path::String, rows::Vector{Dict{String,Any}})
    df = _dict_rows_to_dataframe(rows)
    CSV.write(path, df)
end

function main()
    case_path = get(ENV, "PYPSA_ELEC_S37_24H_SMALL_CASE", _DEFAULT_CASE_PATH)
    snapshot_id = parse(Int, get(ENV, "PM_EXPORT_SNAPSHOT_ID", "1"))
    out_root = get(ENV, "PM_EXPORT_OUT_DIR", _DEFAULT_OUT_ROOT)

    if !isfile(case_path)
        error("Case file not found: $(case_path)")
    end

    raw = JSON.parsefile(case_path)
    _, nw = _make_single_snapshot_network(raw, snapshot_id)

    stamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    out_dir = joinpath(out_root, "snapshot_$(snapshot_id)_$(stamp)")
    mkpath(out_dir)

    _write_csv(joinpath(out_dir, "bus.csv"), _table_rows(nw, "bus"))
    _write_csv(joinpath(out_dir, "load.csv"), _table_rows(nw, "load"))
    _write_csv(joinpath(out_dir, "gen.csv"), _table_rows(nw, "gen"))
    _write_csv(joinpath(out_dir, "storage.csv"), _table_rows(nw, "storage"))
    _write_csv(joinpath(out_dir, "ne_storage.csv"), _table_rows(nw, "ne_storage"))
    _write_csv(joinpath(out_dir, "branch.csv"), _table_rows(nw, "branch"))
    _write_csv(joinpath(out_dir, "dcline.csv"), _table_rows(nw, "dcline"))
    _write_csv(joinpath(out_dir, "shunt.csv"), _table_rows(nw, "shunt"))
    _write_csv(joinpath(out_dir, "switch.csv"), _table_rows(nw, "switch"))

    gen_candidate_rows = _table_rows(nw, "gen"; predicate=(id, comp) -> _is_generator_candidate(comp))
    st_candidate_rows = _table_rows(nw, "storage"; predicate=(id, comp) -> _is_storage_candidate(comp))
    _write_csv(joinpath(out_dir, "gen_candidates.csv"), gen_candidate_rows)
    _write_csv(joinpath(out_dir, "storage_candidates.csv"), st_candidate_rows)

    summary = Dict(
        "case_path" => case_path,
        "snapshot_id" => snapshot_id,
        "out_dir" => out_dir,
        "counts" => Dict(
            "bus" => length(get(nw, "bus", Dict{String,Any}())),
            "load" => length(get(nw, "load", Dict{String,Any}())),
            "gen" => length(get(nw, "gen", Dict{String,Any}())),
            "gen_candidates" => length(gen_candidate_rows),
            "storage" => length(get(nw, "storage", Dict{String,Any}())),
            "storage_candidates" => length(st_candidate_rows),
            "ne_storage" => length(get(nw, "ne_storage", Dict{String,Any}())),
            "branch" => length(get(nw, "branch", Dict{String,Any}())),
            "dcline" => length(get(nw, "dcline", Dict{String,Any}())),
            "shunt" => length(get(nw, "shunt", Dict{String,Any}())),
            "switch" => length(get(nw, "switch", Dict{String,Any}())),
        ),
    )

    open(joinpath(out_dir, "metadata.json"), "w") do io
        JSON.print(io, summary, 2)
    end

    println("Export completed.")
    println("Output folder: ", out_dir)
end

main()
