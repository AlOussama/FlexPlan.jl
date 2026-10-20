from pathlib import Path
from fractions import Fraction as Q
import json,sys,hashlib
R=Path(sys.argv[1]);B=Path(sys.argv[2]);O=R/'lp_bounds_raw_currency';O.mkdir(exist_ok=True)
def load(p):return json.loads(p.read_text())
results=[]
for p in sorted((R/'lp_bounds').glob('*_dual_input.json')):
    d=load(p);case=d['case_id'];raw=load(B/'reports/ap3_runs/20261020_macro/accepted_suite'/case/'case.json')
    byname={v['name']:v['index'] for v in d['variables']};c={i:Q(0) for i in byname.values()};constant=Q(0);components={}
    def add(name,v,component):
        if not v:return
        i=byname[name];c[i]+=v;components.setdefault(component,{})[name]=str(v)
    times=sorted(raw['nw'],key=int);base=Q(raw['baseMVA']);components['investment_constant']=Q(0);components['no_load_constant']=Q(0)
    for t in times:
        sn=raw['nw'][t];tm=raw['paper_a_temporal'][int(t)-1]
        dw=Q(tm['delta_t_h'])*Q(tm['representative_repetitions'])*Q(tm['scenario_probability']);ew=Q(tm['event_repetitions'])*Q(tm['scenario_probability'])
        for table in ['gen','storage','ne_storage']:
            for id,a in sn.get(table,{}).items():
                if 'source_class' not in a:continue
                P=Q(a['p_block_max_MW']);key=f'(:{table}, {id})'
                if t==times[0]:
                    v=P*Q(a['cost_inv_per_mw'])*Q(raw.get('investment_period_fraction',1));add(f'{t}_n_block[{key}]',v,'investment');constant-=Q(a['n0'])*v;components['investment_constant']-=Q(a['n0'])*v
                add(f'{t}_su_block[{key}]',P*ew*Q(a['startup_cost_per_mw']),'startup')
                add(f'{t}_sd_block[{key}]',P*ew*Q(a['shutdown_cost_per_mw']),'shutdown')
                sym='pg' if table=='gen' else 'sd' if table=='storage' else 'sd_ne'
                add(f'{t}_{sym}[{id}]',dw*Q(a['marginal_cost'])*base,'generation' if table=='gen' else 'storage')
                if table=='gen':
                    v=dw*Q(a.get('cost',[0,0])[-1]);constant+=v;components['no_load_constant']+=v
    original_c={i:Q(0) for i in c}
    for v in d['objective']['terms']:original_c[v['index']]+=Q(v['coefficient'])
    diff={str(i):str(c[i]-original_c[i]) for i in c if c[i]!=original_c[i]};diff0=constant-Q(d['objective']['constant'])
    d['objective']={'constant':str(constant),'terms':[{'index':i,'coefficient':str(v)} for i,v in c.items() if v]}
    d['objective_scope']='raw binary rational monetary inputs and declared exact products; normalized constraints unchanged'
    (O/p.name).write_text(json.dumps(d,indent=2))
    point=load(R/'exact_primals'/f'{case}_point.json')
    upper=constant+sum((v*Q(point[name]) for name,i in byname.items() if (v:=c[i])),Q(0))
    row={'case_id':case,'raw_objective_constant':str(constant),'emitted_objective_constant':str(constant-diff0),'objective_constant_difference_exact':str(diff0),'objective_constant_difference':float(diff0),'coefficient_difference_exact':diff,'raw_objective_components':{k:str(v) if isinstance(v,Q) else v for k,v in components.items()},'rigorous_raw_currency_UB_exact':str(upper),'rigorous_raw_currency_UB':float(upper),'constraint_scope':'exact normalized Float64 coefficients; not unrounded physical input equations','raw_case_sha256':hashlib.sha256((B/'reports/ap3_runs/20261020_macro/accepted_suite'/case/'case.json').read_bytes()).hexdigest()}
    (O/f'{case}_objective_mapping.json').write_text(json.dumps(row,indent=2));results.append(row)
    print(case,'raw UB',float(upper),'constant difference',float(diff0),flush=True)
(O/'objective_mappings.json').write_text(json.dumps(results,indent=2))
