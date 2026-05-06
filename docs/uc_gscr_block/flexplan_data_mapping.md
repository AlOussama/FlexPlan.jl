# FlexPlan Data Mapping and Extensions

This document defines the converter-facing UC/gSCR block data contract. The
converter exports model-ready physical/interface data only. It must not encode
optimization formulation policy; those choices are supplied later through a
model template in the downstream optimization package.

## 1. Schema Marker

Every converted case containing UC/gSCR block-enabled devices must include:

```json
{
  "block_model_schema": {
    "name": "uc_gscr_block",
    "version": "2.0"
  }
}
```

Schema v2 rejects block-enabled records that use old or policy-like fields.

Old field names are replaced as follows:

| Old field | Schema-v2 field |
|---|---|
| `type` | `grid_control_mode` |
| `cost_inv_block` | `cost_inv_per_mw` |
| `startup_block_cost` | `startup_cost_per_mw` |
| `shutdown_block_cost` | `shutdown_cost_per_mw` |

The converter must not write model-policy fields:

- `activation_policy`;
- `uc_policy`;
- `gscr_exposure_policy`.

These are downstream model-template choices, not converter data fields.

## 2. Existing FlexPlan/PowerModels Data to Reuse

### `bus`

Use for:

- AC-side bus set \(\mathcal N_{ac}\) used by gSCR;
- bus IDs;
- active demand `pd`;
- reactive demand `qd` for later AC formulation;
- bus zone/area if available.

### `branch`

Use for:

- AC-side branch set \(\mathcal R_{ac}\) used by gSCR;
- `f_bus`, `t_bus`;
- `br_x`, optionally `br_r`;
- `rate_a`;
- `br_status`;
- `angmin`, `angmax`.

Use this to build the gSCR baseline \(B^0\) on the AC-side network. DC buses,
DC branches, and DC-side converter elements do not enter \(B^0\).

### `gen`

Use for existing and candidate controllable generation devices. Every
block-enabled `gen` record must include the common block fields in Section 3.

If the existing generator table is not suitable for new fields, use an
auxiliary table such as `gen_block`, but preserve the same field names and
schema-v2 validation rules.

### `storage` and `ne_storage`

Use for storage-capable devices. Every block-enabled `storage` and
`ne_storage` record must include the common block fields in Section 3 and the
storage field `e_block`.

## 3. Required Per-Device Fields

Every block-enabled `gen`, `storage`, and `ne_storage` record requires:

| Field | Meaning |
|---|---|
| `carrier` | Physical/grouping label used by downstream template matching |
| `grid_control_mode` | Physical AC-grid interface/control classification |
| `n0` | Initial installed blocks |
| `nmax` | Maximum installed blocks |
| `na0` | Initially active/participating blocks before the first snapshot |
| `p_block_max` | Active-power rating per block |
| `q_block_min` | Reactive lower bound per participating block |
| `q_block_max` | Reactive upper bound per participating block |
| `b_block` | Per-block GFM strength contribution |
| `cost_inv_per_mw` | Investment cost per MW of added block capacity |
| `p_min_pu` | Minimum meaningful active dispatch per participating block, if applicable |
| `p_max_pu` | Per-unit availability/capability per participating block |

Block-enabled `storage` and `ne_storage` records additionally require:

| Field | Meaning |
|---|---|
| `e_block` | Energy capacity per storage block |

Valid `grid_control_mode` values are:

```text
gfl
gfm
```

`carrier` is a physical/grouping label used by the downstream template matcher.
The `carrier` value by itself is not a model policy. `grid_control_mode` is the
physical AC-grid interface/control classification, not a formulation type.

Optional physical/interface fields such as `H` and `s_block` may be exported if
the downstream model uses them, but they do not select formulation behavior.

## 4. Block Count Semantics

The same block-count fields are used for fixed, expandable, candidate, and
inactive placeholder resources:

| Field | Meaning |
|---|---|
| `n0` | Initial installed blocks |
| `nmax` | Maximum installed blocks |
| `na0` | Initially active/participating blocks before the first snapshot |
| `p_block_max` | Active-power rating per block |
| `e_block` | Energy capacity per storage block |

Resource-state conventions:

| Resource state | Representation |
|---|---|
| Fixed existing resource | `n0 = nmax` |
| Expandable resource | `nmax > n0` |
| Pure candidate | `n0 = 0` |
| Phased-out resource | Removed before export, or exported with `n0 = nmax = na0 = 0` only if explicitly intended as an inactive placeholder |

The installed block variable is shared across snapshots downstream. The active
or participating block variable is snapshot-specific downstream.

## 5. Availability and Dispatch Semantics

`p_max_pu[t]` is the per-unit availability/capability of each participating
block at snapshot \(t\). `p_min_pu[t]` is the minimum meaningful active dispatch
per participating block, if applicable.

Downstream dispatch bounds use:

\[
p_{min,pu,t} \, p_{block,max} \, n_{a,t}^{block}
\le
p_t
\le
p_{max,pu,t} \, p_{block,max} \, n_{a,t}^{block}.
\]

Reactive dispatch bounds use:

\[
q_{block,min} n_{a,t}^{block}
\le
q_t
\le
q_{block,max} n_{a,t}^{block}.
\]

