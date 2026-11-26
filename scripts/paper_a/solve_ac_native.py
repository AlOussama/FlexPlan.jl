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
        feasibility_only = os.environ.get("PAPER_A_AC_FEASIBILITY_ONLY") == "1"
        if profile.get("outer_lp") or profile.get("inner_lp"):
            # Crossover provides a simplex basis after the barrier has located
            # a near-optimal point in these continuous linear search models.
            call("GRBsetintparam", env, b"Method", 2)
            call("GRBsetintparam", env, b"Crossover", 0 if profile.get("outer_lp") else 1)
        dual_reductions = 0 if feasibility_only else int(os.environ.get("PAPER_A_AC_DUAL_REDUCTIONS", 1))
        call("GRBsetintparam", env, b"DualReductions", dual_reductions)
        focus = int(os.environ.get("PAPER_A_AC_NUMERIC_FOCUS", 2 if profile["formulation"] == "LPAC" else 3))
        threads = int(os.environ.get("PAPER_A_AC_THREADS", 1))
        homogeneous = int(os.environ.get("PAPER_A_AC_HOMOGENEOUS", 1))
        order = int(os.environ.get("PAPER_A_AC_BAR_ORDER", -1))
        aggregate = int(os.environ.get("PAPER_A_AC_AGGREGATE", 1))
        for key, value in ((b"Threads", threads), (b"NumericFocus", focus), (b"Seed", 1),
                           (b"BarHomogeneous", homogeneous), (b"BarOrder", order), (b"Aggregate", aggregate)):
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
        if feasibility_only:
            assert integer("NumQNZs") == 0
            costs = np.empty(n, dtype=np.float64)
            call("GRBgetdblattrarray", model, b"Obj", 0, n, ct.c_void_p(costs.ctypes.data))
            constant = real("ObjCon")
            budget = os.environ.get("PAPER_A_AC_COST_CAP_EUR")
            if budget is not None:
                rhs = float(budget) / export["objective_divisor"] - constant
                indices = np.flatnonzero(costs).astype(np.int32)
                coefficients = costs[indices]
                call("GRBaddconstr", model, len(indices), ct.c_void_p(indices.ctypes.data),
                     ct.c_void_p(coefficients.ctypes.data), ct.c_char(b"<"), ct.c_double(rhs),
                     b"diagnostic_cost_budget")
            zeros = np.zeros_like(costs)
            call("GRBsetdblattrarray", model, b"Obj", 0, n, ct.c_void_p(zeros.ctypes.data))
            call("GRBsetdblattr", model, b"ObjCon", ct.c_double(0.0))
            call("GRBupdatemodel", model)
        names = (ct.c_char_p * n)()
        call("GRBgetstrattrarray", model, b"VarName", 0, n, names)
        positions = np.full(n, -1, dtype=np.int32)
        for col, name in enumerate(names):
            assert name.startswith(b"V")
            positions[int(name[1:])] = col
        assert np.min(positions) >= 0
        neighborhood = None
        if "PAPER_A_AC_FEASIBILITY_NEAR" in os.environ:
            fix_lpac_voltages = os.environ.get("PAPER_A_AC_FIX_LPAC_VOLTAGES") == "1"
            assert feasibility_only or fix_lpac_voltages
            reference = Path(os.environ["PAPER_A_AC_FEASIBILITY_NEAR"])
            point = reference / "native_primal.npy"
            parent = json.loads((reference / "outcome.json").read_bytes())
            assert parent["case_sha256"] == export["case_sha256"]
            assert parent["mps_sha256"] in (profile.get("original_mps_sha256"), export["native_mps_sha256"])
            assert digest(point) == parent["native_primal_sha256"]
            # Restrict original variable bounds around a known G2 point; a
            # feasible witness also satisfies BASE. A negative is local only.
            anchor = np.load(point, allow_pickle=False)
            assert anchor.shape == (n,) and np.isfinite(anchor).all()
            bounds = [np.empty(n, dtype=np.float64) for _ in range(2)]
            for attr, b in zip((b"LB", b"UB"), bounds):
                call("GRBgetdblattrarray", model, attr, 0, n, ct.c_void_p(b.ctypes.data))
            center = np.empty_like(anchor)
            center[positions] = anchor
            center = np.clip(center, *bounds)
            radius = 0.05 + 0.01 * np.abs(center)
            tightened = (np.maximum(bounds[0], center - radius), np.minimum(bounds[1], center + radius))
            assert np.all(tightened[0] <= tightened[1])
            for attr, b in zip((b"LB", b"UB"), tightened):
                call("GRBsetdblattrarray", model, attr, 0, n, ct.c_void_p(b.ctypes.data))
            call("GRBupdatemodel", model)
            neighborhood = dict(reference_sha256=parent["native_primal_sha256"],absolute_radius=0.05,
                                relative_radius=0.01,tightened_lower=int(np.sum(tightened[0]>bounds[0])),
                                tightened_upper=int(np.sum(tightened[1]<bounds[1])))
            if fix_lpac_voltages:
                assert profile["formulation"] == "LPAC"
                # The off-diagonal terms occur only in the LPAC cosine rows.
                # Fix the voltage state near the reference and let presolve
                # determine both terminal flows from the original branch laws.
                angles = set()
                with mps.open("rb") as stream:
                    quadratic = False
                    for line in stream:
                        if not line.startswith(b" "):
                            quadratic = line.startswith(b"QCMATRIX")
                        elif quadratic:
                            a, b, value = line.split()
                            if a != b:
                                assert float(value) < 0
                                angles.update((int(a[1:]), int(b[1:])))
                magnitude = np.isclose(bounds[0], -0.05, rtol=0, atol=1e-15) & (bounds[1] == -bounds[0])
                cosine = (bounds[0] == np.cos(np.pi/2)) & (bounds[1] == 1.0)
                assert 0 < len(angles) <= 6216 and np.count_nonzero(magnitude) == 6216
                assert np.count_nonzero(cosine) == 8736
                fixed = magnitude | cosine
                fixed[positions[list(angles)]] = True
                fixed_count = int(np.count_nonzero(fixed))
                assert fixed_count == 6216 + 8736 + len(angles)
                target = 0.9999 * center + 0.0001 * cosine
                if os.environ.get("PAPER_A_AC_INTERIOR_COSINE") == "1":
                    # A blended approximate anchor may still exceed its
                    # quadratic cosine envelope after the angles are fixed.
                    cosine_col = {}
                    pairs = {}
                    with mps.open("rb") as stream:
                        for line in stream:
                            fields = line.split()
                            if not line.startswith(b" "):
                                section = fields[0]
                                if section == b"QCMATRIX":
                                    row = fields[1]
                            elif section == b"COLUMNS" and fields[1].startswith(b"qc"):
                                assert float(fields[2]) == 1
                                cosine_col[fields[1]] = positions[int(fields[0][1:])]
                            elif section == b"QCMATRIX" and fields[0] != fields[1]:
                                pairs[row] = (positions[int(fields[0][1:])],positions[int(fields[1][1:])],-float(fields[2]))
                    assert pairs.keys() == cosine_col.keys() and len(pairs) == 8736
                    for row,(a,b,k) in pairs.items():
                        col = cosine_col[row]
                        target[col] = min(target[col],1-k*(target[a]-target[b])**2-1e-12)
                assert np.all(target[fixed] >= bounds[0][fixed]) and np.all(target[fixed] <= bounds[1][fixed])
                for attr, original in zip((b"LB", b"UB"), bounds):
                    b = np.where(fixed, target, original)
                    call("GRBsetdblattrarray", model, attr, 0, n, ct.c_void_p(b.ctypes.data))
                call("GRBupdatemodel", model)
                neighborhood = dict(reference_sha256=parent["native_primal_sha256"],fixed_voltage_variables=fixed_count,
                                    reference_weight=0.9999, flat_state_weight=0.0001)
            if os.environ.get("PAPER_A_AC_FIX_SOC_VOLTAGES") == "1":
                assert feasibility_only and profile["formulation"] == "SOC-WR"
                upper_voltage = bounds[1] == 1.05**2
                w = upper_voltage & (bounds[0] == 0.95**2)
                wr = upper_voltage & np.isclose(bounds[0], 0.95**2 * np.cos(np.pi/2), rtol=1e-14, atol=0)
                wi = upper_voltage & (bounds[0] == -(1.05**2))
                assert tuple(map(np.count_nonzero, (w, wr, wi))) == (6216, 8736, 8736)
                fixed = w | wr | wi
                target = 0.9999 * center + 0.0001 * (w | wr)
                for attr, original in zip((b"LB", b"UB"), bounds):
                    b = np.where(fixed, target, original)
                    call("GRBsetdblattrarray", model, attr, 0, n, ct.c_void_p(b.ctypes.data))
                call("GRBupdatemodel", model)
                neighborhood = dict(reference_sha256=parent["native_primal_sha256"],
                                    fixed_voltage_variables=int(np.sum(fixed)),
                                    reference_weight=0.9999, flat_state_weight=0.0001)
        call("GRBoptimize", model)
        status, count = integer("Status"), integer("SolCount")
        labels = {2: "OPTIMAL", 3: "INFEASIBLE", 4: "INF_OR_UNBD", 5: "UNBOUNDED",
                  9: "TIME_LIMIT", 12: "NUMERIC", 13: "SUBOPTIMAL", 17: "MEMORY_LIMIT"}
        result = dict(termination=labels.get(status, str(status)), native_status=status,
                      result_count=count, seconds=real("Runtime"), formulation=profile["formulation"], solver_version=solver_version,
                      case_sha256=export["case_sha256"], mps_sha256=export["native_mps_sha256"],
                      threads=threads,numeric_focus=focus,scale_flag=scaling,bar_homogeneous=homogeneous,bar_order=order,
                      aggregate=aggregate, strength_method=profile.get("strength_method", "G2"),
                      barrier_tolerance=barrier_tolerance, feasibility_tolerance=feasibility_tolerance)
        result["objective_kind"] = "feasibility_zero" if feasibility_only else "annualized_cost"
        if profile.get("outer_lp"):
            result["objective_kind"] = "outer_lp_lower_bound"
            duals = {}
            for attr, size in (("Pi",integer("NumConstrs")),("RC",n)):
                values = np.empty(size,dtype=np.float64)
                code = lib.GRBgetdblattrarray(model,attr.encode(),0,size,ct.c_void_p(values.ctypes.data))
                if code == 0 and np.isfinite(values).all():
                    duals[attr] = values
            if "Pi" in duals:
                np.savez_compressed(directory/"lp_duals.npz",**duals)
                result["dual_archive_sha256"] = digest(directory/"lp_duals.npz")
        if profile.get("inner_lp"):
            result["objective_kind"] = "restricted_primal_cost"
        result["dual_reductions"] = dual_reductions
        if feasibility_only and budget is not None:
            result["cost_cap_EUR2025"] = float(budget)
        for attribute in ("ObjBound", "ObjBoundC", "DualVio", "ComplVio"):
            value = ct.c_double()
            code = lib.GRBgetdblattr(model, attribute.encode(), ct.byref(value))
            if code == 0 and np.isfinite(value.value) and abs(value.value) < 1e100:
                result[attribute] = value.value
        if neighborhood is not None:
            result["restricted_witness_search"] = neighborhood
        if feasibility_only:
            if status == 3 and neighborhood is None and budget is None:
                call("GRBcomputeIIS", model)
                iis = directory / "infeasible.ilp"
                call("GRBwrite", model, os.fsencode(iis))
                result.update(iis_sha256=digest(iis), iis_minimal=integer("IISMinimal"))
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
            objective = float(np.dot(costs, x) + constant) if feasibility_only else real("ObjVal")
            result.update(annualized_EUR2025=objective * export["objective_divisor"],
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
