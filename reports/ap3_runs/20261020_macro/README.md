# AP3 evidence run 20261020_macro

Authoritative selected model records: accepted_suite (162 entries, 124 optimal, 36 infeasible, two numerical_inconclusive). Source provenance records which immutable raw attempt supplies each selected solution. The selection never rewrites the original run status files.

Final independent artifacts: matrices_final, metrics_final, certificates_final, comparisons_final, planning_final, benchmarks_final, enumeration_final, plots_final, integer_bound_audit.json, metric_coverage.json and validation_summary.json. matrices_replay is a second byte-identical reconstruction. cli_replay_suite is a separate three-model continuous BASE/G0/G3 execution using only copied relative input paths; it is not counted as part of the selected 162. benchmarks_function_reference preserves the first function-level benchmark; benchmarks_final is the actual standalone CLI execution.

Directories and logs containing attempt, before, smoke or function_reference, plus suite_final and the solver-repeat directories, preserve development and numerical history. They are not substitutes for the designated final outputs. In particular native integer G3 false infeasibility remains visible. All nine projected integer reference intervals are independently reconstructed numerical bound checks, not native success promotions or independent A3.5 acceptance.

Large raw metrics.json and metrics.csv remain local and are published in adjacent metrics-json.zip and metrics-csv.zip. Extract each ZIP into its parent directory before saved-data tests or exhaustive evidence-index verification on a fresh clone. metric_archive_verification.json proves raw/archive-entry byte identity. All other matrix/case/solution JSON files are ordinary tracked files. Windows path separators in historical manifests are accepted by the recorded Windows replay environment.

Worker results: ../../paper_a_ap3_validation.md and ../../paper_a_ap3_status.yaml. Exact executed CLI argument/exit records and publication receipts are outside this run root, in reports/, to avoid self-changing index entries. export_final/evidence_index.json hashes every file present before the final export. The export's own index/provenance files are deliberately not self-hashed. No later file writers may modify the run root after that export.

Worker status AP3_partial; empirical approval false; A3_closed=false; AP4_ready=false. See blocker_register.json and docs/paper_a/ap3_to_a3_5_handoff.md for the precise independent follow-on scope.
