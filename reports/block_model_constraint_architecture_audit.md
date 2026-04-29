# Block UC/CAPEXP + gSCR Architecture Audit

## Scope
This audit inventories variables, bounds, constraints, and objective terms in the current block UC/CAPEXP + gSCR integration path, with focus on overlap between standard PowerModels/FlexPlan logic and block-scaled logic.

Primary target: find cases where standard bounds/constraints remain active for block-enabled devices and may conflict with block envelopes.

## Audited Files and Functions

### Integration builder
- `src/prob/uc_gscr_block_integration.jl`
  - `build_uc_gscr_block_integration` (line 52)
  - `objective_min_cost_uc_gscr_block_integration` (line 167)
  - `constraint_uc_gscr_block_bus_active_balance` (line 199)
  - `constraint_uc_gscr_block_system_active_balance` (line 219)

### Block variables and constraints
- `src/core/block_variable.jl`
  - `variable_uc_gscr_block` (line 24)
  - `variable_installed_blocks` (line 51)
  - `variable_active_blocks` (line 113)
  - `variable_block_startup_shutdown_counts` (line 162)
  - `constraint_active_blocks_le_installed` (line 221)
  - `constraint_block_count_transitions` (line 257)
  - `constraint_block_minimum_up_time` (line 320)
  - `constraint_block_minimum_down_time` (line 356)
- `src/core/constraint_template.jl`
  - `constraint_uc_gscr_block_dispatch` (line 140)
  - `constraint_uc_gscr_block_active_dispatch_bounds` (line 159)
  - `constraint_uc_gscr_block_reactive_dispatch_bounds` (line 235)
  - `constraint_uc_gscr_block_storage_bounds` (line 293)
  - `constraint_uc_gscr_block_storage_energy_capacity` (line 313)
  - `constraint_uc_gscr_block_storage_charge_discharge_bounds` (line 349)
  - `constraint_gscr_gershgorin_sufficient` (line 415)
- `src/core/constraint.jl`
  - `constraint_uc_gscr_block_active_dispatch_bounds` (line 123)
  - `constraint_uc_gscr_block_reactive_dispatch_bounds` (line 143)
  - `constraint_uc_gscr_block_storage_energy_capacity` (line 208)
  - `constraint_uc_gscr_block_storage_charge_discharge_bounds` (line 231)
  - `constraint_gscr_gershgorin_sufficient` (line 303)

### Storage and candidate storage
- `src/core/storage.jl`
  - candidate variables: `variable_storage_power_real_ne` (47), `variable_storage_energy_ne` (124), `variable_storage_charge_ne` (140), `variable_storage_discharge_ne` (156), `variable_storage_indicator` (172), `variable_storage_investment` (195)
  - candidate constraints: `constraint_storage_thermal_limit_ne` (224/413), `constraint_storage_losses_ne` (229/437), `constraint_storage_bounds_ne` (235/556), `constraint_storage_state_ne` (252/483), `constraint_storage_state_final_ne` (307/499), `constraint_storage_excl_slack_ne` (316/546), `constraint_ne_storage_activation` (382/613)
  - existing storage local wrappers: `constraint_storage_state_final` (302/493), `constraint_storage_excl_slack` (312/536)

### Objective
- `src/core/objective.jl`
  - `calc_uc_gscr_block_investment_cost` (285)
  - `calc_uc_gscr_block_startup_shutdown_cost` (326)
  - `calc_ne_storage_cost` (469)

### Reference extension
- `src/core/ref_extension.jl`
  - `ref_add_uc_gscr_block!` (76)
  - `_validate_uc_gscr_block_devices`
  - `_add_uc_gscr_device_maps!`
  - `_add_uc_gscr_row_metrics!`

### Standard PowerModels functions that remain active
- `C:/Users/User/.julia/packages/PowerModels/LnSmr/src/core/variable.jl`
  - `variable_gen_power_real` (267), `variable_gen_power_imaginary` (284)
  - `variable_branch_power_real` (405)
  - `variable_dcline_power_real` (675)
  - `variable_storage_power_real` (918), `variable_storage_energy` (996), `variable_storage_charge` (1015), `variable_storage_discharge` (1034)
- `C:/Users/User/.julia/packages/PowerModels/LnSmr/src/core/constraint_template.jl`
  - `constraint_power_balance` (171)
  - `constraint_storage_thermal_limit` (845)
  - `constraint_storage_losses` (877)
  - `constraint_storage_state` (886/899)
  - `constraint_dcline_power_losses` (934)
  - `constraint_dcline_setpoint_active` (946)
