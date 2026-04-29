# UC/gSCR Block Math Review

Date: 2026-04-27
Branch: `fix/block-storage-bounds-and-pmin-policy`
Base: `feature/dcline-bus-balance-active-capexp`

## Scope
This review distinguishes:
1. PowerModels-native equations/functions (called, not re-derived).
2. FlexPlan-native / pre-existing project equations/functions (interface review only).
3. New block/gSCR extension equations/functions (full math review and fixes).
4. Diagnostic/test-only policies (test path only).

Storage state/loss dynamics (`se/sc/sd/ps` balance) remain standard PowerModels/FlexPlan equations. The project-specific storage work is the block-scaled capacity/rating interface.

## 1) Classification Table
| function_or_equation | category | source | mathematical role | review_depth | infeasibility_risk | action |
|---|---|---|---|---|---|---|
| `_PM.variable_branch_power` | PowerModels-native | PowerModels | AC branch active-flow vars | call/interface only | Low | Keep |
| `_PM.variable_gen_power` | PowerModels-native | PowerModels | generator active-power vars | call/interface only | Low | Keep |
| `_PM.variable_storage_power` | PowerModels-native | PowerModels | existing storage `ps/sc/sd/se` vars and bounds | call/interface only | Medium | Keep |
| `_PM.variable_dcline_power` | PowerModels-native | PowerModels | dcline flow vars | call/interface only | Medium | Keep |
| `_PM.constraint_power_balance` | PowerModels-native | PowerModels | standard bus power balance | call/path only | High if bypassed | Keep as sole CAPEXP/OPF balance |
| `_PM.constraint_dcline_power_losses` | PowerModels-native | PowerModels | dcline loss coupling | call/interface only | Medium | Keep |
| `_PM.constraint_storage_thermal_limit` | PowerModels-native | PowerModels | storage thermal envelope | call/interface only | Medium | Keep |
| `_PM.constraint_storage_losses` | PowerModels-native | PowerModels | storage loss equation | call/interface only | Medium | Keep |
| `_PM.constraint_dcline_setpoint_active` | PowerModels-native (not CAPEXP) | PowerModels | setpoint fixing | path check only | High if enabled in CAPEXP | Keep off CAPEXP path |
| `variable_storage_power_ne` | FlexPlan-native / pre-existing | `src/core/storage.jl` | candidate storage vars with build indicator | interface-only | Medium | Keep; compare to `n_block` |
| `variable_absorbed_energy_ne` | FlexPlan-native / pre-existing | `src/core/storage.jl` | candidate absorbed-energy bookkeeping | interface-only | Low | Keep |
| `constraint_storage_state_ne` | FlexPlan-native / pre-existing | `src/core/storage.jl` | candidate storage state recursion | interface-only | Medium | Keep standard |
| `constraint_storage_state_final_ne` | FlexPlan-native / pre-existing | `src/core/storage.jl` | candidate final-state lower bound | interface-only | Medium | policy-controlled |
| `constraint_ne_storage_activation` | FlexPlan-native / pre-existing | `src/core/storage.jl` | candidate activation over lifetime | interface-only | Medium | review overlap with block vars |
| `ref_add_uc_gscr_block!` (+ schema checks) | New block/gSCR extension | `src/core/ref_extension.jl` | block schema, maps, gSCR row metrics | full | High | Keep/fixed |
| `variable_uc_gscr_block` (+ `n_block`,`na_block`,`su`,`sd`) | New block/gSCR extension | `src/core/block_variable.jl` | block install/activity/start-stop vars | full | High | Keep |
| `constraint_block_count_transitions` | New block/gSCR extension | `src/core/block_variable.jl` | `na_t-na_{t-1}=su-sd` | full | High | Keep |
| `constraint_uc_gscr_block_dispatch` / active bounds | New block/gSCR extension | `src/core/constraint_template.jl`,`src/core/constraint.jl` | block dispatch bounds | full | High | **Updated**: use `p_min_pu/p_max_pu`, ignore `p_block_min` |
| `constraint_uc_gscr_block_storage_bounds` | New block/gSCR extension | `src/core/constraint_template.jl`,`src/core/constraint.jl` | block-scaled storage capacity/power bounds | full | High | **Updated** to `e_block*n_block`, `p_block_max*na_block` |
| `constraint_gscr_gershgorin_sufficient` | New block/gSCR extension | `src/core/constraint_template.jl`,`src/core/constraint.jl` | linear sufficient gSCR inequality | full | High | Keep |
| `calc_uc_gscr_block_investment_cost` | New block/gSCR extension | `src/core/objective.jl` | block investment term | full | Medium | Keep |
| `calc_uc_gscr_block_startup_shutdown_cost` | New block/gSCR extension | `src/core/objective.jl` | startup/shutdown term | full | Medium | Keep |
| `objective_min_cost_uc_gscr_block_integration` | New block/gSCR extension | `src/prob/uc_gscr_block_integration.jl` | integrated objective assembly | full | Medium | Keep |
| one-snapshot ablation builders and solver-copy policies | Diagnostic/test-only | `test/pypsa_elec_s_37_24h_small_capexp.jl` | diagnostic isolation only | diagnostic-only | N/A | Keep test-only |

