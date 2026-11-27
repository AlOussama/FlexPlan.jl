# The weekly optimizer and the postsolve-only reader share the same JuMP model.
function verify_ac_replay_manifest(manifest_path,dir)
    manifest=JSON.parsefile(manifest_path)
    manifest["schema"]=="paper_a_julia_replay_inputs/1" || error("Unsupported Julia replay manifest")
    inputs=manifest["inputs"]
    required=("primal","outcome","audit_terms","terminal_coordinates","case","export_metadata","evaluator_program")
    for role in required
        haskey(inputs,role) || error("Missing expected replay input: $role")
    end
    for (role,entry) in inputs
        path=entry["path"]
        isfile(path) && filesize(path)==entry["bytes"] && sha_file(path)==entry["sha256"] ||
            error("Missing or changed replay input: $role")
    end
    for (role,name) in (("primal","primal.csv"),("outcome","outcome.json"),("audit_terms","audit_terms.csv"),
                        ("terminal_coordinates","terminal_coordinates.csv"),("export_metadata","export.json"))
        abspath(inputs[role]["path"])==abspath(joinpath(dir,name)) || error("Replay input role/path mismatch")
    end
    abspath(inputs["evaluator_program"]["path"])==abspath(@__FILE__) || error("Unbound Julia evaluator program")
    metadata=JSON.parsefile(inputs["export_metadata"]["path"])
    metadata["case_sha256"]==inputs["case"]["sha256"] || error("Replay case identity mismatch")
    return manifest
end

function read_ac_replay_point(path,vars)
    expected=Set(JuMP.index(v).value for v in vars)
    points=fill(NaN,maximum(expected))
    seen=Set{Int}()
    for row in CSV.File(path)
        row.index in expected && !(row.index in seen) && isfinite(row.value) ||
            error("Duplicate, unknown or nonfinite primal coordinate")
        push!(seen,row.index)
        points[row.index]=row.value
    end
    seen==expected || error("Incomplete primal coordinate roster")
    return points
end

function replay_ac_week(dir, model)
    manifest_path=get(ENV,"PAPER_A_AC_REPLAY_MANIFEST","")
    output=get(ENV,"PAPER_A_AC_REPLAY_OUTPUT","")
    isempty(manifest_path) && error("Replay requires explicit expected PAPER_A_AC_REPLAY_MANIFEST")
    isempty(output) && error("Replay requires separate PAPER_A_AC_REPLAY_OUTPUT")
    abspath(output)!=abspath(dir) && !ispath(output) || error("Replay output must be a new separate directory")
    manifest=verify_ac_replay_manifest(manifest_path,dir)
    path = joinpath(dir,"primal.csv")
    vars = JuMP.all_variables(model.m)
    points = read_ac_replay_point(path,vars)
    evalpoint(v) = points[JuMP.index(v).value]
    val(x) = JuMP.value(evalpoint,x)
    result = JSON.parsefile(joinpath(dir,"outcome.json"))
    isapprox(val(model.objective),result["annualized_EUR2025"];rtol=2e-12) ||
        error("Rebuilt primal coordinates fail archived objective check")
    verify_ac_replay_manifest(manifest_path,dir)
    mkpath(output)
    for name in ("primal.csv","outcome.json","audit_terms.csv","terminal_coordinates.csv","export.json")
        cp(joinpath(dir,name),joinpath(output,name))
    end
    audit_ac_point(output,model,val)
    verify_ac_replay_manifest(manifest_path,dir)
    writejson(joinpath(output,"input_binding.json"),Dict("input_manifest_sha256"=>sha_file(manifest_path),
        "schema"=>manifest["schema"],"gold_qualified"=>false))
end

