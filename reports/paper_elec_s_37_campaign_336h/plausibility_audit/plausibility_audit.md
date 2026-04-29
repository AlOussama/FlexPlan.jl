# Plausibility Audit of 336h elec_s_37 Campaign

## 1. Scope and input data
Period: 14.01--27.01, 336 hourly snapshots. Cases analyzed: BASE, gSCR-GERSH-1.0, and gSCR-GERSH-1.5. No new optimization was run. The audit uses the original case data recorded in `run_config.json` and saved optimization results in the three run folders.

Case data: `D:\Projekte\Code\pypsatomatpowerx_clean_battery_policy\data\flexplan_block_gscr\elec_s_37_2weeks_from_0301\case.json`.

## 2. Cost scale before interpreting optimization
The input-data audit shows that storage and renewable technologies have zero marginal/startup/shutdown costs in the block data, while GFM-BESS has a finite investment cost and strength coefficient. Carrier-level cost scales are written to `cost_scale_by_carrier.csv`.

`carrier` | `type` | `device_count` | `investment_cost_per_block_mean` | `marginal_cost_mean` | `startup_cost_mean` | `investment_cost_per_strength_mean`
--- | --- | --- | --- | --- | --- | ---
CCGT | gfm | 37 | 8.912e+09 | 42.25 | 16.5 | 5.942e+08
lignite | gfm | 12 | 7.087e+10 | 12.2 | 45 | 3.15e+09
biomass | gfm | 12 | 6.952e+08 | 14.89 | 3.5 | 2.781e+08
ror | gfm | 28 | 7.479e+08 | 0 | 0 | 2.991e+08
offwind-ac | gfl | 28 | 1.894e+09 | 0.015 | 0 | NaN
solar | gfl | 37 | 8.901e+07 | 0.01 | 0 | NaN
offwind-dc | gfl | 23 | 2.134e+09 | 0.015 | 0 | NaN
onwind | gfl | 37 | 2.402e+08 | 0.015 | 0 | NaN


## 3. Optimized investment and dispatch decisions
Optimized investment is almost entirely GFM-BESS in the constrained cases. Aggregate dispatch remains dominated by existing renewables, hydro/PHS/storage, and nuclear/gas where available. Detailed per-component dispatch was not saved, so component dispatch utilization is reported as aggregate carrier utilization and missing where a true per-unit ratio would be required.

`scenario_name` | `carrier` | `invested_capacity_GW` | `mean_online_blocks` | `online_block_fraction_mean` | `total_discharge_MWh` | `total_charge_MWh` | `investment_cost_realized`
--- | --- | --- | --- | --- | --- | --- | ---
BASE | battery_gfl | 0 | 0 | 0 | 0 | 0 | 0
BASE | battery_gfm | 0 | 0 | 0 | 0 | 0 | 0
gSCR-GERSH-1.0 | battery_gfl | 0.002 | 0.003006 | 0.1503 | 45 | 53 | 7.927e+05
gSCR-GERSH-1.0 | battery_gfm | 414.8 | 4148 | 1 | 3.7e+07 | 3.701e+07 | 1.747e+11
gSCR-GERSH-1.5 | battery_gfl | 0.001 | 0.0009524 | 0.09524 | 12 | 17 | 3.963e+05
gSCR-GERSH-1.5 | battery_gfm | 821.1 | 8211 | 1 | 2.432e+08 | 2.432e+08 | 3.458e+11


## 4. Why GFM-BESS is strongly preferred
GFM-BESS is preferred because it adds to the gSCR LHS through online strength, while GFL resources add RHS exposure. The paired battery premium has min/mean/max investment premium 6.250 / 6.250 / 6.250 %. The mean premium is below 10%, so the strength service is cheap relative to the GFL alternative. Online/standby costs are absent or zero for storage, and p_min_pu is zero or missing for many converter-like devices, allowing online strength provision with little energy consequence.

## 5. Why BASE has near-zero cost
BASE has no material expansion and existing fleet fixed costs are not included in the campaign objective. Its annual system cost is therefore an incremental cost metric, not a full system cost. Operation cost is near zero despite large dispatch because many dispatched carriers have zero marginal cost in the input data and storage/hydro/PHS initial energy contributes materially. This is best interpreted as a naming/cost-scope issue plus cost-data sparsity, not evidence that serving load is literally free.