- `C:/Users/User/.julia/packages/PowerModels/LnSmr/src/core/constraint.jl`
  - `constraint_dcline_power_losses` (120)
  - `constraint_dcline_setpoint_active` (128)
  - `constraint_storage_thermal_limit` (193)
  - `constraint_storage_state_initial` (203)
  - `constraint_storage_state` (211)
- `C:/Users/User/.julia/packages/PowerModels/LnSmr/src/form/apo.jl`
  - `constraint_power_balance` (58)
  - `constraint_storage_thermal_limit` (270)
  - `constraint_storage_losses` (284)
- `C:/Users/User/.julia/packages/PowerModels/LnSmr/src/core/ref.jl`
  - `ref_calc_storage_injection_bounds` (156)

## Variable Inventory

| Variable | Component | Index set | Source | Bounds | Bound source | Type | Time scope | Block-affected |
|---|---|---|---|---|---|---|---|---|
| `pg` | gen | `(nw, gen)` | PM `variable_gen_power_real` | `pmin <= pg <= pmax` | standard data | continuous | snapshot | yes (also bounded by block dispatch for block gens) |
| `qg` | gen | `(nw, gen)` | PM `variable_gen_power_imaginary` | `qmin <= qg <= qmax` | standard data | continuous | snapshot | yes (only in non-active-power formulations) |
| `p` | branch arc | `(nw, l,i,j)` | PM `variable_branch_power_real` | branch flow bounds via `ref_calc_branch_flow_bounds` | standard branch ratings | continuous | snapshot | no direct block coupling |
| `p_dc` | dcline arc | `(nw, l,i,j)` | PM `variable_dcline_power_real` | `pminf/pmaxf`, `pmint/pmaxt` | standard dcline data | continuous | snapshot | no |
| `ps` | storage | `(nw, storage)` | PM `variable_storage_power_real` | injection bounds from thermal/current ratings | standard storage/bus ratings | continuous | snapshot | indirect (block limits `sc/sd`, not `ps` directly) |
| `se` | storage | `(nw, storage)` | PM `variable_storage_energy` | `0 <= se <= energy_rating` | standard storage rating | continuous | snapshot | yes (also `se <= e_block*n_block` for block storage) |
| `sc` | storage | `(nw, storage)` | PM `variable_storage_charge` | `0 <= sc <= charge_rating` | standard storage rating | continuous | snapshot | yes (also `sc <= p_block_max*na_block`) |
| `sd` | storage | `(nw, storage)` | PM `variable_storage_discharge` | `0 <= sd <= discharge_rating` | standard storage rating | continuous | snapshot | yes (also `sd <= p_block_max*na_block`) |
| `ps_ne` | ne_storage | `(nw, ne_storage)` | local `variable_storage_power_real_ne` | injection bounds from `ref_calc_storage_injection_bounds` then thermal tightening | standard candidate storage ratings | continuous | snapshot | indirect |
| `qs_ne` | ne_storage | `(nw, ne_storage)` | local `variable_storage_power_imaginary_ne` | reactive + injection bounds | standard candidate ratings | continuous | snapshot | yes in reactive formulations |
| `se_ne` | ne_storage | `(nw, ne_storage)` | local `variable_storage_energy_ne` | `0 <= se_ne <= energy_rating` | standard candidate rating | continuous | snapshot | yes (also block envelope) |
| `sc_ne` | ne_storage | `(nw, ne_storage)` | local `variable_storage_charge_ne` | `0 <= sc_ne <= charge_rating` | standard candidate rating | continuous | snapshot | yes (also block envelope) |
| `sd_ne` | ne_storage | `(nw, ne_storage)` | local `variable_storage_discharge_ne` | `0 <= sd_ne <= discharge_rating` | standard candidate rating | continuous | snapshot | yes (also block envelope) |
| `z_strg_ne` | ne_storage build status | `(first nw per hour/scenario, ne_storage)` shared | local `variable_storage_indicator` | `[0,1]` (relaxed in builder) | standard candidate-build logic | continuous in this builder | investment-wide | yes (no direct coupling to `n_block`) |
| `z_strg_ne_investment` | ne_storage investment decision | same sharing as above | local `variable_storage_investment` | `[0,1]` (relaxed in builder) | standard candidate-build logic | continuous in this builder | investment-wide | yes (used by standard candidate cost only) |
| `n_block` | block device count | `(device_key)` shared across snapshots | `variable_installed_blocks` | `n0 <= n_block <= nmax` | block data | integer/continuous(relaxed) | investment-wide | core block variable |
| `na_block` | active block count | `(nw, device_key)` | `variable_active_blocks` | `na_block >= 0`, plus `na_block <= n_block` | block data | integer/continuous(relaxed) | snapshot | core block variable |
| `su_block` | startup block count | `(nw, device_key)` | `variable_block_startup_shutdown_counts` | `su_block >= 0` | block data | integer/continuous(relaxed) | snapshot | core block variable |
| `sd_block` | shutdown block count | `(nw, device_key)` | `variable_block_startup_shutdown_counts` | `sd_block >= 0` | block data | integer/continuous(relaxed) | snapshot | core block variable |
| gSCR LHS/RHS expressions | bus, gfm/gfl devices | `(nw, bus)` | `constraint_gscr_gershgorin_sufficient` | affine inequality only | block data (`b_block`, `p_block_max`, `g_min`) | expression | snapshot | core block variable usage (`na_block`) |

