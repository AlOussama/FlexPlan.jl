"""A3.5 independent exact and raw-input oracle. No FlexPlan diagnostics import.
Usage: python independent_reference_oracle.py RUN_ROOT BASELINE_ROOT
Requires numpy, sympy. Historical exports are comparison targets only.
"""
import csv, hashlib, itertools, json, sys
from pathlib import Path
import numpy as np
import sympy as sp
R=Path(sys.argv[1]); BASE=Path(sys.argv[2]); Q=sp.Rational
def dump(name,obj): (R/name).write_text(json.dumps(obj,indent=2,default=str),encoding='utf-8')
def hashfile(p): return hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
def exact_pack(B,p,alpha=1):
    B=sp.Matrix(B); p=sp.Matrix(p); M=B-alpha*sp.diag(*p)
    minors=[M.extract(c,c).det() for k in range(1,M.rows+1) for c in itertools.combinations(range(M.rows),k)]
    Z=B.inv() if B.det()!=0 else None
    zp=Z*p if Z is not None else None
    return dict(B=B.tolist(),p=list(p),M=M.tolist(),principal_minors=minors,PSD=all(v>=0 for v in minors),eigenvalues=M.eigenvals(),Z=None if Z is None else Z.tolist(),Zp=None if zp is None else list(zp),G1=list(M*sp.ones(M.rows,1)),inverse_nonnegative=Z is not None and all(v>=0 for v in Z))
cases={
 'G0_not_M0':exact_pack([[1,-Q(1,2)],[-Q(1,2),1]],[Q(1,4),Q(2,3)]),
 'M0_not_G1':exact_pack([[2,-1],[-1,2]],[Q(11,10),Q(1,20)]),
 'SPD_non_inverse_positive':exact_pack([[1,Q(4,5)],[Q(4,5),1]],[1,1]),
 'LOCAL_not_G0':exact_pack([[1,-Q(1,2)],[-Q(1,2),1]],[Q(3,4),Q(3,4)]),
 'new_positive':exact_pack([[Q(17,5),-Q(2,5)],[-Q(2,5),Q(11,5)]],[Q(3,10),Q(7,20)]),
 'singular_reducible_zero':exact_pack([[1,-1,0],[-1,1,0],[0,0,0]],[0,0,0]),
 'non_Z_PSD':exact_pack(sp.ones(3),[0,0,0])}
assert cases['G0_not_M0']['PSD'] and cases['G0_not_M0']['Zp']==[Q(7,9),Q(19,18)]
assert cases['M0_not_G1']['Zp']==[Q(3,4),Q(2,5)] and cases['M0_not_G1']['G1'][0]<0
assert not cases['SPD_non_inverse_positive']['PSD'] and not cases['SPD_non_inverse_positive']['inverse_nonnegative']
assert not cases['LOCAL_not_G0']['PSD'] and cases['new_positive']['PSD']
checks=[]
def check(name,condition,detail):
    assert condition,name
    checks.append(dict(id=name,passed=True,detail=detail))
L=sp.Matrix([[2,-1],[-1,-1]])
check('invertible_not_PD_Schur',L.det()<0 and L[0,0]-L[0,1]**2/L[1,1]==3,dict(L=L.tolist(),Schur=3))
L=sp.Matrix([[1,1],[1,0]])
check('pseudoinverse_range_required',L.det()<0 and L[1,0]!=0,dict(L=L.tolist(),range_residual=1))
for name,M in [('G1_not_G2',sp.Matrix([[1,-Q(3,5)],[-Q(3,5),1]])),('G2_not_G1',sp.Matrix([[Q(2,5),-Q(3,5)],[-Q(3,5),Q(6,5)]]))]:
    a=list(M*sp.ones(2,1));b=list(M*sp.Matrix([2,1])); check(name,(all(x>=0 for x in a) and any(x<0 for x in b)) if name=='G1_not_G2' else (all(x>=0 for x in b) and any(x<0 for x in a)),dict(rows=a,scaled_rows=b))
