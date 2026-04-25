# Documentation for FlexPlan UC/gSCR Block-Expansion

This repository extends FlexPlan.jl with block-based generator/storage expansion and full-network gSCR/ESCR security constraints.

The Documenter.jl-built reference documentation is located in `docs/src/` and is published via `docs/make.jl`.

UC/gSCR-specific design documents live in:

```text
docs/block_expansion/         — mathematical block-expansion formulation
docs/uc_gscr_block/           — data mapping, architecture, gSCR LMI and Gershgorin docs
docs/project_start/           — onboarding and start-here guides
docs/review_workflow/         — documentation and review quality requirements
docs/tests/                   — test plan and specification
```

## Preview the documentation (for developers)

While developing you can preview the documentation locally in your browser
with live-reload capability, i.e. when modifying a file, every browser (tab) currently
displaying the corresponding page is automatically refreshed.

### Instructions for *nix

1. Copy the following zsh/Julia code snippet:

   ```julia
   #!/bin/zsh
   #= # Following line is zsh code
   julia -i $0:a # The string `$0:a` represents this file in zsh
   =# # Following lines are Julia code
   import Pkg
   Pkg.activate(; temp=true)
   Pkg.develop("FlexPlan")
   Pkg.add("Documenter")
   Pkg.add("LiveServer")
   using FlexPlan, LiveServer
   cd(pkgdir(FlexPlan))
   servedocs()
   exit()
   ```

2. Save it as a zsh script (name it like `preview_flexplan_docs.sh`).
3. Assign execute permission to the script: `chmod u+x preview_flexplan_docs.sh`.
4. Run the script.
5. Open your favorite web browser and navigate to `http://localhost:8000`.
