"""Binary row rescaling diagnostic for the two signed native SOC-WR angle inequalities."""
import csv
import hashlib
import json
import math
from pathlib import Path
import shutil
import sys
source = Path(sys.argv[1]).resolve()
target = Path(sys.argv[2]).resolve()
def digest(path):
    with path.open("rb") as f: return hashlib.file_digest(f,"sha256").hexdigest()
def read(path): return json.loads(path.read_bytes())
def write(path,data): path.write_text(json.dumps(data,indent=2),encoding="utf-8")
exp, profile = read(source/"export.json"), read(source/"profile.json")
original = source/"native.mps"
assert digest(original) == exp["native_mps_sha256"]
assert digest(source/"profile.json") == exp["profile_sha256"]
target.mkdir(exist_ok=False)
rows = set()
with original.open("rb") as f:
    for line in f:
        if not line.startswith(b" "):
            section=line.split()[0]
            if section==b"RHS": break
        elif section==b"COLUMNS":
            col,row,val=line.split()
            if abs(float(val)) == math.tan(math.pi/2):
                rows.add(row)
assert len(rows)==17472
records={k:[] for k in rows}
senses={}
with original.open("rb") as f, (target/"native.mps").open("xb") as out:
    for line in f:
        if not line.startswith(b" "):
            fields=line.split()
            section=fields[0]
            if section==b"QCMATRIX": assert fields[1] not in rows
        elif section in (b"ROWS",b"COLUMNS",b"RHS"):
            fields=line.split()
            if fields[1] in rows:
                row=fields[1]
                if section==b"ROWS":
                    senses[row]=fields[0]
                elif section==b"RHS":
                    assert float(fields[2])==0
                else:
                    col,row,val=fields
                    value=float(val)
                    scaled=math.ldexp(value,-26)
                    assert math.ldexp(scaled,26)==value
                    records[row].append(value)
                    line=b"    "+col+b"  "+row+b"  "+repr(scaled).encode()+b"\n"
        out.write(line)
assert len(senses)==17472
assert all(sorted(abs(v) for v in vals)==[1.,math.tan(math.pi/2)] for vals in records.values())
with (target/"scaled_angle_rows.csv").open("x",newline="") as f:
    w=csv.writer(f); w.writerow(["row","sense","multiplier"]); w.writerows((r.decode(),senses[r].decode(),2.**-26) for r in sorted(rows))
shutil.copyfile(source/"native_columns.csv",target/"native_columns.csv")
profile.update(parent_mps_sha256=exp["native_mps_sha256"],scaled_angle_rows=len(rows),angle_row_multiplier=2.**-26,scaling_source_sha256=digest(Path(__file__)),signed_row_manifest_sha256=digest(target/"scaled_angle_rows.csv"))
write(target/"profile.json",profile)
exp.update(profile_sha256=digest(target/"profile.json"),native_mps_sha256=digest(target/"native.mps"))
write(target/"export.json",exp)
print(exp,flush=True)