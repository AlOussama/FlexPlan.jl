"""Narrow AP5 native-network bridge delta, reusing accepted R2 plane recipe. No solve."""
if not __debug__:raise RuntimeError('Assertions required')
import ast,collections,csv,hashlib,json,pathlib,sys
from fractions import Fraction as F
from array import array
import numpy as np
from scipy.sparse import coo_matrix
R=pathlib.Path('E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01');A=R.parent/'KW08_RE70_G2_PQ_20261125_01';P=R.parent/'SCI_GOLD_AC_DIRECT_02_LOCAL_20261127_02'
out=R/'05_scientific_results/SOC_WR_NATIVE_BRIDGE_CERTIFICATE_TRANSFER.json';inputs={}
def sha(p):return hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
def bind(role,p):inputs[role]={'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size};return p
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def coeff(c,v):
    d=collections.defaultdict(F)
    for i,a in zip(c,v):d[int(i)]+=F(a)
    return {i:a for i,a in d.items() if a}
def inventory(raw):
    result=collections.Counter();rows=[]
    for row in raw['quadratic_rows']:
        if row['linear_columns_zero_based'] or row['sense']!='<' or row['rhs']!=0:continue
        ts=list(zip(row['quadratic_i_zero_based'],row['quadratic_j_zero_based'],row['quadratic_coefficients']))
        cross=[(i,j,F(v)) for i,j,v in ts if i!=j];diag=[(i,F(v)) for i,j,v in ts if i==j]
        if len(cross)==1 and len(diag)==2 and all(v==1 for _,v in diag):result[str(cross[0][2])]+=1;rows.append((row,cross,diag))
    return dict(result),rows
try:
    proof=bind('accepted_R2_proof',P/'recovered_original_proofs/recovered_qcrm_proof_1.py')
    assert sha(proof)=='61bf3bb7924c1204741ad1f02a40747e6d7255c1b27acbcc063e95aea028ef0e'
    bind('accepted_R2_SOC_outer_recipe',P/'reused_outer_math/SOC_BASE_outer/independent_outer_formulation_math.json')
    tree=ast.parse(proof.read_text());selected=[x for x in tree.body if isinstance(x,ast.FunctionDef) and x.name in ('parse','row')]
    assert len(selected)==2
    exec(compile(ast.Module(body=selected,type_ignores=[]),str(proof),'exec'),globals())
    oldfile=bind('old_native_SOC_voltage_target',A/'CONFIRMED_QBOX/SOC-WR_native/native.mps')
    s,sense,rhs,quads,lo,hi,names=parse(oldfile,533155)
    oldprimary=445795;links=collections.defaultdict(list)
    for j in range(s.shape[0]):
        if j in quads:continue
        c,v=row(s,j)
        if sense[j]==b'E':
            for i in c:
                if i>=oldprimary:links[int(i)].append(j)
    oldvoltage={}
    for j,ts in quads.items():
        if len(ts)!=4 or any(i!=k for i,k,v in ts):continue
        heads=[i for i,k,v in ts if v==1];tails=[i for i,k,v in ts if v==-1]
        if len(heads)!=1 or len(tails)!=3:continue
        head=heads[0];side=[t for t in tails if len(links[t])==2 and links[t]==links[head]]
        assert len(side)==1 and sense[j]==b'G' and rhs[j]==0 and lo[head]>=0
        side=side[0];physical=[]
        signs=[]
        for eq in links[head]:
            c,v=row(s,eq);d=coeff(c,v);assert len(d)==3 and rhs[eq]==0
            original=set(d)-{head,side};assert len(original)==1
            orig=original.pop();assert orig<oldprimary
            assert d[head]/d[orig]==-1 and abs(d[side]/d[orig])==1
            physical.append(orig);signs.append(d[side]/d[orig])
        assert sum(signs)==0
        tailphysical=[]
        for tail in set(tails)-{side}:
            assert len(links[tail])==1
            eq=links[tail][0];c,v=row(s,eq);d=coeff(c,v);assert len(d)==2 and rhs[eq]==0
            orig=(set(d)-{tail}).pop();assert orig<oldprimary and -d[orig]/d[tail]==1
            tailphysical.append(orig)
        key=(tuple(sorted(physical)),tuple(sorted(tailphysical)));assert key not in oldvoltage
        oldvoltage[key]=(names[j],head,tails)
    assert len(oldvoltage)==8736
    rawpath=bind('new_frozen_SOC_WR_CAPI',R/'02_native_g3/SOC-WR_gurobi_frozen/g3_actual_native_readback.json');raw=read(rawpath)
    inv,newrows=inventory(raw);assert inv=={'-2':8736}
    aux={i for _,cross,diag in newrows for i in (*cross[0][:2],*(d[0] for d in diag))}
    defs=collections.defaultdict(list)
    for rr in raw['linear_rows']:
        if rr['sense']!='=' or rr['rhs']!=0:continue
        d=coeff(rr['columns_zero_based'],rr['coefficients'])
        if len(d)!=2:continue
        for c in set(d)&aux:
            others=set(d)-{c}
            if abs(d[c])==1 and len(others)==1:
                orig=others.pop();defs[c].append((orig,-d[orig]/d[c]))
    rotation=F(1592262918131443,2251799813685248);gamma=2*rotation*rotation;assert 0<gamma<=1
    newkeys=set();minhead=None
    for rr,cross,diag in newrows:
        endpoints=[];physicaltails=[]
        for c in cross[0][:2]:
            candidates=[x for x in defs[c] if x[1]==rotation and x[0]<oldprimary]
            assert len(candidates)==1;orig,factor=candidates[0];endpoints.append(orig)
            lb=F(raw['lower_bounds'][orig]);assert lb>=0
            minhead=lb if minhead is None else min(minhead,lb)
        for c,v in diag:
            candidates=[x for x in defs[c] if x[1]==1 and x[0]<oldprimary]
            assert len(candidates)==1;physicaltails.append(candidates[0][0])
        key=(tuple(sorted(endpoints)),tuple(sorted(physicaltails)));assert key in oldvoltage and key not in newkeys;newkeys.add(key)
        for c in endpoints+physicaltails:assert raw['lower_bounds'][c]>=lo[c] and raw['upper_bounds'][c]<=hi[c]
    assert newkeys==set(oldvoltage)
    # Existing parser/recipe identifies old h=(w_f+w_t)/2, t=(w_f-w_t)/2.
    # The sole new coefficient delta gives p^2+q^2 <= gamma*w_f*w_t,
    # gamma<=1, w_f,w_t>=0; this implies that SAME accepted old SOC domain.
    planechecks={};normmax=F(0)
    for label in ('BASE','G2'):
        path=bind('accepted_outer_'+label,A/f'GOLD_PAIR_20261126_01/SOC_{label}_outer/native.mps')
        directions={};rowtypes={};rowrhs={};section=None
        with path.open('rb') as fd:
            for line in fd:
                t=line.split()
                if not t:continue
                if not line[:1].isspace():section=t[0];continue
                if section==b'ROWS' and t[1].startswith(b'qc'):rowtypes[t[1]]=t[0]
                elif section==b'COLUMNS':
                    col=int(t[0][1:])
                    for name,value in zip(t[1::2],t[2::2]):
                        if name.startswith(b'qc'):directions.setdefault(name,{})[col]=F(float(value))
                elif section==b'RHS':
                    for name,value in zip(t[1::2],t[2::2]):
                        if name.startswith(b'qc'):rowrhs[name]=F(float(value))
        checked=0
        for name,head,tails in oldvoltage.values():
            d=directions[name];assert rowtypes[name]==b'G' and rowrhs.get(name,F(0))==0
            assert d[head]==1 and set(d)<=set([head]+tails)
            norm=sum((a*a for c,a in d.items() if c!=head),F(0));assert norm<=1
            normmax=max(normmax,norm);checked+=1
        assert checked==8736;planechecks[label]=checked
    inventories={'SOC-WR':inv}
    del raw,s
    for form in ('LPAC','QCRM'):
        rawfile=bind('new_frozen_'+form+'_CAPI',R/f'02_native_g3/{form}_gurobi_frozen/g3_actual_native_readback.json');data=read(rawfile)
        bins,rowsnew=inventory(data);inventories[form]=bins
        assert bins==({} if form=='LPAC' else {'-1':8736})
        del data
    # Accepted primary variable numbering is unchanged on all terminal fields
    # before the newly appended G3-allocation block; voltage pairs match exactly.
    oldt=bind('old_SOC_terminal_roster',A/'CONFIRMED_QBOX/SOC-WR_native/terminal_coordinates.csv')
    newt=bind('new_SOC_G3_terminal_roster',R/'02_native_g3/SOC-WR_gurobi_frozen/terminal_coordinates.csv')
    def starts(path):
        result={}
        for z in csv.DictReader(path.open()):
            if z['type']=='branch':
                h=int(z['hour']);result[h]=min(result.get(h,10**10),int(z['p_index']))
        return result
    assert starts(oldt)==starts(newt) and len(starts(oldt))==168
    boundverdict=bind('saved_SOC_MPS_roundtrip',R/'06_qa/independent_G3_SOC-WR_gurobi_frozen_MPS_ROUNDTRIP.json');assert read(boundverdict)['status']=='PASS'
    for entry in inputs.values():assert sha(pathlib.Path(entry['path']))==entry['sha256']
    result={'status':'PASS','source_commit':'ebaffb57feb3a27f2d7d87b745930664f625f935','scope':'Narrow new-native network-RSOC bridge implication into previously qualified original native SOC/supporting LP; F02 unchanged','optimization_called':False,'actual_new_voltage_products':8736,'actual_old_voltage_SOC_domains':8736,'same_primary_voltage_coordinate_pairs':8736,'preserved_terminal_hour_starts':168,'new_endpoint_factor_exact':str(rotation),'determinant_factor_min_exact':str(gamma),'determinant_factor_max_exact':str(gamma),'factor_at_most_one':True,'minimum_actual_primary_voltage_lower_bound_exact':str(minhead),'existing_voltage_planes_checked':planechecks,'maximum_plane_direction_norm_squared_exact':str(normmax),'all_primary_voltage_bounds_no_wider_than_old_target':True,'bridge_inventory_direct_product_QC_coefficients':inventories,'implication_recipe':'Actual new p^2+q^2 <= gamma*w_f*w_t with gamma=2*r^2<=1 and nonnegative voltage factors implies the same identified old native SOC h^2>=t^2+p^2+q^2, h=(w_f+w_t)/2, t=(w_f-w_t)/2. Reapply already accepted exact norm<=1 supporting-plane recipe to actual archived BASE/G2 planes. No new general theorem or full SOC-QCP/QCRM nesting claim.','LPAC_QCRM_qualification':'No -2 network-RSOC QC inventory in LPAC/QCRM; LPAC has no such products, QCRM retains 8736 original coefficient -1 current products. This same global RSOC bridge change is absent there.','inputs':inputs,'qa_program_sha256':sha(pathlib.Path(__file__))}
except Exception as e:
    result={'status':'FAIL','error':repr(e),'inputs':inputs,'optimization_called':False}
out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(result['status'],result.get('error',''))
if result['status']!='PASS':raise SystemExit(1)
