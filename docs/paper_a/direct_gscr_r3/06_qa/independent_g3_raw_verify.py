"""Independent R3 raw G3 coefficient checks. No solve or frozen-source edit."""
if not __debug__:
    raise RuntimeError('Scientific QA requires assertion checks enabled')
import collections,csv,hashlib,json,pathlib,sys
from fractions import Fraction as Q
ROOT=pathlib.Path(sys.argv[1]); OUT=pathlib.Path(sys.argv[2])
def sha(p):return hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def terms(columns,values):
    assert len(columns)==len(values)
    a=collections.defaultdict(Q)
    for c,v in zip(columns,values):a[int(c)]+=Q(v)
    return {c:v for c,v in a.items() if v}
def expected_tails():
    tails=collections.Counter(); matrix=set()
    with (ROOT/'audit_terms.csv').open(newline='',encoding='utf-8-sig') as f:
        for r in csv.DictReader(f):
            if r['metric']!='M':continue
            h=int(r['hour']);i,j=map(int,r['id'].split('_'));matrix.add((h,i,j))
            if i!=j:
                assert int(r['index'])==0 or Q(float(r['coefficient']))==0
                if int(r['index'])==0 and float(r['coefficient'])!=0:
                    tails[2*Q(float(r['coefficient']))]+=1
    assert matrix=={(h,i,j) for h in range(1,169) for i in range(1,38) for j in range(i,38)}
    assert sum(tails.values())==8736
    return tails
rawpath=ROOT/'g3_actual_native_readback.json'; verdictpath=ROOT/'g3_actual_native_verdict.json'
raw=read(rawpath); verdict=read(verdictpath)
assert verdict['status']=='PASS' and verdict['optimization_performed'] is False
assert verdict['native_cones_exact']==8736 and verdict['native_node_rows_exact']==6216 and verdict['native_q_nonnegative_bounds']==17472
assert sha(rawpath)==verdict['raw_readback_sha256']
assert sha(ROOT/verdict['persisted_native_model'])==verdict['persisted_native_model_sha256']
qcols=set();tails=collections.Counter();linkids=set();budgetincidence=collections.Counter()
if raw['backend']=='Gurobi_actual_C_API':
    ledger=verdict['native_coordinate_ledger'];assert len(ledger)==8736
    assert len({r['native_quadratic_row_zero_based'] for r in ledger})==8736
    aux={c for r in ledger for c in r['native_coordinate_columns_zero_based']}
    assert len(aux)==3*8736
    defs=collections.defaultdict(list)
    for row in raw['linear_rows']:
        if row['sense']!='=':continue
        a=terms(row['columns_zero_based'],row['coefficients'])
        for c in set(a)&aux:
            if abs(a[c])==1:
                defs[c].append(({k:-v/a[c] for k,v in a.items() if k!=c},Q(row['rhs'])/a[c],row['index_zero_based']))
    qrows={r['index_zero_based']:r for r in raw['quadratic_rows']}
    for item in ledger:
        cs=item['native_coordinate_columns_zero_based'];assert len(cs)==3
        qr=qrows[item['native_quadratic_row_zero_based']]
        assert qr['sense']=='>' and Q(qr['rhs'])==0 and not qr['linear_columns_zero_based']
        assert qr['quadratic_i_zero_based']==qr['quadratic_j_zero_based']
        assert terms(qr['quadratic_i_zero_based'],qr['quadratic_coefficients'])=={cs[0]:Q(1),cs[1]:Q(-1),cs[2]:Q(-1)}
        assert Q(raw['lower_bounds'][cs[0]])==0 and raw['upper_bounds'][cs[0]]>=1e100
        heads=[d for d in defs[cs[0]] if len(d[0])==2 and set(d[0].values())=={Q(1)} and d[1]==0]
        assert len(heads)==1
        head=heads[0];endpoints=set(head[0]);assert not endpoints&aux
        sides=[d for d in defs[cs[1]] if set(d[0])==endpoints and set(d[0].values())=={Q(-1),Q(1)} and d[1]==0]
        constants=[d for d in defs[cs[2]] if not d[0]]
        assert len(sides)==len(constants)==1
        for d in (head,sides[0],constants[0]):linkids.add(d[2])
        tails[constants[0][1]]+=1;qcols.update(endpoints)
    assert len(qcols)==17472 and len(linkids)==3*8736
    for col in qcols:assert Q(raw['lower_bounds'][col])==0 and raw['upper_bounds'][col]>=1e100
    budgetrows=0
    for row in raw['linear_rows']:
        a=terms(row['columns_zero_based'],row['coefficients']);qs=set(a)&qcols
        if qs and row['index_zero_based'] not in linkids:
            assert row['sense']=='>' and all(a[c]==-1 for c in qs)
            budgetincidence.update(qs);budgetrows+=1
else:
    assert raw['backend']=='MOSEK_actual_Task_API' and len(raw['cones'])==8736
    assert len({c['acc_index_one_based'] for c in raw['cones']})==8736
    for cone in raw['cones']:
        assert cone['domain_type']=='MSK_DOMAIN_QUADRATIC_CONE' and len(cone['coordinates'])==3
        coordinates=[]
        for c in cone['coordinates']:
            assert Q(c['afe_g'])==0 and Q(c['constant'])==-Q(c['acc_b'])
            coordinates.append((terms(c['columns_one_based'],c['coefficients']),Q(c['constant'])))
        head,side,tail=coordinates
        assert len(head[0])==2 and set(head[0].values())=={Q(1)} and head[1]==0
        assert set(side[0])==set(head[0]) and set(side[0].values())=={Q(-1),Q(1)} and side[1]==0
        assert not tail[0];tails[tail[1]]+=1;qcols.update(head[0])
    assert len(qcols)==17472
    bounds=raw['q_bounds'];assert len(bounds)==17472 and {b['column_one_based'] for b in bounds}==qcols
    for b in bounds:assert b['bound_key']=='MSK_BK_LO' and Q(b['lower'])==0
    assert len(raw['node_rows'])==6216
    budgetrows=0
    for row in raw['node_rows']:
        assert row['bound_key']=='MSK_BK_LO'
        a=terms(row['columns_one_based'],row['coefficients']);qs=set(a)&qcols
        assert all(a[c]==-1 for c in qs)
        budgetincidence.update(qs);budgetrows+=bool(qs)
assert set(budgetincidence)==qcols and set(budgetincidence.values())=={1}
assert tails==expected_tails()
result={'status':'PASS','source_commit':'ebaffb57feb3a27f2d7d87b745930664f625f935','backend':raw['backend'],'native_cones':8736,'q_endpoints':17472,'all_doubled_fixed_tails_match_full_M_ledger':True,'all_q_budget_incidences_exactly_once':True,'node_budget_rows_with_edges':budgetrows,'raw_readback_sha256':sha(rawpath),'native_model_sha256':verdict['persisted_native_model_sha256'],'audit_terms_sha256':sha(ROOT/'audit_terms.csv'),'independent_verifier_sha256':sha(pathlib.Path(__file__)),'scope':'Independent raw coefficient/endpoint/budget incidence review; physical diagonal coefficient identity additionally verified by frozen Julia source-to-native checker; no optimization'}
OUT.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(ROOT.name,'PASS')
