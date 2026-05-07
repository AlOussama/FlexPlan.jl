# UC/gSCR Block Schema v2

This document defines the target schema for UC/gSCR block model-ready physical
and interface data. It is documentation for upcoming implementation work and
does not imply that all validation is already present. Converter outputs must
not encode optimization formulation policies; formulation choices are supplied
later through a downstream model template.

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
| `carrier` | Physical/grouping label used by downstream template matching |
| `grid_control_mode` | Physical AC-grid interface/control classification, either `"gfl"` or `"gfm"` |
| `n0` | Initial installed blocks |
| `nmax` | Maximum installed blocks |
| `na0` | Initially active or participating blocks before the first snapshot |
| `p_block_max` | Active-power capacity per block |
| `q_block_min` | Reactive lower bound per active block |
| `q_block_max` | Reactive upper bound per active block |
| `b_block` | Per-block GFM strengthening contribution |
| `cost_inv_per_mw` | Raw overnight investment cost per MW of added block capacity before `scale_data!` annualization |
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
policy choice. `grid_control_mode` describes the physical AC-grid interface and
does not choose the mathematical formulation.

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

For expandable block devices (`nmax > n0`), CAPEX annualization requires:

| Field | Meaning |
|---|---|
| `lifetime` | Technical/economic lifetime in years used in the annuity calculation |
| `discount_rate` | Nonnegative discount rate used in the annuity calculation |
| `fixed_om_percent` | Nonnegative fixed O&M percentage added to the annuity |

`lifetime` must be supplied on the device. Case-level `lifetime` is not
supported. `discount_rate` and `fixed_om_percent` may be supplied as device
fields or as case-level `uc_gscr_block_cost_assumptions` values. Precedence is:

```text
lifetime:
    device field required

discount_rate:
    device value > uc_gscr_block_cost_assumptions > error

fixed_om_percent:
    device value > uc_gscr_block_cost_assumptions > error
```

There are no hidden defaults. Explicit zeros are valid only when supplied by
the device or, for `discount_rate` and `fixed_om_percent`, by
`uc_gscr_block_cost_assumptions`.

## 7. Snapshot and Network-Level Fields

Required for time-series operation:

| Field | Meaning |
|---|---|
| `time_elapsed` | Snapshot duration \(\Delta t\) used by storage dynamics |
| `operation_weight` | Compatibility/diagnostic field; not the primary annualization mechanism |

Required only when the selected gSCR formulation needs it:

| Field | Meaning |
|---|---|
| `g_min` | Minimum gSCR/ESCR threshold |

OPEX annualization is performed by `scale_data!`, using:

\[
8760 \cdot year\_scale\_factor / number\_of\_hours.
\]

For `year_scale_factor = 1`, this is \(8760 / number\_of\_hours\).
`operation_weight` is not used as an additional annualization multiplier for
dispatch, curtailment, load operation, startup, or shutdown costs. In the
canonical UC/gSCR block workflow it should be `1.0` if retained in a case for
compatibility. Values other than `1.0` are diagnostic only unless a future
workflow explicitly disables `scale_data!` and documents a different policy.

Do not map PyPSA snapshot objective weights to `operation_weight` in a case
that also uses `scale_data!` for annualization. PyPSA-style time weighting and
FlexPlan `scale_data!` annualization are alternative mechanisms, not
independent multipliers.

`time_elapsed` remains the snapshot duration used by storage dynamics.

## 8. Cost Handling

OPEX coefficients are scaled before model construction by
[`src/io/scale.jl`](../../src/io/scale.jl). The objective in
[`src/core/objective.jl`](../../src/core/objective.jl) assumes those
coefficients are already annualized and does not multiply them by
`operation_weight`.

Startup/shutdown OPEX after `scale_data!`:

\[
startup\_cost\_per\_mw
\leftarrow
startup\_cost\_per\_mw \cdot
8760 \cdot year\_scale\_factor / number\_of\_hours.
\]

\[
shutdown\_cost\_per\_mw
\leftarrow
shutdown\_cost\_per\_mw \cdot
8760 \cdot year\_scale\_factor / number\_of\_hours.
\]

