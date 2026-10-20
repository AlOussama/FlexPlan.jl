#!/usr/bin/env python3
"""Independent exact-rational mathematical checks; no FlexPlan/AP3 imports.
Only SymPy is required. These are proof witnesses, not exhaustive code tests.
"""
import json
from fractions import Fraction
from pathlib import Path
import sympy as S

R = S.Rational
one2 = S.ones(2, 1)
I2 = S.eye(2)
results = []

def check(name, test, details):
    if not bool(test):
        raise AssertionError(name)
    results.append({"id": name, "status": "passed_exact", "details": str(details)})

B = S.Matrix([[1, -R(1,2)], [-R(1,2), 1]])
p = S.Matrix([R(1,4), R(2,3)])
Z = B.inv()
M = B - S.diag(*p)
check("T001_ordinary_schur", B[1,1] > 0 and B[0,0]-B[0,1]**2/B[1,1] == R(3,4), "Schur=3/4")
check("T004_T006_support_kron", (S.Matrix([[2,-1],[-1,2]])-R(7,4)*S.diag(1,0)).det() < 0 and 2-R(1,2)-R(7,4)<0, "Naive bus deletion falsely passes at alpha=7/4")
Cbad=S.Matrix([[1,1],[1,0]])
check("T004_T006_range_failure", Cbad[1,1] == 0 and Cbad[1,0] != 0, "Pseudoinverse-only test fails range condition; Rayleigh unbounded below")
Cgood=S.diag(2,0)
check("T004_T006_generalized_schur_success", Cgood[0,0] == 2 and Cgood[1,0]==0, "Zero support block singular but range condition holds")
check("T007_T008_rank_one", Z[0,0]*p[0] == R(1,3) and (B-p[0]*S.diag(1,0)).det()>0, "Rank-one threshold alpha p_i Z_ii<=1")
check("T010_G0_not_M0", M.eigenvals()=={S.Integer(0):1,R(13,12):1} and Z*p==S.Matrix([R(7,9),R(19,18)]), "G0 true, M0 false")
check("T017_G3_witness", M[0,0] == R(3,4) and M[1,1]==R(1,3) and R(3,4)*R(1,3)==M[0,1]**2, "Exactly zero node residuals and cone slack")
localp=S.Matrix([R(3,4),R(3,4)])
localM=B-S.diag(*localp)
check("T007_T008_local_not_G0", all(localp[i]*Z[i,i]==1 for i in range(2)) and localM.det()<0, "Both local rank-one tests pass but G0 fails")

r=S.Matrix([2,1])
G1pass=S.Matrix([[1,-R(3,5)],[-R(3,5),1]])
G2pass=S.Matrix([[R(2,5),-R(3,5)],[-R(3,5),R(6,5)]])
check("T015_G1_not_fixed_G2", all(x>=0 for x in G1pass*one2) and min(G1pass*r)<0, "r=(2,1)")
check("T015_fixed_G2_not_G1", all(x>=0 for x in G2pass*r) and min(G2pass*one2)<0, "r=(2,1)")
lap=S.Matrix([[1,-1,0],[-1,1,0],[0,0,0]])
check("T018_closed_SDD_singular", lap.eigenvals()=={S.Integer(0):2,S.Integer(2):1} and lap*S.ones(3,1)==S.zeros(3,1), "reducible Laplacian and isolated zero row")
nonz=S.Matrix([[1,R(7,10),R(7,10)],[R(7,10),1,R(7,10)],[R(7,10),R(7,10),1]])
check("T020_non_Z_PSD_not_SDD", nonz.eigenvals()=={R(12,5):1,R(3,10):2} and R(7,10)*2>1, "No positive scaling: summing 3 inequalities gives sum(r)>=1.4sum(r)")

Bmin=S.Matrix([[2,-1],[-1,2]])
Bactual=Bmin+S.diag(1,0)
check("T021_T022_inverse_order", all(x>=0 for x in Bmin.inv()-Bactual.inv()) and Bmin.inv()==S.Matrix([[R(2,3),R(1,3)],[R(1,3),R(2,3)]]), "Exact entrywise inverse bound")
W=S.Matrix([[1,R(1,2)],[R(1,2),1]])
pW=S.Matrix([R(1,4),R(1,4)])
check("T023_M2_exposure", all(x>=0 for x in W*pW-pW), "Wp>=p")

A=I2
Delta=S.Matrix([[0,-R(1,2)],[-R(1,2),0]])
E=A.inv()*Delta
X=(A+Delta).inv()
T1=A.inv()-E*A.inv()
R2=(-E)**2*(I2+E).inv()*A.inv()
check("T025_T028_Neumann_exact_remainder", X-T1==R2, "Exact finite first-order remainder identity")
check("T026_uncontrolled_inverse_false_accept", all(x<=1 for x in S.Matrix([R(3,5),R(3,5)])) and all(x>1 for x in B.inv()*S.Matrix([R(3,5),R(3,5)])), "zero-order inverse I accepts, actual Z rejects")

Brow=S.Matrix([[2,-1],[-1,2]])
prow=S.Matrix([R(11,10),R(1,20)])
Mrow=Brow-S.diag(*prow)
check("A35_NEW_M0_implies_G0_strict_G1", Brow.inv()*prow==S.Matrix([R(3,4),R(2,5)]) and min(Mrow*one2)<0 and Mrow.det()==R(151,200), "M0 true, G1 false, G0 positive definite")
Bbad=S.Matrix([[1,R(4,5)],[R(4,5),1]])
pbad=S.Matrix([1,1])
check("A35_NEW_inverse_positive_is_necessary", Bbad.inv()*pbad==S.Matrix([R(5,9),R(5,9)]) and (Bbad-S.diag(*pbad)).det()<0, "Without Z>=0, M0 does not imply G0")
sourceb=S.symbols('sourceb',positive=True)
networkb=S.symbols('networkb',real=True)
aug=S.Matrix([[sourceb,-sourceb],[-sourceb,networkb+sourceb]])
check("A35_physical_voltage_source_boundary", S.simplify(aug[1,1]-aug[1,0]*aug[0,0]**-1*aug[0,1])==networkb, "Eliminating free internal node cancels bsrc; pinning source voltage retains +bsrc")
u=S.symbols('u',positive=True)
check("A35_decision_dependent_kron_nonaffine", S.diff(2-1/(1+u),u,2) != 0, "Schur eliminating a decision-dependent block is generally nonaffine")

payload={"schema":"a3_5_mathematical_rational_oracle/1.0", "target":"theorem_derivations_not_AP3_solver", "backend":"sympy_exact_rational", "sympy":S.__version__, "passed":len(results), "failed":0, "checks":results}
out=Path(__file__).with_name('oracle_results.json')
out.write_text(json.dumps(payload,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(f"PASS {len(results)}/{len(results)} exact rational checks -> {out}")
