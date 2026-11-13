const _PAPER_A_CASE_IDENTITY = "sha256_raw_json_bytes_v1"
const _PAPER_A_PROFILE_IDENTITY = "paper_a_profiles_v1"
const _PAPER_A_PROFILE_KEY = "_paper_a_profile_binding"

struct _PaperAProfileBinding
    run_identity::String
    digest::String
end

const _PAPER_A_PROFILE_FIELDS = (
    "bus","branch","dcline","switch","link","shunt","gen","load","storage","ne_storage",
    "baseMVA","per_unit","paper_a_block_units","snapshot_id","time_elapsed",
    "pypsa_snapshot_weight_objective","operation_weight","paper_a_temporal",
    "paper_a_cost_state","paper_a_applied_weights","paper_a_capex_scaled",
    "paper_a_currency_factor","paper_a_investment_fraction_applied",
    "uc_gscr_block_cost_convention","uc_gscr_block_cost_assumptions",
)
const _PAPER_A_PROFILE_ROOT_FIELDS = (
    _PAPER_A_PROFILE_FIELDS...,"snapshot_ids","snapshot_weights","snapshot_elapsed_hours",
    "paper_a_network","paper_a_extension","multinetwork","investment_period_fraction","paper_a_segment_identity",
)

_paper_a_synthetic_case(data) =
    get(get(data,"paper_a_extension",Dict()),"dataset_kind",nothing)=="synthetic_regression_only"
_paper_a_sha256_string(x) = x isa AbstractString && occursin(r"\A[0-9a-f]{64}\z",x)
_paper_a_project(data,fields) = Dict(key=>data[key] for key in fields if haskey(data,key))

function _paper_a_identity_mismatch(message)
    throw(ArgumentError("AP1_PROFILE_CONTENT_IDENTITY_MISMATCH: " * message))
end

function _paper_a_origin_unverified(message)
    throw(ArgumentError("PROFILE_ORIGIN_UNVERIFIED: " * message))
end

# Length-prefixed UTF-8, sorted object keys and typed values. Decimal integers
# and Binary64 bit patterns have distinct tags. Explicit null is allowed;
# missing and non-finite numbers do not describe a qualified profile.
function _paper_a_canonical_write(io,x)
    if x isa AbstractDict
        keys_sorted = collect(keys(x))
        all(k->k isa AbstractString || (k isa Integer && !(k isa Bool)),keys_sorted) ||
            _paper_a_origin_unverified("unsupported profile object key")
        sort!(keys_sorted;by=k->(k isa Integer,string(k)))
        print(io,"d",length(keys_sorted),":")
        for key in keys_sorted
            _paper_a_canonical_write(io,key)
            _paper_a_canonical_write(io,x[key])
        end
    elseif x isa AbstractVector || x isa Tuple
        print(io,"a",length(x),":")
        for item in x
            _paper_a_canonical_write(io,item)
        end
    elseif x isa AbstractString
        print(io,"s",ncodeunits(x),":",x)
    elseif x === nothing
        print(io,"n")
    elseif x isa Bool
        print(io,x ? "t" : "f")
    elseif x isa Integer
        print(io,"i",x,":")
    elseif x isa AbstractFloat
        value = Float64(x)
        isfinite(value) && value==x || _paper_a_origin_unverified("non-finite or unsupported profile number")
        print(io,"b",string(reinterpret(UInt64,value);base=16,pad=16))
    else
        _paper_a_origin_unverified("missing or unsupported profile value of type $(typeof(x))")
    end
end

function _paper_a_canonical_digest(payload)
    io=IOBuffer()
    print(io,_PAPER_A_PROFILE_IDENTITY,":")
    _paper_a_canonical_write(io,payload)
    return bytes2hex(SHA.sha256(take!(io)))
end

"""Compute the versioned AP1 input profile digest for a producer or fixture.

Capture this value before edits and pass it as expected_profile_sha256 to
prepare_paper_a_data!. The projection binds each asset table and its fields
to the enclosing network index and snapshot ID, with units and time weights.
Solver dimensions and gSCR policy are separate run settings.
"""
function paper_a_profile_identity(data::AbstractDict)
    payload = _paper_a_project(data,_PAPER_A_PROFILE_ROOT_FIELDS)
    if get(data,"multinetwork",false)
        payload["nw"] = Dict(id=>_paper_a_project(sn,_PAPER_A_PROFILE_FIELDS) for (id,sn) in data["nw"])
    end
    return _paper_a_canonical_digest(payload)
