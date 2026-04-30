abstract type AbstractBlockDeviceFormulation end

struct BlockThermalCommitment <: AbstractBlockDeviceFormulation end
struct BlockRenewableParticipation <: AbstractBlockDeviceFormulation end
struct BlockFixedInstalled <: AbstractBlockDeviceFormulation end
struct BlockStorageParticipation <: AbstractBlockDeviceFormulation end

abstract type AbstractGSCRExposure end

struct OnlineNameplateExposure <: AbstractGSCRExposure end

abstract type AbstractGSCRFormulation end

struct NoGSCR <: AbstractGSCRFormulation end

struct GershgorinGSCR{T<:AbstractGSCRExposure} <: AbstractGSCRFormulation
    exposure::T
end
GershgorinGSCR() = GershgorinGSCR(OnlineNameplateExposure())

const _UC_GSCR_BLOCK_TEMPLATE_TABLES = (:gen, :storage, :ne_storage)

struct UCGSCRBlockTemplate
    carrier_formulations::Dict{Tuple{Symbol,Any},AbstractBlockDeviceFormulation}
    device_formulations::Dict{Tuple{Symbol,Any},AbstractBlockDeviceFormulation}
    gscr_formulation::AbstractGSCRFormulation
end

function UCGSCRBlockTemplate(
    carrier_formulations::AbstractDict,
    gscr_formulation::AbstractGSCRFormulation=NoGSCR();
    device_formulations::AbstractDict=Dict{Tuple{Symbol,Any},AbstractBlockDeviceFormulation}(),
)
    carrier_map = Dict{Tuple{Symbol,Any},AbstractBlockDeviceFormulation}()
    for (key, formulation) in carrier_formulations
        table, carrier = _uc_gscr_block_template_key(key, "carrier assignment")
        if !(table in _UC_GSCR_BLOCK_TEMPLATE_TABLES)
            Memento.error(_LOGGER, "UC/gSCR block template carrier assignment uses unsupported table `$(table)`. Supported tables are gen, storage, and ne_storage.")
        end
        if !(formulation isa AbstractBlockDeviceFormulation)
            Memento.error(_LOGGER, "UC/gSCR block template carrier assignment ($(table), $(carrier)) must map to a block-device formulation object.")
        end
        carrier_map[(table, carrier)] = formulation
    end

    device_map = Dict{Tuple{Symbol,Any},AbstractBlockDeviceFormulation}()
    for (key, formulation) in device_formulations
        table, device_id = _uc_gscr_block_template_key(key, "device override")
        if !(table in _UC_GSCR_BLOCK_TEMPLATE_TABLES)
            Memento.error(_LOGGER, "UC/gSCR block template device override uses unsupported table `$(table)`. Supported tables are gen, storage, and ne_storage.")
        end
        if !(formulation isa AbstractBlockDeviceFormulation)
            Memento.error(_LOGGER, "UC/gSCR block template device override ($(table), $(device_id)) must map to a block-device formulation object.")
        end
        device_map[(table, device_id)] = formulation
    end

    return UCGSCRBlockTemplate(carrier_map, device_map, gscr_formulation)
end

function _uc_gscr_block_template_key(key, context::String)
    if !(key isa Tuple) || length(key) != 2 || !(key[1] isa Symbol)
        Memento.error(_LOGGER, "UC/gSCR block template $(context) keys must be `(table::Symbol, carrier_or_device_id)` tuples.")
    end
    return key[1], key[2]
end

function resolve_uc_gscr_block_template!(pm::_PM.AbstractPowerModel, template::UCGSCRBlockTemplate)
    pm.ext[:uc_gscr_block_template] = template

    resolved = Dict{Int,Dict{Tuple{Symbol,Any},AbstractBlockDeviceFormulation}}()
    for nw in nw_ids(pm)
        resolved[nw] = _resolve_uc_gscr_block_template_network(pm, nw, template)
    end

    pm.ext[:uc_gscr_block_formulations] = resolved
    pm.ext[:uc_gscr_block_gscr_formulation] = template.gscr_formulation
    pm.ext[:uc_gscr_block_device_sets] = _uc_gscr_block_template_device_sets(resolved)
    _validate_uc_gscr_block_template_gscr(pm, template.gscr_formulation)
    return resolved
end

