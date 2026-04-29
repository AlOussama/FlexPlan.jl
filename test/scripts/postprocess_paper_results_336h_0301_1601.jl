using CSV
using DataFrames
using JSON
using Statistics
using Printf

const ROOT = normpath(@__DIR__, "..", "..")
const IN_DIR = normpath(ROOT, "reports", "paper_elec_s_37_campaign_336h")
const OUT_DIR = normpath(ROOT, "reports", "paper_elec_s_37_results_ready_336h_0301_1601")
const TOL = 1e-7
const ALPHA = 1.5

const SCENARIOS = [
    ("BASE", "H_336h_gmin_0p0", 0.0),
    ("gSCR-1", "H_336h_gmin_1p0", 1.0),
    ("gSCR-GERSH", "H_336h_gmin_1p5", 1.5),
]

mkpath(OUT_DIR)

function read_json(path::String)
    isfile(path) || error("Missing required file: $path")
    return JSON.parsefile(path)
end

function read_csv(path::String)
    isfile(path) || error("Missing required file: $path")
    return CSV.read(path, DataFrame)
end

function fmt(x; digits=2)
    if x === nothing || (x isa AbstractFloat && !isfinite(x))
        return "n/a"
    end
    return @sprintf("%.*f", digits, Float64(x))
end

function fmt_sci(x)
    x = Float64(x)
    if abs(x) < 1e-6
        return @sprintf("%.2e", x)
    end
    return fmt(x; digits=2)
end

function tex_escape(s)
    replace(String(s), "_" => "\\_", "%" => "\\%")
end

function scenario_metrics(label, dir, gmin)
    run_dir = normpath(IN_DIR, dir)
    cost = read_json(normpath(run_dir, "cost_summary.json"))
    cap = read_json(normpath(run_dir, "capacity_summary.json"))
    solver = read_json(normpath(run_dir, "solver_summary.json"))
    post = read_json(normpath(run_dir, "posthoc_strength_summary.json"))
    ts = read_csv(normpath(run_dir, "posthoc_strength_timeseries.csv"))
    node = read_csv(normpath(run_dir, "node_binding_frequency.csv"))

    mu_col = hasproperty(ts, :min_mu_t_alpha_1p5) ? :min_mu_t_alpha_1p5 : :mu_t
    mus = Float64.(ts[!, mu_col])
    gscrs = Float64.(ts.gSCR_t)
    rels = Float64.(ts.relative_margin_rG)
    min_kappa = Float64.(ts.min_kappa)
    med_kappa = hasproperty(ts, :median_kappa) ? Float64.(ts.median_kappa) : fill(NaN, nrow(ts))
    viol_count = count(<(-TOL), mus)
    binding_nodes = count(x -> Float64(x) > 0.0, node.beta_i)
    sorted_nodes = sort(node, :beta_i, rev=true)
    top5 = join(String.(sorted_nodes.region_name[1:min(5, nrow(sorted_nodes))]), "; ")

    return Dict{String,Any}(
        "label" => label,
        "dir" => dir,
        "gmin" => gmin,
        "run_dir" => run_dir,
        "status" => solver["status"],
        "cost_BEUR" => Float64(cost["total_annual_system_cost_BEUR_per_year"]),
        "BESS_GFM_GW" => Float64(cap["installed_BESS_GFM_GW"]),
        "BESS_GFL_GW" => Float64(cap["installed_BESS_GFL_GW"]),
        "WindPV_GW" => Float64(cap["installed_RES_GW"]),
        "Wind_GW" => Float64(cap["installed_wind_GW"]),
        "Solar_GW" => Float64(get(cap, "installed_PV_GW", get(cap, "installed_solar_GW", 0.0))),
        "Gas_GW" => Float64(cap["installed_CCGT_GW"]),
        "OCGT_GW" => Float64(get(cap, "installed_OCGT_GW", 0.0)),
        "solve_min" => Float64(solver["solve_time_sec"]) / 60.0,
        "min_mu" => minimum(mus),
        "min_gscr" => minimum(gscrs),
        "viol_count" => viol_count,
        "viol_percent" => 100.0 * viol_count / max(1, nrow(ts)),
        "min_rel" => minimum(rels),
        "median_rel" => median(rels),
        "mean_rel" => mean(rels),
        "max_rel" => maximum(rels),
        "min_local_kappa" => minimum(min_kappa),
        "median_local_kappa" => median(skipmissing(med_kappa)),
        "mean_local_kappa" => mean(min_kappa),
        "binding_nodes" => binding_nodes,
        "top5" => top5,
        "ts" => ts,
        "node" => node,
    )
