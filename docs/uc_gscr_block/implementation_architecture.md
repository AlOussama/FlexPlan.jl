# Implementation Architecture

## 1. Main principle

Use PowerModels/FlexPlan multiple-dispatch architecture.

Do not implement a one-off script.

## 2. Recommended source layout

```text
src/core/block_variable.jl
src/core/block_constraint_template.jl
src/core/block_constraint.jl
src/core/block_expression.jl
src/core/block_objective.jl
src/core/gscr_ref_extension.jl
src/core/gscr_constraint_template.jl
src/core/gscr_constraint.jl
src/prob/uc_gscr_block.jl
```

Exact names may be adapted to the existing repository style.

## 3. Reference extension

Build:

```julia
:gfl_devices
:gfm_devices
:bus_gfl_devices
:bus_gfm_devices
:gscr_sigma0_gershgorin_margin
:gscr_sigma0_raw_rowsum
```

Policy for mixed AC/DC cases:

- do not restrict the optimization model to AC-only systems;
- compute gSCR `B0`/sigma0 from extracted AC `bus`/`branch` tables only;
- ignore DC buses/branches/DC-side converter elements in `B0`;
- throw an explicit error when AC-side extraction is ambiguous;
- allow disconnected AC graphs and compute sigma0 row-wise.

## 4. Variables

Installed block variable:

```julia
:n_block
```

or component-specific:

```julia
:n_gen_block
:n_storage_block
```

Active block variable:

```julia
:na_block
```

or component-specific:

```julia
:na_gen_block
:na_storage_block
```

The installed variable is shared across snapshots.

The active variable is per snapshot.

## 5. Expressions

Bus-level GFL online capacity:

```julia
:p_gfl_online_bus
```

Bus-level GFM strengthening contribution:

```julia
:b_gfm_online_bus
```

Later global LMI matrices:

```julia
:B_gscr_affine
:S_gscr_affine
```

or directly build the PSD matrix expression.

## 6. Constraints

Block constraints:

```julia
constraint_installed_block_bounds
constraint_active_blocks_le_installed
constraint_block_active_power_dispatch
constraint_block_reactive_power_dispatch
constraint_storage_block_energy_capacity
```

gSCR constraints:

```julia
constraint_gscr_gershgorin_sufficient
constraint_gscr_global_lmi
```

The global LMI is a later SDP module.
gSCR constraint indexing is over AC buses only, and device contributions use
their AC terminal bus mapping \(\phi(k)\).

## 7. Formulation compatibility

The following are formulation-independent:

- installed/active block bounds;
- gSCR Gershgorin sufficient condition;
- global gSCR LMI;
- investment cost.

The following need formulation-specific methods:

- active-power balance;
- line-flow constraints;
- reactive dispatch constraints;
- AC/branch-flow/conic network constraints.

## 8. First implementation target

LP with:

```julia
relax = true
```

and Gershgorin sufficient gSCR constraint.

Do not start with SDP or MISDP.