## Constraint Inventory

### Standard constraints active in this builder

| Constraint | Source | Form | Component | Variables | Uses standard ratings | Active for block-enabled | Conflict risk | Proposed action |
|---|---|---|---|---|---|---|---|---|
| Bus active power balance | PM template + APO form | `sum(branch)+sum(dcline)+... = sum(pg)-sum(ps)-load-shunt` | bus | `p,p_dc,pg,ps` | no (uses variables) | yes | low | keep |
| Dcline loss equation | PM core | `(1-loss1)*p_fr + (p_to-loss0)=0` | dcline | `p_dc` | dcline params only | yes | low | keep |
| Dcline setpoint equation | PM core/template | `p_fr=pf, p_to=pt` | dcline | `p_dc` | setpoint data | **not called** | none | keep not-used |
| Gen variable bounds | PM variable | `pmin<=pg<=pmax`, `qmin<=qg<=qmax` | gen | `pg,qg` | yes | yes | medium/high if block capacities exceed standard `pmax/qmax` | skip for block-enabled or widen at variable creation |
| Storage thermal limit (existing) | PM template/APO | tightens `ps` to rating | storage | `ps` | yes (`thermal_rating`) | yes | medium | modeling decision; likely keep |
| Storage loss equation (existing) | PM template/APO | `ps + (sd-sc) == p_loss + r*ps^2` (APO) | storage | `ps,sc,sd` | params only | yes | low | keep |
| Storage state equation (existing) | PM template + local wrapper | intertemporal `se` balance | storage | `se,sc,sd` | initial `energy` | yes | low | keep |
| Storage final state (existing) | local | `se_T >= energy` | storage | `se` | initial energy | yes | high for strict policy | needs modeling decision (policy gating) |
| Storage excl slack (existing) | local | `sc+sd <= max(ub(sc),ub(sd))` | storage | `sc,sd` | yes via variable UBs | yes | medium | keep for non-block; modify for block-enabled if needed |
| Candidate storage thermal limit | local APO | tightens `ps_ne` to `±thermal_rating` | ne_storage | `ps_ne` | yes | yes | medium/high with zero ratings | skip or condition for block-enabled |
| Candidate storage losses | local APO | `ps_ne + (sd_ne-sc_ne) == p_loss` | ne_storage | `ps_ne,sc_ne,sd_ne` | params only | yes | low | keep |
| Candidate storage bounds (z-coupled) | local | each var bounded by `var_ub * z_strg_ne` | ne_storage | `se_ne,sc_ne,sd_ne,ps_ne,qs_ne,z_strg_ne` | yes (through var UBs from standard ratings) | yes | **critical** with zero ratings | replace for block-enabled with block-z coupling |
| Candidate storage state | local | intertemporal `se_ne` balance with `z_strg_ne` inflow/outflow scaling | ne_storage | `se_ne,sc_ne,sd_ne,z_strg_ne` | initial energy | yes | low | keep |
| Candidate storage final | local | `se_ne_T >= energy*z_strg_ne` | ne_storage | `se_ne,z_strg_ne` | initial energy | yes | high for strict policy | needs modeling decision |
| Candidate activation | local | `z_strg_ne == sum(z_strg_ne_investment over horizon)` | ne_storage | `z_strg_ne,z_strg_ne_investment` | no | yes | medium (parallel investment logic with `n_block`) | add explicit coupling or disable one path |

### Block-specific constraints

