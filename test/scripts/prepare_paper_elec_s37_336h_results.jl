import CSV
import DataFrames
import JSON
using Plots
using Statistics
using Printf

const DF = DataFrames

const ALPHA_PAPER = 1.5
const EPS_P = 1e-6
const EPS_GSCR = 1e-6
const EPS_MU = 1e-7
const ANNUAL_OPERATION_SCALING_FACTOR = 26.0

const INPUT_ROOT = normpath(@__DIR__, "..", "..", "reports", "frozen_postprocessing_336h_0114_integer_blocks_20260428", "results")
const OUTPUT_ROOT = normpath(@__DIR__, "..", "..", "reports", "paper_elec_s_37_campaign_336h")

const CASES = [
    (label="BASE", run_dir="H_336h_gmin_0p0_integer_blocks", gmin=0.0),
    (label="gSCR-GERSH-1.0", run_dir="H_336h_gmin_1p0_integer_blocks", gmin=1.0),
    (label="gSCR-GERSH-1.5", run_dir="H_336h_gmin_1p5_integer_blocks", gmin=1.5),
]

const WIND_CARRIERS = Set(["onwind", "offwind-ac", "offwind-dc"])
const SOLAR_CARRIERS = Set(["solar"])
const GAS_CARRIERS = Set(["CCGT"])
const BESS_GFL_CARRIERS = Set(["battery_gfl", "BESS-GFL"])
const BESS_GFM_CARRIERS = Set(["battery_gfm", "BESS-GFM"])

function read_json(path::AbstractString)
    return JSON.parsefile(path)
end

function read_csv(path::AbstractString)
    return CSV.read(path, DF.DataFrame; normalizenames=false)
end

function write_csv(path::AbstractString, df::DF.DataFrame)
    mkpath(dirname(path))
    CSV.write(path, df)
end

function run_path(case)
    return normpath(INPUT_ROOT, case.run_dir)
end

function require_file(path::AbstractString)
    isfile(path) || error("Required input file missing: $path")
    return path
end

function carrier_value(d::AbstractDict, carrier::String)
    return Float64(get(d, carrier, 0.0))
end

function get_installed_by_carrier(case)
    path = require_file(normpath(run_path(case), "investment_by_carrier.csv"))
    df = read_csv(path)
    d = Dict{String,Float64}()
    for r in eachrow(df)
        d[string(r["carrier"])] = Float64(r["installed_capacity_GW"])
    end
    return d
end

function group_capacity_gw(case)
    d = get_installed_by_carrier(case)
    wind = sum(carrier_value(d, c) for c in WIND_CARRIERS; init=0.0)
    solar = sum(carrier_value(d, c) for c in SOLAR_CARRIERS; init=0.0)
    gas = sum(carrier_value(d, c) for c in GAS_CARRIERS; init=0.0)
    bess_gfl = sum(carrier_value(d, c) for c in BESS_GFL_CARRIERS; init=0.0)
    bess_gfm = sum(carrier_value(d, c) for c in BESS_GFM_CARRIERS; init=0.0)
    return Dict(
        "Wind" => wind,
        "Solar PV" => solar,
        "Gas" => gas,
        "BESS-GFL" => bess_gfl,
        "BESS-GFM" => bess_gfm,
    )
end

function group_energy_twh(case)
    path = require_file(normpath(run_path(case), "dispatch_by_carrier.csv"))
    df = read_csv(path)
    gen = Dict{String,Float64}()
    dch = Dict{String,Float64}()
    ch = Dict{String,Float64}()
    for r in eachrow(df)
        c = string(r["carrier"])
        gen[c] = Float64(r["generation"])
        dch[c] = Float64(r["storage_discharge"])
        ch[c] = Float64(r["storage_charge"])
    end
    scale = ANNUAL_OPERATION_SCALING_FACTOR / 1e6
    wind = scale * sum(get(gen, c, 0.0) for c in WIND_CARRIERS; init=0.0)
    solar = scale * sum(get(gen, c, 0.0) for c in SOLAR_CARRIERS; init=0.0)
    gas = scale * sum(get(gen, c, 0.0) for c in GAS_CARRIERS; init=0.0)
    bess_discharge = scale * sum(get(dch, c, 0.0) for c in union(BESS_GFL_CARRIERS, BESS_GFM_CARRIERS); init=0.0)
    bess_charge = scale * sum(get(ch, c, 0.0) for c in union(BESS_GFL_CARRIERS, BESS_GFM_CARRIERS); init=0.0)
    return Dict(
        "Wind" => wind,
        "Solar PV" => solar,
        "Gas" => gas,
        "BESS discharge" => bess_discharge,
        "BESS charge" => bess_charge,
    )
