## Generators

"Add to `ref` the keys for handling dispatchable and non-dispatchable generators"
function ref_add_gen!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})

    for (n, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        # Dispatchable generators. Their power varies between `pmin` and `pmax` and cannot be curtailed.
        nw_ref[:dgen] = Dict(x for x in nw_ref[:gen] if x.second["dispatchable"] == true)
        # Non-dispatchable generators. Their reference power `pref` can be curtailed.
        nw_ref[:ndgen] = Dict(x for x in nw_ref[:gen] if x.second["dispatchable"] == false)
    end
end


## Storage

function ref_add_storage!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})

    for (n, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        if haskey(nw_ref, :storage)
            nw_ref[:storage_bounded_absorption] = Dict(x for x in nw_ref[:storage] if 0.0 < get(x.second, "max_energy_absorption", Inf) < Inf)
        end
    end
end

function ref_add_ne_storage!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    for (n, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        if haskey(nw_ref, :ne_storage)
            bus_storage_ne = Dict([(i, []) for (i,bus) in nw_ref[:bus]])
            for (i,storage) in nw_ref[:ne_storage]
                push!(bus_storage_ne[storage["storage_bus"]], i)
            end
            nw_ref[:bus_storage_ne] = bus_storage_ne
            nw_ref[:ne_storage_bounded_absorption] = Dict(x for x in nw_ref[:ne_storage] if 0.0 < get(x.second, "max_energy_absorption", Inf) < Inf)
        end
    end
end

## UC/gSCR block reference extension

const _UC_GSCR_BLOCK_REQUIRED_FIELDS = [
    "type",
    "n0",
    "nmax",
    "p_block_min",
    "p_block_max",
    "q_block_min",
    "q_block_max",
    "b_block",
]

const _UC_GSCR_BLOCK_OPTIONAL_FIELDS = ["H", "s_block", "e_block"]

"""
    ref_add_uc_gscr_block!(ref, data)

Adds UC/gSCR block reference maps and baseline full-network row metrics to
each PowerModels network reference.

Mathematically, this stores GFL/GFM device sets, bus-device incidence maps,
the full-network baseline susceptance matrix `B^0`, the Gershgorin margin
`B^0[n,n] - sum(abs(B^0[n,j]) for j != n)`, and the raw row sum diagnostic.
The function reads block fields from `gen`, `storage`, and `ne_storage`.
If no block fields are present in a network, it leaves that network unchanged.

Arguments are the PowerModels `ref` dictionary and original network `data`.
Block strengths are assumed to be in a per-unit base consistent with device
power fields. This function is formulation-independent and mutates only `ref`.
"""
function ref_add_uc_gscr_block!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    for (nw, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        if !_has_uc_gscr_block_data(nw_ref)
            continue
        end

        _validate_uc_gscr_block_devices(nw_ref)
        _add_uc_gscr_device_maps!(nw_ref)
        _add_uc_gscr_row_metrics!(nw_ref)
    end
end

"""
    _has_uc_gscr_block_data(nw_ref)

Returns whether any supported device table in `nw_ref` contains a UC/gSCR
block field.

This is a schema-detection helper for the formulation-independent reference
extension. It mutates no data and exists to preserve backward compatibility:
networks without block fields are skipped.
"""
function _has_uc_gscr_block_data(nw_ref::Dict{Symbol,<:Any})
    for table_name in (:gen, :storage, :ne_storage)
        if !haskey(nw_ref, table_name)
            continue
        end
        for (device_id, device) in nw_ref[table_name]
            if any(haskey(device, field) for field in [_UC_GSCR_BLOCK_REQUIRED_FIELDS; _UC_GSCR_BLOCK_OPTIONAL_FIELDS])
                return true
            end
        end
    end
    return false
end

"""
    _validate_uc_gscr_block_devices(nw_ref)

Validates required UC/gSCR block fields on every block-annotated supported
device in `nw_ref`.

The required mathematical fields are `type`, `n0`, `nmax`, per-active-block
P/Q bounds, and `b_block`, with `type` restricted to `"gfl"` or `"gfm"`.
No defaults are inferred for these mathematical fields. Optional fields
`H`, `s_block`, and `e_block` are only read when present. This function is
formulation-independent and mutates no data.
"""
function _validate_uc_gscr_block_devices(nw_ref::Dict{Symbol,<:Any})
    for (table_name, device_id, device) in _uc_gscr_block_devices(nw_ref)
        for field in _UC_GSCR_BLOCK_REQUIRED_FIELDS
            if !haskey(device, field)
                Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) is missing required UC/gSCR block field `$(field)`.")
            end
        end

        device_type = device["type"]
        if !(device_type in ("gfl", "gfm"))
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid UC/gSCR block field `type=$(device_type)`. Expected `gfl` or `gfm`.")
        end

        n0 = device["n0"]
        nmax = device["nmax"]
        if n0 < 0 || nmax < n0
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid UC/gSCR block bounds: require 0 <= n0 <= nmax.")
        end
    end
end

"""
    _uc_gscr_block_devices(nw_ref)

Collects supported devices that carry at least one UC/gSCR block field.

The returned tuples are `(table_name, device_id, device)` for `gen`,
`storage`, and `ne_storage`. This helper is formulation-independent and
does not mutate data.
"""
function _uc_gscr_block_devices(nw_ref::Dict{Symbol,<:Any})
    devices = Tuple{Symbol,Any,Any}[]
    for table_name in (:gen, :storage, :ne_storage)
        if !haskey(nw_ref, table_name)
            continue
        end
        for (device_id, device) in nw_ref[table_name]
            if any(haskey(device, field) for field in [_UC_GSCR_BLOCK_REQUIRED_FIELDS; _UC_GSCR_BLOCK_OPTIONAL_FIELDS])
                push!(devices, (table_name, device_id, device))
            end
        end
    end
    return devices
end

"""
    _add_uc_gscr_device_maps!(nw_ref)

Builds UC/gSCR GFL/GFM device maps and bus-device incidence maps.

Device keys are `(table_name, device_id)` tuples so generator, storage, and
candidate-storage identifiers cannot collide. `bus_gfl_devices` and
`bus_gfm_devices` contain all original buses, including buses with no block
devices. The function is formulation-independent and mutates `nw_ref`.
"""
function _add_uc_gscr_device_maps!(nw_ref::Dict{Symbol,<:Any})
    gfl_devices = Dict{Tuple{Symbol,Any},Any}()
    gfm_devices = Dict{Tuple{Symbol,Any},Any}()
    bus_gfl_devices = Dict((bus_id, Tuple{Symbol,Any}[]) for (bus_id, bus) in nw_ref[:bus])
    bus_gfm_devices = Dict((bus_id, Tuple{Symbol,Any}[]) for (bus_id, bus) in nw_ref[:bus])

    for (table_name, device_id, device) in _uc_gscr_block_devices(nw_ref)
        bus_id = _uc_gscr_device_bus(table_name, device)
        if !haskey(nw_ref[:bus], bus_id)
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) references bus $(bus_id), which is not present in the full network bus set.")
        end

        device_key = (table_name, device_id)
        if device["type"] == "gfl"
            gfl_devices[device_key] = device
            push!(bus_gfl_devices[bus_id], device_key)
        else
            gfm_devices[device_key] = device
            push!(bus_gfm_devices[bus_id], device_key)
        end
    end

    nw_ref[:gfl_devices] = gfl_devices
    nw_ref[:gfm_devices] = gfm_devices
    nw_ref[:bus_gfl_devices] = bus_gfl_devices
    nw_ref[:bus_gfm_devices] = bus_gfm_devices
end

"""
    _uc_gscr_device_bus(table_name, device)

Returns the full-network bus id associated with a UC/gSCR block device.

Generators use `gen_bus`; storage and candidate storage use `storage_bus`.
This helper is formulation-independent, assumes PowerModels data field names,
and mutates no data.
"""
function _uc_gscr_device_bus(table_name::Symbol, device::Dict{String,<:Any})
    if table_name == :gen
        return device["gen_bus"]
    elseif table_name == :storage || table_name == :ne_storage
        return device["storage_bus"]
    else
        Memento.error(_LOGGER, "Unsupported UC/gSCR block device table `$(table_name)`.")
    end
end

"""
    _add_uc_gscr_row_metrics!(nw_ref)

Computes and stores the baseline full-network susceptance row metrics.

The matrix `B^0` is built on the original bus set from active branches using
`1 / br_x`, with diagonal entries increased and off-diagonal entries
decreased for each in-service branch. The Gershgorin margin is
`B^0[n,n] - sum(abs(B^0[n,j]) for j != n)`, and the raw row sum is
`sum(B^0[n,j] for j)`. This function is formulation-independent and mutates
`nw_ref`.
"""
function _add_uc_gscr_row_metrics!(nw_ref::Dict{Symbol,<:Any})
    b0 = _calc_uc_gscr_susceptance_matrix(nw_ref)
    bus_ids = collect(keys(nw_ref[:bus]))

    margin = Dict{Any,Float64}()
    raw_rowsum = Dict{Any,Float64}()
    for bus_id in bus_ids
        diag_value = b0[(bus_id, bus_id)]
        offdiag_abs = sum(abs(b0[(bus_id, other_bus_id)]) for other_bus_id in bus_ids if other_bus_id != bus_id)
        margin[bus_id] = diag_value - offdiag_abs
        raw_rowsum[bus_id] = sum(b0[(bus_id, other_bus_id)] for other_bus_id in bus_ids)
    end

    nw_ref[:gscr_b0] = b0
    nw_ref[:gscr_sigma0_gershgorin_margin] = margin
    nw_ref[:gscr_sigma0_raw_rowsum] = raw_rowsum
end

"""
    _calc_uc_gscr_susceptance_matrix(nw_ref)

Builds the full-network baseline susceptance matrix `B^0` from branch data.

Only active branches with endpoints present in the full bus set are used.
Each branch contributes `1 / br_x` to both endpoint diagonal entries and
`-1 / br_x` to the symmetric off-diagonal entries. Branch reactance is
assumed to be nonzero and in the same per-unit base as the gSCR data. This
helper is formulation-independent and mutates no data.
"""
function _calc_uc_gscr_susceptance_matrix(nw_ref::Dict{Symbol,<:Any})
    bus_ids = collect(keys(nw_ref[:bus]))
    b0 = Dict((i, j) => 0.0 for i in bus_ids for j in bus_ids)

    if !haskey(nw_ref, :branch)
        return b0
    end

    for (branch_id, branch) in nw_ref[:branch]
        if get(branch, "br_status", 1) != 1
            continue
        end

        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        if !(haskey(nw_ref[:bus], f_bus) && haskey(nw_ref[:bus], t_bus))
            continue
        end

        br_x = branch["br_x"]
        if br_x == 0
            Memento.error(_LOGGER, "Branch $(branch_id) has `br_x=0`, so the UC/gSCR baseline susceptance contribution `1 / br_x` is undefined.")
        end

        b = 1.0 / br_x
        b0[(f_bus, f_bus)] += b
        b0[(t_bus, t_bus)] += b
        b0[(f_bus, t_bus)] -= b
        b0[(t_bus, f_bus)] -= b
    end

    return b0
end


## Flexible loads

"Add to `ref` the keys for handling flexible demand"
function ref_add_flex_load!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})

    for (n, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        # Loads that can be made flexible, depending on investment decision
        nw_ref[:flex_load] = Dict(x for x in nw_ref[:load] if x.second["flex"] == 1)
        # Loads that are not flexible and do not have an associated investment decision
        nw_ref[:fixed_load] = Dict(x for x in nw_ref[:load] if x.second["flex"] == 0)
    end

    # Compute the total energy demand of each flex load and store it in the first hour nw
    for nw in nw_ids(data; hour = 1)
        if haskey(ref[:it][_PM.pm_it_sym][:nw][nw], :time_elapsed)
            time_elapsed = ref[:it][_PM.pm_it_sym][:nw][nw][:time_elapsed]
        else
            Memento.warn(_LOGGER, "network data should specify time_elapsed, using 1.0 as a default")
            time_elapsed = 1.0
        end
        timeseries_nw_ids = similar_ids(data, nw, hour = 1:dim_length(data,:hour))
        for (l, load) in ref[:it][_PM.pm_it_sym][:nw][nw][:flex_load]
            # `ref` instead of `data` must be used to access loads, since the former has
            # already been filtered to remove inactive loads.
            load["ed"] = time_elapsed * sum(ref[:it][_PM.pm_it_sym][:nw][n][:load][l]["pd"] for n in timeseries_nw_ids)
        end
    end
end


## Distribution networks

"Like ref_add_ne_branch!, but ne_buspairs are built using _calc_buspair_parameters_allbranches"
function ref_add_ne_branch_allbranches!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    for (nw, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        if !haskey(nw_ref, :ne_branch)
            Memento.error(_LOGGER, "required ne_branch data not found")
        end

        nw_ref[:ne_branch] = Dict(x for x in nw_ref[:ne_branch] if (x.second["br_status"] == 1 && x.second["f_bus"] in keys(nw_ref[:bus]) && x.second["t_bus"] in keys(nw_ref[:bus])))

        nw_ref[:ne_arcs_from] = [(i,branch["f_bus"],branch["t_bus"]) for (i,branch) in nw_ref[:ne_branch]]
        nw_ref[:ne_arcs_to]   = [(i,branch["t_bus"],branch["f_bus"]) for (i,branch) in nw_ref[:ne_branch]]
        nw_ref[:ne_arcs] = [nw_ref[:ne_arcs_from]; nw_ref[:ne_arcs_to]]

        ne_bus_arcs = Dict((i, []) for (i,bus) in nw_ref[:bus])
        for (l,i,j) in nw_ref[:ne_arcs]
            push!(ne_bus_arcs[i], (l,i,j))
        end
        nw_ref[:ne_bus_arcs] = ne_bus_arcs

        if !haskey(nw_ref, :ne_buspairs)
            ismc = haskey(nw_ref, :conductors)
            cid = nw_ref[:conductor_ids]
            nw_ref[:ne_buspairs] = _calc_buspair_parameters_allbranches(nw_ref[:bus], nw_ref[:ne_branch], cid, ismc)
        end
    end
end

"""
Add to `ref` the following keys:
- `:frb_branch`: the set of `branch`es whose `f_bus` is the reference bus;
- `:frb_ne_branch`: the set of `ne_branch`es whose `f_bus` is the reference bus.
"""
function ref_add_frb_branch!(ref::Dict{Symbol,Any}, data::Dict{String,<:Any})
    for (nw, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        ref_bus_id = first(keys(nw_ref[:ref_buses]))

        frb_branch = Dict{Int,Any}()
        for (i,br) in nw_ref[:branch]
            if br["f_bus"] == ref_bus_id
                frb_branch[i] = br
            end
        end
        nw_ref[:frb_branch] = frb_branch

        if haskey(nw_ref, :ne_branch)
            frb_ne_branch = Dict{Int,Any}()
            for (i,br) in nw_ref[:ne_branch]
                if br["f_bus"] == ref_bus_id
                    frb_ne_branch[i] = br
                end
            end
            nw_ref[:frb_ne_branch] = frb_ne_branch
        end
    end
end

"""
Add to `ref` the following keys:
- `:oltc_branch`: the set of `frb_branch`es that are OLTCs;
- `:oltc_ne_branch`: the set of `frb_ne_branch`es that are OLTCs.
"""
function ref_add_oltc_branch!(ref::Dict{Symbol,Any}, data::Dict{String,<:Any})
    for (nw, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        if !haskey(nw_ref, :frb_branch)
            Memento.error(_LOGGER, "ref_add_oltc_branch! must be called after ref_add_frb_branch!")
        end
        oltc_branch = Dict{Int,Any}()
        for (i,br) in nw_ref[:frb_branch]
            if br["transformer"] && haskey(br, "tm_min") && haskey(br, "tm_max") && br["tm_min"] < br["tm_max"]
                oltc_branch[i] = br
            end
        end
        nw_ref[:oltc_branch] = oltc_branch

        if haskey(nw_ref, :frb_ne_branch)
            oltc_ne_branch = Dict{Int,Any}()
            for (i,br) in nw_ref[:ne_branch]
                if br["transformer"] && haskey(br, "tm_min") && haskey(br, "tm_max") && br["tm_min"] < br["tm_max"]
                    oltc_ne_branch[i] = br
                end
            end
            nw_ref[:oltc_ne_branch] = oltc_ne_branch
        end
    end
end

"Like PowerModels.calc_buspair_parameters, but retains indices of all the branches and drops keys that depend on branch"
function _calc_buspair_parameters_allbranches(buses, branches, conductor_ids, ismulticondcutor)
    bus_lookup = Dict(bus["index"] => bus for (i,bus) in buses if bus["bus_type"] != 4)

    branch_lookup = Dict(branch["index"] => branch for (i,branch) in branches if branch["br_status"] == 1 && haskey(bus_lookup, branch["f_bus"]) && haskey(bus_lookup, branch["t_bus"]))

    buspair_indexes = Set((branch["f_bus"], branch["t_bus"]) for (i,branch) in branch_lookup)

    bp_branch = Dict((bp, Int[]) for bp in buspair_indexes)

    if ismulticondcutor
        bp_angmin = Dict((bp, [-Inf for c in conductor_ids]) for bp in buspair_indexes)
        bp_angmax = Dict((bp, [ Inf for c in conductor_ids]) for bp in buspair_indexes)
    else
        @assert(length(conductor_ids) == 1)
        bp_angmin = Dict((bp, -Inf) for bp in buspair_indexes)
        bp_angmax = Dict((bp,  Inf) for bp in buspair_indexes)
    end

    for (l,branch) in branch_lookup
        i = branch["f_bus"]
        j = branch["t_bus"]

        if ismulticondcutor
            for c in conductor_ids
                bp_angmin[(i,j)][c] = max(bp_angmin[(i,j)][c], branch["angmin"][c])
                bp_angmax[(i,j)][c] = min(bp_angmax[(i,j)][c], branch["angmax"][c])
            end
        else
            bp_angmin[(i,j)] = max(bp_angmin[(i,j)], branch["angmin"])
            bp_angmax[(i,j)] = min(bp_angmax[(i,j)], branch["angmax"])
        end

        bp_branch[(i,j)] = push!(bp_branch[(i,j)], l)
    end

    buspairs = Dict((i,j) => Dict(
        "branches"=>bp_branch[(i,j)],
        "angmin"=>bp_angmin[(i,j)],
        "angmax"=>bp_angmax[(i,j)],
        "vm_fr_min"=>bus_lookup[i]["vmin"],
        "vm_fr_max"=>bus_lookup[i]["vmax"],
        "vm_to_min"=>bus_lookup[j]["vmin"],
        "vm_to_max"=>bus_lookup[j]["vmax"]
        ) for (i,j) in buspair_indexes
    )

    return buspairs
end
