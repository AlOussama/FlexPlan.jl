# UC/gSCR Block Math Review

Scope date: 2026-04-27

This review explicitly separates:
1. PowerModels-native equations/functions.
2. FlexPlan-native / pre-existing project equations/functions.
3. New project-specific block/gSCR equations/functions.
4. Diagnostic/test-only constructs.

Standard PowerModels OPF equations are treated as external math (called, not re-derived).

## 1) Classification Table
| function_or_equation | category | source | mathematical role | review_depth | infeasibility_risk | action |
|---|---|---|---|---|---|---|
| `_PM.variable_branch_power` | PowerModels-native | PowerModels package | AC branch active flow variables | call/interface only | Low | Keep; ensure called before bus balance |
| `_PM.variable_gen_power` | PowerModels-native | PowerModels package | Generator dispatch variables | call/interface only | Low | Keep |
| `_PM.variable_storage_power` | PowerModels-native | PowerModels package | Existing storage `ps/sc/sd/se` variables and native bounds | call/interface only | Medium | Keep; ensure block constraints do not conflict with fixed ratings unintentionally |
| `_PM.variable_dcline_power` | PowerModels-native | PowerModels package | DC-line active flow variables and bounds | call/interface only | Medium | Keep |
| `_PM.constraint_power_balance` | PowerModels-native | PowerModels package | Standard bus-wise active balance with `bus_arcs` + `bus_arcs_dc` terms | call/interface only | High if bypassed | Must remain the only active-balance equation on CAPEXP path |
| `_PM.constraint_dcline_power_losses` | PowerModels-native | PowerModels package | DC-line directional/loss coupling constraints | call/interface only | Medium | Keep |
| `_PM.constraint_storage_thermal_limit` | PowerModels-native | PowerModels package | Thermal envelope for existing storage | call/interface only | Medium | Keep |
| `_PM.constraint_storage_losses` | PowerModels-native | PowerModels package | Existing-storage loss-power relation | call/interface only | Medium | Keep |
| `_PM.constraint_storage_state` / `_PM.constraint_storage_state_final` (if PowerModels native implementation is used directly in other flows) | PowerModels-native | PowerModels package | Existing-storage intertemporal dynamics | call/interface only | Medium | No derivation review in this document |
| `_PM.constraint_dcline_setpoint_active` | PowerModels-native (not CAPEXP path) | PowerModels package | Fixes dcline to setpoint dispatch when used | call/path check only | High if accidentally enabled in CAPEXP | Keep off CAPEXP builder path |
| `variable_storage_power_ne` | FlexPlan-native / pre-existing | `src/core/storage.jl` | Candidate-storage variable stack (`ps_ne/sc_ne/sd_ne/se_ne/z`) | interface-only | Medium | Keep; review interaction with block-scaled limits |
| `variable_absorbed_energy_ne` | FlexPlan-native / pre-existing | `src/core/storage.jl` | Candidate absorbed-energy accounting | interface-only | Low | Keep |
| `constraint_storage_state_ne` | FlexPlan-native / pre-existing | `src/core/storage.jl` | Candidate-storage intertemporal state equation | interface-only | Medium | Keep; ensure initialization policy is consistent in solver-copy diagnostics |
| `constraint_storage_state_final_ne` | FlexPlan-native / pre-existing | `src/core/storage.jl` | Candidate terminal energy lower bound | interface-only | Medium | Keep; track one-snapshot applicability |
| `constraint_ne_storage_activation` | FlexPlan-native / pre-existing | `src/core/storage.jl` | Candidate activation across investment horizon via `z`/investment vars | interface-only | Medium | Keep |
| `calc_ne_storage_cost` and broader pre-existing storage/expansion objective pieces | FlexPlan-native / pre-existing | `src/core/objective.jl` | Candidate investment objective terms | interface-only | Low | Keep |
| `ref_add_uc_gscr_block!` (+ helpers/validation for `type,n0,nmax,na0,p_block_max,e_block,b_block,startup/shutdown`) | New block/gSCR extension | `src/core/ref_extension.jl` | Creates block device maps and validates required block schema and Gershgorin row data | full math+data review | High | Keep; central to new formulation |
| `variable_uc_gscr_block` / `variable_installed_blocks` / `variable_active_blocks` | New block/gSCR extension | `src/core/block_variable.jl` | Adds `n_block`, `na_block` and structural block counts | full math review | High | Keep |
| `constraint_block_count_transitions` | New block/gSCR extension | `src/core/block_variable.jl` | Startup/shutdown transition equation `na_t-na_{t-1}=su-sd` with `na0` initialization | full math review | High | Keep; critical coupling |
| `constraint_active_blocks_le_installed` | New block/gSCR extension | `src/core/block_variable.jl` | Enforces `na_block <= n_block` | full math review | Medium | Keep |
| `constraint_uc_gscr_block_dispatch` / `constraint_uc_gscr_block_active_dispatch_bounds` | New block/gSCR extension | `src/core/constraint_template.jl`, `src/core/constraint.jl` | Dispatch bounds using block activity (`p_block_min*na <= p <= p_block_max*na`) | full math review | High | Keep; flag `p_block_min` policy |
| `constraint_uc_gscr_block_storage_bounds` / `...energy_capacity` / `...charge_discharge_bounds` | New block/gSCR extension | `src/core/constraint_template.jl`, `src/core/constraint.jl` | Block-scaled storage limits (`se<=e_block*n_block`, `sc/sd<=rating*na`) | full math review | High | Keep; key interface with standard storage ratings |
| `constraint_gscr_gershgorin_sufficient` | New block/gSCR extension | `src/core/constraint_template.jl`, `src/core/constraint.jl` | Linear sufficient gSCR inequality using `b_block`, `p_block_max`, `na_block` | full math review | High | Keep |
| `calc_uc_gscr_block_investment_cost` | New block/gSCR extension | `src/core/objective.jl` | Adds `cost_inv_block*p_block_max*(n_block-n0)` | full math review | Medium | Keep |
| `calc_uc_gscr_block_startup_shutdown_cost` | New block/gSCR extension | `src/core/objective.jl` | Adds `startup_block_cost*su + shutdown_block_cost*sd` | full math review | Medium | Keep |
| `objective_min_cost_uc_gscr_block_integration` | New block/gSCR extension | `src/prob/uc_gscr_block_integration.jl` | Integrates gen cost + candidate storage cost + new block cost terms | full math review | Medium | Keep |
| `build_uc_gscr_block_integration` | New block/gSCR extension (builder orchestration) | `src/prob/uc_gscr_block_integration.jl` | Calls standard PM equations + block/gSCR constraints on each snapshot | full path review | High | Keep; no custom balance |
| `constraint_uc_gscr_block_bus_active_balance` | New block/gSCR extension (wrapper over PM-native equation) | `src/prob/uc_gscr_block_integration.jl` | Wrapper loop that calls PM-native bus balance | call/path review | High if bypassed | Keep as canonical balance wrapper |
| `constraint_uc_gscr_block_system_active_balance` | New block/gSCR extension (legacy alias) | `src/prob/uc_gscr_block_integration.jl` | Deprecated alias delegating to bus-wise standard balance | quarantine-only | Medium | Quarantined/deprecated; keep only for compatibility |
| One-snapshot/full ablation builders in `test/pypsa_elec_s_37_24h_small_capexp.jl` | Diagnostic/test-only | `test/...small_capexp.jl` | Isolate infeasibility layers by toggling constraint families | diagnostic only | N/A | Keep out of production model path |
| Solver-copy policy `existing_storage_initial_energy_policy="half_energy_rating"` | Diagnostic/test-only | `test/...small_capexp.jl` | Pre-solve data mutation for consistency checks | diagnostic only | N/A | Keep clearly diagnostic |
| Candidate one-block-installed policy (if enabled in tests) | Diagnostic/test-only | test-only mutators | Sensitivity policy to probe candidate feasibility | diagnostic only | N/A | Keep clearly diagnostic |
| Diagnostic candidate-rating-from-blocks policy | Diagnostic/test-only | `test/...small_capexp.jl` | Sets candidate `energy/charge/discharge_rating` from `n_block_max`*block sizes | diagnostic only | N/A | Keep clearly diagnostic |