For wind and PV, availability such as `0.3` means each participating block has
`0.3` pu available output. It does not change the rated GFL exposure of a
participating block. The number of participating blocks is represented
downstream by `na_block`.

## 6. Cost Conventions

Investment cost is per MW:

```text
cost_inv_per_mw
```

The downstream objective convention is:

\[
cost\_inv\_per\_mw \cdot p\_block\_max \cdot (n\_block - n0).
\]

Startup and shutdown costs are per MW of started or shut-down block capacity:

```text
startup_cost_per_mw
shutdown_cost_per_mw
```

The downstream objective convention is:

\[
startup\_cost\_per\_mw \cdot p\_block\_max \cdot su\_block,
\]

\[
shutdown\_cost\_per\_mw \cdot p\_block\_max \cdot sd\_block.
\]

If the source data gives startup/shutdown costs per MW, pass them through after
unit conversion. If the source data gives startup/shutdown costs per block or
per unit, convert explicitly to per MW using the block rating, or reject the
input as ambiguous. Do not silently reinterpret MATPOWER-style startup/shutdown
cost fields.

## 7. Snapshot Operation Weights

Every converted snapshot/network must include:

| Field | Meaning |
|---|---|
| `operation_weight` | Compatibility/diagnostic field; not the annualization mechanism when `scale_data!` is active |
| `time_elapsed` | Snapshot duration used by storage dynamics |

OPEX annualization is performed by FlexPlan `scale_data!` before
`make_multinetwork`, using \(8760 \cdot year\_scale\_factor /
number\_of\_hours\). `operation_weight` is not multiplied into dispatch or
startup/shutdown costs in the canonical UC/gSCR block workflow and should be
`1.0` if retained for compatibility. Do not map PyPSA snapshot weights into
`operation_weight` when `scale_data!` is active. `time_elapsed` remains the
snapshot duration used by storage dynamics.

## 8. Global Security Fields

The converter must provide the physical data needed by downstream gSCR
templates:

- `grid_control_mode` for GFL/GFM classification;
- `b_block` for GFM strength contribution;
- `p_block_max` for GFL exposure.

If the converter package owns scenario/case export, it must provide `g_min` at
network/case level only for cases that will be solved with gSCR constraints.

`g_min` is a case-level scalar, not a per-device field. It must be provided
explicitly in gSCR cases; no silent default is permitted.

The converter does not choose:

- `NoGSCR`;
- `GershgorinGSCR`;
- `OnlineNameplateExposure`.

Those are downstream model-template choices.

The linear Gershgorin condition consumed downstream is:

\[
\sigma_n^{0,G}
+
\sum_{k:\phi(k)=n,\;grid\_control\_mode(k)=gfm}
b_k^{block}n_{a,k,t}
\ge
\underline g
\sum_{i:\phi(i)=n,\;grid\_control\_mode(i)=gfl}
P_i^{block,max}n_{a,i,t}.
\]

## 9. No Template Serialization

The converter should not serialize downstream formulation objects or policy
fields, including:

- `BlockThermalCommitment`;
- `BlockRenewableParticipation`;
- `BlockFixedInstalled`;
- `NoGSCR`;
- `GershgorinGSCR`;
- `OnlineNameplateExposure`;
- `activation_policy`;
- `uc_policy`;
- `gscr_exposure_policy`.

Human-facing documentation may recommend default mappings, for example:

| Carrier or class | Possible downstream formulation |
|---|---|
| `CCGT`, `OCGT` | `BlockThermalCommitment` |
| `wind`, `solar` | `BlockRenewableParticipation` |
| `BESS-GFL`, `BESS-GFM` | `BlockFixedInstalled` |

These mappings are not exported as device fields.

## 10. Quantities to Precompute

### Full Susceptance Matrix

Build from the extracted AC-side PowerModels network only:

\[
B^0.
\]

Policy:

- mixed AC/DC optimization cases are allowed;
- \(B^0\) for gSCR is computed from AC `bus`/`branch` tables only;
- AC-side extraction ambiguity is a hard explicit error;
- disconnected AC-side graphs are allowed; compute row metrics bus-by-bus.

### Gershgorin Margin

\[
\sigma_n^{0,G}
=
B^0_{nn}
-
\sum_{j\ne n}|B^0_{nj}|.
\]

Store:

```julia
:gscr_sigma0_gershgorin_margin
```

gSCR constraints are indexed over AC buses only. GFL/GFM block contributions
enter through their AC terminal bus mapping \(\phi(k)\).

### Raw Row Sum for Diagnostics

Optionally store:

```julia
:gscr_sigma0_raw_rowsum
```

This is diagnostic-only and is not used as a security certificate.

## 11. Validation Checklist

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
- `startup_cost_per_mw` and `shutdown_cost_per_mw` are per MW if present.
- `p_min_pu` and `p_max_pu` are scalar or time-series compatible with exported snapshots.
- `operation_weight`, if present, is `1.0` in the canonical `scale_data!` workflow.
- `time_elapsed` exists for every snapshot.
- `e_block` exists for block-enabled `storage` and `ne_storage`.

## 12. Backward Compatibility

Cases without block-enabled records remain outside this schema. Once block data
is exported, the schema-v2 marker and fields above are required; v2 must not be
silently inferred from older v1-style fields.