end

metrics = Dict(m["label"] => m for m in (scenario_metrics(s...) for s in SCENARIOS))
base = metrics["BASE"]
gscr1 = metrics["gSCR-1"]
gscr = metrics["gSCR-GERSH"]

function delta_text(v, b; digits=2)
    d = Float64(v) - Float64(b)
    if abs(Float64(b)) <= 1e-12
        return "$(fmt(d; digits=digits)) (n/a)"
    end
    return "$(fmt(d; digits=digits)) ($(fmt(100d/Float64(b); digits=1))%)"
end

main_rows = [
    ("Cost (B€/a)", base["cost_BEUR"], gscr["cost_BEUR"], delta_text(gscr["cost_BEUR"], base["cost_BEUR"])),
    ("BESS-GFM (GW)", base["BESS_GFM_GW"], gscr["BESS_GFM_GW"], delta_text(gscr["BESS_GFM_GW"], base["BESS_GFM_GW"])),
    ("BESS-GFL (GW)", base["BESS_GFL_GW"], gscr["BESS_GFL_GW"], delta_text(gscr["BESS_GFL_GW"], base["BESS_GFL_GW"]; digits=3)),
    ("Wind+PV (GW)", base["WindPV_GW"], gscr["WindPV_GW"], delta_text(gscr["WindPV_GW"], base["WindPV_GW"]; digits=3)),
    ("Gas (GW)", base["Gas_GW"], gscr["Gas_GW"], delta_text(gscr["Gas_GW"], base["Gas_GW"])),
    ("Min. mu_t", base["min_mu"], gscr["min_mu"], "--"),
    ("Violating snapshots (%)", base["viol_percent"], gscr["viol_percent"], "--"),
    ("Min. gSCR", base["min_gscr"], gscr["min_gscr"], "--"),
    ("Solve time (min)", base["solve_min"], gscr["solve_min"], "--"),
]

CSV.write(normpath(OUT_DIR, "table_results_base_vs_gscr.csv"), DataFrame(
    row=[r[1] for r in main_rows],
    BASE=[r[2] for r in main_rows],
    gSCR_GERSH=[r[3] for r in main_rows],
    Delta_vs_BASE=[r[4] for r in main_rows],
))

function value_for_table(rowname, x)
    if occursin("mu", rowname)
        return fmt_sci(x)
    elseif occursin("gSCR", rowname)
        return fmt(x; digits=3)
    elseif occursin("%", rowname)
        return fmt(x; digits=1)
    elseif occursin("BESS-GFL", rowname) || occursin("Wind+PV", rowname)
        return fmt(x; digits=3)
    else
        return fmt(x; digits=2)
    end
end

open(normpath(OUT_DIR, "table_results_base_vs_gscr.tex"), "w") do io
    println(io, "\\begin{table}[!t]")
    println(io, "\\centering")
    println(io, "\\caption{Capacity Expansion and gSCR Post-Hoc Validation}")
    println(io, "\\label{tab:results}")
    println(io, "\\renewcommand{\\arraystretch}{1.08}")
    println(io, "\\begin{tabular}{lrrr}")
    println(io, "\\toprule")
    println(io, " & BASE & gSCR-GERSH & \$\\Delta\$ vs.\\ BASE \\\\")
    println(io, "\\midrule")
    for (name, b, g, d) in main_rows
        println(io, tex_escape(name), " & ", value_for_table(name, b), " & ", value_for_table(name, g), " & ", tex_escape(d), " \\\\")
    end
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
    println(io, "\\begin{minipage}{0.95\\columnwidth}")
    println(io, "\\footnotesize Percent changes are reported as n/a where the BASE value is zero.")
    println(io, "\\end{minipage}")
    println(io, "\\end{table}")