end

function _paper_a_reference_identity(ref,temporal=get(ref,:paper_a_temporal,nothing))
    temporal isa NamedTuple || _paper_a_identity_mismatch("missing normalized model reference chronology")
    fields=(_PAPER_A_PROFILE_FIELDS...,"dgen","ndgen","storage_bounded_absorption","ne_storage_bounded_absorption")
    payload=Dict{String,Any}(key=>ref[Symbol(key)] for key in fields
        if key!="paper_a_temporal" && haskey(ref,Symbol(key)))
    payload["paper_a_temporal"]=(temporal.snapshot_id,temporal.delta_t_h,temporal.dispatch,temporal.event,temporal.probability)
    return _paper_a_canonical_digest(payload)
end

function _paper_a_profile_binding(data;expected_profile_sha256=nothing,allow_unverified=false)
    binding=get(data,_PAPER_A_PROFILE_KEY,nothing)
    if binding===nothing && expected_profile_sha256===nothing
        allow_unverified || _paper_a_origin_unverified("no expected case or profile identity from the producer run")
        return nothing
    end
    if binding===nothing
        _paper_a_sha256_string(expected_profile_sha256) ||
            _paper_a_origin_unverified("invalid expected profile SHA-256")
        binding=_PaperAProfileBinding("ap1:profile-sha256:" * expected_profile_sha256,expected_profile_sha256)
    else
        binding isa _PaperAProfileBinding || _paper_a_origin_unverified("invalid in-memory profile binding")
        expected_profile_sha256===nothing || _paper_a_origin_unverified("an existing run cannot be rebound")
    end
    actual=paper_a_profile_identity(data)
    actual==binding.digest ||
        _paper_a_identity_mismatch("profile SHA-256 $actual differs from the expected value for $(binding.run_identity)")
    return binding
end

function _paper_a_advance_profile_binding!(data,binding)
    binding===nothing && return
    data[_PAPER_A_PROFILE_KEY]=_PaperAProfileBinding(binding.run_identity,paper_a_profile_identity(data))
    return nothing
end

function _paper_a_validate_case_manifest(data,path,expected)
    isfile(path) || _paper_a_origin_unverified("missing producer case manifest")
    manifest=try
        JSON.parsefile(path)
    catch err
        err isa InterruptException && rethrow()
        _paper_a_origin_unverified("unreadable producer case manifest")
    end
    manifest isa AbstractDict && get(manifest,"schema",nothing)=="paper_a_ap1_manifest_1.0" &&
        get(manifest,"case_content_identity",nothing)==_PAPER_A_CASE_IDENTITY ||
        _paper_a_origin_unverified("unsupported producer case manifest identity version")
    run_identity="ap1:sha256:" * expected
    get(manifest,"case_sha256",nothing)==expected && get(manifest,"case_run_identity",nothing)==run_identity ||
        _paper_a_identity_mismatch("producer case manifest does not match the expected run")
    ids=get(data,"snapshot_ids",nothing)
    selected=get(manifest,"selected_snapshots",nothing)
    ids isa AbstractDict && selected isa AbstractVector && length(ids)==length(selected) &&
        all(i->get(ids,string(i),nothing)==selected[i],eachindex(selected)) ||
        _paper_a_identity_mismatch("producer manifest snapshots do not match the case axis")
    owner=_paper_a_owner_scenario(data)
    if owner!==nothing
        declared=get(manifest,"owner_scenario",nothing)
        declared isa AbstractDict && _paper_a_canonical_digest(owner)==_paper_a_canonical_digest(declared) ||
            _paper_a_identity_mismatch("producer manifest owner scenario does not match the case")
        if haskey(owner,"source_binding")
            source=owner["source_binding"]
            derived=source isa AbstractDict ? get(source,"derived_csv_bundle_sha256",nothing) : nothing
            _paper_a_sha256_string(derived) && get(manifest,"source_dataset_identity_sha256",nothing)==derived ||
                _paper_a_identity_mismatch("producer manifest source CSV identity does not match the owner case")
        end
    end
    return run_identity
end
