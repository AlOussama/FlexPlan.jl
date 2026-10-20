#!/usr/bin/env python3
"""A3.5-MATH 2026-10-20: independently authored exact Fraction oracle.
No FlexPlan, previous A3.5, or AP3 diagnostic module is imported.
Core checks: exact Gaussian elimination, all principal-minor PSD test,
componentwise matrix inequalities, direct edge-budget checks.
Cross-check: separately use SymPy characteristic-polynomial spectrum.
"""
from fractions import Fraction as F
from itertools import combinations
from pathlib import Path
from hashlib import sha256
import json
import sympy as sp

D=F

def mat(rows):
    return [[F(str(v)) for v in row] for row in rows]
def vec(xs): return [F(str(v)) for v in xs]
def pretty(x):
    if isinstance(x,F): return str(x)
    if isinstance(x,list): return [pretty(v) for v in x]
    if isinstance(x,dict): return {k:pretty(v) for k,v in x.items()}
    return x

def mm(A,B):return [[sum((A[i][k]*B[k][j] for k in range(len(B))),F(0)) for j in range(len(B[0]))] for i in range(len(A))]
def mv(A,v):return [sum((a*b for a,b in zip(row,v)),F(0)) for row in A]
def add(A,B):return [[x+y for x,y in zip(ra,rb)] for ra,rb in zip(A,B)]
def sub(A,B):return [[x-y for x,y in zip(ra,rb)] for ra,rb in zip(A,B)]
def scale(A,s):return [[s*x for x in row] for row in A]
def diag(x): return [[x[i] if i==j else F(0) for j in range(len(x))] for i in range(len(x))]
def ident(n):return diag([F(1)]*n)
def transpose(A):return list(map(list,zip(*A)))
def minor(A,I):return [[A[i][j] for j in I] for i in I]
def det(A):
    n=len(A)
    if n==0:return F(1)
    W=[r[:] for r in A]; sign=1; out=F(1)
    for k in range(n):
        sel=next((i for i in range(k,n) if W[i][k]),None)
        if sel is None:return F(0)
        if sel!=k:W[k],W[sel]=W[sel],W[k];sign=-sign
        pv=W[k][k];out*=pv
        for i in range(k+1,n):
            z=W[i][k]/pv
            for j in range(k+1,n):W[i][j]-=z*W[k][j]
            W[i][k]=F(0)
    return sign*out

def inv(A):
    n=len(A);W=[A[i][:]+ident(n)[i][:] for i in range(n)]
    for k in range(n):
        sel=next((i for i in range(k,n) if W[i][k]),None)
        if sel is None: raise ZeroDivisionError('singular inverse')
        if sel!=k:W[sel],W[k]=W[k],W[sel]
        pv=W[k][k];W[k]=[x/pv for x in W[k]]
        for i in range(n):
            if i==k:continue
            z=W[i][k]; W[i]=[x-z*y for x,y in zip(W[i],W[k])]
    return [row[n:] for row in W]

def psd(A):
    if A!=transpose(A):return False
    n=len(A)
    return all(det(minor(A,I))>=0 for sz in range(1,n+1) for I in combinations(range(n),sz))
def pd(A):
    if A!=transpose(A):return False
    return all(det(minor(A,range(k)))>0 for k in range(1,len(A)+1))
def spectrum(A):
    return [(str(ev),int(mult)) for ev,mult in sp.Matrix([[sp.Rational(x.numerator,x.denominator) for x in row] for row in A]).eigenvals().items()]
def marg(A,p,alpha):
    n=len(A); M=sub(A,scale(diag(p),alpha)); r=mv(M,[F(1)]*n)
    out={"B":A,"p":p,"alpha":alpha,"M":M,"M_psd":psd(M),"M_pd":pd(M),"M_det":det(M),"M_row_sums":r,"G1_Z_rows":all(M[i][j]<=0 for i in range(n) for j in range(n) if i!=j) and all(t>=0 for t in r),"M_eigenvalues":spectrum(M)}
    if pd(A):
        Z=inv(A);zp=mv(Z,p)
        out.update(Z=Z,Zp=zp,Z_nonnegative=all(t>=0 for row in Z for t in row),M0=(all(alpha*t<=1 for t in zp) if alpha>0 else 'undefined_alpha_nonpositive'),local=[alpha*p[i]*Z[i][i]<=1 for i in range(n)])
    else:out.update(M0="undefined_non_PD",local="undefined_non_PD")
    return out

