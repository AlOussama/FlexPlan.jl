"""Read exact printed B,p pairs and independently falsify central algebra. SymPy rational checks; no solver."""
from pathlib import Path
import re,json,hashlib,argparse
import sympy as s
Q=s.Rational;M=s.Matrix
def nums(expr):
    expr=re.sub(r'\\(?:t?frac)\{(-?\d+)\}\{(\d+)\}',r'\1/\2',expr)
    expr=re.sub(r'\\(?:t?frac)(\d)(\d)',r'\1/\2',expr)
    return [Q(v) for v in re.findall(r'(?<![\d/])-?\d+(?:/\d+)?',expr)]
def inverse_examples(tex):
    region=tex[tex.index("Both reverse"):tex.index("For M1")] if "Both reverse" in tex else tex[tex.index("inverse test and its domain"):tex.index("For M1")]
    pat=r'(?<![A-Za-z])(?P<sym>[Bp])(?:_\{[^}]+\}|_[012ab])?\s*=\s*(?P<val>\[[^]]+\]|\([^)]*\)|\\begin\{[bp]matrix\}[\s\S]*?\\end\{[bp]matrix\})'
    pairs=[];B=None
    for m in re.finditer(pat,region):
        v=nums(m['val'])
        if m['sym']=='B' and len(v)==4:B=M(2,2,v)
        if m['sym']=='p' and B is not None and len(v)==2:
            p=M(v);pairs.append((B,p,m[0]))
    if len(pairs)!=2:raise ValueError(('matrix/pair grammar',region[:1800],pairs))
    return pairs
def assess(B,p):
    H=B-s.diag(*p);Z=B.inv();z=Z*p;e=H.eigenvals()
    assert B.is_positive_definite and all(i>=0 for i in Z) and all(i>=0 for i in p)
    return dict(B=list(map(str,B)),p=list(map(str,p)),det=str(H.det()),eigen={str(x):n for x,n in e.items()},inverse_p=list(map(str,z)),psd=H.is_positive_semidefinite,m0=all(i<=1 for i in z),g1=all(i>=0 for i in H*s.ones(2,1)))
