module PaperADiagnostics
using LinearAlgebra
import SHA, JSON

const SCHEMA="paper_a_ap3/1.0"
const DEFAULT_TOL=1e-7
matrix(x)=x isa AbstractMatrix ? Matrix{Float64}(x) : reduce(vcat,permutedims.(Float64.(v) for v in x))
rows(A::AbstractMatrix)=[collect(A[i,:]) for i in axes(A,1)]
hashfile(path)=bytes2hex(SHA.sha256(read(path)))
entry(value;status="valid",unit="pu",method="independent_linear_algebra",theorem="T-C2A-001:028",residual=nothing)=Dict{String,Any}("value"=>value,"status"=>status,"unit"=>unit,"method"=>method,"theorem"=>theorem,"residual"=>residual)
undefined(reason)=entry(nothing;status=reason)

"""Independent physical stamp and passive elimination. Uses original AP1
primitives and physical native source bases, never AP2 coefficients or B caches.
The importer remains responsible for inventory/qualification acceptance.
"""
function reconstruct(raw,solution,t;tol=DEFAULT_TOL)
    net=raw["paper_a_network"];sn=raw["nw"][string(t)];base=raw["baseMVA"]
    names=String.(net["physical_ac_bus_order"]); idx=Dict(x=>i for (i,x) in enumerate(names))
    bus=Dict(d["name"]=>d for d in values(sn["bus"]))
    Y=zeros(ComplexF64,length(names),length(names))
    for br in net["branch_primitives"]
        br["status"]==0 && continue
        br["source_component"]=="lines" && get(br,"tap_ratio",1)==1 && get(br,"phase_shift",0)==0 || throw(ArgumentError("independent stamp unsupported primitive"))
        a,b=br["bus0"],br["bus1"]; i,j=idx[a],idx[b]
        zbase=bus[a]["base_kv"]^2/base
        isapprox(bus[a]["base_kv"],bus[b]["base_kv"];rtol=tol) || throw(ArgumentError("voltage base mismatch"))
        y=zbase/complex(br["r_phys"],br["x_phys"]); charge=im*br["b_siemens"]*zbase/2
        Y[i,i]+=y+charge;Y[j,j]+=y+charge;Y[i,j]-=y;Y[j,i]-=y
    end
    for (b,sh) in net["fixed_shunts"];Y[idx[b],idx[b]]+=complex(sh["gs_pu"],sh["bs_pu"]);end
    L=-imag.(Y);ri=[idx[b] for b in net["retained_physical_buses"]];zi=[idx[b] for b in net["eliminated_physical_buses"]]
    schurres=0.;B0=L[ri,ri]
    if !isempty(zi)
        minimum(eigvals(Symmetric(L[zi,zi])))>tol || throw(ArgumentError("passive eliminated block not PD"))
        X=L[zi,zi]\L[zi,ri];schurres=norm(L[zi,zi]*X-L[zi,ri],Inf);B0-=L[ri,zi]*X
    end
    regions=[net["bus_to_region"][b] for b in net["retained_physical_buses"]]
    bs=[Float64(get(get(net,"fixed_strength_by_region_pu",Dict()),r,0.)) for r in regions]
    p=zeros(length(regions));pnom=copy(p);pop=copy(p);ledger=Any[];conn=0.;normres=0.
    state=solution["snapshots"][string(t)]
    for table in ("gen","storage","ne_storage"),(id,d) in get(sn,table,Dict())
        haskey(d,"source_class") || continue
        v=state["assets"]["$table:$id"]; on=v["online"];inst=v["installed"]
        r=findfirst(==(d["region_id"]),regions);r===nothing && throw(ArgumentError("source on eliminated/unknown region"))
        conn=max(conn,max(0.,on-d["a_conn"]*inst,-on))
        strength=0.;exposure=0.
        if d["source_class"]=="GFL"
            exposure=d["mu_fl"]*d["p_block_max_MW"]*on/base
            p[r]+=exposure;pnom[r]+=d["mu_fl"]*d["p_block_max_MW"]*inst/base
            # AC-side operating magnitude is explicitly distinct from nameplate.
            pop[r]+=d["mu_fl"]*abs(v["dispatch_MW"]-get(v,"charge_MW",0.))/base
        elseif !get(d,"fixed_strength_already_in_network",false)
            strength=d["mu_str"]*d["native_source_MVA"]/(base*d["x_src"])*on
            bs[r]+=strength
            normres=max(normres,abs(d["b_block"]-d["native_source_MVA"]/(base*d["x_src"])))
        end
        push!(ledger,Dict("asset"=>"$table:$id","name"=>d["name"],"region"=>regions[r],"class"=>d["source_class"],"strength"=>strength,"exposure"=>exposure,"online"=>on,"installed"=>inst,"new_MW"=>(inst-d["n0"])*d["p_block_max_MW"],"installed_MVA"=>inst*d["S_block_MVA"],"installed_MWh"=>table=="gen" ? nothing : inst*d["e_block"]))
    end
    B=B0+Diagonal(bs);alpha=sn["g_min"];M=B-alpha*Diagonal(p)
    pack=Dict{String,Any}("Y_real"=>rows(real.(Y)),"Y_imag"=>rows(imag.(Y)),"L"=>rows(L),"B0"=>rows(B0),"B"=>rows(B),"p"=>p,"M"=>rows(M),"b_src"=>bs,"regions"=>regions,"alpha"=>alpha,"base_MVA"=>base,"source_ledger"=>ledger,"schur_residual"=>schurres,"source_base_residual"=>normres,"connection_violation"=>conn,"S_nom_v1"=>pnom,"S_on_v1"=>p,"S_op_magnitude_v1"=>pop,"S_I_v1"=>nothing,"qualification"=>get(raw,"paper_a_parameter_qualification",Dict()),"passive_domain_issues"=>net["passive_domain_issues"],"empirical_approved"=>false)
    supplied=get(net,"B0_reference_pu",nothing)
    pack["producer_B0_residual"]=supplied===nothing ? nothing : norm(B0-matrix(supplied),Inf)
    pack["affine_reconstruction_residual"]=haskey(state,"affine") ? maximum([norm(B-matrix(state["affine"]["B"]),Inf),norm(M-matrix(state["affine"]["M"]),Inf),norm(p-state["affine"]["p"],Inf)]) : nothing
    return pack
