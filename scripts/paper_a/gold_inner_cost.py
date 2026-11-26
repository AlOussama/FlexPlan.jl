"""Search for original-feasible weekly incumbents in an inscribed polyhedron."""
import collections
import itertools
import json
import math
from fractions import Fraction
from pathlib import Path
import shutil
import sys

import numpy as np
from solve_ac_native import digest
from gold_outer_cost import upward


def export(source, reference, target):
    meta = json.loads((source/"export.json").read_bytes())
    profile = json.loads((source/"profile.json").read_bytes())
    point = json.loads((reference/"outcome.json").read_bytes())
    mps = source/"native.mps"
    assert digest(mps) == meta["native_mps_sha256"] == point["mps_sha256"]
    assert digest(reference/"native_primal.npy") == point["native_primal_sha256"]
    x = np.load(reference/"native_primal.npy",allow_pickle=False)
    affine, rhs, sense = {}, {}, {}
    records = collections.defaultdict(list)
    with mps.open("rb") as f:
        for line in f:
            if not line.startswith(b" "):
                fields = line.split()
                section = fields[0]
                if section == b"QCMATRIX":
                    name = fields[1]
            elif section in (b"ROWS",b"COLUMNS",b"RHS"):
                fields = line.split()
                row = fields[1]
                if row.startswith(b"qc"):
                    if section == b"ROWS":
                        sense[row] = fields[0]
                    elif section == b"COLUMNS":
                        assert row not in affine and float(fields[2]) == 1
                        affine[row] = fields[0]
                    else:
                        rhs[row] = float(fields[2])
            elif section == b"QCMATRIX":
                a,b,v = line.split()
                records[name].append((a,b,float(v)))
    assert len(records) == len(sense) == 26208
    planes = []
    columns = collections.defaultdict(list)

    def add(terms, limit):
        row = b"I"+str(len(planes)).encode()
        planes.append((row,limit))
        for col,c in terms:
            if c:
                columns[col].append((row,float(c)))

    for row, terms in records.items():
        diag = {a:v for a,b,v in terms if a==b}
        if row in affine:
            a,b = diag
            k = Fraction(diag[a])
            assert len(terms)==4 and diag[a]==diag[b]>0 and rhs[row]==1 and sense[row]==b"L"
            assert sorted(v for i,j,v in terms if i!=j)==[-float(k),-float(k)]
            # Restrict delta to an exact dyadic interval. The secant majorizes
            # k*delta^2 there. Use a dyadic slope and enforce both end values.
            mid = Fraction(round((x[int(a[1:])]-x[int(b[1:])])*65536),65536)
            lo,hi = mid-Fraction(1,1024),mid+Fraction(1,1024)
            slope = Fraction(round(k*(lo+hi)*2**24),2**24)
            intercept = max(k*d*d-slope*d for d in (lo,hi))
            add([(a,1),(b,-1)],float(hi))
            add([(b,1),(a,-1)],float(-lo))
            add([(a,slope),(b,-slope),(affine[row],1)],-upward(intercept-1))
            continue
        head = None
        if sense[row]==b"G":
            head, = [a for a,v in diag.items() if v==1]
            tail = [a for a,v in diag.items() if v==-1]
            assert len(tail)+1==len(terms) and rhs.get(row,0)==0
        else:
            assert len(terms)==2 and list(diag.values())==[1,1] and sense[row]==b"L"
            tail = list(diag)
        # An integer Householder reflector rotates the L1 ball so that one
        # vertex nearly points towards the reference. All normals are dyadic.
        direction = np.array([x[int(a[1:])] for a in tail])
        direction /= max(np.linalg.norm(direction),1e-30)
        direction[0] += 1 if direction[0]>=0 else -1
        v = np.rint(direction*2048).astype(np.int64)
        den = int(v@v)
        numerator = den*np.eye(len(tail),dtype=np.int64)-2*np.outer(v,v)
        scale = 2**den.bit_length()
        radius = 0 if head else math.nextafter(math.sqrt(rhs[row]),-math.inf)
        limit = 0 if head else -upward(-Fraction(radius)*den/scale)
        for signs in itertools.product((-1,1),repeat=len(tail)):
            coefficients = np.asarray(signs)@numerator
            terms = [(a,int(c)/scale) for a,c in zip(tail,coefficients)]
            if head:
                terms.append((head,-den/scale))
            add(terms,limit)
    target.mkdir(exist_ok=False)
    with mps.open("rb") as f, (target/"native.mps").open("xb") as out:
        for line in f:
            if not line.startswith(b" "):
                section = line.split()[0]
                if section == b"COLUMNS":
                    for row,_ in planes:
                        out.write(b" L  "+row+b"\n")
                elif section == b"BOUNDS":
                    for row,limit in planes:
                        if limit:
                            out.write(b"    RHS1  "+row+b"  "+repr(limit).encode()+b"\n")
                elif section == b"QCMATRIX":
                    out.write(b"ENDATA\n")
                    break
            elif section in (b"ROWS",b"COLUMNS",b"RHS"):
                fields = line.split()
                if section == b"COLUMNS":
                    for row,c in columns.pop(fields[0],()):
                        out.write(b"    "+fields[0]+b"  "+row+b"  "+repr(c).encode()+b"\n")
                if fields[1] in sense:
                    continue
            out.write(line)
    assert not columns
    shutil.copyfile(source/"native_columns.csv",target/"native_columns.csv")
    profile.update(inner_lp=True,parent_mps_sha256=meta["native_mps_sha256"],anchor_sha256=point["native_primal_sha256"])
    (target/"profile.json").write_text(json.dumps(profile,indent=2))
    meta.update(profile_sha256=digest(target/"profile.json"),native_mps_sha256=digest(target/"native.mps"))
    (target/"export.json").write_text(json.dumps(meta,indent=2))


if __name__ == "__main__":
    export(*(Path(p).resolve() for p in sys.argv[1:]))
