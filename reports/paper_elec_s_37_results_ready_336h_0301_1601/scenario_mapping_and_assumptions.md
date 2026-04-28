# Scenario Mapping and Assumptions

- Study period: 03.01 -- 16.01
- Horizon: 336 h = 2 weeks
- Annual operation scaling: 26
- Investment cost policy: investment costs are not divided by the number of days/weeks.
- Annual system cost: `C_year = C_inv + 26*(C_op + C_startup + C_shutdown)`.
- Main scenarios: BASE = g_min=0.0; gSCR-GERSH = g_min=1.5.
- Sensitivity: g_min=1.0 is an intermediate gSCR sensitivity case only and is denoted gSCR-1.
- No HEUR-GFM run is included. No HEUR-GFM proxy is used.
- The previously requested g_min=2.0 run was skipped by user instruction; no g_min=2.0 values are used in these paper-ready outputs.
- Missing latitude/longitude: bus coordinates are unavailable, so Figure 1 uses a ranked regional binding plot.
- Carrier aggregation: BESS-GFM = battery_gfm; BESS-GFL = battery_gfl; Wind = onwind + offwind-ac + offwind-dc; Solar = solar; Wind+PV = Wind + Solar; Gas = CCGT. OCGT is reported separately in extracted metrics but is zero in these runs.
