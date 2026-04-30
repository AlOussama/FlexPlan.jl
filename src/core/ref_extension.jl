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
    "carrier",
    "grid_control_mode",
    "n0",
    "nmax",
    "na0",
    "p_block_max",
    "q_block_min",
    "q_block_max",
    "b_block",
    "cost_inv_per_mw",
    "p_min_pu",
    "p_max_pu",
]

const _UC_GSCR_BLOCK_MIN_UP_DOWN_FIELDS = ["min_up_block_time", "min_down_block_time"]
const _UC_GSCR_BLOCK_STORAGE_REQUIRED_FIELDS = ["e_block"]
const _UC_GSCR_BLOCK_OPTIONAL_FIELDS = ["H", "s_block", "startup_cost_per_mw", "shutdown_cost_per_mw", "p_block_min", _UC_GSCR_BLOCK_MIN_UP_DOWN_FIELDS...]
const _UC_GSCR_BLOCK_REJECTED_FIELDS = [
    "type",
    "startup_block_cost",
    "shutdown_block_cost",
    "cost_inv_block",
    "activation_policy",
    "uc_policy",
    "gscr_exposure_policy",
]
const _UC_GSCR_BLOCK_DETECTION_FIELDS = unique([
    _UC_GSCR_BLOCK_REQUIRED_FIELDS;
    _UC_GSCR_BLOCK_STORAGE_REQUIRED_FIELDS;
    _UC_GSCR_BLOCK_OPTIONAL_FIELDS;
    _UC_GSCR_BLOCK_REJECTED_FIELDS;
])

"""
    ref_add_uc_gscr_block!(ref, data)

Adds UC/gSCR block reference maps and baseline full-network row metrics to
each PowerModels network reference.

Mathematically, this stores GFL/GFM device sets, bus-device incidence maps,
the full-network baseline susceptance matrix `B^0`, the Gershgorin margin
`B^0[n,n] - sum(abs(B^0[n,j]) for j != n)`, and the raw row sum diagnostic.
The function reads block fields from `gen`, `storage`, and `ne_storage`.
If no block fields are present in a network, it leaves that network unchanged.
Mixed AC/DC optimization networks are supported: `B^0` is built only from the
AC-side PowerModels tables (`:bus`, `:branch`), while DC-side tables are
ignored for `B^0`.

Arguments are the PowerModels `ref` dictionary and original network `data`.
Block strengths are assumed to be in a per-unit base consistent with device
power fields. This function is formulation-independent and mutates only `ref`.
"""
function ref_add_uc_gscr_block!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    any_block_data = any(_has_uc_gscr_block_data(nw_ref) for (_, nw_ref) in ref[:it][_PM.pm_it_sym][:nw])
    if any_block_data
        _validate_uc_gscr_block_schema_declaration(ref, data)
    end

    for (nw, nw_ref) in ref[:it][_PM.pm_it_sym][:nw]
        if !_has_uc_gscr_block_data(nw_ref)
            continue
        end

        _validate_uc_gscr_block_snapshot_fields(nw_ref, nw)
        min_up_down_enabled = _uc_gscr_block_min_up_down_enabled(nw_ref)
        missing_report = _uc_gscr_missing_required_fields_report(nw_ref; min_up_down_enabled)
        _warn_uc_gscr_missing_required_fields(missing_report)
        _validate_uc_gscr_rejected_block_fields(nw_ref)
        _validate_uc_gscr_block_devices(nw_ref; min_up_down_enabled)
        _warn_uc_gscr_deprecated_block_fields(nw_ref)
        _add_uc_gscr_device_maps!(nw_ref)
        _add_uc_gscr_row_metrics!(nw_ref)
        nw_ref[:uc_gscr_block_min_up_down_enabled] = min_up_down_enabled
    end
end

