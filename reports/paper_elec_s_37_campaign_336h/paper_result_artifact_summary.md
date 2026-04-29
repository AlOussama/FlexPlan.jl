# Paper Result Artifact Summary

- Input campaign directory used: `..\frozen_postprocessing_336h_0114_integer_blocks_20260428\results`
- Output directory: `reports/paper_elec_s_37_campaign_336h`
- Study period: 14.01--27.01
- Horizon: 336 hourly snapshots
- Annual operation scaling factor: 26
- Common validation threshold alpha_paper: 1.5
- No new optimization was run.
- No HEUR-GFM run or proxy was used.
- No geographic plot was generated.
- All three cases complete: true

## Scenario Mapping
- BASE = `H_336h_gmin_0p0_integer_blocks`, optimization_g_min=0.0
- gSCR-GERSH-1.0 = `H_336h_gmin_1p0_integer_blocks`, optimization_g_min=1.0
- gSCR-GERSH-1.5 = `H_336h_gmin_1p5_integer_blocks`, optimization_g_min=1.5

## Selected Regions for Figure 1(a)
- DE: region_id=8, region_name=DE1 0, reason=top_wind_exposure
- ES: region_id=12, region_name=ES1 0, reason=top_wind_exposure
- IT: region_id=22, region_name=IT1 0, reason=top_solar_exposure
- UK: region_id=16, region_name=GB0 0, reason=top_solar_exposure
- DK: region_id=9, region_name=DK1 0, reason=top_local_utilization

## Generated Files
- `paper_figure_1_strength_timeseries.pdf`
- `paper_figure_1_strength_timeseries.png`
- `paper_figure_2_mix.pdf`
- `paper_figure_2_mix.png`
- `paper_figure_1_timeseries_strength.csv`
- `paper_figure_1_selected_regions.csv`
- `paper_figure_2_mix.csv`
- `paper_table_A_system_design.csv`
- `paper_table_B_energy_mix.csv`
- `paper_table_C_global_gscr_validation.csv`
- `paper_result_artifact_summary.md`

## Data Availability and Assumptions
- Curtailment data available: false. Curtailment is reported as NA in Table B and omitted from Figure 2(b).
- Local metric reconstruction successful: true, from `online_schedule.csv`.
- sigma_i^G: no full per-bus sigma artifact is stored; the frozen study documents the gSCR baseline as a pure Laplacian with sigma_i^G=0 up to numerical tolerance, so zero was used for local ratio reconstruction.
- Carrier aggregation: Wind = onwind + offwind-ac + offwind-dc; Solar PV = solar; Gas = CCGT; BESS-GFL = battery_gfl/BESS-GFL; BESS-GFM = battery_gfm/BESS-GFM.
- Figure 2(a) uses the saved `investment_by_carrier.csv` capacity values, labelled as expansion [GW].
- Figure 2(b) scales two-week dispatch by 26 and converts MWh to TWh/a equivalent.
- Local-ratio plot y-axis upper limit: 2.022; raw values are preserved in `paper_figure_1_timeseries_strength.csv`.
- gSCR violation tolerance epsilon_gSCR: 1.0e-6
- mu violation tolerance epsilon_mu: 1.0e-7

## Missing Fields
- Curtailment was not found in saved artifacts.
- Geographic coordinates were not used because geographic maps are explicitly excluded.
