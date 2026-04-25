# Codex Task 01 — Reference Extension Only

## Goal

Add data/reference support for block UC/gSCR.

Do not add optimization variables yet.

## Read first

```text
docs/uc_gscr_block/flexplan_data_mapping.md
docs/uc_gscr_block/gscr_global_lmi_and_gershgorin.md
docs/uc_gscr_block/implementation_architecture.md
docs/tests/flexplan_test_data_plan.md
docs/review_workflow/documentation_quality_requirements.md
docs/tests/test_specification.md
```

## Implement

1. Parse/read fields:
   - `type`
   - `n0`
   - `nmax`
   - `p_block_min`
   - `p_block_max`
   - `q_block_min`
   - `q_block_max`
   - `b_block`
   - optional `H`, `s_block`, `e_block`.

2. Build reference maps:
   - `gfl_devices`;
   - `gfm_devices`;
   - `bus_gfl_devices`;
   - `bus_gfm_devices`.

3. Build full-network susceptance matrix \(B^0\) or compute row metrics from branch data.

4. Store:
   - `gscr_sigma0_gershgorin_margin`;
   - `gscr_sigma0_raw_rowsum`.

5. Add tests:
   - type classification;
   - bus mapping;
   - row metric computation;
   - missing-field validation.

6. Add docstrings for every new function.

## Do not implement

- `n` variables;
- `na` variables;
- dispatch constraints;
- gSCR constraints;
- objective terms;
- SDP/LMI.
