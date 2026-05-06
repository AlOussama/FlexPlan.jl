# UC/gSCR Block Architecture Decisions

This document records locked architecture decisions for the planned UC/gSCR
block generation-expansion refactor. It is an implementation target, not a
claim that the repository already implements every item.

## 1. Block-Only Storage Architecture

The UC/gSCR block path must remain separate from the standard FlexPlan binary
candidate-storage path.

In block mode:

- do not use `z_strg_ne` or `z_strg_ne_investment`;
- do not use standard candidate-storage activation constraints;
- do not use standard candidate-storage investment cost;
- use block variables and block-scaled constraints as the source of truth.

Later implementation must add hard validation that rejects mixed binary/block
storage formulations in the same optimization model. A storage asset must be
handled by either the standard binary candidate-storage formulation or the
UC/gSCR block formulation, never both.

## 2. Data and Model Separation

Input data must contain physical and interface fields only. Formulation
behavior is assigned by a model template and must not be encoded as data policy
fields.

Do not use these data fields:

- `activation_policy`;
- `uc_policy`;
- `gscr_exposure_policy`.

Replace the old ambiguous physical field `type` with:

```text
grid_control_mode in {"gfl", "gfm"}
```

`grid_control_mode` describes the device interface with the AC grid. It does
not choose the mathematical formulation.

## 3. Schema v2 Contract

Every block-data case must declare:

```text
block_model_schema.name = "uc_gscr_block"
block_model_schema.version = "2.0"
```

Schema v2 rejects old ambiguous fields, including:

- `type`;
- `cost_inv_block`;
- `startup_block_cost`;
- `shutdown_block_cost`.

Use the v2 cost fields:

- `cost_inv_per_mw`;
- `startup_cost_per_mw`;
- `shutdown_cost_per_mw`.

## 4. Block Variable Semantics

For every block-enabled device \(k\):

- \(n_k^{block}\), stored as `n_block`, is installed blocks after expansion;
- \(n_k^0\), stored as `n0`, is initial installed blocks;
- \(n_k^{max}\), stored as `nmax`, is maximum installed blocks;
- \(n_{a,k,t}^{block}\), stored as `na_block`, is active or participating
  blocks at snapshot \(t\).

Existing, fixed, expandable, and candidate resources use the same block
representation:

| Resource state | Block representation |
|---|---|
| Fixed | `n0 = nmax` |
| Expandable | `nmax > n0` |
| Pure candidate | `n0 = 0` |
| Phased out | Removed before model build, or `n0 = nmax = na0 = 0` |

The installed block variable is shared across snapshots. The active block
variable is snapshot-specific.

## 5. Formulation Template Architecture

A lightweight model-template layer will be added later. The template assigns
formulation objects by `(table, carrier)`, with optional exact
`(table, device_id)` overrides.

The model template is a model-build input, not a data field. Converter outputs
must provide physical/interface data; the caller that builds the optimization
model provides or selects the template.

Rules:

- every block-enabled device must resolve to exactly one formulation;
- there is no silent default for unmapped block devices;
- exact `(table, device_id)` overrides take precedence over `(table, carrier)`
  assignments;
- template resolution happens inside the model builder;
- formulation-specific device sets are cached in `pm.ext`.

`ref_add_uc_gscr_block!` must remain limited to physical/interface validation,
GFL/GFM maps, and AC-side `B0`/Gershgorin metrics. It must not become the place
where model behavior is chosen.

## 6. Initial Formulation Objects

Planned block-device formulation hierarchy:

```julia
AbstractBlockDeviceFormulation
BlockThermalCommitment
BlockRenewableParticipation
BlockFixedInstalled
BlockStorageParticipation  # future/optional
```

Planned gSCR formulation hierarchy:

```julia
AbstractGSCRFormulation
NoGSCR
GershgorinGSCR
```

Planned gSCR exposure hierarchy:

```julia
AbstractGSCRExposure
OnlineNameplateExposure
```

The first optimization formulations are only `NoGSCR` and `GershgorinGSCR`.
More advanced gSCR formulations are later extensions.

## 7. Default Paper Template

The default paper template assigns:

