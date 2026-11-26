"""Derive the paired KW8 BASE model from the reviewed native G2 export."""
import csv
import json
import math
from pathlib import Path
import shutil
import sys

from solve_ac_native import digest


def read_json(path):
    return json.loads(path.read_bytes())


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, allow_nan=False), encoding="utf-8")


def read_g2_terms(source):
    with (source / "native_columns.csv").open() as f:
        columns = {int(r["index"]): ("V" + r["native"]).encode() for r in csv.DictReader(f)}
    vectors = {}
    rhs = {}
    with (source / "audit_terms.csv").open() as f:
        for r in csv.DictReader(f):
            if r["metric"] != "G2":
                continue
            key = int(r["hour"]), int(r["id"])
            index = int(r["index"])
            coefficient = float(r["coefficient"])
            if index == 0:
                if key in rhs:
                    raise ValueError("Duplicate G2 constant")
                rhs[key] = -coefficient
                vectors[key] = {}
            elif coefficient:
                vectors[key][columns[index]] = coefficient
    assert set(rhs) == {(h, i) for h in range(1, 169) for i in range(1, 38)}
    return vectors, rhs


def identify_rows(mps, vectors, rhs):
    candidates = {}
    signs = {}
    bounds = {}
    with mps.open("rb") as f:
        for line in f:
            fields = line.split()
            if not line.startswith(b" "):
                section = fields[0]
                if section == b"BOUNDS":
                    break
            elif section == b"ROWS" and fields[0] in (b"L", b"G"):
                name = fields[1]
                candidates[name] = {}
                signs[name] = 1 if fields[0] == b"G" else -1
            elif section in (b"COLUMNS", b"RHS"):
                for name, raw in zip(fields[1::2], fields[2::2], strict=True):
                    if name not in candidates:
                        continue
                    value = float(raw) * signs[name]
                    if section == b"RHS":
                        bounds[name] = value
                    elif value:
                        candidates[name][fields[0]] = value
    signatures = {}
    for key, vector in vectors.items():
        signatures.setdefault(frozenset(vector), []).append(key)
    matches = {}
    def close(a, b):
        return math.isclose(a, b, rel_tol=1e-11, abs_tol=1e-12)
    for name, terms in candidates.items():
        for key in signatures.get(frozenset(terms), ()):
            if close(bounds.get(name, 0), rhs[key]) and all(close(v, vectors[key][c]) for c, v in terms.items()):
                if key in matches:
                    raise ValueError(f"Ambiguous native G2 row for {key}")
                matches[key] = name
    assert matches.keys() == vectors.keys() and len(set(matches.values())) == 6216
    return matches


def write_base(source, destination, removed):
    counts = {"ROWS": 0, "COLUMNS": 0, "RHS": 0}
    with source.open("rb") as original, destination.open("xb") as base:
        for line in original:
            if not line.startswith(b" "):
                section = line.split()[0]
                if section == b"QCMATRIX" and line.split()[1] in removed:
                    raise ValueError("G2 row has quadratic terms")
            elif section in (b"ROWS", b"COLUMNS", b"RHS"):
                fields = line.split()
                if fields[1] in removed:
                    if section != b"ROWS" and len(fields) != 3:
                        raise ValueError("Mixed MPS record requires separate handling")
                    counts[section.decode()] += 1
                    continue
                if len(fields) > 3 and fields[3] in removed:
                    raise ValueError("Unexpected packed MPS record")
            base.write(line)
    assert counts["ROWS"] == 6216
    return counts


def export_base(source, directory):
    export = read_json(source / "export.json")
    profile = read_json(source / "profile.json")
    qa = read_json(source / "independent_native_export_replay.json")
    mps = source / "native.mps"
    assert digest(mps) == export["native_mps_sha256"] == qa["native_mps_sha256"]
    assert digest(source / "native_columns.csv") == export["native_columns_sha256"] == qa["map_sha256"]
    assert digest(source / "profile.json") == export["profile_sha256"] == qa["profile_sha256"]
    assert digest(source / "audit_terms.csv") == qa["reference_audit_terms_sha256"]
    assert export["case_sha256"] == qa["case_sha256"] == "66885c9b5d27b21ac1000cf16e8da5d886b7ab50085783957907cebef8a41d3b"
    assert profile["G2_rows"] == 6216 and profile["discrete_after_relaxation"] == 0
    vectors, rhs = read_g2_terms(source)
    matches = identify_rows(mps, vectors, rhs)
    directory.mkdir(exist_ok=False)
    counts = write_base(mps, directory / "native.mps", set(matches.values()))
    with (directory / "removed_g2_rows.csv").open("x", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(("hour", "id", "mps_row"))
        writer.writerows((h, i, matches[h, i].decode()) for h, i in sorted(matches))
    shutil.copyfile(source / "native_columns.csv", directory / "native_columns.csv")
    profile.update(strength_method="BASE", G2_rows=0, parent_export=str(source),
                   original_mps_sha256=export["native_mps_sha256"], removed_records=counts,
                   removed_rows_sha256=digest(directory / "removed_g2_rows.csv"),
                   base_exporter_sha256=digest(Path(__file__)))
    write_json(directory / "profile.json", profile)
    export.update(native_mps_sha256=digest(directory / "native.mps"),
                  profile_sha256=digest(directory / "profile.json"))
    write_json(directory / "export.json", export)
    print(profile["formulation"], counts, export["native_mps_sha256"], flush=True)


if __name__ == "__main__":
    export_base(*(Path(arg).resolve() for arg in sys.argv[1:]))
