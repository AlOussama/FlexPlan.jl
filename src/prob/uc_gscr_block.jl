# Problem definition for block UC / gSCR (Task 05)
#
# Implements uc_gscr_block, an LP/MILP-compatible problem that couples:
#   - block expansion variables (n, na) for gen devices
#   - active-power dispatch bounds scaled by na
#   - reactive-power dispatch bounds (no-op for active-power-only formulations)
#   - Gershgorin-sufficient per-bus gSCR constraints

"""
    uc_gscr_block(data, model_type, optimizer; relax, kwargs...)

Solve the block unit-commitment / gSCR sufficient condition problem.

This problem:
1. Declares the installed block variable `n_block` (shared across snapshots).
2. Declares the active block variable `na_block` (per snapshot).
3. Adds active-power and reactive-power dispatch bounds scaled by `na_block`.
4. Enforces the per-bus Gershgorin sufficient gSCR condition.

The network data must contain block fields on gen entries (`n0`, `nmax`,
`p_block_min`, `p_block_max`, `q_block_min`, `q_block_max`, `b_block`) and
the case-level scalar `g_min`.

Cases without block fields are supported: the new constraints are simply absent.

# Arguments
- `data`       : multinetwork data dictionary (already expanded by `make_multinetwork`)
- `model_type` : a PowerModels formulation type
- `optimizer`  : JuMP-compatible solver
- `relax`      : if `true` (default) use continuous variables; `false` for integer
"""
function uc_gscr_block(data::Dict{String,Any}, model_type::Type,
                       optimizer; relax::Bool = true, kwargs...)
    return _PM.solve_model(
        data, model_type, optimizer, build_uc_gscr_block;
        ref_extensions = [ref_add_gen!, ref_add_gscr_block!],
        solution_processors = [_PM.sol_data_model!],
        multinetwork = true,
        setting = Dict("relax" => relax),
        kwargs...
    )
end

"""
    build_uc_gscr_block(pm; relax)

Build function for the `uc_gscr_block` problem.

Declares variables and constraints for every multinetwork snapshot.

The `relax` setting is read from `pm.setting["relax"]` (default `true`).
"""
function build_uc_gscr_block(pm::_PM.AbstractPowerModel)
    relax = get(pm.setting, "relax", true)

    for n in nw_ids(pm)
        # Power system variables (PowerModels standard)
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)

        # Block variables (FlexPlan extension)
        variable_block_installed(pm; nw = n, relax = relax)
        variable_block_active(pm; nw = n, relax = relax)
    end

    for n in nw_ids(pm)
        # Power flow constraints
        _PM.constraint_model_voltage(pm; nw = n)
        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :bus)
            _PM.constraint_power_balance(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        # Block dispatch constraints
        nw_ref = _PM.ref(pm, n)
        block_ids = [k for (k, gen) in nw_ref[:gen]
                     if haskey(gen, "n0") && haskey(gen, "nmax")]

        for k in block_ids
            constraint_block_active_power_dispatch(pm, k; nw = n)
            constraint_block_reactive_power_dispatch(pm, k; nw = n)
        end

        # gSCR Gershgorin constraint (only if g_min is present)
        if haskey(nw_ref, :g_min)
            for i in _PM.ids(pm, n, :bus)
                constraint_gscr_gershgorin_sufficient(pm, i; nw = n)
            end
        end
    end
end