end

sens_rows = [
    ("Cost (B€/a)", base["cost_BEUR"], gscr1["cost_BEUR"], gscr["cost_BEUR"]),
    ("BESS-GFM (GW)", base["BESS_GFM_GW"], gscr1["BESS_GFM_GW"], gscr["BESS_GFM_GW"]),
    ("BESS-GFL (GW)", base["BESS_GFL_GW"], gscr1["BESS_GFL_GW"], gscr["BESS_GFL_GW"]),
    ("Wind+PV (GW)", base["WindPV_GW"], gscr1["WindPV_GW"], gscr["WindPV_GW"]),
    ("Gas (GW)", base["Gas_GW"], gscr1["Gas_GW"], gscr["Gas_GW"]),
    ("Min. mu_t", base["min_mu"], gscr1["min_mu"], gscr["min_mu"]),
    ("Violating snapshots (%)", base["viol_percent"], gscr1["viol_percent"], gscr["viol_percent"]),
    ("Min. gSCR", base["min_gscr"], gscr1["min_gscr"], gscr["min_gscr"]),
    ("Solve time (min)", base["solve_min"], gscr1["solve_min"], gscr["solve_min"]),
]
CSV.write(normpath(OUT_DIR, "table_results_with_sensitivity.csv"), DataFrame(
    row=[r[1] for r in sens_rows], BASE=[r[2] for r in sens_rows], gSCR_1=[r[3] for r in sens_rows], gSCR_GERSH=[r[4] for r in sens_rows]
))
open(normpath(OUT_DIR, "table_results_with_sensitivity.tex"), "w") do io
    println(io, "\\begin{table}[!t]")
    println(io, "\\centering")
    println(io, "\\caption{gSCR Threshold Sensitivity}")
    println(io, "\\label{tab:gscr_sensitivity}")
    println(io, "\\renewcommand{\\arraystretch}{1.08}")
    println(io, "\\begin{tabular}{lrrr}")
    println(io, "\\toprule")
    println(io, " & BASE & gSCR-1 & gSCR-GERSH \\\\")
    println(io, "\\midrule")
    for (name, b, s1, g) in sens_rows
        println(io, tex_escape(name), " & ", value_for_table(name, b), " & ", value_for_table(name, s1), " & ", value_for_table(name, g), " \\\\")
    end
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
    println(io, "\\end{table}")
end

node = copy(gscr["node"])
sort!(node, :beta_i, rev=true)
node.rank_beta = 1:nrow(node)
node.top5_flag = node.rank_beta .<= 5
node.latitude = fill("", nrow(node))
node.longitude = fill("", nrow(node))
binding_data = DataFrame(
    scenario=fill("gSCR-GERSH", nrow(node)),
    bus=node.bus,
    region_name=node.region_name,
    beta_i=node.beta_i,
    gfm_bess_capacity_GW=node.gfm_bess_capacity_GW,
    latitude=node.latitude,
    longitude=node.longitude,
    top5_flag=node.top5_flag,
    rank_beta=node.rank_beta,
)
CSV.write(normpath(OUT_DIR, "figure_binding_data.csv"), binding_data)
CSV.write(normpath(OUT_DIR, "per_region_binding_summary.csv"), select(node, [:bus, :region_name, :beta_i, :gfm_bess_capacity_GW, :min_kappa, :mean_kappa, :p05_kappa, :rank_beta]))

margin_rows = DataFrame()
for label in ["BASE", "gSCR-GERSH", "gSCR-1"]
    m = metrics[label]
    ts = m["ts"]
    mu_col = hasproperty(ts, :min_mu_t_alpha_1p5) ? :min_mu_t_alpha_1p5 : :mu_t
    append!(margin_rows, DataFrame(
        scenario=fill(label, nrow(ts)),
        t=ts.snapshot,
        global_margin_gSCR_minus_alpha=Float64.(ts.gSCR_t) .- ALPHA,
        relative_margin_rG=Float64.(ts.relative_margin_rG),
        mu_t=Float64.(ts[!, mu_col]),
        min_local_kappa=Float64.(ts.min_kappa),
        median_local_kappa=hasproperty(ts, :median_kappa) ? Float64.(ts.median_kappa) : fill(NaN, nrow(ts)),
        gershgorin_conservatism_gap=hasproperty(ts, :gershgorin_conservatism_gap) ? Float64.(ts.gershgorin_conservatism_gap) : fill(NaN, nrow(ts)),
    ))
