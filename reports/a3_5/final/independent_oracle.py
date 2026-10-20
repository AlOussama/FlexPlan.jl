#!/usr/bin/env python3
"""Independent exact-rational scientific counterexamples. NO Julia or MISOCP execution."""
import json
import hashlib
import sympy as s
cases = [
 ("G0_not_M0", [[1, "-1/2"],["-1/2",1]], ["1/4","2/3"]),
 ("M0_not_G1", [[2,-1],[-1,2]],["11/10","1/20"]),
 ("inverse_positive_missing", [[1,"4/5"],["4/5",1]],[1,1])
]
records=[]
for name,b,p in cases:
 B=s.Matrix([[s.Rational(str(y)) for y in row] for row in b])
 P=s.Matrix([s.Rational(str(y)) for y in p])
 M=B-s.diag(*P)
 Zp=B.inv()*P
 row=M*s.ones(B.rows,1)
 rec={"name":name,"matrix":[[str(x) for x in row] for row in B.tolist()],
 "p":list(map(str,P)),"Zp":list(map(str,Zp)),"M_rows":list(map(str,row)),
 "det_M":str(M.det()),"eigen_B":{str(k):v for k,v in B.eigenvals().items()},
 "M_PSD": all(float(k)>=-1e-12 for k in M.eigenvals()),
 "M0": all(v<=1 for v in Zp),"G1":all(v>=0 for v in row)}
 rec["sha256"]=hashlib.sha256(s.json if False else json.dumps(rec,sort_keys=True).encode()).hexdigest()
 records.append(rec)
print(json.dumps({"evidence_scope":"exact rational counterexamples only","cases":records},indent=2))
