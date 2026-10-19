param(
    [Parameter(Mandatory=$true)][string]$ProducerRoot,
    [string]$AcceptancePath = 'reports/strang_b/parametric_acceptance.json',
    [string]$OutputPath = 'reports/strang_b/normalized_residuals.json'
)
$ErrorActionPreference='Stop'
$acceptance=Get-Content -Raw -LiteralPath $AcceptancePath | ConvertFrom-Json -AsHashtable
$rows=@()
foreach($result in $acceptance.cases){
    $casePath=Join-Path $ProducerRoot ('data/paper_a_study/cases/{0}/study_{1}snap/case.json' -f $result.scenario_id,$result.snapshots)
    $inputCase=Get-Content -Raw -LiteralPath $casePath | ConvertFrom-Json -AsHashtable
    if((Get-FileHash -Algorithm SHA256 -LiteralPath $casePath).Hash.ToLowerInvariant() -ne $result.case_sha256){throw 'Case bytes changed'}
    $peakDemand=1.0
    foreach($snapshot in $inputCase.nw.Values){
        $demand=0.0
        foreach($load in $snapshot.load.Values){$demand += [Math]::Abs($load.pd)}
        $peakDemand=[Math]::Max($peakDemand,$demand)
    }
    $energyScale=1.0; $sourceScale=1.0; $countScale=1.0
    foreach($table in @('gen','storage','ne_storage')){
        if(-not $inputCase.nw.'1'.ContainsKey($table)){continue}
        foreach($device in $inputCase.nw.'1'[$table].Values){
            if(-not $device.ContainsKey('source_class')){continue}
            $installed=$result.installed_assets[$device.name].installed
            $countScale=[Math]::Max($countScale,$installed)
            if($table -ne 'gen'){$energyScale=[Math]::Max($energyScale,$installed*$device.e_block)}
            if($device.source_class -ne 'GFL'){$sourceScale += $device.mu_str*$device.b_block*$installed}
        }
    }
    $rows += [ordered]@{
        scenario_id=$result.scenario_id;relaxed=$result.relaxed;case_sha256=$result.case_sha256
        peak_demand_scale_MW=$peakDemand;largest_installed_storage_scale_MWh=$energyScale
        installed_source_nameplate_scale_pu=$sourceScale;max_installed_count_scale=$countScale
        power_residual_over_peak_demand=$result.power_balance_MW_residual/$peakDemand
        SOC_residual_over_largest_storage=$result.soc_MWh_residual/$energyScale
        cost_residual_over_objective=$result.cost_residual/[Math]::Max(1.0,[Math]::Abs($result.objective))
        G1_violation_over_installed_source_scale=$result.G1_violation/$sourceScale
        connection_violation_over_installed_count=$result.connection_violation/$countScale
        integrality_residual_over_installed_count=$result.integrality_residual/$countScale
    }
}
[ordered]@{definition='Characteristic-scale normalized diagnostics; not a new solver run or alternative tolerance';cases=$rows} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