end
CSV.write(normpath(OUT_DIR, "figure_margin_data.csv"), margin_rows)

function conserv_row(label)
    m = metrics[label]
    rows = margin_rows[margin_rows.scenario .== label, :]
    return (
        scenario=label,
        min_global_margin=minimum(rows.global_margin_gSCR_minus_alpha),
        median_global_margin=median(rows.global_margin_gSCR_minus_alpha),
        mean_global_margin=mean(rows.global_margin_gSCR_minus_alpha),
        max_global_margin=maximum(rows.global_margin_gSCR_minus_alpha),
        min_relative_margin=m["min_rel"],
        median_relative_margin=m["median_rel"],
        mean_relative_margin=m["mean_rel"],
        violating_snapshot_percent=m["viol_percent"],
        min_local_kappa=minimum(rows.min_local_kappa),
        median_local_kappa=median(rows.median_local_kappa),
        mean_local_kappa=mean(rows.min_local_kappa),
    )
end
CSV.write(normpath(OUT_DIR, "gscr_conservatism_summary.csv"), DataFrame([conserv_row("BASE"), conserv_row("gSCR-GERSH"), conserv_row("gSCR-1")]))

function posthoc_row(label)
    m = metrics[label]
    return (
        scenario=label,
        min_mu_t=m["min_mu"],
        min_gSCR_t=m["min_gscr"],
        violating_snapshot_count=m["viol_count"],
        violating_snapshot_percent=m["viol_percent"],
        min_relative_margin_rG=m["min_rel"],
        median_relative_margin_rG=m["median_rel"],
        mean_relative_margin_rG=m["mean_rel"],
        max_relative_margin_rG=m["max_rel"],
        min_local_kappa=m["min_local_kappa"],
        median_local_kappa=m["median_local_kappa"],
        mean_local_kappa=m["mean_local_kappa"],
        number_of_binding_nodes=m["binding_nodes"],
        top_5_binding_regions=m["top5"],
    )
end
CSV.write(normpath(OUT_DIR, "posthoc_validation_summary.csv"), DataFrame([posthoc_row("BASE"), posthoc_row("gSCR-GERSH"), posthoc_row("gSCR-1")]))

CSV.write(normpath(OUT_DIR, "appendix_sensitivity_gmin1.csv"), DataFrame([posthoc_row("gSCR-1")]))
open(normpath(OUT_DIR, "appendix_sensitivity_gmin1.tex"), "w") do io
    println(io, "\\begin{table}[!t]\\centering")
    println(io, "\\caption{Intermediate gSCR Sensitivity Case}")
    println(io, "\\begin{tabular}{lr}\\toprule Metric & gSCR-1 \\\\ \\midrule")
    for (name, _, val, _) in sens_rows
        println(io, tex_escape(name), " & ", value_for_table(name, val), " \\\\")
    end
    println(io, "\\bottomrule\\end{tabular}\\end{table}")
end

function pdf_escape(s)
    replace(String(s), "\\" => "\\\\", "(" => "\\(", ")" => "\\)")
end

