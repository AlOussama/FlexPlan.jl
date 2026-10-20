$ErrorActionPreference='Stop'
$run='D:/Projekte/Code/FlexPlan_A35_EXEC_RUN'
$base='D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE'
$fix='D:/Projekte/Code/FlexPlan_A35_EXEC_REVIEW'
$python='C:/Users/User/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$audit="$fix/reports/a3_5/executable_closure_20261020"
$env:PYTHONPATH="$run/python_deps"
Set-Location $base
& $python "$audit/independent_reference_oracle.py" $run $base *> "$run/oracle_final.log"
if($LASTEXITCODE -ne 0){throw 'oracle_final failed'}
& $python "$audit/independent_integer_summary.py" $run $base *> "$run/integer_summary_final.log"
if($LASTEXITCODE -ne 0){throw 'integer_summary_final failed'}
& $python "$audit/independent_metric_audit.py" $run $base *> "$run/independent_metrics_final.log"
if($LASTEXITCODE -ne 0){throw 'independent_metrics_final failed'}
Set-Location $fix
& julia +1.10.11 --startup-file=no --project=. scripts/paper_a/ap3.jl evaluate_strength_metrics "$run/matrices" "$run/metrics_unit_fix" *> "$run/fixed_metric_reexport.log"
if($LASTEXITCODE -ne 0){throw 'fixed_metric_reexport failed'}
Set-Location $base
& julia +1.10.11 --startup-file=no --project=. scripts/paper_a/ap3.jl unknown_action "$run/suite" "$run/negative_output" *> "$run/negative_cli_unknown.log"
$unknownExit=$LASTEXITCODE
& julia +1.10.11 --startup-file=no --project=. scripts/paper_a/ap3.jl reconstruct_strength_matrices "$run/missing_input" "$run/negative_missing_output" *> "$run/negative_cli_missing.log"
$missingExit=$LASTEXITCODE
& julia +1.10.11 --startup-file=no --project=. scripts/paper_a/ap3.jl reconstruct_strength_matrices "$run/suite" "$run/matrices" *> "$run/negative_cli_overwrite.log"
$overwriteExit=$LASTEXITCODE
@{unknown_exit=$unknownExit;missing_exit=$missingExit;overwrite_exit=$overwriteExit}|ConvertTo-Json|Set-Content "$run/negative_cli_results.json"
if($unknownExit -eq 0 -or $missingExit -eq 0 -or $overwriteExit -eq 0){throw 'negative CLI guard failed'}
exit 0