| Device class | Formulation |
|---|---|
| `CCGT`, `OCGT` | `BlockThermalCommitment` |
| `wind`, `solar` | `BlockRenewableParticipation` |
| `BESS-GFL`, `BESS-GFM` | `BlockFixedInstalled` |
| gSCR case | `GershgorinGSCR(OnlineNameplateExposure)` |
| BASE case | `NoGSCR` |

Biomass and pumped hydro must be assigned explicitly. They must not be inferred
from a broad fallback rule.

## 8. Formulation-Specific Behavior

Variables created for all block-enabled devices:

- `n_block`;
- `na_block`.

Variables created only for `BlockThermalCommitment` devices:

- `su_block`;
- `sd_block`.

Startup/shutdown transitions apply only to `BlockThermalCommitment` devices.

`BlockFixedInstalled` imposes:

\[
n_{a,k,t}^{block} = n_k^{block}.
\]

`BlockRenewableParticipation` imposes:

\[
0 \le n_{a,k,t}^{block} \le n_k^{block},
\]

with no startup/shutdown variables.

## 9. Dispatch and Storage Bounds

Block-scaled bounds are the source of truth for block-enabled devices. Standard
PowerModels/FlexPlan fixed bounds must be removed, bypassed, or validated as
nonbinding.

Active dispatch:

\[
p_{k}^{min,pu} P_k^{block,max} n_{a,k,t}^{block}
\le
p_{k,t}
\le
p_{k}^{max,pu} P_k^{block,max} n_{a,k,t}^{block}.
\]

Reactive dispatch:

\[
Q_k^{block,min} n_{a,k,t}^{block}
\le
q_{k,t}
\le
Q_k^{block,max} n_{a,k,t}^{block}.
\]

Storage:

\[
e_{k,t} \le E_k^{block} n_k^{block},
\]

\[
p_{k,t}^{charge}, p_{k,t}^{discharge}
\le
P_k^{block,max} n_{a,k,t}^{block}.
\]

Reactive handling should follow the existing PowerModels/FlexPlan
multiple-dispatch style. Active-power-only formulations should provide no-op
methods for reactive constraints where required by dispatch.

## 10. gSCR Formulation

`GershgorinGSCR` uses `OnlineNameplateExposure` by default:

\[
P_{fl,n,t}
=
\sum_{k:\phi(k)=n,\ grid\_control\_mode(k)=gfl}
P_k^{block,max} n_{a,k,t}^{block}.
\]

The current Gershgorin condition is the MILP-compatible sufficient condition:

\[
\sigma_{n}^{G,0}
+
\sum_{k:\phi(k)=n,\ grid\_control\_mode(k)=gfm}
B_k^{block} n_{a,k,t}^{block}
\ge
g^{min}
\sum_{i:\phi(i)=n,\ grid\_control\_mode(i)=gfl}
P_i^{block,max} n_{a,i,t}^{block}.
\]

`g_min` is required only when the selected gSCR formulation needs it. Post-solve
verification should later compute eigenvalue and gSCR margins as diagnostics.

## 11. Objective and Costs

### Cost Handling: FlexPlan OPEX Scaling and PyPSA-Eur-Style Annualized CAPEX

Original FlexPlan annualizes OPEX-like coefficients in
[`src/io/scale.jl`](../../src/io/scale.jl) before `make_multinetwork`. The
operational scaling factor is:

\[
8760 \cdot year\_scale\_factor / number\_of\_hours.
\]

This project uses the same approach for UC/gSCR block OPEX. For the common
study setup of one scenario with probability 1.0, one model year,
`year_scale_factor = 1`, and a representative horizon of `number_of_hours =
N_h`, the OPEX factor is:

\[
8760 / N_h.
\]

The factor applies to standard generator dispatch costs, non-dispatchable
curtailment costs, load operation costs where applicable, and UC/gSCR block
startup/shutdown costs. `operation_weight` must not be used as an additional
annualization multiplier in [`src/core/objective.jl`](../../src/core/objective.jl).
If the field remains present for compatibility, it is ignored for cost
annualization when `scale_data!` is active.