check('singular_exposure_negative_zero_block',2-10**2<0,dict(B=[[2,0],[0,-1]],S=[[1,0],[0,0]],formal_finite_eigenvalue=2,rayleigh_at_1_10=-98,infimum='-infinity'))
A=sp.Matrix([[3,-1],[-1,2]]); C=sp.Matrix([[2,Q(1,3)],[Q(1,3),1]])
check('parallel_sum',C-C*(A+C).inv()*C==(A.inv()+C.inv()).inv(),dict(A=A.tolist(),C=C.tolist()))
Delta=sp.diag(Q(1,10),Q(1,20));Z=A.inv();E=Z*Delta;direct=(A+Delta).inv();wood=Z-Z*Delta*(sp.eye(2)+Z*Delta).inv()*Z
T=(sp.eye(2)-E)*Z;rem=E**2*(sp.eye(2)+E).inv()*Z
norm=lambda X:max(sum(abs(X[i,j]) for j in range(X.cols)) for i in range(X.rows))
q=norm(E);bound=q**2/(1-q)*norm(Z)
check('Woodbury_Neumann_exact',wood==direct and direct-T==rem and norm(rem)<=bound,dict(E=E.tolist(),norm=q,actual_error=norm(rem),bound=bound,remainder=rem.tolist()))
check('source_boundary',Q(7)+Q(3)-Q(3)**2/Q(3)==7,dict(fixed_internal_terminal=10,free_internal_schur=7))
check('M1_order',all(x>=0 for x in A.inv()-(A+Delta).inv()),dict(Zub=A.inv().tolist(),Z=(A+Delta).inv().tolist()))
cp=sp.Matrix([Q(3,5),Q(3,5)]);cb=sp.Matrix([[1,-Q(1,2)],[-Q(1,2),1]])
check('uncontrolled_inverse_false_acceptance',max(cp)<1 and max(cb.inv()*cp)>1,dict(approximate_burden=list(cp),exact_burden=list(cb.inv()*cp)))
check('outside_Neumann_norm_region',norm(cb.inv()*3*sp.eye(2))>=1,dict(norm=norm(cb.inv()*3*sp.eye(2)),one_sided_certificate=False))
# Complex transformer with resistance, pi charge and shunt: unsymmetric L must be detected.
y=1/complex(.03,.2);tap=1.1*np.exp(.17j);Y=np.array([[(y+.02j)/abs(tap)**2,-y/np.conj(tap)],[-y/tap,y+.02j-.04j]])
check('phase_tap_not_silently_symmetric',np.max(np.abs(Y.imag-Y.imag.T))>1e-4,dict(Yreal=Y.real.tolist(),Yimag=Y.imag.tolist(),symmetry_residual=float(np.max(np.abs(Y.imag-Y.imag.T)))))
def jsonable(x):
    if isinstance(x,dict):return {str(k):jsonable(v) for k,v in x.items()}
    if isinstance(x,(tuple,list)):return [jsonable(v) for v in x]
    if isinstance(x,sp.Basic):return str(x)
    return x
dump('oracle_results.json',jsonable(dict(exact_cases=cases,checks=checks,method='new_sympy_exact_principal_minors_and_identities')))
enumerated=[];feasible={k:[] for k in ['G0','G3','M0','G1','M2']}
for a,b in itertools.product(range(9),repeat=2):
    BB=sp.Matrix([[Q(1,2)+Q(a,4),-Q(1,2)],[-Q(1,2),Q(1,2)+Q(b,4)]]);pp=sp.Matrix([Q(1,4),Q(2,3)]);MM=BB-sp.diag(*pp);cost=a+3*b
    g0=MM[0,0]>=0 and MM[1,1]>=0 and MM.det()>=0
    m0=BB.det()>0 and max(BB.inv()*pp)<=1
    g1=min(MM*sp.ones(2,1))>=0
    m2=min(BB*sp.ones(2,1)-sp.Matrix([[1,Q(1,5)],[Q(1,5),1]])*pp)>=0
    # In 2x2, q=(M11,M22) is a complete edge witness exactly when PSD.
    flags=dict(G0=bool(g0),G3=bool(g0),M0=bool(m0),G1=bool(g1),M2=bool(m2))
    for k,v in flags.items():
        if v:feasible[k].append(cost)
    enumerated.append(dict(a=a,b=b,cost=cost,**flags))
opt={k:min(v) for k,v in feasible.items()};assert opt['G0']==opt['G3']<=opt['M0']<=opt['G1']<=opt['M2']
dump('independent_exact_integer_enumeration.json',dict(assignments=enumerated,complete=True,domain='new two-region 81-assignment rational toy; not the nine producer cases',optima=opt))