end

function scenario_cost_beur(case)
    d = read_json(require_file(normpath(run_path(case), "cost_summary.json")))
    return Float64(d["total_annual_system_cost_BEUR_per_year"])
end

function solve_time_min(case)
    d = read_json(require_file(normpath(run_path(case), "solver_summary.json")))
    return Float64(d["solve_time_sec"]) / 60.0
end

function termination_status(case)
    d = read_json(require_file(normpath(run_path(case), "solver_summary.json")))
    return string(d["status"])
end

function region_code(name::AbstractString)
    m = match(r"^([A-Za-z]+)", strip(name))
    isnothing(m) && return strip(name)
    code = uppercase(m.captures[1])
    code = replace(code, r"\d" => "")
    return code == "GB" ? "UK" : code
end

function bus_region_map(case)
    df = read_csv(require_file(normpath(run_path(case), "node_binding_frequency.csv")))
    names = Dict{Int,String}()
    codes = Dict{Int,String}()
    for r in eachrow(df)
        b = Int(round(Float64(r["bus"])))
        nm = string(r["region_name"])
        names[b] = nm
        codes[b] = region_code(nm)
    end
    return names, codes
end

function online_metrics(case)
    sched = read_csv(require_file(normpath(run_path(case), "online_schedule.csv")))
    agg = Dict{Tuple{Int,Int},Dict{String,Float64}}()
    for r in eachrow(sched)
        t = Int(round(Float64(r["snapshot"])))
        b = Int(round(Float64(r["bus"])))
        carr = string(r["carrier"])
        typ = lowercase(string(r["type"]))
        cap = Float64(r["online_capacity_MW"])
        stren = Float64(r["online_strength"])
        key = (t, b)
        v = get!(agg, key, Dict("gfl" => 0.0, "gfm" => 0.0, "wind" => 0.0, "solar" => 0.0))
        if typ == "gfl"
            v["gfl"] += cap
            if carr in WIND_CARRIERS
                v["wind"] += cap
            elseif carr in SOLAR_CARRIERS
                v["solar"] += cap
            end
        elseif typ == "gfm"
            v["gfm"] += stren
        end
    end
    return agg
end