UC/gSCR block CAPEX follows the PyPSA-Eur annualized-capex convention used by
[`scripts/process_cost_data.py`](https://github.com/PyPSA/pypsa-eur/blob/master/scripts/process_cost_data.py)
and documented in
[`doc/costs.rst`](https://github.com/PyPSA/pypsa-eur/blob/master/doc/costs.rst):

\[
(annuity(lifetime, discount\_rate) + FOM/100) \cdot investment \cdot nyears.
\]

For UC/gSCR block devices, `cost_inv_per_mw` is raw overnight investment cost
per MW before `scale_data!`. The repository annualizes it as:

\[
cost\_inv\_per\_mw \cdot
(annuity(lifetime, discount\_rate) + fixed\_om\_percent/100) \cdot
year\_scale\_factor.
\]

When `discount_rate = 0` and `fixed_om_percent = 0`, this reduces to:

\[
overnight\ CAPEX / lifetime.
\]

For the one-year zero-discount, zero-FOM case, this is consistent with
FlexPlan's residual-value treatment of investments.

| Topic | Original FlexPlan | PyPSA-Eur | UC/gSCR block decision |
|---|---|---|---|
| OPEX time weighting | `scale_data!` scales hourly OPEX by \(8760 \cdot year\_scale\_factor / number\_of\_hours\) | Snapshot weights time-weight operation | Use FlexPlan `scale_data!`; no extra `operation_weight` multiplier |
| CAPEX treatment | Candidate investments use lifetime/residual-value scaling | Annualized capital cost \((annuity + FOM/100) \cdot investment \cdot nyears\) | Annualize raw `cost_inv_per_mw` before objective |
| Lifetime use | Investment residual value | Annuity term | Required for expandable block devices |
| Discount rate use | Not in the original residual-value rule | Annuity term | Device value, then explicit case assumption |
| FOM use | Not in the original residual-value rule | Added as `FOM/100` | Device value, then explicit case assumption |
| Scenario probability use | Applied separately in stochastic objectives | Separate from snapshot weights | Scenario probabilities stay in stochastic objectives |
| Multi-year handling | Year dimensions and residual value | `nyears` multiplier | `year_scale_factor` multiplier for annualized block CAPEX |

Investment cost:

\[
C_k^{inv}
=
c_k^{inv/MW} P_k^{block,max}(n_k^{block} - n_k^0).
\]

Startup/shutdown costs:

\[
C_{k,t}^{su}
=
c_k^{su/MW} P_k^{block,max} su_{k,t}^{block},
\]

\[
C_{k,t}^{sd}
=
c_k^{sd/MW} P_k^{block,max} sd_{k,t}^{block}.
\]

Operation costs use coefficients already scaled by `scale_data!`. Operation
weights do not apply to dispatch, startup/shutdown, or investment cost in the
canonical UC/gSCR block workflow.

Marginal dispatch cost should keep using standard dispatch cost fields unless
that objective layer is explicitly refactored later.

No-load cost, ramping, and additional UC features are later extensions.

## 12. Storage Terminal Policies

Planned storage terminal policy options:

| Policy | Terminal condition |
|---|---|
| `:cyclic` | \(e_T = e_1\) |
| `:fixed_initial` | \(e_T = e^{initial}\) |
| `:relaxed_cyclic` | \(e_T \ge storage\_terminal\_fraction \cdot e_1\) |
| `:none` | no terminal condition |

Storage terminal policy is formulation/model-build behavior. It must not be
encoded through device data policy fields such as `activation_policy` or
`uc_policy`.

## 13. Network Formulation

Follow PowerModels/FlexPlan model-type dispatch. Do not add a custom
`network_model` keyword.

The selected PowerModels model type determines the network physics. Use
FlexPlan-extended balance templates when candidate storage or FlexPlan
extensions must enter the power balance.

The network formulation choice is therefore a standard model-type choice at
model build time, separate from schema-v2 device data and separate from the
UC/gSCR block formulation template.

## 14. Interface Scope

This repository does not implement the PyPSA converter.

External converter packages are responsible for writing model-ready data. This
repository defines the schema, validates the interface, builds the model, and
reports diagnostics.

## 15. Testing Strategy

Acceptance should be layered:

1. schema/interface tests;
2. template matching and compatibility tests;
3. small optimization tests;
4. full converted-case tests only after small tests pass.
