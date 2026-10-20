using JuMP, LinearAlgebra, Test
import FlexPlan as FP, Clarabel, HiGHS, Pajarito, Gurobi, JSON, SHA
const MOI=JuMP.MOI
const OUT=abspath(ARGS[1])
mkpath(OUT)
writejson(n,x)=open(io->JSON.print(io,x,2),joinpath(OUT,n),"w")
rows(A)=[collect(A[i,:]) for i in axes(A,1)]
results=Any[]
cases=[("G0_not_M0",[1. -.5;-.5 1.],[.25,2/3]),("new_positive",[3.4 -.4;-.4 2.2],[.3,.35]),("laplacian_zero_row",[1. -1 0;-1 1 0;0 0 0],zeros(3)),("non_Z_PSD",ones(3,3),zeros(3)),("indefinite",[1. -.5;-.5 1.],[.75,.75])]
@testset "Independent actual JuMP/MOI cones" begin
for (id,B,p) in cases,kind in ("G0","G3")
    M=B-Diagonal(p);model=Model(Clarabel.Optimizer);set_silent(model)
    set_optimizer_attribute(model,"tol_feas",1e-10);set_optimizer_attribute(model,"tol_gap_abs",1e-10)
    # Attempt01 records Clarabel compact-chordal failure on constant singular PSD.
    # Disable decomposition for this independent boundary replay only.
    set_optimizer_attribute(model,"chordal_decomposition_enable",false)
    f=kind=="G0" ? FP.ExactPSDGSCR() : FP.ExactEdgeSOCGSCR()
    c=FP.add_paper_a_constraints!(model,B,p,M,f;alpha=1.)
    @objective(model,Min,0.)
    optimize!(model);status=string(termination_status(model));feasible=primal_status(model)==MOI.FEASIBLE_POINT
    d=Dict{String,Any}("id"=>id,"kind"=>kind,"termination"=>status,"eigmin"=>eigmin(Symmetric(M)),"B"=>rows(B),"p"=>p,"constraints"=>[string(F)*" in "*string(S)=>num_constraints(model,F,S) for (F,S) in list_of_constraint_types(model)])
    expected=eigmin(Symmetric(M))>=-1e-10 && !(id=="non_Z_PSD" && kind=="G3")
    @test feasible==expected
    if feasible
        report=primal_feasibility_report(model;atol=0.);d["full_primal_violation"]=maximum(values(report);init=0.)
        d["dual_status"]=string(dual_status(model));d["dual_objective"]=dual_objective_value(model)
        @test d["full_primal_violation"]<1e-7
        if kind=="G3"
            expectededges=[(i,j) for i in axes(M,1) for j in i+1:size(M,1) if M[i,j]!=0]
            @test c.edges==expectededges
            R=zeros(size(M));used=zeros(size(M,1));products=Float64[];cones=Any[];dualerr=0.;complement=0.
            for (k,(i,j)) in enumerate(c.edges)
                u,v=value.(c.q[k,:]);cv=constraint_object(c.cones[k]); vals=value.(cv.func)
                @test cv.set==MOI.RotatedSecondOrderCone(3)
                @test vals≈[u,v,sqrt(2.)*M[i,j]] atol=1e-12
                @test coefficient(cv.func[1],c.q[k,1])==1 && coefficient(cv.func[2],c.q[k,2])==1
                z=dual(c.cones[k]);dualerr=max(dualerr,-z[1],-z[2],z[3]^2-2z[1]*z[2]);complement=max(complement,abs(dot(vals,z)))
                push!(products,u*v-M[i,j]^2);used[i]+=u;used[j]+=v;R[i,i]+=u;R[j,j]+=v;R[i,j]+=M[i,j];R[j,i]+=M[i,j]
                push!(cones,Dict("edge"=>[i,j],"function"=>string(cv.func),"MOI_set"=>string(cv.set),"primal"=>vals,"dual"=>z))
            end
            residue=diag(M)-used;R+=Diagonal(residue)
            d["cones"]=cones;d["reconstruction_residual"]=maximum(abs.(R-M));d["node_residue"]=residue;d["product_slacks"]=products;d["dual_cone_violation"]=dualerr;d["complementarity"]=complement
            @test minimum(residue)>=-1e-7 && minimum(products;init=0.)>=-1e-7 && d["reconstruction_residual"]<1e-12
        end
    end
    write_to_file(model,joinpath(OUT,"moi_$(id)_$(kind).mof.json"));push!(results,d)
end
# Mutation checks use an independently assembled rank-one boundary witness.
M=[.75 -.5;-.5 1/3];q=[.75,1/3]
@test q[1]*q[2]≈M[1,2]^2
@test q[1]*q[2]-(2M[1,2])^2<0 # wrong RSOC multiplier
@test maximum(abs.(Diagonal(diag(M))-M))==.5 # lost edge
@test minimum(diag(M)-2q)<0 # duplicated edge budgets
@test eigmin(Symmetric([0. -.5;-.5 0.]))<0 # missing diagonal residual admits indefinite M
@test norm(M-[.75 .5;.5 1/3],Inf)==1. # signed reconstruction
@test FP.PaperADiagnostics.finite_spectrum([2. 0;0 -1.],[1.,0.])["status"]=="domain_invalid_zero_block"
@test FP.PaperADiagnostics.finite_spectrum([1. 1;1 0.],[1.,0.])["status"]=="domain_invalid_range_condition"
@test FP.PaperADiagnostics.finite_spectrum(zeros(2,2),zeros(2))["gamma"]===nothing
@test FP.PaperADiagnostics.finite_spectrum([2. 0;0 0.],[1.,0.])["gamma"]==2.
end
writejson("independent_moi_results.json",results)
env=Dict{String,Any}("Julia"=>string(VERSION),"CPU"=>Sys.CPU_NAME,"logical_threads"=>Sys.CPU_THREADS,"julia_threads"=>Threads.nthreads(),"BLAS"=>string(BLAS.get_config()))
try
    model=Model(Gurobi.Optimizer);@variable(model,x,Bin);@objective(model,Min,x);optimize!(model)
    env["Gurobi"]=string(termination_status(model))
catch e
    env["Gurobi"]=sprint(showerror,e)
end
writejson("runtime_capabilities.json",env)
println("Independent MOI audit completed")