## 2) Standard PowerModels Calls Used by Active Builder
Active UC/gSCR builder (`src/prob/uc_gscr_block_integration.jl`) uses standard PM equations/functions by call:
- Variables: `_PM.variable_branch_power`, `_PM.variable_gen_power`, `_PM.variable_dcline_power`, `_PM.variable_storage_power`.
- Constraints: `_PM.constraint_power_balance` (via `constraint_uc_gscr_block_bus_active_balance`), `_PM.constraint_dcline_power_losses`, `_PM.constraint_storage_thermal_limit`, `_PM.constraint_storage_losses`.
- Not used on CAPEXP path: `_PM.constraint_dcline_setpoint_active`.

Review result for PM-native pieces:
- No custom active-power-balance equation in active builder.
- No reimplementation of PM-native dcline setpoint fixing.
- Correct call sequence: dcline variables/losses are created before bus-balance constraints.

## 3) FlexPlan/Pre-existing Pieces and Interface Risks
Reviewed interfaces only (not re-deriving pre-existing FlexPlan math):
- `variable_storage_power_ne`, `constraint_storage_state_ne`, `constraint_storage_state_final_ne`, `constraint_ne_storage_activation`, related `*_ne` storage constraints.

Interface risks with new block path:
1. Candidate standard ratings (`energy_rating`, `charge_rating`, `discharge_rating`) can conflict with block-scaled capacities if left zero while block vars allow expansion.
2. Existing storage state equations use storage `energy` data directly; inconsistent initial-energy policy can mask root causes.
3. Candidate-state equations rely on pre-existing `ne_storage` semantics (`z`, investment horizon), while block constraints live on `storage`/`ne_storage` compound keys; mixed representations can overconstrain if not calibrated.

