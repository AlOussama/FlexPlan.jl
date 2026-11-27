"""Write an outer LP for a native weekly QCP using one supporting plane per cone."""
import collections
import json
import math
from fractions import Fraction
from pathlib import Path
import shutil
import sys

import numpy as np
from solve_ac_native import digest


def upward(x):
    value = float(x)
    return math.nextafter(value, math.inf) if Fraction(value) < x else value


def export(source, reference, target, reference_model=None):
    meta = json.loads((source / "export.json").read_bytes())
    point = json.loads((reference / "outcome.json").read_bytes())
    profile = json.loads((source / "profile.json").read_bytes())
    mps = source / "native.mps"
    assert digest(mps) == meta["native_mps_sha256"]
    anchor_model = reference_model or source
    assert digest(anchor_model/"native.mps") == point["mps_sha256"]
    assert digest(anchor_model/"native_columns.csv") == digest(source/"native_columns.csv")
    assert point["case_sha256"] == meta["case_sha256"]
    assert digest(reference / "native_primal.npy") == point["native_primal_sha256"]
    x = np.load(reference / "native_primal.npy", allow_pickle=False)
    records = collections.defaultdict(list)
    rhs, sense = {}, {}
    with mps.open("rb") as f:
        for line in f:
            if not line.startswith(b" "):
                fields = line.split()
                section = fields[0]
                if section == b"QCMATRIX":
                    name = fields[1]
            elif section == b"ROWS":
                s, row = line.split()
                if row.startswith(b"qc"):
                    sense[row] = s
            elif section == b"RHS":
                _, row, val = line.split()
                if row.startswith(b"qc"):
                    rhs[row] = float(val)
            elif section == b"QCMATRIX":
                a, b, v = line.split()
                records[name].append((a,b,float(v)))
    adds = collections.defaultdict(list)
    qcrm = profile["formulation"] == "QCRM"
    strength_cones = profile.get("strength_edge_cones",0)
    assert strength_cones == (8736 if profile.get("strength_method")=="G3" else 0)
    assert len(records) == len(sense) == (41160 if qcrm else 26208)+strength_cones
    for row, terms in records.items():
        diagonals = {a:v for a,b,v in terms if a == b}
        if qcrm and len(terms) == 1:
            a, = diagonals
            k = Fraction(diagonals[a])
            slope = float(2*k*Fraction(x[int(a[1:])]))
            # Complete the square for the rounded slope; RHS rounds outwards.
            limit = Fraction(rhs.get(row,0))+Fraction(slope)**2/(4*k)
            rhs[row] = upward(limit) if k>0 else -upward(-limit)
            adds[a].append((row,slope))
        elif qcrm and sense[row] == b"L" and len(terms) == 4:
            pairs = [(a,b) for a,b,v in terms if a!=b and v==-0.5]
            assert len(pairs)==2 and pairs[0]==pairs[1][::-1] and list(diagonals.values())==[1,1]
            u,v = pairs[0]
            direction = np.array([2*x[int(a[1:])] for a in diagonals]+[x[int(u[1:])]-x[int(v[1:])]])
            weights = np.trunc(direction/max(np.linalg.norm(direction),1e-30)*2**24).astype(np.int64)
            assert sum(int(i)**2 for i in weights) <= 2**48
            for a,w in zip(diagonals,weights):
                adds[a].append((row,2*float(w)/2**24))
            adds[u].append((row,float(weights[-1])/2**24-1))
            adds[v].append((row,-float(weights[-1])/2**24-1))
        elif sense[row] == b"G":
            head, = [a for a,v in diagonals.items() if v == 1]
            tail = [a for a,v in diagonals.items() if v == -1]
            assert len(tail)+1 == len(terms) and rhs.get(row,0) == 0
            direction = np.array([x[int(a[1:])] for a in tail])
            length = np.linalg.norm(direction)
            weights = np.trunc(direction / max(length,1e-30) * 2**24).astype(np.int64)
            assert sum(int(i)**2 for i in weights) <= 2**48
            adds[head].append((row,1.0))
            for a,v in zip(tail,weights):
                if v:
                    adds[a].append((row,-float(v)/2**24))
        elif len(terms) == 2:
            assert list(diagonals.values()) == [1,1] and sense[row] == b"L"
            direction = np.array([x[int(a[1:])] for a in diagonals])
            weights = np.trunc(direction/max(np.linalg.norm(direction),1e-30)*2**24).astype(np.int64)
            assert sum(int(i)**2 for i in weights) <= 2**48
            for a,v in zip(diagonals,weights):
                if v:
                    adds[a].append((row,float(v)/2**24))
            rhs[row] = math.nextafter(math.sqrt(rhs[row]),math.inf)
        else:
            a,b = diagonals
            k = diagonals[a]
            assert sense[row] == b"L" and rhs[row] == 1 and k == diagonals[b] > 0
            assert sorted(v for i,j,v in terms if i != j) == [-k,-k]
            slope = float(2*k*(x[int(a[1:])]-x[int(b[1:])]))
            adds[a].append((row,slope))
            adds[b].append((row,-slope))
            rhs[row] = math.nextafter(upward(1+Fraction(slope)**2/(4*Fraction(k))),math.inf)
    target.mkdir(exist_ok=False)
    with mps.open("rb") as f, (target/"native.mps").open("xb") as out:
        for line in f:
            if not line.startswith(b" "):
                section = line.split()[0]
                if section == b"QCMATRIX":
                    out.write(b"ENDATA\n")
                    break
                if section == b"BOUNDS" and qcrm:
                    for row in missing_rhs:
                        if rhs[row]:
                            out.write(b"    RHS1  "+row+b"  "+repr(rhs[row]).encode()+b"\n")
                if section == b"RHS":
                    missing_rhs = set(rhs)
            elif section == b"COLUMNS":
                col = line.split(None,1)[0]
                for row,coef in adds.pop(col, ()):
                    out.write(b"    "+col+b"  "+row+b"  "+repr(coef).encode()+b"\n")
            elif section == b"RHS":
                label,row,value = line.split()
                if row in rhs:
                    missing_rhs.discard(row)
                    line=b"    "+label+b"  "+row+b"  "+repr(rhs[row]).encode()+b"\n"
            out.write(line)
    assert not adds
    shutil.copyfile(source/"native_columns.csv",target/"native_columns.csv")
    profile.update(outer_lp=True, parent_mps_sha256=meta["native_mps_sha256"],
                   anchor_sha256=point["native_primal_sha256"])
    (target/"profile.json").write_text(json.dumps(profile,indent=2))
    meta.update(profile_sha256=digest(target/"profile.json"),native_mps_sha256=digest(target/"native.mps"))
    (target/"export.json").write_text(json.dumps(meta,indent=2))


if __name__ == "__main__":
    export(*(Path(p).resolve() for p in sys.argv[1:]))
