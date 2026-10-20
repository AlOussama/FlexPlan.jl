param([string]$RunRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$taskRoot=(Resolve-Path -LiteralPath $RunRoot).Path
$repo=(Resolve-Path (Join-Path $taskRoot '../../..')).Path
$ci=[System.Globalization.CultureInfo]::InvariantCulture
$comparisons=(Get-Content -LiteralPath (Join-Path $taskRoot 'comparisons_final/comparisons.json') -Raw | ConvertFrom-Json).records
$bounds=(Get-Content -LiteralPath (Join-Path $taskRoot 'integer_bound_audit.json') -Raw | ConvertFrom-Json).records
$lines=[System.Collections.Generic.List[string]]::new()
$lines.Add('# Tatsächlicher parametrischer Formulierungsvergleich')
$lines.Add('')
$lines.Add('Kontinuierliche Modelle; Kosten in deklarierter Währung des repräsentierten Horizonts. Prozentdifferenzen beziehen sich auf abs(G0). Integer-Gap aus separatem Originalwährungs-Referenzintervall. Keine empirische Studienfreigabe.')
$lines.Add('')
$lines.Add('| Szenario | G0 Kosten | G1 Aufschlag % | G3 Delta % | M2 voll % | M2 Nachbar % | Integer-Referenzgap |')
$lines.Add('|---|---:|---:|---:|---:|---:|---:|')
foreach($id in ($comparisons.case_id | Sort-Object -Unique)){
    $rows=@($comparisons | Where-Object {$_.case_id -eq $id -and $_.relaxed})
    $vals=@{}
    foreach($fid in @('G0','G1','G3','M2_full','M2_neighbor')){
        $row=$rows | Where-Object {$_.formulation -eq $fid}
        $value=if($fid -eq 'G0'){$row.objective}else{100*$row.relative_delta}
        $vals[$fid]=([double]$value).ToString('G10',$ci)
    }
    $gap=($bounds | Where-Object {$_.case_id -eq $id}).original_currency_relative_gap
    $lines.Add("| $id | $($vals['G0']) | $($vals['G1']) | $($vals['G3']) | $($vals['M2_full']) | $($vals['M2_neighbor']) | $(([double]$gap).ToString('G5',$ci)) |")
}
$lines | Set-Content -LiteralPath (Join-Path $taskRoot 'parametric_comparison.md') -Encoding utf8
$registry=Get-Content -LiteralPath (Join-Path $taskRoot 'metrics_final/metric_registry.json') -Raw | ConvertFrom-Json
$doc=Join-Path $repo 'docs/paper_a/ap3_evaluation_metric_registry.md'
if((Get-Content -LiteralPath $doc -Raw).Contains('## Exact exported ID inventory')){throw 'Inventory already appended'}
$append=[System.Collections.Generic.List[string]]::new()
$append.Add('');$append.Add('## Exact exported ID inventory');$append.Add('')
$append.Add('The following table is generated from the final machine registry. Base is the per-record system MVA; domain status and source/theorem fields remain attached to every JSON/CSV record. A formula may compute a failed screen or an explicitly noncertifying diagnostic; a non-null value does not imply scientific acceptance.');$append.Add('')
$append.Add('| Metric ID | Formula / executable quantity | Unit | Scope |');$append.Add('|---|---|---|---|')
foreach($prop in ($registry.PSObject.Properties | Sort-Object Name)){
    $r=$prop.Value;$formula=$r.formula.Replace('|','&#124;')
    $append.Add("| $($prop.Name) | $formula | $($r.unit) | $($r.scope) |")
}
$append | Add-Content -LiteralPath $doc -Encoding utf8