## 4) New Block/gSCR Equations: Full Review (A-I)
### 4.1 `ref_add_uc_gscr_block!` and schema validation
- A. Intended equation: no optimization equation; reference-set and parameters for downstream equations.
- B. Variables/data: validates `type,n0,nmax,na0,p_block_min,p_block_max,q bounds,b_block,startup/shutdown`, optional `e_block,H,s_block`.
- C. Infeasibility: indirectly high (bad data rejected or inconsistent bounds propagate).
- D. PM variable usage: N/A (reference stage).
- E. Greenfield `n_block0=0`: supported if mapped to `n0=0` and constraints remain consistent.
- F. Uses `n_block` vs `n0`: N/A.
- G. Uses `na_block`: N/A.
- H. `p_block_min` present and validated; see dispatch review.
- I. Zero candidate standard ratings: not prevented here; downstream risk remains.

### 4.2 `variable_uc_gscr_block` + sub-variables
- A. Equations: variable domains and `na<=n`, transition equations (`na_t-na_{t-1}=su-sd`).
- B. Variables/data: `n_block,na_block,su_block,sd_block`, fields `n0,nmax,na0`.
- C. Infeasibility: high if `na0>nmax` or transitions inconsistent.
- D. PM usage: uses PM variable/constraint containers correctly.
- E. Greenfield: yes (`n0=0` works).
- F. Uses `n_block` (correct) for installed capacity links.
- G. Uses `na_block` (correct) for active-state transitions.
- H. `p_block_min`: not used here.
- I. Candidate zero ratings: not directly addressed.

### 4.3 `constraint_uc_gscr_block_dispatch`
- A. Equation: `p_block_min*na <= p <= p_block_max*na` (+ reactive analog where applicable).
- B. Variables/data: dispatch var (`pg/ps/ps_ne`), `na_block`, `p_block_min`, `p_block_max`.
- C. Infeasibility: high when `p_block_min>0` with required offline/low-load states.
- D. PM usage: variable mapping helper is correct for `gen/storage/ne_storage`.
- E. Greenfield: yes (if `na=0`, bounds force `p=0`).
- F. Uses `n_block` vs `n0`: uses `na_block` for dispatch, which is correct.
- G. Uses `na_block`: yes, correct.
- H. `p_block_min` used: yes; flagged for policy review (prefer using `p_min_pu` path unless block minimum is intentional).
- I. Candidate zero standard ratings: this equation itself does not use standard ratings.

### 4.4 `constraint_uc_gscr_block_storage_bounds`
- A. Equations: `se <= e_block*n_block`, `sc<=charge_rating*na`, `sd<=discharge_rating*na`.
- B. Variables/data: `se/sc/sd` or `se_ne/sc_ne/sd_ne`, `n_block`, `na_block`, `e_block`, `charge_rating`, `discharge_rating`.
- C. Infeasibility: high when standard ratings are zero but `na_block`/`n_block` allow activity.
- D. PM usage: mapped storage variables are used correctly.
- E. Greenfield: yes structurally, but depends on rating data.
- F. Uses `n_block` where energy capacity should scale: yes.
- G. Uses `na_block` where charge/discharge should scale: yes.
- H. `p_block_min`: not used.
- I. Candidate zero standard ratings: yes, can block candidate batteries despite block investment potential.