## 2) Standard PowerModels Calls Used by Active Builder
Active integration path (`build_uc_gscr_block_integration`) calls:
- `_PM.variable_branch_power`
- `_PM.variable_gen_power`
- `_PM.variable_dcline_power`
- `_PM.variable_storage_power`
- `_PM.constraint_dcline_power_losses`
- `_PM.constraint_power_balance` (via `constraint_uc_gscr_block_bus_active_balance`)
- `_PM.constraint_storage_thermal_limit`
- `_PM.constraint_storage_losses`

No custom power-balance equation is used. `constraint_dcline_setpoint_active` is not on CAPEXP/OPF path.

## 3) FlexPlan/pre-existing interface focus
Review focus: interface with block variables, not re-deriving pre-existing equations.

Key interface risk:
- FlexPlan `ne_storage` build/activation semantics (`z`, investment-horizon activation) can overlap with block install/activity semantics (`n_block`, `na_block`) for the same candidate, creating dual constraints if not linked.

## 4) New block/gSCR equation review (A-H-I checklist)
### 4.1 `constraint_uc_gscr_block_active_dispatch_bounds`
- Intended equation (A):
  - generator-only: `p_min_pu * p_block_max * na_block <= pg <= p_max_pu * p_block_max * na_block`
- Variables/data (B): `pg`, `na_block`, `p_min_pu` (default `0`), `p_max_pu` (default `1`), `p_block_max`.
- Infeasibility risk (C): medium/high if bad `p_min_pu` or `p_max_pu` data.
- PM var usage (D): standard `pg` and block vars used correctly.
- Greenfield support (E): yes (`n0=0` supported).
- Uses `n_block` vs `n0` (F): dispatch uses `na_block`, correct.
- Uses `na_block` (G): yes, correct.
- `p_block_min` usage (H): **removed from active equation**; now deprecated/ignored.
- Candidate zero standard ratings issue (I): not directly in this equation.

### 4.2 `constraint_uc_gscr_block_storage_bounds`
- Intended equations (A):
  - `0 <= se <= e_block * n_block`
  - `0 <= sc <= p_block_max * na_block`
  - `0 <= sd <= p_block_max * na_block`
- Variables/data (B): `se/sc/sd`, `n_block`, `na_block`, `e_block`, `p_block_max`.
- Infeasibility risk (C): lower than prior zero-rating coupling; still data-sensitive.
- PM var usage (D): uses standard storage vars (`se/sc/sd` and `_ne` variants).
- Greenfield support (E): yes.
- Uses `n_block` where install-capacity should scale (F): yes.
- Uses `na_block` where online-power should scale (G): yes.
- `p_block_min` usage (H): none.
- Candidate zero standard ratings issue (I): addressed by block-scaled bounds; zero standard ratings no longer the active limiting interface in these block constraints.

