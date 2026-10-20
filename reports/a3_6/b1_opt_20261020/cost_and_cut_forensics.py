import json,pathlib,ast,sys,copy,collections,math
from fractions import Fraction as Q
R=pathlib.Path(sys.argv[1]);B=pathlib.Path(sys.argv[2]);A=pathlib.Path(sys.argv[3])
def load(p):return json.loads(p.read_text())
source=ast.parse((A/'independent_reference_oracle.py').read_text())
node=next(n for n in source.body if isinstance(n,ast.FunctionDef) and n.name=='economics')
ns={};exec(compile(ast.Module(body=[node],type_ignores=[]),'pinned_cost_oracle','exec'),ns);eco=ns['economics']
old=load(A/'integer_global_bounds_and_objective_audit.json');out=[]
for row in old:
    raw=load(B/'reports/ap3_runs/20261020_macro/accepted_suite'/row['case_id']/'case.json');points=[]
    for fid in ['G0','G3']:
        w=load(R/'input/integer_best'/f'full_witness_{row["case_id"]}_{fid}.json');s=w['solution'];projected=copy.deepcopy(s)
        for state in projected['snapshots'].values():
            for v in state['assets'].values():
                for k in ['installed','online','startup','shutdown']:v[k]=round(v[k])
        original=eco(raw,s);rounded=eco(raw,projected)
        points.append({'formulation':fid,'original':original,'integer_projected_cost_diagnostic':rounded,'projection_cost_change':rounded['total']-original['total'],'projection_signed_gap_to_old_LB':rounded['total']-row['original_reference_lower_claim'],'rigorous_UB':False,'projection_is_not_a_recovered_exact_primal':True})
    out.append({'case_id':row['case_id'],'case_sha256':row['case_sha256'],'historical_lower_claim':row['original_reference_lower_claim'],'points':points})
(R/'cost_integer_projection_diagnostics.json').write_text(json.dumps(out,indent=2))
# Independently expand vector nonnegative constraints into scalar rows and
# evaluate the *changed* LP after HiGHS' documented ingestion filter.
m=load(R/'experiments/stages/oa_frozen.mof.json');w=load(R/'experiments/stages/oa_full_witness.json');vals={m['variables'][p['index']-1]['name']:p['value'] for p in w}
rows=[]
for ci,c in enumerate(m['constraints']):
    f=c['function'];s=c['set'];typ=f['type']
    if typ=='VectorAffineFunction':
        ts=collections.defaultdict(list)
        for t in f['terms']:ts[t['output_index']-1].append(t['scalar_term'])
        assert s['type']=='Nonnegatives'
        for i,const in enumerate(f['constants']):rows.append((f'{ci}:{i}',ts[i],const,0.,None))
    elif typ=='ScalarAffineFunction':rows.append((str(ci),f['terms'],f['constant'],s.get('value',s.get('lower')),s.get('value',s.get('upper'))))
cutrows=[]
for key,ts,c,l,u in rows:
    tiny=[t for t in ts if 0<abs(t['coefficient'])<=1e-9]
    if not tiny:continue
    v=c+math.fsum(t['coefficient']*vals[t['variable']] for t in ts)
    dropped=math.fsum(t['coefficient']*vals[t['variable']] for t in tiny);vd=v-dropped
    violation=lambda z:max(0.,0. if l is None else l-z,0. if u is None else z-u)
    cutrows.append({'row':key,'terms':ts,'constant':c,'lower':l,'upper':u,'dropped_terms_at_1e-9':tiny,'value_original':v,'value_after_filter':vd,'violation_original':violation(v),'violation_after_filter':violation(vd),'removed_contribution':dropped})
(R/'oa_coefficient_filter_forensics.json').write_text(json.dumps({'affected_rows':cutrows,'count':len(cutrows),'max_original_violation':max([r['violation_original'] for r in cutrows],default=0),'max_filtered_violation':max([r['violation_after_filter'] for r in cutrows],default=0)},indent=2))
for r in out:print(r['case_id'],[(p['formulation'],p['projection_cost_change'],p['projection_signed_gap_to_old_LB']) for p in r['points']])
print('Filtered OA rows',len(cutrows),'max witness violation after filter',max([r['violation_after_filter'] for r in cutrows],default=0))