| Constraint | Source | Form | Component | Variables | Standard or block | Active for block-enabled | Uses standard ratings | Conflict risk | Proposed action |
|---|---|---|---|---|---|---|---|---|---|
| Installed block bounds | `block_variable.jl` | `n0 <= n_block <= nmax` | gen/storage/ne_storage | `n_block` | block | yes | no | low | keep |
| Active block bounds | `block_variable.jl` | `0 <= na_block <= n_block` | gen/storage/ne_storage | `na_block,n_block` | block | yes | no | low | keep |
| Startup/shutdown transitions | `block_variable.jl` | `na_t-na_{t-1}=su_t-sd_t` (`na0` at first) | gen/storage/ne_storage | `na_block,su_block,sd_block` | block | yes | no | low | keep |
| Min up/down block counts | `block_variable.jl` | windowed sums on `su_block/sd_block` | gen/storage/ne_storage | `su_block,sd_block,na_block,n_block` | block | conditional | no | low | keep |
| Block active dispatch | `constraint.jl` | `p_min_pu*p_block_max*na <= p <= p_max_pu*p_block_max*na` | gen | `pg,na_block` | block | yes | no | medium with standard `pg` bounds | keep + relax/skip standard bounds for block-enabled gen |
| Block reactive dispatch | `constraint.jl` | `q_block_min*na <= q <= q_block_max*na` | gen/storage/ne_storage | `q* ,na_block` | block | active only where q vars exist | no | medium | keep |
| Block storage energy envelope | `constraint.jl` | `se <= e_block*n_block` / `se_ne <= e_block*n_block` | storage/ne_storage | `se/se_ne,n_block` | block | yes | no | high overlap with standard rating UBs | keep + skip/replace standard rating UBs for block-enabled |
| Block storage charge/discharge envelopes | `constraint.jl` | `sc/sd <= p_block_max*na` (and `_ne`) | storage/ne_storage | `sc,sd,sc_ne,sd_ne,na_block` | block | yes | no | high overlap with standard rating UBs | keep + skip/replace standard rating UBs for block-enabled |
| gSCR Gershgorin sufficient | `constraint.jl` | `sigma0 + Σ(b_block*na_gfm) >= g_min*Σ(p_block_max*na_gfl)` | bus/device groups | `na_block` | block | yes | no | low | keep unchanged |

## Objective-Term Inventory

| Term | Source | Expression | Applies to | Risk |
|---|---|---|---|---|
| Generation operating cost | `calc_gen_cost` | linear `cost*pg` | all gens, all snapshots | low |
| Standard candidate storage investment cost | `calc_ne_storage_cost` | `(eq_cost+inst_cost+co2)*z_strg_ne_investment` | `ne_storage` | **double-count risk** with block investment when same assets are block-enabled |
| Block investment cost | `calc_uc_gscr_block_investment_cost` | `cost_inv_block*p_block_max*(n_block-n0)` | block-enabled gen/storage/ne_storage | **double-count risk** with standard `ne_storage` cost |
| Block startup/shutdown cost | `calc_uc_gscr_block_startup_shutdown_cost` | `startup_block_cost*su_block + shutdown_block_cost*sd_block` | all block-enabled devices | low |

## Conflict Matrix

| Conflict row | Current status | Severity | Proposed action |
|---|---|---|---|
| `pg` standard `pmax` vs `p_block_max*na_block` | both active for block-enabled gen | medium/high | modify variable upper/lower bounds for block-enabled gen (or skip standard gen bounds) |
| `qg` standard `qmax/qmin` vs block `q` bounds | both active where reactive model used | medium | skip standard q bounds for block-enabled or align data mapping |
| `se` standard `energy_rating` vs `e_block*n_block` | both active for block-enabled storage | high | skip/modify standard `se` UB for block-enabled storage |
| `sc` standard `charge_rating` vs `p_block_max*na_block` | both active for block-enabled storage | high | skip/modify standard `sc` UB for block-enabled storage |
| `sd` standard `discharge_rating` vs `p_block_max*na_block` | both active for block-enabled storage | high | skip/modify standard `sd` UB for block-enabled storage |
| `se_ne` standard `energy_rating*z_ne` vs `e_block*n_block` | both active; standard can force zero | **critical** | replace `constraint_storage_bounds_ne` for block-enabled with block-based z-coupling |
| `sc_ne` standard `charge_rating*z_ne` vs `p_block_max*na_block` | both active; standard can force zero | **critical** | replace/skip standard for block-enabled candidate storage |
| `sd_ne` standard `discharge_rating*z_ne` vs `p_block_max*na_block` | both active; standard can force zero | **critical** | replace/skip standard for block-enabled candidate storage |
| `z_strg_ne` build logic vs `n_block` investment logic | both present, no explicit coupling | high | add explicit coupling or choose one investment formalism |
| standard `ne_storage` investment cost vs block investment cost | both present | high | skip `calc_ne_storage_cost` for block-enabled `ne_storage` |
| strict final storage constraint vs relaxed/no-final/aggregate policy | strict path can make 24h infeasible | high | needs modeling decision + policy switch in builder |
| standard UC status/startup vs `su_block/sd_block` | standard UC not active in this builder | low | keep as-is; no duplication currently |

