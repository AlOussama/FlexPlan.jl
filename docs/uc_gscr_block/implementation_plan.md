# UC/gSCR Block Implementation Plan

This plan sequences implementation branches for the UC/gSCR block
generation-expansion refactor. The current document is planning only; it does
not state that the implementation is complete.

The documentation branch comes first. Implementation branches start only after
the architecture decisions, schema-v2 contract, and implementation plan are
reviewed and merged.

## Branch 1: `feature/uc-gscr-block-schema-v2`

### Scope

- Add schema-v2 validation for `block_model_schema.name = "uc_gscr_block"` and
  `block_model_schema.version = "2.0"`.
- Validate physical/interface fields for block-enabled `gen`, `storage`, and
  `ne_storage`.
- Replace old `type` usage with `grid_control_mode`.
- Reject ambiguous old fields: `type`, `cost_inv_block`,
  `startup_block_cost`, `shutdown_block_cost`, and other policy-like data
  fields.
- Validate snapshot/network fields `time_elapsed`, compatibility-only `operation_weight`, and
  conditionally `g_min`.
- Document that template and network-physics choices are model-build inputs,
  not schema-v2 device fields.

### Non-Goals

- Do not add formulation template dispatch.
- Do not add optimization variables or constraints.
- Do not change standard FlexPlan candidate-storage behavior.
- Do not implement a PyPSA converter.

### Acceptance Tests

- Schema test accepts a minimal valid schema-v2 case.
- Schema test rejects missing or wrong `block_model_schema`.
- Schema test rejects `type`, `cost_inv_block`, `startup_block_cost`, and
  `shutdown_block_cost`.
- Schema test rejects missing required block fields.
- Schema test requires `g_min` only when the validation context or later
  template resolution selects a gSCR formulation needing it; otherwise this
  check remains deferred until template selection is available.

## Branch 2: `feature/block-model-template`

### Scope

- Add a lightweight model-template layer.
- Treat the template as a model-build input, not a device data field.
- Define initial formulation objects:
  - `AbstractBlockDeviceFormulation`;
  - `BlockThermalCommitment`;
  - `BlockRenewableParticipation`;
  - `BlockFixedInstalled`;
  - optional placeholder for `BlockStorageParticipation`;
  - `AbstractGSCRFormulation`;
  - `NoGSCR`;
  - `GershgorinGSCR`;
  - `AbstractGSCRExposure`;
  - `OnlineNameplateExposure`.
- Resolve template assignments by `(table, carrier)`.
- Support exact `(table, device_id)` overrides.
- Require every block-enabled device to resolve to exactly one formulation.
- Cache formulation-specific device sets in `pm.ext`.
- Keep `ref_add_uc_gscr_block!` limited to validation, GFL/GFM maps, and
  AC-side `B0`/Gershgorin metrics.

### Non-Goals

- Do not add formulation-specific constraints beyond validation and grouping.
- Do not implement gSCR constraints.
- Do not infer biomass or pumped hydro behavior.

### Acceptance Tests

- Template test maps CCGT/OCGT to `BlockThermalCommitment`.
- Template test maps wind/solar to `BlockRenewableParticipation`.
- Template test maps BESS-GFL/BESS-GFM to `BlockFixedInstalled`.
- Template test rejects an unmapped block-enabled device.
- Template test verifies exact `(table, device_id)` overrides take precedence.
- Template test verifies biomass and pumped hydro require explicit assignment.

## Branch 3: `feature/block-formulation-specific-constraints`

### Scope

- Create `n_block` and `na_block` for all block-enabled devices.
- Create `su_block` and `sd_block` only for `BlockThermalCommitment`.
- Add installed block bounds \(n0 \le n\_block \le nmax\).
- Add active block bounds \(0 \le na\_block \le n\_block\).
- Add startup/shutdown transition constraints only for
  `BlockThermalCommitment`.
- Add `BlockFixedInstalled` constraint `na_block = n_block`.
- Add `BlockRenewableParticipation` participation bounds without startup or
  shutdown variables.
- Add block-scaled active and reactive dispatch bounds using
  `p_min_pu`, `p_max_pu`, `p_block_max`, `q_block_min`, and `q_block_max`.
- Follow PowerModels/FlexPlan multiple-dispatch style, including no-op reactive
  methods for active-power-only formulations.

### Non-Goals

- Do not implement investment/startup/shutdown objective costs.
- Do not implement gSCR constraints.
- Do not add no-load cost, ramping, or min-up/min-down constraints unless a
  selected formulation explicitly requires them in a later branch.

### Acceptance Tests

- Small model creates `n_block` and `na_block` for every block-enabled device.
- Small model creates `su_block` and `sd_block` only for thermal commitment
  devices.
- Constraint test verifies `BlockFixedInstalled` imposes `na_block = n_block`.
- Constraint test verifies renewables have no startup/shutdown variables.
- Dispatch-bound test confirms standard fixed bounds are bypassed, removed, or
  validated as nonbinding for block-enabled devices.

## Branch 4: `feature/block-objective-units-and-weights`

### Scope

- Add block investment cost:
  \[
  cost\_inv\_per\_mw \cdot p\_block\_max \cdot (n\_block - n0).
  \]
- Add startup/shutdown costs for `BlockThermalCommitment`:
  \[
  startup\_cost\_per\_mw \cdot p\_block\_max \cdot su\_block,
  \]
  \[
  shutdown\_cost\_per\_mw \cdot p\_block\_max \cdot sd\_block.
  \]