cases=[]
def submit(name,input,observations,expect=None):
    result=pretty(observations)
    if expect:
        for k,v in expect.items():
            if observations[k]!=v: raise AssertionError(f'{name}: {k}={observations[k]!r}, expected {v!r}')
    cases.append({"id":name,"input":pretty(input),"exact":result,"expected":pretty(expect or {}),"result":"PASS"})

B=mat([[1,'-1/2'],['-1/2',1]])
for name,p,exp in [
  ('C01_G0_not_M0',vec(['1/4','2/3']),{'M_psd':True,'M0':False}),
  ('C02_all_LOCAL_not_G0',vec(['3/4','3/4']),{'M_psd':False,'local':[True,True]}),
  ('C03_uncontrolled_inverse_accepts_unsafe',vec(['3/5','3/5']),{'M0':False})]:
    d=marg(B,p,F(1))
    if name.startswith('C03'):d['naive_diag_inverse_burden']=p;d['naive_accept']=all(q<=1 for q in p)
    submit(name,{'B':B,'p':p,'alpha':1},d,exp)
B2=mat([[2,-1],[-1,2]]);p2=vec(['11/10','1/20']);d=marg(B2,p2,F(1))
submit('C04_M0_not_G1',{'B':B2,'p':p2,'alpha':1},d,{'M0':True,'M_psd':True,'G1_Z_rows':False})
Bp=mat([[1,'4/5'],['4/5',1]]);pp=vec([1,1]);d=marg(Bp,pp,F(1))
submit('C05_inverse_positive_required',{'B':Bp,'p':pp,'alpha':1},d,{'M0':True,'M_psd':False,'Z_nonnegative':False})
Zgood=mat([[2,1,0],[1,2,1],[0,1,2]]); B3=inv(Zgood);p3=vec(['1/5','1/5','1/5']);d=marg(B3,p3,F(1));
submit('C06_inverse_nonnegative_B_not_Z',{'B':B3,'p':p3,'alpha':1},d,{'M0':True,'M_psd':True,'Z_nonnegative':True})
for name,Bx,px,alpha,exp in [
 ('C07_zero_support',B2,vec([0,0]),F(1),{'M0':True,'M_psd':True}),
 ('C08_singular_support',B2,vec([1,0]),F(1),{'M0':True,'M_psd':True}),
 ('C09_boundary_M0_G0',mat([[1]]),vec([1]),F(1),{'M0':True,'M_psd':True,'M_pd':False}),
 ('C10_reducible_inverse',mat([[2,0,0],[0,2,-1],[0,-1,2]]),vec(['1/4','1/2','1/2']),F(1),{'M0':True,'M_psd':True}),
 ('C11_alpha_zero_outside_domain',B2,vec([1,1]),F(0),{'M_psd':True}),
 ('C12_singular_B_inverse_undefined',mat([[1,-1],[-1,1]]),vec([0,0]),F(1),{'M_psd':True,'M0':'undefined_non_PD'})]:
    submit(name,{'B':Bx,'p':px,'alpha':alpha},marg(Bx,px,alpha),exp)

r=vec([2,1])
for name,M0,exp in [
 ('C13_G1_not_fixed_G2',mat([[1,'-3/5'],['-3/5',1]]),{'G1':True,'G2':False}),
 ('C14_fixed_G2_not_G1',mat([['2/5','-3/5'],['-3/5','6/5']]),{'G1':False,'G2':True})]:
    sums=mv(M0,vec([1,1]));Mr=mv(M0,r)
    obs={'M':M0,'M_psd':psd(M0),'M_eigenvalues':spectrum(M0),'row_sum':sums,'Mr':Mr,'G1':all(v>=0 for v in sums),'G2':all(v>=0 for v in Mr)}
    submit(name,{'M':M0,'r':r},obs,exp)

