# AP2 partial validation — 2026-10-19

Repository API read succeeded; FlexPlan master verified as `991d0e99627b9bd57b3df476c66141ae6bb5163d`; AP1 producer branch verified at `00b259da66f084e00d53c5dc1be4d23de145fdc1`. The producer status remains AP1_partial; its file explicitly labels economic_data_valid and theorem_domain_valid unverified.

## Test declarations, NOT EXECUTED
- New standalone Julia test: `julia --project=. test/paper_a_regional.jl`.
- New tests check analytic 3-bus Schur, no-elimination, invalid eliminated block/asymmetry, base scaling, mixed fixed/online strength, non-unit mu, GFL nameplate, independent connection/resource values, temporal weights, SYN mode and SC refusal.
- Julia runtime: unavailable; solver: unavailable. No numerical Julia test pass, objective value, optimizer version, numerical solve residual, or integrated model acceptance is claimed.
- New module is not included from `src/FlexPlan.jl`, and no template / optimization integration has occurred. Existing test suite not run.

## Unverified study evidence
True source reactances/time scales, representative event repetitions, annualized battery P+E costs, valid fixed network shunt/grounding/SC cost metadata and AP1 real fixture regeneration not verified. No invented values imported.

## Blockers
Main AP2 integration, physical network positive-sequence Y, economic objective corrections, compatibility regression, and AP1 producer reconciliation remain open. AP3 and AP4 are blocked.
