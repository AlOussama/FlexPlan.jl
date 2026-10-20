"""Independent metric expectations from raw inputs, prices, decisions and matrix algebra.
Runtime attributes are checked for faithful export, not independently timed historic facts.
"""
import csv,json,sys
from pathlib import Path
import numpy as np
R=Path(sys.argv[1]);B=Path(sys.argv[2]);tol=1e-7
rows=json.loads((R/'independent_matrices_B_p_S_M_Zp_G3.json').read_text());ec=json.loads((R/'independent_objective_audit.json').read_text())
lookup={(x['label'],x['case_id'],x['formulation'],x['relaxed'],x['t']):x['matrices'] for x in rows}
costs={(x['label'],x['case_id'],x['formulation'],x['relaxed']):x for x in ec}
def close(a,b):
    if isinstance(a,dict) and isinstance(b,dict):return set(a)==set(b) and all(close(a[k],b[k]) for k in a)
    if isinstance(a,list) and isinstance(b,list):
        if a and b and isinstance(a[0],dict) and isinstance(b[0],dict) and 'asset' in a[0] and 'asset' in b[0]:a=sorted(a,key=lambda x:x['asset']);b=sorted(b,key=lambda x:x['asset'])
        return len(a)==len(b) and all(close(x,y) for x,y in zip(a,b))
    if a is None or b is None:return a is b
    if isinstance(a,str) or isinstance(b,str):return a==b
    try:return np.shape(a)==np.shape(b) and bool(np.allclose(np.array(a,float),np.array(b,float),atol=1e-7,rtol=2e-7,equal_nan=False))
    except (TypeError,ValueError):return a==b
