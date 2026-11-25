"""Solve the PowerModels-exported weekly QCP after its Julia builder exits."""
import csv
import ctypes as ct
import hashlib
import json
import os
from pathlib import Path
import sys

import numpy as np
import psutil


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def solve(source, directory=None):
    if directory is None:
        directory = source
    else:
        directory.mkdir(exist_ok=False)
    export = json.loads((source / "export.json").read_bytes())
    profile = json.loads((source / "profile.json").read_bytes())
    mps = source / "native.mps"
    columns = source / "native_columns.csv"
    for file, key in ((mps, "native_mps_sha256"), (columns, "native_columns_sha256"),
                      (source / "profile.json", "profile_sha256")):
        assert digest(file) == export[key]
    outcome = directory / "outcome.json"
    log = directory / "native_solver.log"
    if outcome.exists() or log.exists():
        raise FileExistsError("Use a fresh native solver output")
    lib = ct.WinDLL(export["solver_library"])
    version = [ct.c_int() for _ in range(3)]
    lib.GRBversion(*(ct.byref(v) for v in version))
    solver_version = ".".join(str(v.value) for v in version)
    assert solver_version == export["solver_version"]
    env, model = ct.c_void_p(), ct.c_void_p()

    def call(name, *args):
        code = getattr(lib, name)(*args)
        if code:
            raise RuntimeError((name, code))

    def integer(key):
        result = ct.c_int()
        call("GRBgetintattr", model, key.encode(), ct.byref(result))
        return result.value

    def real(key):
        result = ct.c_double()
        call("GRBgetdblattr", model, key.encode(), ct.byref(result))
        return result.value

    call("GRBemptyenv", ct.byref(env))
    try:
        focus = int(os.environ.get("PAPER_A_AC_NUMERIC_FOCUS", 2 if profile["formulation"] == "LPAC" else 3))
        threads = int(os.environ.get("PAPER_A_AC_THREADS", 1))
        homogeneous = int(os.environ.get("PAPER_A_AC_HOMOGENEOUS", 1))
        order = int(os.environ.get("PAPER_A_AC_BAR_ORDER", -1))
        for key, value in ((b"Threads", threads), (b"NumericFocus", focus), (b"Seed", 1),
                           (b"BarHomogeneous", homogeneous), (b"BarOrder", order)):
            call("GRBsetintparam", env, key, value)
        scaling = int(os.environ.get("PAPER_A_AC_SCALING", -1 if profile["formulation"] == "LPAC" else 2))
        call("GRBsetintparam", env, b"ScaleFlag", scaling)
        barrier_tolerance = float(os.environ.get("PAPER_A_AC_BARRIER_TOL", "1e-8"))
        feasibility_tolerance = float(os.environ.get("PAPER_A_AC_FEASIBILITY_TOL", "1e-6"))
        for key, value in ((b"BarQCPConvTol", barrier_tolerance), (b"FeasibilityTol", feasibility_tolerance), (b"TimeLimit", 7200.0)):
            call("GRBsetdblparam", env, key, ct.c_double(value))
        call("GRBsetstrparam", env, b"LogFile", os.fsencode(log))
        call("GRBstartenv", env)
        call("GRBreadmodel", env, os.fsencode(mps), ct.byref(model))
        n = integer("NumVars")
        assert n == export["variables"] and integer("NumIntVars") == 0
        assert integer("ModelSense") == 1
        names = (ct.c_char_p * n)()
        call("GRBgetstrattrarray", model, b"VarName", 0, n, names)
        positions = np.full(n, -1, dtype=np.int32)
        for col, name in enumerate(names):
            assert name.startswith(b"V")
            positions[int(name[1:])] = col
        assert np.min(positions) >= 0
        call("GRBoptimize", model)
        status, count = integer("Status"), integer("SolCount")
        labels = {2: "OPTIMAL", 3: "INFEASIBLE", 4: "INF_OR_UNBD", 5: "UNBOUNDED",
                  9: "TIME_LIMIT", 12: "NUMERIC", 13: "SUBOPTIMAL", 17: "MEMORY_LIMIT"}
        result = dict(termination=labels.get(status, str(status)), native_status=status,
                      result_count=count, seconds=real("Runtime"), formulation=profile["formulation"], solver_version=solver_version,
                      case_sha256=export["case_sha256"], mps_sha256=export["native_mps_sha256"],
                      threads=threads,numeric_focus=focus,scale_flag=scaling,bar_homogeneous=homogeneous,bar_order=order,
                      barrier_tolerance=barrier_tolerance, feasibility_tolerance=feasibility_tolerance)
        if count:
            x = np.empty(n, dtype=np.float64)
            call("GRBgetdblattrarray", model, b"X", 0, n, ct.c_void_p(x.ctypes.data))
            assert np.isfinite(x).all()
            np.save(directory / "native_primal.npy", x[positions])
            with columns.open() as source, (directory / "primal.csv").open("x", newline="") as target:
                writer = csv.writer(target)
                writer.writerow(("index", "value"))
                for row in csv.DictReader(source):
                    writer.writerow((row["index"], float(x[positions[int(row["native"])]])))
            result.update(annualized_EUR2025=real("ObjVal") * export["objective_divisor"],
                          native_constraint_violation=real("ConstrVio"), bound_violation=real("BoundVio"),
                          primal_sha256=digest(directory / "primal.csv"),
                          native_primal_sha256=digest(directory / "native_primal.npy"))
        memory = psutil.Process().memory_info()
        result.update(peak_process_working_set_bytes=memory.peak_wset,
                      peak_process_pagefile_usage_bytes=memory.peak_pagefile)
        outcome.write_text(json.dumps(result, indent=2, allow_nan=False), encoding="utf-8")
        print(json.dumps(result), flush=True)
    finally:
        if model:
            lib.GRBfreemodel(model)
        lib.GRBfreeenv(env)


if __name__ == "__main__":
    solve(*(Path(p).resolve() for p in sys.argv[1:]))
