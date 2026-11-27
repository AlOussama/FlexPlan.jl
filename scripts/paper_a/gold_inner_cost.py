"""Search for original-feasible weekly incumbents in an inscribed polyhedron."""
import collections
import itertools
import json
import math
import os
from fractions import Fraction
from pathlib import Path
import shutil
import sys

import numpy as np
from solve_ac_native import digest
from gold_outer_cost import upward


def export(source, reference, target, reference_model=None):
    meta = json.loads((source/"export.json").read_bytes())
    profile = json.loads((source/"profile.json").read_bytes())
    point = json.loads((reference/"outcome.json").read_bytes())
    mps = source/"native.mps"
    assert digest(mps) == meta["native_mps_sha256"]
    anchor_model = reference_model or source
    assert digest(anchor_model/"native.mps") == point["mps_sha256"]
    assert digest(anchor_model/"native_columns.csv") == digest(source/"native_columns.csv")
    assert point["case_sha256"] == meta["case_sha256"]
    assert digest(reference/"native_primal.npy") == point["native_primal_sha256"]
    x = np.load(reference/"native_primal.npy",allow_pickle=False)
    affine, rhs, sense = {}, {}, {}
    records = collections.defaultdict(list)
    domains = collections.defaultdict(dict)
    wide = profile["formulation"] == "QCRM" and os.getenv("PAPER_A_QCRM_WIDE_INNER") == "1"
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
            elif wide and section == b"BOUNDS":
                fields = line.split()
                if fields[0] in (b"LO",b"UP",b"FX"):
                    domains[fields[2]][fields[0]] = float(fields[3])
    qcrm = profile["formulation"] == "QCRM"
    assert len(records) == len(sense) == (41160 if qcrm else 26208)
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
        if qcrm and row in affine:
            # Both univariate parabolas use the secant over a dyadic interval.
            a, = diag
            assert len(terms) == 1
            sign = 1 if sense[row] == b"L" else -1
            k = Fraction(diag[a])*sign
            assert k > 0
            mid = Fraction(round(x[int(a[1:])]*65536),65536)
            if wide:
                lo = Fraction(domains[a].get(b"LO",0))
                hi = Fraction(domains[a][b"UP"])
                knots = sorted({lo,hi,min(hi,max(lo,mid)),*(lo+(hi-lo)*i/4 for i in (1,2,3))})
                for left,right in zip(knots,knots[1:]):
                    slope = Fraction(float(k*(left+right)))
                    excess = max(k*z*z-slope*z for z in (left,right))
                    add([(a,slope),(affine[row],sign)],-upward(excess-sign*rhs.get(row,0)))
                continue
            lo, hi = mid-Fraction(1,1024), mid+Fraction(1,1024)
            slope = Fraction(round(k*(lo+hi)*2**24),2**24)
            excess = max(k*z*z-slope*z for z in (lo,hi))
            add([(a,1)],float(hi))
            add([(a,-1)],float(-lo))
            add([(a,slope),(affine[row],sign)],-upward(excess-sign*rhs.get(row,0)))
            continue
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
        rotated = qcrm and len(terms)==4
        if rotated:
            # ||(2p,2q,u-v)|| <= u+v for p²+q² <= uv.
            pairs = [(a,b) for a,b,c in terms if a!=b and c==-0.5]
            assert len(pairs)==2 and pairs[0]==pairs[1][::-1] and list(diag.values())==[1,1]
            u,vcol = pairs[0]
            tail = list(diag)
        elif sense[row]==b"G":
            head, = [a for a,v in diag.items() if v==1]
            tail = [a for a,v in diag.items() if v==-1]
            assert len(tail)+1==len(terms) and rhs.get(row,0)==0
        else:
            assert len(terms)==2 and list(diag.values())==[1,1] and sense[row]==b"L"
            tail = list(diag)
        # An integer Householder reflector rotates the L1 ball so that one
        # vertex nearly points towards the reference. All normals are dyadic.
        direction = np.array([x[int(a[1:])] for a in tail])
        if rotated:
            direction = np.append(2*direction,x[int(u[1:])]-x[int(vcol[1:])])
        direction /= max(np.linalg.norm(direction),1e-30)
        if rotated and wide:
            from scipy.spatial import ConvexHull
            # Every vertex is inside the unit ball. Both zero-power poles
            # remain available even when the anchor carries substantial flow.
            grid = 1024
            axes = np.eye(3,dtype=np.int64)*grid
            vertex = np.trunc(direction*grid).astype(np.int64)
            vertices = np.unique(np.vstack([axes,-axes,*[vertex*np.array(s)
                for s in itertools.product((-1,1),repeat=3)]]),axis=0)
            assert np.all((vertices*vertices).sum(axis=1)<=grid**2)
            facets = set()
            for face in ConvexHull(vertices).simplices:
                i,j,l = vertices[face]
                normal = np.cross(j-i,l-i)
                offset = int(normal@i)
                if offset < 0:
                    normal,offset = -normal,-offset
                assert offset>0 and np.max(vertices@normal)<=offset
                p,q,z = (int(n)*grid for n in normal)
                coefs = (2*p,2*q,z-offset,-z-offset)
                divisor = math.gcd(*coefs)
                facets.add(tuple(c//divisor for c in coefs))
            for coefs in sorted(facets):
                scale = 2**max(abs(c) for c in coefs).bit_length()
                add(list(zip([*tail,u,vcol],[c/scale for c in coefs])),0)
            continue
        direction[0] += 1 if direction[0]>=0 else -1
        v = np.rint(direction*2048).astype(np.int64)
        den = int(v@v)
        numerator = den*np.eye(len(direction),dtype=np.int64)-2*np.outer(v,v)
        scale = 2**den.bit_length()
        radius = 0 if head or rotated else math.nextafter(math.sqrt(rhs[row]),-math.inf)
        limit = -upward(-Fraction(radius)*den/scale)
        for signs in itertools.product((-1,1),repeat=len(direction)):
            coefficients = np.asarray(signs)@numerator
            terms = [(a,int(c)/scale) for a,c in zip(tail,coefficients)]
            if rotated:
                terms = [(a,2*c) for a,c in terms]
                last = int(coefficients[-1])
                terms.extend([(u,(last-den)/scale),(vcol,(-last-den)/scale)])
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
                if wide and section == b"RHS" and abs(float(fields[2])-0.70*meta["demand_MWh"])<1e-5:
                    # The positive weekly production floor is tightened only
                    # for the witness search to allow original-coordinate replay.
                    line = b"    RHS1  "+fields[1]+b"  "+repr(float(fields[2])+1.).encode()+b"\n"
            elif wide and section == b"BOUNDS":
                fields = line.split()
                if fields[0] == b"LO" and 5e-17 < float(fields[3]) < 6e-17:
                    line = b" LO BND1  "+fields[2]+b"  1e-7\n"
            out.write(line)
    assert not columns
    shutil.copyfile(source/"native_columns.csv",target/"native_columns.csv")
    profile.update(inner_lp=True,parent_mps_sha256=meta["native_mps_sha256"],anchor_sha256=point["native_primal_sha256"])
    if wide:
        profile["qcrm_inner_geometry"] = "full_box_secants_and_inscribed_hull_with_axial_vertices"
    (target/"profile.json").write_text(json.dumps(profile,indent=2))
    meta.update(profile_sha256=digest(target/"profile.json"),native_mps_sha256=digest(target/"native.mps"))
    (target/"export.json").write_text(json.dumps(meta,indent=2))


if __name__ == "__main__":
    export(*(Path(p).resolve() for p in sys.argv[1:]))