end

"""Finite positive-support generalized spectrum, with PSD and projector range
checks on the entire zero-exposure block (T004/T006). No epsilon exposure."""
function finite_spectrum(B,p;tol=DEFAULT_TOL)
    n=length(p); a=findall(>(0.),p);z=findall(==(0.),p)
    any(<(0.),p) && return Dict("status"=>"domain_invalid","gamma"=>nothing)
    isempty(a) && return Dict("status"=>"undefined_no_positive_exposure","gamma"=>nothing)
    C=B[a,a];X=zeros(length(z),length(a));rr=0.
    if !isempty(z)
        F=eigen(Symmetric(B[z,z]));minimum(F.values)<-tol && return Dict("status"=>"domain_invalid_zero_block","gamma"=>nothing)
        D=Diagonal([v>tol ? 1/v : 0. for v in F.values]);pinvC=F.vectors*D*F.vectors'
        X=pinvC*B[z,a];rr=norm(B[z,z]*X-B[z,a],Inf)
        rr>tol*max(1.,norm(B,Inf)) && return Dict("status"=>"domain_invalid_range_condition","gamma"=>nothing,"range_residual"=>rr)
        C-=B[a,z]*X
    end
    D=Diagonal(1 ./sqrt.(p[a]));H=Symmetric(D*C*D);F=eigen(H);g=minimum(F.values)
    critical=findall(v->abs(v-g)<=tol*max(1.,abs(g)),F.values)
    V=zeros(n,length(critical));V[a,:]=D*F.vectors[:,critical]
    isempty(z) || (V[z,:]=-X*V[a,:])
    residual=norm(B*V-Diagonal(p)*V*g,Inf)
    accuracy=residual<=tol*max(1.,norm(B,Inf)*norm(V,Inf),abs(g)*norm(Diagonal(p)*V,Inf))
    return Dict("status"=>accuracy ? "valid" : "solver_inconclusive_eigen_residual","gamma"=>accuracy ? g : nothing,"finite_eigenvalues"=>F.values,"range_residual"=>rr,"eigenspace"=>rows(V),"multiplicity"=>length(critical),"participation"=>vec(sum(abs2,V;dims=2))/sum(abs2,V),"eigen_residual"=>residual)
