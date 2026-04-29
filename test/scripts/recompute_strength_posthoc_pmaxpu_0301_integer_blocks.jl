import CSV
import DataFrames
import JSON
import PowerModels
using LinearAlgebra
using Statistics
using Printf
using Plots

const DF = DataFrames

const ALPHA_PAPER = 1.5
const EPS_GSCR = 1e-6
const EPS_MU = 1e-7
const EPS_P = 1e-9

const CASE_PATH = raw"D:\Projekte\Code\pypsatomatpowerx_clean_battery_policy\data\flexplan_block_gscr\elec_s_37_2weeks_from_0301\case.json"
const INPUT_ROOT = normpath(@__DIR__, "..", "..", "reports", "paper_elec_s_37_campaign_336h_integer_blocks_v2")
const OUTPUT_ROOT = normpath(@__DIR__, "..", "..", "reports", "paper_elec_s_37_results_ready_336h_0301_1601_integer_blocks")

const CASES = [
    (label="BASE", run_dir="H_336h_gmin_0p0_integer_blocks", color=RGB(0.0, 0.0, 0.0)),
    (label="gSCR-GERSH-1.0", run_dir="H_336h_gmin_1p0_integer_blocks", color=RGB(0.0, 0.45, 0.70)),
    (label="gSCR-GERSH-1.5", run_dir="H_336h_gmin_1p5_integer_blocks", color=RGB(0.84, 0.37, 0.0)),
]

function _fmt(x; digits=3)
    if x isa AbstractString
        return x
    elseif !isfinite(x)
        return "--"
    elseif abs(x) > 0 && (abs(x) < 1e-3 || abs(x) >= 1e4)
        return digits == 3 ? @sprintf("%.3e", x) : @sprintf("%.2e", x)
    else
        return digits == 3 ? @sprintf("%.3g", x) : @sprintf("%.2g", x)
    end
end

function _basic_susceptance_data(nw::Dict{String,Any})
    bus = Dict{String,Any}()
    for (bus_id, bus_data) in nw["bus"]
        b = deepcopy(bus_data)
        b["index"] = get(b, "index", parse(Int, bus_id))
        b["bus_i"] = get(b, "bus_i", b["index"])
        b["bus_type"] = get(b, "bus_type", 1)
        b["vm"] = get(b, "vm", 1.0)
        b["va"] = get(b, "va", 0.0)
        b["vmin"] = get(b, "vmin", 0.9)
        b["vmax"] = get(b, "vmax", 1.1)
        b["base_kv"] = get(b, "base_kv", 1.0)
        b["zone"] = get(b, "zone", 1)
        bus[string(bus_id)] = b
    end

    branch = Dict{String,Any}()
    for (branch_id, branch_data) in nw["branch"]
        br = deepcopy(branch_data)
        br["index"] = get(br, "index", parse(Int, branch_id))
        br["br_status"] = get(br, "br_status", 1)
        br["br_r"] = get(br, "br_r", 0.0)
        br["br_x"] = get(br, "br_x", 0.0)
        br["g_fr"] = get(br, "g_fr", 0.0)
        br["g_to"] = get(br, "g_to", 0.0)
        br["b_fr"] = get(br, "b_fr", 0.0)
        br["b_to"] = get(br, "b_to", 0.0)
        br["tap"] = get(br, "tap", 1.0)
        br["shift"] = get(br, "shift", 0.0)
        br["rate_a"] = get(br, "rate_a", 1.0e6)
        br["angmin"] = get(br, "angmin", -Inf)
        br["angmax"] = get(br, "angmax", Inf)
        br["transformer"] = get(br, "transformer", false)
        branch[string(branch_id)] = br
    end

    return Dict{String,Any}(
        "basic_network" => true,
        "bus" => bus,
        "branch" => branch,
        "dcline" => Dict{String,Any}(),
        "switch" => Dict{String,Any}(),
    )
end

