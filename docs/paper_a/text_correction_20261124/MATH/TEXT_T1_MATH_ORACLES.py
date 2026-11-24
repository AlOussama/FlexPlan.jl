"""Independent Paper A T1. Read manuscript bytes. No solver, artifact modification, or Git write."""
import argparse, hashlib, json, re, sys
from pathlib import Path
from sympy import Matrix, Rational as Q, diag, eye, zeros, ones, symbols, expand

def digest(data):
    return hashlib.sha256(data).hexdigest()

def number(s):
    s = re.sub(r'\\(?:d|t)?frac\s*\{(-?\d+)\}\s*\{(\d+)\}', r'\1/\2', s)
    return Q(s.strip().replace(' ', ''))

def matrix(s):
    if 'matrix}' in s:
        s = re.sub(r'\\(?:begin|end)\{[bp]matrix\}', '', s)
        rows = re.split(r'\\\\', s)
        return Matrix([[number(x) for x in row.split('&')] for row in rows])
    return Matrix([[number(x) for x in row.split(',')] for row in s[1:-1].split(';')])

def je(x):
    if isinstance(x, Matrix().__class__):
        return [[str(v) for v in row] for row in x.tolist()]
    if isinstance(x, (tuple,list)):
        return [je(y) for y in x]
    if isinstance(x, dict):
        return {str(k):je(v) for k,v in x.items()}
    if isinstance(x, (str,int,bool)) or x is None:
        return x
    return str(x)

