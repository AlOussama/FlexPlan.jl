"""
    _uc_gscr_block_schema_v2()

Returns the required UC/gSCR block schema-v2 marker for test fixtures.
"""
function _uc_gscr_block_schema_v2()
    return Dict{String,Any}("name" => "uc_gscr_block", "version" => "2.0")
end

"""
    _uc_gscr_add_block_fields!(device, mode; kwargs...)

Adds explicit UC/gSCR schema-v2 block fields to one test device.

The default fixture represents a `test-carrier` thermal-style block device:
GFL unless `mode == "gfm"`, NoGSCR/Gershgorin neutral, no storage energy unless
`e_block` is provided, and startup/shutdown fields present unless disabled.
"""
function _uc_gscr_add_block_fields!(
    device,
    mode;
    carrier="test-carrier",
    n0=1,
    nmax=4,
    na0=n0,
    p_block_min=nothing,
    p_block_max=10.0,
    q_block_min=-2.0,
    q_block_max=2.0,
    b_block=nothing,
    cost_inv_per_mw=1.0,
    lifetime=20.0,
    discount_rate=0.0,
    fixed_om_percent=0.0,
    p_min_pu=0.0,
    p_max_pu=1.0,
    startup_cost_per_mw=1.0,
    shutdown_cost_per_mw=1.0,
    include_startup_shutdown=true,
    e_block=nothing,
    h=nothing,
    s_block=nothing,
)
    device["carrier"] = carrier
    device["grid_control_mode"] = mode
    device["n0"] = n0
    device["nmax"] = nmax
    device["na0"] = na0
    if !isnothing(p_block_min)
        device["p_block_min"] = p_block_min
    end
    device["p_block_max"] = p_block_max
    device["q_block_min"] = q_block_min
    device["q_block_max"] = q_block_max
    device["b_block"] = isnothing(b_block) ? (mode == "gfm" ? 1.0 : 0.0) : b_block
    device["cost_inv_per_mw"] = cost_inv_per_mw
    device["lifetime"] = lifetime
    device["discount_rate"] = discount_rate
    device["fixed_om_percent"] = fixed_om_percent
    device["p_min_pu"] = p_min_pu
    device["p_max_pu"] = p_max_pu
    if include_startup_shutdown
        device["startup_cost_per_mw"] = startup_cost_per_mw
        device["shutdown_cost_per_mw"] = shutdown_cost_per_mw
    else
        delete!(device, "startup_cost_per_mw")
        delete!(device, "shutdown_cost_per_mw")
    end
    if !isnothing(e_block)
        device["e_block"] = e_block
    end
    if !isnothing(h)
        device["H"] = h
    end
    if !isnothing(s_block)
        device["s_block"] = s_block
    end
    return device
end

"""
    _uc_gscr_common_test_template(; gscr=_FP.NoGSCR(), carrier="test-carrier", tables=(:gen, :storage, :ne_storage))

Builds a common UC/gSCR template assigning one formulation to each table/carrier.

By default this is a NoGSCR thermal-commitment template for generator, storage,
and candidate-storage devices with `test-carrier`; pass `gscr=_FP.GershgorinGSCR()`
for tests that require the Gershgorin formulation.
"""
function _uc_gscr_common_test_template(;
    gscr=_FP.NoGSCR(),
    carrier="test-carrier",
    tables=(:gen, :storage, :ne_storage),
    formulation=_FP.BlockThermalCommitment(),
)
    return _FP.UCGSCRBlockTemplate(Dict((table, carrier) => formulation for table in tables), gscr)
end

"""
    _uc_gscr_minimal_gen(id; carrier="test-carrier", mode="gfl", startup=true)

Creates one small schema-v2 generator fixture. It has no storage/ne_storage
record and is suitable for NoGSCR or Gershgorin template-resolution tests.
"""
function _uc_gscr_minimal_gen(id; carrier="test-carrier", mode="gfl", startup=true)
    gen = Dict{String,Any}(
        "index" => id,
        "gen_bus" => 1,
        "gen_status" => 1,
        "pmin" => 0.0,
        "pmax" => 10.0,
        "qmin" => -2.0,
        "qmax" => 2.0,
        "vg" => 1.0,
        "mbase" => 1.0,
        "model" => 2,
        "startup" => 0.0,
        "shutdown" => 0.0,
        "ncost" => 2,
        "cost" => [0.0, 0.0],
    )
    _uc_gscr_add_block_fields!(
        gen,
        mode;
        carrier,
        n0=1,
        nmax=2,
        na0=1,
        p_block_max=10.0,
        q_block_min=-2.0,
        q_block_max=2.0,
        b_block=(mode == "gfm" ? 1.0 : 0.0),
        cost_inv_per_mw=3.0,
        startup_cost_per_mw=1.0,
        shutdown_cost_per_mw=1.0,
        include_startup_shutdown=startup,
    )
    return gen
end
