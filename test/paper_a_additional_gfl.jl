using LinearAlgebra

function _additional_gfl_model(f;hours=2)
    d=_ap2_fixture(;hours)
    _FP.scale_paper_a_costs!(d)
    return _ap2_model(d;template=_ap2_template(gscr=f),objective=false,
        defer_paper_a_strength=true,storage_terminal_policy=:fixed_initial)
end

function _additional_gfl_input(pm)
    c=JuMP.@variable(pm.model,[1:2],lower_bound=0.,upper_bound=100.)
    profiles=[0.2 0.8; 0.0 1.0]
    extra=Dict(n=>Dict("R1"=>profiles[n,1]/pm.data["baseMVA"]*c[1],
                      "R2"=>profiles[n,2]/pm.data["baseMVA"]*c[2]) for n in 1:2)
    return c,profiles,extra
end

@testset "Shared G1 equals the accepted direct row attachment" begin
    raw=_ap2_fixture(;hours=2);_FP.scale_paper_a_costs!(raw)
    old=_ap2_model(deepcopy(raw);objective=false,storage_terminal_policy=:fixed_initial)
    new=_additional_gfl_model(_FP.GershgorinGSCR())
    oldc,profiles,_=_additional_gfl_input(old)
    newc,_,extra=_additional_gfl_input(new)
    _FP.finalize_paper_a_strength!(new;additional_gfl=extra)
    canonical(f)=f isa JuMP.GenericAffExpr ? (f.constant,sort([(JuMP.index(v).value,c) for (c,v) in JuMP.linear_terms(f) if c!=0])) : repr(f)
    for n in 1:2,i in 1:2
        region="R$i"
        a=_PM.con(old,n,:gscr_gershgorin_sufficient)[region]
        b=_PM.con(new,n,:gscr_gershgorin_sufficient)[region]
        # Same direct coefficient replacement used by the frozen weekly helper.
        JuMP.set_normalized_coefficient(a,oldc[i],-4*profiles[n,i]/250)
        @test canonical(JuMP.constraint_object(a).func)==canonical(JuMP.constraint_object(b).func)
        @test JuMP.constraint_object(a).set==JuMP.constraint_object(b).set
    end
    for fn in (_FP.calc_uc_gscr_block_investment_cost,_FP.calc_uc_gscr_block_startup_shutdown_cost)
        @test canonical(fn(old))==canonical(fn(new))
    end
    # Physical rows are identical; their construction order can differ because
    # the deferred strength rows are appended only after the new variables.
    physical(pm)=sort([repr((canonical(JuMP.constraint_object(c).func),JuMP.constraint_object(c).set))
        for (F,S) in JuMP.list_of_constraint_types(pm.model) for c in JuMP.all_constraints(pm.model,F,S)
        if !(c in Set(values(_PM.con(pm,1,:gscr_gershgorin_sufficient)))) &&
           !(c in Set(values(_PM.con(pm,2,:gscr_gershgorin_sufficient))))])
    @test physical(old)==physical(new)
end

@testset "Shared added GFL exposure before G1/G2/G3 construction" begin
    for f in (_FP.GershgorinGSCR(),_FP.FixedScalingGSCR([1.5,0.7];provenance="synthetic"),
              _FP.ExactEdgeSOCGSCR())
        pm=_additional_gfl_model(f)
        @test pm.ext[:paper_a_strength_pending]
        @test !haskey(pm.ext,:paper_a_online)
        c,profiles,extra=_additional_gfl_input(pm)
        _FP.finalize_paper_a_strength!(pm;additional_gfl=extra)
        @test !pm.ext[:paper_a_strength_pending]
        for n in 1:2
            x=pm.ext[:paper_a_online][n];alpha=_FP._uc_gscr_g_min(pm,n)
            for i in 1:2,j in 1:2
                coefficient=i==j ? profiles[n,i]/pm.data["baseMVA"] : 0.
                @test JuMP.coefficient(x.p_fl[i],c[j])≈coefficient
                @test JuMP.coefficient(x.p_native[i],c[j])==0
                @test JuMP.coefficient(x.p_new[i],c[j])≈coefficient
                @test JuMP.coefficient(x.B[i,i],c[j])==0
                @test JuMP.coefficient(x.M[i,i],c[j])≈-alpha*coefficient
                @test JuMP.coefficient(x.M[i,3-i],c[j])==0
            end
            if f isa _FP.GershgorinGSCR
                rows=_PM.con(pm,n,:gscr_gershgorin_sufficient)
                for (i,region) in enumerate(x.regions)
                    @test JuMP.coefficient(JuMP.constraint_object(rows[region]).func,c[i])≈
                        -alpha*profiles[n,i]/pm.data["baseMVA"]
                end
            elseif f isa _FP.FixedScalingGSCR
                cert=pm.ext[:paper_a_certificates][n]
                for i in 1:2
                    @test JuMP.coefficient(JuMP.constraint_object(cert.rows[i]).func,c[i])≈
                        -alpha*f.r[i]*profiles[n,i]/pm.data["baseMVA"]
                end
            else
                cert=pm.ext[:paper_a_certificates][n]
                @test cert.edges==[(1,2)]
                @test length(cert.cones)==1
                for i in 1:2
                    @test JuMP.coefficient(cert.residue[i],c[i])≈
                        -alpha*profiles[n,i]/pm.data["baseMVA"]
                end
            end
        end
        @test_throws ArgumentError _FP.finalize_paper_a_strength!(pm;additional_gfl=extra)
    end