### 4.5 `constraint_gscr_gershgorin_sufficient`
- A. Equation: `sigma0 + sum(b_block*na_gfm) >= g_min*sum(p_block_max*na_gfl)` per bus.
- B. Variables/data: `na_block`, `b_block`, `p_block_max`, `g_min`, `sigma0`.
- C. Infeasibility: high when `g_min` strong and GFM strength insufficient.
- D. PM usage: accesses PM refs and existing `na_block` correctly.
- E. Greenfield: supported (`na=0` baseline plus investments).
- F. Uses `n_block` vs `n0`: uses `na_block`, appropriate for online strength.
- G. Uses `na_block`: yes, correct.
- H. `p_block_min`: not used.
- I. Candidate zero standard ratings: not directly; but if candidate cannot become active due to other constraints, this can indirectly fail.

### 4.6 Objective terms (`calc_uc_gscr_block_investment_cost`, `calc_uc_gscr_block_startup_shutdown_cost`, `objective_min_cost_uc_gscr_block_integration`)
- A. Equations: investment `cost_inv_block*p_block_max*(n_block-n0)` and startup/shutdown `startup*su + shutdown*sd`.
- B. Variables/data: `n_block,su_block,sd_block`, cost fields.
- C. Infeasibility: low directly (objective terms), but wrong signs/units may distort solutions.
- D. PM usage: JuMP affine expressions and PM var refs are correct.
- E. Greenfield: yes (`n0=0` case naturally handled).
- F. Uses `n_block` (correct) and `n0` constant baseline.
- G. Uses `na_block`: not required in objective equations.
- H. `p_block_min`: not used.
- I. Candidate zero standard ratings: objective does not fix this.

### 4.7 Builder-level wrapper (`build_uc_gscr_block_integration`)
- A. Role: orchestrates variable/constraint calls, not a new scalar equation.
- B. Uses PM-native + FlexPlan + new block/gSCR components.
- C. Infeasibility: high if call ordering mixes incompatible constraints.
- D. PM usage: now aligned to standard bus-balance wrapper only.
- E/F/G/H/I: delegated to called equation families.

## 5) Mathematical Issues Found
1. Candidate-storage representation mismatch risk remains: standard candidate storage ratings (`energy_rating/charge_rating/discharge_rating`) can conflict with block-scaled expansion, producing artificial infeasibility.
2. `p_block_min` appears in new dispatch constraints; if nonzero while other unit-commitment semantics already enforce minimum behavior, this can overconstrain.
3. Mixed representation risk: candidate devices represented via both block variables and pre-existing `ne_storage` semantics can create coupling sensitivity if data policies differ.
4. Legacy system-balance alias existed; while mathematically equivalent wrapper now, it was a potential confusion point for diagnostics.

## 6) Cleanup Actions Applied / Needed Before Further Tests
Applied in this pass:
- Quarantined legacy aggregate balance alias:
  - `constraint_uc_gscr_block_system_active_balance` kept only as deprecated compatibility wrapper.
  - Removed legacy alias constraint key write in `constraint_uc_gscr_block_bus_active_balance`.
- Kept active builder on standard PM bus balance only (via wrapper call).
- Kept dcline setpoint constraints off CAPEXP path.
- Updated test no-gSCR builders to call `constraint_uc_gscr_block_bus_active_balance` directly.
- Made ablation builder share the same balance wrapper as the full builder.

Still needed before major sweeps:
1. Decide policy for `p_block_min` usage vs `p_min_pu` semantics for block devices.
2. Decide single canonical candidate-storage representation for CAPEXP runs (block-scaled vs standard `ne_storage` rating path) and remove ambiguous dual enforcement.
3. Keep diagnostic solver-copy policies explicitly test-only and never default in production solve entry points.

## 7) Minimal Next Tests After Cleanup
Run only lightweight targeted tests:
1. `julia --project=. test\runtests.jl uc_gscr_block_integration`
2. If (1) passes, run one one-snapshot diagnostic only (no positive `g_min`) to verify no regression in balance path.

No positive `g_min` sweep and no converter-data update in this phase.
