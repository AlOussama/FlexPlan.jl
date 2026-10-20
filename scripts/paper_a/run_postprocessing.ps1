param([Parameter(Mandatory=$true)][string]$Julia,[Parameter(Mandatory=$true)][string]$RunRoot)
$ErrorActionPreference='Stop'
$taskRunRoot=(Resolve-Path -LiteralPath $RunRoot).Path
$taskCommands=[System.Collections.Generic.List[object]]::new()
function Invoke-AP3Action([string]$Action,[string]$InputName,[string]$OutputName) {
    $taskArguments=@('--startup-file=no','--project=.','scripts/paper_a/ap3.jl',$Action,(Join-Path $taskRunRoot $InputName),(Join-Path $taskRunRoot $OutputName))
    $taskLog=Join-Path $taskRunRoot ($OutputName+'.log')
    $taskCommands.Add(@{action=$Action;arguments=$taskArguments;log=$taskLog})
    $taskCommands | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $taskRunRoot 'postprocessing_commands.json')
    & $Julia @taskArguments *> $taskLog
    if($LASTEXITCODE -ne 0){throw "AP3 action failed: $Action; see $taskLog"}
}
Invoke-AP3Action reconstruct_strength_matrices accepted_suite matrices_final
Invoke-AP3Action reconstruct_strength_matrices accepted_suite matrices_replay
Invoke-AP3Action evaluate_strength_metrics matrices_final metrics_final
Invoke-AP3Action verify_certificates matrices_final certificates_final
Invoke-AP3Action compare_formulations accepted_suite comparisons_final
Invoke-AP3Action assess_planning_results accepted_suite planning_final
