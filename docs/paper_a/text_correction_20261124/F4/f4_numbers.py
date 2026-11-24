"""Check published numerical statements from independent Decimal calculations, inspect actual matplotlib artists."""
import csv,json,re,hashlib,math,runpy
from pathlib import Path
from decimal import Decimal as D,ROUND_CEILING,ROUND_FLOOR
def rd(p):
    with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def H(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def jf(p):return json.loads(p.read_bytes())
def outward(x,places,lower):return x.quantize(D(1).scaleb(-places),rounding=ROUND_FLOOR if lower else ROUND_CEILING)
PANEL=[(q,m) for q in [50,60,70] for m in (['BASE','G1','G2'] if q==70 else ['BASE','G1'])]
def audit(p,g):
    ds=rd(g/'02_FINAL_WEEK168_RESULT_MATRIX.csv');bs=rd(g/'02_OBJECTIVE_AND_SOLVER_BOUNDS.csv')
    assert len(ds)==len(bs)==14 and len({x['row_id'] for x in ds})==14
    assert all((p/a).read_bytes()==(g/b).read_bytes() for a,b in [('04_reviewed_points.csv','02_FINAL_WEEK168_RESULT_MATRIX.csv'),('04_reviewed_bounds.csv','02_OBJECTIVE_AND_SOLVER_BOUNDS.csv'),('04_additional_methods.csv','03_QUALIFIED_REAL_METHOD_RESULTS.csv')])
    rows={x['row_id']:x for x in ds};bnd={x['row_id']:x for x in bs}
    def r(q,m,t):return rows[f'WK08-{q}-{m}-{t}']
    def b(q,m,t,which):return D(bnd[f'WK08-{q}-{m}-{t}'][which])
    def endpoint(q,m,t,d):return b(q,m,t,'numeric_'+d+'_EUR2025')/D(10**9)
    def delta(q,which):return endpoint(q,'G1','MILP',which)-endpoint(q,'BASE','MILP','ub' if which=='lb' else 'lb')
    table=(p/'04_results.tex').read_text(encoding='utf8');ab=(p/'04_result_abstract.tex').read_text(encoding='utf8');con=(p/'04_result_conclusion.tex').read_text(encoding='utf8');ex=(p/'04_qualified_extensions.tex').read_text(encoding='utf8');gl=(p/'04_numerical_limits.tex').read_text(encoding='utf8');main=(p/'04_PAPER_A.tex').read_text(encoding='utf8')
    def present(t,values):
        for v in values:assert str(v) in t,('missing',v,t[:160])
    report={'cohort':{},'printed_rows':{},'charts':{},'G3_attempts':[]}
    for id,x in rows.items():
        assert x['numeric_solver_status']=='OPTIMAL'
        ver='13.0.3' if id=='WK08-70-G2-MILP' else '12.0.3'
        assert x['solver_version']==ver
        qa=g/'02_final_rows'/(id+'.json')
        assert H(qa)==x['original_replay_sha256']
        rr=jf(qa);assert rr['case_sha256']==x['input_case_sha256']
        def val(k):return D(x[k])
        assert abs(val('actual_RE_MWh')/val('actual_load_MWh')*100-val('actual_RE_share_pct'))<D('1e-9')
        assert abs(val('raw_week_OPEX_EUR2025')*8760/168+val('CAPEX_EUR2025')-val('annualized_total_EUR2025'))<D('.001')
        for c in ['wind','PV','GFL_BESS','GFM_BESS']:
            assert abs(val(c+'_baseline_MW')+val(c+'_added_MW')-val(c+'_total_MW'))<D('1e-7')
        for c in ['G0','G1','G2','M0']:
            assert int(x[c+'_defined_hours'])+int(x[c+'_undefined_hours'])==168 and int(x[c+'_failed_hours'])<=int(x[c+'_defined_hours'])
        report['cohort'][id]={'status':x['numeric_solver_status'],'version':ver,'case_sha':x['input_case_sha256'],'primal':x['original_primal_sha256'],'qa':H(qa),'dimension':rr['original_point_dimensions']}
    matches=re.findall(r'^(\d+)\\% & (BASE|G1|G2) & ([\d.]+) & ([\d.]+) & ([\d.]+) & ([\d.]+)',table,re.M);assert len(matches)==len(PANEL)
    for (q0,m,lp,lb,ub,gap),(q,method) in zip(matches,PANEL):
        assert int(q0)==q and m==method
        want=[outward(endpoint(q,m,'LP','lb'),4,True),outward(endpoint(q,m,'MILP','lb'),4,True),outward(endpoint(q,m,'MILP','ub'),4,False)]
        assert list(map(D,[lp,lb,ub]))==want and D(gap)==(100*b(q,m,'MILP','relative_gap_fraction')).quantize(D('.001'))
        report['printed_rows'][q0+m]=[lp,lb,ub,gap]
    wins=re.findall(r'\$\[([\d.]+),([\d.]+)\]\$',table);assert len(wins)==3
    for q,(lo,hi) in zip([50,60,70],wins):assert 0<D(lo)==outward(delta(q,'lb'),3,True)<D(hi)==outward(delta(q,'ub'),3,False)
    present(ab,[outward(delta(70,'lb'),2,True),outward(delta(70,'ub'),2,False)])
    g2=r(70,'G2','MILP');g1=r(70,'G1','MILP');d=(endpoint(70,'G1','MILP','ub')-endpoint(70,'G2','MILP','ub'))*1000
    assert max(endpoint(70,m,'MILP','lb') for m in ['G1','G2'])<min(endpoint(70,m,'MILP','ub') for m in ['G1','G2'])
    present(table,[f'{D(g2["CAPEX_EUR2025"])/D(1e9):.3f}',f'{D(g2["raw_week_OPEX_EUR2025"])/D(1e6):.2f}',f'{D(g2["annualized_week_OPEX_EUR2025"])/D(1e9):.3f}',f'{D(g2["actual_RE_share_pct"]):.3f}',f'{d:.1f}'])
    present(con,[f'{d:.1f}',g2['G1_failed_hours'],'168'])
    events=[x for x in ds if int(x['SU_SD_positive_overlaps'])]
    assert [x['row_id'] for x in events]==['WK08-50-BASE-MILP','WK08-60-BASE-MILP']
    present(table,[f"{D(x['avoidable_overlap_week_EUR2025']):,.2f}" for x in events]+['3 and 1'])
    for m in ['BASE','G1','G2']:
        for aa,bb in [('GFL_BESS','GFM_BESS'),('wind','PV')]:
            order=['GFL_BESS','wind'].index(aa)
            pair=re.findall(r'([\d.]+)/([\d.]+) GW \('+m+r'\)',table)[order]
            for printed,k in zip(pair,(aa,bb)):
                assert abs(D(printed)-D(r(70,m,'MILP')[k+'_added_MW'])/1000)<=D('.005')
    base=[x for x in ds if x['model']=='BASE' and int(x['M0_defined_hours'])]
    assert len(base)==1 and base[0]['M0_failed_hours']==base[0]['M0_defined_hours']=='12'
    present(table,['12 of 168','12 fail',g2['G1_failed_hours']+' hours',g2['M0_failed_hours']+' of 168',g2['G2_failed_hours']+' hours'])
    present(main,['Gurobi 12.0.3','13 cases','70\\% G2 MILP used Gurobi 13.0.3','12,432'])
    extensions=rd(p/'04_additional_methods.csv')
    ub=D(next(z for z in extensions if z['method']=='G3' and z['mode']=='integer_witness')['objective_EUR2025'])
    lb=D(next(z for z in extensions if z['method']=='M2' and z['mode']=='relaxed')['qualified_numerical_bound_EUR2025'])
    present(ex,[outward(ub/D(10**9),6,False),outward(lb/D(10**9),6,True),f'{(lb-ub)/D(10**6):.2f}'])
    assert len([z for z in extensions if z['method']=='M2' and z['mode']=='integer' and 'NO_INTEGER_PRIMAL' in z['state']])==2
    nmap={z['code']:z for z in jf(g/'03_GATED_SOLVER_NEGATIVES.json')['negative_runs'] if z['method']=='G3'}
    g3=rd(p/'04_g3_attempts.csv');assert set(nmap)=={x['code'] for x in g3} and len(g3)==8
    for x in g3:
        n=nmap[x['code']];ck=n['original_check'] or {};raw=n.get('QA') or n['summary']
        assert H(Path(raw['path']))==raw['sha256']==x['evidence_sha256']
        assert x['case_sha256']==n['case_sha256'] and x['state']==n['state']
        assert (str(ck['maximum_constraint_distance']) if ck else '')==x['distance']
        assert x['code'][:8] in gl
        if ck:present(gl,[f"{float(x['distance']):.3g}"])
        report['G3_attempts'].append({'code':x['code'],'case':x['case_sha256'],'evidence':raw,'original_check':ck})
    report['extra_bounds']={'UB':str(ub),'LB':str(lb),'EUR_difference':str(lb-ub)}
    return report
def artists(p,g):
    import matplotlib.pyplot as plt
    import numpy as np
    ns=runpy.run_path(str(p/'04_build_results.py'));rows=rd(g/'02_FINAL_WEEK168_RESULT_MATRIX.csv');bs=rd(g/'02_OBJECTIVE_AND_SOLVER_BOUNDS.csv')
    md={(x['model'],int(x['quota_pct']),x['integrality']):x for x in rows}; bd={k:next(b for b in bs if b['row_id']==v['row_id']) for k,v in md.items()}
    seen={}
    def check(fig,name):
        aa=fig.axes
        if 'cost' in name:
            logits=[]
            for i,q in enumerate([50,60,70]):
                a=aa[i]; ms=[m for qq,m in PANEL if qq==q]; assert a.get_title()==f'{q}% quota' and [t.get_text() for t in a.get_xticklabels()]==ms
                for j,m in enumerate(ms):
                    seg,d,u,l=a.lines[j*4:j*4+4]
                    lo,up=[float(bd[(m,q,'MILP')][col])/1e9 for col in ['numeric_lb_EUR2025','numeric_ub_EUR2025']];lp=float(bd[(m,q,'LP')]['numeric_lb_EUR2025'])/1e9
                    assert np.allclose(seg.get_ydata(),[lo,up],atol=1e-10,rtol=0)
                    for art,mark,n in [(d,'v',lo),(u,'^',up),(l,'_',lp)]:
                        assert art.get_marker()==mark and abs(art.get_ydata()[0]-n)<1e-10
                    logits.append([q,m,lo,up,lp])
            assert 'Billion EUR' in aa[0].get_ylabel();seen[name]=logits
        elif 'portfolio' in name:
            vals=[]
            for ax,metrics in zip(aa,[('GFL_BESS','GFM_BESS'),('wind','PV')]):
                assert ax.get_xlabel()=='Added capacity (GW)'
                for bars,c in zip(ax.containers,metrics):
                    for bar,(q,m) in zip(bars,PANEL):
                        n=float(md[m,q,'MILP'][c+'_added_MW'])/1000;assert abs(bar.get_width()-n)<1e-9;vals.append((q,m,c,n))
            assert len(vals)==28;seen[name]=vals
        else:
            ax=aa[0];zs=ax.images[0].get_array();labels=[x.get_text() for x in ax.texts];assert zs.shape==(14,4) and len(labels)==56
            vals=[]
            for i,(q,m,t) in enumerate((q,m,t) for q,m in PANEL for t in ['LP','MILP']):
                for j,c in enumerate(['G1','G2','G0','M0']):
                    x=md[m,q,t];n=int(x[c+'_failed_hours']);dom=int(x[c+'_defined_hours']);show=str(n) if j<3 else (f'{n}/{dom}' if dom else 'n/a')
                    assert (np.ma.is_masked(zs[i,j]) if not dom else zs[i,j]==n) and labels[i*4+j]==show;vals.append([q,m,t,c,n,dom,show])
            seen[name]=vals
        plt.close(fig)
    for nm,args in [('plot_intervals',(md,bd)),('plot_portfolios',(md,)),('plot_diagnostics',(md,))]:
        f=ns[nm];f.__globals__['save']=check;f(*args)
    assert len(seen)==3
    return seen