### 4.3 Storage state/loss equations remain standard
- `constraint_storage_losses`, `constraint_storage_state`, `constraint_storage_state_final` (+ `_ne`) remain PowerModels/FlexPlan-native.
- No rewrite performed.
- Block extension now only changes capacity envelopes, not state recursion math.

## 5) FlexPlan `ne_storage` vs block model comparison
| FlexPlan variable/function | meaning | unit | block-model counterpart | compatibility risk | required linking equation |
|---|---|---|---|---|---|
| `z_strg_ne` (`variable_storage_indicator`) | build/active indicator across horizon | binary/relaxed indicator | `n_block` install count; `na_block` active count | High overlap risk if both gate same candidate independently | If both retained: `n_block <= nmax * z_strg_ne` and `na_block <= n_block` |
| `z_strg_ne_investment` | investment decision by horizon | binary/relaxed | investment increment in `n_block - n0` | Medium | If both retained: map yearly investment to `n_block` delta |
| `constraint_ne_storage_activation` | links indicator to investment horizon | logical activation | block startup/online handled via `na_block` transitions | High | Explicitly choose one activation authority, or add linking equalities |
| `variable_storage_power_ne` (`ps_ne/sc_ne/sd_ne/se_ne`) | candidate storage operational vars | MW/MWh | same physical vars used by block constraints in `_ne` tables | Medium | No duplicate bounds with conflicting rating semantics |
| `constraint_storage_state_ne` / `_final_ne` | standard candidate storage dynamics | MWh recursion | same `se_ne/sc_ne/sd_ne` under block-scaled envelopes | Low if linked cleanly | none if canonical path uses standard state + block envelopes |

Canonical formulation recommendation:
- Keep standard storage dynamic equations (`se/sc/sd/ps` state/loss).
- Use block vars as canonical expansion/activity layer for block-gSCR candidates:
  - `n_block` = installed candidate blocks
  - `na_block` = active candidate blocks
  - block envelopes define effective capacities/power
- Avoid independent, unlinked dual activation semantics (`z` and `na_block`) on same candidate in final production path.

## 6) Final storage-state policy
Allowed policies:
1. `short_horizon_relaxed`:
   - no terminal lower bound to initial state (`se_T` free except normal bounds).
2. `start_preserving` / cyclic:
   - `se_T >= se_0` (or `se_T = se_0` if explicitly selected).

Recommendation:
- For 1-snapshot / 24h diagnostics: `short_horizon_relaxed`.
- For production planning: choose and document one policy explicitly; if added as switch, use `final_storage_policy = "relaxed" | "start_preserving"`.

## 7) Validation / schema policy updates
Implemented or documented:
1. Hard invariant: `0 <= na0 <= n0 <= nmax` (hard error).
2. `p_block_max <= 0`:
   - if `nmax > n0`: hard error (invalid expandable candidate).
   - if `nmax=n0=na0=0`: treated as inactive placeholder and ignored.
3. `p_min_pu`:
   - missing -> defaults to `0` in active dispatch lower bound.
4. `p_block_min`:
   - deprecated; ignored in active dispatch; warning emitted if present.
5. Candidate storage with zero standard ratings:
   - allowed in block formulation path because block-scaled bounds are active.

## 8) Mathematical issues and cleanup status
Resolved in this branch:
- Removed active use of `p_block_min` from dispatch bounds.
- Dispatch bounds now generator-only and based on `p_min_pu/p_max_pu` with defaults.
- Storage block power bounds now use `p_block_max * na_block` (not standard charge/discharge ratings).
- Active balance path remains standard PowerModels bus balance only; no custom balance added.
- Legacy `...system_active_balance` alias quarantined/deprecated.

Remaining architectural decision before broader studies:
- Single canonical candidate activation model (`z`-based vs purely block-based) should be finalized with explicit linking if both remain.