function _validate_uc_gscr_block_schema_declaration(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    schema = if haskey(data, "block_model_schema")
        data["block_model_schema"]
    else
        first_nw_ref = first(values(ref[:it][_PM.pm_it_sym][:nw]))
        if haskey(first_nw_ref, :block_model_schema)
            first_nw_ref[:block_model_schema]
        else
            nothing
        end
    end

    if !(schema isa Dict)
        Memento.error(_LOGGER, "UC/gSCR block schema v2 validation failed: block data requires block_model_schema.name=\"uc_gscr_block\" and version=\"2.0\".")
    end
    if get(schema, "name", nothing) != "uc_gscr_block"
        Memento.error(_LOGGER, "UC/gSCR block schema v2 validation failed: block_model_schema.name must be \"uc_gscr_block\".")
    end
    if get(schema, "version", nothing) != "2.0"
        Memento.error(_LOGGER, "UC/gSCR block schema v2 validation failed: block_model_schema.version must be \"2.0\".")
    end
    return nothing
end

function _validate_uc_gscr_block_snapshot_fields(nw_ref::Dict{Symbol,<:Any}, nw)
    if !haskey(nw_ref, :operation_weight)
        Memento.error(_LOGGER, "UC/gSCR block schema v2 validation failed: network snapshot $(nw) is missing required field `operation_weight`.")
    end
    if !haskey(nw_ref, :time_elapsed)
        Memento.warn(_LOGGER, "UC/gSCR block schema v2 prefers explicit `time_elapsed`; continuing with existing storage default behavior for snapshot $(nw).")
    end
    return nothing
end

"""
    _uc_gscr_block_min_up_down_enabled(nw_ref)

Returns whether UC/gSCR block minimum up/down-time constraints are enabled for
`nw_ref`.

The feature is enabled when at least one block-annotated supported device
contains either `min_up_block_time` or `min_down_block_time`. This helper is
formulation-independent, mutates no data, and preserves backward
compatibility for cases that do not opt in to minimum up/down-time fields.
"""
function _uc_gscr_block_min_up_down_enabled(nw_ref::Dict{Symbol,<:Any})
    for (_, _, device) in _uc_gscr_block_devices(nw_ref)
        if any(haskey(device, field) for field in _UC_GSCR_BLOCK_MIN_UP_DOWN_FIELDS)
            return true
        end
    end
    return false
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
            if any(haskey(device, field) for field in _UC_GSCR_BLOCK_DETECTION_FIELDS)
                return true
            end
        end
    end
    return false
end

"""
    _uc_gscr_missing_required_fields_report(nw_ref; min_up_down_enabled=false)

Builds a missing-field report for required UC/gSCR block schema entries.

Returned keys are `(table_name, device_id)` tuples and values are vectors of
missing required field names. When `min_up_down_enabled=true`, required fields
also include `min_up_block_time` and `min_down_block_time`; otherwise only the
base UC/gSCR block schema is required. Only block-annotated devices with
missing fields are included. This helper is formulation-independent and
mutates no data.
"""
function _uc_gscr_missing_required_fields_report(nw_ref::Dict{Symbol,<:Any}; min_up_down_enabled::Bool=false)
    report = Dict{Tuple{Symbol,Any},Vector{String}}()
    required_fields = if min_up_down_enabled
        [_UC_GSCR_BLOCK_REQUIRED_FIELDS; _UC_GSCR_BLOCK_MIN_UP_DOWN_FIELDS]
    else
        _UC_GSCR_BLOCK_REQUIRED_FIELDS
    end
    for (table_name, device_id, device) in _uc_gscr_block_devices(nw_ref)
        device_required_fields = table_name in (:storage, :ne_storage) ? [required_fields; _UC_GSCR_BLOCK_STORAGE_REQUIRED_FIELDS] : required_fields
        missing = String[field for field in device_required_fields if !haskey(device, field)]
        if !isempty(missing)
            report[(table_name, device_id)] = missing
        end
    end
    return report
end

function _validate_uc_gscr_rejected_block_fields(nw_ref::Dict{Symbol,<:Any})
    rejected_report = Dict{Tuple{Symbol,Any},Vector{String}}()
    for (table_name, device_id, device) in _uc_gscr_block_devices(nw_ref)
        rejected = String[field for field in _UC_GSCR_BLOCK_REJECTED_FIELDS if haskey(device, field)]
        if !isempty(rejected)
            rejected_report[(table_name, device_id)] = rejected
        end
    end

    if !isempty(rejected_report)
        device_summaries = String[
            "$(uppercase(string(table_name))) $(device_id): $(join(rejected_fields, ", "))"
            for ((table_name, device_id), rejected_fields) in rejected_report
        ]
        Memento.error(
            _LOGGER,
            "UC/gSCR block schema v2 validation failed due to rejected old or policy fields. " *
            "Rejected-field report: " * join(device_summaries, " | ") * ". " *
            "Use grid_control_mode and cost_inv_per_mw, and provide formulation policy through a model template.",
        )
    end
    return nothing
end

"""
    _warn_uc_gscr_missing_required_fields(missing_report)

Logs warnings for every device that is missing required UC/gSCR block fields.

This warning pass is intentionally separate from hard validation errors so the
user gets an explicit missing-field report before execution stops. The helper
is formulation-independent and mutates no model or data state.
"""
function _warn_uc_gscr_missing_required_fields(missing_report::Dict{Tuple{Symbol,Any},Vector{String}})
    for ((table_name, device_id), missing_fields) in missing_report
        Memento.warn(
            _LOGGER,
            "$(uppercase(string(table_name))) device $(device_id) is missing required UC/gSCR block fields: $(join(missing_fields, ", ")).",
        )
    end
    return nothing
end

"""
    _validate_uc_gscr_block_devices(nw_ref; min_up_down_enabled=false)

Validates required UC/gSCR block fields on every block-annotated supported
device in `nw_ref`.

The required schema-v2 fields include `carrier`, `grid_control_mode`, `n0`,
`nmax`, `na0`, per-active-block P/Q bounds, `b_block`, `cost_inv_per_mw`,
`p_min_pu`, and `p_max_pu`, with `grid_control_mode` restricted to `"gfl"` or
`"gfm"`.
When `min_up_down_enabled=true`, `min_up_block_time` and
`min_down_block_time` are additionally required and must be nonnegative
integers (snapshot counts). No defaults are inferred for these mathematical
fields. Block counts must satisfy `0 <= na0 <= n0 <= nmax`. Optional fields `H`, `s_block`, and `e_block` are only read when
present. For block-annotated `ne_storage` devices, a warning is emitted when
`charge_rating` or `discharge_rating` is smaller than `p_block_max`, since the
standard rating creates a hard variable upper bound that may bind before the
block-scaled constraint. This function is formulation-independent and mutates no data.
Missing required fields are reported explicitly and then raise a hard
validation error.
"""
function _validate_uc_gscr_block_devices(nw_ref::Dict{Symbol,<:Any}; min_up_down_enabled::Bool=false)
    missing_report = _uc_gscr_missing_required_fields_report(nw_ref; min_up_down_enabled)
    if !isempty(missing_report)
        device_summaries = String[
            "$(uppercase(string(table_name))) $(device_id): $(join(missing_fields, ", "))"
            for ((table_name, device_id), missing_fields) in missing_report
        ]
        Memento.error(
            _LOGGER,
            "UC/gSCR block schema validation failed due to missing required fields. " *
            "Missing-field report: " * join(device_summaries, " | ") * ". " *
            "No silent defaults are applied.",
        )
    end

    for (table_name, device_id, device) in _uc_gscr_block_devices(nw_ref)
        grid_control_mode = device["grid_control_mode"]
        if !(grid_control_mode in ("gfl", "gfm"))
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid UC/gSCR block field `grid_control_mode=$(grid_control_mode)`. Expected `gfl` or `gfm`.")
        end

        n0 = device["n0"]
        nmax = device["nmax"]
        if !_uc_gscr_is_numeric(n0) || !_uc_gscr_is_numeric(nmax) || n0 < 0 || nmax < n0
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid UC/gSCR block bounds: require numeric 0 <= n0 <= nmax.")
        end

        na0 = device["na0"]
        if !_uc_gscr_is_numeric(na0) || na0 < 0 || n0 < na0
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid UC/gSCR active-block initial state: require numeric 0 <= na0 <= n0 <= nmax.")
        end

        p_block_max = device["p_block_max"]
        if !_uc_gscr_is_numeric(p_block_max)
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid `p_block_max=$(p_block_max)`. Expected a numeric value.")
        end
        if nmax > n0 && p_block_max <= 0
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid expandable UC/gSCR block capacity: require p_block_max > 0 when nmax > n0.")
        end

        if !_uc_gscr_is_numeric(device["q_block_min"]) || !_uc_gscr_is_numeric(device["q_block_max"])
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid reactive block bounds: q_block_min and q_block_max must be numeric.")
        end
        if device["q_block_min"] > device["q_block_max"]
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid reactive block bounds: require q_block_min <= q_block_max.")
        end
        if !_uc_gscr_is_numeric(device["b_block"])
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid `b_block=$(device["b_block"])`. Expected a numeric value.")
        end
        if !_uc_gscr_is_numeric(device["cost_inv_per_mw"]) || device["cost_inv_per_mw"] < 0
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid `cost_inv_per_mw=$(device["cost_inv_per_mw"])`. Expected a nonnegative numeric value.")
        end
        _validate_uc_gscr_block_pu_bounds(table_name, device_id, device)

        if table_name in (:storage, :ne_storage) && !_uc_gscr_is_numeric(device["e_block"])
            Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid `e_block=$(device["e_block"])`. Expected a numeric value.")
        end

        if min_up_down_enabled
            min_up_block_time = device["min_up_block_time"]
            min_down_block_time = device["min_down_block_time"]

            if !(min_up_block_time isa Integer) || min_up_block_time < 0
                Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid `min_up_block_time=$(min_up_block_time)`. Expected a nonnegative integer number of snapshots.")
            end
            if !(min_down_block_time isa Integer) || min_down_block_time < 0
                Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid `min_down_block_time=$(min_down_block_time)`. Expected a nonnegative integer number of snapshots.")
            end
        end

        if table_name == :ne_storage && _uc_gscr_is_numeric(p_block_max) && p_block_max > 0
            _warn_uc_gscr_storage_rating_conflict(device, device_id, p_block_max, nmax)
        end
    end
end

_uc_gscr_is_numeric(value) = value isa Real && isfinite(value)

function _validate_uc_gscr_block_pu_bounds(table_name::Symbol, device_id, device::Dict{String,<:Any})
    p_min_values = _uc_gscr_numeric_values(device["p_min_pu"], "p_min_pu")
    p_max_values = _uc_gscr_numeric_values(device["p_max_pu"], "p_max_pu")

    if any(value < 0 for value in p_min_values)
        Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid `p_min_pu`: numeric values must be nonnegative.")
    end
    if any(value < 0 for value in p_max_values)
        Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid `p_max_pu`: numeric values must be nonnegative.")
    end

    if device["p_min_pu"] isa Real && device["p_max_pu"] isa Real && device["p_min_pu"] > device["p_max_pu"]
        Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid scalar active-power per-unit bounds: require 0 <= p_min_pu <= p_max_pu.")
    end

    if device["p_min_pu"] isa AbstractVector && device["p_max_pu"] isa AbstractVector
        for (p_min, p_max) in zip(device["p_min_pu"], device["p_max_pu"])
            if p_min > p_max
                Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid vector active-power per-unit bounds: require p_min_pu <= p_max_pu at each comparable snapshot.")
            end
        end
    elseif device["p_min_pu"] isa Dict && device["p_max_pu"] isa Dict
        for key in intersect(keys(device["p_min_pu"]), keys(device["p_max_pu"]))
            p_min = device["p_min_pu"][key]
            p_max = device["p_max_pu"][key]
            if p_min > p_max
                Memento.error(_LOGGER, "$(uppercase(string(table_name))) device $(device_id) has invalid snapshot-keyed active-power per-unit bounds at $(key): require p_min_pu <= p_max_pu.")
            end
        end
    end

    return nothing
end

function _uc_gscr_numeric_values(value, field_name::String)
    if value isa Real
        if !isfinite(value)
            Memento.error(_LOGGER, "UC/gSCR block schema v2 validation failed: $(field_name) values must be finite numeric values.")
        end
        return Real[value]
    elseif value isa AbstractVector || value isa Tuple
        numeric_values = Real[]
        for item in value
            if !(item isa Real) || !isfinite(item)
                Memento.error(_LOGGER, "UC/gSCR block schema v2 validation failed: $(field_name) time-series values must be finite numeric values.")
            end
            push!(numeric_values, item)
        end
        return numeric_values
    elseif value isa Dict
        numeric_values = Real[]
        for item in values(value)
            if !(item isa Real) || !isfinite(item)
                Memento.error(_LOGGER, "UC/gSCR block schema v2 validation failed: $(field_name) snapshot-keyed values must be finite numeric values.")
            end
            push!(numeric_values, item)
        end
        return numeric_values
    else
        Memento.error(_LOGGER, "UC/gSCR block schema v2 validation failed: p_min_pu and p_max_pu must be scalar, vector, tuple, or dict keyed by snapshot.")
    end
end

"""
    _warn_uc_gscr_storage_rating_conflict(device, device_id, p_block_max, nmax)

Warns when a block-annotated `ne_storage` device has standard charge or
discharge ratings smaller than `p_block_max`.

The standard `charge_rating` and `discharge_rating` fields set hard variable
upper bounds that also appear in `constraint_storage_bounds_ne`. When these
ratings are smaller than `p_block_max`, they are binding before the
block-scaled constraint `sc <= p_block_max * na_block` takes effect, silently
limiting storage capability below the block-scaled design. Users must set
`charge_rating >= p_block_max` and `discharge_rating >= p_block_max` (or
equivalently `>= p_block_max * nmax` for block counts above 1) to avoid this
conflict. This function is formulation-independent and mutates no data.
"""
function _warn_uc_gscr_storage_rating_conflict(device::Dict{String,<:Any}, device_id, p_block_max::Real, nmax::Real)
    charge_rating = get(device, "charge_rating", Inf)
    discharge_rating = get(device, "discharge_rating", Inf)
    if charge_rating < p_block_max
        Memento.warn(
            _LOGGER,
            "NE_STORAGE device $(device_id) has charge_rating=$(charge_rating) < p_block_max=$(p_block_max). " *
            "The standard charge_rating sets a hard variable upper bound via constraint_storage_bounds_ne " *
            "that will be binding before the block-scaled bound sc <= p_block_max * na_block. " *
            "Set charge_rating >= p_block_max (ideally >= p_block_max * nmax=$(nmax)) to avoid this conflict.",
        )
    end
    if discharge_rating < p_block_max
        Memento.warn(
            _LOGGER,
            "NE_STORAGE device $(device_id) has discharge_rating=$(discharge_rating) < p_block_max=$(p_block_max). " *
            "The standard discharge_rating sets a hard variable upper bound via constraint_storage_bounds_ne " *
            "that will be binding before the block-scaled bound sd <= p_block_max * na_block. " *
            "Set discharge_rating >= p_block_max (ideally >= p_block_max * nmax=$(nmax)) to avoid this conflict.",
        )
    end
end

"""
    _warn_uc_gscr_deprecated_block_fields(nw_ref)

Warns when deprecated UC/gSCR block fields are present.

`p_block_min` is deprecated in the active block-dispatch formulation and is
ignored there. Use `p_min_pu` with `p_block_max` instead.
"""
function _warn_uc_gscr_deprecated_block_fields(nw_ref::Dict{Symbol,<:Any})
    for (table_name, device_id, device) in _uc_gscr_block_devices(nw_ref)
        if haskey(device, "p_block_min")
            Memento.warn(
                _LOGGER,
                "$(uppercase(string(table_name))) device $(device_id) sets deprecated field `p_block_min`. " *
                "It is ignored by active block dispatch bounds; use p_min_pu and p_block_max.",
            )
        end
    end
    return nothing
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
            if any(haskey(device, field) for field in _UC_GSCR_BLOCK_DETECTION_FIELDS)
                if _uc_gscr_is_inactive_placeholder_device(device)
                    continue
                end
                push!(devices, (table_name, device_id, device))
            end
        end
    end
    return devices
end

"""
    _uc_gscr_is_inactive_placeholder_device(device)

Returns whether a block record is an inactive placeholder that should be
ignored by the UC/gSCR block extension.

A placeholder has `p_block_max <= 0` and zero baseline block counts
`na0 = n0 = nmax = 0`.
"""
function _uc_gscr_is_inactive_placeholder_device(device::Dict{String,<:Any})
    if !(haskey(device, "p_block_max") && haskey(device, "n0") && haskey(device, "nmax") && haskey(device, "na0"))
        return false
    end
    if !_uc_gscr_is_numeric(device["p_block_max"])
        return false
    end
    return device["p_block_max"] <= 0 && device["na0"] == 0 && device["n0"] == 0 && device["nmax"] == 0
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
        if device["grid_control_mode"] == "gfl"
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

The matrix `B^0` is built as the UC/gSCR strength matrix from PowerModels'
basic susceptance convention: `B^0 = -B_pm`, where
`B_pm = calc_basic_susceptance_matrix(...)`. The Gershgorin margin is
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
        offdiag_abs = sum((abs(b0[(bus_id, other_bus_id)]) for other_bus_id in bus_ids if other_bus_id != bus_id); init=0.0)
        margin[bus_id] = diag_value - offdiag_abs
        raw_rowsum[bus_id] = sum((b0[(bus_id, other_bus_id)] for other_bus_id in bus_ids); init=0.0)
    end

    nw_ref[:gscr_b0] = b0
    nw_ref[:gscr_sigma0_gershgorin_margin] = margin
    nw_ref[:gscr_sigma0_raw_rowsum] = raw_rowsum
end

"""
    _calc_uc_gscr_susceptance_matrix(nw_ref)

Builds the full-network baseline strength matrix `B^0` from PowerModels
susceptance conventions.

This helper builds a basic-compatible network dictionary on a non-mutating
path and computes `B_pm = PowerModels.calc_basic_susceptance_matrix(data)`,
which follows PowerModels' DC-flow sign convention `p = -B_pm * theta`.
The UC/gSCR strength matrix is then defined as `B^0 = -B_pm`, yielding the
required sign pattern (nonnegative diagonal, nonpositive off-diagonal for
inductive networks). The matrix is mapped back onto the original full bus set
without Kron reduction, and missing rows/columns are kept at zero. This helper
is formulation-independent and mutates no input data.
"""
function _calc_uc_gscr_susceptance_matrix(nw_ref::Dict{Symbol,<:Any})
    bus_ids = sort(collect(keys(nw_ref[:bus])))
    b0_strength = Dict((i, j) => 0.0 for i in bus_ids for j in bus_ids)

    basic_data = _uc_gscr_basic_susceptance_data(nw_ref)
    if isempty(basic_data["branch"])
        return b0_strength
    end

    b0_strength_ac = -_PM.calc_basic_susceptance_matrix(basic_data)
    idx_to_bus = _PM.calc_susceptance_matrix(basic_data).idx_to_bus

    for row_idx in axes(b0_strength_ac, 1), col_idx in axes(b0_strength_ac, 2)
        row_bus = idx_to_bus[row_idx]
        col_bus = idx_to_bus[col_idx]
        if haskey(nw_ref[:bus], row_bus) && haskey(nw_ref[:bus], col_bus)
            b0_strength[(row_bus, col_bus)] = b0_strength_ac[row_idx, col_idx]
        end
    end

    return b0_strength
end

"""
    _uc_gscr_basic_susceptance_data(nw_ref)

Builds a non-mutating, basic-compatible network dictionary for susceptance
matrix construction.

The returned data keeps the full bus set from `nw_ref` where possible and
contains only the fields required by PowerModels susceptance routines:
`bus`, `branch`, `dcline`, `switch`, and `basic_network=true`. Branch defaults
are filled for omitted optional electrical fields. AC-side extraction must be
unambiguous: each AC branch endpoint must map to the AC bus table. This helper
is
formulation-independent and mutates no input data.
"""
function _uc_gscr_basic_susceptance_data(nw_ref::Dict{Symbol,<:Any})
    if !haskey(nw_ref, :bus)
        Memento.error(_LOGGER, "UC/gSCR AC-side extraction is ambiguous: network reference is missing `:bus`.")
    end

    branch_table = get(nw_ref, :branch, Dict())
    _validate_uc_gscr_ac_side_extraction(nw_ref[:bus], branch_table)

    bus = Dict{String,Any}()
    for (bus_id, bus_data) in nw_ref[:bus]
        bus_entry = deepcopy(bus_data)
        bus_entry["index"] = get(bus_entry, "index", bus_id)
        bus_entry["bus_i"] = get(bus_entry, "bus_i", bus_entry["index"])
        bus_entry["bus_type"] = get(bus_entry, "bus_type", 1)
        bus_entry["vm"] = get(bus_entry, "vm", 1.0)
        bus_entry["va"] = get(bus_entry, "va", 0.0)
        bus_entry["vmin"] = get(bus_entry, "vmin", 0.9)
        bus_entry["vmax"] = get(bus_entry, "vmax", 1.1)
        bus_entry["base_kv"] = get(bus_entry, "base_kv", 1.0)
        bus_entry["zone"] = get(bus_entry, "zone", 1)
        bus[string(bus_id)] = bus_entry
    end

    branch = Dict{String,Any}()
    for (branch_id, branch_data) in branch_table
        branch_entry = deepcopy(branch_data)
        branch_entry["index"] = get(branch_entry, "index", branch_id)
        branch_entry["br_status"] = get(branch_entry, "br_status", 1)
        branch_entry["br_r"] = get(branch_entry, "br_r", 0.0)
        branch_entry["br_x"] = get(branch_entry, "br_x", 0.0)
        branch_entry["g_fr"] = get(branch_entry, "g_fr", 0.0)
        branch_entry["g_to"] = get(branch_entry, "g_to", 0.0)
        branch_entry["b_fr"] = get(branch_entry, "b_fr", 0.0)
        branch_entry["b_to"] = get(branch_entry, "b_to", 0.0)
        branch_entry["tap"] = get(branch_entry, "tap", 1.0)
        branch_entry["shift"] = get(branch_entry, "shift", 0.0)
        branch_entry["rate_a"] = get(branch_entry, "rate_a", 1.0e6)
        branch_entry["angmin"] = get(branch_entry, "angmin", -Inf)
        branch_entry["angmax"] = get(branch_entry, "angmax", Inf)
        branch_entry["transformer"] = get(branch_entry, "transformer", false)
        branch[string(branch_id)] = branch_entry
    end

    return Dict{String,Any}(
        "basic_network" => true,
        "bus" => bus,
        "branch" => branch,
        "dcline" => Dict{String,Any}(),
        "switch" => Dict{String,Any}(),
    )
end

"""
    _validate_uc_gscr_ac_side_extraction(bus_table, branch_table)

Validates that the AC-side tables used for UC/gSCR `B^0` extraction are
unambiguous.

Each branch must define `f_bus` and `t_bus`, and both endpoint buses must
exist in `bus_table`. This validator is formulation-independent and mutates no
input data.
"""
function _validate_uc_gscr_ac_side_extraction(bus_table, branch_table)
    for (branch_id, branch_data) in branch_table
        if !haskey(branch_data, "f_bus") || !haskey(branch_data, "t_bus")
            Memento.error(
                _LOGGER,
                "UC/gSCR AC-side extraction is ambiguous: branch $(branch_id) is missing `f_bus` or `t_bus` in `:branch`.",
            )
        end

        f_bus = branch_data["f_bus"]
        t_bus = branch_data["t_bus"]
        if !haskey(bus_table, f_bus) || !haskey(bus_table, t_bus)
            Memento.error(
                _LOGGER,
                "UC/gSCR AC-side extraction is ambiguous: branch $(branch_id) endpoint(s) ($(f_bus), $(t_bus)) are not present in AC `:bus`.",
            )
        end
    end
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