"""
    _uc_gscr_block_gscr_formulation(pm, nw)

Returns the resolved UC/gSCR block gSCR formulation for network `nw`.

Block-enabled schema-v2 models must resolve a `UCGSCRBlockTemplate` before
formulation-specific model construction. No physical device fields or legacy
policy fields are used to infer whether gSCR constraints should be active.
"""
function _uc_gscr_block_gscr_formulation(pm::_PM.AbstractPowerModel, nw::Int)
    if !_has_uc_gscr_block_ref(pm, nw)
        return NoGSCR()
    end
    _require_uc_gscr_block_template_resolved(pm, nw)

    if haskey(pm.ext, :uc_gscr_block_gscr_formulation)
        gscr = pm.ext[:uc_gscr_block_gscr_formulation]
    elseif haskey(pm.ext, :uc_gscr_block_template)
        template = pm.ext[:uc_gscr_block_template]
        if !(template isa UCGSCRBlockTemplate)
            Memento.error(_LOGGER, "Resolved UC/gSCR block template cache has unsupported type `$(typeof(template))`.")
        end
        gscr = template.gscr_formulation
    else
        Memento.error(
            _LOGGER,
            "UC/gSCR block formulation-specific model construction requires a resolved UCGSCRBlockTemplate for network $(nw). " *
            "Pass `template=...` to `uc_gscr_block_integration` or call `resolve_uc_gscr_block_template!` before creating block variables or constraints.",
        )
    end

    _validate_uc_gscr_block_gscr_formulation_supported(gscr)
    return gscr
end

"""
    _uc_gscr_block_requires_gscr_constraints(pm, nw)

Returns whether the resolved UC/gSCR block template selects a gSCR constraint
formulation for network `nw`.
"""
function _uc_gscr_block_requires_gscr_constraints(pm::_PM.AbstractPowerModel, nw::Int)
    gscr = _uc_gscr_block_gscr_formulation(pm, nw)
    if gscr isa NoGSCR
        return false
    elseif gscr isa GershgorinGSCR
        return true
    else
        Memento.error(_LOGGER, "Unsupported UC/gSCR block template gSCR formulation `$(typeof(gscr))`.")
    end
end

function _resolve_uc_gscr_block_template_network(pm::_PM.AbstractPowerModel, nw::Int, template::UCGSCRBlockTemplate)
    block_device_keys = _uc_gscr_block_template_device_keys(pm, nw)
    block_device_set = Set(block_device_keys)

    for override_key in keys(template.device_formulations)
        if !(override_key in block_device_set)
            Memento.error(_LOGGER, "UC/gSCR block template override $(override_key) does not reference a block-enabled device in network $(nw).")
        end
    end

    resolved = Dict{Tuple{Symbol,Any},AbstractBlockDeviceFormulation}()
    for device_key in block_device_keys
        formulation = _uc_gscr_block_template_formulation(pm, nw, template, device_key)
        _validate_uc_gscr_block_template_device(pm, nw, device_key, formulation)
        resolved[device_key] = formulation
    end
    return resolved
end

function _uc_gscr_block_template_formulation(pm::_PM.AbstractPowerModel, nw::Int, template::UCGSCRBlockTemplate, device_key::Tuple{Symbol,Any})
    if haskey(template.device_formulations, device_key)
        return template.device_formulations[device_key]
    end

    table, device_id = device_key
    carrier = _PM.ref(pm, nw, table, device_id, "carrier")
    carrier_key = (table, carrier)
    if !haskey(template.carrier_formulations, carrier_key)
        Memento.error(_LOGGER, "UC/gSCR block template has no formulation assignment for block-enabled $(uppercase(string(table))) device $(device_id) with carrier `$(carrier)` in network $(nw).")
    end
    return template.carrier_formulations[carrier_key]
end

function _validate_uc_gscr_block_template_device(pm::_PM.AbstractPowerModel, nw::Int, device_key::Tuple{Symbol,Any}, formulation::AbstractBlockDeviceFormulation)
    if formulation isa BlockThermalCommitment
        for field in ("startup_cost_per_mw", "shutdown_cost_per_mw")
            if !haskey(_PM.ref(pm, nw, device_key[1], device_key[2]), field)
                Memento.error(_LOGGER, "UC/gSCR block template validation failed: $(uppercase(string(device_key[1]))) device $(device_key[2]) uses BlockThermalCommitment and is missing required field `$(field)`.")
            end
        end
    end
    return nothing
end

function _validate_uc_gscr_block_template_gscr(pm::_PM.AbstractPowerModel, gscr::AbstractGSCRFormulation)
    _validate_uc_gscr_block_gscr_formulation_supported(gscr)
    if gscr isa NoGSCR
        return nothing
    elseif gscr isa GershgorinGSCR
        _validate_uc_gscr_block_template_gershgorin(pm, gscr)
        return nothing
    end
end

