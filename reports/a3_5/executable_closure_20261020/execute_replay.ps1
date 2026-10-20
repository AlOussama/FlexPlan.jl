$ErrorActionPreference='Stop'
$base='D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE'
$run='D:/Projekte/Code/FlexPlan_A35_EXEC_RUN'
Set-Location $base
$records=[System.Collections.Generic.List[object]]::new()
function Invoke-JuliaAudit([string]$id,[string[]]$arguments) {
    $start=[DateTime]::UtcNow
    & julia +1.10.11 --startup-file=no --project=. @arguments *> "$run/$id.log"
    $ec=$LASTEXITCODE
    $records.Add([ordered]@{id=$id;command=@('julia','+1.10.11','--startup-file=no','--project=.')+$arguments;cwd=$base;exit_code=$ec;started_utc=$start.ToString('o');ended_utc=[DateTime]::UtcNow.ToString('o')})
    ConvertTo-Json -InputObject $records.ToArray() -Depth 10 | Set-Content "$run/execution.json" -Encoding utf8
    Write-Output "$id exit=$ec"
}
Invoke-JuliaAudit 'full_regression' @("$run/validation/test/runtests.jl")
Invoke-JuliaAudit 'saved_evidence' @('test/run_paper_a_ap3_evidence.jl',"$run/historical_evidence")
Invoke-JuliaAudit 'make_config' @('scripts/paper_a/make_suite_config.jl',"$run/producer_3b8","$run/suite_config.json")
Invoke-JuliaAudit 'cli_suite' @('scripts/paper_a/ap3.jl','run_formulation_suite',"$run/suite_config.json","$run/suite")
Invoke-JuliaAudit 'cli_matrices' @('scripts/paper_a/ap3.jl','reconstruct_strength_matrices',"$run/suite","$run/matrices")
Invoke-JuliaAudit 'cli_metrics' @('scripts/paper_a/ap3.jl','evaluate_strength_metrics',"$run/matrices","$run/metrics")
Invoke-JuliaAudit 'cli_certificates' @('scripts/paper_a/ap3.jl','verify_certificates',"$run/matrices","$run/certificates")
Invoke-JuliaAudit 'cli_comparisons' @('scripts/paper_a/ap3.jl','compare_formulations',"$run/suite","$run/comparisons")
Invoke-JuliaAudit 'cli_planning' @('scripts/paper_a/ap3.jl','assess_planning_results',"$run/suite","$run/planning")
Invoke-JuliaAudit 'cli_benchmarks' @('scripts/paper_a/ap3.jl','benchmark_conic_scaling',"$run/suite_config.json","$run/benchmarks")
Invoke-JuliaAudit 'ap1_acceptance' @('test/run_paper_a_ap1_acceptance.jl',"$run/producer_3b8/data","$run/ap1_acceptance.json")
Invoke-JuliaAudit 'parameter_acceptance' @('test/run_paper_a_parameter_acceptance.jl',"$run/producer_3b8","$run/parameter_acceptance.json")
Invoke-JuliaAudit 'network_audit' @('test/run_paper_a_parameter_network_audit.jl',"$run/producer_3b8","$run/network_audit.json")
