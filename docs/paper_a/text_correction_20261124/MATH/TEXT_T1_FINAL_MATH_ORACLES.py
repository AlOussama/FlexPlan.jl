"""Independently verify revised row-disc argument and rerun exact manuscript oracles."""
import hashlib, importlib.util, io, json, re, runpy, sys
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch
from sympy import Abs, Matrix, diag, symbols, expand
location=Path(__file__).resolve().parent
root=location.parent
paper=root/'PAPER'
target=paper/'04_PAPER_A.tex'
raw=target.read_bytes()
def digest(b): return hashlib.sha256(b).hexdigest()
pinned='941de1a3715d9b4a462419cec92368de69e037660c661d71ef15520c71502a31'
assert digest(raw)==pinned
oracle=location/'TEXT_T1_MATH_ORACLES.py'
negative=location/'TEXT_T1_NEGATIVE_CONTROLS.py'
proof=raw.decode().split(r'\begin{proof}',1)[1].split(r'\end{proof}',1)[0]
key='Gershgorin1931'
def read_gershgorin(txt):
    rules=[('identity',r'H_{ii}-\sum_{j\ne i}|H_{ij}|=r_i(Mr)_i'),
           ('scale',r'$H=RMR$'),
           ('domain','off-diagonal entries are nonpositive'),
           ('union',r'Every eigenvalue lies in the union of these discs \cite{Gershgorin1931}')]
    return {name:statement in txt for name,statement in rules}
actual=read_gershgorin(proof)
assert all(actual.values()),actual
x,y,z=symbols('r1 r2 r3',positive=True)
a,b,c=symbols('a b c',real=True)
d,e,f=symbols('w12 w13 w23',nonnegative=True)
M=Matrix([[a,-d,-e],[-d,b,-f],[-e,-f,c]])
r=Matrix([x,y,z]); R=diag(x,y,z);H=R*M*R
lhs=Matrix([H[i,i]-sum(Abs(H[i,j]) for j in range(3) if j!=i) for i in range(3)])
identity=(lhs-R*M*r).applyfunc(expand)
assert identity==Matrix([0,0,0])
def discs(m,r):
    h=diag(*r)*m*diag(*r)
    rad=[sum(abs(h[i,j]) for j in range(h.rows) if i!=j) for i in range(h.rows)]
    endpoints=[(h[i,i]-rad[i],h[i,i]+rad[i]) for i in range(h.rows)]
    eigen=list(h.eigenvals())
    assert all(any(lo<=g<=hi for lo,hi in endpoints) for g in eigen)
    assert [lo for lo,hi in endpoints]==list(diag(*r)*m*r)
    return {'M':str(m),'r':str(r),'discs_real_cross_sections':str(endpoints),'exact_eigenvalues':str(eigen)}
controls=[discs(Matrix([[2,-1],[-1,1]]),Matrix([1,2])),
          discs(Matrix([[1,-1],[-1,1]]),Matrix([1,1])),
          discs(diag(2,5),Matrix([1,1]))]
corrupt=[]
for word,bad in [('-\\sum','+\\sum'),('union','intersection'),('H=RMR','H=RM'),('r_i(Mr)_i$: its','(Mr)_i$: its')]:
    assert word in proof
    rt=read_gershgorin(proof.replace(word,bad,1))
    assert not all(rt.values()),(word,bad)
    corrupt.append({'source':word,'replacement':bad,'rejected':k if (k:=[k for k,v in rt.items() if not v]) else []})
base=location/'TEXT_T2_RERUN_BASE_ARITHMETIC.json'
with patch.object(sys,'argv',[str(oracle),'--tex',str(target),'--stage','candidate','--output',str(base)]):
    try: runpy.run_path(str(oracle),run_name='__main__')
    except SystemExit as ex: assert ex.code==0
core=json.loads(base.read_text())
assert core['tex_sha256']==pinned and len(core['checks'])==40 and not core['failed']
old_path=location/'TEXT_T1_NEGATIVE_CONTROLS.json'
new_path=location/'TEXT_T1_FINAL_NEGATIVE_CONTROLS.json'
write_original=Path.write_text
read_original=Path.read_bytes
def write(p,*args,**kwargs):
    return write_original(new_path if p==old_path else p,*args,**kwargs)
def read(p):
    return read_original(new_path if p==old_path else p)
with patch.object(Path,'write_text',write),patch.object(Path,'read_bytes',read):
    runpy.run_path(str(negative),run_name='__main__')
mut=json.loads(new_path.read_text())
assert mut['source_tex_sha256']==pinned and len(mut['mutations'])==5 and all(x['oracle_exit']==1 for x in mut['mutations'])
bib=paper/'04_references.bib'
assert re.search(r'@\w+\{\s*Gershgorin1931,',bib.read_text(encoding='utf-8'))
out=dict(reviewer='/root/math_r',scope='T1/updated T2 mathematical verification only',tex=str(target),tex_sha256=pinned,
           script_sha256=digest(Path(__file__).read_bytes()),original_core_oracle_sha256=digest(oracle.read_bytes()),
           all_core_tests=core['checks'],core_replay_sha256=digest(base.read_bytes()),actual_revised_proof=proof.strip(),
           printed_claims=actual,symbolic_residual=str(identity),signed_edge_variables='arbitrary nonnegative weights; positive scaling; arbitrary real diagonals',
           general_source_proof='Normalize an eigenvector by an entry of maximal nonzero magnitude. Its row of Hv=lambda*v gives |lambda-Hii| <= sum(j!=i) |Hij|. This chooses at least one disc. H is real symmetric, so its eigenvalues lie on the real line. Hij<=0 implies the left endpoint equals the row sum, ri*(Mr)i. If Mr>=0 every left endpoint is nonnegative; positive congruence transfers H PSD to M PSD.',
           exact_disc_examples=controls,additional_mutations=corrupt,original_mutations=mut['mutations'],
           original_mutation_receipt_sha256=digest(new_path.read_bytes()),bibliography_sha256=digest(bib.read_bytes()),
           metadata='Gerschgorin (1931), pp. 749–754; proof matched to Satz II as identified by the independent F4 original-scan readback and the publisher catalogue.',
           command=[sys.executable,'-B',str(Path(__file__).resolve())],exit=0)
result=location/'TEXT_T2_FINAL_MATH_ORACLE_RESULTS.json'
result.write_text(json.dumps(out,indent=2,ensure_ascii=True)+'\n',encoding='utf8')
for p in [result,Path(__file__),new_path]:
    print(p.name,digest(p.read_bytes()))

