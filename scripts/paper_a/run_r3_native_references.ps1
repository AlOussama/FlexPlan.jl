param(
    [string]$OutputRoot = 'E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01',
    [string[]]$Methods = @('G0','G3'),
    [string[]]$Formulations = @('LPAC','SOC-WR','QCRM'),
    [string]$ReferenceSuffix = '_frozen'
)
$ErrorActionPreference='Stop'
if(-not ([IO.Path]::GetFullPath($OutputRoot).StartsWith('E:\',[StringComparison]::OrdinalIgnoreCase))) {throw 'Explicit E: output root required'}
foreach($part in @('00_intake','01_native_g0','02_native_g3','03_replay_integrity','04_reproducibility','05_scientific_results','06_qa','logs','tmp','julia_depot')) {
    New-Item -ItemType Directory -Path "$OutputRoot/$part" -Force | Out-Null
}
$drive=Get-PSDrive E
if($drive.Free -le 0) {throw 'No free E: capacity'}
[IO.File]::WriteAllText("$OutputRoot/00_intake/native_reference_write_probe.txt",'R3 explicit E: writer probe')
$archive='E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01'
$julia='C:/Users/User/.julia/juliaup/julia-1.11.5+0.x64.w64.mingw32/bin/julia.exe'
$python='C:/ProgramData/anaconda3/python.exe'
$env:JULIA_DEPOT_PATH="$OutputRoot/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/SCI_GOLD_AC_DIRECT_02_LOCAL_20261127_01/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_FIVE_WEEKS_RE50_20261115_01/depot;C:/Users/User/.julia"
$env:JULIA_PKG_PRECOMPILE_AUTO='0'
$env:TEMP="$OutputRoot/tmp"
$env:TMP=$env:TEMP
$env:PAPER_A_PROXY_CONSUMER_COMMIT=(git rev-parse HEAD)
$env:PAPER_A_WEEK_CONTRACT='E:/ResearchResults/FlexPlan_UC_GSCR/SGOV145_20261121_01/FORMULATION_CONTRACT.md'
$env:PAPER_A_STRENGTH_EXISTING_CASE_DIR="$archive/CASES/G2"
$env:PAPER_A_AC_CASE_DIR="$archive/CONFIRMED_QBOX/AC_CASE"
$env:PAPER_A_AC_REFERENCE_ONLY='1'
$env:PAPER_A_AC_EXPORT_NATIVE='0'
$env:PAPER_A_AC_REPLAY='0'
$env:PAPER_A_STRENGTH_BACKEND='mosek'
$env:PAPER_A_STRENGTH_SECONDS='120'
$science='E:/ResearchResults/FlexPlan_UC_GSCR/ORCH_FULL37_SEQUENTIAL_117_20261113_01/SCI02_POSITIVE_SYN_MINIMUM_04/CASE.json'
foreach($method in $Methods) {
    $section=if($method -eq 'G0'){'01_native_g0'}else{'02_native_g3'}
    $solvers=if($method -eq 'G0'){@('mosek')}else{@('gurobi','mosek')}
    foreach($form in $Formulations) {
        foreach($solver in $solvers) {
            $env:PAPER_A_AC_FORMULATION=$form
            $env:PAPER_A_AC_SOLVER=$solver
            $env:PAPER_A_AC_ATTEMPT="$section/${form}_${solver}$ReferenceSuffix"
            $dir="$OutputRoot/$($env:PAPER_A_AC_ATTEMPT)"
            if(Test-Path -LiteralPath "$dir/reference_export.json") {continue}
            if(Test-Path -LiteralPath $dir) {throw "Partial reference exists: $dir; preserve it and choose a fresh output root"}
            $before=(git rev-parse HEAD)
            if($before -ne $env:PAPER_A_PROXY_CONSUMER_COMMIT) {throw 'Source commit changed between reference builds'}
            $dirty=git diff --name-only
            if($dirty) {throw 'Tracked code must be clean before a frozen reference build'}
            $started=[DateTime]::UtcNow
            & $julia --startup-file=no --project=. scripts/paper_a/run_week_strength_comparison.jl $OutputRoot $science $method relaxed ac_compare *> "$OutputRoot/logs/${method}_${form}_${solver}$ReferenceSuffix.log"
            $exit=$LASTEXITCODE
            $after=(git rev-parse HEAD)
            $dirtyAfter=git diff --name-only
            $receipt=@{source_commit=$before;source_commit_after=$after;tracked_dirty_before=@($dirty);tracked_dirty_after=@($dirtyAfter);started_utc=$started.ToString('o');ended_utc=[DateTime]::UtcNow.ToString('o');exit_code=$exit;method=$method;formulation=$form;backend=$solver;optimization_performed=$false;command=@($julia,'--startup-file=no','--project=.','scripts/paper_a/run_week_strength_comparison.jl',$OutputRoot,$science,$method,'relaxed','ac_compare');environment=@{JULIA_DEPOT_PATH=$env:JULIA_DEPOT_PATH;TEMP=$env:TEMP;PAPER_A_AC_REFERENCE_ONLY='1';PAPER_A_AC_ATTEMPT=$env:PAPER_A_AC_ATTEMPT;PAPER_A_WEEK_CONTRACT=$env:PAPER_A_WEEK_CONTRACT;PAPER_A_STRENGTH_EXISTING_CASE_DIR=$env:PAPER_A_STRENGTH_EXISTING_CASE_DIR;PAPER_A_AC_CASE_DIR=$env:PAPER_A_AC_CASE_DIR}}
            $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$OutputRoot/04_reproducibility/${method}_${form}_${solver}${ReferenceSuffix}_BUILD_RECEIPT.json" -Encoding UTF8
            if($exit -ne 0) {throw "Native build failed: $method $form $solver; see log"}
            if($before -ne $after -or $dirtyAfter) {throw 'Source freeze changed during reference build'}
            if($method -eq 'G0') {
                & $python audit/r3_independent_native_verify.py "$dir/native_psd_readback.json" --expected "$dir/expected_psd.json" --task "$dir/native.task.gz" --output "$dir/INDEPENDENT_COEFFICIENT_VERDICT.json"
                if($LASTEXITCODE -ne 0) {throw "Independent native audit failed: $dir"}
            }
        }
    }
}