end

function verify_g3(M,witness;tol=DEFAULT_TOL)
    n=size(M,1);expected=Set((i,j) for i in 1:n for j in i+1:n if M[i,j]!=0)
    e=[(Int(e[1]),Int(e[2])) for e in witness["edges"]]
    complete=length(e)==length(unique(e)) && Set(e)==expected
    complete || return Dict("status"=>"domain_invalid_edge_coverage","valid"=>false)
    R=zeros(n,n);used=zeros(n);cones=Float64[];qmin=Inf
    for (k,(i,j)) in enumerate(e)
        u,v=witness["q"][k];qmin=min(qmin,u,v);push!(cones,u*v-M[i,j]^2)
        R[i,i]+=u;R[j,j]+=v;R[i,j]=M[i,j];R[j,i]=M[i,j];used[i]+=u;used[j]+=v
    end
    d=diag(M)-used;R+=Diagonal(d);res=norm(M-R,Inf)
    ok=minimum(d)>=-tol && minimum(cones;init=0.)>=-tol && qmin>=-tol && res<=tol
    return Dict("status"=>"valid","valid"=>ok,"edges_complete"=>complete,"cone_product_slacks"=>cones,"node_budget"=>d,"minimum_q"=>isempty(e) ? nothing : qmin,"reconstruction_residual"=>res)
end

