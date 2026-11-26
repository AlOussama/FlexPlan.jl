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


def export(source, reference, target):
    meta = json.loads((source / "export.json").read_bytes())
    point = json.loads((reference / "outcome.json").read_bytes())
    profile = json.loads((source / "profile.json").read_bytes())
    mps = source / "native.mps"
    assert digest(mps) == point["mps_sha256"] == meta["native_mps_sha256"]
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
    assert len(records) == len(sense) == 26208
    for row, terms in records.items():
        diagonals = {a:v for a,b,v in terms if a == b}
        if sense[row] == b"G":
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
            elif section == b"COLUMNS":
                col = line.split(None,1)[0]
                for row,coef in adds.pop(col, ()):
                    out.write(b"    "+col+b"  "+row+b"  "+repr(coef).encode()+b"\n")
            elif section == b"RHS":
                label,row,value = line.split()
                if row in rhs:
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
