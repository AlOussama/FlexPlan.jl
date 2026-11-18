# Positive GFM source projection and one-week technical comparison

Date: 2026-11-17. This is the separately identified `colib_epri_frozen_E_blocks_v1` planning proxy. It does not replace the original Full37 annual case or qualify a closed-loop EPRI controller, AC feasibility, fault current or dynamic stability.

The owner requested a positive CoLib/EPRI contribution, retained synchronous `x''d=0.25`, and selected comparable source models with the instruction **“bilde beide modelle gleich ähnlich aus”**, after the frozen-internal-voltage distinction and common block-count formulation were explained. Both source classes contribute through their active blocks, bounded by installed blocks. Installed inactive capacity receives no strength credit. Existing dispatch, storage, expansion caps, costs and UC semantics remain unchanged.

## Source and mathematical contract

The original [EPRI technical update 3002021403, December 2021](https://restservice.epri.com/publicdownload/000000003002021403/0/Product), sections 2-1/2-2, identifies a controlled voltage-source network interface. Table 2-1 specifies the series components `Rf=0.0015`, `Xf=0.15` on device MVA. Its source/current-control diagrams and table were visually inspected on PDF pages 12–14. The locally inspected 719,324-byte, 36-page PDF has SHA-256 `ca5827123ab36226956ef5e59706ac28365be3462863b377a45391d7e122f3d2`.

The [pinned CoLib entry](https://github.com/CRESYM/Colib_Quarto.github.io/blob/16d6171513fd1adf900d51a0ec664888d66b274a/models/4-HVDC/VSC/GridFormingConverter/EPRI-GFM-Converter/index.qmd) supplies the same R/X values. The existing [A3.5 source-boundary result](../../reports/a3_5/math_closure_20261020_repository_independent_adjudication.md) establishes a positive terminal stamp when the internal source voltage is fixed. It also shows that a freely eliminated internal source does not provide that stamp. This existing method is reused.

For a connected fixed-E series component, the common system-p.u. coefficient is

`b_block = (S_block/S_base) * X/(R^2 + X^2)`.

R and X use the same device MVA and referred-voltage bases and receive the same conversion factors. The existing purely reactive three-argument code path is preserved exactly. With R=0 it gives `S_block/(S_base*X)`.

| Source model | Device X | Device R | b for equal 25-MVA blocks / 100-MVA system |
|---|---:|---:|---:|
| Existing SYN class proxy | 0.25 | 0 in the retained reactive model | 1.0000000000 |
| EPRI fixed-E GFM class proxy | 0.15 | 0.0015 | 1.6665000167 |

The GFM value is not the resistance-free `1.6666666667`. The 25-MVA GFM class adopts dimensionless reference component values; this is a class-model assumption, not rebasing the same physical 100-MVA EPRI device. Actual SYN block ratings are preserved. For example, a 300-MVA SYN block retains b=12 on 100 MVA.

The G1 left side uses `sum(mu_str*b_block*n_active)` for these regular sources. GFM uses `mu_str=1`, `mu_fl=0`. The branch is counted once, outside passive B0. No separate transformer, virtual impedance, inertia-derived strength or GFL source credit is added. The same frozen-E component abstraction is used at each hourly operating point; it does not fix dispatch or active counts over the horizon.

## Independent qualification and bounded findings

Two separate read-only agents reviewed the physical source domain and the mathematical/code domain. They wrote no implementation files.

| Reviewer / receipt | Outcome |
|---|---|
| `/root/gfm_epri_phy_qual`, primary-source and Dynawo interface inspection | `PASS_SCOPED_SOURCE_COMPONENT`: the fixed-E series source is supported; no closed-loop controller or operational AC/fault qualification. |
| `/root/gfm_epri_math_qual`, original PDF and existing A3.5 proof | `CONDITIONAL_PASS_DESIGN` for the owner-selected fixed-E planning projection, with common bases and active-block credit. |
| First code differential review | `REPAIR_REQUIRED`: GFM-QA-01 required complete preflight before mutation; GFM-QA-02 required exercising the actual overlay API. |
| Bundled repair and focused independent recheck | `PASS_SCOPED_IMPLEMENTATION_AND_RUNNER_STATIC`. GFM-QA-01/02 closed: complete staging before mutation and actual API/content-preservation/negative tests inspected. Actual casebyte and LP acceptance remain separate. |

The EPRI report explicitly describes network iteration to maintain current limits. This prevents interpreting its fixed-E component stamp as an unrestricted closed-loop terminal stiffness. The [Dynawo implementation](https://github.com/dynawo/dynawo/blob/d9c57913aee5f5ba62f2441a8246fa318cc55b8b/dynawo/sources/Models/Modelica/Dynawo/Electrical/Controls/Converters/EpriGFM/EpriGFM.mo) independently confirms a controlled internal injector behind series R/X. No EPRI Appendix software was copied into the product or executed.

One additional, bounded controller-source discrepancy remains: original table 2-1 gives `Q_drp=0.045` (4.5%), whereas the pinned CoLib row gives `4.5` with unit `pu`. No equivalent alternative normalization was established. The LP does not import this controller parameter. Similarly, Dynawo example parameters differ from the original reference; model families are not mixed. These are limitations for a future full-controller qualification, not newly chosen planning parameters.

## Implementation and tests

- `src/core/paper_a_regional.jl`: explicit `voltage_behind_series_impedance_frozen_E` source kind and four-argument R/X projection. Required flags identify a planning proxy and deny physical controller equivalence. Native MVA and voltage transformations apply to both R and X.
- `src/core/paper_a_full37.jl`: `apply_paper_a_gfm_source_proxy!` first checks the authenticated parent AP1 identity and existing Full37 contract. It stages exactly 37 GFM candidates per snapshot, validates their proposed source fields, then applies the delta and advances the input profile digest. The mode is restricted to the existing 168-hour technical-week path; annual input admission remains unchanged.
- `test/paper_a_gfm_source_proxy.jl`: positive source/basis checks, actual 168-hour overlay, unchanged non-source fields, valid new profile digest and rejection without partial mutation of bad identities, missing candidates, invalid kV and unsupported scope.
- `scripts/paper_a/run_840h_frozen_E_lp.jl`: reuses the byte-pinned existing five-week common and crossover workflows. It creates distinct derived AP2 JSON bytes and SHA receipts, checks that non-source profile content remains identical, and runs only the continuous gSCR variant. It preserves the existing joint expansion/operation objective and quota.

Executed checks: 18 existing regional primitive assertions, 21 R/X/scope assertions, 14,295 actual overlay/content/negative assertions, and 11 fixed-E/production-G1 assertions passed. The last group verifies that the active GFM variable receives b, installed capacity alone receives none, and increasing an active source count increases the actual G1 left side. No solve is used in these component tests.

Local detailed evidence: `E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_FIVE_WEEKS_RE50_20261115_01/ROUNDING_DIAGNOSIS_20261117_01/GFM_EPRI_QUALIFICATION_20261117_01`. Large source PDFs, derived case data and raw solver outputs remain local.

## LP execution contract

The unchanged selected weeks are 8, 15, 27, 39 and 45 of 2013: 840 physical one-hour steps. Wind/PV positive injections must cover at least 50% of selected demand. Shared installed block counts and renewable expansion couple all five periods. The existing weekly outer SOC boundaries are retained.

OPEX, including startup/shutdown, is multiplied once by `8760/840 = 73/7`. Annualized CAPEX is counted once without that factor. The run relaxes integrality, uses no previous LP/MIP incumbent, keeps gSCR active, and has a maximum solver budget of 7,200 seconds. LP output remains continuous; no rounding is performed by the runner.

The saved candidate includes all primal variables with indices/bounds and symbolic coordinates, all 31,080 G1 bus-hour rows, actual native solver status/constraint/bound violations, original AP1 SHAs and distinct derived AP2 SHAs. A `FEASIBLE_POINT` label alone is insufficient. Numerical acceptance requires no independently recomputed primal violations above 1e-6 in model units, all G1 slacks at least -1e-6 pu, and native constraint/bound violations within 1e-6. Cost reconciliation and quota checks from the original workflow remain active. Feasibility and optimality are reported separately.

Runtime code SHA, actual case SHAs and results are added after the independent implementation recheck and execution. Neither this technical proxy nor an optimal LP grants Full37-year, Gate-J, F3, AC or dynamic acceptance.

## Execution continuation: one week first

The owner subsequently requested **one week with and without network-strength constraints first**. The 840-hour continuation is therefore deferred. KW 8 is selected as the first already qualified week. Both runs are LP relaxations with the same 50% Wind/PV quota and source/operating/cost parameters. The active formulation is the existing G1/gSCR sufficient condition; no separate SCR/eSCR formulation is introduced. The second run removes every G1 row and exports its values only as counterfactual diagnostics.

For this 168-hour study, actual OPEX annualization is `8760/168 = 52.142857142857146`; CAPEX is counted once. The authenticated source cases retain their parent-cohort marker `8760/840`. That provenance marker is not the multiplier used in the new study objective. The runner records the actual factor and 168-hour scope explicitly.

The initial 840-hour model construction at runtime `73ae452ae95851a848b589acf39bd4c6d4dfee06` ended before any optimizer call: the resource monitor stopped the process at 2,111.484 seconds when available physical RAM temporarily reached 2,076,893,184 bytes, just below its 2-GiB reserve. Commit headroom was still 15,714,328,576 bytes. Peak process private memory was 7,281,909,760 bytes. This was a monitor threshold event, not a solver infeasibility or demonstrated commit-memory exhaustion. Its source variants and failed-attempt logs are preserved.

All five derived case files nevertheless completed and received independent actual-byte PASS (`independent_case_byte_review.json`, SHA-256 `ca0d3806d96d63422d656e1fd7e2cd66cae0262deb7d26d9ca8d88d4943dac80`). The reviewer verified 31,080 positive GFM snapshot-devices, 150,360 unchanged SYN snapshot-devices and exact complete non-source content equality after the accepted PU importer. KW 8's actual AP2 SHA-256 is `c03dfc3cd78d68e0aeb8fb6875a3875e71db5d2c2efd8d680ba1904f95a79cfe`.

The continuation reuses these qualified prepared-PU bytes through `PAPER_A_PROXY_QUALIFIED_CASE_ROOT`, without another export or source-overlay application. The loader checks parent AP1 bytes, inherited review SHA, actual AP2 byte SHA and the recorded profile digest. It binds the input honestly as `ap2:sha256`, admitted only within the existing strictly validated 168-hour source-proxy scope. A real reader-only probe must succeed before the model run. `PAPER_A_PROXY_SINGLE_WEEK=8` selects the one-week pair in the same existing workflow.

A directly relevant postprocess delta was also corrected: `PaperADiagnostics.reconstruct` previously reconstructed the new R/X source as purely reactive. Its new subtype branch now independently evaluates the complex series admittance, retaining the existing voltage-base transformation and unchanged SYN path. This affects diagnosis only; the model/solver already used the correct R/X coefficient. Focused tests cover R>0, R=0, unequal native MVA/voltage bases, correct source stamps and unchanged SYN results. No old mathematical/conic solver suite is rerun for this postprocess repair.

The bounded continuation resource profile retains a 20-GiB process limit, 2-GiB commit reserve and 2-GiB E: reserve. Its physical-RAM reserve is 512 MiB, allowing normal Windows paging during temporary input-reading peaks. The solver budget remains at most 7,200 seconds per variant.

## Actual KW 8 LP comparison, 18 November 2026

Both joint expansion/dispatch LPs finished `OPTIMAL` (native Gurobi status 2) on 18–24 February 2013, 168 hourly steps. They use identical qualified AP2 bytes, cold starts and 50% positive Wind/PV injection divided by load. The objective is annualized CAPEX plus `(8760/168) * (generation + storage + startup/shutdown OPEX)`. Actual output root: `E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE50_GFM_FROZEN_E_20261118_01`.

| Quantity | With G1/gSCR | Without G1/gSCR |
|---|---:|---:|
| Annualized objective, billion EUR2025 | 98.619706096 | 97.551528967 |
| Annualized CAPEX, billion EUR2025 | 62.062737889 | 60.351397209 |
| Annualized OPEX, billion EUR2025 | 36.556968207 | 37.200131758 |
| New CCGT / OCGT, GW | 1.799133 / 0 | 1.874730 / 0 |
| New BESS GFL / GFM, GW | 7.270790 / 30.682728 | 16.970308 / 0 |
| New onshore wind / PV, GW | 343.419994 / 438.061454 | 343.300595 / 436.277457 |
| Gas dispatch in 168 h, TWh | 4.192861 | 4.560932 |
| Battery charge / discharge in 168 h, TWh | 1.529788 / 1.468597 | 0.689396 / 0.661820 |
| PHS charge / discharge in 168 h, TWh | 2.072406 / 1.554305 | 2.209661 / 1.657246 |
| Native solve time, s | 155.315 | 162.664 |
| Native maximum constraint violation | 3.056e-11 | 3.723e-10 |
| Native maximum bound violation | 2.987e-11 | 8.569e-11 |
| Active-model primal violations above 1e-6 | 0 | 0 |

The common weekly load is 71.058866 TWh and Wind/PV injection is 35.529433 TWh (50%). Complete carrier dispatch aggregates and receipt hashes are in the compact [versioned result receipt](receipts/kw08_re50_frozen_E_lp_20261118.json). The independent CSV replay gives maximum hourly system-balance residuals of 3.493e-8 MW and 3.655e-8 MW, respectively. Replayed objective residuals are below EUR 0.004. Both native LP bounds equal their objective values at the reported precision. These are LP bounds for this exact weekly proxy formulation, not bounds for an independently weighted year or a different model.

G1 adds EUR 1.068177130 billion/year (+1.094988%): CAPEX rises by EUR 1.711340680 billion/year and OPEX falls by EUR 0.643163550 billion/year. Of 6,216 G1 bus-hour rows, 942 are binding within 1e-6 pu at 25 buses and none is violated; minimum slack is -2.018e-12 pu. Removing these rows leaves 3,026 counterfactual violations, minimum -983.266908 pu. Those disabled rows do not invalidate the no-G1 solution. G1 is the implemented sufficient Gershgorin condition. Separate classical SCR/eSCR constraints and an exact spectral gSCR test were not introduced by this comparison.

Runtime producer commit: `becec6d63c0fbf2b8a160c41f87631f5270046b9`; consumer commit: `89897ee8b0caa8a54533b0fb03fa61b6adb1bd88`. The source variant was created at consumer `73ae452ae95851a848b589acf39bd4c6d4dfee06`. The actual runner SHA-256 was `8f2d168f74e26deda62bdced90e83f8a15f41f2a049238044ad2ab4ea787e3c5`. The separately reviewed KW8 case-byte receipt has SHA-256 `9b35bc7616b555224a5fc72db135804ce7f7c4c0b508f906652a95b4af5ea0f7`; the successful real-reader probe has SHA-256 `e27416e65cc589c61e21719d0483e0d4e860b4e0198886ca1bd3d143366800ce`.

The pre-existing, already tested producer memory-export commit is now also remotely reachable on [`codex/paper-a-q5-memory-139`](https://github.com/AlOussama/PyPSA2MatpowerX/tree/codex/paper-a-q5-memory-139), with remote SHA `becec6d63c0fbf2b8a160c41f87631f5270046b9` verified by `ls-remote`. The unpublished delta was 40 source-code lines in two files, containing no original data. The existing dirty Q4 hunk in `src/block_gscr_converter.jl` was not edited or included in the push; the producer HEAD and untracked evidence remain in place.

The pair exited normally in 539.484 wall seconds. Sampled peak private memory was 4,267,048,960 bytes and peak working set 3,255,623,680 bytes; no resource guard fired. Raw case/dispatch/primal/log files remain on E:. No integer rounding or integer optimization occurred in this LP pair. All comparisons are restricted to the owner-selected fixed-E planning proxy.

The separate mathematical/code reviewer accepted the saved results as `PASS_SCOPED_LP_RESULT_REVIEW`, receipt SHA-256 `98f1d2c3a567cf4a2570a8f59ff7c8466bb0f74bebc96688872bbe3acce7b026`. The review independently replays original load profiles, physical generation/storage dispatch prices, startup/shutdown variables and their block-MW event rates, investment coefficients, annualization, native bounds and G1 exports. No model or solver was run by the result reviewer. All 311,395 original JuMP variables are saved once with finite values. This is not a complete native-Gurobi auxiliary vector: the backend has 8,736 extra columns whose exact bridge mapping was not archived. The 12,432 new-renewable dispatch variables have values in the full vector and asset/time dispatch CSVs, but lack direct symbolic index-coordinate rows. These bounded archive limitations do not affect the independently reconciled energy/cost result; the receipt does not claim complete native auxiliary reconstruction.

## Owner-authorized integer continuation

After the LP comparison, the owner requested the same pair without LP relaxation. `PAPER_A_PROXY_INTEGRALITY=integer` reuses the existing integer branch, preserving installed/active/source/event integrality and leaving renewable MW expansion continuous as already specified. It skips automatic LP fallback, clears solver starts between variants, and retains the same case, quota and annualization. Each MIP has a 7,200-second budget and the existing 0.5% relative-gap target. Native `IntVio`, integer/binary flags in the complete primal CSV and independent integer residuals are recorded. Integer feasibility is checked at 1e-6; solver `IntFeasTol=1e-8` is stricter than that acceptance threshold. No LP-derived variable bounds or rounded incumbent are imposed. Actual MIP outcomes are added after execution and independent result review.

The 50% MIP pair uses the archived exact runner bytes from `d11f3f3e8376768d97e08f339990c6bb489e6ce5` (SHA-256 `04a369470b8e53565b5e175f2b8977567b9498b13d50334750dae4f572313dbc`) under `E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE50_GFM_FROZEN_E_MIP_20261118_01`. Its separate `PASS_SCOPED_RUNNER_DELTA` receipt has SHA-256 `8a3cc0e0575715a77c8b8a67735210946986bb7024b83942631a704378dae7d7`, and the inherited exact-case byte gate has SHA-256 `a17718c92a6393f7c4a5489a0bfa209e4f0fd2f2b30a3d2f3505890dd0d132f5`. Both were written by the independent reviewer before optimization. They grant this bounded technical run, not result acceptance.

Both 50% MILPs subsequently reached the configured gap target and passed independent saved-result replay. `independent_result_review.json` has SHA-256 `82d75f5b9e65cfa91170b0412612bd49a395d53381486aa4183a22d16fbde987`.

| 50% MILP result | With G1 | Without G1 |
|---|---:|---:|
| Objective, billion EUR2025/year | 98.998127117 | 97.566598150 |
| Native lower bound, billion EUR2025/year | 98.619706096 | 97.551528967 |
| Actual relative gap | 0.3822507% | 0.0154450% |
| CCGT / OCGT expansion, GW | 1.840500 / 4.200000 | 1.840500 / 0 |
| BESS GFL / GFM expansion, GW | 7.300000 / 33.525000 | 16.975000 / 0 |
| Onshore / PV expansion, GW | 341.283182 / 442.799946 | 344.307199 / 434.410593 |
| Gas generation in 168 h, TWh | 4.164204 | 4.542495 |
| BESS charge / discharge in 168 h, TWh | 1.596535 / 1.532673 | 0.686437 / 0.658979 |
| Native solve time, s | 2948.019 | 288.012 |
| Integer residual, native and exported | 0 | 0 |
| Active-model violations above 1e-6 | 0 | 0 |

These are gap-qualified feasible plans; the investment mix is not certified at exact zero gap. Relative to its LP, the with-G1 plan costs EUR 378.421021 million/year more. Its larger gas portfolio therefore must not be described as a uniquely optimal consequence of G1. The difference between the two reported integer-plan costs is EUR 1.431528967 billion/year. All 311,395 original variables, including the 12,432 new-renewable dispatch coordinates, are now fully indexed. Without G1, 3,004 counterfactual G1 rows are negative; the actual model remains feasible.

The common CCGT addition is nine 204.5-MW blocks at `NO2 0`. The with-G1 plan additionally builds fourteen 300-MW OCGT blocks at ten buses. Their combined generation is only 1.920 GWh in the week (0.457 equivalent full-load hours, 0.272% utilization); total gas generation is predominantly CCGT. A read-only check of installed versus hourly active counts finds no newly installed gas capacity above the observed active-count peak: every added block is used in at least one hour. This documents the rare-hour role of those OCGT additions without claiming that their exact portfolio is globally necessary or uniquely optimal. The diagnostic is retained as `gas_capacity_utilization_diagnosis.json` in the MIP50 output root.

The with-G1 trace has no incumbent until its root heuristic finds the reported plan at 2,947 seconds, immediately reaching 0.3823%. The no-G1 trace improves from a very poor feasible plan (86.8% gap at 252 seconds) to 0.0154% at 287 seconds. The first variant's original builder default start was rejected at row R18573 by 0.040824829 model units; this was not a reused LP plan or model infeasibility. The second variant used a fresh optimizer with cleared starts. The independent initialization note has SHA-256 `b27d0e5b71f9e44d39cd0abd31d56064bb6f374d631993fd57ae4fac06cea289`. The pair exited normally in 3,506.734 wall seconds, peak private memory 5,556,383,744 bytes, peak working set 3,684,007,936 bytes, no resource guards.

## Additional 60% and 70% comparisons

The owner subsequently authorized LP and MILP pairs with and without G1 at both 60% and 70%, after completing the 50% pair. The same workflow accepts `PAPER_A_PROXY_WIND_PV_QUOTA_PCT=50|60|70`; default is 50. Only the lower bound on positive Wind/PV injection divided by total 168-hour demand changes, together with matching summary and replay checks. The annual factor remains `8760/168`, CAPEX remains once, and input profiles, prices and source assumptions are unchanged. All quota cases begin cold, without borrowing another quota's plan or modifying discrete-variable bounds.

The additional output root is `E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE60_70_FROZEN_E_20261118_01`. Execution order: 50% integer pair, 60% LP pair, 60% integer pair, 70% LP pair, 70% integer pair. LP pairs use up to 7,200 solver seconds per variant; each MILP retains the same 7,200-second limit and 0.5% gap target. A time-limited integer witness is reported with its actual bound/gap; absence of a witness is reported explicitly. Such an outcome does not suppress the independently authorized other quota runs. All pending outcomes remain unaccepted until their actual numerical and independent result checks complete.

The 60% LP pair is complete and independently accepted (`quota_60/relaxed/independent_result_review.json`, SHA-256 `0bcce35812babb0dfcc3957913efbae1a2b99f3d9cd3daf00029358cdb339333`). Both native statuses are `OPTIMAL`, bounds equal objectives, all active-model violations are below 1e-6, and positive Wind/PV injection is exactly 60% of load.

| 60% LP result | With G1 | Without G1 |
|---|---:|---:|
| Annualized cost, billion EUR2025 | 111.395759439 | 109.730971330 |
| Annualized CAPEX / OPEX, billion EUR2025 | 86.782272332 / 24.613487108 | 84.708983069 / 25.021988261 |
| Gas expansion, GW | 1.724421 | 1.811264 |
| BESS GFL / GFM expansion, GW | 37.270316 / 56.094183 | 76.297822 / 0 |
| Onshore / PV expansion, GW | 457.061804 / 620.166645 | 459.515013 / 603.455024 |
| Gas generation in 168 h, TWh | 1.503129 | 1.718438 |
| BESS charge / discharge in 168 h, TWh | 3.546705 / 3.404837 | 2.716798 / 2.608126 |

The 60% LP pair exited normally in 435.984 seconds with peak private memory 4,269,821,952 bytes and no guards. All remaining pairs subsequently completed and passed independent review. The final [50/60/70% result report](kw08_re50_60_70_joint_expansion_dispatch.md) and its [machine-readable index](receipts/kw08_re50_60_70_joint_results_20261118.json) contain all twelve results, actual capacity/dispatch/cost comparisons and their review/resource receipts. Every MILP reached the configured 0.5% gap target; no solver fallback was needed.

The 70% MILP objectives are EUR 127.818618545 billion/year with G1 and EUR 125.055972701 billion/year without G1, gaps 0.367897965% and 0.052967773%, respectively. The final pair review has SHA-256 `a420186466f44b8f85a48ace151aeedb22c6af6e1d06720a421a5d1c275843a6`. QREF selects 70% as the highest requested qualified reference, receipt SHA-256 `971c4bac09ed5f859a7a4a07d378a4fa8a8d5314f12284a1ef57290be7f06b34`.

## Conditional comparison of strength formulations

After these quota runs, the owner requested a comparison of different gSCR/SCR/eSCR conditions at the highest converged RE level. The owner explicitly selected the criterion: a numerically accepted integer plan and achieved relative gap at most 0.5%; if none qualifies, no additional constraint comparison is performed yet. The reference for selecting the highest quota is the MILP with active gSCR. LP optimality alone does not trigger this continuation.

A separate read-only inventory prepares that continuation without changing the current G1 runs. It maps existing mathematical definitions and partial implementations to executable formulation selectors, postsolve metrics and their remaining integration requirements. The owner explicitly confirmed that many conditions are already formulated; those definitions and implementations are reused. The current helper inserts new Wind/PV expansion exposure directly into G1 rows; another selector cannot be substituted without separately checking the same new-renewable exposure in its shared p/S/M input. Classical SCR/eSCR variants use their specified source/fault conventions and are kept distinct from the G1 Gershgorin condition. A missing integrated selector does not imply that its mathematical definition is absent. Exact readiness findings, existing mathematical-source pointers and code paths are recorded under the additional output root's `STRENGTH_CONSTRAINT_COMPARISON_READINESS`. No extra formulation optimization is started before the owner-selected convergence condition is met.