def rebuild(raw,state,t):
    net=raw['paper_a_network'];sn=raw['nw'][t];base=raw['baseMVA'];names=net['physical_ac_bus_order'];idx={x:i for i,x in enumerate(names)}
    bus={b['name']:b for b in sn['bus'].values()};Y=np.zeros((len(names),len(names)),complex)
    for br in net['branch_primitives']:
        if not br['status']:continue
        i,j=idx[br['bus0']],idx[br['bus1']];zb=bus[br['bus0']]['base_kv']**2/base
        ys=zb/complex(br['r_phys'],br['x_phys']);ch=.5j*br['b_siemens']*zb
        a=br.get('tap_ratio',1)*np.exp(1j*br.get('phase_shift',0))
        Y[i,i]+=(ys+ch)/abs(a)**2;Y[j,j]+=ys+ch;Y[i,j]-=ys/np.conj(a);Y[j,i]-=ys/a
    for b,sh in net['fixed_shunts'].items():Y[idx[b],idx[b]]+=complex(sh['gs_pu'],sh['bs_pu'])
    L=-Y.imag;rr=[idx[x] for x in net['retained_physical_buses']];ee=[idx[x] for x in net['eliminated_physical_buses']]
    B0=L[np.ix_(rr,rr)].copy();Lee=L[np.ix_(ee,ee)];schur=0.
    if ee:
        X=np.linalg.solve(Lee,L[np.ix_(ee,rr)]);B0-=L[np.ix_(rr,ee)]@X;schur=float(np.max(np.abs(Lee@X-L[np.ix_(ee,rr)])))
    regions=[net['bus_to_region'][x] for x in net['retained_physical_buses']];p=np.zeros(len(rr));bs=np.array([net.get('fixed_strength_by_region_pu',{}).get(x,0) for x in regions],float)
    for table in ['gen','storage','ne_storage']:
        for id,d in sn.get(table,{}).items():
            if 'source_class' not in d:continue
            a=state['assets'][f'{table}:{id}'];i=regions.index(d['region_id'])
            if d['source_class']=='GFL':p[i]+=d['mu_fl']*d['p_block_max_MW']/base*a['online']
            elif not d['fixed_strength_already_in_network']:bs[i]+=d['mu_str']*d['native_source_MVA']/(base*d['x_src'])*a['online']
    B=B0+np.diag(bs);S=np.diag(p);M=B-sn['g_min']*S;ev=np.linalg.eigvalsh(B);mev=np.linalg.eigvalsh(M)
    Z=np.linalg.inv(B) if ev.min()>1e-9 else None
    a=np.flatnonzero(p>0);z=np.flatnonzero(p==0);gamma=None;range_res=0.
    if len(a):
        H=B[np.ix_(a,a)].copy()
        if len(z):
            C=B[np.ix_(z,z)];cross=B[np.ix_(z,a)];CX=np.linalg.pinv(C)@cross;range_res=np.max(np.abs(C@CX-cross));H-=cross.T@CX
        gamma=float(np.linalg.eigvalsh(H/np.sqrt(np.outer(p[a],p[a]))).min())
    expected={(i+1,j+1) for i in range(len(rr)) for j in range(i+1,len(rr)) if M[i,j]!=0};wit=state.get('witness');g3=None
    if wit:
        used=np.zeros(len(rr));rec=np.zeros_like(M);products=[]
        for (i,j),(u,v) in zip(wit['edges'],wit['q']):
            i-=1;j-=1;used[i]+=u;used[j]+=v;rec[i,i]+=u;rec[j,j]+=v;rec[i,j]+=M[i,j];rec[j,i]+=M[i,j];products.append(u*v-M[i,j]**2)
        d=np.diag(M)-used;rec+=np.diag(d)
        g3=dict(edge_complete=len(wit['edges'])==len(expected) and {tuple(e) for e in wit['edges']}==expected,product_min=min(products,default=0),residue_min=float(d.min()),reconstruction=float(np.max(np.abs(rec-M))),q=wit['q'],edges=wit['edges'])
    return dict(Yreal=Y.real.tolist(),Yimag=Y.imag.tolist(),L=L.tolist(),B0=B0.tolist(),B=B.tolist(),p=p.tolist(),S=S.tolist(),M=M.tolist(),Zp=None if Z is None else (Z@p).tolist(),Zmin=None if Z is None else float(Z.min()),eigB=ev.tolist(),eigM=mev.tolist(),gamma=gamma,range_residual=float(range_res),Lee_eigenvalues=np.linalg.eigvalsh(Lee).tolist() if ee else [],schur_residual=schur,G1=(M@np.ones(len(rr))).tolist(),G3=g3,model_diff=max(float(np.max(np.abs(B-np.array(state['affine']['B'])))),float(np.max(np.abs(M-np.array(state['affine']['M'])))),float(np.max(np.abs(p-np.array(state['affine']['p']))))))