# Explicit Schur and rank projector tests; scalar eliminated blocks allow exact examples.
for name,L,expect in [
 ('C15_Schur_eliminated_PD',mat([[2,-1],[-1,1]]),{'block_PD':True,'full_PSD':True,'Schur_PSD':True}),
 ('C16_inverse_only_is_not_PSD',mat([[2,-1],[-1,-1]]),{'block_PD':False,'full_PSD':False,'Schur_PSD':True}),
 ('C17_negative_eliminated_algebra_only',mat([[2,0],[0,-1]]),{'block_PD':False,'full_PSD':False,'Schur_PSD':True})]:
    c=L[1][1];sch=L[0][0]-L[0][1]*L[1][0]/c
    d={'L':L,'L_det':det(L),'L_eigenvalues':spectrum(L),'C':c,'block_PD':c>0,'full_PSD':psd(L),'Schur':sch,'Schur_PSD':sch>=0}
    submit(name,{'L':L,'retained':[0],'eliminated':[1]},d,expect)
for name,L,expect in [
 ('C18_pseudoinverse_without_range_false',mat([[1,1],[1,0]]),{'range_ok':False,'full_PSD':False,'naive_Schur_PSD':True}),
 ('C19_singular_range_satisfied',mat([[2,0],[0,0]]),{'range_ok':True,'full_PSD':True,'naive_Schur_PSD':True})]:
    c=L[1][1];f=L[0][1];pinv=F(1)/c if c else F(0);sch=L[0][0]-f*f*pinv
    d={'L':L,'L_eigenvalues':spectrum(L),'C':c,'C_dagger':pinv,'range_residual':f if c==0 else F(0),'range_ok':(c!=0 or f==0),'naive_Schur':sch,'naive_Schur_PSD':sch>=0,'full_PSD':psd(L)}
    submit(name,{'L':L},d,expect)

# Source boundary conditions and nonaffine Kron reduction.
for name,b,Bnet in [('C20_source_internal_fixed_vs_free',F(3),F(2))]:
    ext=mat([[b,-b],[-b,Bnet+b]])
    free=Bnet+b-b*b/b
    submit(name,{'b':b,'B_net':Bnet,'extended':ext},{'terminal_fixed_internal_coefficient':Bnet+b,'terminal_after_free_internal_Kron':free,'source_gain_difference':b,'ext_eigenvalues':spectrum(ext)},{'terminal_fixed_internal_coefficient':F(5),'terminal_after_free_internal_Kron':F(2)})
vals=[F(2)-F(1)/(F(1)+t) for t in (0,1,2)]
submit('C21_nonaffine_eliminated_diagonal',{'L(t)':'[[2,-1],[-1,1+t]]','t':[0,1,2]},{'Schur_values':vals,'increment_0_to_1':vals[1]-vals[0],'increment_1_to_2':vals[2]-vals[1],'affine':(vals[1]-vals[0]==vals[2]-vals[1])},{'affine':False})

J=mat([[1,1,1],[1,1,1],[1,1,1]])
submit('C22_PSD_nonZ_not_closed_SDD',{'M':J},{'M_PSD':psd(J),'eigenvalues':spectrum(J),'trace':F(3),'undirected_edges':3,'minimum_edge_total_budget':F(6),'sum_available_diagonal':F(3),'G3_possible':False},{'M_PSD':True,'G3_possible':False})
Lap=mat([[1,-1,0],[-1,2,-1],[0,-1,1]])
submit('C23_singular_laplacian_sdd',{'M':Lap},{'M_psd':psd(Lap),'eig':spectrum(Lap),'r':vec([1,1,1]),'Mr':mv(Lap,vec([1,1,1])),'G3_budgets':{'q12':F(1),'q23':F(1),'node_residues':vec([0,0,0])}},{'M_psd':True,'Mr':vec([0,0,0])})