function _validate_uc_gscr_block_gscr_formulation_supported(gscr::AbstractGSCRFormulation)
    if gscr isa NoGSCR
        return nothing
    elseif gscr isa GershgorinGSCR
        if !(gscr.exposure isa OnlineNameplateExposure)
            Memento.error(_LOGGER, "Unsupported GershgorinGSCR exposure `$(typeof(gscr.exposure))`.")
        end
        return nothing
    else
        Memento.error(_LOGGER, "Unsupported UC/gSCR block template gSCR formulation `$(typeof(gscr))`.")
    end
end

function _validate_uc_gscr_block_template_gershgorin(pm::_PM.AbstractPowerModel, gscr::GershgorinGSCR)
    for nw in nw_ids(pm)
        if !_has_uc_gscr_block_ref(pm, nw)
            continue
        end
        if !haskey(_PM.ref(pm, nw), :g_min)
            Memento.error(_LOGGER, "UC/gSCR block template validation failed: GershgorinGSCR requires network $(nw) field `g_min`.")
        end
        for key in (:gfl_devices, :gfm_devices, :bus_gfl_devices, :bus_gfm_devices, :gscr_sigma0_gershgorin_margin)
            if !haskey(_PM.ref(pm, nw), key)
                Memento.error(_LOGGER, "UC/gSCR block template validation failed: GershgorinGSCR requires reference map `:$(key)` in network $(nw).")
            end
        end
        for device_key in keys(_PM.ref(pm, nw, :gfl_devices))
            if !haskey(_PM.ref(pm, nw, device_key[1], device_key[2]), "p_block_max")
                Memento.error(_LOGGER, "UC/gSCR block template validation failed: GershgorinGSCR(OnlineNameplateExposure) requires `p_block_max` for GFL device $(device_key).")
            end
        end
        for device_key in keys(_PM.ref(pm, nw, :gfm_devices))
            if !haskey(_PM.ref(pm, nw, device_key[1], device_key[2]), "b_block")
                Memento.error(_LOGGER, "UC/gSCR block template validation failed: GershgorinGSCR(OnlineNameplateExposure) requires `b_block` for GFM device $(device_key).")
            end
        end
    end
end

function _uc_gscr_block_template_device_keys(pm::_PM.AbstractPowerModel, nw::Int)
    if !_has_uc_gscr_block_ref(pm, nw)
        return Tuple{Symbol,Any}[]
    end
    return _uc_gscr_block_device_keys(pm, nw)
end

function _uc_gscr_block_template_device_sets(resolved::Dict{Int,Dict{Tuple{Symbol,Any},AbstractBlockDeviceFormulation}})
    all_keys = Set{Tuple{Symbol,Any}}()
    thermal = Set{Tuple{Symbol,Any}}()
    renewable = Set{Tuple{Symbol,Any}}()
    fixed = Set{Tuple{Symbol,Any}}()
    storage = Set{Tuple{Symbol,Any}}()

    for (_, nw_resolved) in resolved
        union!(all_keys, keys(nw_resolved))
        union!(thermal, _uc_gscr_block_template_keys(nw_resolved, BlockThermalCommitment))
        union!(renewable, _uc_gscr_block_template_keys(nw_resolved, BlockRenewableParticipation))
        union!(fixed, _uc_gscr_block_template_keys(nw_resolved, BlockFixedInstalled))
        union!(storage, _uc_gscr_block_template_keys(nw_resolved, BlockStorageParticipation))
    end

    thermal_keys = _uc_gscr_block_template_sorted(thermal)
    return Dict{Symbol,Vector{Tuple{Symbol,Any}}}(
        :all => _uc_gscr_block_template_sorted(all_keys),
        :thermal_commitment => thermal_keys,
        :renewable_participation => _uc_gscr_block_template_sorted(renewable),
        :fixed_installed => _uc_gscr_block_template_sorted(fixed),
        :storage_participation => _uc_gscr_block_template_sorted(storage),
        :startup_shutdown => copy(thermal_keys),
    )
end

function _uc_gscr_block_template_keys(nw_resolved::Dict{Tuple{Symbol,Any},AbstractBlockDeviceFormulation}, formulation_type)
    keys_for_type = [device_key for (device_key, formulation) in nw_resolved if formulation isa formulation_type]
    sort!(keys_for_type; by=_uc_gscr_block_template_sort_key)
    return keys_for_type
end

function _uc_gscr_block_template_sorted(keys)
    sorted_keys = collect(keys)
    sort!(sorted_keys; by=_uc_gscr_block_template_sort_key)
    return sorted_keys
end

_uc_gscr_block_template_sort_key(device_key::Tuple{Symbol,Any}) = (string(device_key[1]), string(device_key[2]))