def verify(tex,baseline=False):
    o={};pairs=inverse_examples(tex);a,b=[assess(B,p) for B,p,_ in pairs];o['parsed_inverse_examples']=[a,b]
    assert a['m0'] and not a['g1']
    assert b['det']=='0' and b['psd'] and b['inverse_p']==['7/9','19/18'] and not b['m0']
    if not baseline:assert b['p']==['1/4','2/3'] and b['eigen']=={'13/12':1,'0':1}
    mixed=assess(M([[1,-Q(1,2)],[-Q(1,2),1]]),M([Q(1,2),Q(4,3)]))
    assert mixed['det']=='-5/12' and mixed['inverse_p']==['14/9','19/9'] and not mixed['psd'];o['mixed_scale_negative']=mixed
    t=tex.replace(' ','')
    for expr in [r'RMR',r'Mr',r'M_{ij}',r'q_{ij}',r'M_{ii}',r'B_{',r'Wp',r'D^\dagger',r'8760}{168}']:
        assert expr in t,expr
    row=tex[tex.index("quadratic form"):tex.index("\\begin{proposition}[Edge-conic")]
    r=M(nums(re.search(r'r\s*=\s*(\([^)]*\))',row)[1]))
    if baseline:
        mutual=nums(re.search(r'off-diagonal\s+\$([^$]+)',row)[1])[0]
        diag=re.search(r'diagonals\s+\$(\([^)]*\))\$\s+and\s+\$(\([^)]*\))',row)
        left,right=[M([[v[0],mutual],[mutual,v[1]]]) for v in [nums(diag[i]) for i in [1,2]]]
    else:
        left,right=[M(2,2,nums(re.search(r'M_'+v+r'=\\begin\{bmatrix\}(.*?)\\end\{bmatrix\}',row)[1])) for v in ('a','b')]
        for A,lab in [(left,'a'),(right,'b')]:
            for vec,pattern in [(s.ones(2,1),r'\\one'),(r,r'\s*r')]:
                printed=M(nums(re.search('M_'+lab+pattern+r'=\(([^)]+)\)',row)[1]))
                assert A*vec==printed
        B,p,_=pairs[1]
        reg=tex[tex.index("inverse test and its domain"):tex.index("For M1")]
        printed_M=M(2,2,nums(re.search(r'\bM=\\begin\{bmatrix\}(.*?)\\end\{bmatrix\}',reg)[1]))
        assert B-s.diag(*p)==printed_M
        zprinted=[nums(x) for x in re.findall(r'\bZp=\(([^)]+)\)',reg)]
        assert zprinted==[list(Bi.inv()*pi) for Bi,pi,_ in pairs]
        assert nums(re.search(r'M\\one=\(([^)]+)\)',reg)[1])==list((pairs[0][0]-s.diag(*pairs[0][1]))*s.ones(2,1))
        vals=re.search(r'eigenvalues are \$([^$]+)\$ and \$([^$]+)\$',reg)
        assert sorted(nums(vals[1])+nums(vals[2]))==sorted(printed_M.eigenvals())
        assert nums(re.search(r'\\det M=([^$]+)',reg)[1])==[printed_M.det()]
    def certificate(A,u):return list(A*u)
    u=s.ones(2,1)
    assert min(left*u)>=0>min(left*r) and min(right*r)>=0>min(right*u)
    o['printed_unit_and_scaled_noninclusions']=[list(map(str,A*v)) for A,v in [(left,u),(left,r),(right,u),(right,r)]]
    x,y,k,a0,b0,r1,r2=s.symbols('x y k a b r1 r2',positive=True)
    A=M([[a0,-k],[-k,b0]]);R=s.diag(r1,r2);v=M([x,y]);rv=M([r1,r2])
    identity=(v.T*R*A*R*v)[0]-(k*r1*r2*(x-y)**2+sum(rv[i]*(A*rv)[i]*v[i]**2 for i in range(2)))
    assert s.expand(identity)==0;o['scaled_congruence_form']=str(s.expand(identity))
    # RSOC readback: supplied first coordinate times two times second equals qij*qji.
    match=re.search(r'\((q_\{ij\}(?:/\d+)?),(q_\{ji\}),M_\{ij\}\)',t)
    assert match, 'printed RSOC tuple'
    scale=Q(1,int(match[1].split('/')[-1])) if '/' in match[1] else Q(1)
    assert 2*scale==1
    o['printed_RSOC_first_coordinate_multiplier']=str(scale)
    A=s.diag(right,0,s.Matrix([[4,-1],[-1,3]])); rr=M([1,2,1,1,1]); edge={};remain=[]
    for i in range(A.rows):
        sq=0
        for j in range(A.rows):
            if i!=j and A[i,j]!=0:
                q=-A[i,j]*rr[j]/rr[i];edge[(i,j)]=q;sq+=q
        remain.append(A[i,i]-sq)
    assert A.is_positive_semidefinite and min(remain)>=0 and all(v*edge[j,i]==A[i,j]**2 for (i,j),v in edge.items())
    o['singular_reducible_SDD_allocation']={'node_remainder':list(map(str,remain)),'edges':{str(key):str(v) for key,v in edge.items()}}
    D=s.diag(2,0);C=M([[1,0]]);A=M([[1]]);S=A-C*D.pinv()*C.T;bad=M([[1,1]])
    assert (s.eye(2)-D*D.pinv())*C.T==s.zeros(2,1) and S[0]==Q(1,2)
    assert (s.eye(2)-D*D.pinv())*bad.T!=s.zeros(2,1)
    assert not A.row_join(bad).col_join(bad.T.row_join(D)).is_positive_semidefinite
    o['generalized_schur']={'valid_reduced':str(S[0]),'failed_range':str((s.eye(2)-D*D.pinv())*bad.T),'zero_exposure':'S=0, xTSx=0 all x'}
    Bmin=M([[2,-1],[-1,2]]);B=Bmin+s.diag(1,3);delta=Bmin.inv()-B.inv()
    assert delta==Bmin.inv()*(B-Bmin)*B.inv() and min(delta)>=0
    W=M([[1,Q(2,3)],[Q(1,4),1]]);p=M([2,3])
    assert min(W*p-p)>=0 and s.eye(2)*p==p
    o['M1_inverse_difference']=list(map(str,delta));o['M2_Wp_minus_p']=list(map(str,W*p-p))
    # Upper burden must be placed on RHS in a sufficient direction; wrong free rho yields explicit zero.
    P,d,ell=Q(3),Q(2),Q(1);assert 0<P/d<=P/ell and 0<=P/ell
    o['ratio_counterexample']={'P/d':str(P/d),'P/ell':str(P/ell),'admissible_rho':0}
    H=M([[2,1],[1,1]]);D=s.diag(Q(1,5),Q(1,8));A=H.inv();V=(s.eye(2)+A*D).inv()*A
    assert V==(H+D).inv() and V!=A*(s.eye(2)+A*D).inv()
    o['noncommutative_order']={'correct_inverse':list(map(str,V)),'row_norm':str(max(sum(abs(i) for i in (A*D).row(j)) for j in range(2)))}
    # A feasible G2 zero-margin scaling exists at the normalized G0-not-M0 example.
    fixed=M([2,3]);K=M([[1,-Q(1,2)],[-Q(1,2),1]]);pp=M([Q(1,4),Q(2,3)])
    assert (K-s.diag(*pp))*fixed==s.zeros(2,1) and max(K.inv()*pp)>1
    o['G2_does_not_imply_inverse_screen']={'r':['2','3'],'Mr':['0','0'],'Zp':[str(v) for v in K.inv()*pp]}
    # Algebra behind singular quotient outside the range: x=(1,-t) with fixed xTSx=1.
    t=s.symbols('t',positive=True);sg=s.diag(1,0);xx=M([1,-t]);cross=M([[1,1],[1,0]])
    assert (xx.T*sg*xx)[0]==1 and s.limit((xx.T*cross*xx)[0],t,s.oo)==-s.oo
    o['unbounded_singular_quotient']={'quadratic':str((xx.T*cross*xx)[0]),'denominator':1}
    # Gershgorin centres minus radii of RMR equal the stated weighted row margins.
    T=M([[a0,-k],[-k,b0]]);C=R*T*R
    ds=M([C[i,i]-sum(s.Abs(C[i,j]) for j in range(2) if i!=j) for i in range(2)])
    assert all(s.simplify(z)==0 for z in ds-R*T*rv)
    o['Gershgorin_Z_domain_exact_left_endpoints']=list(map(str,ds))
    return o
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('tex',type=Path);p.add_argument('out',type=Path);p.add_argument('--baseline',action='store_true');a=p.parse_args()
    b=a.tex.read_bytes();t=b.decode();o=verify(t,a.baseline)
    o.update(source_sha256=hashlib.sha256(b).hexdigest(),reviewer='/root/qa_r',script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),baseline=a.baseline)
    a.out.write_text(json.dumps(o,indent=2,default=str)+"\n");print(o)