import CSV
import DataFrames
using Plots

const DF = DataFrames

const ALPHA_PAPER = 1.5
const INPUT_ROOT = normpath(@__DIR__, "..", "..", "reports", "paper_elec_s_37_campaign_336h_integer_blocks_v2")
const OUTPUT_ROOT = normpath(@__DIR__, "..", "..", "reports", "paper_elec_s_37_results_ready_336h_0301_1601_integer_blocks")

const CASES = [
    (label="BASE", run_dir="H_336h_gmin_0p0_integer_blocks", color=RGB(0.0, 0.0, 0.0)),
    (label="gSCR-GERSH-1.0", run_dir="H_336h_gmin_1p0_integer_blocks", color=RGB(0.0, 0.45, 0.70)),
    (label="gSCR-GERSH-1.5", run_dir="H_336h_gmin_1p5_integer_blocks", color=RGB(0.84, 0.37, 0.0)),
]

function require_file(path::AbstractString)
    isfile(path) || error("Missing required file: $path")
    return path
end

function load_global_gscr(case)
    path = require_file(normpath(INPUT_ROOT, case.run_dir, "posthoc_strength_timeseries.csv"))
    df = CSV.read(path, DF.DataFrame; normalizenames=false)
    "snapshot" in names(df) || error("Missing snapshot column in $path")
    "gSCR_t" in names(df) || error("Missing gSCR_t column in $path")
    return DF.DataFrame(
        t = Int.(round.(Float64.(df[!, "snapshot"]))),
        hour = Int.(round.(Float64.(df[!, "snapshot"]))),
        scenario_name = fill(case.label, DF.nrow(df)),
        gSCR_t = Float64.(df[!, "gSCR_t"]),
        normalized_global_gSCR = Float64.(df[!, "gSCR_t"]) ./ ALPHA_PAPER,
        alpha_paper = fill(ALPHA_PAPER, DF.nrow(df)),
    )
end

function main()
    mkpath(OUTPUT_ROOT)
    rows = DF.DataFrame[]
    plt = plot(
        size=(560, 315),
        dpi=300,
        fontfamily="Computer Modern",
        framestyle=:box,
        legend=:bottomright,
        legendfontsize=7,
        tickfontsize=8,
        guidefontsize=9,
        margin=4Plots.mm,
        grid=true,
        gridalpha=0.18,
        minorgrid=false,
    )

    for case in CASES
        df = load_global_gscr(case)
        push!(rows, df)
        plot!(
            plt,
            df.hour,
            df.normalized_global_gSCR,
            label=case.label,
            color=case.color,
            linewidth=1.6,
        )
    end

    hline!(plt, [1.0], label="", color=:black, linestyle=:dash, linewidth=1.2, alpha=0.75)
    xlabel!(plt, "Time [h]")
    ylabel!(plt, "Normalized global gSCR")
    xlims!(plt, (1, 336))
    ylims!(plt, (0, 1.12))

    out_df = vcat(rows...)
    CSV.write(normpath(OUTPUT_ROOT, "paper_figure_global_gscr_timeseries.csv"), out_df)
    savefig(plt, normpath(OUTPUT_ROOT, "paper_figure_global_gscr_timeseries.pdf"))
    savefig(plt, normpath(OUTPUT_ROOT, "paper_figure_global_gscr_timeseries.png"))

    println("generated: ", normpath(OUTPUT_ROOT, "paper_figure_global_gscr_timeseries.pdf"))
    println("generated: ", normpath(OUTPUT_ROOT, "paper_figure_global_gscr_timeseries.png"))
    println("generated: ", normpath(OUTPUT_ROOT, "paper_figure_global_gscr_timeseries.csv"))
end

main()