function _b0_matrix(first_nw::Dict{String,Any})
    buses = sort(parse.(Int, collect(keys(first_nw["bus"]))))
    basic = _basic_susceptance_data(first_nw)
    b_pm = PowerModels.calc_basic_susceptance_matrix(basic)
    idx_to_bus = PowerModels.calc_susceptance_matrix(basic).idx_to_bus
    idx = Dict(b => i for (i, b) in enumerate(buses))
    b0 = zeros(length(buses), length(buses))
    for r in axes(b_pm, 1), c in axes(b_pm, 2)
        rb = idx_to_bus[r]
        cb = idx_to_bus[c]
        if haskey(idx, rb) && haskey(idx, cb)
            b0[idx[rb], idx[cb]] = -b_pm[r, c]
        end
    end
    sigma = Dict{Int,Float64}()
    for b in buses
        i = idx[b]
        sigma[b] = b0[i, i] - sum(abs(b0[i, j]) for j in axes(b0, 2) if j != i)
    end
    return buses, idx, b0, sigma
end

function _pmax_pu(data::Dict{String,Any}, snapshot::Int, table::AbstractString, id)
    nw = data["nw"][string(snapshot)]
    tbl = get(nw, table, Dict{String,Any}())
    d = tbl[string(Int(round(Float64(id))))]
    return Float64(get(d, "p_block_max_pu", get(d, "p_max_pu", 1.0)))
end

function _recompute_case(case, data, buses, idx, b0, sigma)
    path = normpath(INPUT_ROOT, case.run_dir, "online_schedule.csv")
    isfile(path) || error("Missing online schedule: $path")
    schedule = CSV.read(path, DF.DataFrame; normalizenames=false)
    grouped = DF.groupby(schedule, "snapshot")
    ts_rows = Dict{String,Any}[]
    local_rows = Dict{String,Any}[]

    for sdf in grouped
        snap = Int(round(Float64(first(sdf[!, "snapshot"]))))
        B = copy(b0)
        Sdiag = zeros(length(buses))
        gfm = Dict(b => 0.0 for b in buses)
        gfl = Dict(b => 0.0 for b in buses)

        for r in eachrow(sdf)
            b = Int(round(Float64(r["bus"])))
            haskey(idx, b) || continue
            pu = _pmax_pu(data, snap, string(r["component_table"]), r["component_id"])
            na = Float64(r["na_block"])
            if string(r["type"]) == "gfm"
                contribution = Float64(r["b_block"]) * na * pu
                gfm[b] += contribution
            elseif string(r["type"]) == "gfl"
                exposure = Float64(r["p_block_max"]) * na * pu
                gfl[b] += exposure
            end
        end

        for b in buses
            B[idx[b], idx[b]] += gfm[b]
            Sdiag[idx[b]] = gfl[b]
        end

        M = Symmetric(B - ALPHA_PAPER * Diagonal(Sdiag))
        mu = minimum(eigvals(M))
        active = findall(x -> x > EPS_P, Sdiag)
        gscr = Inf
        if !isempty(active)
            vals = eigvals(Symmetric(B[active, active]), Symmetric(Matrix(Diagonal(Sdiag[active]))))
            finite_vals = [real(v) for v in vals if isfinite(real(v))]
            gscr = isempty(finite_vals) ? Inf : minimum(finite_vals)
        end

        util_vals = Float64[]
        total_deficit = 0.0
        min_kappa = Inf
        for b in buses
            denom = sigma[b] + gfm[b]
            kappa = denom - ALPHA_PAPER * gfl[b]
            min_kappa = min(min_kappa, kappa)
            total_deficit += max(0.0, -kappa)
            if gfl[b] > EPS_P && denom > EPS_P
                util = ALPHA_PAPER * gfl[b] / denom
                rho = denom / (ALPHA_PAPER * gfl[b])
                push!(util_vals, util)
                push!(local_rows, Dict(
                    "t" => snap,
                    "hour" => snap,
                    "scenario_name" => case.label,
                    "bus" => b,
                    "rho_local_dec_pmaxpu" => rho,
                    "u_local_dec_pmaxpu" => util,
                    "kappa_alpha_1p5_pmaxpu" => kappa,
                    "GFL_exposure_pmaxpu" => gfl[b],
                    "GFM_strength_pmaxpu" => gfm[b],
                    "sigma_i_G" => sigma[b],
                    "alpha_paper" => ALPHA_PAPER,
                ))
            end
        end

        push!(ts_rows, Dict(
            "t" => snap,
            "hour" => snap,
            "scenario_name" => case.label,
            "gSCR_t" => gscr,
            "normalized_global_gSCR" => gscr / ALPHA_PAPER,
            "mu_t_alpha_1p5" => mu,
            "max_local_utilization_alpha_1p5" => isempty(util_vals) ? NaN : maximum(util_vals),
            "total_local_deficit_alpha_1p5" => total_deficit,
            "total_GFL_exposure_pmaxpu" => sum(values(gfl); init=0.0),
            "total_GFM_strength_pmaxpu" => sum(values(gfm); init=0.0),
            "alpha_paper" => ALPHA_PAPER,
        ))
    end
    sort!(ts_rows, by=r -> r["t"])
    sort!(local_rows, by=r -> (r["t"], r["bus"]))
    return ts_rows, local_rows
