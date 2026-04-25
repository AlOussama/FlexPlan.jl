# Documentation and Implementation Quality Requirements

## 1. Every new function must have a docstring

Every new Julia function added for this project must have a docstring immediately above the function definition.

This includes:

- parser helpers;
- reference-extension functions;
- variable constructors;
- expression builders;
- constraint templates;
- formulation-specific constraint methods;
- objective helpers;
- solution-reporting helpers;
- test helper functions.

## 2. Required docstring content

Each docstring must include:

1. one-line purpose;
2. mathematical meaning if applicable;
3. important arguments;
4. assumptions and units;
5. whether the function is formulation-independent or formulation-specific;
6. whether it mutates data or model state.

Example:

```julia
#=
    constraint_gscr_gershgorin_sufficient(pm, n; nw=nw_id_default)

Adds the linear Gershgorin sufficient gSCR/ESCR condition at bus `n`
for network snapshot `nw`:

    gscr_sigma0_gershgorin_margin[n] + sum(b_block[k] * na[k] for k in gfm_at_bus[n])
        >= g_min * sum(P^{block}[i] * na[i] for i in gfl_at_bus[n])

This constraint is formulation-independent and LP/MILP-compatible.
It uses the full-network Gershgorin margin, not a reduced network.
=#
```

## 3. Constraint-template docstrings

Every constraint-template function must state:

- which equation it implements;
- which reference data it reads;
- which lower-level formulation method it calls;
- whether it is no-op for any formulation.

## 4. Formulation-specific method docstrings

Every formulation-specific method must state:

- which PowerModels formulation family it targets;
- which variables it assumes exist;
- why it differs from the generic method.

For active-power-only reactive constraints, document explicitly that the method is a no-op because reactive variables are absent.

## 5. Data-schema documentation

Every new input field must be documented in:

```text
docs/uc_gscr_block/flexplan_data_mapping.md
```

and in parser error messages if missing or invalid.

## 6. Error-message quality

Validation errors must be explicit.

Bad:

```text
invalid data
```

Good:

```text
GFM device 7 is missing required field `b_block`.
The gSCR Gershgorin constraint uses b_block * na as the per-block
susceptance contribution.
```

## 7. Test quality

Every new function must be covered by at least one test unless it is a thin wrapper.

Each test must state what equation or rule it validates.

Prefer small deterministic tests before integration tests.

## 8. No silent fallback for mathematical fields

Do not silently guess:

- `type`;
- `b_block`;
- `g_min`;
- `n0`;
- `nmax`.

Fallbacks are allowed only for documented convenience fields such as:

```text
p_block = p_block_max
s_block = p_block_max
e_block = energy_to_power * p_block_max
```

and only if explicitly documented.

## 9. Formatting and style

Requirements:

- keep functions short;
- avoid duplicating loops over devices where helper functions are clearer;
- use descriptive names;
- preserve existing project style;
- avoid broad refactors in feature PRs.

## 10. Review requirement

Codex and Copilot may write code, but every PR must include:

- changed files;
- equations implemented;
- functions added and docstrings status;
- tests added;
- tests run;
- limitations;
- open assumptions.

No PR should be merged without human mathematical review.
