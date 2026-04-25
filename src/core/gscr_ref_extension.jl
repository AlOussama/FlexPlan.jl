# Reference extension for block UC/gSCR constraints
#
# Implements Task 01 of the block expansion / UC-gSCR design.
#
# Adds the following keys to each nw_ref:
#   :gfl_devices          – Dict{Int,Dict} of gen entries with type == "gfl"
#   :gfm_devices          – Dict{Int,Dict} of gen entries with type == "gfm"
#   :bus_gfl_devices      – Dict{Int,Vector{Int}} bus → list of gfl device ids
#   :bus_gfm_devices      – Dict{Int,Vector{Int}} bus → list of gfm device ids
#   :gscr_sigma0_gershgorin_margin – Dict{Int,Float64} bus → σ_n^{0,G}
#   :gscr_sigma0_raw_rowsum        – Dict{Int,Float64} bus → Σ_j B^0_{nj}

"""
    _build_susceptance_matrix(nw_ref) -> Dict{Tuple{Int,Int},Float64}

Build the full-network real susceptance matrix B^0 from branch data.

Each branch ℓ = (f, t) with reactance x contributes:
- B^0_{ff} += 1/x
- B^0_{tt} += 1/x
- B^0_{ft} -= 1/x
- B^0_{tf} -= 1/x

Only branches with `br_status == 1` are included.

Returns a sparse representation as a `Dict{Tuple{Int,Int},Float64}` keyed by
(i, j) bus-index pairs (including diagonal entries).
"""
function _build_susceptance_matrix(nw_ref::Dict{Symbol,<:Any})
    B = Dict{Tuple{Int,Int},Float64}()

    # initialise diagonal for every bus
    for i in keys(nw_ref[:bus])
        B[(i, i)] = 0.0
    end

    for (_, branch) in nw_ref[:branch]
        branch["br_status"] == 1 || continue

        f = branch["f_bus"]
        t = branch["t_bus"]
        x = branch["br_x"]

        # skip degenerate branches
        abs(x) < 1e-12 && continue

        b = 1.0 / x   # per-unit susceptance magnitude

        B[(f, f)] = get(B, (f, f), 0.0) + b
        B[(t, t)] = get(B, (t, t), 0.0) + b
        B[(f, t)] = get(B, (f, t), 0.0) - b
        B[(t, f)] = get(B, (t, f), 0.0) - b
    end

    return B
end

"""
    _compute_gershgorin_margins(B, bus_ids) -> (margin, rowsum)

Compute the Gershgorin diagonal dominance margin for each bus n:

    σ_n^{0,G} = B^0_{nn} - Σ_{j ≠ n} |B^0_{nj}|

Also compute the raw row sum (for diagnostics):

    rowsum_n = Σ_j B^0_{nj}

Returns two `Dict{Int,Float64}` indexed by bus id.
"""
function _compute_gershgorin_margins(B::Dict{Tuple{Int,Int},Float64},
                                     bus_ids)
    margin  = Dict{Int,Float64}(n => 0.0 for n in bus_ids)
    rowsum  = Dict{Int,Float64}(n => 0.0 for n in bus_ids)

    for ((i, j), val) in B
        i in bus_ids || continue
        rowsum[i] += val
        if i != j
            margin[i] -= abs(val)  # subtract |B^0_{ij}| for off-diagonal
        else
            margin[i] += val       # add B^0_{ii} for diagonal
        end
    end

    return margin, rowsum
end

"""
    ref_add_gscr_block!(ref, data)

Reference extension that populates block UC/gSCR quantities for every
multinetwork snapshot.

Added keys per `nw_ref`:
- `:gfl_devices`  – gen entries whose `"type"` field equals `"gfl"`.
- `:gfm_devices`  – gen entries whose `"type"` field equals `"gfm"`.
- `:bus_gfl_devices` – mapping from bus id to list of gfl device ids at that bus.
- `:bus_gfm_devices` – mapping from bus id to list of gfm device ids at that bus.
- `:gscr_sigma0_gershgorin_margin` – σ_n^{0,G} per bus (see equation in
  `docs/uc_gscr_block/gscr_global_lmi_and_gershgorin.md` §6).
- `:gscr_sigma0_raw_rowsum` – raw row sum of B^0 per bus (diagnostic).

Cases without block fields are supported: if no gen entry carries a `"type"`
field the above dictionaries are populated with empty / zero values so that
the rest of the FlexPlan pipeline is unaffected.
"""
function ref_add_gscr_block!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    for (_, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        bus_ids = keys(nw_ref[:bus])

        # ── device type maps ──────────────────────────────────────────────
        gfl = Dict{Int,Any}()
        gfm = Dict{Int,Any}()

        for (k, gen) in nw_ref[:gen]
            t = get(gen, "type", nothing)
            if t == "gfl"
                gfl[k] = gen
            elseif t == "gfm"
                gfm[k] = gen
            end
        end

        nw_ref[:gfl_devices] = gfl
        nw_ref[:gfm_devices] = gfm

        # ── bus → device maps ─────────────────────────────────────────────
        bus_gfl = Dict{Int,Vector{Int}}(n => Int[] for n in bus_ids)
        bus_gfm = Dict{Int,Vector{Int}}(n => Int[] for n in bus_ids)

        for (k, gen) in gfl
            push!(bus_gfl[gen["gen_bus"]], k)
        end
        for (k, gen) in gfm
            push!(bus_gfm[gen["gen_bus"]], k)
        end

        nw_ref[:bus_gfl_devices] = bus_gfl
        nw_ref[:bus_gfm_devices] = bus_gfm

        # ── susceptance matrix and Gershgorin metrics ─────────────────────
        B = _build_susceptance_matrix(nw_ref)
        margin, rowsum = _compute_gershgorin_margins(B, bus_ids)

        nw_ref[:gscr_sigma0_gershgorin_margin] = margin
        nw_ref[:gscr_sigma0_raw_rowsum]        = rowsum
    end
end