- Use `scale_data!` to annualize dispatch, curtailment, load operation, and
  startup/shutdown OPEX coefficients.
- Do not apply `operation_weight` as an additional objective multiplier.
- Annualize raw block `cost_inv_per_mw` using
  `(annuity(lifetime, discount_rate) + fixed_om_percent/100) *
  year_scale_factor`.
- Require explicit lifetime for expandable block devices and explicit
  nonnegative discount/FOM inputs on the device or in case-level cost
  assumptions.
- Keep marginal dispatch cost on existing standard dispatch cost fields.

### Non-Goals

- Do not refactor marginal dispatch cost fields.
- Do not add no-load, ramping, or additional UC objective terms.
- Do not reuse standard candidate-storage investment cost for block storage.

### Acceptance Tests

- Objective unit test verifies investment cost scales with MW per block and
  added blocks.
- Objective unit test verifies startup/shutdown costs scale with MW per block
  and already-scaled OPEX coefficients.
- Objective test verifies neither operation nor investment cost is
  operation-weighted.
- Regression test verifies standard non-block devices keep existing objective
  behavior.

## Branch 5: `feature/gscr-formulation-template`

### Scope

- Select `NoGSCR` or `GershgorinGSCR` through the model template.
- Implement `GershgorinGSCR(OnlineNameplateExposure)`.
- Use online nameplate GFL exposure:
  \[
  P_{fl} = \sum p\_block\_max \cdot na\_block.
  \]
- Add the MILP-compatible Gershgorin sufficient condition:
  \[
  \sigma_G + \sum_{GFM} b\_block \cdot na\_block
  \ge
  g\_min \sum_{GFL} p\_block\_max \cdot na\_block.
  \]
- Store diagnostics needed for later post-solve eigenvalue/gSCR margin checks.

### Non-Goals

- Do not add SDP, MISDP, or global LMI formulations.
- Do not add advanced exposure models beyond `OnlineNameplateExposure`.
- Do not make `g_min` mandatory for `NoGSCR`.

### Acceptance Tests

- BASE template with `NoGSCR` builds without `g_min`.
- gSCR template with `GershgorinGSCR` requires `g_min`.
- Small optimization case enforces the Gershgorin sufficient condition.
- Diagnostic test confirms GFL/GFM sets and AC-side bus mappings are reported.

## Branch 6: `feature/storage-terminal-policy`

### Scope

- Add explicit storage terminal policy selection for block storage.
- Treat terminal policy as formulation/model-build behavior, not as a
  per-device policy data field.
- Support planned policies:
  - `:cyclic`, \(e_T = e_1\);
  - `:fixed_initial`, \(e_T = e^{initial}\);
  - `:relaxed_cyclic`,
    \(e_T \ge storage\_terminal\_fraction \cdot e_1\);
  - `:none`, no terminal condition.
- Ensure storage energy capacity uses \(e \le e\_block \cdot n\_block\).
- Ensure charge/discharge bounds use
  \(p \le p\_block\_max \cdot na\_block\).

### Non-Goals

- Do not introduce a new storage state convention when existing
  PowerModels/FlexPlan fields are sufficient.
- Do not implement binary standard candidate-storage behavior in the block path.

### Acceptance Tests

- Storage test verifies each terminal policy produces the expected terminal
  constraint or no constraint.
- Storage test verifies energy capacity scales with installed blocks.
- Storage test verifies charge/discharge power scales with active blocks.

## Branch 7: `feature/block-architecture-guards`

### Scope

- Add hard validation that prevents mixed binary/block storage formulations.
- Reject block-enabled storage that also uses `z_strg_ne` or
  `z_strg_ne_investment`.
- Reject use of standard candidate-storage activation constraints and standard
  candidate-storage investment cost for block-enabled storage.
- Validate standard PowerModels/FlexPlan fixed bounds are nonbinding or bypassed
  for block-enabled devices.

### Non-Goals

- Do not remove standard FlexPlan candidate-storage support for non-block cases.
- Do not change non-block examples except where validation messages need to be
  made explicit.

### Acceptance Tests

- Guard test rejects a storage device marked for both binary candidate storage
  and block storage.
- Guard test rejects block storage when standard binary investment variables are
  present for the same asset.
- Regression test confirms existing standard candidate-storage cases still run
  when no block fields are present.

## Branch 8: `feature/uc-gscr-block-tests-and-fixtures`

### Scope

- Add schema/interface fixtures.
- Add template matching and compatibility fixtures.
- Add small optimization fixtures for:
  - thermal commitment blocks;
  - renewable participation blocks;
  - fixed installed BESS blocks;
  - BASE `NoGSCR`;
  - `GershgorinGSCR`.
- Add converted-case fixtures only after small tests pass.
- Add post-solve diagnostic checks when the corresponding reporting layer
  exists.

### Non-Goals

- Do not start with full converted-case tests before small cases are stable.
- Do not make converter implementation part of this repository.
- Do not require advanced gSCR formulations that are explicitly later
  extensions.

### Acceptance Tests

- Schema/interface tests cover required and rejected fields.
- Template tests cover exact overrides and unmapped-device rejection.
- Small optimization tests solve and verify expected variable/constraint
  behavior.
- Full converted-case tests are added only after the small optimization suite is
  passing and diagnostically useful.
