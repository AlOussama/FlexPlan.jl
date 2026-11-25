const _PaperAWRNetwork = Union{_PM.SOCWRPowerModel,_PM.SOCWRConicPowerModel,_PM.QCRMPowerModel}
const _PaperAACNetwork = Union{_PM.LPACCPowerModel,_PaperAWRNetwork}

"""
    paper_a_ac_network(data, model_type, optimizer; template, build_options=(;), kwargs...)

Solve Paper A with LPACC, SOCWR (quadratic or explicit conic form), or QCRM network physics and the strength
formulation selected by the existing UC template. Supply prepared, cost-scaled
multinetwork data. Pass builder options such as `relax_block_variables` via
`build_options`. PowerModels solve options go in `kwargs`.

Each block requires an explicit `terminal_rating_block_MVA` and
`terminal_pq_halfspaces`, a list of dimensionless [a,b,c] rows enforcing
a P + b Q ≤ c Pmax per online block, in grid-injection convention. An empty
list explicitly selects only the block P/Q bounds and MVA circle. Schema-v2
storage q_block bounds use PowerModels' absorption convention. Terminal ratings
are independent of the nameplates used in the strength equivalent.

Set `paper_a_ac_terminal_policy="online_q_box"` to use the explicit
q_block_min/max per online block and fixed-device qmin/qmax without an
apparent-power circle. Branch constraints use the selected PowerModels formulation.
"""
function paper_a_ac_network(data, model_type::Type{<:_PaperAACNetwork}, optimizer;
        template, build_options=(;), kwargs...)
    build = pm -> build_paper_a_ac_network(pm; template, build_options...)
    return _solve_uc_gscr_network(data, model_type, optimizer, build, template; kwargs...)
end

"""Build the opt-in Paper-A P/Q network on an instantiated PowerModels model."""
function build_paper_a_ac_network(pm::_PaperAACNetwork; template, kwargs...)
    _paper_a_enabled(pm.data) || throw(ArgumentError("P/Q integration requires prepared Paper-A data"))
    _build_uc_gscr_network(pm; template, kwargs...)
end

function _validate_paper_a_operational_network(pm::_PM.AbstractActivePowerModel)
    pm isa _PM.AbstractDCPModel || throw(ArgumentError("Paper-A operational integration requires a PowerModels DCP model"))
end

function _validate_paper_a_operational_network(pm::_PaperAACNetwork)
    policy = get(pm.data, "paper_a_ac_terminal_policy", "terminal_polygon_and_circle")
    policy in ("online_q_box", "terminal_polygon_and_circle") || throw(ArgumentError("unknown AC terminal policy $policy"))
    for n in nw_ids(pm)
        for (table, id) in keys(_PM.ref(pm, n, :paper_a_coefficients))
            device = _PM.ref(pm, n, table, id)
            if policy == "online_q_box"
                PaperARegional.number(device, "q_block_min") <= PaperARegional.number(device, "q_block_max") ||
                    throw(ArgumentError("reversed reactive capability for $table $id"))
                continue
            end
            PaperARegional.number(device, "terminal_rating_block_MVA"; positive=true)
            rows = get(device, "terminal_pq_halfspaces", nothing)
            rows isa AbstractVector && all(row -> row isa AbstractVector && length(row) == 3 &&
                all(x -> x isa Real && !(x isa Bool) && isfinite(x), row), rows) ||
                throw(ArgumentError("expected terminal_pq_halfspaces for $table $id at snapshot $n"))
        end
        for table in (:storage, :ne_storage), (id, s) in _PM.ref(pm, n, table)
            all(k -> iszero(s[k]), ("r", "x")) ||
                throw(ArgumentError("P/Q storage requires zero series impedance for $table $id at snapshot $n"))
            haskey(s, "current_rating") &&
                throw(ArgumentError("storage current ratings require a voltage-dependent limit for $table $id"))
            if _is_uc_gscr_block_enabled_device(pm, n, table, id)
                all(k -> iszero(s[k]), ("p_loss", "q_loss")) ||
                    throw(ArgumentError("block storage requires zero fixed terminal losses for $table $id"))
            end
        end
    end
end

_uc_gscr_storage_variables(pm::_PM.AbstractActivePowerModel, n) = _PM.variable_storage_power(pm; nw=n)
_uc_gscr_terminal_capabilities(pm::_PM.AbstractActivePowerModel, n) = nothing
_uc_gscr_fixed_storage_rating(pm::_PM.AbstractPowerModel,n,i) = _PM.constraint_storage_thermal_limit(pm,i;nw=n)
function _uc_gscr_fixed_storage_rating(pm::_PaperAACNetwork,n,i)
    if get(pm.data,"paper_a_ac_terminal_policy",nothing) == "online_q_box"
        d = _PM.ref(pm,n,:storage,i)
        for sym in (:qs,:qsc)
            v = _PM.var(pm,n,sym,i)
            JuMP.set_lower_bound(v,d["qmin"])
            JuMP.set_upper_bound(v,d["qmax"])
        end
    else
        _PM.constraint_storage_thermal_limit(pm,i;nw=n)
    end
