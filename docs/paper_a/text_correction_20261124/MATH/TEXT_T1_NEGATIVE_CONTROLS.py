"""Execute deliberately corrupted TeX fragments in memory, leaving manuscript and original files untouched."""
import csv, hashlib, importlib.util, io, json, re, sys
from contextlib import redirect_stdout
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch
here=Path(__file__).resolve().parent
paper=here.parent/'PAPER'
old=here.parent.parent/'PAPER_A_BUNDLE_20261123_GOLD01'
spec=importlib.util.spec_from_file_location('paper_math',here/'TEXT_T1_MATH_ORACLES.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
def h(b):
    return hashlib.sha256(b).hexdigest()
candidate=paper/'04_PAPER_A.tex'
data=candidate.read_bytes()
realread=Path.read_bytes
receipt=here/'_in_memory_not_written_.json'
def run_mutation(before,after,expected):
    b,a=before.encode(),after.encode()
    assert data.count(b)==1,b
    mutated=data.replace(b,a,1)
    buf={}
    def read(p):
        if p==candidate:return mutated
        if p==receipt:return buf['json'].encode()
        return realread(p)
    def write(p,txt,*args,**kwargs):
        assert p==receipt
        buf['json']=txt
    with patch.object(Path,'read_bytes',read),patch.object(Path,'write_text',write),patch.object(sys,'argv',[str(spec.origin),'--tex',str(candidate),'--stage','candidate','--output',str(receipt)]),redirect_stdout(io.StringIO()):
        rc=module.main()
    found=json.loads(buf['json'])['failed']
    assert rc==1 and set(expected)<=set(found),(before,rc,found)
    return {'before':before,'after':after,'mutated_tex_sha256':h(mutated),'oracle_exit':rc,'failed_assertions':found}
mutations=[
    run_mutation('p=(1/4,2/3)','p=(1/2,4/3)',['PRINTED_G0_not_M0','PRINTED_normalized_M','PRINTED_both_inverse_burden_vectors']),
    run_mutation('r=(1,2)','r=(2,1)',['PRINTED_G1_G2_nonnesting','PRINTED_Mb_scaled_row']),
    run_mutation('Zp=(7/9,19/18)','Zp=(6/9,19/18)',['PRINTED_both_inverse_burden_vectors']),
    run_mutation('and $13/12$','and $13/24$',['PRINTED_spectrum_and_determinant']),
    run_mutation('M_a r=(-1,1)','M_a r=(1,1)',['PRINTED_Ma_scaled_row'])]
methods=old/'03_QUALIFIED_REAL_METHOD_RESULTS.csv'
with methods.open(encoding='utf-8-sig',newline='') as f:
    rows=list(csv.DictReader(f))
w=next(r for r in rows if r['method']=='G3' and r['mode']=='integer_witness')
m=next(r for r in rows if r['method']=='M2' and r['mode']=='relaxed')
lower=Decimal(m['qualified_numerical_bound_EUR2025'])
upper=Decimal(w['objective_EUR2025'])
ext=paper/'04_qualified_extensions.tex'; source=ext.read_text()
bills=[Decimal(v) for v in re.findall(r'(\d+\.\d+) billion EUR',source)]
mill=Decimal(re.search(r'(\d+\.\d+) million EUR',source)[1])
assert upper/10**9<=bills[0]<upper/10**9+Decimal('.000001')
assert lower/10**9-Decimal('.000001')<bills[1]<=lower/10**9
assert abs(mill-(lower-upper)/10**6)<Decimal('.005')
assert w['case_sha256']!=m['case_sha256'] and 'different case hashes' in source
out={'reviewer':'/root/math_r','scope':'T1 targeted falsification, secondary independent cross-model calculation','source_tex_sha256':h(data),'oracle_sha256':h(Path(spec.origin).read_bytes()),'script_sha256':h(Path(__file__).read_bytes()),'mutations':mutations,'source_method_csv_sha256':h(methods.read_bytes()),'source_extension_sha256':h(ext.read_bytes()),'M2_native_lower_EUR':str(lower),'G3_upper_witness_EUR':str(upper),'difference_million_EUR':str((lower-upper)/10**6),'M2_case_sha256':m['case_sha256'],'G3_case_sha256':w['case_sha256'],'printed_outward_billion_bounds':[str(v) for v in bills],'printed_descriptive_million':str(mill)}
target=here/'TEXT_T1_NEGATIVE_CONTROLS.json'
target.write_text(json.dumps(out,indent=2)+'\n',encoding='utf8')
print('5 genuine fail-closed mutations; original decimals and outward directions pass',h(target.read_bytes()))