CAPEX follows the PyPSA-Eur annualized-capex convention from
[`scripts/process_cost_data.py`](https://github.com/PyPSA/pypsa-eur/blob/master/scripts/process_cost_data.py)
and
[`doc/costs.rst`](https://github.com/PyPSA/pypsa-eur/blob/master/doc/costs.rst):

\[
annualized\_cost\_inv\_per\_mw =
cost\_inv\_per\_mw \cdot
(annuity(lifetime, discount\_rate) + fixed\_om\_percent/100)
\cdot year\_scale\_factor
\cdot cost\_scale\_factor.
\]

\[
annuity(n,r) =
\begin{cases}
r / (1 - (1+r)^{-n}) & r > 0,\\
1/n & r = 0.
\end{cases}
\]

For `discount_rate = 0`, `fixed_om_percent = 0`, and
`year_scale_factor = 1`, annualized CAPEX is `cost_inv_per_mw / lifetime`.

| Topic | Original FlexPlan | PyPSA-Eur | UC/gSCR block decision |
|---|---|---|---|
| OPEX time weighting | `scale_data!` scales hourly OPEX by \(8760 \cdot year\_scale\_factor / number\_of\_hours\) | Snapshot weights time-weight operation | Use FlexPlan `scale_data!`; `operation_weight` is compatibility-only |
| CAPEX treatment | Candidate investments use lifetime/residual-value scaling | Annualized capital cost \((annuity + FOM/100) \cdot investment \cdot nyears\) | `cost_inv_per_mw` is raw overnight CAPEX and is annualized by `scale_data!` |
| Lifetime use | Investment residual value | Annuity term | Device field required for expandable block devices; no case-level lifetime |
| Discount rate use | Not used in original residual-value rule | Annuity term | Device value, then case-level cost assumption, otherwise error |
| FOM use | Not used in original residual-value rule | Added as `FOM/100` | Device value, then case-level cost assumption, otherwise error |
| Scenario probability use | Applied separately in stochastic objectives | Separate from snapshot weights | Scenario probabilities remain only in stochastic objectives |
| Multi-year handling | Year dimensions and residual value | `nyears` multiplier | `year_scale_factor` multiplier for block annualized CAPEX |

## 9. Bounds and Units

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

At objective construction time, `cost_inv_per_mw` is the annualized coefficient
after `scale_data!`.

Startup/shutdown costs:

\[
startup\_cost\_per\_mw \cdot p\_block\_max \cdot su\_block,
\]

\[
shutdown\_cost\_per\_mw \cdot p\_block\_max \cdot sd\_block.
\]

If source data provides startup/shutdown costs per MW, pass them through after
unit conversion. If source data provides startup/shutdown costs per block or
per unit, convert explicitly to per MW using the block rating, or reject the
input as ambiguous. MATPOWER-style startup/shutdown cost fields must not be
silently reinterpreted.

All power, energy, susceptance, and cost fields must use the same internal base
conventions as the corresponding PowerModels/FlexPlan quantities in the active
model. Validation should report missing or inconsistent required fields rather
than guessing fallback values.

For wind and PV, `p_max_pu[t] = 0.3` means each participating block has `0.3`
pu available output. It does not change the rated GFL exposure of a
participating block; participation is represented downstream by `na_block`.

## 10. Template Compatibility Checks

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

## 11. gSCR Data Use

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

The converter is responsible for `grid_control_mode`, `b_block`, and
`p_block_max`, and for case-level `g_min` only when it owns export of a case
that will be solved with gSCR constraints. The converter does not choose
`NoGSCR`, `GershgorinGSCR`, or `OnlineNameplateExposure`; those are downstream
template choices.

## 12. Interface Boundary

The repository consumes model-ready data. It does not implement a PyPSA
converter. External converter packages must write schema-v2-compliant data; the
repository validates it, builds the optimization model, and reports diagnostics.

Model-build choices such as the formulation template and the selected
PowerModels model type are outside the schema-v2 device records. Schema v2
defines the physical/interface contract those choices consume.

The converter should not serialize downstream formulation objects or policy
fields, such as `BlockThermalCommitment`, `BlockRenewableParticipation`,
`BlockFixedInstalled`, `NoGSCR`, `GershgorinGSCR`,
`OnlineNameplateExposure`, `activation_policy`, `uc_policy`, or
`gscr_exposure_policy`. Documentation may recommend human-readable default
mappings, but those mappings are not exported as device fields.

## 13. Converter-Side Validation Checklist

Converter-side validation should check:

- `block_model_schema` exists and is version `2.0` when block data is exported.
- Every block-enabled device has `carrier` and `grid_control_mode`.
- `grid_control_mode` is `gfl` or `gfm`.
- No old fields are present: `type`, `cost_inv_block`, `startup_block_cost`, `shutdown_block_cost`.
- No model-policy fields are present: `activation_policy`, `uc_policy`, `gscr_exposure_policy`.
- `0 <= na0 <= n0 <= nmax`.
- `p_block_max > 0` for expandable devices.
- `q_block_min <= q_block_max`.
- `cost_inv_per_mw >= 0`.
- Expandable block devices provide device-level `lifetime`.
- `discount_rate` and `fixed_om_percent` are present either on the device or through explicit case-level cost assumptions.
- `startup_cost_per_mw` and `shutdown_cost_per_mw` are per MW if present.
- `p_min_pu` and `p_max_pu` are scalar or time-series compatible with exported snapshots.
- `operation_weight`, if present, is `1.0` in the canonical `scale_data!` workflow.
- `time_elapsed` exists for every snapshot.
- `e_block` exists for block-enabled `storage` and `ne_storage`.