end

@testset "Added exposure is availability, independent of curtailed dispatch" begin
    pm=_additional_gfl_model(_FP.GershgorinGSCR())
    c,profiles,extra=_additional_gfl_input(pm)
    _FP.finalize_paper_a_strength!(pm;additional_gfl=extra)
    # Independent finite point: installed MW are nonzero while all dispatch
    # variables are zero. Availability still contributes to strength burden.
    native_values=Dict{JuMP.VariableRef,Float64}()
    for n in 1:2
        native_values[_PM.var(pm,n,:na_block,(:gen,1))]=1.
        native_values[_PM.var(pm,n,:na_block,(:gen,2))]=3.
        native_values[_PM.var(pm,n,:na_block,(:storage,1))]=1.
    end
    atpoint(v)=v==c[1] ? 50. : v==c[2] ? 25. : get(native_values,v,0.)
    for n in 1:2
        x=pm.ext[:paper_a_online][n]
        expected=[0.32+profiles[n,1]*50/250,profiles[n,2]*25/250]
        @test JuMP.value.(Ref(atpoint),x.p_fl)≈expected
        @test JuMP.value.(Ref(atpoint),x.p_native)≈[0.32,0.]
        @test JuMP.value.(Ref(atpoint),x.p_new)≈expected-[0.32,0.]
    end
    x=pm.ext[:paper_a_online][1]
    # Missing added RE would accept this deliberately insufficient source
    # increment; the complete diagonal uses its positive extra burden.
    alpha=_FP._uc_gscr_g_min(pm,1)
    @test alpha*JuMP.value(atpoint,x.p_fl[1])>alpha*JuMP.value(atpoint,x.p_native[1])
    @test JuMP.value(atpoint,x.b_src[2])-alpha*JuMP.value(atpoint,x.p_native[2])==0
    @test JuMP.value(atpoint,x.b_src[2])-alpha*JuMP.value(atpoint,x.p_fl[2])<0
    B=JuMP.value.(Ref(atpoint),x.B);p=JuMP.value.(Ref(atpoint),x.p_fl)
    metrics=_FP.PaperADiagnostics.evaluate(B,p,alpha)
    @test metrics["B.G0"]["value"] && !metrics["B.G1"]["value"]
end

@testset "Independent added-renewable reconstruction uses input profiles" begin
    raw=_ap2_fixture(;hours=2)
    snapshots=Dict{String,Any}()
    for n in 1:2
        sn=raw["nw"][string(n)]
        assets=Dict{String,Any}("$table:$id"=>Dict("installed"=>1.,"online"=>1.,"dispatch_MW"=>0.)
            for table in ("gen","storage","ne_storage") for id in keys(sn[table]))
        snapshots[string(n)]=Dict("assets"=>assets,"renewable_dispatch_MW"=>Dict("new PV"=>0.))
    end
    point=Dict("snapshots"=>snapshots,"renewable_capacity_MW"=>Dict("new PV"=>50.))
    project=Dict("name"=>"new PV","bus"=>"B","carrier"=>"solar","availability"=>[0.2,1.],
        "snapshot_ids"=>[x["snapshot_id"] for x in raw["paper_a_temporal"]])
    for n in 1:2
        old=_FP.PaperADiagnostics.reconstruct(raw,point,n)
        rec=_FP.PaperADiagnostics.reconstruct(raw,point,n;renewable_projects=[project])
        @test rec["B"]==old["B"]
        @test rec["p_native"]==old["p"]
        @test rec["p_new"]≈[0.,project["availability"][n]*50/250]
        @test rec["p"]≈old["p"]+rec["p_new"]
        @test rec["S_op_magnitude_v1"]==old["S_op_magnitude_v1"]
    end
    bad=deepcopy(project);bad["snapshot_ids"]=reverse(bad["snapshot_ids"])
    @test_throws ArgumentError _FP.PaperADiagnostics.reconstruct(raw,point,1;renewable_projects=[bad])
    bad=deepcopy(project);bad["snapshot_ids"][2]=bad["snapshot_ids"][1]
    @test_throws ArgumentError _FP.PaperADiagnostics.reconstruct(raw,point,1;renewable_projects=[bad])
    @test_throws ArgumentError _FP.PaperADiagnostics.reconstruct(raw,point,1;renewable_projects=[project,project])
