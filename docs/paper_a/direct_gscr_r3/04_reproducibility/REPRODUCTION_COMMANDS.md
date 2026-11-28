# R3 reproduction commands

Scientific source: `ebaffb57feb3a27f2d7d87b745930664f625f935`. Working directory: `D:/Projekte/Code/FlexPlan_UC_GSCR`.
Use the recorded Julia 1.11.5 executable, committed Manifest-v1.11.toml and original input paths from REFERENCE_PINS.json. New output must be a fresh writable E: directory; the reference launcher checks E: capacity/writability. The nine actual commands, environments, UTC times and exits are preserved in the individual *_frozen_BUILD_RECEIPT.json files.

```powershell
& ./scripts/paper_a/run_r3_native_references.ps1 -OutputRoot 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH'
```

This builds three G0/MOSEK and six G3/(Gurobi,MOSEK) weekly references. PAPER_A_AC_REFERENCE_ONLY=1 returns before optimize!. The launcher currently checks unstaged changes; the independent index/worktree supplement additionally verifies staged cleanliness for the actual delivered runs. Verify `git status --porcelain --untracked-files=no` is empty before reproduction.

For each G0 reference directory D, the independent persisted-task check is:

```powershell
& 'C:/ProgramData/anaconda3/python.exe' audit/r3_independent_native_verify.py D/native_psd_readback.json --expected D/expected_psd.json --task D/native.task.gz --output D/INDEPENDENT_COEFFICIENT_VERDICT.json
```

For each frozen reference, compare to the original same-formulation G3 ledger (LPAC, SOC-WR, QCRM respectively):

```powershell
& 'C:/ProgramData/anaconda3/python.exe' scripts/paper_a/compare_original_ledgers.py ORIGINAL_G3_DIRECTORY NEW_REFERENCE_DIRECTORY NEW_SOURCE_DELTA.json
```

Original LPAC G3 point, with expected bytes frozen BEFORE evaluation (fresh manifest/output paths):

```powershell
$study='E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01'
& 'C:/ProgramData/anaconda3/python.exe' -B scripts/paper_a/replay_direct_ac.py $study "$study/DIRECT_GSCR_PM0217_01/LPAC_G3" "$study/DIRECT_GSCR_PM0217_01/LPAC_G3_solve" --freeze-manifest 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH/LPAC_G3_inputs.json'
& 'C:/ProgramData/anaconda3/python.exe' -B scripts/paper_a/replay_direct_ac.py $study "$study/DIRECT_GSCR_PM0217_01/LPAC_G3" "$study/DIRECT_GSCR_PM0217_01/LPAC_G3_solve" --manifest 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH/LPAC_G3_inputs.json' --output 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH/LPAC_G3_original'
```

The manifest-generation command freezes expected bytes without evaluating. Replay refuses missing or changed expected data and Python -O. The final delivered point uses LPAC_G3_inputs_guarded.json and LPAC_G3_original_guarded. Historical F02 and exact lower certificates are reused without re-optimization or renewed mathematical review.

Runtime inventory command, using the E: depot/temp variables below:

```powershell
& 'C:/Users/User/.julia/juliaup/julia-1.11.5+0.x64.w64.mingw32/bin/julia.exe' --startup-file=no --project=. scripts/paper_a/r3_runtime_inventory.jl 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH/JULIA_RUNTIME.json'
```

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
