# Fast Result Recommendations

## Cost decomposition by scenario
Why it matters: Separates investment, operating, startup, and shutdown drivers.
Required input files: cost_summary.json, objective_summary.json
Estimated complexity: fast post-processing
Needed before paper submission: yes

## Online-zero-dispatch counts
Why it matters: Shows whether converters are committed for strength without energy.
Required input files: online_schedule.csv plus component dispatch if available
Estimated complexity: fast post-processing
Needed before paper submission: yes

## na_block utilization
Why it matters: Quantifies whether online block decisions are acting as a strength variable.
Required input files: online_schedule.csv
Estimated complexity: fast post-processing
Needed before paper submission: yes

## Dispatch utilization
Why it matters: Compares actual energy use with online capability.
Required input files: dispatch_by_carrier.csv; per-component dispatch would improve it
Estimated complexity: fast post-processing
Needed before paper submission: yes

## gSCR LHS/RHS ratios
Why it matters: Identifies truly binding local constraints using RHS/LHS.
Required input files: online_schedule.csv, gscr_constraint_summary.json
Estimated complexity: fast post-processing
Needed before paper submission: yes

## GFM cost-per-strength
Why it matters: Explains why GFM-BESS is attractive.
Required input files: case.json
Estimated complexity: fast post-processing
Needed before paper submission: yes

## BASE post-hoc violation diagnosis
Why it matters: Separates cheap feasibility from strength inadequacy.
Required input files: posthoc_strength_timeseries.csv, gscr summaries
Estimated complexity: fast post-processing
Needed before paper submission: yes

## Load vs capability time series
Why it matters: Shows adequacy is covered by existing and storage capability.
Required input files: case.json, online_schedule.csv
Estimated complexity: fast post-processing
Needed before paper submission: yes

## Storage depletion/end-effect summary
Why it matters: Checks whether relaxed terminal storage creates free energy.
Required input files: storage_summary.json
Estimated complexity: fast post-processing
Needed before paper submission: yes

## Per-island gSCR validation
Why it matters: Avoids misinterpreting disconnected-network zero modes.
Required input files: case.json branch graph, posthoc_strength_timeseries.csv
Estimated complexity: fast post-processing
Needed before paper submission: yes

## GFM premium sensitivity
Why it matters: Tests robustness of GFM-BESS dominance.
Required input files: case data plus new cost assumptions
Estimated complexity: requires new optimization
Needed before paper submission: yes before strong economic claims

