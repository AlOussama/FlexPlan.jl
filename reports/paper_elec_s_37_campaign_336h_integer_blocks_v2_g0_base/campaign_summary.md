# Paper elec_s_37 336h CAPEXP/gSCR Campaign

- solved cases: 1
- failed/infeasible cases: 0
- selected_weeks_policy: two_weeks_from_0301_with_preprocessed_fossil_exclusion
- source dataset: elec_s_37_2weeks_from_0301
- excluded_carriers: coal, lignite, oil
- excluded aliases removed: hard coal
- HEUR-GFM is not implemented in this campaign.
- missing optional fields: bus latitude/longitude; bus-level RES_GW in paper_figure_1_spatial_map.csv
- startup/shutdown costs are applied only through the existing conventional non-renewable synchronous su_block/sd_block policy after coal/lignite/oil exclusion.

## Runs
- BASE-INTEGER: status=OPTIMAL, objective=0.078125, min_gSCR_margin=0.0

## 336h Technical Matrix
- BASE-INTEGER: optimization_g_min=0.0, total_annual_system_cost_BEUR_per_year=2.03125e-9, BESS-GFM_GW=0.0, BESS-GFL_GW=0.0, RES_GW=0.0, wind_GW=0.0, PV_GW=0.0, CCGT_GW=0.0, OCGT_GW=0.0, solver_wallclock_min=0.6740333318710328, min_mu_t_alpha_1p5=-172400.6820624249, min_gSCR_t=0.003422952395491217, violating_snapshots_percent_alpha_1p5=100.0, own_target_mu_t=13.342760953515246

## Validation Flags