"""T018 constructive witness on each connected PSD Z block, including a
positive null vector for singular irreducible blocks and isolated zero rows."""
function closed_sdd_witness(M;tol=DEFAULT_TOL)
    n=size(M,1);norm(M-M',Inf)<=tol || return nothing
    any(M[i,j]>0 for i in 1:n,j in 1:n if i!=j) && return nothing
    eigmin(Symmetric(M))>=-tol*max(1.,opnorm(M,Inf)) || return nothing
    r=ones(n);unseen=Set(1:n)
    while !isempty(unseen)
        todo=[first(unseen)];comp=Int[]
        while !isempty(todo)
            i=pop!(todo);i in unseen || continue;delete!(unseen,i);push!(comp,i)
            append!(todo,[j for j in unseen if M[i,j]!=0])
        end
        A=M[comp,comp];F=eigen(Symmetric(A))
        if minimum(F.values)>tol*max(1.,opnorm(A,Inf))
            r[comp]=A\ones(length(comp))
        elseif length(comp)>1
            r[comp]=abs.(F.vectors[:,argmin(F.values)])
        end
    end
    minimum(r)>0 || return nothing
    edges=[[i,j] for i in 1:n for j in i+1:n if M[i,j]!=0]
    q=[[-M[i,j]*r[j]/r[i],-M[i,j]*r[i]/r[j]] for (i,j) in edges]
    return Dict("edges"=>edges,"q"=>q,"origin"=>"independent_T018_block_scaling","r"=>r)
end

function inverse_updates(A,Delta;order=1,tol=DEFAULT_TOL)
    n=size(A,1);Id=Matrix{Float64}(I,n,n)
    minimum(eigvals(Symmetric(A)))>tol && minimum(eigvals(Symmetric(A+Delta)))>tol || return Dict("status"=>"domain_invalid_inverse")
    Z=A\Id;direct=(A+Delta)\Id
    # Woodbury U=Delta, C=I, V=I, valid even when Delta is singular.
    wood=Z-Z*Delta*((Id+Z*Delta)\Z)
    E=Z*Delta;rho=maximum(abs.(eigvals(E)));q=opnorm(E,Inf)
    T=copy(Z);power=copy(Id)
    for _ in 1:order;power=-power*E;T+=power*Z;end
    bound=q<1 ? q^(order+1)/(1-q)*opnorm(Z,Inf) : nothing
    remainder=(-E)^(order+1)*((Id+E)\Z)
    return Dict("status"=>"exploratory_noncertifying","woodbury_residual"=>norm(wood-direct,Inf),"E_norm_inf"=>q,"spectral_radius"=>rho,"series_converges"=>rho<1,"order"=>order,"truncation"=>rows(T),"actual_error"=>opnorm(T-direct,Inf),"exact_remainder_residual"=>norm(direct-T-remainder,Inf),"remainder_bound"=>bound,"trust_region_norm_valid"=>q<1,"one_sided_safety_certified"=>false)
end

function evaluate(B,p,alpha; r=ones(length(p)),W=Matrix{Float64}(I,length(p),length(p)),Bmin=nothing,witness=nothing,tol=DEFAULT_TOL)
    B=matrix(B);p=Float64.(p);n=length(p)
    size(B)==(n,n) && all(isfinite,B) && all(isfinite,p) && isfinite(alpha) && alpha>=0 || throw(ArgumentError("invalid matrices/alpha"))
    norm(B-B',Inf)<=tol && minimum(p)>=-tol || throw(ArgumentError("asymmetric B or negative exposure"))
    exposure_roundoff=max(0.,-minimum(p))
    # Solver feasibility roundoff is not positive epsilon exposure: preserve
    # exact zeros and record the removed negative roundoff explicitly.
    p=max.(0.,p)
    length(r)==n && minimum(r)>0 && all(isfinite,r) || throw(ArgumentError("invalid fixed r"))
    W=matrix(W);size(W)==(n,n) && minimum(W)>=0 && all(diag(W).==1) || throw(ArgumentError("invalid W"))
    M=B-alpha*Diagonal(p);eB=eigvals(Symmetric(B));eM=eigvals(Symmetric(M));scale=max(1.,opnorm(B,Inf));etol=tol*scale
    sym=norm(B-B',Inf);off=maximum([B[i,j] for i in 1:n,j in 1:n if i!=j];init=0.)
    spectrum=finite_spectrum(B,p;tol)
    m=Dict{String,Any}()
    put(id,v;kw...)=m[id]=entry(v;kw...)
    put("A.exposure_roundoff_correction",exposure_roundoff;method="max(0,-minimum(raw_p)); negative solver roundoff <= tolerance projected to zero")
    put("A.symmetry",sym);put("A.positive_offdiagonal",max(0.,off));put("A.Z_class",off<=tol;unit="boolean")
    put("A.B_eigenvalues",eB);put("A.M_eigenvalues",eM)
    put("A.inertia",[count(<(-etol),eB),count(x->abs(x)<=etol,eB),count(>(etol),eB)];unit="count")
    put("A.nullity",count(x->abs(x)<=etol,eB);unit="count");put("A.rank",count(x->abs(x)>etol,eB);unit="count")
    c=cond(B);put("A.condition",isfinite(c) ? c : nothing;status=isfinite(c) ? "valid" : "undefined_singular",unit="dimensionless")
    put("B.gamma",get(spectrum,"gamma",nothing);status=spectrum["status"],theorem="T-C2A-004/006")
    put("B.gamma_margin",get(spectrum,"gamma",nothing)===nothing ? nothing : spectrum["gamma"]-alpha;status=spectrum["status"])
    for key in ("range_residual","eigen_residual","eigenspace","multiplicity","participation");put("B.$key",get(spectrum,key,nothing);status=haskey(spectrum,key) ? "valid" : spectrum["status"]);end
    put("B.G0_eigmin",minimum(eM));put("B.G0",minimum(eM)>=-etol;unit="boolean",theorem="T-C2A-005")
    put("B.G1_rows",M*ones(n));put("B.G2_rows",M*r);put("B.G1",minimum(M*ones(n))>=-etol;unit="boolean");put("B.G2",minimum(M*r)>=-etol;unit="boolean")
    put("B.G1_binding",abs.(M*ones(n)).<=etol;unit="boolean");put("B.G2_binding",abs.(M*r).<=etol;unit="boolean")
    put("B.G1_false_rejection",minimum(eM)>=-etol && minimum(M*ones(n)) < -etol;unit="boolean")
    put("C.Wp",W*p);put("C.M2_rows",B*ones(n)-alpha*W*p);put("C.M2",minimum(B*ones(n)-alpha*W*p)>=-etol;unit="boolean")
    witness===nothing && (witness=closed_sdd_witness(M;tol))
    if witness===nothing
        m["B.G3"]=undefined("not_executed_missing_witness")
        for k in ("status","valid","edges","q","edges_complete","cone_product_slacks","node_budget","minimum_q","reconstruction_residual");m["B.G3_$k"]=undefined("not_executed_missing_witness");end
    else
        g=verify_g3(M,witness;tol=etol)
        g["edges"]=witness["edges"];g["q"]=witness["q"]
        m["B.G3"]=entry(g["valid"];unit="boolean",status=g["status"])
        for (k,v) in g;put("B.G3_$k",v;status=g["status"]);end
    end
    invkeys=("Z","Z_diag","equivalent_strength","inverse_min","solve_residual","Zp","rho_diag","rho_Zp","M0_slack","M0","MIIF","LOCAL_eigmin","LOCAL","M1_upper_burden","M1_order_violation","M1_lower_violation","M1")
    if minimum(eB)<=etol || c>1e12
        reason=c>1e12 && minimum(eB)>0 ? "solver_inconclusive_ill_conditioned" : "undefined_non_PD"
        for key in invkeys;m["C.$key"]=undefined(reason);end
    else
        Z=B\Matrix{Float64}(I,n,n);y=B\p
        ztol=tol*max(1.,opnorm(Z,Inf));positive=minimum(Z)>=-ztol
        put("C.Z",rows(Z));put("C.Z_diag",diag(Z));put("C.inverse_min",minimum(Z));put("C.solve_residual",norm(B*y-p,Inf));put("C.equivalent_strength",1 ./diag(Z))
        put("C.Zp",y);put("C.rho_diag",[p[i]>0 ? 1/(Z[i,i]*p[i]) : nothing for i in 1:n];status=any(==(0.),p) ? "valid_with_undefined_zero_denominators" : "valid")
        put("C.rho_Zp",[y[i]>etol ? 1/y[i] : nothing for i in 1:n];status=any(y.<=etol) ? "valid_with_undefined_zero_denominators" : "valid")
        put("C.MIIF",rows(Z ./diag(Z)))
        local_e=[eigmin(Symmetric(B-alpha*p[i]*(Matrix{Float64}(I,n,n)[:,i]*Matrix{Float64}(I,n,n)[:,i]'))) for i in 1:n]
        put("C.LOCAL_eigmin",local_e);put("C.LOCAL",minimum(local_e)>=-etol;unit="boolean")
        for (k,v) in (("M0_slack",alpha>0 ? 1/alpha .-y : nothing),("M0",alpha>0 ? maximum(y)<=1/alpha+etol : nothing))
            put("C.$k",positive && alpha>0 ? v : nothing;status=!positive ? "domain_invalid_inverse_sign" : alpha==0 ? "undefined_alpha_zero" : "valid")
        end
        if Bmin===nothing
            for k in ("M1_upper_burden","M1_order_violation","M1_lower_violation","M1");m["C.$k"]=undefined("not_executed_missing_Bmin");end
        else
            A=matrix(Bmin);valid=size(A)==size(B)&&isposdef(Symmetric(A))&&maximum([A[i,j] for i in 1:n,j in 1:n if i!=j];init=0.)<=tol
            valid || throw(ArgumentError("invalid M1 minimum matrix"))
            Zub=A\Matrix{Float64}(I,n,n);lower=max(0.,maximum(A-B));order=max(0.,maximum(Z-Zub))
            put("C.M1_lower_violation",lower);put("C.M1_order_violation",order)
            put("C.M1_upper_burden",Zub*p;status=lower<=etol ? "valid" : "domain_invalid_unenforced_Bmin")
            put("C.M1",lower<=etol && order<=ztol && alpha>0 && maximum(Zub*p)<=1/alpha+tol*max(1.,norm(Zub*p,Inf));unit="boolean",status=lower<=etol ? "valid" : "domain_invalid_unenforced_Bmin")
        end
    end
    for k in ("SCR_external","ESCR_external","MSCR_external","gSCR_external");m["C.$k"]=undefined("not_comparable_missing_source_fault_convention");end
    return m
end
end
