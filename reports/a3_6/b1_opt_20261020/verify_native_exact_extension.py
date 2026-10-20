import ast,json,pathlib,sys,hashlib,itertools
from fractions import Fraction as Q
from collections import Counter
R=pathlib.Path(sys.argv[1])
tree=ast.parse((R/'verify_exact_certificates.py').read_text())
defs=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['affine','val','det','point_check']]
scope={'Q':Q,'Counter':Counter,'itertools':itertools};exec(compile(ast.Module(body=defs,type_ignores=[]),'separate_exact_verifier','exec'),scope)
p=R/'original_01/b1_exact_native.mof.json';m=json.loads(p.read_text());x={n:Q(v) for n,v in json.loads((R/'exact_primals/reference_24snap_point.json').read_text()).items()};original=len(x)
for _ in range(3):
    for c in m['constraints']:
        if c['set']['type']!='EqualTo' or c['function']['type'] not in ['Variable','ScalarAffineFunction']:continue
        a,k=scope['affine'](c['function']);missing=[n for n in a if n not in x]
        if len(missing)!=1:continue
        n=missing[0];x[n]=(Q(c['set']['value'])-k-sum((v*x[j] for j,v in a.items() if j!=n),Q(0)))/a[n]
assert len(x)==len(m['variables'])
fail=scope['point_check'](m,x);assert not fail,fail
op=R/'exact_primals/reference_24snap_native_point.json';op.write_text(json.dumps({n:str(v) for n,v in x.items()}))
r={'native_model_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'all_constraints_exactly_passed':True,'variables':len(x),'original_physical_variables':original,'exactly_extended_objective_increments':len(x)-original,'integer_constraints':sum(c['set']['type'] in ['Integer','ZeroOne'] for c in m['constraints']),'point_sha256':hashlib.sha256(op.read_bytes()).hexdigest(),'scope':'original serialized binary rational integer MISOCP including rebase equalities; no numerical feasibility tolerance'}
(R/'native_exact_extension_verification.json').write_text(json.dumps(r,indent=2));print(json.dumps(r,indent=2))