end

function _table_c(all_ts)
    rows = Dict{String,Any}[]
    metrics = [
        ("min_global_gSCR_t", "p.u."),
        ("global_gSCR_violation_snapshots_percent_alpha_1p5", "%"),
        ("min_mu_t_alpha_1p5", "p.u."),
        ("mu_violation_snapshots_percent_alpha_1p5", "%"),
        ("max_local_utilization_alpha_1p5", "p.u."),
        ("total_local_deficit_alpha_1p5", "MW-equivalent"),
    ]
    bycase = Dict(case.label => [r for r in all_ts if r["scenario_name"] == case.label] for case in CASES)
    for (metric, unit) in metrics
        out = Dict{String,Any}("metric" => metric, "unit" => unit)
        for case in CASES
            ts = bycase[case.label]
            val = if metric == "min_global_gSCR_t"
                minimum(r["gSCR_t"] for r in ts)
            elseif metric == "global_gSCR_violation_snapshots_percent_alpha_1p5"
                100 * count(r -> r["gSCR_t"] < ALPHA_PAPER - EPS_GSCR, ts) / length(ts)
            elseif metric == "min_mu_t_alpha_1p5"
                minimum(r["mu_t_alpha_1p5"] for r in ts)
            elseif metric == "mu_violation_snapshots_percent_alpha_1p5"
                100 * count(r -> r["mu_t_alpha_1p5"] < -EPS_MU, ts) / length(ts)
            elseif metric == "max_local_utilization_alpha_1p5"
                maximum(r["max_local_utilization_alpha_1p5"] for r in ts if isfinite(r["max_local_utilization_alpha_1p5"]))
            else
                sum(r["total_local_deficit_alpha_1p5"] for r in ts)
            end
            out[case.label] = val
        end
        push!(rows, out)
    end
    df = DF.DataFrame(rows)
    return df[:, ["metric", "unit", "BASE", "gSCR-GERSH-1.0", "gSCR-GERSH-1.5"]]
end

function _write_latex_table_c(table::DF.DataFrame)
    d = Dict(row["metric"] => row for row in eachrow(table))
    scen = ["BASE", "gSCR-GERSH-1.0", "gSCR-GERSH-1.5"]
    getv(metric) = [Float64(d[metric][s]) for s in scen]
    gscr = [@sprintf("%.3f", x) for x in getv("min_global_gSCR_t")]
    viol = [@sprintf("%.1f", x) for x in getv("global_gSCR_violation_snapshots_percent_alpha_1p5")]
    mu = [_fmt(x; digits=3) for x in getv("min_mu_t_alpha_1p5")]
    muviol = [@sprintf("%.1f", x) for x in getv("mu_violation_snapshots_percent_alpha_1p5")]
    util = [@sprintf("%.2f", x) for x in getv("max_local_utilization_alpha_1p5")]
    deficit = [_fmt(x; digits=3) for x in getv("total_local_deficit_alpha_1p5")]
    content = """
\\begin{table}[!t]
\\centering
\\caption{Post-Hoc Global gSCR Validation at \\(\\alpha=1.5\\)}
\\label{tab:strength_validation}
\\renewcommand{\\arraystretch}{1.08}
\\begin{tabular}{lrrr}
\\toprule
Metric & BASE & gSCR-1.0 & gSCR-1.5 \\\\
\\midrule
\\(\\min_t \\mathrm{gSCR}_t\\)                  & $(gscr[1]) & $(gscr[2]) & $(gscr[3]) \\\\
Snapshots with \\(\\mathrm{gSCR}_t<1.5\\) (\\%) & $(viol[1]) & $(viol[2]) & $(viol[3]) \\\\
\\(\\min_t \\mu_t^{1.5}\\)                      & $(mu[1]) & $(mu[2]) & $(mu[3]) \\\\
Snapshots with \\(\\mu_t^{1.5}<0\\) (\\%)       & $(muviol[1]) & $(muviol[2]) & $(muviol[3]) \\\\
\\(\\max_{i,t} u_{i,t}^{1.5}\\)                & $(util[1]) & $(util[2]) & $(util[3]) \\\\
Total local deficit \\(D^{\\mathrm{def}}\\)    & $(deficit[1]) & $(deficit[2]) & $(deficit[3]) \\\\
\\bottomrule
\\end{tabular}
\\end{table}
"""
    write(normpath(OUTPUT_ROOT, "latex_table_C_strength_validation_pmaxpu.tex"), content)
