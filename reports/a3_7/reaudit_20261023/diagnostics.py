"""Replay reviewed diagnostic recipes with only output/input path substitutions."""
from execute import *
import hashlib
T=R/'submitted_tools/continuation'; D=R/'diagnostics'; D.mkdir(exist_ok=True)
def adapt(name):
    source=(T/name).read_text()
    text=source.replace('D:/Downloads/A3_7_B1_preflight_20261022_203803',str((R/'validation/prior/original_01').as_posix()))
    text=text.replace('original_G3.mof.json','b1_exact_native.mof.json')
    text=text.replace('integrity/prior/','../validation/prior/')
    target=D/name;target.write_text(text,encoding='utf-8')
    (D/(name+'.adaptation.json')).write_text(json.dumps(dict(source_sha256=hashlib.sha256(source.encode()).hexdigest(),
        adapted_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),original=str(T/name),
        changes='only external input paths and literal input filename; @__DIR__ relocates output'),indent=2))
    return target
if __name__=='__main__':
    mode=sys.argv[1]
    if mode=='commercial':
        script=adapt('candidate_diagnostics.jl')
        jl('raw_gurobi',script,'Gurobi');jl('raw_mosek',script,'MOSEK')
    elif mode=='pajarito':
        jl('pajarito_double_gap',adapt('pajarito_double_gap.jl'))
        jl('pajarito_original_gap',adapt('pajarito_gap_diagnosis.jl'))
        jl('filter_regressions',adapt('filter_regressions.jl'))
    else: raise ValueError(mode)
