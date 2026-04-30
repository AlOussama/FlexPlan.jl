# UC/gSCR Block Schema v2

This document defines the target schema for UC/gSCR block model-ready data. It
is documentation for upcoming implementation work and does not imply that all
validation is already present.

## 1. Schema Declaration

Every case using block-enabled devices must include:

```json
{
  "block_model_schema": {
    "name": "uc_gscr_block",
    "version": "2.0"
  }
}
```

Validation must require:

- `block_model_schema.name == "uc_gscr_block"`;
- `block_model_schema.version == "2.0"`.

Cases with older or missing block schema declarations must not be silently
interpreted as schema v2.

## 2. Rejected Fields

Schema v2 rejects fields whose meaning mixes physical data and formulation
policy, or whose units are ambiguous.

Rejected physical/formulation fields:

- `type`;
- `activation_policy`;
- `uc_policy`;
- `gscr_exposure_policy`.

Rejected old cost fields:

- `startup_block_cost`;
- `shutdown_block_cost`;
- `cost_inv_block`.

Use the v2 fields instead:

- `grid_control_mode`;
- `cost_inv_per_mw`;
- `startup_cost_per_mw`;
- `shutdown_cost_per_mw`.

## 3. Device Tables

The schema applies to block-enabled records in:

- `gen`;
- `storage`;
- `ne_storage`.

The same physical block representation is used for existing, fixed,
expandable, and candidate resources. The model template, not the data record,
selects whether a resource behaves as thermal commitment, renewable
participation, fixed installed capacity, storage participation, or another
future formulation.

## 4. Required Device Fields

Each block-enabled `gen`, `storage`, or `ne_storage` record requires:

| Field | Meaning |
|---|---|
| `carrier` | Technology or fuel carrier used by template matching |
| `grid_control_mode` | AC-grid interface mode, either `"gfl"` or `"gfm"` |
| `n0` | Initial installed blocks |
| `nmax` | Maximum installed blocks |
| `na0` | Initially active or participating blocks before the first snapshot |
| `p_block_max` | Active-power capacity per block |
| `q_block_min` | Reactive lower bound per active block |
| `q_block_max` | Reactive upper bound per active block |
| `b_block` | Per-block GFM strengthening contribution |
| `cost_inv_per_mw` | Investment cost per MW of added block capacity |
| `p_min_pu` | Minimum active dispatch as per-unit of `p_block_max` per active block |
| `p_max_pu` | Maximum active dispatch as per-unit of `p_block_max` per active block |

Valid `grid_control_mode` values:

```text
gfl
gfm
```

`carrier` is an interface field for template matching. It must not be used as a
silent fallback formulation by itself. A `(table, carrier)` template entry is
an explicit model-template assignment; the `carrier` data value alone is not a
policy choice.

## 5. Storage-Specific Fields

Block-enabled `storage` and `ne_storage` records also require:

| Field | Meaning |
|---|---|
| `e_block` | Energy capacity per installed block |
| `charge_efficiency` | Charging efficiency |
| `discharge_efficiency` | Discharging efficiency |
| existing energy field | Initial or current energy field consistent with the repository's storage representation |

The exact initial-energy field name should follow the existing FlexPlan/
PowerModels storage table convention already used by the selected storage
model. Schema validation should verify consistency instead of introducing a
parallel storage state field without need.

## 6. Conditionally Required Fields

The formulation template determines which additional fields are required.

For `BlockThermalCommitment`:

| Field | Meaning |
|---|---|
| `startup_cost_per_mw` | Startup cost per MW of started block capacity |
| `shutdown_cost_per_mw` | Shutdown cost per MW of shut-down block capacity |
| `min_up_block_time` | Minimum active block up-time, if the selected template enables min-up constraints |
| `min_down_block_time` | Minimum active block down-time, if the selected template enables min-down constraints |

`startup_cost_per_mw` and `shutdown_cost_per_mw` are required when startup and
shutdown variables are created. `min_up_block_time` and `min_down_block_time`
are required only for formulation templates that enable those constraints.

For `BlockRenewableParticipation` and `BlockFixedInstalled`, startup/shutdown
fields are not required and must not trigger startup/shutdown variables.

## 7. Snapshot and Network-Level Fields

Required for time-series operation:

| Field | Meaning |
|---|---|
| `time_elapsed` | Snapshot duration \(\Delta t\) used by storage dynamics |
| `operation_weight` | Snapshot/scenario objective weight for operation costs |

Required only when the selected gSCR formulation needs it:

| Field | Meaning |
|---|---|
| `g_min` | Minimum gSCR/ESCR threshold |

`operation_weight` applies to dispatch and startup/shutdown costs, not to
investment cost.

## 8. Bounds and Units

Block-scaled bounds are the authoritative bounds for block-enabled devices.

Active dispatch:

\[
p_{min,pu} P^{block,max} n_a^{block}
\le
p
\le
p_{max,pu} P^{block,max} n_a^{block}.
\]

Reactive dispatch:

\[
Q^{block,min} n_a^{block}
\le
q
\le
Q^{block,max} n_a^{block}.
\]

Storage:

\[
e \le E^{block} n^{block},
\]

\[
p^{charge}, p^{discharge}
\le
P^{block,max} n_a^{block}.
\]

Investment cost:

\[
cost\_inv\_per\_mw \cdot p\_block\_max \cdot (n\_block - n0).
\]

Startup/shutdown costs:

\[
startup\_cost\_per\_mw \cdot p\_block\_max \cdot su\_block,
\]

\[
shutdown\_cost\_per\_mw \cdot p\_block\_max \cdot sd\_block.
\]

All power, energy, susceptance, and cost fields must use the same internal base
conventions as the corresponding PowerModels/FlexPlan quantities in the active
model. Validation should report missing or inconsistent required fields rather
than guessing fallback values.

## 9. Template Compatibility Checks

Schema validation confirms the physical/interface data. Template compatibility
checks confirm that the selected model template can formulate every
block-enabled device.

The model template is supplied to the model builder. It is not serialized into
device records as `activation_policy`, `uc_policy`, `gscr_exposure_policy`, or
similar policy fields.

Compatibility requirements:

- every block-enabled device resolves to exactly one formulation;
- no block-enabled device is silently assigned a default formulation;
- `(table, device_id)` overrides are allowed and take precedence;
- `(table, carrier)` assignments are allowed for broad groups;
- devices with missing required fields for the resolved formulation are rejected
  before optimization model construction proceeds.

## 10. gSCR Data Use

For `GershgorinGSCR(OnlineNameplateExposure)`, GFL exposure is:

\[
P_{fl}
=
\sum_{k \in GFL} p\_block\_max_k \cdot na\_block_k.
\]

The MILP-compatible sufficient condition is:

\[
\sigma_G
+
\sum_{k \in GFM} b\_block_k \cdot na\_block_k
\ge
g\_min
\sum_{i \in GFL} p\_block\_max_i \cdot na\_block_i.
\]

`g_min` is required for this formulation. It is not required for `NoGSCR`.

## 11. Interface Boundary

The repository consumes model-ready data. It does not implement a PyPSA
converter. External converter packages must write schema-v2-compliant data; the
repository validates it, builds the optimization model, and reports diagnostics.

Model-build choices such as the formulation template and the selected
PowerModels model type are outside the schema-v2 device records. Schema v2
defines the physical/interface contract those choices consume.