function select_regions(g15_case)
    agg = online_metrics(g15_case)
    names, codes = bus_region_map(g15_case)
    buses = sort(collect(unique(k[2] for k in keys(agg))))
    rows = Dict{Int,Dict{String,Float64}}()
    for b in buses
        wind = 0.0
        solar = 0.0
        gfl = 0.0
        max_util = NaN
        max_rho = NaN
        for t in 1:336
            v = get(agg, (t, b), Dict("gfl" => 0.0, "gfm" => 0.0, "wind" => 0.0, "solar" => 0.0))
            wind += v["wind"]
            solar += v["solar"]
            gfl += v["gfl"]
            denom = v["gfm"]
            if denom > EPS_P && v["gfl"] > EPS_P
                util = ALPHA_PAPER * v["gfl"] / denom
                rho = denom / (ALPHA_PAPER * v["gfl"])
                max_util = isnan(max_util) ? util : max(max_util, util)
                max_rho = isnan(max_rho) ? rho : max(max_rho, rho)
            end
        end
        rows[b] = Dict(
            "wind_exposure_sum" => wind,
            "solar_exposure_sum" => solar,
            "gfl_exposure_sum" => gfl,
            "max_local_utilization" => max_util,
            "max_local_rho_dec" => max_rho,
        )
    end

    selected = Int[]
    reasons = Dict{Int,String}()
    function add_top(metric, n, reason)
        ranked = sort(buses; by=b -> (isnan(rows[b][metric]) ? -Inf : rows[b][metric]), rev=true)
        for b in ranked
            rows[b][metric] > 0 || continue
            if !(b in selected)
                push!(selected, b)
                reasons[b] = reason
            end
            length([x for x in selected if get(reasons, x, "") == reason]) >= n && break
        end
    end
    add_top("wind_exposure_sum", 2, "top_wind_exposure")
    add_top("solar_exposure_sum", 2, "top_solar_exposure")
    add_top("max_local_utilization", 1, "top_local_utilization")
    ranked_gfl = sort(buses; by=b -> rows[b]["gfl_exposure_sum"], rev=true)
    for b in ranked_gfl
        length(selected) >= 5 && break
        if !(b in selected)
            push!(selected, b)
            reasons[b] = "fill_next_high_gfl"
        end
    end
    selected = selected[1:min(5, length(selected))]

    out = DF.DataFrame(
        region_id = Int[],
        region_name = String[],
        region_code = String[],
        legend_label = String[],
        selection_reason = String[],
        wind_exposure_sum = Float64[],
        solar_exposure_sum = Float64[],
        gfl_exposure_sum = Float64[],
        max_local_utilization = Union{Missing,Float64}[],
        max_local_rho_dec = Union{Missing,Float64}[],
    )
    for b in selected
        r = rows[b]
        push!(out, (
            b,
            get(names, b, string(b)),
            get(codes, b, string(b)),
            get(codes, b, string(b)),
            reasons[b],
            r["wind_exposure_sum"],
            r["solar_exposure_sum"],
            r["gfl_exposure_sum"],
            isnan(r["max_local_utilization"]) ? missing : r["max_local_utilization"],
            isnan(r["max_local_rho_dec"]) ? missing : r["max_local_rho_dec"],
        ))
    end
    return out, agg, names, codes
end

function strength_timeseries(selected, agg, names, codes)
    rows = DF.DataFrame(
        t = Int[],
        hour = Int[],
        day = Float64[],
        scenario_name = String[],
        region_id = Union{Missing,Int}[],
        region_name = String[],
        region_code = String[],
        metric_type = String[],
        value = Union{Missing,Float64}[],
        alpha_paper = Float64[],
    )

    for r in eachrow(selected)
        b = Int(r.region_id)
        for t in 1:336
            v = get(agg, (t, b), Dict("gfl" => 0.0, "gfm" => 0.0))
            rho = v["gfl"] <= EPS_P ? missing : v["gfm"] / (ALPHA_PAPER * v["gfl"])
            push!(rows, (t, t, (t - 1) / 24 + 1, "gSCR-GERSH-1.5", b, get(names, b, string(b)), get(codes, b, string(b)), "local_rho_dec", rho, ALPHA_PAPER))
        end
    end

    for case in CASES
        ts = read_csv(require_file(normpath(run_path(case), "posthoc_strength_timeseries.csv")))
        for r in eachrow(ts)
            t = Int(round(Float64(r["snapshot"])))
            rho = Float64(r["gSCR_t"]) / ALPHA_PAPER
            push!(rows, (t, t, (t - 1) / 24 + 1, case.label, missing, "system", "system", "global_rho_gscr", rho, ALPHA_PAPER))
        end
    end
    return rows
end

function local_validation_metrics(case)
    agg = online_metrics(case)
    max_util = -Inf
    total_deficit = 0.0
    for v in values(agg)
        denom = v["gfm"]
        gfl = v["gfl"]
        if denom > EPS_P && gfl > EPS_P
            max_util = max(max_util, ALPHA_PAPER * gfl / denom)
        end
        total_deficit += max(0.0, ALPHA_PAPER * gfl - denom)
    end
    return (isfinite(max_util) ? max_util : NaN, total_deficit)
end

