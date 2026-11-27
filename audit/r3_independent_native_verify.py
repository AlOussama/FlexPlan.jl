"""Independent exact-binary-rational verifier of MOSEK bar PSD readback.

No optimizer is called. Input must be read back from the saved native task,
with expected affine entries exported independently from the original JuMP PSD.
"""
import argparse
import collections
from fractions import Fraction
import hashlib
import json
from pathlib import Path

if not __debug__:
    raise RuntimeError("Exact scientific checks require Python assertion checks enabled")


def rational(value):
    if isinstance(value, str):
        return Fraction(value) if "/" in value else Fraction(float(value))
    return Fraction(value)


def coefficients(columns, values):
    assert len(columns) == len(values), "column/value length mismatch"
    result = collections.defaultdict(Fraction)
    for column, value in zip(columns, values):
        result[int(column)] += rational(value)
    return {column: value for column, value in result.items() if value}


def signature(terms, constant):
    return tuple(sorted(terms.items())), constant


def verify(data):
    assert data["afe_bar_triplet_count"] == 0, "unexpected AFE coupling to PSD bars"
    assert data["bar_objective_triplet_count"] == 0, "unexpected objective coupling to PSD bars"
    dimensions = list(map(int, data["bar_dimensions"]))
    rows = {int(row["row"]): row for row in data["rows"]}
    assert len(rows) == len(data["rows"]), "duplicate native row id"
    triplets = data["bar_triplets"]
    fields = ("row", "bar", "i", "j", "value")
    assert len({len(triplets[key]) for key in fields}) == 1, "triplet array mismatch"
    incident = collections.defaultdict(lambda: collections.defaultdict(Fraction))
    for row, bar, i, j, value in zip(*(triplets[key] for key in fields)):
        row, bar, i, j = map(int, (row, bar, i, j))
        assert 1 <= bar <= len(dimensions), "bar id out of range"
        assert 1 <= i <= dimensions[bar - 1] and 1 <= j <= dimensions[bar - 1], "bar coordinate out of range"
        incident[row][(bar, min(i, j), max(i, j))] += rational(value)
    actual = collections.defaultdict(dict)
    native_columns = {int(item["native_column"]) for item in data["original_variables"]}
    assert len(native_columns) == len(data["original_variables"]), "original column map not injective"
    assert len({int(item["jump_index"]) for item in data["original_variables"]}) == len(native_columns), "duplicate original JuMP variable id"
    for row_id, entries in incident.items():
        entries = {key: value for key, value in entries.items() if value}
        assert len(entries) == 1, "PSD linking row has multiple or absent bar entries"
        (bar, i, j), stored = next(iter(entries.items()))
        trace_weight = stored * (1 if i == j else 2)
        assert abs(trace_weight) == 1, "linking bar trace coefficient is not exactly plus/minus one"
        row = rows[row_id]
        assert str(row["bound_key"]).upper() in ("MSK_BK_FX", "FX", "FIXED"), "PSD link row not fixed equality"
        lower, upper = rational(row["lower"]), rational(row["upper"])
        assert lower == upper, "unequal equality bounds"
        scalar = coefficients(row["columns"], row["values"])
        assert set(scalar) <= native_columns, "PSD link contains extra auxiliary scalar variable"
        # A*x + trace(B*Y) = b; Yij = b/w - A*x/w.
        reconstructed = signature({column: -value / trace_weight for column, value in scalar.items()}, lower / trace_weight)
        assert (i, j) not in actual[bar], "multiple native rows for one bar coordinate"
        actual[bar][i, j] = reconstructed
    expected = []
    expected_scalar_terms = 0
    expected_nonzero_constants = 0
    for block in data["expected_blocks"]:
        dimension = int(block["dimension"])
        entries = {}
        for entry in block["entries"]:
            i, j = sorted((int(entry["i"]), int(entry["j"])))
            assert 1 <= i <= j <= dimension, "expected coordinate outside block"
            assert (i, j) not in entries, "duplicate expected coordinate"
            terms = entry["terms"]
            entries[i, j] = signature(coefficients([t[0] for t in terms], [t[1] for t in terms]), rational(entry["constant"]))
            expected_scalar_terms += len(entries[i, j][0])
            expected_nonzero_constants += bool(entries[i, j][1])
        coordinates = {(i, j) for j in range(1, dimension + 1) for i in range(1, j + 1)}
        assert set(entries) == coordinates, "expected triangle incomplete"
        expected.append((block["hour"], dimension, tuple(sorted(entries.items()))))
    assert len(expected) == len(dimensions), "native/expected PSD block count differs"
    assert len({hour for hour, _, _ in expected}) == len(expected), "duplicate expected hour"
    actual_fingerprints = collections.defaultdict(list)
    for bar, dimension in enumerate(dimensions, 1):
        coordinates = {(i, j) for j in range(1, dimension + 1) for i in range(1, j + 1)}
        assert set(actual[bar]) == coordinates, "native bar triangle incomplete or extra"
        actual_fingerprints[dimension, tuple(sorted(actual[bar].items()))].append(bar)
    mapping = []
    for hour, dimension, entries in expected:
        candidates = actual_fingerprints.get((dimension, entries), [])
        assert len(candidates) == 1, "full native block fingerprint missing or ambiguous"
        mapping.append({"hour": hour, "bar": candidates.pop()})
    assert not any(actual_fingerprints.values()), "extra unmatched native PSD block"
    return {"status": "PASS", "method": "independent_exact_binary_rational_native_trace_readback",
            "blocks": len(expected), "positions": sum(d * (d + 1) // 2 for d in dimensions),
            "dimensions": dict(collections.Counter(dimensions)), "hour_to_bar": mapping,
            "native_bar_triplets": len(triplets["value"]),
            "exact_affine_scalar_terms": expected_scalar_terms,
            "exact_nonzero_constants": expected_nonzero_constants,
            "exact_link_rows": len(incident),
            "symmetric_trace_offdiagonal_multiplier": 2,
            "native_link_trace_weights": "+1_or_-1_exact", "sqrt2_used": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("readback", type=Path)
    parser.add_argument("--expected", type=Path)
    parser.add_argument("--task", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    raw = args.readback.read_bytes()
    data = json.loads(raw)
    if args.expected:
        expected_raw = args.expected.read_bytes()
        expected_sha = hashlib.sha256(expected_raw).hexdigest()
        assert data["expected_psd_sha256"] == expected_sha, "expected PSD SHA binding differs"
        expected = json.loads(expected_raw)
        assert not set(expected) & set(data), "expected/readback schema overlaps"
        data.update(expected)
    if args.task:
        assert hashlib.sha256(args.task.read_bytes()).hexdigest() == data["native_task_sha256"], "native task SHA binding differs"
    result = verify(data)
    if args.expected:
        result["expected_psd_sha256"] = expected_sha
    if args.task:
        result["native_task_sha256"] = data["native_task_sha256"]
    result["input_sha256"] = hashlib.sha256(raw).hexdigest()
    result["verifier_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    text = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
