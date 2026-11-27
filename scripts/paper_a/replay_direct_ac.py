"""Replay a weekly G3 native primal in the unscaled MPS and all 168 original PSD matrices."""
import json
import sys
from pathlib import Path

import numpy as np

from solve_ac_native import digest


def replay(study, model, solved):
    sys.path.insert(0, str(study / "BASE_PAIR_20261126"))
    import independent_base_point as qa

    result = qa.read(solved / "outcome.json")
    meta = qa.read(model / "export.json")
    profile = qa.read(model / "profile.json")
    case = study / "CONFIRMED_QBOX/AC_CASE/case.json"
    assert meta["case_sha256"] == result["case_sha256"] == digest(case)
    assert digest(model / "native.mps") == meta["native_mps_sha256"]
    assert digest(model / "profile.json") == meta["profile_sha256"]
    assert digest(model / "native_columns.csv") == meta["native_columns_sha256"]
    assert profile["strength_method"] == result["strength_method"] == "G3"
    assert profile["G2_rows"] == 0 and profile["strength_edge_cones"] == 8736
    if result["mps_sha256"] != meta["native_mps_sha256"]:
        scaled = model.with_name(model.name + "_scaled")
        assert qa.read(scaled / "profile.json")["parent_mps_sha256"] == meta["native_mps_sha256"]
        assert digest(scaled / "native.mps") == result["mps_sha256"]
    report = dict(termination=result["termination"], result_count=result["result_count"],
                  source_mps_sha256=meta["native_mps_sha256"], case_sha256=meta["case_sha256"],
                  outcome_sha256=digest(solved/"outcome.json"), evaluator_sha256=digest(Path(qa.__file__)))
    if result["result_count"]:
        assert digest(solved / "native_primal.npy") == result["native_primal_sha256"]
        native = np.load(solved / "native_primal.npy")
        primal = {int(r["index"]): native[int(r["native"])] for r in qa.rows(model/"native_columns.csv")}
        primal[0] = 1.
        values = qa.affine_metrics(model, primal)
        matrices = np.zeros((168,37,37))
        terms = 0
        for (metric,h,key), value in values.items():
            if metric == "M":
                i,j = (int(k)-1 for k in key.split("_"))
                assert 1<=h<=168 and 0<=i<=j<37
                matrices[h-1,i,j] = matrices[h-1,j,i] = value
                terms += 1
        assert terms == 168*37*38//2
        eigen = np.linalg.eigvalsh(matrices)[:,0]
        check = qa.evaluate_native(model/"native.mps", native, meta["objective_divisor"])
        physical = qa.physical_metrics(model, qa.read(case), primal, values)
        assert abs(check["annualized_EUR2025"]-values["cost",0,"0"]) < .02
        report.update(original_matrix=check,physical=physical,hourly_minimum_eigenvalues=eigen.tolist(),
                      minimum_eigenvalue=eigen.min(),original_cost_EUR2025=values["cost",0,"0"],
                      primal_sha256=result["native_primal_sha256"],audit_terms_sha256=digest(model/"audit_terms.csv"))
    with (solved/"original_gscr_replay.json").open("x") as stream:
        json.dump(report,stream,indent=2,allow_nan=False)


if __name__ == "__main__":
    replay(*(Path(p).resolve() for p in sys.argv[1:]))
