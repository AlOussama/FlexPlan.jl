# Paper elec_s_37 336h CAPEXP/gSCR Campaign

- solved cases: 3
- failed/infeasible cases: 0
- selected_weeks_policy: two_weeks_from_0114_with_preprocessed_fossil_exclusion
- source dataset: elec_s_37_2weeks_from_0114
- excluded_carriers: coal, lignite, oil
- excluded aliases removed: hard coal
- HEUR-GFM is not implemented in this campaign.
- missing optional fields: bus latitude/longitude; bus-level RES_GW in paper_figure_1_spatial_map.csv
- startup/shutdown costs are applied only through the existing conventional non-renewable synchronous su_block/sd_block policy after coal/lignite/oil exclusion.

## Runs
- BASE-INTEGER: status=OPTIMAL, objective=278.078125, min_gSCR_margin=236.5
- gSCR-GERSH-1p0-INTEGER: status=OPTIMAL, objective=278.078125, min_gSCR_margin=186.5
- gSCR-GERSH-1p5-INTEGER: status=OPTIMAL, objective=278.078125, min_gSCR_margin=150.0

## 336h Technical Matrix
- BASE-INTEGER: optimization_g_min=0.0, total_annual_system_cost_BEUR_per_year=7.23003125e-6, BESS-GFM_GW=0.0, BESS-GFL_GW=0.0, RES_GW=0.0, wind_GW=0.0, PV_GW=0.0, CCGT_GW=0.0, OCGT_GW=0.0, solver_wallclock_min=0.4022166689236959, min_mu_t_alpha_1p5=222.7459915986271, min_gSCR_t=2.9999999999999956, violating_snapshots_percent_alpha_1p5=0.0, own_target_mu_t=323.02301552427053
- gSCR-GERSH-1p0-INTEGER: optimization_g_min=1.0, total_annual_system_cost_BEUR_per_year=7.23003125e-6, BESS-GFM_GW=0.0, BESS-GFL_GW=0.0, RES_GW=0.0, wind_GW=0.0, PV_GW=0.0, CCGT_GW=0.0, OCGT_GW=0.0, solver_wallclock_min=1.0232833305994669, min_mu_t_alpha_1p5=222.74590977191215, min_gSCR_t=2.999999999999998, violating_snapshots_percent_alpha_1p5=0.0, own_target_mu_t=259.6736270628912
- gSCR-GERSH-1p5-INTEGER: optimization_g_min=1.5, total_annual_system_cost_BEUR_per_year=7.23003125e-6, BESS-GFM_GW=0.0, BESS-GFL_GW=0.0, RES_GW=0.0, wind_GW=0.0, PV_GW=0.0, CCGT_GW=0.0, OCGT_GW=0.0, solver_wallclock_min=5.118016668160757, min_mu_t_alpha_1p5=222.747225996884, min_gSCR_t=2.999999999999997, violating_snapshots_percent_alpha_1p5=0.0, own_target_mu_t=222.747225996884

## Validation Flags
