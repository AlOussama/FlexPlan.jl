"""Replay archived weekly candidates with the independent original-case evaluator."""
import csv
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

from solve_ac_native import digest


def polish_angles(x, model, manifest):
    with manifest.open() as stream:
        senses = {r["row"].encode(): r["sense"] for r in csv.DictReader(stream)}
    terms = defaultdict(list)
    with model.open("rb") as stream:
        for line in stream:
            if not line.startswith(b" "):
                section = line.split()[0]
                if section == b"BOUNDS":
                    break
            elif section == b"COLUMNS":
                col, row, val = line.split()
                if row in senses:
                    terms[row].append((int(col[1:]), float(val)))
    assert len(terms) == len(senses) == 17472
    before = x.copy()
    for row, pair in terms.items():
        (i, a), (j, b) = sorted(pair, key=lambda term: abs(term[1]))
        sign = 1 if senses[row] == "G" else -1
        assert abs(a) == 1 and sign*b == math.tan(math.pi/2)
        limit = math.nextafter(-a*x[i]/b, math.inf)
        x[j] = max(x[j], limit)
    return int(np.count_nonzero(before != x)), float(np.max(np.abs(before-x)))


def main(root, name, source, target):
    sys.path.insert(0, str(root))
    from independent_gold import F, GOLD, qa, read, reference, rows
    _, mode, metrics, original = reference(name)
    model = original / "native.mps"
    meta = read(original / "export.json")
    assert digest(model) == meta["native_mps_sha256"]
    assert digest(original / "native_columns.csv") == meta["native_columns_sha256"]
    assert digest(F / "AC_CASE/case.json") == meta["case_sha256"]
    inp = source / "native_primal.npy"
    parent = read(source / "outcome.json")
    assert digest(inp) == parent["native_primal_sha256"] and meta["case_sha256"] == parent["case_sha256"]
    x = np.load(inp)
    assert len(x) == meta["variables"] and np.isfinite(x).all()
    target.mkdir(exist_ok=False)
    changes = (0, 0.)
    if name == "SOC_G2":
        changes = polish_angles(x, model, root / "SOC_G2_model/scaled_angle_rows.csv")
    np.save(target / "native_primal.npy", x)
    mapped = {int(r["index"]): x[int(r["native"])] for r in rows(original / "native_columns.csv")}
    mapped[0] = 1.
    mat = qa.evaluate_native(model, x, meta["objective_divisor"])
    vals = qa.affine_metrics(metrics, mapped)
    phys = qa.physical_metrics(metrics, read(F / "AC_CASE/case.json"), mapped, vals)
    g2 = min(v for (k,h,i),v in vals.items() if k == "G2") if mode == "G2" else None
    cost = vals["cost",0,"0"]
    assert abs(cost-mat["annualized_EUR2025"]) < .02
    assert phys["quota_margin_MWh"] >= 0 and mat["max_any_constraint_violation"] <= 1e-6
    assert all(phys["largest_violations"][key]["value"] <= GOLD["original_KCL_MW"]["dimensioned_threshold"] for key in ("P_KCL_MW","Q_KCL_MVAr"))
    assert g2 is None or g2 >= -GOLD["G2_row_pu"]["dimensioned_threshold"]
    result = dict(executor="ORCH", evaluator_sha256=digest(Path(qa.__file__)), replay_sha256=digest(Path(__file__)),
                  original_mps_sha256=digest(model), case_sha256=meta["case_sha256"], parent_sha256=digest(inp),
                  primal_sha256=digest(target / "native_primal.npy"), modified_coordinates=changes[0],
                  max_modification=changes[1], cost_EUR2025=cost, min_g2=g2, physical=phys, original_matrix=mat)
    (target / "review.json").write_text(json.dumps(result,indent=2,allow_nan=False))
    print(name, cost, phys["quota_margin_MWh"], changes, mat, flush=True)


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve(), sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4]))
