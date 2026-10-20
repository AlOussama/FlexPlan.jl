param([string]$RunRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$taskRoot=(Resolve-Path -LiteralPath $RunRoot).Path
$verification=Join-Path $taskRoot 'metric_archive_verification.json'
if(Test-Path -LiteralPath $verification){throw 'Archive verification already exists'}
$rows=[System.Collections.Generic.List[object]]::new()
$files=Get-ChildItem -LiteralPath $taskRoot -Recurse -File | Where-Object {$_.Name -in @('metrics.json','metrics.csv')}
foreach($file in $files){
    $zipPath=Join-Path $file.DirectoryName ('metrics-'+$file.Extension.TrimStart('.')+'.zip')
    if(!(Test-Path -LiteralPath $zipPath)){Compress-Archive -LiteralPath $file.FullName -DestinationPath $zipPath -CompressionLevel Optimal}
    $rawHash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $archive=[System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entry=$archive.GetEntry($file.Name)
        if($null -eq $entry){throw "Missing archive entry: $zipPath"}
        $stream=$entry.Open();$hasher=[System.Security.Cryptography.SHA256]::Create()
        try {$entryHash=[Convert]::ToHexString($hasher.ComputeHash($stream)).ToLowerInvariant()}
        finally {$stream.Dispose();$hasher.Dispose()}
    } finally {$archive.Dispose()}
    if($rawHash -ne $entryHash){throw "Archive SHA mismatch: $zipPath"}
    $rows.Add(@{raw_path=[System.IO.Path]::GetRelativePath($taskRoot,$file.FullName);archive_path=[System.IO.Path]::GetRelativePath($taskRoot,$zipPath);raw_bytes=$file.Length;archive_bytes=(Get-Item -LiteralPath $zipPath).Length;raw_sha256=$rawHash;entry_sha256=$entryHash;archive_sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant();byte_identical=$true})
}
@{schema='paper_a_ap3/1.0';archives=$rows;raw_files_retained_locally=$true} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $verification -Encoding utf8
Write-Output "Verified $($rows.Count) lossless metric archives"
