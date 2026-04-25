# Start Here

## Step 0 — Human mathematical review

Review these files before any code changes:

```text
docs/block_expansion/mathematical_formulation.md
docs/uc_gscr_block/gscr_global_lmi_and_gershgorin.md
docs/uc_gscr_block/flexplan_data_mapping.md
docs/tests/flexplan_test_data_plan.md
docs/review_workflow/documentation_quality_requirements.md
docs/review_workflow/codex_copilot_roles.md
```

## Step 1 — Repository setup

Add:

```text
.github/copilot-instructions.md
.github/PULL_REQUEST_TEMPLATE/uc_gscr_block.md
```

## Step 2 — Codex first task

Use:

```text
codex_tasks/01_reference_extension.md
```

This first task is data/reference support only.

## Step 3 — Review cycle

Every Codex and Copilot contribution must be reviewed.

Rule:

```text
No generated code is accepted unless it is traceable to a documented equation, has docstrings, and is covered by a test.
```
