"""Pre-evaluation integrity and coordinate checks for original-point replay."""
import csv
import hashlib
import json
import math
from pathlib import Path

SCHEMA = "paper_a_original_replay_inputs/1"


class EvidenceError(ValueError):
    pass


def digest(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def record(path):
    path = Path(path).resolve()
    return dict(path=str(path), bytes=path.stat().st_size, sha256=digest(path))


def verify_manifest(path, required):
    manifest = read_json(path)
    if manifest.get("schema") != SCHEMA:
        raise EvidenceError("Unsupported input manifest")
    entries = manifest["inputs"]
    if set(required) - set(entries):
        raise EvidenceError("Missing input roles: " + str(sorted(set(required) - set(entries))))
    paths = {}
    for role, entry in entries.items():
        source = Path(entry["path"])
        if not source.is_file() or source.stat().st_size != entry["bytes"] or digest(source) != entry["sha256"]:
            raise EvidenceError("Missing or changed input: " + role)
        paths[role] = source
    return manifest, paths


def rows(path):
    with open(path, newline="", encoding="utf-8-sig") as stream:
        yield from csv.DictReader(stream)


def validate_mapping(path, size):
    mapping = {}
    natives = set()
    for row in rows(path):
        index, native = int(row["index"]), int(row["native"])
        if index <= 0 or index in mapping or native in natives or not 0 <= native < size:
            raise EvidenceError("Duplicate or invalid native mapping")
        mapping[index] = native
        natives.add(native)
    if not mapping or set(mapping) != set(range(1, len(mapping) + 1)):
        raise EvidenceError("Incomplete original coordinate roster")
    return mapping


def validate_ledgers(audit, terminals, mapping, hours=168, regions=37, bus_ids=None):
    seen, groups, constants, matrix = set(), set(), set(), set()
    for row in rows(audit):
        key = (row["metric"], int(row["hour"]), row["id"])
        index, coefficient = int(row["index"]), float(row["coefficient"])
        full = key + (index,)
        if full in seen or not math.isfinite(coefficient) or (index != 0 and index not in mapping):
            raise EvidenceError("Duplicate, nonfinite or unknown affine coordinate")
        seen.add(full)
        groups.add(key)
        if index == 0:
            constants.add(key)
        if key[0] == "M":
            matrix.add(key)
    expected = {("M", h, f"{i}_{j}") for h in range(1, hours + 1)
                for i in range(1, regions + 1) for j in range(i, regions + 1)}
    if matrix != expected or groups != constants:
        raise EvidenceError("Missing or unexpected full matrix key or expression constant")
    if bus_ids is not None:
        expected_balance={(metric,h,str(bus)) for metric in ("P","Q")
                          for h in range(1,hours+1) for bus in bus_ids}
        if {key for key in groups if key[0] in ("P","Q")} != expected_balance:
            raise EvidenceError("Missing or unexpected nodal balance coordinate")
        if not {("cost",0,"0"),("wind_pv",0,"0")} <= groups:
            raise EvidenceError("Missing objective or quota expression")
    seen_terminals = set()
    for row in rows(terminals):
        key = (row["type"], int(row["hour"]), row["id"], row["end_bus"])
        if key in seen_terminals or not 1 <= key[1] <= hours:
            raise EvidenceError("Duplicate or invalid terminal key")
        seen_terminals.add(key)
        for field in ("p_index", "q_index", "online_index"):
            index = int(row[field])
            if (index == 0 and field != "online_index") or (index != 0 and index not in mapping):
                raise EvidenceError("Unknown terminal coordinate")
        if not all(math.isfinite(float(row[f])) for f in ("q_factor_pu", "rating_pu")):
            raise EvidenceError("Nonfinite terminal coefficient")
    if not seen_terminals:
        raise EvidenceError("Empty terminal roster")
    return dict(matrix_positions=len(matrix), affine_terms=len(seen), terminals=len(seen_terminals))
