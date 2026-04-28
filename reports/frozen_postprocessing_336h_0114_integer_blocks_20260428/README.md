# Frozen Post-Processing State

- Frozen at: 2026-04-28 Europe/Berlin
- Project root: D:\Projekte\Code\FlexPlan_UC_GSCR
- Git branch: feature/post_processing
- Git HEAD: f0792ee91c1bb3ab83c6b8cbee8bf4329572b87d
- Selected result source: reports/paper_elec_s_37_campaign_336h_0114_integer_blocks
- Frozen result copy: reports/frozen_postprocessing_336h_0114_integer_blocks_20260428/results
- Dataset source: D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr\elec_s_37_2weeks_from_0114\case.json
- Dataset period: 2013-01-14 00:00:00 to 2013-01-27 23:00:00
- Horizon: 336 hourly snapshots, two weeks
- Block policy: integer block variables, relax_block_variables=false
- Scenarios frozen: g_min=0.0, 1.0, 1.5

## Scenario Status
- BASE-INTEGER: status=OPTIMAL, cost_BEUR_per_year=7.23003125e-6, min_gSCR=2.9999999999999956, min_mu_alpha_1p5=222.7459915986271, solve_min=0.4022166689236959
- gSCR-GERSH-1p0-INTEGER: status=OPTIMAL, cost_BEUR_per_year=7.23003125e-6, min_gSCR=2.999999999999998, min_mu_alpha_1p5=222.74590977191215, solve_min=1.0232833305994669
- gSCR-GERSH-1p5-INTEGER: status=OPTIMAL, cost_BEUR_per_year=7.23003125e-6, min_gSCR=2.999999999999997, min_mu_alpha_1p5=222.747225996884, solve_min=5.118016668160757

## Freeze Contents
- results/: copied campaign result artifacts used for post-processing
- result_file_hashes.csv: SHA256 hashes for frozen result files
- git_head.txt, git_branch.txt, git_status_short.txt: project state metadata
- relevant_code_diff.patch: uncommitted relevant code/script diff at freeze time
- git_diff_excluding_reports.patch: full non-report diff at freeze time

Post-processing should read from the frozen result copy unless explicitly redirected.