function export_ac_coordinates(dir, model)
    (;m,pm,w,new_q,objective) = model
    # Independent readers can match the primal vector to source case IDs and
    # repeat the sparse EUR, quota, G2 and nodal residual calculations.
    open(joinpath(dir,"audit_terms.csv"),"w") do io
        println(io,"metric,hour,id,index,coefficient")
        function terms(metric,h,id,expr)
            println(io,metric,",",h,",",id,",0,",JuMP.constant(expr))
            for (coef,v) in JuMP.linear_terms(expr)
                println(io,metric,",",h,",",id,",",JuMP.index(v).value,",",coef)
            end
        end
        terms("cost",0,0,objective)
        terms("wind_pv",0,0,w.quota)
        for n in 1:168
            for (kind,sym) in (("P",:uc_gscr_block_bus_active_balance),
                               ("Q",:uc_gscr_block_bus_reactive_balance))
                for (id,row) in fp.con(pm,n,sym)
                    terms(kind,n,id,JuMP.constraint_object(row).func-JuMP.normalized_rhs(row))
                end
            end
            cert=pm.ext[:paper_a_certificates][n]
            if cert.kind=="G2"
                for (i,row) in enumerate(cert.rows)
                    terms("G2",n,i,JuMP.constraint_object(row).func-JuMP.normalized_rhs(row))
                end
            else
                M=FP._paper_a_online_expressions!(pm,n).M
                for i in axes(M,1), j in i:size(M,2)
                    terms("M",n,string(i,"_",j),JuMP.AffExpr(0.)+M[i,j])
                end
            end
        end
    end
    index(v) = JuMP.index(v).value
    open(joinpath(dir,"terminal_coordinates.csv"),"w") do io
        println(io,"type,hour,id,end_bus,p_index,q_index,online_index,q_factor_pu,rating_pu")
        for n in 1:168
            for (i,b) in fp.ref(pm,n,:branch), (f,t) in ((b["f_bus"],b["t_bus"]),(b["t_bus"],b["f_bus"]))
                arc=(i,f,t)
                println(io,"branch,",n,",",i,",",f,",",index(fp.var(pm,n,:p,arc)),",",index(fp.var(pm,n,:q,arc)),",0,0,",b["rate_a"])
            end
            for (i,b) in fp.ref(pm,n,:dcline), (f,t,k) in ((b["f_bus"],b["t_bus"],"qmaxf"),(b["t_bus"],b["f_bus"],"qmaxt"))
                arc=(i,f,t)
                println(io,"dcline,",n,",",i,",",f,",",index(fp.var(pm,n,:p_dc,arc)),",",index(fp.var(pm,n,:q_dc,arc)),",0,",b[k],",0")
            end
            for key in FP._uc_gscr_block_all_device_keys(pm,n)
                q = FP._uc_gscr_block_dispatch_variable(pm,n,key,:q)
                p = FP._uc_gscr_block_dispatch_variable(pm,n,key,:p)
                println(io,key[1],",",n,",",key[2],",0,",index(p),",",index(q),",",index(fp.var(pm,n,:na_block,key)),",",fp.ref(pm,n,key...)["q_block_max"],",0")
            end
            for (i,s) in fp.ref(pm,n,:storage)
                haskey(s,"source_class") && continue
                println(io,"fixed_hydro,",n,",",i,",0,",index(fp.var(pm,n,:ps,i)),",",index(fp.var(pm,n,:qs,i)),",0,",s["qmax"],",0")
            end
            for p in w.projects
                println(io,"added,",n,",",p.name,",0,",index(p.gen[n]),",",index(new_q[(n,p.name)]),",",index(p.installed),",",qratio/w.base,",0")
            end
        end
    end
end

"""Capture the original row roster before any solver-only transformation."""
function freeze_ac_original_model(m)
    rows=JuMP.all_constraints(m;include_variable_in_set_constraints=true)
    snapshot = (model=m, rows=rows, rowset=Set(rows),
                preserved=Dict{Any,Any}())
    m.ext[:paper_a_original_audit] = snapshot
    return snapshot
end

"""Preserve a row before changing its coefficients or deleting it."""
function preserve_ac_original_constraint!(snapshot, row)
    row in snapshot.rowset || error("Cannot preserve a non-original row")
    get!(snapshot.preserved,row) do
        obj=JuMP.constraint_object(row)
        f=obj.func isa AbstractVector ? copy.(obj.func) : copy(obj.func)
        (func=f,set=obj.set)
    end
    snapshot.model.ext[:paper_a_solver_transformed] = true
    return nothing
end

function original_ac_distances(snapshot,val;atol=1e-8)
    violated=Dict{Any,Float64}()
    for row in snapshot.rows
        obj = if haskey(snapshot.preserved,row)
            snapshot.preserved[row]
        else
            JuMP.is_valid(snapshot.model,row) || error("Original row deleted without preservation")
            JuMP.constraint_object(row)
        end
        x=obj.func isa AbstractVector ? val.(obj.func) : val(obj.func)
        all(isfinite,x isa Number ? (x,) : x) || error("Nonfinite original row value")
        d=JuMP.MOI.Utilities.distance_to_set(x,obj.set)
        isfinite(d) || error("Nonfinite original row distance")
        d>atol && (violated[row]=d)
    end
    return violated
end

