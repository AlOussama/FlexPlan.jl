# Paper elec_s_37 336h CAPEXP/gSCR Campaign

- solved cases: 2
- failed/infeasible cases: 0
- selected_weeks_policy: two_weeks_from_0301_with_preprocessed_fossil_exclusion
- source dataset: elec_s_37_2weeks_from_0301
- excluded_carriers: coal, lignite, oil
- excluded aliases removed: hard coal
- HEUR-GFM is not implemented in this campaign.
- missing optional fields: bus latitude/longitude; bus-level RES_GW in paper_figure_1_spatial_map.csv
- startup/shutdown costs are applied only through the existing conventional non-renewable synchronous su_block/sd_block policy after coal/lignite/oil exclusion.

## Runs
- gSCR-GERSH-1p0-INTEGER: status=OPTIMAL, objective=1.7607669531317188e11, min_gSCR_margin=0.0
- gSCR-GERSH-1p5-INTEGER: status=OPTIMAL, objective=3.479700044989219e11, min_gSCR_margin=0.0

## 336h Technical Matrix
- gSCR-GERSH-1p0-INTEGER: optimization_g_min=1.0, total_annual_system_cost_BEUR_per_year=176.07726276510363, BESS-GFM_GW=417.70000000000005, BESS-GFL_GW=0.0, RES_GW=0.1, wind_GW=0.0, PV_GW=0.1, CCGT_GW=0.0, OCGT_GW=0.0, solver_wallclock_min=4.739066668351492, min_mu_t_alpha_1p5=-3953.875719700078, min_gSCR_t=1.0013461538461526, violating_snapshots_percent_alpha_1p5=100.0, own_target_mu_t=1.534516972762066
- gSCR-GERSH-1p5-INTEGER: optimization_g_min=1.5, total_annual_system_cost_BEUR_per_year=347.97051468842534, BESS-GFM_GW=826.1, BESS-GFL_GW=0.0, RES_GW=0.05, wind_GW=0.0, PV_GW=0.05, CCGT_GW=0.0, OCGT_GW=0.0, solver_wallclock_min=6.407799998919169, min_mu_t_alpha_1p5=-1.4886607656362923e-12, min_gSCR_t=1.4999999999999984, violating_snapshots_percent_alpha_1p5=0.0, own_target_mu_t=-1.4886607656362923e-12

## Validation Flags