`scenario_name` | `total_annual_system_cost` | `investment_cost` | `operation_cost_raw_horizon` | `startup_cost_raw_horizon` | `total_generation_dispatch` | `total_storage_discharge` | `final_storage_ratio`
--- | --- | --- | --- | --- | --- | --- | ---
BASE | 0 | 0 | 0 | 0 | 1.049e+08 | 3.393e+07 | 0.9311
gSCR-GERSH-1.0 | 1.748e+11 | 1.748e+11 | 0.01989 | 2.036e+04 | 1.042e+08 | 7.902e+07 | 0.9282
gSCR-GERSH-1.5 | 3.458e+11 | 3.458e+11 | 0.01152 | 2.04e+04 | 1.044e+08 | 2.85e+08 | 0.9285


## 6. Load vs generation and storage capability
The load/capability diagnostic is written to `load_vs_capability_timeseries.csv` and plotted in `load_vs_capability_plot.pdf/png`. Minimum adequacy margins are:

`scenario_name` | `min_adequacy_margin_gen_only` | `min_adequacy_margin_gen_plus_storage` | `min_adequacy_ratio_gen_only` | `min_adequacy_ratio_gen_plus_storage` | `snapshot_min_gen_only_margin`
--- | --- | --- | --- | --- | ---
BASE | -1.107e+05 | 4.21e+04 | 0.7743 | 1.086 | 307
gSCR-GERSH-1.0 | -1.107e+05 | 4.569e+05 | 0.7743 | 1.932 | 307
gSCR-GERSH-1.5 | -1.107e+05 | 8.633e+05 | 0.7743 | 2.761 | 307


Investment is not primarily needed for energy adequacy in these artifacts; the large constrained-case buildout is mainly explained by gSCR strength requirements.

## 7. Online-block and dispatch utilization
The GFM-BESS online-zero-dispatch count is 22848. Because per-component dispatch was not saved, all online GFM-BESS events with no matching per-component dispatch are conservatively counted as diagnostic online-zero-dispatch candidates. High online fraction with low aggregate dispatch utilization indicates that `na_block` is functioning as a strength-availability variable without standby cost.

## 8. gSCR binding analysis using RHS/LHS ratios
The reconstructed local ratio diagnostic uses `LHS = online GFM strength` and `RHS = 1.5 * online GFL exposure`; full Delta_b time series was not saved, so Delta_b is explicitly set to zero in the CSV. Max utilization ratios are:

`scenario_name` | `min_cover_ratio` | `max_utilization_ratio` | `near_binding_095_count` | `near_binding_099_count` | `violated_count` | `top_binding_bus` | `top_binding_snapshot`
--- | --- | --- | --- | --- | --- | --- | ---
BASE | 0 | 1500 | 0 | 0 | 1.142e+04 | 17 | 336
gSCR-GERSH-1.0 | 0.6667 | 1.5 | 18 | 2 | 6012 | 8 | 1
gSCR-GERSH-1.5 | 1 | 1 | 7069 | 7001 | 0 | 18 | 1


## 9. Effect of AC islands and zero eigenvalues of Bnet
The AC graph has 7 connected island(s), and the reconstructed Bnet has 7 near-zero eigenvalue(s). These counts match, which is the key plausibility check for a disconnected Laplacian. Global gSCR must be interpreted using finite generalized eigenvalues or per-island values on islands with positive GFL exposure.

## 10. Risks of global p_min_pu = 0.1
Adding a global p_min_pu would prevent fully dispatch-free online blocks, but it risks artificial must-run energy, storage SOC distortion, infeasibility or curtailment, and wrong coupling between converter strength and active power. In clustered systems one block may represent a large aggregate unit, so 10% minimum output can be a large artificial injection. Better alternatives are technology-specific thermal p_min_pu, online/standby cost on `na_block`, converter standby losses/costs, GFM-BESS headroom/SOC constraints, and GFM cost-premium sensitivities.

## 11. Conclusions and recommended next steps
The optimized GFM-BESS buildout is economically plausible under the current cost/capability model, but it should be qualified: the model prices GFM strength through investment only, not through online standby operation. BASE near-zero cost is an incremental-objective interpretation issue and reflects omitted existing fixed costs plus zero/near-zero operating costs. Before paper submission, report gSCR per connected AC subsystem or clearly state that the post-hoc global metric excludes disconnected zero modes.

Top warnings:

- Per-component and per-snapshot optimized dispatch was not present in the run artifacts; dispatch-utilization and online-zero-dispatch use aggregate dispatch or conservative missing markers.
- Local gSCR LHS/RHS ratios are reconstructed from online strength/exposure with Delta_b set to 0 because full per-bus Delta_b time series is not saved.
- The global gSCR island audit reconstructs Bnet from branch reactances and graph connectivity; it does not rerun the original posthoc generalized-eigenvalue implementation.
- Mean GFM/GFL battery investment premium is below 10%, making GFM-BESS economically dominant when strength has no standby cost.