end

@testset "G2 r=1 is the same G1 row with added RE; M1/M2 receive the same p" begin
    pm=_additional_gfl_model(_FP.FixedScalingGSCR(ones(2);provenance="synthetic"))
    c,profiles,extra=_additional_gfl_input(pm)
    _FP.finalize_paper_a_strength!(pm;additional_gfl=extra)
    for n in 1:2
        g2=pm.ext[:paper_a_certificates][n].rows
        g1=_FP._paper_a_g1!(pm,n)
        for (i,region) in enumerate(pm.ext[:paper_a_online][n].regions)
            a=JuMP.constraint_object(g1[region]);b=JuMP.constraint_object(g2[i])
            @test JuMP.isequal_canonical(a.func-a.set.lower,b.func-b.set.lower)
        end
        x=pm.ext[:paper_a_online][n];alpha=_FP._uc_gscr_g_min(pm,n)
        W=[1. 0.3;0.2 1.]
        m2=_FP.add_paper_a_constraints!(pm.model,x.B,x.p_fl,x.M,
            _FP.InteractionGSCR(W;provenance="synthetic" );alpha)
        minimum_matrix=[12. -10.;-10. 12.]
        m1=_FP.add_paper_a_constraints!(pm.model,x.B,x.p_fl,x.M,
            _FP.InverseBoundGSCR(minimum_matrix;provenance="synthetic");alpha)
        inverse=inv(minimum_matrix)
        for i in 1:2,j in 1:2
            @test JuMP.coefficient(JuMP.constraint_object(m2.rows[i]).func,c[j])≈
                -alpha*W[i,j]*profiles[n,j]/250
            @test JuMP.coefficient(JuMP.constraint_object(m1.rows[i]).func,c[j])≈
                inverse[i,j]*profiles[n,j]/250
        end
    end
end

@testset "Added GFL identities and signs reject before finalization" begin
    for mutation in (:missing_network,:extra_region,:negative,:unbounded,:foreign,:quadratic)
        pm=_additional_gfl_model(_FP.GershgorinGSCR())
        c,profiles,extra=_additional_gfl_input(pm)
        if mutation==:missing_network
            delete!(extra,2)
        elseif mutation==:extra_region
            extra[1]["UNKNOWN"]=extra[1]["R1"]
        elseif mutation==:negative
            extra[1]["R1"]=-c[1]
        elseif mutation==:unbounded
            JuMP.delete_lower_bound(c[1])
        elseif mutation==:foreign
            other=JuMP.Model();v=JuMP.@variable(other,lower_bound=0.)
            extra[1]["R1"]=JuMP.AffExpr(0.)+v
        elseif mutation==:quadratic
            # Widen the value container only for the intentionally invalid input.
            extra=Dict(n=>Dict{String,Any}(v) for (n,v) in extra)
            extra[1]["R1"]=c[1]^2
        end
        before=JuMP.num_constraints(pm.model;count_variable_in_set_constraints=true)
        @test_throws ArgumentError _FP.finalize_paper_a_strength!(pm;additional_gfl=extra)
        @test pm.ext[:paper_a_strength_pending]
        @test !haskey(pm.ext,:paper_a_online)
        @test !haskey(pm.ext,:paper_a_additional_gfl)
        @test JuMP.num_constraints(pm.model;count_variable_in_set_constraints=true)==before
    end
    d=_ap2_fixture();_FP.scale_paper_a_costs!(d)
    @test_throws ArgumentError _ap2_model(d;defer_paper_a_strength=true)
    regular=_ap2_model(d;objective=false)
    @test !get(regular.ext,:paper_a_strength_pending,false)
    @test all(x.p_new===nothing for x in values(regular.ext[:paper_a_online]))
end
