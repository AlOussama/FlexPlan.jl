# Result Fill Report

## Source files used

- `reports/paper_elec_s_37_campaign_336h/paper_table_A_system_design.csv`
- `reports/paper_elec_s_37_campaign_336h/paper_table_B_energy_mix.csv`
- `reports/paper_elec_s_37_campaign_336h/paper_table_C_global_gscr_validation.csv`
- `reports/paper_elec_s_37_campaign_336h/paper_result_artifact_summary.md`

## Scenario mapping

- `BASE`: found
- `gSCR-GERSH-1.0`: found
- `gSCR-GERSH-1.5`: found

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
Table~\ref{tab:system_design} shows that the optimized system design is
unchanged across the three cases for the selected 336-hour study period.
The additional gSCR constraints therefore do not change annualized system
cost after rounding, and the reported cost increments remain below
0.01~B\euro{}/a.
```

```latex
Table~\ref{tab:energy_mix} reports the annual-equivalent dispatch obtained
by scaling the two-week operation by a factor of 26. Wind and solar
generation increase moderately in the gSCR-constrained cases, while gas
generation decreases relative to the BASE case. Curtailment is not reported
because no explicit curtailment artifact was available in the saved
post-processing outputs.
```

```latex
Table~\ref{tab:strength_validation} validates all cases at the common paper
threshold \(\alpha=1.5\) using the global finite generalized eigenvalue
metric. The minimum global gSCR remains above the threshold in all three
cases, and no global gSCR or matrix-margin violations are observed over the
336 snapshots. The local utilization values remain below one, indicating
non-binding decentralized strength constraints for this selected period.
```

## Warnings

- The absolute annual system cost in the frozen campaign is extremely small in B€/a (`7.23003125e-6` B€/a) and identical across cases in the post-processing table, so cost deltas round to `0.00` B€/a and `0.00`%.
- No figures were generated or referenced by this fill-in step.
- No geographic/map outputs were used.
- No optimization was rerun.