function validation_table()
    df = DF.DataFrame(metric=String[], unit=String[])
    for case in CASES
        df[!, case.label] = Any[]
    end
    metric_rows = [
        ("min_global_gSCR_t", "p.u."),
        ("global_gSCR_violation_snapshots_percent_alpha_1p5", "%"),
        ("min_mu_t_alpha_1p5", "p.u."),
        ("mu_violation_snapshots_percent_alpha_1p5", "%"),
        ("max_local_utilization_alpha_1p5", "p.u."),
        ("total_local_deficit_alpha_1p5", "MW-equivalent"),
    ]
    for (m, u) in metric_rows
        vals = Any[m, u]
        for case in CASES
            ts = read_csv(require_file(normpath(run_path(case), "posthoc_strength_timeseries.csv")))
            gscr = Float64.(ts[!, "gSCR_t"])
            mu = Float64.(ts[!, "min_mu_t_alpha_1p5"])
            util, deficit = local_validation_metrics(case)
            val = if m == "min_global_gSCR_t"
                minimum(gscr)
            elseif m == "global_gSCR_violation_snapshots_percent_alpha_1p5"
                100 * count(x -> x < ALPHA_PAPER - EPS_GSCR, gscr) / length(gscr)
            elseif m == "min_mu_t_alpha_1p5"
                minimum(mu)
            elseif m == "mu_violation_snapshots_percent_alpha_1p5"
                100 * count(x -> x < -EPS_MU, mu) / length(mu)
            elseif m == "max_local_utilization_alpha_1p5"
                util
            else
                deficit
            end
            push!(vals, val)
        end
        push!(df, Tuple(vals))
    end
    return df
end

function table_a()
    costs = Dict(c.label => scenario_cost_beur(c) for c in CASES)
    caps = Dict(c.label => group_capacity_gw(c) for c in CASES)
    times = Dict(c.label => solve_time_min(c) for c in CASES)
    base = costs["BASE"]
    near_zero_cost = abs(base) < 1e-9
    rows = [
        ("Delta cost vs BASE", "B€/a", "--", costs["gSCR-GERSH-1.0"] - base, costs["gSCR-GERSH-1.5"] - base),
        ("Delta cost vs BASE (%)", "%", "--", near_zero_cost ? "n/a" : 100 * (costs["gSCR-GERSH-1.0"] - base) / base, near_zero_cost ? "n/a" : 100 * (costs["gSCR-GERSH-1.5"] - base) / base),
        ("BESS-GFM", "GW", caps["BASE"]["BESS-GFM"], caps["gSCR-GERSH-1.0"]["BESS-GFM"], caps["gSCR-GERSH-1.5"]["BESS-GFM"]),
        ("BESS-GFL", "GW", caps["BASE"]["BESS-GFL"], caps["gSCR-GERSH-1.0"]["BESS-GFL"], caps["gSCR-GERSH-1.5"]["BESS-GFL"]),
        ("Wind", "GW", caps["BASE"]["Wind"], caps["gSCR-GERSH-1.0"]["Wind"], caps["gSCR-GERSH-1.5"]["Wind"]),
        ("Solar PV", "GW", caps["BASE"]["Solar PV"], caps["gSCR-GERSH-1.0"]["Solar PV"], caps["gSCR-GERSH-1.5"]["Solar PV"]),
        ("Gas", "GW", caps["BASE"]["Gas"], caps["gSCR-GERSH-1.0"]["Gas"], caps["gSCR-GERSH-1.5"]["Gas"]),
        ("Total BESS", "GW", caps["BASE"]["BESS-GFL"] + caps["BASE"]["BESS-GFM"], caps["gSCR-GERSH-1.0"]["BESS-GFL"] + caps["gSCR-GERSH-1.0"]["BESS-GFM"], caps["gSCR-GERSH-1.5"]["BESS-GFL"] + caps["gSCR-GERSH-1.5"]["BESS-GFM"]),
        ("Solve time", "min", times["BASE"], times["gSCR-GERSH-1.0"], times["gSCR-GERSH-1.5"]),
    ]
    out = DF.DataFrame(metric=String[], unit=String[], BASE=Any[], var"gSCR-GERSH-1.0"=Any[], var"gSCR-GERSH-1.5"=Any[], delta_gSCR_1p5_vs_BASE=Any[], delta_gSCR_1p5_vs_BASE_percent=Any[])
    for (m,u,b,g1,g15) in rows
        delta = (b isa Number && g15 isa Number) ? g15 - b : "--"
        pct = (b isa Number && g15 isa Number && abs(b) > 1e-12) ? 100 * (g15 - b) / b : "n/a"
        push!(out, (m,u,b,g1,g15,delta,pct))
    end
    return out
