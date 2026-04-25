---
applyTo: "test/**/*.jl"
---

For tests:

- Each test must state which equation or implementation rule it validates.
- Start with small deterministic cases before integration cases.
- Use the test-data ladder in `docs/tests/flexplan_test_data_plan.md`.
- Test relaxed mode first: `relax=true`.
- Include regression tests for cases without block fields.
- Do not use large time-series cases for first debugging.