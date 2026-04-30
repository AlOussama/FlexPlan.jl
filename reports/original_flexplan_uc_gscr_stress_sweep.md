# Original FlexPlan UC/gSCR gSCR Stress Sweep

## Purpose

This analysis-only sweep uses a native FlexPlan `case2_d_strg.m` fixture to test whether the Gershgorin gSCR constraint can become binding or economically visible before external PyPSA fixtures are regenerated.

## Data And Model Setup

- Source data: `test/data/case2/case2_d_strg.m`
- Model type: `DCPPowerModel`
- Solver: `HiGHS`
- Template: explicit `UCGSCRBlockTemplate`
- gSCR formulations: `NoGSCR` and `GershgorinGSCR(OnlineNameplateExposure())`
- Storage terminal policies: `:none` for the full grid and `:relaxed_cyclic` with `storage_terminal_fraction=0.8` for a focused subset
- External PyPSA fixtures were not used.

## Sweep Results

- Total runs: 105
- Status counts: Dict("OPTIMAL" => 105)
- Classification counts: Dict("feasible_binding_gscr" => 12, "feasible_gscr_changes_decision" => 78, "feasible_nonbinding_gscr" => 15)

| formulation | g_min | b_block | cost_mult | policy | status | objective | min margin | near | GFM n | GFM na | delta obj | class | notes |
| --- | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| NoGSCR | 0.0 | 0.5 | 1.0 | none | OPTIMAL | 182.0 | missing | 0 | 20.2 | 20.2 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 0.5 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 2 | 20.2 | 20.1 | 0.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 0.5 | 0.5 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 4 | 20.2 | 20.0 | -2.842171e-14 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 0.5 | 1.0 | none | OPTIMAL | 186.95 | 0.0 | 4 | 20.2 | 20.2 | 4.95 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 0.5 | 1.0 | none | OPTIMAL | 188.6333 | 0.0 | 4 | 20.2 | 20.2 | 6.633333 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 0.5 | 1.0 | none | OPTIMAL | 189.475 | -8.881784e-16 | 4 | 20.2 | 20.2 | 7.475 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 0.5 | 1.0 | none | OPTIMAL | 190.3167 | 0.0 | 4 | 20.2 | 20.2 | 8.316667 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 0.5 | 5.0 | none | OPTIMAL | 910.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 0.5 | 5.0 | none | OPTIMAL | 910.0 | 0.0 | 2 | 2.0 | 2.0 | 0.0 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 0.5 | 5.0 | none | OPTIMAL | 910.0 | 0.0 | 4 | 20.0 | 20.0 | -3.410605e-13 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 0.5 | 5.0 | none | OPTIMAL | 914.95 | 0.0 | 4 | 20.2 | 20.2 | 4.95 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 0.5 | 5.0 | none | OPTIMAL | 916.6333 | 0.0 | 4 | 20.2 | 20.2 | 6.633333 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 0.5 | 5.0 | none | OPTIMAL | 917.475 | -8.881784e-16 | 4 | 20.2 | 20.2 | 7.475 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 0.5 | 5.0 | none | OPTIMAL | 918.3167 | -2.664535e-15 | 4 | 20.2 | 20.2 | 8.316667 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 0.5 | 20.0 | none | OPTIMAL | 910.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 0.5 | 20.0 | none | OPTIMAL | 910.0 | 0.0 | 2 | 2.0 | 2.0 | -2.273737e-13 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 0.5 | 20.0 | none | OPTIMAL | 1877.45 | 0.0 | 4 | 15.1 | 15.1 | 967.45 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 0.5 | 20.0 | none | OPTIMAL | 2634.967 | 0.0 | 4 | 20.13333 | 20.13333 | 1724.967 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 0.5 | 20.0 | none | OPTIMAL | 2889.975 | 0.0 | 4 | 15.15 | 15.15 | 1979.975 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 0.5 | 20.0 | none | OPTIMAL | 3041.98 | 0.0 | 4 | 16.16 | 16.16 | 2131.98 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 0.5 | 20.0 | none | OPTIMAL | 3215.7 | -3.552714e-15 | 4 | 17.31429 | 17.31429 | 2305.7 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 0.5 | 50.0 | none | OPTIMAL | 910.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 0.5 | 50.0 | none | OPTIMAL | 910.0 | 0.0 | 2 | 2.0 | 2.0 | -2.273737e-13 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 0.5 | 50.0 | none | OPTIMAL | 3557.45 | 0.0 | 4 | 15.1 | 15.1 | 2647.45 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 0.5 | 50.0 | none | OPTIMAL | 5824.967 | 0.0 | 4 | 20.13333 | 20.13333 | 4914.967 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 0.5 | 50.0 | none | OPTIMAL | 6834.975 | 0.0 | 4 | 15.15 | 15.15 | 5924.975 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 0.5 | 50.0 | none | OPTIMAL | 7289.98 | 0.0 | 4 | 16.16 | 16.16 | 6379.98 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 0.5 | 50.0 | none | OPTIMAL | 7809.986 | -3.552714e-15 | 4 | 17.31429 | 17.31429 | 6899.986 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 1.0 | 1.0 | none | OPTIMAL | 182.0 | missing | 0 | 20.2 | 20.2 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 1.0 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 2 | 20.2 | 20.1 | 0.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 0.5 | 1.0 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 2 | 20.2 | 20.1 | -2.842171e-14 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 1.0 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 4 | 20.2 | 20.0 | -2.842171e-14 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 1.0 | 1.0 | none | OPTIMAL | 185.2667 | 0.0 | 4 | 20.2 | 20.2 | 3.266667 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 1.0 | 1.0 | none | OPTIMAL | 186.95 | 0.0 | 4 | 20.2 | 20.2 | 4.95 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 1.0 | 1.0 | none | OPTIMAL | 188.6333 | 0.0 | 4 | 20.2 | 20.2 | 6.633333 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 1.0 | 5.0 | none | OPTIMAL | 910.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 1.0 | 5.0 | none | OPTIMAL | 910.0 | 0.0 | 2 | 2.0 | 2.0 | 0.0 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 1.0 | 5.0 | none | OPTIMAL | 910.0 | -1.332268e-14 | 4 | 10.0 | 10.0 | -2.273737e-13 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 1.0 | 5.0 | none | OPTIMAL | 910.0 | 0.0 | 4 | 20.0 | 20.0 | -3.410605e-13 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 1.0 | 5.0 | none | OPTIMAL | 913.2667 | 0.0 | 4 | 20.2 | 20.2 | 3.266667 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 1.0 | 5.0 | none | OPTIMAL | 914.95 | 0.0 | 4 | 20.2 | 20.2 | 4.95 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 1.0 | 5.0 | none | OPTIMAL | 916.6333 | 0.0 | 4 | 20.2 | 20.2 | 6.633333 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 1.0 | 20.0 | none | OPTIMAL | 910.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 1.0 | 20.0 | none | OPTIMAL | 910.0 | 0.0 | 2 | 2.0 | 2.0 | 0.0 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 1.0 | 20.0 | none | OPTIMAL | 1265.9 | 0.0 | 4 | 9.1 | 9.1 | 355.9 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 1.0 | 20.0 | none | OPTIMAL | 1877.45 | 0.0 | 4 | 15.1 | 15.1 | 967.45 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 1.0 | 20.0 | none | OPTIMAL | 2331.96 | 0.0 | 4 | 18.12 | 18.12 | 1421.96 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 1.0 | 20.0 | none | OPTIMAL | 2634.967 | 0.0 | 4 | 20.13333 | 20.13333 | 1724.967 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 1.0 | 20.0 | none | OPTIMAL | 2889.975 | 0.0 | 4 | 15.15 | 15.15 | 1979.975 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 1.0 | 50.0 | none | OPTIMAL | 910.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 1.0 | 50.0 | none | OPTIMAL | 910.0 | 0.0 | 2 | 2.0 | 2.0 | 0.0 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 1.0 | 50.0 | none | OPTIMAL | 1798.4 | 0.0 | 4 | 9.1 | 9.1 | 888.4 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 1.0 | 50.0 | none | OPTIMAL | 3557.45 | 0.0 | 4 | 15.1 | 15.1 | 2647.45 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 1.0 | 50.0 | none | OPTIMAL | 4917.96 | 0.0 | 4 | 18.12 | 18.12 | 4007.96 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 1.0 | 50.0 | none | OPTIMAL | 5824.967 | 0.0 | 4 | 20.13333 | 20.13333 | 4914.967 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 1.0 | 50.0 | none | OPTIMAL | 6834.975 | 0.0 | 4 | 15.15 | 15.15 | 5924.975 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 2.0 | 1.0 | none | OPTIMAL | 182.0 | missing | 0 | 20.2 | 20.2 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 2.0 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 2 | 20.2 | 20.1 | 0.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 0.5 | 2.0 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 2 | 20.2 | 20.1 | 0.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 2.0 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 2 | 20.2 | 20.1 | -2.842171e-14 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 2.0 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 2 | 20.2 | 20.0 | -2.842171e-14 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 2.0 | 1.0 | none | OPTIMAL | 182.0 | 0.0 | 4 | 20.2 | 20.0 | -2.842171e-14 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 2.0 | 1.0 | none | OPTIMAL | 185.2667 | 0.0 | 4 | 20.2 | 20.2 | 3.266667 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 2.0 | 5.0 | none | OPTIMAL | 910.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 2.0 | 5.0 | none | OPTIMAL | 910.0 | 0.0 | 2 | 2.0 | 2.0 | -1.136868e-13 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 2.0 | 5.0 | none | OPTIMAL | 910.0 | -3.552714e-15 | 4 | 5.0 | 5.0 | 0.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 2.0 | 5.0 | none | OPTIMAL | 910.0 | -2.664535e-14 | 4 | 10.0 | 10.0 | -2.273737e-13 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 2.0 | 5.0 | none | OPTIMAL | 910.0 | -7.105427e-15 | 4 | 15.0 | 15.0 | -3.410605e-13 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 2.0 | 5.0 | none | OPTIMAL | 910.0 | -2.131628e-14 | 4 | 20.0 | 20.0 | -1.136868e-13 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 2.0 | 5.0 | none | OPTIMAL | 913.2667 | 0.0 | 4 | 20.2 | 20.2 | 3.266667 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 2.0 | 20.0 | none | OPTIMAL | 910.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 2.0 | 20.0 | none | OPTIMAL | 910.0 | 0.0 | 2 | 2.0 | 2.0 | -1.136868e-13 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 2.0 | 20.0 | none | OPTIMAL | 1038.4 | -9.769963e-15 | 4 | 4.55 | 4.55 | 128.4 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 2.0 | 20.0 | none | OPTIMAL | 1265.9 | -3.552714e-15 | 4 | 9.1 | 9.1 | 355.9 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 2.0 | 20.0 | none | OPTIMAL | 1552.8 | -7.105427e-15 | 4 | 12.94286 | 12.94286 | 642.8 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 2.0 | 20.0 | none | OPTIMAL | 1877.45 | 0.0 | 4 | 15.1 | 15.1 | 967.45 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 2.0 | 20.0 | none | OPTIMAL | 2331.96 | -3.552714e-15 | 4 | 18.12 | 18.12 | 1421.96 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 2.0 | 50.0 | none | OPTIMAL | 910.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 2.0 | 50.0 | none | OPTIMAL | 910.0 | 0.0 | 2 | 2.0 | 2.0 | -1.136868e-13 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 2.0 | 50.0 | none | OPTIMAL | 1229.65 | -9.769963e-15 | 4 | 4.55 | 4.55 | 319.65 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 2.0 | 50.0 | none | OPTIMAL | 1798.4 | -3.552714e-15 | 4 | 9.1 | 9.1 | 888.4 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 2.0 | 50.0 | none | OPTIMAL | 2585.657 | -7.105427e-15 | 4 | 12.94286 | 12.94286 | 1675.657 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 2.0 | 50.0 | none | OPTIMAL | 3557.45 | 0.0 | 4 | 15.1 | 15.1 | 2647.45 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 2.0 | 50.0 | none | OPTIMAL | 4917.96 | -3.552714e-15 | 4 | 18.12 | 18.12 | 4007.96 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 0.5 | 1.0 | relaxed_cyclic | OPTIMAL | 194.0 | missing | 0 | 21.4 | 20.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 0.5 | 1.0 | relaxed_cyclic | OPTIMAL | 194.0 | 0.0 | 2 | 21.4 | 20.0 | 0.0 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 0.5 | 1.0 | relaxed_cyclic | OPTIMAL | 194.0 | 0.0 | 4 | 21.4 | 20.0 | -2.842171e-14 | feasible_binding_gscr |  |
| GershgorinGSCR | 1.0 | 0.5 | 1.0 | relaxed_cyclic | OPTIMAL | 198.65 | 0.0 | 4 | 21.4 | 21.4 | 4.65 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 0.5 | 1.0 | relaxed_cyclic | OPTIMAL | 200.4333 | -8.881784e-16 | 4 | 21.4 | 21.4 | 6.433333 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 0.5 | 1.0 | relaxed_cyclic | OPTIMAL | 201.325 | 0.0 | 4 | 21.4 | 21.4 | 7.325 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 0.5 | 1.0 | relaxed_cyclic | OPTIMAL | 202.2167 | -8.881784e-16 | 4 | 21.4 | 21.4 | 8.216667 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 2.0 | 20.0 | relaxed_cyclic | OPTIMAL | 942.0 | missing | 0 | 2.0 | 2.0 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 2.0 | 20.0 | relaxed_cyclic | OPTIMAL | 942.0 | 0.0 | 2 | 2.0 | 1.16 | 0.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 0.5 | 2.0 | 20.0 | relaxed_cyclic | OPTIMAL | 1060.0 | 0.0 | 4 | 5.0 | 5.0 | 118.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 2.0 | 20.0 | relaxed_cyclic | OPTIMAL | 1310.0 | 0.0 | 4 | 10.0 | 10.0 | 368.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 2.0 | 20.0 | relaxed_cyclic | OPTIMAL | 1668.0 | -3.552714e-15 | 4 | 13.71429 | 13.71429 | 726.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 2.0 | 20.0 | relaxed_cyclic | OPTIMAL | 2012.0 | 0.0 | 4 | 16.0 | 16.0 | 1070.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 2.0 | 20.0 | relaxed_cyclic | OPTIMAL | 2493.6 | 0.0 | 4 | 19.2 | 19.2 | 1551.6 | feasible_gscr_changes_decision |  |
| NoGSCR | 0.0 | 1.0 | 5.0 | relaxed_cyclic | OPTIMAL | 930.0 | missing | 0 | 3.6 | 1.8 | missing | feasible_nonbinding_gscr |  |
| GershgorinGSCR | 0.0 | 1.0 | 5.0 | relaxed_cyclic | OPTIMAL | 930.0 | -2.700062e-15 | 3 | 3.6 | 1.8 | 0.0 | feasible_binding_gscr |  |
| GershgorinGSCR | 0.5 | 1.0 | 5.0 | relaxed_cyclic | OPTIMAL | 930.0 | -3.552714e-15 | 4 | 10.0 | 10.0 | -3.410605e-13 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.0 | 1.0 | 5.0 | relaxed_cyclic | OPTIMAL | 930.0 | 0.0 | 4 | 20.0 | 20.0 | -1.136868e-13 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 1.5 | 1.0 | 5.0 | relaxed_cyclic | OPTIMAL | 933.3333 | 0.0 | 4 | 20.0 | 20.0 | 3.333333 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 2.0 | 1.0 | 5.0 | relaxed_cyclic | OPTIMAL | 935.0 | -1.776357e-15 | 4 | 20.0 | 20.0 | 5.0 | feasible_gscr_changes_decision |  |
| GershgorinGSCR | 3.0 | 1.0 | 5.0 | relaxed_cyclic | OPTIMAL | 936.6667 | 0.0 | 4 | 20.0 | 20.0 | 6.666667 | feasible_gscr_changes_decision |  |

## Findings

- gSCR became binding: true
- gSCR changed objective or block decisions relative to matched NoGSCR baselines: true
- Infeasible runs: 0
- Storage terminal policy changes objective independently of gSCR when `:relaxed_cyclic` is used; the matching NoGSCR rows provide that baseline.
- Largest visible gSCR effect in this sweep: `gersh_none_g3.0_b0.5_c50.0` with delta objective 6899.986, GFM installed delta 15.31429, and GFM online delta 15.31429.
- The fixture remains useful for smoke/regression testing. Publication-style economics still require a stronger native synthetic case or regenerated PyPSA-derived fixtures with meaningful weak-grid structure.

## Recommendation

Use the identified binding rows as a compact regression/stress fixture, but still treat the case2-derived setup as a diagnostic toy case. For meaningful gSCR economics and plots, regenerate or curate larger fixtures with spatially separated GFL exposure and costly GFM support.
