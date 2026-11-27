using Test, JuMP, LinearAlgebra
import FlexPlan as FP, MosekTools, Gurobi, JSON
include("../scripts/paper_a/NativeG3Solver.jl")

"Evaluate the stored finite SOC as exact binary rationals, without a solve."
function exact_g3_point(B,qvalues)
    m=Model()
    cert=FP.add_paper_a_constraints!(m,B,zeros(size(B,1)),B,FP.ExactEdgeSOCGSCR();alpha=1.)
    point=Dict(cert.q[k,j]=>Rational{BigInt}(qvalues[k,j]) for k in axes(qvalues,1),j in 1:2)
    eval(z)=z isa Real ? Rational{BigInt}(z) : z isa VariableRef ? point[z] :
        Rational{BigInt}(z.constant)+sum(Rational{BigInt}(a)*point[v] for (a,v) in linear_terms(z);init=big(0)//big(1))
    valid=all(>=(0),values(point))
    for (k,(i,j)) in enumerate(cert.edges)
        object=constraint_object(cert.cones[k]);@test object.set isa MOI.SecondOrderCone
        y=eval.(object.func)
        @test y==[point[cert.q[k,1]]+point[cert.q[k,2]],point[cert.q[k,1]]-point[cert.q[k,2]],2Rational{BigInt}(B[i,j])]
        @test y[1]^2-y[2]^2-y[3]^2==4*(point[cert.q[k,1]]*point[cert.q[k,2]]-Rational{BigInt}(B[i,j])^2)
        valid &= y[1]>=0 && y[1]^2>=sum(abs2,y[2:end])
    end
    valid &= all(eval(r)>=0 for r in cert.residue)
    return valid,m,cert
end

@testset "G3 exact finite SOC and boundary fixtures" begin
    for B in ([2. -1.;-1. 2.],[1. -1.;-1. 1.],[1. -1. 0.;-1. 1. 0.;0. 0. 0.])
        @test first(exact_g3_point(B,reshape([1.,1.],1,2)))
    end
    @test first(exact_g3_point(zeros(2,2),zeros(0,2))) # isolated components
    @test !first(exact_g3_point([1. -1.;-1. 1.],reshape([1.,prevfloat(1.)],1,2)))
    @test !first(exact_g3_point([1. -1.;-1. 1.],reshape([-1.,-1.],1,2)))
    # The archived sqrt(2) rotation under-represents this exact product.
    a=big(1592262918131443)//big(2251799813685248)
    @test 2a^2<1
    @test (big(3)//big(4)+big(3)//big(4))^2>=1 # faulty un-doubled tail would pass
    @test !first(exact_g3_point([1. -1.;-1. 1.],reshape([0.75,0.75],1,2)))
    @test !first(exact_g3_point([1. -1.;-1. Float64(2a^2)],reshape([1.,Float64(2a^2)],1,2)))
    valid,m,c=exact_g3_point([1. -0.3;-0.3 1.],reshape([1.,1.],1,2))
    @test valid
    @test constraint_object(only(c.cones)).func[3].constant==2*(-0.3)
end

@testset "G3 common finite SOC native small solves" begin
    for solver in (:gurobi,:mosek)
        m=Model();@variable(m,x>=0)
        B=[0.3+x -0.3;-0.3 0.3]
        cert=FP.add_paper_a_constraints!(m,B,zeros(2),B,FP.ExactEdgeSOCGSCR();alpha=1.)
        @objective(m,Min,x)
        opt=NativeG3Solver.optimizer(;backend=solver)
        set_optimizer(m,opt);set_silent(m)
        solver==:gurobi && set_optimizer_attribute(m,"BarQCPConvTol",1e-10)
        NativeG3Solver.configure_bridges!(m,opt)
        info=NativeG3Solver.prepare_backend!(m,opt)
        if solver==:gurobi
            @test info["cones"]==1
            native=unsafe_backend(m)
            ci=only(MOI.get(native,MOI.ListOfConstraintIndices{MOI.VectorOfVariables,MOI.SecondOrderCone}()))
            variables=MOI.get(native,MOI.ConstraintFunction(),ci).variables
            @test length(variables)==3
            @test Gurobi.GRBupdatemodel(native)==0
            nl=Ref{Cint}(0);nq=Ref{Cint}(0)
            @test Gurobi.GRBgetqconstr(native,0,nl,C_NULL,C_NULL,nq,C_NULL,C_NULL,C_NULL)==0
            li=zeros(Cint,nl[]);lv=zeros(nl[]);qi=zeros(Cint,nq[]);qj=zeros(Cint,nq[]);qv=zeros(nq[])
            @test Gurobi.GRBgetqconstr(native,0,nl,li,lv,nq,qi,qj,qv)==0
            @test nl[]==0 && nq[]==3 && qi==qj
            @test sort(qv)==[-1.,-1.,1.]
            columns=Int.(Gurobi.c_column.(Ref(native),variables))
            @test Dict(Int(i)=>v for (i,v) in zip(qi,qv))==Dict(columns[1]=>1.,columns[2]=>-1.,columns[3]=>-1.)
            head=Int(Gurobi.c_column(native,first(variables)))
            lb=Ref{Cdouble}(NaN)
            @test Gurobi.GRBgetdblattrelement(native,"LB",head,lb)==0
            @test lb[]==0.
        end
        if haskey(ENV,"R3_G3_TEST_OUTPUT")
            dir=joinpath(ENV["R3_G3_TEST_OUTPUT"],string(solver));mkpath(dir)
            readback=NativeG3Solver.native_certificate_readback!(dir,m,Dict(1=>cert))
            @test readback["status"]=="PASS" && readback["native_cones_exact"]==1 && readback["native_node_rows_exact"]==2
            if solver==:gurobi
                native=unsafe_backend(m)
                raw=JSON.parsefile(joinpath(dir,"g3_actual_native_readback.json"))
                tail=only(readback["native_coordinate_ledger"])["native_coordinate_columns_zero_based"][3]
                row=only(r for r in raw["linear_rows"] if r["sense"]=="=" && r["columns_zero_based"]==[tail])
                @test Gurobi.GRBsetdblattrelement(native,"RHS",row["index_zero_based"],prevfloat(row["rhs"]))==0
                @test_throws ErrorException NativeG3Solver.native_certificate_readback!(dir,m,Dict(1=>cert))
                @test Gurobi.GRBsetdblattrelement(native,"RHS",row["index_zero_based"],row["rhs"])==0
                qcol=Int(Gurobi.c_column(native,optimizer_index(cert.q[1,1])))
                @test Gurobi.GRBsetdblattrelement(native,"LB",qcol,-1.)==0
                @test_throws ErrorException NativeG3Solver.native_certificate_readback!(dir,m,Dict(1=>cert))
                @test Gurobi.GRBsetdblattrelement(native,"LB",qcol,0.)==0
                @test Gurobi.GRBsetdblattrelement(native,"LB",qcol,1.)==0
                @test_throws ErrorException NativeG3Solver.native_certificate_readback!(dir,m,Dict(1=>cert))
                @test Gurobi.GRBsetdblattrelement(native,"LB",qcol,0.)==0
                @test Gurobi.GRBsetdblattrelement(native,"UB",qcol,1.)==0
                @test_throws ErrorException NativeG3Solver.native_certificate_readback!(dir,m,Dict(1=>cert))
                @test Gurobi.GRBsetdblattrelement(native,"UB",qcol,Gurobi.GRB_INFINITY)==0
            end
        end
        optimize!(m)
        @test termination_status(m)==MOI.OPTIMAL
        @test abs(value(x))<1e-7
        @test NativeG3Solver.primal_check(m)["status"]=="passed"
        @test all(value(v)>=-1e-7 for v in cert.q)
    end
end