end

function table_b()
    e = Dict(c.label => group_energy_twh(c) for c in CASES)
    rowspec = [
        ("Wind generation", "TWh/a equiv.", "Wind"),
        ("Solar PV generation", "TWh/a equiv.", "Solar PV"),
        ("Gas generation", "TWh/a equiv.", "Gas"),
        ("BESS discharge", "TWh/a equiv.", "BESS discharge"),
        ("BESS charge", "TWh/a equiv.", "BESS charge"),
    ]
    out = DF.DataFrame(metric=String[], unit=String[], BASE=Any[], var"gSCR-GERSH-1.0"=Any[], var"gSCR-GERSH-1.5"=Any[], delta_gSCR_1p5_vs_BASE=Any[], delta_gSCR_1p5_vs_BASE_percent=Any[])
    for (m,u,k) in rowspec
        b = e["BASE"][k]; g1 = e["gSCR-GERSH-1.0"][k]; g15 = e["gSCR-GERSH-1.5"][k]
        push!(out, (m,u,b,g1,g15,g15-b, abs(b)>1e-12 ? 100*(g15-b)/b : "n/a"))
    end
    push!(out, ("Curtailment", "TWh/a equiv.", missing, missing, missing, missing, "n/a"))
    return out
end

function figure_2_data()
    rows = DF.DataFrame(scenario_name=String[], panel=String[], technology_or_carrier=String[], value=Float64[], unit=String[])
    for case in CASES
        caps = group_capacity_gw(case)
        for k in ["Wind", "Solar PV", "Gas", "BESS-GFL", "BESS-GFM"]
            push!(rows, (case.label, "expansion_mix", k, caps[k], "GW"))
        end
        ens = group_energy_twh(case)
        for k in ["Wind", "Solar PV", "Gas", "BESS discharge"]
            push!(rows, (case.label, "energy_mix", k, ens[k], "TWh_per_year_equiv"))
        end
    end
    return rows
end