end

function _plot_global(all_ts)
    df = DF.DataFrame(all_ts)
    CSV.write(normpath(OUTPUT_ROOT, "paper_figure_global_gscr_timeseries_pmaxpu.csv"), df)
    plt = plot(size=(560, 315), dpi=300, fontfamily="Computer Modern", framestyle=:box,
        legend=:bottomright, legendfontsize=7, tickfontsize=8, guidefontsize=9,
        margin=4Plots.mm, grid=true, gridalpha=0.18)
    for case in CASES
        sub = df[df.scenario_name .== case.label, :]
        plot!(plt, sub.hour, sub.normalized_global_gSCR, label=case.label, color=case.color, linewidth=1.6)
    end
    hline!(plt, [1.0], label="", color=:black, linestyle=:dash, linewidth=1.2, alpha=0.75)
    xlabel!(plt, "Time [h]")
    ylabel!(plt, "Normalized global gSCR")
    xlims!(plt, (1, 336))
    ylims!(plt, (0, 1.12))
    savefig(plt, normpath(OUTPUT_ROOT, "paper_figure_global_gscr_timeseries_pmaxpu.pdf"))
    savefig(plt, normpath(OUTPUT_ROOT, "paper_figure_global_gscr_timeseries_pmaxpu.png"))
end

function main()
    mkpath(OUTPUT_ROOT)
    data = JSON.parsefile(CASE_PATH)
    first_nw = data["nw"]["1"]
    buses, idx, b0, sigma = _b0_matrix(first_nw)
    all_ts = Dict{String,Any}[]
    all_local = Dict{String,Any}[]
    for case in CASES
        case_result = _recompute_case(case, data, buses, idx, b0, sigma)
        ts = case_result[1]
        local_rows = case_result[2]
        append!(all_ts, ts)
        append!(all_local, local_rows)
    end
    table = _table_c(all_ts)
    CSV.write(normpath(OUTPUT_ROOT, "paper_table_C_global_gscr_validation_pmaxpu.csv"), table)
    CSV.write(normpath(OUTPUT_ROOT, "paper_strength_timeseries_pmaxpu_adjusted.csv"), DF.DataFrame(all_ts))
    CSV.write(normpath(OUTPUT_ROOT, "paper_local_gscr_timeseries_pmaxpu_adjusted.csv"), DF.DataFrame(all_local))
    _write_latex_table_c(table)
    _plot_global(all_ts)
    open(normpath(OUTPUT_ROOT, "pmaxpu_strength_recompute_note.md"), "w") do io
        println(io, "# p_max_pu-adjusted strength recomputation")
        println(io)
        println(io, "- Recomputed post-hoc strength metrics from `online_schedule.csv` and `case.json` as a second evaluation option.")
        println(io, "- Original non-availability-adjusted strength outputs were not overwritten.")
        println(io, "- GFL exposure uses `p_block_max * na_block * p_block_max_pu`.")
        println(io, "- GFM strength uses `b_block * na_block * p_block_max_pu`.")
        println(io, "- `p_block_max_pu` falls back to `p_max_pu`, then `1.0` if unavailable.")
        println(io, "- Eigenvalue metric remains `lambda_min^fin(B_t,S_t)` with `B_t = B0 + diag(Delta b_t)` and `S_t = diag(P_GFL_t)`.")
        println(io, "- Common paper threshold: alpha = $(ALPHA_PAPER).")
    end
    println("wrote second-option p_max_pu-adjusted strength artifacts in: ", OUTPUT_ROOT)
end

main()