end
function _uc_gscr_storage_losses(pm::_PM.AbstractActivePowerModel, n, table, i)
    table == :storage ? _PM.constraint_storage_losses(pm, i; nw=n) : constraint_storage_losses_ne(pm, i; nw=n)
end

function _uc_gscr_storage_variables(pm::_PaperAACNetwork, n)
    # With zero series impedance the storage terminal model needs no current variable.
    for variable in (_PM.variable_storage_power_real, _PM.variable_storage_power_imaginary,
            _PM.variable_storage_power_control_imaginary, _PM.variable_storage_energy,
            _PM.variable_storage_charge, _PM.variable_storage_discharge)
        variable(pm; nw=n)
    end
end

function _uc_gscr_storage_losses(pm::_PaperAACNetwork, n, table, i)
    s = _PM.ref(pm, n, table, i)
    v = _PM.var(pm, n)
    ps, qs, qsc, sc, sd = table == :storage ? (:ps,:qs,:qsc,:sc,:sd) :
        (:ps_ne,:qs_ne,:qsc_ne,:sc_ne,:sd_ne)
    JuMP.@constraint(pm.model, v[ps][i] + v[sd][i] - v[sc][i] == s["p_loss"])
    JuMP.@constraint(pm.model, v[qs][i] == v[qsc][i] + s["q_loss"])
end

function _uc_gscr_terminal_capabilities(pm::_PaperAACNetwork, n)
    for key in _uc_gscr_block_all_device_keys(pm, n)
        table, i = key
        d = _PM.ref(pm, n, table, i)
        na = _PM.var(pm, n, :na_block, key)
        p = _uc_gscr_block_dispatch_variable(pm, n, key, :p)
        q = _uc_gscr_block_dispatch_variable(pm, n, key, :q)
        if table != :gen
            # Per-block dispatch and MVA constraints replace the single-unit Q bounds.
            control = _PM.var(pm, n, table == :storage ? :qsc : :qsc_ne, i)
            for v in (q, control)
                JuMP.has_lower_bound(v) && JuMP.delete_lower_bound(v)
                JuMP.has_upper_bound(v) && JuMP.delete_upper_bound(v)
            end
        end
        get(pm.data,"paper_a_ac_terminal_policy",nothing) == "online_q_box" && continue
        smax = d["terminal_rating_block_MVA"] / pm.data["baseMVA"]
        JuMP.@constraint(pm.model, [smax * na, p, q] in JuMP.SecondOrderCone())
        injection = table == :gen ? 1 : -1
        for (a,b,c) in d["terminal_pq_halfspaces"]
            JuMP.@constraint(pm.model, injection * (a*p + b*q) <= c*d["p_block_max"]*na)
        end
    end
end

_paper_a_shunt_voltage(pm::_PM.LPACCPowerModel, n, i) = 1 + 2*_PM.var(pm, n, :phi, i)
_paper_a_shunt_voltage(pm::_PaperAWRNetwork, n, i) = _PM.var(pm, n, :w, i)

function constraint_uc_gscr_block_bus_active_balance(pm::_PaperAACNetwork; nw::Int=_PM.nw_id_default)
    con = _PM.con(pm, nw)
    haskey(con, :uc_gscr_block_bus_active_balance) && return con[:uc_gscr_block_bus_active_balance]
    r = _PM.ref(pm, nw)
    v = _PM.var(pm, nw)
    for (balance, branch, dc, gen, storage, candidate, demand, shunt, sign) in (
            (:uc_gscr_block_bus_active_balance, :p, :p_dc, :pg, :ps, :ps_ne, "pd", "gs", -1),
            (:uc_gscr_block_bus_reactive_balance, :q, :q_dc, :qg, :qs, :qs_ne, "qd", "bs", 1))
        rows = con[balance] = Dict{Int,JuMP.ConstraintRef}()
        for i in _PM.ids(pm, nw, :bus)
            voltage = _paper_a_shunt_voltage(pm, nw, i)
            rows[i] = JuMP.@constraint(pm.model,
                sum(v[branch][a] for a in r[:bus_arcs][i]) +
                sum(v[dc][a] for a in r[:bus_arcs_dc][i]) ==
                sum(v[gen][g] for g in r[:bus_gens][i]) -
                sum(v[storage][s] for s in r[:bus_storage][i]) -
                sum(v[candidate][s] for s in r[:bus_storage_ne][i]) -
                sum(r[:load][l][demand] for l in r[:bus_loads][i]) +
                sign * sum(r[:shunt][s][shunt] for s in r[:bus_shunts][i]) * voltage)
            if _IM.report_duals(pm)
                _PM.sol(pm, nw, :bus, i)[branch == :p ? :lam_kcl_r : :lam_kcl_i] = rows[i]
            end
        end
    end
    return con[:uc_gscr_block_bus_active_balance]
end
