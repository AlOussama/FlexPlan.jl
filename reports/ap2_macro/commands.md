# Executed AP2 commands and reproduction targets

Workspace: `D:\Projekte\Code\FlexPlan_UC_GSCR`. All final test commands used the absolute Julia 1.10.11 binary below and `--startup-file=no`; package versions are locked by `Manifest-v1.10.toml`.

```powershell
$JuliaAP2 = 'C:\Users\User\.julia\juliaup\julia-1.10.11+0.x64.w64.mingw32\bin\julia.exe'
git fetch origin
git -C D:\Projekte\Code\pypsatomatpowerx fetch origin
& $JuliaAP2 --project=. -e 'using Pkg; Pkg.instantiate(;allow_autoprecomp=false); Pkg.status(;mode=Pkg.PKGMODE_MANIFEST)'
& $JuliaAP2 --startup-file=no --project=. -e 'using Pkg; Pkg.add([PackageSpec(name="PowerModels",version="0.21.4"),PackageSpec(name="JSON",version="0.21.4")];preserve=Pkg.PRESERVE_ALL); Pkg.status()'
& $JuliaAP2 --startup-file=no --project=. test/paper_a_environment.jl
$env:PAPER_A_AP2_EVIDENCE = "$PWD\reports\ap2_macro\synthetic_results_amended_final.json"
& $JuliaAP2 --startup-file=no --project=. test/run_paper_a_ap2.jl
$env:PYPSA_FLEXPLAN_BLOCK_GSCR_ROOT = 'D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr'
& $JuliaAP2 --startup-file=no --project=. test/runtests.jl
$pinnedRoot = Join-Path (git rev-parse --absolute-git-dir) 'ap2-producer-32ff452\data'
& $JuliaAP2 --startup-file=no --project=. test/run_paper_a_ap1_acceptance.jl $pinnedRoot reports/ap2_macro/producer_solver_results_final.json
& $JuliaAP2 --startup-file=no --project=. test/paper_a_producer_gate.jl $pinnedRoot reports/ap2_macro/producer_gate_pinned.json
```

The producer pin was materialized with `git archive --format=zip --output=<FlexPlan .git>/ap2-producer-32ff452.zip 32ff4525dc576af52c16298cb35ebd98f02cf8b2 data/paper_a_ap1 data/paper_a_ap1_synthetic docs/paper_a/ap1_scientific_data_contract.md docs/paper_a/ap1_to_ap2_handoff.md reports/paper_a_ap1_status.yaml reports/paper_a_ap1_validation.md src/paper_a_ap1.jl src/block_gscr_converter.jl src/generate_flexplan_datasets.jl src/pypsa_import.jl src/PyPSA2Matpower.jl`, executed read-only in the producer repository, then expanded into FlexPlan's Git metadata directory. No dataset was retyped or committed into the consumer source tree. The acceptance target fails on missing files or manifest/case hash mismatch. For CI, provide an authorized checkout of the same producer SHA as PINNED_PRODUCER_DATA_ROOT.

Earlier exact command variants are retained by their log names: a failed `julia +1.10 --version` alias lookup was followed by locating the existing 1.10.11 executable; the isolated old depot import failed on missing packages; the first AP2 run used `--compiled-modules=no`. `lock_repair.log` records the failed preserve-all single-package downgrade; `lock_repair02.log` records the bounded two-package repair. All failed and superseded test logs remain present. The source commits were not rewritten.

Final executed code: `5b24ef8ad33d812ce87008558913a6abf82e57f4`. Results: 5987/5987 full suite, 153/153 grouped AP2, 51/51 pinned producer mathematical acceptance, all exit 0. The strict producer study gate is a separate BLOCKED observation and is never folded into a positive study approval.
