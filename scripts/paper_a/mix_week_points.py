"""Create a traceable convex-combination candidate for original-model replay."""
import csv
import json
import sys
from pathlib import Path

import numpy as np

from solve_ac_native import digest


def mix(first, second, original, weight, target):
    export = json.loads((original / "export.json").read_bytes())
    columns = original / "native_columns.csv"
    assert digest(columns) == export["native_columns_sha256"]
    assert 0 < weight < 1
    parents = []
    vectors = []
    for folder in (first, second):
        data = json.loads((folder / "outcome.json").read_bytes())
        assert data["case_sha256"] == export["case_sha256"]
        assert digest(folder / "native_primal.npy") == data["native_primal_sha256"]
        vector = np.load(folder / "native_primal.npy")
        assert vector.shape == (export["variables"],)
        with columns.open() as names, (folder / "primal.csv").open() as mapped:
            for col, row in zip(csv.DictReader(names), csv.DictReader(mapped), strict=True):
                assert col["index"] == row["index"]
                assert vector[int(col["native"])] == float(row["value"])
        vectors.append(vector)
        parents.append(data)
    x = vectors[0] + weight * (vectors[1] - vectors[0])
    target.mkdir(exist_ok=False)
    np.save(target / "native_primal.npy", x)
    with columns.open() as names, (target / "primal.csv").open("x", newline="") as out:
        writer = csv.writer(out)
        writer.writerow(("index", "value"))
        for col in csv.DictReader(names):
            writer.writerow((col["index"], x[int(col["native"])]))
    data = dict(termination="CONSTRUCTED", objective_kind="convex_combination", result_count=1,
                native_status=None, formulation=parents[0]["formulation"], strength_method=parents[0]["strength_method"],
                mps_sha256=export["native_mps_sha256"], case_sha256=export["case_sha256"],
                parent_points=[p["native_primal_sha256"] for p in parents], second_weight=weight,
                annualized_EUR2025=(1-weight)*parents[0]["annualized_EUR2025"]+weight*parents[1]["annualized_EUR2025"],
                primal_sha256=digest(target / "primal.csv"), native_primal_sha256=digest(target / "native_primal.npy"))
    (target / "outcome.json").write_text(json.dumps(data, indent=2))


if __name__ == "__main__":
    mix(*map(Path, sys.argv[1:4]), float(sys.argv[4]), Path(sys.argv[5]))