def expectations(m,raw,sol,run,t,eco):
    sn=raw['nw'][t];st=sol['snapshots'][t];P=run['parameters'];base=raw['baseMVA'];alpha=sn['g_min'];A=np.array(m['B']);M=np.array(m['M']);p=np.array(m['p']);n=len(p);etol=tol*max(1,np.linalg.norm(A,np.inf));ev=np.array(m['eigB']);mev=np.array(m['eigM']);r=np.array(P['r_degree'] if run['formulation']=='G2_degree' else P['r_identity']);W=np.array(P['W_neighbor'] if run['formulation']=='M2_neighbor' else P['W_full']);floor=np.array(P['Bmin']);Z=np.linalg.inv(A) if min(ev)>etol else None
    exp={'A.B':A,'A.B0':m['B0'],'A.L':m['L'],'A.M':M,'A.S_diag':p,'A.Y_real':m['Yreal'],'A.Y_imag':m['Yimag'],'A.B_eigenvalues':ev,'A.M_eigenvalues':mev,'A.symmetry':np.max(abs(A-A.T)),'A.positive_offdiagonal':max(0,max((A[i,j] for i in range(n) for j in range(n) if i!=j),default=0)),'A.Z_class':all(A[i,j]<=tol for i in range(n) for j in range(n) if i!=j),'A.condition':np.linalg.cond(A),'A.inertia':[sum(ev<-etol),sum(abs(ev)<=etol),sum(ev>etol)],'A.nullity':sum(abs(ev)<=etol),'A.rank':sum(abs(ev)>etol),'A.exposure_roundoff_correction':max(0,-min(p)),'A.schur_residual':m['schur_residual'],'A.affine_reconstruction_residual':m['model_diff'],'A.producer_B0_residual':np.max(abs(np.array(m['B0'])-raw['paper_a_network']['B0_reference_pu'])),'B.gamma':m['gamma'],'B.gamma_margin':None if m['gamma'] is None else m['gamma']-alpha,'B.range_residual':m['range_residual'],'B.G0':min(mev)>=-etol,'B.G0_eigmin':min(mev),'B.G1_rows':M@np.ones(n),'B.G2_rows':M@r,'B.G1':min(M@np.ones(n))>=-etol,'B.G2':min(M@r)>=-etol,'B.G1_binding':abs(M@np.ones(n))<=etol,'B.G2_binding':abs(M@r)<=etol,'B.G1_false_rejection':min(mev)>=-etol and min(M@np.ones(n))<-etol,'C.Wp':W@p,'C.M2_rows':A@np.ones(n)-alpha*W@p,'C.M2':min(A@np.ones(n)-alpha*W@p)>=-etol,'E.S_on_v1':p,'E.S_I_v1':None}
    le=[min(np.linalg.eigvalsh(A-alpha*p[i]*np.diag(np.eye(n)[i]))) for i in range(n)];exp.update({'C.LOCAL_eigmin':le,'C.LOCAL':min(le)>=-etol})
    aa=np.flatnonzero(p>0);zz=np.flatnonzero(p==0)
    if len(aa):
        H=A[np.ix_(aa,aa)].copy();X=np.zeros((len(zz),len(aa)))
        if len(zz):X=np.linalg.pinv(A[np.ix_(zz,zz)])@A[np.ix_(zz,aa)];H-=A[np.ix_(aa,zz)]@X
        D=np.diag(1/np.sqrt(p[aa]));ee,U=np.linalg.eigh(D@H@D);ix=np.flatnonzero(abs(ee-ee[0])<=tol*max(1,abs(ee[0])));V=np.zeros((n,len(ix)));V[aa]=D@U[:,ix]
        if len(zz):V[zz]=-X@V[aa]
        exp.update({'B.eigenspace':V,'B.multiplicity':len(ix),'B.eigen_residual':np.max(abs(A@V-np.diag(p)@V*ee[0])),'B.participation':np.sum(V**2,axis=1)/np.sum(V**2)})
    edges=[(i,j) for i in range(n) for j in range(i+1,n) if M[i,j]!=0];wit=st.get('witness');q=None
    if wit:q=np.array(wit['q'])
    elif min(mev)>=-tol*max(1,np.linalg.norm(M,np.inf)) and all(M[i,j]<=0 for i,j in edges):
        rr=np.ones(n);left=set(range(n))
        while left:
            stack=[min(left)];component=[]
            while stack:
                i=stack.pop()
                if i not in left:continue
                left.remove(i);component.append(i);stack.extend(j for j in left if M[i,j]!=0)
            C=M[np.ix_(component,component)];evv,vec=np.linalg.eigh(C)
            if min(evv)>tol*max(1,np.linalg.norm(C,np.inf)):rr[component]=np.linalg.solve(C,np.ones(len(component)))
            elif len(component)>1:rr[component]=abs(vec[:,0])
        if min(rr)>0:q=np.array([[-M[i,j]*rr[j]/rr[i],-M[i,j]*rr[i]/rr[j]] for i,j in edges])
    if q is not None:
        used=np.zeros(n);recon=np.zeros_like(M);prod=[]
        for (i,j),(u,v) in zip(edges,q):used[i]+=u;used[j]+=v;recon[i,i]+=u;recon[j,j]+=v;recon[i,j]+=M[i,j];recon[j,i]+=M[i,j];prod.append(u*v-M[i,j]**2)
        dd=np.diag(M)-used;recon+=np.diag(dd);qmin=float(np.min(q)) if len(q) else None;valid=min(dd)>=-etol and min(prod,default=0)>=-etol and (qmin is None or qmin>=-etol)
        exp.update({'B.G3':bool(valid),'B.G3_valid':bool(valid),'B.G3_status':'valid','B.G3_edges_complete':True,'B.G3_edges':[[i+1,j+1] for i,j in edges],'B.G3_q':q.tolist(),'B.G3_cone_product_slacks':prod,'B.G3_node_budget':dd,'B.G3_minimum_q':qmin,'B.G3_reconstruction_residual':np.max(abs(recon-M))})
    else:
        for k in ['','_valid','_status','_edges_complete','_edges','_q','_cone_product_slacks','_node_budget','_minimum_q','_reconstruction_residual']:exp['B.G3'+k]=None
    if Z is not None:
        y=Z@p;zub=np.linalg.inv(floor);lower=max(0,np.max(floor-A));order=max(0,np.max(Z-zub));ztol=tol*max(1,np.linalg.norm(Z,np.inf))
        exp.update({'C.Z':Z,'C.Z_diag':Z.diagonal(),'C.inverse_min':Z.min(),'C.Zp':y,'C.solve_residual':np.max(abs(A@y-p)),'C.equivalent_strength':1/Z.diagonal(),'C.equivalent_strength_MVA':base/Z.diagonal(),'C.rho_diag':[1/(Z[i,i]*p[i]) if p[i]>0 else None for i in range(n)],'C.rho_Zp':[1/v if v>etol else None for v in y],'C.MIIF':Z/Z.diagonal()[:,None],'C.M0':bool(max(y)<=1/alpha+etol) if Z.min()>=-ztol and alpha>0 else None,'C.M0_slack':1/alpha-y if alpha>0 and Z.min()>=-ztol else None,'C.M1_upper_burden':zub@p,'C.M1_lower_violation':lower,'C.M1_order_violation':order,'C.M1':bool(lower<=etol and order<=ztol and max(zub@p)<=1/alpha+tol*max(1,np.max(abs(zub@p))))})
    exp.update({f'C.{id}_external':None for id in ['SCR','ESCR','MSCR','gSCR']})
    if min(np.linalg.eigvalsh(floor))>tol and min(ev)>tol:
        zi=np.linalg.inv(floor);delta=A-floor;E=zi@delta;di=np.linalg.inv(A);T=(np.eye(n)-E)@zi;rem=E@E@np.linalg.solve(np.eye(n)+E,zi);q=np.linalg.norm(E,np.inf);rho=max(abs(np.linalg.eigvals(E)));bd=q*q/(1-q)*np.linalg.norm(zi,np.inf) if q<1 else None
        exp.update({'D.E_norm_inf':q,'D.spectral_radius':rho,'D.series_converges':rho<1,'D.order':1,'D.truncation':T,'D.actual_error':np.linalg.norm(T-di,np.inf),'D.remainder_bound':bd,'D.trust_region_norm_valid':q<1,'D.one_sided_safety_certified':False,'D.status':'exploratory_noncertifying','D.woodbury_residual':np.max(abs(zi-zi@delta@np.linalg.solve(np.eye(n)+E,zi)-di)),'D.exact_remainder_residual':np.max(abs(di-T-rem)),'D.E2_false_acceptance':bool(max(T@p)<=1/alpha and not exp['C.M0']),'D.E2_conservative_rejection':bool(max(T@p)>1/alpha and exp['C.M0'])})
    regions=[raw['paper_a_network']['bus_to_region'][b] for b in raw['paper_a_network']['retained_physical_buses']];nom=np.zeros(n);op=np.zeros(n);conn=0.;sr=0.;source=[];portfolio=[];curtail=0.
    for table in ['gen','storage','ne_storage']:
        for id,d in sn.get(table,{}).items():
            if 'source_class' not in d:continue
            v=st['assets'][f'{table}:{id}'];i=regions.index(d['region_id']);on=v['online'];inst=v['installed'];strength=0.;exposure=0.;Pmw=d['p_block_max_MW']
            conn=max(conn,0,on-d['a_conn']*inst,-on)
            if d['source_class']=='GFL':
                exposure=d['mu_fl']*Pmw*on/base;nom[i]+=d['mu_fl']*Pmw*inst/base;op[i]+=d['mu_fl']*abs(v['dispatch_MW']-v.get('charge_MW',0))/base
            elif not d['fixed_strength_already_in_network']:
                strength=d['mu_str']*d['native_source_MVA']/(base*d['x_src'])*on;sr=max(sr,abs(d['b_block']-d['native_source_MVA']/(base*d['x_src'])))
            source.append(dict(asset=f'{table}:{id}',name=d['name'],region=regions[i],**{'class':d['source_class']},strength=strength,exposure=exposure,online=on,installed=inst,new_MW=(inst-d['n0'])*Pmw,installed_MVA=inst*d['S_block_MVA'],installed_MWh=None if table=='gen' else inst*d['e_block']))
    exp.update({'A.connection_violation':conn,'A.source_base_residual':sr,'E.S_nom_v1':nom,'E.S_op_magnitude_v1':op,'A.source_ledger':source,'A.network_domain':{k:raw['paper_a_network'][k] for k in ['network_islands','reference_buses','retained_physical_buses','eliminated_physical_buses','fixed_shunts','fixed_sources_in_network']}})
    exp.update({f'E.{k}':v for k,v in eco['components'].items() if k not in ['startup','shutdown']});exp['E.events']=eco['components']['startup']+eco['components']['shutdown'];exp['E.objective_residual']=eco['objective_residual']
    exp.update({f'E.{a}':eco['violations'][b] for a,b in [('bounds_violation_blocks','connection_blocks'),('power_balance_MW','balance_MW'),('SOC_residual_MWh','soc_MWh'),('terminal_residual_MWh','terminal_MWh'),('UC_transition_residual','UC_transition')]});exp['E.integrality_residual']=None if run['relaxed'] else eco['violations']['integrality_blocks']
    thermal=0.;curtail=0.;portfolio=[];tt=sorted(raw['nw'],key=int)
    for ts in tt:
        nw=raw['nw'][ts];ss=sol['snapshots'][ts];tm=raw['paper_a_temporal'][int(ts)-1];dw=tm['delta_t_h']*tm['representative_repetitions']*tm['scenario_probability']
        for id,br in nw['branch'].items():
            if br.get('br_status',1):thermal=max(thermal,*(max(0,abs(v)-br.get('rate_a',np.inf)) for v in ss['branch_flows_MW'][id]))
        for table in ['gen','storage','ne_storage']:
            for id,d in nw.get(table,{}).items():
                if 'source_class' not in d:continue
                v=ss['assets'][f'{table}:{id}'];new=v['installed']-d['n0'];Pmw=d['p_block_max_MW']
                if ts==tt[0]:portfolio.append(dict(asset=d['name'],carrier=d['carrier'],region=d['region_id'],source_class=d['source_class'],initial_blocks=d['n0'],installed_blocks=v['installed'],new_blocks=new,new_MW=Pmw*new,new_MVA=d['S_block_MVA']*new,new_MWh=None if table=='gen' else d['e_block']*new))
                if table=='gen' and d['source_class']=='GFL':curtail+=dw*max(0,Pmw*v['online']*d['a_res']-v['dispatch_MW'])
    exp.update({'E.thermal_violation_MW':thermal,'E.curtailment_MWh':curtail,'E.portfolio':portfolio,'E.FOM':dict(status='included_in_registered_annualized_price_when_declared',separately_identifiable=False)})
    for k in ['dual_cone_violation','complementarity_residual']:exp['F.'+k]=st.get('conic_dual',{}).get(k)
    for k in ['model','build_wall_s','solve_wall_s','solver_time_s','relative_gap','bound','barrier_iterations','simplex_iterations','nodes','primal_status','dual_status','termination','solver']:exp[f'F.{k}']=run.get(k)
    return exp
