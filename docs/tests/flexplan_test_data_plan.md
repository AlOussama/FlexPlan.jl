# FlexPlan Test-Data Plan

This document defines which existing FlexPlan test datasets should be used, in which order, and how to extend them with `gfl/gfm` and block data.

## Principle

Use a ladder:

```text
Level 0: synthetic 2–3 bus data
Level 1: case2_d_strg
Level 2: case6, 4h, 1s, 1y, DCP
Level 3: ieee_33, 4h, 1s, 1y, BFARad
Level 4: cigre_mv_eu, 24h, candidate storage
Level 5: case67, 4h first, then larger
```

Do not start with large time-series datasets.

## Level 0 — synthetic 2–3 bus test case

Create a tiny local test case with:

- 2 or 3 buses;
- 2 lines;
- one GFL device;
- one GFM device;
- optionally one BESS;
- 2–3 time snapshots;
- hand-computable \(B^0\).

Use this for:

- sign convention checks;
- row-margin checks;
- type classification;
- block variable bounds;
- simple gSCR feasibility/infeasibility tests.

This test should not depend on the full FlexPlan example loaders.

## Level 1 — `case2_d_strg.m`

Use:

```text
test/data/case2/case2_d_strg.m
```

Purpose:

- storage block-field parsing;
- `ne_storage` block extension;
- storage energy capacity:
  \[
  e_{s,t}\le n_s e_s^{block};
  \]
- charge/discharge limits scaled by \(n_{a,s,t}\).

This is the first storage-specific dataset.

## Level 2 — `case6` for transmission/DCP/time-series tests

Use FlexPlan's `load_case6` with small dimensions:

```julia
data = load_case6(
    number_of_hours = 4,
    number_of_scenarios = 1,
    number_of_years = 1,
    scale_gen = 13,
    share_data = false,
    sn_data_extensions = [add_uc_gscr_block_fields!],
)
```

Use for:

- full-network transmission indexing;
- DCP/active-power formulation;
- time-dependent \(n_a(t)\);
- snapshot-shared \(n\);
- gSCR reference maps;
- Gershgorin LP constraint;
- regression against existing FlexPlan DCP pathway.

### Example extension function

```julia
function add_uc_gscr_block_fields!(data)
    for (id, gen) in data["gen"]
        is_gfm = id == "1"

        gen["type"] = is_gfm ? "gfm" : "gfl"
        gen["n0"] = 1
        gen["nmax"] = 3

        pblk = max(abs(gen["pmax"]), 1e-3)

        gen["p_block_min"] = 0.0
        gen["p_block_max"] = pblk

        gen["q_block_min"] = get(gen, "qmin", -pblk)
        gen["q_block_max"] = get(gen, "qmax",  pblk)

        gen["b_block"] = is_gfm ? 0.2 : 0.0
        gen["cost_inv_block"] = 1.0
        gen["H"] = is_gfm ? 5.0 : 0.0
        gen["s_block"] = pblk

        gen["pmin"] = 0.0
        gen["pmax"] = gen["nmax"] * gen["p_block_max"]

        if haskey(gen, "qmin")
            gen["qmin"] = gen["nmax"] * gen["q_block_min"]
            gen["qmax"] = gen["nmax"] * gen["q_block_max"]
        end
    end

    data["g_min"] = 2.0
end
```

## Level 3 — `ieee_33` for radial distribution/BFARad compatibility

Use:

```julia
data = load_ieee_33(
    number_of_hours = 4,
    number_of_scenarios = 1,
    number_of_years = 1,
    scale_load = 1.52,
    share_data = false,
)
```

Then patch the multinetwork data if the loader does not expose an extension hook.

Purpose:

- check architecture is not DCP-only;
- test BFARad instantiation;
- verify reactive hooks do not break active/radial formulation;
- verify full-network reference mapping works on distribution data.

## Level 4 — `cigre_mv_eu` for realistic storage/time-series tests

Use:

```julia
data = load_cigre_mv_eu(
    number_of_hours = 24,
    start_period = 1,
    ne_storage = true,
    flex_load = false,
    scale_load = 1.0,
    scale_gen = 1.0,
    share_data = false,
)
```

Purpose:

- candidate storage;
- storage energy dynamics;
- 24-hour time indexing;
- storage block investment;
- storage active blocks;
- realistic distribution time-series.

Do not use this for first debugging.

## Level 5 — `case67` for larger transmission regression

Use:

```julia
data = load_case67(
    number_of_hours = 4,
    number_of_scenarios = 1,
    number_of_years = 1,
    scale_load = 1.0,
    scale_gen = 1.0,
    share_data = false,
    sn_data_extensions = [add_uc_gscr_block_fields!],
)
```

Purpose:

- scalability;
- all-bus gSCR constraints;
- reference mapping performance;
- larger transmission regression.

Do not use until Level 0–3 pass.

## How to patch multinetwork data

If a loader does not expose `sn_data_extensions`, use:

```julia
function add_uc_gscr_fields_to_multinetwork!(data)
    for (nw_id, nw) in data["nw"]
        add_uc_gscr_block_fields!(nw)
    end
end
```

## Test sequence

1. Parser/reference tests:
   - synthetic;
   - case2;
   - case6 4h.

2. Variable/dispatch tests:
   - synthetic;
   - case6 4h;
   - case2 storage.

3. First gSCR LP test:
   - case6 4h, 1 scenario, 1 year.

4. Formulation compatibility:
   - ieee_33 4h.

5. Storage/time-series:
   - cigre_mv_eu 24h.

6. Scalability:
   - case67 4h, then larger.
