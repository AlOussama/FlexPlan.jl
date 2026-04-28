# Result Fill Report: 03.01--16.01 Integer Blocks

## Source files used

- `reports/paper_elec_s_37_campaign_336h_integer_blocks_v2/H_336h_gmin_0p0_integer_blocks/`
- `reports/paper_elec_s_37_campaign_336h_integer_blocks_v2/H_336h_gmin_1p0_integer_blocks/`
- `reports/paper_elec_s_37_campaign_336h_integer_blocks_v2/H_336h_gmin_1p5_integer_blocks/`
- `paper_table_A_system_design.csv`
- `paper_table_B_energy_mix.csv`
- `paper_table_C_global_gscr_validation.csv`
- `paper_result_artifact_summary.md`

## Scenario mapping

- `BASE`: found, integer block run, `optimization_g_min = 0.0`
- `gSCR-GERSH-1.0`: found, integer block run, `optimization_g_min = 1.0`
- `gSCR-GERSH-1.5`: found, integer block run, `optimization_g_min = 1.5`

All three tables were filled from the generated post-processing CSVs.

## Missing values

- Curtailment was not available in the saved artifacts. The Curtailment row in Table B is therefore filled with `--` for all scenarios and for the delta column.

## Carrier mappings used

- Wind = `onwind` + `offwind-ac` + `offwind-dc`
- Solar PV = `solar`
- Gas = `CCGT` as used by the post-processing file
- BESS-GFL = `battery_gfl` / `BESS-GFL`
- BESS-GFM = `battery_gfm` / `BESS-GFM`
- Total BESS = BESS-GFL + BESS-GFM

## Units and scaling

- Costs are reported in B€/a and rounded to two decimals.
- Delta cost percentages are reported as `n/a` because the BASE cost is numerically near zero (`2.03125e-9` B€/a), making percentage deltas not meaningful.
- Energy values are annual-equivalent TWh/a values from the post-processing output, scaled by `annual_operation_scaling_factor = 26`.
- Capacities are reported in GW.
- Solve times are reported in minutes.
- Total local deficit uses the raw unit reported by the post-processing file: `MW-equivalent`.

## Validation interpretation

- Table C uses the global eigenvalue-based gSCR metric as the primary validation metric: `min_global_gSCR_t` from the finite generalized eigenvalue problem `B_t v = lambda S_t v`.
- Common validation threshold: `alpha_paper = 1.5`.
- gSCR violation tolerance reported by post-processing: `epsilon_gSCR = 1e-6`.
- Matrix-margin violation tolerance reported by post-processing: `epsilon_mu = 1e-7`.

## Copy-paste LaTeX result text

```latex
Table~\ref{tab:system_design} shows that enforcing the decentralized
strength constraint with integer block variables substantially increases
GFM-BESS deployment in the selected 03.01--16.01 two-week period. The
BASE case contains no additional BESS investment, while the gSCR-1.5 case
installs 826.1~GW of BESS-GFM. Absolute cost increments are reported
relative to BASE; percentage increments are omitted because the BASE cost
is numerically close to zero.
```

```latex
Table~\ref{tab:energy_mix} reports the annual-equivalent dispatch obtained
by scaling the 336-hour horizon by a factor of 26. The gSCR-constrained
integer-block cases shift operation from wind and solar generation toward
gas generation and storage cycling. Curtailment is not reported because no
explicit curtailment artifact was available in the saved outputs.
```

```latex
Table~\ref{tab:strength_validation} validates all optimized designs at the
common paper threshold \(\alpha=1.5\) using the global finite generalized
eigenvalue metric. BASE and gSCR-1.0 remain below the paper threshold in
all snapshots, whereas gSCR-1.5 reaches the target with no global gSCR or
matrix-margin violations at \(\alpha=1.5\).
```

## Warnings

- The g=0 BASE run was added after the existing g=1.0 and g=1.5 integer-block campaign. The raw run directory is present in `paper_elec_s_37_campaign_336h_integer_blocks_v2`, but the older campaign-level comparison files in that raw folder were not overwritten.
- No new optimization was run during this post-processing step.
- No figures were generated beyond the requested post-processing figures.
- No geographic/map outputs were used.
