# PyPSA OPF Infeasibility Diagnostics

Dataset: `D:\Projekte\Code\pypsatomatpowerx\data\flexplan_block_gscr\base_s_5_3snap\case.json`

Base standard OPF status: `OPTIMAL`

## Snapshot Metrics

| nw | P load | Q load | gen pmin | gen pmax | storage charge | storage discharge | dcline import | dcline export | gens pmax>0 | storage | dcline | ref bus | vmin/vmax | rate min/max | min |x| | active balance necessary |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|---:|---|
| 1 | 9752.000003 | 0.000000 | 0.000000 | 11486.917011 | 1071.896064 | 1071.896064 | 0.000000 | 0.000000 | 17 | 5 | 0 | 1 | 0.9000 / 1.1000 | 1698.102612 / 5094.307835 | 0.00235040 | PASS |
| 2 | 10003.000008 | 0.000000 | 0.000000 | 10988.441521 | 1071.896064 | 1071.896064 | 0.000000 | 0.000000 | 17 | 5 | 0 | 1 | 0.9000 / 1.1000 | 1698.102612 / 5094.307835 | 0.00235040 | PASS |
| 3 | 11774.000013 | 0.000000 | 0.000000 | 11028.179651 | 1071.896064 | 1071.896064 | 0.000000 | 0.000000 | 21 | 5 | 0 | 1 | 0.9000 / 1.1000 | 1698.102612 / 5094.307835 | 0.00235040 | PASS |

## Structural Issues

### Snapshot 1
- active-power necessary interval: [-1071.896064, 12558.813075] vs load 9752.000003
- near-zero branch x: none
- zero/small branch rate: none
- generator pmin > pmax: none
- storage inconsistent bounds: none
- missing bus attachments: none

### Snapshot 2
- active-power necessary interval: [-1071.896064, 12060.337585] vs load 10003.000008
- near-zero branch x: none
- zero/small branch rate: none
- generator pmin > pmax: none
- storage inconsistent bounds: none
- missing bus attachments: none

### Snapshot 3
- active-power necessary interval: [-1071.896064, 12100.075715] vs load 11774.000013
- near-zero branch x: none
- zero/small branch rate: none
- generator pmin > pmax: none
- storage inconsistent bounds: none
- missing bus attachments: none

## Diagnostic Solve Variants

| variant | status | objective | note |
|---|---|---:|---|
| base solve_mn_opf_strg DCP | OPTIMAL | 0.000000 |  |
| branch limits relaxed | OPTIMAL | 0.000000 |  |
| voltage bounds widened | OPTIMAL | 0.000000 |  |
| q limits relaxed | OPTIMAL | 0.000000 |  |
| storage removed | INFEASIBLE | 0.000000 |  |
| storage disabled | INFEASIBLE | 0.000000 |  |
| dcline links removed | OPTIMAL | 0.000000 |  |
| DC OPF without storage table | INFEASIBLE | 0.000000 |  |
| storage energy clamped to rating | OPTIMAL | 0.000000 |  |

## Converter-Side Consistency Flags

- all PyPSA links in this dataset are non-DC carrier links or have non-AC endpoints; no PowerModels dcline is active
- 30 non-DC links ignored by standard OPF solver copy

## Likely Cause

- The strongest diagnostic is storage-state inconsistency: several snapshots contain storage `energy` above `energy_rating`, and the first-period state equation can require more discharge than the unit can provide while respecting `se <= energy_rating`.
- Branch limits, voltage bounds, q limits, and dcline removal are secondary unless their relaxed variants are the first to become feasible.

## Recommended Converter-Side Fix

- Ensure `storage.energy` is an initial state of charge within `[0, energy_rating]` on the PowerModels/FlexPlan base, or export an `energy_rating` that is at least the maximum initial state plus physically reachable first-period adjustment.
- Preserve only PyPSA links with `carrier == "DC"` as PowerModels `dcline`; non-electrical carrier links should not enter standard OPF.