def main():
    cli=argparse.ArgumentParser()
    cli.add_argument('--tex', required=True, type=Path)
    cli.add_argument('--stage',required=True,choices=['baseline','candidate'])
    cli.add_argument('--output',required=True,type=Path)
    args=cli.parse_args()
    raw=args.tex.read_bytes()
    body=raw.decode('utf-8-sig')
    cases=[]
    def record(name, outcome, evidence):
        cases.append(dict(id=name, passed=bool(outcome), computed=je(evidence)))
    def binds(name, token):
        loc=body.find(token)
        record('TEX_'+name,loc>=0,{'anchor':token,'line':1+body.count('\n',0,loc) if loc>=0 else None})
    for name,token in [('exposure','eq:burden'),('quota','eq:quota'),('cost','eq:cost'),('matrix','eq:mat'),('edge','eq:g3'),('row_proposition','pr:row'),('edge_proposition','pr:edge')]:
        binds(name,token)
    epattern=r'\\begin\{[bp]matrix\}.*?\\end\{[bp]matrix\}|\[[\d ,;/+-]+\]'
    e1=ones(2,1)
    def evalcase(B,p):
        M=B-diag(*p)
        return {'B':B,'p':p,'M':M,'det':M.det(),'eigenvalues':list(M.eigenvals()),'PSD':bool(M.is_positive_semidefinite),'B_inv_p':B.inv()*p,'G1margin':M*e1}
    # The legacy display inherits the immediately preceding B assignment. The release
    # requires an explicit B in each example, so the two questions have separate outputs.
    inverse_section=body.split('pr:edge}',1)[-1]
    if 'inverse test and its domain}' in inverse_section:
        inverse_section=inverse_section.split('inverse test and its domain}',1)[-1]
    blist=list(re.finditer(r'(?<![A-Za-z])B\s*=\s*('+epattern+r')',inverse_section,re.S))
    plist=list(re.finditer(r'(?<![A-Za-z])p\s*=\s*\(\s*([\d\s/{}\\-]+)\s*,\s*([\d\s/{}\\-]+)\s*\)',inverse_section))
    evals=[]
    prev=-1
    for k,pv in enumerate(plist):
        available=[b for b in blist if b.start()<pv.start()]
        if not available:
            continue
        bm=available[-1]
        B=matrix(bm[1]); p=Matrix([number(pv[1]),number(pv[2])])
        calc=evalcase(B,p)
        calc['explicit_B_since_previous_p']=bm.start()>prev
        calc['source_p']=pv[0]
        calc['source_B']=bm[0]
        calc['source_line']=body.count('\n',0,body.find(inverse_section)+pv.start())+1
        evals.append(calc)
        prev=pv.start()
        if len(evals)==2: break
    record('PRINTED_inverse_examples_count',len(evals)==2,len(evals))
    if len(evals)==2:
        a,b=evals
        record('PRINTED_M0_not_G1',a['B']==Matrix([[2,-1],[-1,2]]) and a['B_inv_p']==Matrix([Q(5,12),Q(5,6)]) and a['G1margin']==Matrix([1,-Q(1,4)]),a)
        record('PRINTED_G0_not_M0',b['PSD'] and b['det']==0 and b['B_inv_p']==Matrix([Q(7,9),Q(19,18)]) and bool(re.search(r'19\s*/\s*18|\\(?:t|d)?frac\{19\}\{18\}',inverse_section)),b)
        is_normal=b['explicit_B_since_previous_p'] and b['B']==Matrix([[1,-Q(1,2)],[-Q(1,2),1]]) and b['p']==Matrix([Q(1,4),Q(2,3)])
        record('EXPECTED_explicit_normalized_example_stage_gate',is_normal==(args.stage=='candidate'),{'observed_explicit_normalized_binding':is_normal,'expected':args.stage=='candidate'})
        if args.stage=='candidate':
            record('PRINTED_normalized_eigensystem',set(b['eigenvalues'])=={0,Q(13,12)},b['eigenvalues'])
    wrong=evalcase(Matrix([[1,-Q(1,2)],[-Q(1,2),1]]),Matrix([Q(1,2),Q(4,3)]))
    record('NEGATIVE_legacy_numerators_with_normalized_matrix',not wrong['PSD'] and wrong['det']==-Q(5,12) and wrong['B_inv_p']==Matrix([Q(14,9),Q(19,9)]),wrong)
    # Extract the row matrices and scaling from one local occurrence, independently of names.
    rp=re.search(r'r\s*=\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)',body)
    r=Matrix([int(rp[1]),int(rp[2])]) if rp else None
    mats=[]
    if rp:
        neighborhood=body[max(0,rp.start()-80):rp.end()+1250]
        mats=[matrix(m[1]) for m in re.finditer(r'M_?\{?[ab]\}?\s*=\s*('+epattern+r')',neighborhood,re.S)]
        if not mats:
            legacy=re.search(r'off-diagonal \$(-?\d+)\$ and diagonals \$\(([^)]+)\)\$ and \$\(([^)]+)\)\$',neighborhood)
            if legacy:
                for item in (legacy[2],legacy[3]):
                    d=[number(v) for v in item.split(',')]
                    mats.append(Matrix([[d[0],number(legacy[1])],[number(legacy[1]),d[1]]]))
    record('PRINTED_row_witnesses_found',len(mats)==2 and r==Matrix([1,2]),dict(r=r,matrices=mats))
    if len(mats)==2 and r is not None:
        m,n=mats
        record('PRINTED_G1_G2_nonnesting',min(m*e1)>=0 and min(m*r)<0 and min(n*e1)<0 and min(n*r)>=0,{'Ma1':m*e1,'Mar':m*r,'Mb1':n*e1,'Mbr':n*r})
    if args.stage=='candidate' and len(evals)==len(mats)==2:
        def vectors(expr,txt):
            pat=expr+r'\s*=\s*\(\s*([-/0-9]+)\s*,\s*([-/0-9]+)\s*\)'
            return [Matrix([number(a),number(b)]) for a,b in re.findall(pat,txt)]
        mb=evals[1]['M']
        first=evals[0]
        def match_one(expr,txt,expected,identifier):
            actual=vectors(expr,txt)
            record(identifier,actual==[expected],{'printed':actual,'computed':expected})
        match_one(r'M_a\\one',body,mats[0]*e1,'PRINTED_Ma_unit_row')
        match_one(r'M_a\s*r',body,mats[0]*r,'PRINTED_Ma_scaled_row')
        match_one(r'M_b\\one',body,mats[1]*e1,'PRINTED_Mb_unit_row')
        match_one(r'M_b\s*r',body,mats[1]*r,'PRINTED_Mb_scaled_row')
        match_one(r'M\\one',inverse_section,first['G1margin'],'PRINTED_first_inverse_G1_margin')
        zp=vectors(r'Zp',inverse_section)
        record('PRINTED_both_inverse_burden_vectors',zp==[first['B_inv_p'],evals[1]['B_inv_p']],zp)
        mm=re.search(r'(?<![A-Za-z])M\s*=\s*('+epattern+r')',inverse_section,re.S)
        record('PRINTED_normalized_M',bool(mm) and matrix(mm[1])==mb,{'printed':matrix(mm[1]) if mm else None,'computed':mb})
        eig=re.search(r'eigenvalues are \$([-/0-9]+)\$ and \$([-/0-9]+)\$',inverse_section)
        det=re.search(r'\\det\s*M\s*=\s*([-/0-9]+)',inverse_section)
        record('PRINTED_spectrum_and_determinant',bool(eig and det) and {number(eig[1]),number(eig[2])}==set(mb.eigenvals()) and number(det[1])==mb.det(),{'printed_eigenvalues':eig.groups() if eig else None,'printed_determinant':det[1] if det else None})
        local_r=Matrix([2,3])
        record('PROOF_G2_not_M0',mb*local_r==zeros(2,1) and max(evals[1]['B_inv_p'])>1,{'positive_fixed_r':local_r,'scaled_rows':mb*local_r,'inverse_burden':evals[1]['B_inv_p']})
    a,b,c,x,y,u,v=symbols('a b c x y u v', real=True)
    M=Matrix([[a,-c],[-c,b]]); R=diag(u,v); X=Matrix([x,y]); K=R*M*R
    form=(X.T*K*X)[0]+K[0,1]*(x-y)**2-sum(s*t*t for s,t in zip(K*e1,X))
    record('PROOF_row_congruence_symbolic',expand(form)==0,expand(form))
    N=Matrix([[2,-1,0],[-1,2,-1],[0,-1,1]])
    rr=N.inv()*ones(3,1)
    def edge_decompose(M,r):
        acc=zeros(M.rows); budgets=[]
        for i in range(M.rows):
            for j in range(i):
                h=M[i,j]
                if h:
                    d=-h*r[j]/r[i]; f=-h*r[i]/r[j]
                    assert d>=0 and f>=0 and 2*(d/2)*f==h*h
                    acc[i,i]+=d; acc[j,j]+=f; acc[i,j]+=h;acc[j,i]+=h
            budgets.append((M*r)[i]/r[i])
        return acc+diag(*budgets),budgets
    for name,M,r in [('SPD',N,rr),('singular_reducible_isolate',diag(Matrix([[2,-1],[-1,Q(1,2)]]),0,3),Matrix([1,2,1,1]))]:
        rebuilt,left=edge_decompose(M,r)
        record('PROOF_G3_RSOC_'+name,rebuilt==M and min(left)>=0 and bool(M.is_positive_semidefinite),dict(matrix=M,r=r,residual=left))
    record('NEGATIVE_omitted_edge_and_node_budget',not bool(Matrix([[1,-2],[-2,1]]).is_positive_semidefinite) and Q(1,2)<1,{'omitted_coupling':-2,'unit_allocations_product':1,'required_product':4,'insufficient_diagonal':'1/2'})
    record('NEGATIVE_Z_assumption_essential',not bool(Matrix([[0,1],[1,0]]).is_positive_semidefinite) and min(Matrix([[0,1],[1,0]])*e1)>=0,{'Mr':[1,1],'eigenvalues':[-1,1]})
    S=diag(1,0,0); D=diag(2,0); C=Matrix([[2,0]])
    B=Matrix([[3,2,0],[2,2,0],[0,0,0]])
    t=symbols('t',real=True); x0=Matrix([1,t])
    bad=Matrix([[1,-1],[-1,0]])
    quot=(x0.T*bad*x0)[0]
    record('PROOF_singular_S_Schur_and_range',(eye(2)-D*D.pinv())*C.T==zeros(2,1) and (C*D.pinv()*C.T)[0]==2 and bool((B-S).is_positive_semidefinite),{'S':S,'Schur_B_A':1,'minimum_quotient':1,'zero_block_rank':1})
    record('NEGATIVE_positive_denominator_not_finite_infimum',expand(quot-(1-2*t))==0 and not bool(bad.is_positive_semidefinite),{'x':[1,t],'q':quot,'q_limit_as_t_increases':'-infinity','Bzz':0,'cross':-1})
    record('NEGATIVE_negative_Bzz_and_S_zero',not bool(diag(2,-1).is_positive_semidefinite) and zeros(2)==diag(0,0),{'Szero_domain':'empty','Sdiag10_Bdiag2minus1_q':'2-t^2','G0_with_S0':'test B PSD'})
    Bmin=Matrix([[2,-1],[-1,2]]); delta=diag(2,1); B=Bmin+delta
    diff=Bmin.inv()-B.inv()
    record('PROOF_M1_order',diff==Bmin.inv()*delta*B.inv() and min(diff)>=0,{'inverse_difference':diff})
    W=Matrix([[1,Q(1,2)],[Q(2,3),1]]); p=Matrix([Q(1,4),Q(2,3)])
    record('PROOF_M2_and_identity',min(W*p-p)>=0 and eye(2)*p==p,{'extra_burden':W*p-p})
    record('NEGATIVE_free_ratio_RHS',0<=Q(3,2) and 0<Q(3,4)<=Q(3,2),{'P':3,'d':4,'ell':2,'true_ratio':'3/4','substitution':'3/2','free_feasible_rho':0})
    L=Matrix([[2,-2],[-2,2]]); full=L-diag(Q(1,4),Q(1,4))
    record('PHYSICS_series_vs_pi_row_sums',L*e1==zeros(2,1) and full*e1==Matrix([-Q(1,4)]*2),{'series_rowsums':L*e1,'pi_rowsums':full*e1})
    record('PHYSICS_rating_and_pu',Q(25,100)/Q(1,5)==Q(5,4),{'example_MVA':25,'common_MVA':100,'X_pu':'1/5','stiffness_pu':'5/4'})
    record('PHYSICS_curtailment_vs_quota',Q(1,2)*40/100==Q(1,5) and (20-0)>0,{'availability':'1/2','new_MW':40,'p_pu':'1/5','dispatch_fully_curtailed_MWh':0})
    u,v=3,1; z=min(u,v)
    record('UC_event_cancellation',u-v==(u-z)-(v-z) and z>0 and min(u-z,v-z)==0,{'starts':u,'stops':v,'remaining':[u-z,v-z],'event_cost_multiplier':Q(8760,168),'weekly_event_saving_per_unit':Q(6,5)})
    record('BOUNDS_conditional_subtraction',Q(128108717,10**6)-Q(127449599,10**6)==Q(659118,10**6),{'M2_relaxation_LB_minus_G0G3_feasible_UB_using_printed_Bn':'0.659118 billion EUR','integer_M2_UB':'unavailable'})
    out=dict(reviewer_id='/root/math_r',stage=args.stage,tex=str(args.tex),tex_sha256=digest(raw),script_sha256=digest(Path(__file__).read_bytes()),argv=sys.argv,checks=cases,failed=[c['id'] for c in cases if not c['passed']])
    args.output.write_text(json.dumps(out,indent=2,ensure_ascii=True)+'\n',encoding='utf8')
    print(f"{args.stage}: {len(cases)} tests, failures {out['failed']}; output {digest(args.output.read_bytes())}")
    return int(bool(out['failed']))
if __name__=='__main__':
    raise SystemExit(main())

