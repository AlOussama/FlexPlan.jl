"""Exact weak-duality lower bounds for the emitted Float64 BASE-LP.

All input floats denote their exact binary rational values. No residual tolerance
is used for validity. The generated certificate contains the exact multipliers,
finite implied variable bounds and the residual correction.
"""
from fractions import Fraction as Q
from pathlib import Path
import json,sys,hashlib
R=Path(sys.argv[1])
def q(x): return Q(x)
def encode(x): return str(x.numerator)+'/'+str(x.denominator)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def certify(p):
    inp=json.loads(p.read_text()); vs=inp['variables']; ids=[v['index'] for v in vs]
    bounds={i:[None,None] for i in ids}; rows=[]
    for r in inp['rows']:
        terms={t['index']:q(t['coefficient']) for t in r['terms'] if t['coefficient']!=0}
        lo=None if r['lower'] is None else q(r['lower'])-q(r['constant'])
        hi=None if r['upper'] is None else q(r['upper'])-q(r['constant'])
        rows.append((terms,lo,hi,q(r['dual'])))
    # A pair of opposite lower bounds also gives useful upper bounds through
    # shared sum constraints; no assumed UC upper bound is introduced here.
    # Derive only absent bounds, limiting rational expression growth. Every
    # inference is a direct interval consequence of a linear original LP row.
    provenance={}; changes=[]
    for sweep in range(100):
        count=0
        for ri,(a,lo,hi,y) in enumerate(rows):
            for i,ai in a.items():
                for target,rhs in [('upper',hi),('lower',lo)]:
                    if rhs is None:continue
                    bi=1 if (target=='upper')==(ai>0) else 0
                    if bounds[i][bi] is not None:continue
                    total=Q(0); valid=True
                    for j,aj in a.items():
                        if j==i:continue
                        bj=(0 if aj>0 else 1) if target=='upper' else (1 if aj>0 else 0)
                        if bounds[j][bj] is None:valid=False;break
                        total+=aj*bounds[j][bj]
                    if valid:
                        bounds[i][bi]=(rhs-total)/ai
                        provenance[f'{i}:{bi}']={'row':ri,'direction':target,'value':encode(bounds[i][bi]),'sweep':sweep}
                        count+=1
        changes.append(count)
        if not count:break
    c={i:Q(0) for i in ids}
    for t in inp['objective']['terms']:c[t['index']]+=q(t['coefficient'])
    ys=[]
    for a,lo,hi,y in rows:
        if (y>0 and lo is None) or (y<0 and hi is None):y=Q(0)
        ys.append(y)
    zeroed=[];exact_uc_dual_repairs=[]
    # Exact projection of UC transition multipliers into their event-cost
    # interval avoids unnecessary loss of the entire transition dual.
    event_ids={v['index'] for v in vs if ('_su_block[' in v['name'] or '_sd_block[' in v['name']) and bounds[v['index']][1] is None}
    for ri,(a,lo,hi,y) in enumerate(rows):
        if len(a)==1 and next(iter(a)) in event_ids and lo is not None and hi is None:
            ys[ri]=Q(0)
    for ri,(a,lo,hi,y) in enumerate(rows):
        affected=[i for i in a if i in event_ids]
        if not affected or lo is None or hi!=lo:continue
        lower=None;upper=None
        for i in affected:
            other=sum((ys[k]*aa.get(i,Q(0)) for k,(aa,ll,hh,yy) in enumerate(rows) if k!=ri),Q(0))
            cap=(c[i]-other)/a[i]
            if a[i]>0:upper=cap if upper is None else min(upper,cap)
            else:lower=cap if lower is None else max(lower,cap)
        if lower is not None and upper is not None and lower>upper:continue
        new=ys[ri]
        if lower is not None:new=max(new,lower)
        if upper is not None:new=min(new,upper)
        if new!=ys[ri]:exact_uc_dual_repairs.append({'row':ri,'old':encode(ys[ri]),'new':encode(new)})
        ys[ri]=new
    # If a residual points toward an unbounded endpoint, discard connected dual
    # multipliers. This can only weaken the certificate; no variable bound is
    # invented. In these cases simultaneous start/stop variables lack an upper
    # bound. Their nonnegative original costs permit the zero dual choice.
    for _ in range(len(ids)):
        residual=c.copy()
        for (a,lo,hi,y0),y in zip(rows,ys):
            for i,ai in a.items():residual[i]-=y*ai
        missing=[i for i,ri in residual.items() if ri and bounds[i][0 if ri>0 else 1] is None]
        if not missing:break
        touched=[ri for ri,(a,lo,hi,y) in enumerate(rows) if ys[ri] and any(i in a for i in missing)]
        if not touched:break
        for ri in touched:ys[ri]=Q(0)
        zeroed.extend(touched)
    residual=c.copy(); dualvalue=q(inp['objective']['constant']); multipliers=[]
    for ri,((a,lo,hi,y0),y) in enumerate(zip(rows,ys)):
        # For min problems, >= has y>=0; <= has y<=0. Intervals
        # select the endpoint according to sign. Equality y is unrestricted.
        if (y>0 and lo is None) or (y<0 and hi is None):y=Q(0)
        multipliers.append(encode(y))
        if y==0:continue
        b=lo if y>0 else hi
        dualvalue+=y*b
        for i,ai in a.items():residual[i]-=y*ai
    correction=Q(0);missing=[];residuals={}
    for i,ri in residual.items():
        if ri==0:continue
        residuals[str(i)]=encode(ri)
        endpoint=bounds[i][0 if ri>0 else 1]
        if endpoint is None:missing.append(i)
        else:correction+=ri*endpoint
    certified=not missing
    out={'case_id':inp['case_id'],'case_sha256':inp['case_sha256'],'input_sha256':sha(p),'scope':'exact binary rational coefficients of emitted BASE LP; relaxation inclusion must be checked separately','method':'Lagrangian weak duality with exact residual minimization over proven finite bounds','dual_rows_discarded_for_unbounded_residuals':zeroed,'bound_propagation_new_per_sweep':changes,'finite_variable_bounds':{str(i):[None if z is None else encode(z) for z in b] for i,b in bounds.items()},'bound_provenance':provenance,'exact_row_multipliers':multipliers,'exact_stationarity_residuals':residuals,'dual_value_exact':encode(dualvalue),'residual_correction_exact':encode(correction),'uncorrected_dual_value':float(dualvalue),'residual_correction':float(correction),'missing_required_bounds':missing,'rigorous_LB_for_serialized_LP':certified,'certified_LB_exact':encode(dualvalue+correction) if certified else None,'certified_LB':float(dualvalue+correction) if certified else None,'solver_numerical_bound':inp['stats']['bound']}
    out['exact_uc_dual_repairs']=exact_uc_dual_repairs
    op=p.with_name(p.stem.replace('_dual_input','_exact_LB')+'.json');op.write_text(json.dumps(out,indent=2))
    print(inp['case_id'],'certified',certified,'missing',len(missing),'correction',float(correction),'LB',out['certified_LB'],flush=True)
    return {k:out[k] for k in ['case_id','case_sha256','input_sha256','rigorous_LB_for_serialized_LP','certified_LB','missing_required_bounds','residual_correction']}
results=[certify(p) for p in sorted(R.glob('*_dual_input.json'))]
(R/'exact_bounds_summary.json').write_text(json.dumps(results,indent=2))