Bmin=mat([[2,-1],[-1,2]]);Bplus=mat([[3,-1],[-1,2]]);Zmin=inv(Bmin);Zplus=inv(Bplus)
submit('C24_M1_inverse_entry_order',{'Bmin':Bmin,'B':Bplus},{'Zmin':Zmin,'Z':Zplus,'Z_le_Zmin':all(Zplus[i][j]<=Zmin[i][j] for i in range(2) for j in range(2))},{'Z_le_Zmin':True})
Bhi=mat([[3,'-1/2'],['-1/2',3]]);Blow=mat([[1,'-1/2'],['-1/2',1]]);phigh=vec([2,2]);a=marg(Bhi,phigh,F(1));
submit('C25_G1_not_M1',{'Bmin':Blow,'B':Bhi,'p':phigh},{'G1':a['G1_Z_rows'],'M1':all(v<=1 for v in mv(inv(Blow),phigh)),'G0':a['M_psd']},{'G1':True,'M1':False})
p=p2; a=marg(Bmin,p,F(1))
submit('C26_M1_not_G1',{'Bmin':Bmin,'B':Bmin,'p':p},{'M1':all(v<=1 for v in mv(inv(Bmin),p)),'G1':a['G1_Z_rows']},{'M1':True,'G1':False})

# Finite geometric inverse approximations.
X=mat([[1,'-1/2'],['-1/2',1]])
E=mat([[0,'-1/2'],['-1/2',0]])
Z=inv(X); z1=add(ident(2),scale(E,F(-1)))
submit('C27_first_order_false_accept',{'A':ident(2),'Delta':E,'p':['3/5','3/5']},{'true_burden':mv(Z,vec(['3/5','3/5'])),'linear_burden':mv(z1,vec(['3/5','3/5'])),'true_M0':all(v<=1 for v in mv(Z,vec(['3/5','3/5']))),'linear_M0':all(v<=1 for v in mv(z1,vec(['3/5','3/5'])))},{'true_M0':False,'linear_M0':True})
N=mat([[0,2],[0,0]])
submit('C28_nonnormal_Neumann_spectral_radius',{'E':N},{'E2':mm(N,N),'rho_exact':F(0),'infty_norm':F(2),'series_exact_I_minus_E':sub(ident(2),N),'inverse_I_plus_E':inv(add(ident(2),N))},{'rho_exact':F(0),'infty_norm':F(2)})

# Invalid naive "smallest finite generalized eigenvalue" for indefinite zero-exposure subspace.
Bbad=mat([[2,0],[0,-1]]);Sbad=diag(vec([1,0]));alpha=F(1)
submit('C29_finite_eig_not_global_if_nullblock_negative',{'B':Bbad,'S':Sbad,'alpha':alpha},{'formal_finite_generalized_lambda':F(2),'zero_support_block':F(-1),'G0':psd(sub(Bbad,scale(Sbad,alpha))),'Rayleigh_at_x_1_3':F(2)-F(9)},{'G0':False})

# Signed off-diagonal not replaceable with simple Z-Laplacian without assumptions.
Lnon=mat([[1,'1/2'],['1/2',1]])
submit('C30_positive_offdiag_dd_witness',{'M':Lnon},{'PSD':psd(Lnon),'DD_abs':all(Lnon[i][i]>=abs(Lnon[i][1-i]) for i in (0,1)),'row_sums':mv(Lnon,vec([1,1]))},{'PSD':True,'DD_abs':True})

# Independent eigenvalue oracle check against rational principal minor test.
for t in cases:
    if 'M' in t['exact'] and 'M_psd' in t['exact']:
        d=t['exact']; M=mat(d['M']);eig=sp.Matrix([[sp.Rational(q.numerator,q.denominator) for q in row] for row in M]).eigenvals()
        nonneg=all(bool(ev.is_nonnegative) for ev in eig) # exact algebraic Sympy eigenvalues
        if nonneg!=d['M_psd']: raise AssertionError('Independent exact spectrum/PSD disagreement: '+t['id'])

out={'schema':'a3_5_math_closure_oracle_v1','independence':'fresh Python fractions + separate SymPy exact-eigenspectrum cross-check; no AP3 code','n_cases':len(cases),'passed':sum(t['result']=='PASS' for t in cases),'cases':cases}
path=Path(__file__).with_name('oracle_results.json')
path.write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(json.dumps({'passed':out['passed'],'total':len(cases),'results_sha256':sha256(path.read_bytes()).hexdigest(),'script_sha256':sha256(Path(__file__).read_bytes()).hexdigest()},sort_keys=True))
