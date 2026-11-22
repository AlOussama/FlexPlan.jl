module WeekPortfolioStart
using JuMP
import Gurobi
const MOI = JuMP.MOI

"""Apply portfolio-only MIP hints from the accepted LP, subject to original capacity bounds."""
function capacity_start!(model, blocks, projects, expansion_rows, seed)
    Set(keys(blocks)) == Set(keys(seed["installed_blocks"])) || error("Block hint roster mismatch")
    Set(keys(projects)) == Set(keys(seed["renewable_capacity"])) || error("Renewable hint roster mismatch")
    function bounded(v, x)
        lo, hi = lower_bound(v), upper_bound(v)
        isfinite(x) && lo - 1e-6 <= x <= hi + 1e-6 || error("LP capacity outside original bounds")
        return clamp(x, lo, hi)
    end
    upper = Dict{VariableRef,Float64}()
    lower = Dict{VariableRef,Float64}()
    for (key, v) in blocks
        x = bounded(v, seed["installed_blocks"][key])
        snapped = abs(x - round(x)) <= 1e-7 ? round(x) : x
        upper[v], lower[v] = ceil(snapped), floor(snapped)
    end
    function fits(candidate)
        return all(expansion_rows) do row
            c = constraint_object(row)
            c.set isa MOI.LessThan && value(v -> candidate[v], c.func) <= c.set.upper + 1e-7
        end
    end
    fits(lower) || error("Floored LP portfolio exceeds an expansion ceiling")
    use_ceiling = fits(upper)
    selected = use_ceiling ? upper : lower
    starts = Dict(v => x for (v,x) in selected if upper_bound(v) > lower_bound(v))
    for (name, v) in projects
        starts[v] = bounded(v, seed["renewable_capacity"][name])
    end
    cleared = 0
    for v in all_variables(model)
        if start_value(v) !== nothing
            set_start_value(v, nothing)
            cleared += 1
        end
    end
    for (v,x) in starts
        set_start_value(v, x)
    end
    return (; starts, use_ceiling, cleared)
end

"""Read the single Gurobi MIP start on every original column after optimizer attachment."""
function verify_capacity_start(native, starts)
    Gurobi.GRBupdatemodel(native) == 0 || error("Cannot refresh native model")
    start_count = Ref{Cint}(-1)
    start_number = Ref{Cint}(-1)
    Gurobi.GRBgetintattr(native, "NumStart", start_count) == 0 || error("Cannot read number of MIP starts")
    Gurobi.GRBgetintparam(Gurobi.GRBgetenv(native), "StartNumber", start_number) == 0 || error("Cannot read selected MIP start")
    start_count[] == 1 && start_number[] == 0 || error("Expected only the first native MIP start")
    n = Ref{Cint}(0)
    Gurobi.GRBgetintattr(native, "NumVars", n) == 0 || error("Cannot read native columns")
    values = zeros(n[])
    Gurobi.GRBgetdblattrarray(native, "Start", 0, n[], values) == 0 || error("Cannot read native MIP start")
    expected = fill(Float64(Gurobi.GRB_UNDEFINED), n[])
    for (v,x) in starts
        j = Int(Gurobi.c_column(native, optimizer_index(v))) + 1
        expected[j] = x
    end
    values == expected || error("Native portfolio MIP start differs from declared columns")
    return length(starts)
end

end
