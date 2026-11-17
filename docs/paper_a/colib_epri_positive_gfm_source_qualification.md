# Positive GFM source projection for the 840-hour technical LP

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