function audit_ac_point(dir, model, val; original_snapshot=get(model.m.ext,:paper_a_original_audit,nothing))
    (;m,w,objective) = model
    if !isfile(joinpath(dir,"export.json")) && !isfile(joinpath(dir,"start_receipt.json"))
        export_ac_coordinates(dir,model)
    end
    native = JuMP.primal_feasibility_report(v->val(v),m;atol=1e-8)
    writejson(joinpath(dir,"native_solver_audit.json"),Dict(
        "audit_role"=>"solver representation only", "gold_qualified"=>false,
        "max_distance_above_1e-8"=>isempty(native) ? 0.0 : maximum(values(native)),
        "constraints_above_1e-8"=>length(native)))
    transformed=get(m.ext,:paper_a_solver_transformed,false)
    transformed && isnothing(original_snapshot) && error("Original audit requires pre-transformation snapshot")
    violated = isnothing(original_snapshot) ? native : original_ac_distances(original_snapshot,val)
    worst = isempty(violated) ? 0.0 : maximum(values(violated))
    if criterion in ("G0","G3")
        hourly=[FP.eigmin(FP.Symmetric(val.(FP._paper_a_online_expressions!(model.pm,n).M))) for n in 1:168]
        writejson(joinpath(dir,"original_strength_eigenvalues.json"),Dict(
            "criterion"=>criterion,"minimum_eigenvalues"=>hourly,"minimum"=>minimum(hourly),
            "primal_sha256"=>sha_file(joinpath(dir,"primal.csv"))))
    end
    check=Dict(
        "audit_role"=>"original unscaled JuMP algebra; independent bound native replay required",
        "gold_qualified"=>false,"solver_transformed"=>transformed,
        "original_rows"=>isnothing(original_snapshot) ? JuMP.num_constraints(m;count_variable_in_set_constraints=true) : length(original_snapshot.rows),
        "max_distance_above_1e-8"=>worst,"constraints_above_1e-8"=>length(violated),
        "cost_EUR2025"=>val(objective),"wind_pv_MWh"=>val(w.quota),"demand_MWh"=>w.demand,
        "primal_sha256"=>sha_file(joinpath(dir,"primal.csv")),
        "audit_terms_sha256"=>sha_file(joinpath(dir,"audit_terms.csv")),
        "terminal_coordinates_sha256"=>sha_file(joinpath(dir,"terminal_coordinates.csv")))
    writejson(joinpath(dir,"original_model_audit.json"),check)
    writejson(joinpath(dir,"original_model_check.json"),check)
end

# Transfer terminal dispatch and online/capacity coordinates by case ID. The
# target formulation's other variables retain the PowerModels starting values.
function set_ac_terminal_starts!(dir, model, source, case_sha)
    result = JSON.parsefile(joinpath(source,"outcome.json"))
    check = JSON.parsefile(joinpath(source,"original_model_check.json"))
    result["result_count"] > 0 && result["case_sha256"] == case_sha || error("Unrelated starting point")
    for file in ("primal","terminal_coordinates")
        sha_file(joinpath(source,file*".csv")) == check[file*"_sha256"] || error("Starting point changed")
    end
    export_ac_coordinates(dir,model)
    point = Dict(r.index=>r.value for r in CSV.File(joinpath(source,"primal.csv")))
    fields = (:p_index,:q_index,:online_index)
    table = "terminal_coordinates.csv"
    rows(path) = CSV.File(joinpath(path,table);types=Dict(:id=>String,:type=>String))
    key(r) = (r.type,r.hour,r.id,r.end_bus)
    original = Dict(key(r)=>Tuple(getproperty(r,k) for k in fields) for r in rows(source))
    starts = Dict{Int,Float64}()
    target_rows = 0
    for r in rows(dir)
        indexes = original[key(r)]
        target_rows += 1
        for (j,k) in enumerate(fields)
            old, new = indexes[j], getproperty(r,k)
            iszero(old) == iszero(new) || error("Terminal coordinate mismatch")
            iszero(old) && continue
            x = point[old]
            isfinite(x) && get!(starts,new,x) == x || error("Inconsistent or nonfinite start")
        end
    end
    length(original) == target_rows || error("Different terminal rosters")
    for (i,x) in starts
        JuMP.set_start_value(JuMP.VariableRef(model.m,JuMP.MOI.VariableIndex(i)),x)
    end
    writejson(joinpath(dir,"start_receipt.json"),Dict("case_sha256"=>case_sha,
        "source"=>basename(source),"source_primal_sha256"=>check["primal_sha256"],
        "terminal_rows"=>target_rows,"variables_with_terminal_starts"=>length(starts)))
end