function plot_figures(strength_df, mix_df)
    Plots.gr()
    default(
        fontfamily="Computer Modern",
        linewidth=1.3,
        tickfontsize=7,
        guidefontsize=9,
        legendfontsize=7,
        framestyle=:box,
        grid=:y,
        gridalpha=0.22,
        dpi=300,
    )
    colors = [:blue, :orange, :green, :purple, :brown, :black]

    local_df = strength_df[strength_df.metric_type .== "local_rho_dec", :]
    global_df = strength_df[strength_df.metric_type .== "global_rho_gscr", :]
    p1a = plot(xlabel="", ylabel="Local decentralized ratio", legend=:outerright, size=(650, 520), margin=4Plots.mm)
    i = 1
    local_ymax_candidates = Float64[]
    for code in unique(local_df.region_code)
        sub = local_df[local_df.region_code .== code, :]
        vals = [ismissing(v) ? NaN : Float64(v) for v in sub.value]
        append!(local_ymax_candidates, filter(isfinite, vals))
        plot!(p1a, sub.hour, vals, label=code, color=colors[i], linewidth=1.3)
        i += 1
    end
    hline!(p1a, [1.0], label="", color=:black, linestyle=:dash, linewidth=1.2)
    annotate!(p1a, (5, 0.92, Plots.text("(a)", 9, :left)))
    y95 = isempty(local_ymax_candidates) ? 2.0 : quantile(local_ymax_candidates, 0.95)
    ytop = max(1.2, min(maximum(local_ymax_candidates), max(2.0, 1.15*y95)))
    ylims!(p1a, (0, ytop))

    p1b = plot(xlabel="Time [h]", ylabel="Global gSCR ratio", legend=:outerright, margin=4Plots.mm)
    for (j, case) in enumerate(CASES)
        sub = global_df[global_df.scenario_name .== case.label, :]
        plot!(p1b, sub.hour, Float64.(sub.value), label=case.label, color=colors[j], linewidth=1.3)
    end
    hline!(p1b, [1.0], label="", color=:black, linestyle=:dash, linewidth=1.2)
    annotate!(p1b, (5, 0.92, Plots.text("(b)", 9, :left)))
    fig1 = plot(p1a, p1b, layout=(2,1), size=(680, 620))
    savefig(fig1, normpath(OUTPUT_ROOT, "paper_figure_1_strength_timeseries.pdf"))
    savefig(fig1, normpath(OUTPUT_ROOT, "paper_figure_1_strength_timeseries.png"))

    scen = [c.label for c in CASES]
    exp_groups = ["Wind", "Solar PV", "Gas", "BESS-GFL", "BESS-GFM"]
    en_groups = ["Wind", "Solar PV", "Gas", "BESS discharge"]
    exp_mat = hcat([[only(mix_df[(mix_df.scenario_name .== s) .& (mix_df.panel .== "expansion_mix") .& (mix_df.technology_or_carrier .== g), :value]) for s in scen] for g in exp_groups]...)
    en_mat = hcat([[only(mix_df[(mix_df.scenario_name .== s) .& (mix_df.panel .== "energy_mix") .& (mix_df.technology_or_carrier .== g), :value]) for s in scen] for g in en_groups]...)
    x = collect(1:length(scen))
    function stacked_bar_panel(mat, groups, ylabel)
        p = plot(
            xticks=(x, scen),
            xrotation=15,
            ylabel=ylabel,
            legend=:outerright,
            margin=4Plots.mm,
            xlims=(0.45, length(scen) + 0.55),
        )
        bottom = zeros(length(scen))
        for (j, g) in enumerate(groups)
            vals = mat[:, j]
            bar!(
                p,
                x,
                vals,
                fillrange=bottom,
                label=g,
                color=colors[j],
                linecolor=:white,
                linewidth=0.4,
                bar_width=0.62,
            )
            bottom .+= vals
        end
        return p, bottom
    end
    p2a, exp_total = stacked_bar_panel(exp_mat, exp_groups, "Expansion [GW]")
    annotate!(p2a, (1, maximum(exp_total)*0.94, Plots.text("(a)", 9, :left)))
    p2b, en_total = stacked_bar_panel(en_mat, en_groups, "Annual-equivalent energy [TWh/a]")
    annotate!(p2b, (1, maximum(en_total)*0.94, Plots.text("(b)", 9, :left)))
    fig2 = plot(p2a, p2b, layout=(1,2), size=(720, 320), bottom_margin=8Plots.mm)
    savefig(fig2, normpath(OUTPUT_ROOT, "paper_figure_2_mix.pdf"))
    savefig(fig2, normpath(OUTPUT_ROOT, "paper_figure_2_mix.png"))

    return ytop
end