function write_simple_pdf(path, width, height, stream)
    objects = String[]
    push!(objects, "<< /Type /Catalog /Pages 2 0 R >>")
    push!(objects, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    push!(objects, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>")
    push!(objects, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    push!(objects, "<< /Length $(length(stream)) >>\nstream\n$(stream)\nendstream")
    open(path, "w") do io
        println(io, "%PDF-1.4")
        offsets = Int[]
        for (i, obj) in enumerate(objects)
            push!(offsets, position(io))
            println(io, "$i 0 obj")
            println(io, obj)
            println(io, "endobj")
        end
        xref = position(io)
        println(io, "xref")
        println(io, "0 $(length(objects)+1)")
        println(io, "0000000000 65535 f ")
        for off in offsets
            println(io, lpad(off, 10, '0'), " 00000 n ")
        end
        println(io, "trailer << /Size $(length(objects)+1) /Root 1 0 R >>")
        println(io, "startxref")
        println(io, xref)
        println(io, "%%EOF")
    end
end

function svg_text(x,y,text; size=12, anchor="start")
    return "<text x=\"$x\" y=\"$y\" font-size=\"$size\" font-family=\"Arial\" text-anchor=\"$anchor\">$(replace(String(text), "&"=>"&amp;", "<"=>"&lt;", ">"=>"&gt;"))</text>"
end

function make_binding_svg_pdf()
    w, h = 900, 720
    left, right, top = 190, 40, 55
    rowh = 16
    maxbeta = maximum(Float64.(binding_data.beta_i))
    maxcap = maximum(Float64.(binding_data.gfm_bess_capacity_GW))
    rows = binding_data
    parts = ["<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$w\" height=\"$h\" viewBox=\"0 0 $w $h\">",
             "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>",
             svg_text(w/2, 25, "Binding frequency and GFM-BESS deployment (gSCR-GERSH)"; size=18, anchor="middle")]
    stream = "1 1 1 rg 0 0 $w $h re f\nBT /F1 16 Tf $(w/2-210) $(h-25) Td ($(pdf_escape("Binding frequency and GFM-BESS deployment (gSCR-GERSH)"))) Tj ET\n"
    for (i, r) in enumerate(eachrow(rows))
        y = top + i*rowh
        bw = 560 * Float64(r.beta_i) / max(1e-9, maxbeta)
        cap = Float64(r.gfm_bess_capacity_GW)
        parts_push = [
            svg_text(10, y+4, "$(Int(r.rank_beta)). $(r.region_name)"; size=10),
            "<rect x=\"$left\" y=\"$(y-8)\" width=\"$bw\" height=\"10\" fill=\"#4477aa\"/>",
            "<circle cx=\"$(left+bw+16)\" cy=\"$(y-3)\" r=\"$(3+8*sqrt(cap/max(1e-9,maxcap)))\" fill=\"#cc6677\" fill-opacity=\"0.75\"/>",
        ]
        append!(parts, parts_push)
        if Bool(r.top5_flag)
            push!(parts, svg_text(left+bw+34, y+2, @sprintf("%.2f GW", cap); size=10))
        end
        stream *= "0.1 0.1 0.1 rg BT /F1 7 Tf 10 $(h-y) Td ($(pdf_escape("$(Int(r.rank_beta)). $(r.region_name)"))) Tj ET\n"
        stream *= "0.27 0.47 0.67 rg $left $(h-y) $bw 8 re f\n"
        stream *= "0.8 0.4 0.47 rg $(left+bw+12) $(h-y) 6 6 re f\n"
    end
    push!(parts, svg_text(left, h-20, "x-axis: binding frequency beta_i; red markers scale with installed BESS-GFM capacity"; size=11))
    push!(parts, "</svg>")
    write(normpath(OUT_DIR, "figure_binding.svg"), join(parts, "\n"))
    write_simple_pdf(normpath(OUT_DIR, "figure_binding.pdf"), w, h, stream)
end

function quantiles(v)
    vv = sort(Float64.(v))
    n = length(vv)
    q(p) = vv[clamp(round(Int, 1 + p*(n-1)), 1, n)]
    return (q(0.0), q(0.25), q(0.5), q(0.75), q(1.0))
end

function make_margin_svg_pdf()
    w, h = 900, 520
    parts = ["<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$w\" height=\"$h\" viewBox=\"0 0 $w $h\">",
             "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>",
             svg_text(w/2, 25, "Post-hoc gSCR margin and local Gershgorin slack"; size=18, anchor="middle")]
    stream = "1 1 1 rg 0 0 $w $h re f\nBT /F1 16 Tf 230 495 Td ($(pdf_escape("Post-hoc gSCR margin and local Gershgorin slack"))) Tj ET\n"
    leftx, rightx = 95, 535
    plotw, ploth = 300, 360
    y0 = 430
    labels = ["BASE", "gSCR-GERSH"]
    vals = [margin_rows[margin_rows.scenario .== lab, :global_margin_gSCR_minus_alpha] for lab in labels]
    ymin = minimum(vcat(vals...)); ymax = max(0.1, maximum(vcat(vals...)))
    scale_y(v) = y0 - (Float64(v)-ymin)/(ymax-ymin)*ploth
    push!(parts, svg_text(leftx+plotw/2, 55, "Global margin gSCR_t - alpha"; size=13, anchor="middle"))
    push!(parts, "<line x1=\"$leftx\" y1=\"$(scale_y(0))\" x2=\"$(leftx+plotw)\" y2=\"$(scale_y(0))\" stroke=\"#555\" stroke-dasharray=\"4 4\"/>")
    stream *= "0.3 0.3 0.3 rg $leftx $(h-scale_y(0)) $plotw 1 re f\n"
    for (i, lab) in enumerate(labels)
        q0,q1,q2,q3,q4 = quantiles(vals[i])
        x = leftx + 90*i - 35
        push!(parts, "<line x1=\"$x\" y1=\"$(scale_y(q0))\" x2=\"$x\" y2=\"$(scale_y(q4))\" stroke=\"#333\"/>")
        push!(parts, "<rect x=\"$(x-22)\" y=\"$(scale_y(q3))\" width=\"44\" height=\"$(scale_y(q1)-scale_y(q3))\" fill=\"#88ccee\" stroke=\"#333\"/>")
        push!(parts, "<line x1=\"$(x-22)\" y1=\"$(scale_y(q2))\" x2=\"$(x+22)\" y2=\"$(scale_y(q2))\" stroke=\"#000\"/>")
        push!(parts, svg_text(x, 455, lab; size=11, anchor="middle"))
        stream *= "0.53 0.8 0.93 rg $(x-22) $(h-scale_y(q1)) 44 $(scale_y(q1)-scale_y(q3)) re f\n"
        stream *= "0 0 0 rg BT /F1 8 Tf $(x-30) 55 Td ($(pdf_escape(lab))) Tj ET\n"
    end
    slack = margin_rows[margin_rows.scenario .== "gSCR-GERSH", :min_local_kappa]
    smin, smax = minimum(slack), max(0.1, maximum(slack))
    sy(v) = y0 - (Float64(v)-smin)/(smax-smin)*ploth
    push!(parts, svg_text(rightx+plotw/2, 55, "Minimum local kappa_i,t (gSCR-GERSH)"; size=13, anchor="middle"))
    push!(parts, "<line x1=\"$rightx\" y1=\"$(sy(0))\" x2=\"$(rightx+plotw)\" y2=\"$(sy(0))\" stroke=\"#555\" stroke-dasharray=\"4 4\"/>")
    q0,q1,q2,q3,q4 = quantiles(slack); x = rightx + plotw/2
    push!(parts, "<line x1=\"$x\" y1=\"$(sy(q0))\" x2=\"$x\" y2=\"$(sy(q4))\" stroke=\"#333\"/>")
    push!(parts, "<rect x=\"$(x-36)\" y=\"$(sy(q3))\" width=\"72\" height=\"$(sy(q1)-sy(q3))\" fill=\"#ddcc77\" stroke=\"#333\"/>")
    push!(parts, "<line x1=\"$(x-36)\" y1=\"$(sy(q2))\" x2=\"$(x+36)\" y2=\"$(sy(q2))\" stroke=\"#000\"/>")
    stream *= "0.87 0.8 0.47 rg $(x-36) $(h-sy(q1)) 72 $(sy(q1)-sy(q3)) re f\n"
    stream *= "0 0 0 rg BT /F1 9 Tf 560 55 Td ($(pdf_escape("Local slack uses available per-snapshot min kappa data."))) Tj ET\n"
    push!(parts, svg_text(w/2, h-18, "Box plots show min, quartiles, median, and max; horizontal dashed lines mark zero."; size=11, anchor="middle"))
    push!(parts, "</svg>")
    write(normpath(OUT_DIR, "figure_margin.svg"), join(parts, "\n"))
    write_simple_pdf(normpath(OUT_DIR, "figure_margin.pdf"), w, h, stream)
end

make_binding_svg_pdf()
make_margin_svg_pdf()

open(normpath(OUT_DIR, "scenario_mapping_and_assumptions.md"), "w") do io
    println(io, "# Scenario Mapping and Assumptions")
    println(io)
    println(io, "- Study period: 03.01 -- 16.01")
    println(io, "- Horizon: 336 h = 2 weeks")
    println(io, "- Annual operation scaling: 26")
    println(io, "- Investment cost policy: investment costs are not divided by the number of days/weeks.")
    println(io, "- Annual system cost: `C_year = C_inv + 26*(C_op + C_startup + C_shutdown)`.")
    println(io, "- Main scenarios: BASE = g_min=0.0; gSCR-GERSH = g_min=1.5.")
    println(io, "- Sensitivity: g_min=1.0 is an intermediate gSCR sensitivity case only and is denoted gSCR-1.")
    println(io, "- No HEUR-GFM run is included. No HEUR-GFM proxy is used.")
    println(io, "- The previously requested g_min=2.0 run was skipped by user instruction; no g_min=2.0 values are used in these paper-ready outputs.")
    println(io, "- Missing latitude/longitude: bus coordinates are unavailable, so Figure 1 uses a ranked regional binding plot.")
    println(io, "- Carrier aggregation: BESS-GFM = battery_gfm; BESS-GFL = battery_gfl; Wind = onwind + offwind-ac + offwind-dc; Solar = solar; Wind+PV = Wind + Solar; Gas = CCGT. OCGT is reported separately in extracted metrics but is zero in these runs.")
end

top5 = split(gscr["top5"], "; ")
results_md = """
# Numerical Results Summary

## System Cost and Capacity Expansion

Table II compares BASE and gSCR-GERSH for the 336 h study period. BASE has no explicit system-strength constraint and obtains a total annualized system cost of $(fmt(base["cost_BEUR"])) B€/a. The gSCR-GERSH case enforces the decentralized gSCR condition with `g_min = 1.5` and increases the annualized cost to $(fmt(gscr["cost_BEUR"])) B€/a. Because the BASE cost is zero in the exported planning-cost accounting, the relative cost increase is undefined and is reported as n/a.

The gSCR-GERSH case installs $(fmt(gscr["BESS_GFM_GW"])) GW of BESS-GFM capacity, compared with $(fmt(base["BESS_GFM_GW"])) GW in BASE. BESS-GFL capacity remains negligible ($(fmt(gscr["BESS_GFL_GW"]; digits=3)) GW). Wind+PV capacity is $(fmt(gscr["WindPV_GW"]; digits=3)) GW in gSCR-GERSH and $(fmt(base["WindPV_GW"]; digits=3)) GW in BASE, while CCGT gas capacity is zero in both cases.

Post-hoc validation shows that BASE violates the paper threshold in all snapshots, with minimum ``\\mu_t = $(fmt_sci(base["min_mu"]))`` and minimum gSCR of $(fmt(base["min_gscr"]; digits=3)). In contrast, gSCR-GERSH has minimum ``\\mu_t = $(fmt_sci(gscr["min_mu"]))`` within numerical tolerance, zero violating snapshots, and minimum gSCR of $(fmt(gscr["min_gscr"]; digits=3)). Solver wall-clock times are $(fmt(base["solve_min"]; digits=2)) min for BASE and $(fmt(gscr["solve_min"]; digits=2)) min for gSCR-GERSH. The intermediate gSCR-1 case is retained only as a sensitivity case.

## Spatial Binding Pattern

Figure 1 reports the regional binding frequency ``\\beta_i`` for gSCR-GERSH together with installed GFM-BESS capacity. Coordinates are unavailable in the input artifacts, so the figure uses a ranked regional binding plot rather than a geographic map. The five most frequently binding regions are $(join(top5, ", ")). These regions also receive substantial GFM-BESS deployment in the optimized solution, consistent with the local nature of the Gershgorin constraint.

## Conservatism of the Linear Constraint

Figure 2 compares the post-hoc global gSCR margin ``gSCR_t-\\alpha`` for BASE and gSCR-GERSH and reports the available local Gershgorin slack information for gSCR-GERSH. BASE is evaluated against the same threshold and remains below it throughout the study horizon. For gSCR-GERSH, the minimum global matrix eigenvalue margin is non-negative within numerical tolerance and the minimum gSCR equals the enforced threshold. The local slack distribution shows that the sufficient constraints are frequently active, which is expected for a pure branch-Laplacian network where diagonal dominance must be supplied locally by online GFM strength.
"""
write(normpath(OUT_DIR, "numerical_results_summary.md"), results_md)

results_tex = replace(results_md,
    "# Numerical Results Summary\n\n" => "\\section{Numerical Results}\n\\label{sec:results}\n\n",
    "## System Cost and Capacity Expansion" => "\\subsection{System Cost and Capacity Expansion}",
    "## Spatial Binding Pattern" => "\\subsection{Spatial Binding Pattern}",
    "## Conservatism of the Linear Constraint" => "\\subsection{Conservatism of the Linear Constraint}",
    "`g_min = 1.5`" => "\$g_{\\min}=1.5\$",
    "`g_min=2.0`" => "\$g_{\\min}=2.0\$",
    "``\\mu_t = " => "\$\\mu_t = ",
    "``" => "\$",
    "\\alpha" => "\$\\alpha\$",
    "\\beta_i" => "\$\\beta_i\$",
)
write(normpath(OUT_DIR, "numerical_results_summary.tex"), results_tex)

discussion = """
# Discussion Notes

## Network decoupling and conservatism

The implemented Gershgorin constraint is local and sufficient. For each snapshot, post-hoc validation considers

```math
M_t = B_t - \\alpha S_t, \\qquad \\mu_t = \\lambda_{\\min}(M_t).
```

The local constraint slack is

```math
\\kappa_{i,t} = \\sigma_i^G + \\Delta b_{i,t} - \\alpha P_{i,t}^{GFL}.
```

For a pure lossless branch Laplacian, the Gershgorin network margin may be zero at each node. The diagonal-dominance margin must then be supplied locally by online GFM strength. This makes the condition transparent but conservative, because it does not fully exploit support from the meshed network. The post-hoc eigenvalue analysis quantifies the gap between local sufficient constraints and the global matrix-strength condition.

## Computational tractability

The method preserves the MILP structure of the clustered generation-expansion problem. It requires no SDP solver and no repeated eigenvalue-gradient update inside branch-and-bound. Each scenario is solved as a single MILP. In the completed 336 h campaign, the BASE and gSCR-GERSH solve times were $(fmt(base["solve_min"]; digits=2)) min and $(fmt(gscr["solve_min"]; digits=2)) min, respectively.

## Planning interpretation and limitations

The gSCR constraint is a planning-level system-strength proxy. It does not replace converter-dynamic or electromagnetic-transient simulations, and the threshold must be calibrated against the converter controls and stability criteria of interest. The two-week period 03.01--16.01 is the selected stress window used in this study and should not be interpreted as full-year chronological validation.
"""
write(normpath(OUT_DIR, "discussion_notes.md"), discussion)
discussion_tex = replace(discussion,
    "# Discussion Notes\n\n" => "\\section{Discussion}\n\\label{sec:discussion}\n\n",
    "## Network decoupling and conservatism" => "\\noindent\\textit{Network decoupling and conservatism.}\\;",
    "## Computational tractability" => "\\noindent\\textit{Computational tractability.}\\;",
    "## Planning interpretation and limitations" => "\\noindent\\textit{Planning interpretation and limitations.}\\;",
    "```math\n" => "\\begin{equation}\n",
    "\n```" => "\n\\end{equation}",
)
write(normpath(OUT_DIR, "results_and_discussion_draft.tex"), results_tex * "\n\n" * discussion_tex)

println("postprocess_complete")
println(OUT_DIR)
