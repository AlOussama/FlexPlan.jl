# Paper elec_s_37 336h CAPEXP/gSCR Campaign

- solved cases: 3
- failed/infeasible cases: 0
- selected_weeks_policy: two_weeks_from_0301_with_preprocessed_fossil_exclusion
- source dataset: elec_s_37_2weeks_from_0301
- excluded_carriers: coal, lignite, oil
- excluded aliases removed: hard coal
- HEUR-GFM is not implemented in this campaign.
- missing optional fields: bus latitude/longitude; bus-level RES_GW in paper_figure_1_spatial_map.csv
- startup/shutdown costs are applied only through the existing conventional non-renewable synchronous su_block/sd_block policy after coal/lignite/oil exclusion.

## Runs
- BASE: status=OPTIMAL, objective=0.0, min_gSCR_margin=0.0
- gSCR-GERSH-1p0: status=OPTIMAL, objective=1.7477678329740625e11, min_gSCR_margin=-4.547473508864641e-13
- gSCR-GERSH-1p5: status=OPTIMAL, objective=3.458087208455625e11, min_gSCR_margin=-9.094947017729282e-13

## 336h Technical Matrix
- BASE: optimization_g_min=0.0, total_annual_system_cost_BEUR_per_year=0.0, BESS-GFM_GW=0.0, BESS-GFL_GW=0.0, RES_GW=0.0, wind_GW=0.0, PV_GW=0.0, CCGT_GW=0.0, OCGT_GW=0.0, solver_wallclock_min=0.44740000168482463, min_mu_t_alpha_1p5=-172415.68203127332, min_gSCR_t=0.003233776493455415, violating_snapshots_percent_alpha_1p5=100.0, own_target_mu_t=2.5961480969383977
- gSCR-GERSH-1p0: optimization_g_min=1.0, total_annual_system_cost_BEUR_per_year=174.77729222677635, BESS-GFM_GW=414.8031829821719, BESS-GFL_GW=0.002, RES_GW=0.05460000000000001, wind_GW=0.0, PV_GW=0.05460000000000001, CCGT_GW=0.0, OCGT_GW=0.0, solver_wallclock_min=5.739483332633972, min_mu_t_alpha_1p5=-1858.9632164030609, min_gSCR_t=0.9999999999999423, violating_snapshots_percent_alpha_1p5=100.0, own_target_mu_t=-5.924731322266323e-13
- gSCR-GERSH-1p5: optimization_g_min=1.5, total_annual_system_cost_BEUR_per_year=345.80923086817296, BESS-GFM_GW=821.1497744732582, BESS-GFL_GW=0.001, RES_GW=0.006700000000000006, wind_GW=0.0, PV_GW=0.006700000000000006, CCGT_GW=0.0, OCGT_GW=0.0, solver_wallclock_min=0.5210166692733764, min_mu_t_alpha_1p5=-1.3848668464392223e-12, min_gSCR_t=1.4999999999999512, violating_snapshots_percent_alpha_1p5=0.0, own_target_mu_t=-1.3848668464392223e-12

## Validation Flags
- BASE violates post-hoc system strength at alpha=1.5: true
- gSCR-GERSH-1p5 satisfies mu_t >= 0 at alpha=1.5: true
- gSCR-GERSH-1p0 satisfies its own target g_min=1.0: true
- gSCR-GERSH-1p0 satisfies paper target alpha=1.5: false
