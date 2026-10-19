# AP3 independent postprocessing user guide

Use Julia 1.10.11 with the committed Project.toml and Manifest-v1.10.toml. Install with `julia --project=. -e 'using Pkg; Pkg.instantiate()'`. Clarabel and Pajarito are pinned additions; existing package versions are preserved. Gurobi is optional and its actual license is probed. No network/data authority gate is relaxed by selecting a solver.

All commands run from the repository root. INPUT and OUTPUT are explicit paths. Relative case/registry/scenario paths in a suite configuration resolve against that configuration's directory. Output directories/configs must not already exist: select a new run ID, retain failed attempts. No private filesystem location is hardcoded in the implementation.

```powershell
julia --project=. scripts/paper_a/make_suite_config.jl PRODUCER_ROOT new_suite.json
julia --project=. scripts/paper_a/ap3.jl run_formulation_suite new_suite.json results/new_run/suite
julia --project=. scripts/paper_a/ap3.jl reconstruct_strength_matrices results/new_run/suite results/new_run/matrices
julia --project=. scripts/paper_a/ap3.jl evaluate_strength_metrics results/new_run/matrices results/new_run/metrics
julia --project=. scripts/paper_a/ap3.jl verify_certificates results/new_run/matrices results/new_run/certificates
julia --project=. scripts/paper_a/ap3.jl compare_formulations results/new_run/suite results/new_run/comparisons
julia --project=. scripts/paper_a/ap3.jl assess_planning_results results/new_run/suite results/new_run/planning
julia --project=. scripts/paper_a/ap3.jl benchmark_conic_scaling new_suite.json results/new_run/benchmarks
julia --project=. scripts/paper_a/ap3.jl export_paper_a_evidence results/new_run results/new_run/export
```

For a single case, use JSON `{ "AP1_SHA":"...", "cases":[{"id":"reference_3snap","case":"relative/case.json","registry":"parameter_registry.csv","scenarios":"study_scenarios.toml"}],"relaxations":[true,false] }`. Optional `formulations` selects explicit IDs from the candidate registry, and `sizes` specifies benchmark sizes. Strategies are computed and saved before solving. Seed 20261020, fixed initial/terminal SOC, scope parametric_study and discharge-only storage price match the accepted consumer contract. Only requested valid synthetic/registered cases are accepted. Cost scaling is applied once. A positive objective normalization for conic conditioning is recorded; reported objective/bound are restored to the original currency scale.

Outputs use schema paper_a_ap3/1.0. Suite copies immutable case bytes, producer case manifest and canonical registration files, saves parameter matrices, per-solve numerical asset/flow decisions, affine matrices for comparison, solver statuses and gaps, versions and source/input hashes. The independent reconstruction does not read JuMP coefficients, cached Y/B0, or solver slacks. G3 q is read as a witness only and independently checked; G0 can obtain a separate T018 constructive scaling witness. Domain failures and undefined denominators have explicit statuses and null values.

`run_paper_a_ap3.jl` runs the frozen mathematical and integrated finite integer references. `AP3Pipeline.enumerate_tiny(NEW_DIRECTORY)` supplies the separate complete tiny M0 discrete benchmark. This reference is not a full-scale nonlinear M0 optimizer. E2 is an executable noncertifying diagnostic with a controlled remainder; no bilinear inverse expression is mislabeled LP.

To replay saved evidence without the producer checkout, point a new suite configuration at copied suite/<case_id>/case.json and its copied registry/scenarios. Postprocessing accepts the saved suite directly and requires no optimization rerun. The machine evidence index hashes every input/output file under the run root, excluding its subsequently written index itself. metrics.csv JSON-valued cells preserve arrays and units. Logs and failed attempts are retained. The validation report specifies actual executions, counts and numerical limits; these example commands alone do not claim a PASS.

Empirical network/source/economic qualification and scientific study-design approval remain open. Worker verification is not independent A3.5 acceptance.