## Key Findings

1. Critical candidate-storage overlap exists at both variable bound creation and z-coupled standard bounds:
- `variable_storage_energy_ne`, `variable_storage_charge_ne`, `variable_storage_discharge_ne` set UBs from standard ratings.
- `constraint_storage_bounds_ne` re-imposes those UBs multiplied by `z_strg_ne`.
- For PyPSA candidates with zero standard ratings, block envelopes cannot unlock charge/discharge/energy.

2. Existing storage (`storage`) has the same overlap pattern (standard rating UBs + block envelopes), though less severe when standard ratings are nonzero.

3. Block-enabled `ne_storage` has duplicated investment semantics:
- build indicator/investment via `z_strg_ne`/`z_strg_ne_investment`
- installed capacity via `n_block`
- objective includes both standard and block investment terms.

4. Standard PowerModels bus balance and dcline-loss constraints are active and consistent with required modeling conventions; dcline setpoint constraints are available but not called.

5. gSCR/Gershgorin implementation is cleanly separated from power-balance and storage dynamics, and uses only block activity variables and block coefficients.

## Proposed Code Changes (Not Applied)

### 1. Block-aware standard bound gating for storage/ne_storage
- At variable creation:
  - For block-enabled `storage`/`ne_storage`, do not set `se/sc/sd` UBs from standard ratings.
  - Keep LB at zero.
- At constraint level:
  - Skip standard `constraint_storage_bounds_ne` for block-enabled `ne_storage`.
  - Replace with explicit block-aware z-coupled bounds only when required:
    - `se_ne <= e_block*n_block`
    - `sc_ne <= p_block_max*na_block`
    - `sd_ne <= p_block_max*na_block`
    - optional build gating choice (see open decisions).

### 2. Gen bound gating for block-enabled generators
- For block-enabled gen, avoid hard `pg <= pmax` conflict with block dispatch.
- Option: custom `variable_gen_power_real_block_aware` in this builder path.

### 3. Resolve dual investment logic for block-enabled candidate storage
- Pick one canonical build logic:
  - Option A: block-native (`n_block`, `na_block`) and disable `z_strg_ne*` terms/costs.
  - Option B: keep `z_strg_ne` and explicitly couple to `n_block` (e.g., `n_block <= nmax*z` and `n_block >= z` style, dataset-dependent).
- Also remove one investment cost path to avoid double counting.

### 4. Final storage policy architecture
- Keep storage energy balance unchanged.
- Make terminal policy explicit and selectable in this builder: strict / none / aggregate / short_horizon_relaxed.
- Avoid implicit strict final in experiments where relaxed policy is intended.

### 5. Preserve required conventions
- Keep standard PowerModels bus balance.
- Keep dcline in standard balance and out of `B0`/gSCR.
- Keep current gSCR/Gershgorin formula.
- Do not reimplement storage dynamics.

## Proposed Regression Tests

A. Block-enabled `ne_storage` with zero standard ratings and positive block ratings can charge/discharge/store after investment.

B. Block-enabled generator with low/zero standard `pmax` and positive `p_block_max` is not clipped by standard `pmax`.

C. Non-block storage still obeys standard `energy_rating/charge_rating/discharge_rating`.

D. Storage energy balance equations remain unchanged and satisfied.

E. Block investment cost counted exactly once.

F. Standard `ne_storage` investment cost not double-counted with block investment cost.

G. `g_min=0` remains non-restrictive.

H. gSCR reconstruction residual stays near zero for positive `g_min`.

## Open Modeling Decisions Requiring Confirmation

1. For block-enabled candidate storage, should `z_strg_ne` remain as a separate binary/investment decision, or be removed in favor of pure `n_block` logic?

2. If `z_strg_ne` is kept, what is the intended coupling to `n_block`?

3. Should block-enabled existing storage ignore standard `energy/charge/discharge_rating` entirely, or should both standard and block limits be enforced conservatively?

4. Should block-enabled generators ignore standard `pmax/qmax` or should block limits be treated as additional conservative limits only?

5. Which terminal storage policy is default for 24h CAPEXP studies (`short_horizon_relaxed`, no-final, aggregate)?