allchecks={};failures=[];roundtrips=[]
for label,root,path in [('historical',R/'historical_evidence',R/'historical_evidence/metrics_final'),('fresh',R,R/'metrics')]:
    suite=root/('accepted_suite' if label=='historical' else 'suite')
    if not (path/'metrics.json').exists():continue
    runs=json.loads((suite/'runs.json').read_text())['runs'];runmap={r['solution_file']:r for r in runs};cache={}
    metrics=json.loads((path/'metrics.json').read_text())['metrics'];reg=json.loads((path/'metric_registry.json').read_text())
    with open(path/'metrics.csv',newline='',encoding='utf-8-sig') as f:
        count=0
        for i,(mr,cr) in enumerate(itertools_zip:=zip(metrics,csv.DictReader(f))):
            assert mr['value_or_null']==json.loads(cr['value_or_null_json']);assert mr['metric_id']==cr['metric_id'];count+=1
    assert count==len(metrics)
    for mr in metrics:
        run=runmap[mr['run_id']];id=mr['metric_id'];key=(label,run['case_id'],run['formulation'],run['relaxed']);ck=(mr['run_id'],mr['snapshot_id']);t=mr['snapshot_id']
        item=allchecks.setdefault((label,id),dict(records=0,compared=0,failures=0,nulls=0,methods=set(),unit=mr['unit']))
        item['records']+=1;item['nulls']+=mr['value_or_null'] is None
        if mr['value_or_null'] is None:assert mr['validity_status']!='valid'
        if ck not in cache:
            raw=json.loads((suite/run['case_id']/'case.json').read_text());sol=json.loads((suite/mr['run_id']).read_text());tt=sorted(sol['snapshots'],key=int)[0] if t=='all' else t
            mm=lookup[(*key,tt)];cache[ck]=(expectations(mm,raw,sol,run,tt,costs[key]),mm)
        exp,mm=cache[ck]
        if id in exp:
            if id=='B.eigenspace' and mr['value_or_null'] is not None:
                V=np.array(mr['value_or_null']);VV=np.array(exp[id]);ok=V.shape==VV.shape and close(V@np.linalg.pinv(V),VV@np.linalg.pinv(VV))
            else:ok=close(mr['value_or_null'],exp[id])
            item['compared']+=1;item['methods'].add('runtime_export_consistency' if id.startswith('F.') else 'raw_input_numpy_or_price_decision_reconstruction')
            if not ok:item['failures']+=1;failures.append(dict(label=label,id=id,case=run['case_id'],formulation=run['formulation'],snapshot=t,actual=mr['value_or_null'],expected=str(exp[id])))
        else:item['methods'].add('schema_status_only_pending_value_oracle')
    roundtrips.append(dict(label=label,metric_ids=len(reg),records=len(metrics),csv_roundtrip=count,registry_coverage=set(reg)=={x['metric_id'] for x in metrics}))
for item in allchecks.values():item['methods']=sorted(item['methods'])
(R/'independent_metric_results.json').write_text(json.dumps(dict(roundtrips=roundtrips,metrics=[dict(label=k[0],id=k[1],**v) for k,v in sorted(allchecks.items())],failures=failures),indent=2))
print('roundtrips',roundtrips,'value failures',len(failures),'value-checked IDs',len({k[1] for k,v in allchecks.items() if v['compared']}))
