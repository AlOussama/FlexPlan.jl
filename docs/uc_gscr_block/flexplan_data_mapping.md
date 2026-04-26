# FlexPlan Data Mapping and Extensions

## 1. Existing FlexPlan/PowerModels data to reuse

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

Use this to build the gSCR baseline \(B^0\) on the AC-side network.
DC buses, DC branches, and DC-side converter elements do not enter \(B^0\).

### `gen`

Use for existing controllable devices.

Extend with:

```julia
type
n0
nmax
p_block_min
p_block_max
q_block_min
q_block_max
b_block
H
s_block
cost_inv_block
startup_block_cost
shutdown_block_cost
na0
```

If the existing generator table is not suitable for new fields, use an auxiliary table such as `gen_block`.

### `storage` and `ne_storage`

Use for storage-capable devices.

Extend candidate storage first because FlexPlan already has candidate-storage expansion structure.

Add:

```julia
type
n0
nmax
p_block_min
p_block_max
q_block_min
q_block_max
b_block
e_block
H
s_block
cost_inv_block
startup_block_cost
shutdown_block_cost
na0
```

### `time_elapsed`

Use as:

\[
\Delta t.
\]

### Multinetwork / time-series data

Use existing FlexPlan multinetwork/time-series machinery for:

- time-varying loads;
- renewable availability;
- hour/scenario/year snapshot indexing;
- storage dynamics across ordered snapshots.

The installed block variable \(n\) must be shared across snapshots.

The active block variable \(n_a(t)\) is snapshot-specific.

## 2. New common fields

| Field | Meaning |
|---|---|
| `type` | `"gfl"` or `"gfm"` |
| `n0` | initially installed blocks |
| `nmax` | maximum installed blocks |
| `na0` | initially active/online blocks at first snapshot |
| `p_block_min` | active lower bound per active block |
| `p_block_max` | active upper bound per active block |
| `q_block_min` | reactive lower bound per active block |
| `q_block_max` | reactive upper bound per active block |
| `b_block` | per-block GFM susceptance/strength contribution |
| `H` | inertia time constant for later RoCoF/inertia constraints |
| `s_block` | rating used with \(H\), optional |
| `cost_inv_block` | investment cost per added block |
| `startup_block_cost` | startup cost per started block |
| `shutdown_block_cost` | shutdown cost per shut-down block |
| `min_up_block_time` | minimum online duration after startup, in snapshots |
| `min_down_block_time` | minimum offline duration after shutdown, in snapshots |

### Unit and base conventions for block fields

Use the following internal-unit conventions consistently across `gen`,
`storage`, and `ne_storage`:

| Field | Internal unit/base convention |
|---|---|
| `p_block_min`, `p_block_max` | same internal base as `pg`, `ps`, `ps_ne`, `sc`, `sd`, `sc_ne`, `sd_ne` |
| `q_block_min`, `q_block_max` | same internal base as `qg`, `qs`, `qs_ne` |
| `e_block` | same internal base as `se`, `se_ne` |
| `s_block` | same base convention as the rating quantity used in CbaOPF-style inertia aggregation |
| `H` | inertia time constant; do not power-scale |
| `b_block` | per-unit admittance/susceptance contribution in the same base as shunt admittances and line susceptance terms (\(1/x\)); it is not defined as a direct copy of any single line \(1/br_x\) value |
| `cost_inv_block` | pure investment-cost coefficient (objective-level use); do not MVA-base scale |
| `startup_block_cost`, `shutdown_block_cost` | pure startup/shutdown objective coefficients per block count; do not MVA-base scale |

For later inertia aggregation, use:

\[
\sum_k H_k \, s_k^{block} \, n_{a,k,t}.
\]

Current FlexPlan candidate-storage investment cost in the objective is modeled
as:

\[
(\text{eq\_cost} + \text{inst\_cost}) \cdot z^{investment}.
\]

For block expansion, use:

\[
\text{cost\_inv\_block}\cdot p_{k}^{block,max}\cdot(n_k - n_k^0).
\]

`cost_inv_block` is treated as a pure investment coefficient at objective
level. Planning-horizon depreciation/scaling for this custom field is left as a
TODO and must be handled explicitly when block-investment objective terms are
implemented.

Schema validation policy for block fields:

- no silent guessing of missing required mathematical fields;
- explicit warning/report listing missing required fields;
- hard validation error if required fields are missing.

For simplified block startup/shutdown counting, the required explicit fields
are:

- `na0`;
- `startup_block_cost`;
- `shutdown_block_cost`.

For block minimum up/down-time constraints (count-based UC extension), the
feature is enabled when these fields are provided on block devices, and then
both are required explicitly:

- `min_up_block_time`;
- `min_down_block_time`.

They are integer numbers of snapshots and are not inferred from hourly
durations.

## 3. Global security fields

| Field | Meaning |
|---|---|
| `g_min` | global minimum gSCR/ESCR strength threshold \(\underline g\) |

`g_min` is a case-level scalar, not a per-device field.
It must be provided explicitly in the network data; no silent default is permitted.

`g_min` is dimensionless when all strength and power quantities are expressed on a consistent per-unit base (susceptance in p.u., active power in p.u.).

`g_min` appears in two constraints:

**LP/MILP-compatible Gershgorin sufficient condition** (implemented first):

\[
\sigma_n^{0,G}
+
\sum_{k:\phi(k)=n,\;type(k)=gfm}
b_k^{block}n_{a,k,t}
\ge
\underline g
\sum_{i:\phi(i)=n,\;type(i)=gfl}
P_i^{block}n_{a,i,t}
\qquad \forall n,t.
\]

**Global full-network SDP/LMI condition** (implemented later):

\[
B_t - \underline g\, S_t \succeq 0.
\]

## 4. Storage-specific fields

| Field | Meaning |
|---|---|
| `e_block` | energy capacity per installed block |
| `energy_to_power` | optional fallback for `e_block` |
| `charge_efficiency` | storage charge efficiency |
| `discharge_efficiency` | storage discharge efficiency |
| `self_discharge_rate` | optional |

## 5. Quantities to precompute

### Full susceptance matrix

Build from the extracted AC-side PowerModels network only:

\[
B^0.
\]

Policy:

- mixed AC/DC optimization cases are allowed;
- \(B^0\) for gSCR is computed from AC `bus`/`branch` tables only;
- AC-side extraction ambiguity is a hard explicit error;
- disconnected AC-side graphs are allowed; compute row metrics bus-by-bus.

### Gershgorin margin

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

### Raw row sum for diagnostics

Optionally store:

```julia
:gscr_sigma0_raw_rowsum
```

This is diagnostic-only and is not used as a security certificate.

## 6. Backward compatibility

If no block fields exist, the new module should do nothing.

Existing FlexPlan examples should continue to run.