function write_summary(selected, local_plot_ymax, complete)
    files = [
        "paper_figure_1_strength_timeseries.pdf",
        "paper_figure_1_strength_timeseries.png",
        "paper_figure_2_mix.pdf",
        "paper_figure_2_mix.png",
        "paper_figure_1_timeseries_strength.csv",
        "paper_figure_1_selected_regions.csv",
        "paper_figure_2_mix.csv",
        "paper_table_A_system_design.csv",
        "paper_table_B_energy_mix.csv",
        "paper_table_C_global_gscr_validation.csv",
        "paper_result_artifact_summary.md",
    ]
    open(normpath(OUTPUT_ROOT, "paper_result_artifact_summary.md"), "w") do io
        println(io, "# Paper Result Artifact Summary")
        println(io)
        println(io, "- Input campaign directory used: `$(relpath(INPUT_ROOT, OUTPUT_ROOT))`")
        println(io, "- Output directory: `reports/paper_elec_s_37_campaign_336h`")
        println(io, "- Study period: 14.01--27.01")
        println(io, "- Horizon: 336 hourly snapshots")
        println(io, "- Annual operation scaling factor: 26")
        println(io, "- Common validation threshold alpha_paper: 1.5")
        println(io, "- No new optimization was run.")
        println(io, "- No HEUR-GFM run or proxy was used.")
        println(io, "- No geographic plot was generated.")
        println(io, "- All three cases complete: $(complete)")
        println(io)
        println(io, "## Scenario Mapping")
        for case in CASES
            println(io, "- $(case.label) = `$(case.run_dir)`, optimization_g_min=$(case.gmin)")
        end
        println(io)
        println(io, "## Selected Regions for Figure 1(a)")
        for r in eachrow(selected)
            println(io, "- $(r.legend_label): region_id=$(r.region_id), region_name=$(r.region_name), reason=$(r.selection_reason)")
        end
        println(io)
        println(io, "## Generated Files")
        for f in files
            println(io, "- `$f`")
        end
        println(io)
        println(io, "## Data Availability and Assumptions")
        println(io, "- Curtailment data available: false. Curtailment is reported as NA in Table B and omitted from Figure 2(b).")
        println(io, "- Local metric reconstruction successful: true, from `online_schedule.csv`.")
        println(io, "- sigma_i^G: no full per-bus sigma artifact is stored; the frozen study documents the gSCR baseline as a pure Laplacian with sigma_i^G=0 up to numerical tolerance, so zero was used for local ratio reconstruction.")
        println(io, "- Carrier aggregation: Wind = onwind + offwind-ac + offwind-dc; Solar PV = solar; Gas = CCGT; BESS-GFL = battery_gfl/BESS-GFL; BESS-GFM = battery_gfm/BESS-GFM.")
        println(io, "- Figure 2(a) uses the saved `investment_by_carrier.csv` capacity values, labelled as expansion [GW].")
        println(io, "- Figure 2(b) scales two-week dispatch by 26 and converts MWh to TWh/a equivalent.")
        ymax_str = @sprintf("%.4g", local_plot_ymax)
        println(io, "- Local-ratio plot y-axis upper limit: $(ymax_str); raw values are preserved in `paper_figure_1_timeseries_strength.csv`.")
        println(io, "- gSCR violation tolerance epsilon_gSCR: $(EPS_GSCR)")
        println(io, "- mu violation tolerance epsilon_mu: $(EPS_MU)")
        println(io)
        println(io, "## Missing Fields")
        println(io, "- Curtailment was not found in saved artifacts.")
        println(io, "- Geographic coordinates were not used because geographic maps are explicitly excluded.")
    end
end

function main()
    mkpath(OUTPUT_ROOT)
    complete = all(case -> termination_status(case) == "OPTIMAL", CASES)

    g15 = CASES[3]
    selected, agg, names, codes = select_regions(g15)
    strength = strength_timeseries(selected, agg, names, codes)
    mix = figure_2_data()
    tab_a = table_a()
    tab_b = table_b()
    tab_c = validation_table()

    write_csv(normpath(OUTPUT_ROOT, "paper_figure_1_selected_regions.csv"), selected)
    write_csv(normpath(OUTPUT_ROOT, "paper_figure_1_timeseries_strength.csv"), strength)
    write_csv(normpath(OUTPUT_ROOT, "paper_figure_2_mix.csv"), mix)
    write_csv(normpath(OUTPUT_ROOT, "paper_table_A_system_design.csv"), tab_a)
    write_csv(normpath(OUTPUT_ROOT, "paper_table_B_energy_mix.csv"), tab_b)
    write_csv(normpath(OUTPUT_ROOT, "paper_table_C_global_gscr_validation.csv"), tab_c)

    local_plot_ymax = plot_figures(strength, mix)
    write_summary(selected, local_plot_ymax, complete)

    println("input campaign directory: ", INPUT_ROOT)
    println("study period: 14.01--27.01")
    println("cases used: ", join([c.label for c in CASES], ", "))
    println("all runs complete: ", complete)
    println("generated plot files: paper_figure_1_strength_timeseries.pdf/png, paper_figure_2_mix.pdf/png")
    println("generated CSV files: paper_figure_1_timeseries_strength.csv, paper_figure_1_selected_regions.csv, paper_figure_2_mix.csv, paper_table_A_system_design.csv, paper_table_B_energy_mix.csv, paper_table_C_global_gscr_validation.csv")
    println("selected regions: ", join(["$(r.legend_label) ($(r.selection_reason))" for r in eachrow(selected)], ", "))
    println("curtailment available: false")
    println("local metric reconstruction successful: true")
    println("Table C alpha_paper: ", ALPHA_PAPER)
    println("missing/assumed fields: curtailment unavailable; sigma_i^G assumed zero from frozen pure-Laplacian study documentation")
end

main()
