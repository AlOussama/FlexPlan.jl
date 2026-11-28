# Exact regression commands

Frozen source: `ebaffb57feb3a27f2d7d87b745930664f625f935`. Working directory: `D:/Projekte/Code/FlexPlan_UC_GSCR`.

The first two commands below are the exact final commands executed by the G3 worker. Other command provenance is explicitly recorded in REGRESSION_RESULTS.json.

## g3_focused

```powershell
Set-Location -LiteralPath 'D:/Projekte/Code/FlexPlan_UC_GSCR'
$env:JULIA_DEPOT_PATH='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/SCI_GOLD_AC_DIRECT_02_LOCAL_20261127_01/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_FIVE_WEEKS_RE50_20261115_01/depot;C:/Users/User/.julia'
$env:TEMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
$env:TMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
$env:R3_G3_TEST_OUTPUT='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/02_native_g3/small'
& 'C:/Users/User/.julia/juliaup/julia-1.11.5+0.x64.w64.mingw32/bin/julia.exe' --project=. --startup-file=no -e 'include("test/paper_a_g3_finite_exact.jl"); include("test/paper_a_week_mosek_conditioning.jl"); include("test/paper_a_added_gfl_native_g3.jl"); include("test/paper_a_added_gfl_mosek.jl"); include("test/paper_a_mosek_zeroone_bounds.jl")' *> 'E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/logs/g3_finite_tests_final.log'
```

Exact final command executed by G3 implementation worker.

## dcp_ap3

```powershell
Set-Location -LiteralPath 'D:/Projekte/Code/FlexPlan_UC_GSCR'
$env:JULIA_DEPOT_PATH='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/SCI_GOLD_AC_DIRECT_02_LOCAL_20261127_01/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_FIVE_WEEKS_RE50_20261115_01/depot;C:/Users/User/.julia'
$env:TEMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
$env:TMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
& 'C:/Users/User/.julia/juliaup/julia-1.11.5+0.x64.w64.mingw32/bin/julia.exe' --project=. --startup-file=no -e 'using Test,JuMP; import FlexPlan as _FP, PowerModels as _PM, HiGHS; using FlexPlan.PaperARegional; include("test/uc_gscr_block_test_utils.jl"); include("test/paper_a_fixtures.jl"); include("test/paper_a_ap3.jl"); include("test/paper_a_additional_gfl.jl")' *> 'E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/logs/g3_dcp_ap3_regression_final.log'
```

Exact final command executed by G3 implementation worker.

## ac_network

```powershell
Set-Location -LiteralPath 'D:/Projekte/Code/FlexPlan_UC_GSCR'
$env:JULIA_DEPOT_PATH='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/SCI_GOLD_AC_DIRECT_02_LOCAL_20261127_01/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_FIVE_WEEKS_RE50_20261115_01/depot;C:/Users/User/.julia'
$env:TEMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
$env:TMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
& 'C:/Users/User/.julia/juliaup/julia-1.11.5+0.x64.w64.mingw32/bin/julia.exe' --project=. --startup-file=no test/paper_a_ac_network.jl *> 'E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/logs/ac_network_regression.log'
```

Direct-file reproduction command; parent executed test and supplied log; exact parent shell command not embedded in log.

## original_audit

```powershell
Set-Location -LiteralPath 'D:/Projekte/Code/FlexPlan_UC_GSCR'
$env:JULIA_DEPOT_PATH='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/SCI_GOLD_AC_DIRECT_02_LOCAL_20261127_01/julia_depot;E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_FIVE_WEEKS_RE50_20261115_01/depot;C:/Users/User/.julia'
$env:TEMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
$env:TMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
& 'C:/Users/User/.julia/juliaup/julia-1.11.5+0.x64.w64.mingw32/bin/julia.exe' --project=. --startup-file=no test/paper_a_original_audit.jl
```

03_replay_integrity/focused_validation.json records julia1.11.5 --project=. --startup-file=no test/paper_a_original_audit.jl.

## python_replay

```powershell
Set-Location -LiteralPath 'D:/Projekte/Code/FlexPlan_UC_GSCR'
$env:TEMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
$env:TMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
C:/ProgramData/anaconda3/python.exe -B -m unittest discover -s test -p test_replay_evidence.py -v
```

03_replay_integrity/focused_validation.json.

## native_psd_mutations

```powershell
Set-Location -LiteralPath 'D:/Projekte/Code/FlexPlan_UC_GSCR'
$env:TEMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
$env:TMP='E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01/tmp'
C:/ProgramData/anaconda3/python.exe -B audit/test_r3_independent_native_verify.py
```

Reproduction command inferred from executable QA script; frozen output receipt independently records 1 exact positive and 10 material negatives.

Final counts: 152 focused G3 + 360 DCP/AP3/added-GFL + 101 AC-network + 12 original-audit = 625 Julia assertions; 3 Python replay test groups; independent native PSD verifier 1 exact positive and 10 material negative controls.
No JULIA_PKG_PRECOMPILE_AUTO override was set in the two final G3-worker launches. TEMP/TMP point to the existing R3 output directory on E:.