def economics(raw,solution):
    totals=dict(investment=0.,generation=0.,storage=0.,startup=0.,shutdown=0.,no_load=0.);times=sorted(raw['nw'],key=int);viol=dict(balance_MW=0.,soc_MWh=0.,terminal_MWh=0.,connection_blocks=0.,integrality_blocks=0.,UC_transition=0.)
    for t in times:
        sn=raw['nw'][t];ss=solution['snapshots'][t];tm=raw['paper_a_temporal'][int(t)-1];dt=tm['delta_t_h'];dw=dt*tm['representative_repetitions']*tm['scenario_probability'];ew=tm['event_repetitions']*tm['scenario_probability']
        balance={str(i):0. for i in sn['bus']}
        for l in sn['load'].values():balance[str(l['load_bus'])]+=l['pd']
        for i,br in sn['branch'].items():
            if br.get('br_status',1):
                f,to=ss['branch_flows_MW'][i];balance[str(br['f_bus'])]+=f;balance[str(br['t_bus'])]+=to
        for table in ['gen','storage','ne_storage']:
            for i,d in sn.get(table,{}).items():
                if 'source_class' not in d:continue
                key=f'{table}:{i}';v=ss['assets'][key];P=d['p_block_max_MW'];inst=v['installed'];on=v['online']
                if t==times[0]:totals['investment']+=(inst-d['n0'])*P*d['cost_inv_per_mw']*raw.get('investment_period_fraction',1)
                totals['startup']+=P*ew*d['startup_cost_per_mw']*v['startup'];totals['shutdown']+=P*ew*d['shutdown_cost_per_mw']*v['shutdown']
                totals['generation' if table=='gen' else 'storage']+=dw*d['marginal_cost']*v['dispatch_MW']
                viol['connection_blocks']=max(viol['connection_blocks'],0.,on-d['a_conn']*inst,-on,d['n0']-inst,inst-d['nmax'])
                viol['integrality_blocks']=max(viol['integrality_blocks'],*(abs(v[x]-round(v[x])) for x in ['installed','online','startup','shutdown']))
                if table=='gen':
                    balance[str(d['gen_bus'])]-=v['dispatch_MW'];totals['no_load']+=dw*d.get('cost',[0,0])[-1]
                    if d['source_class']=='SYN':
                        prev=d['na0'] if t==times[0] else solution['snapshots'][times[times.index(t)-1]]['assets'][key]['online'];viol['UC_transition']=max(viol['UC_transition'],abs(on-prev-v['startup']+v['shutdown']))
                else:
                    balance[str(d['storage_bus'])]+=v['charge_MW']-v['dispatch_MW'];prev=d['energy'] if t==times[0] else solution['snapshots'][times[times.index(t)-1]]['assets'][key]['energy_MWh']
                    viol['soc_MWh']=max(viol['soc_MWh'],abs(v['energy_MWh']-prev-dt*(d['charge_efficiency']*v['charge_MW']-v['dispatch_MW']/d['discharge_efficiency'])))
                    if t==times[-1]:viol['terminal_MWh']=max(viol['terminal_MWh'],abs(v['energy_MWh']-raw['nw'][times[0]][table][i]['energy']))
        viol['balance_MW']=max(viol['balance_MW'],*(abs(x) for x in balance.values()))
    return dict(components=totals,total=sum(totals.values()),violations=viol,hours=sum(x['delta_t_h'] for x in raw['paper_a_temporal']))
def audit_suite(path,label):
    if not (path/'runs.json').exists():return []
    rows=[]
    for run in json.loads((path/'runs.json').read_text())['runs']:
        f=path/run.get('solution_file','absent');case=path/run['case_id']/'case.json'
        if not f.is_file() or run['status']!='optimal':continue
        raw=json.loads(case.read_text());sol=json.loads(f.read_text());eco=economics(raw,sol)
        for t,state in sol['snapshots'].items():
            m=rebuild(raw,state,t);rows.append(dict(label=label,case_id=run['case_id'],formulation=run['formulation'],relaxed=run['relaxed'],t=t,case_sha256=hashfile(case),solution_sha256=hashfile(f),matrices=m))
        economics_rows.append(dict(label=label,case_id=run['case_id'],formulation=run['formulation'],relaxed=run['relaxed'],case_sha256=hashfile(case),solution_sha256=hashfile(f),objective=run['objective'],bound=run.get('bound'),objective_scale=run.get('objective_solver_scaling'),objective_residual=abs(eco['total']-run['objective']),**eco))
    return rows
economics_rows=[]
rows=audit_suite(BASE/'reports/ap3_runs/20261020_macro/accepted_suite','historical')+audit_suite(R/'suite','fresh')
dump('independent_matrices_B_p_S_M_Zp_G3.json',rows);dump('independent_objective_audit.json',economics_rows)
dump('raw_reconstruction_summary.json',dict(snapshots=len(rows),solutions=len(economics_rows),maximum_model_matrix_difference=max((r['matrices']['model_diff'] for r in rows),default=0),maximum_objective_difference=max((r['objective_residual'] for r in economics_rows),default=0)))
print('exact cases',len(cases),'identity/boundary checks',len(checks),'states',len(rows),'solutions',len(economics_rows))
