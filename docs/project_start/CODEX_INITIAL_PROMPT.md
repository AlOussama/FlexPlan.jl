# Initial Codex Prompt

You are working in a FlexPlan/PowerModels-style Julia repository.

Implement the project according to:

```text
docs/block_expansion/
docs/uc_gscr_block/
docs/tests/
docs/review_workflow/documentation_quality_requirements.md
```

Start with:

```text
codex_tasks/01_reference_extension.md
```

Important:

- Do not add optimization variables in task 1.
- Do not implement the gSCR inequality in task 1.
- Do not introduce a reduced network.
- Do not use data-driven linearization.
- Use full-network \(B^0\).
- Add tests for every change.
- Add docstrings for every new function.
- If ambiguous, document the question under `docs/uc_gscr_block/`.
