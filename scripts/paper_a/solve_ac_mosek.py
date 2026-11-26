"""Cross-solver retry of an already exported PowerModels week on Windows."""
import csv
import json
import os
from pathlib import Path
import sys
import time

import numpy as np
from solve_ac_native import digest


def encode_soc_wr(task, destination, mosek):
    """Recover the original SOC(t,x) from its MPS form t²−sum(x²) ≥ 0, t ≥ 0."""
    domains = {n: task.appendquadraticconedomain(n) for n in (3, 4)}
    domain_ids, columns = [], []
    dimensions = {3: 0, 4: 0}
    with (destination / "cone_columns.csv").open("x", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("row", "first_afe", "dimension", "t", "x", "y", "z_if_present"))
        for k in range(task.getnumcon()):
            if not task.getnumqconknz(k):
                continue
            _, ii, jj, coefficients = task.getqconk(k)
            positive = [i for i, v in zip(ii, coefficients) if v == 2.0]
            negative = [i for i, v in zip(ii, coefficients) if v == -2.0]
            bound, lower, _ = task.getconbound(k)
            n = len(ii)
            if (list(ii) != list(jj) or n not in domains or len(positive) != 1
                    or len(set(ii)) != n or len(negative) != n - 1
                    or bound != mosek.boundkey.lo or lower != 0.0 or any(task.getarow(k)[2])):
                raise ValueError(f"Unsupported SOC row {k}")
            t = positive[0]
            kind, lo, _ = task.getvarbound(t)
            if kind not in (mosek.boundkey.lo, mosek.boundkey.ra, mosek.boundkey.fx) or lo < 0.0:
                raise ValueError(f"Missing nonnegative leading coordinate at {k}")
            members = positive + negative
            writer.writerow((task.getconname(k), len(columns), n, *(task.getvarname(i) for i in members)))
            columns.extend(members)
            domain_ids.append(domains[n])
            dimensions[n] += 1
            task.putqconk(k, [], [], [])
    if dimensions != {3: 17472, 4: 8736} or task.getnumafe() != 0:
        raise ValueError(f"Unexpected native weekly cone layout {dimensions}")
    task.appendafes(len(columns))
    task.putafefentrylist(range(len(columns)), columns, [1.0] * len(columns))
    task.appendaccsseq(domain_ids, len(columns), 0, None)
    task.writedata(str(destination / "native_cones.task.gz"))


def encode_rotated_products(task, destination, mosek, expected_count=8736):
    """Transmit x²+y²≤uv with nonnegative u,v as (u/2,v,x,y) in the rotated cone."""
    rows = []
    for k in range(task.getnumcon()):
        if task.getnumqconknz(k) != 3:
            continue
        _, ii, jj, coefficients = task.getqconk(k)
        squares = [i for i, j, v in zip(ii, jj, coefficients) if i == j and v == 2.0]
        product = [(i, j) for i, j, v in zip(ii, jj, coefficients) if i != j and v == -1.0]
        if len(squares) != 2 or len(product) != 1:
            continue
        u, v = product[0]
        x, y = squares
        sense, _, rhs = task.getconbound(k)
        if len({u, v, x, y}) != 4 or sense != mosek.boundkey.up or rhs != 0.0 or any(task.getarow(k)[2]):
            raise ValueError(f"Unsupported affine part or cone domain at {k}")
        for i in (u, v):
            kind, lower, _ = task.getvarbound(i)
            if kind not in (mosek.boundkey.lo, mosek.boundkey.ra, mosek.boundkey.fx) or lower < 0.0:
                raise ValueError(f"Nonnegative factor missing at {k}")
        rows.append((k, u, v, x, y))
    if len(rows) != expected_count:
        raise ValueError(f"Unexpected number of rotated cones for this weekly export: {len(rows)}")
    original_names = [task.getvarname(i) for i in range(task.getnumvar())]
    row_names = [task.getconname(row[0]) for row in rows]
    for k, *_ in rows:
        task.putqconk(k, [], [], [])
    # MOSEK handles the remaining convex quadratic constraints with its own
    # converter before the explicit affine conic constraints are transmitted.
    task.toconic()
    if any(task.getvarname(i) != name for i, name in enumerate(original_names)):
        raise ValueError("MOSEK changed the original variable ordering")
    domain = task.appendrquadraticconedomain(4)
    first = task.getnumafe()
    task.appendafes(4 * len(rows))
    flat_columns = [i for row in rows for i in row[1:]]
    task.putafefentrylist(range(first, first + len(flat_columns)), flat_columns, [0.5, 1.0, 1.0, 1.0] * len(rows))
    task.appendaccsseq([domain] * len(rows), len(flat_columns), first, None)
    with (destination / "cone_columns.csv").open("x", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("row", "u", "v", "x", "y", "first_afe"))
        for n, (k, u, v, x, y) in enumerate(rows):
            writer.writerow((row_names[n], *(original_names[i] for i in (u, v, x, y)), first + 4*n))
    task.writedata(str(destination / "native_cones.task.gz"))


def solve(source, target):
    dlls = os.add_dll_directory(os.environ["PAPER_A_MOSEK_BIN"])
    import mosek

    receipt = json.loads((source / "export.json").read_bytes())
    profile = json.loads((source / "profile.json").read_bytes())
    assert digest(source / "profile.json") == receipt["profile_sha256"]
    assert digest(source / "native_columns.csv") == receipt["native_columns_sha256"]
    assert digest(source / "native.mps") == receipt["native_mps_sha256"]
    target.mkdir(exist_ok=False)
    result = dict(formulation=profile["formulation"], case_sha256=receipt["case_sha256"],
                  mps_sha256=receipt["native_mps_sha256"], result_count=0,
                  solver_version=".".join(map(str, mosek.Env.getversion())))
    start = time.monotonic()
    with mosek.Task() as task, (target / "mosek.log").open("x") as log:
        task.set_Stream(mosek.streamtype.log, lambda msg: (log.write(msg), log.flush()))
        task.putintparam(mosek.iparam.num_threads, 1)
        task.putdouparam(mosek.dparam.optimizer_max_time, 7200.0)
        task.putdouparam(mosek.dparam.data_tol_aij_huge, 1.0e19)
        try:
            task.readdata(str(source / "native.mps"))
            assert task.getnumvar() == receipt["variables"] and task.getnumintvar() == 0
            native = np.fromiter((int(task.getvarname(i).removeprefix("V")) for i in range(task.getnumvar())),
                                 dtype=int, count=task.getnumvar())
            assert np.array_equal(np.sort(native), np.arange(len(native)))
            if profile["formulation"] == "SOC-WR" and profile.get("strength_method") == "BASE":
                encode_soc_wr(task, target, mosek)
            elif os.environ.get("PAPER_A_MOSEK_ROTATED") == "1":
                assert profile["formulation"] == "QCRM"
                encode_rotated_products(task, target, mosek)
            if (target / "native_cones.task.gz").exists():
                result["native_task_sha256"] = digest(target / "native_cones.task.gz")
                result["cone_columns_sha256"] = digest(target / "cone_columns.csv")
            result["optimizer_response"] = str(task.optimize())
            sol = mosek.soltype.itr
            status = task.getsolsta(sol)
            result.update(termination=str(status), problem_status=str(task.getprosta(sol)))
            if status in (mosek.solsta.optimal, mosek.solsta.prim_feas, mosek.solsta.prim_and_dual_feas):
                point = np.empty(len(native))
                point[native] = task.getxxslice(sol,0,len(native))
                assert np.isfinite(point).all()
                np.save(target / "native_primal.npy", point)
                with (source / "native_columns.csv").open() as columns, (target / "primal.csv").open("x", newline="") as out:
                    writer = csv.writer(out)
                    writer.writerow(("index", "value"))
                    for row in csv.DictReader(columns):
                        writer.writerow((row["index"], float(point[int(row["native"])])))
                result.update(result_count=1, annualized_EUR2025=task.getprimalobj(sol) * receipt["objective_divisor"],
                              primal_sha256=digest(target / "primal.csv"), native_primal_sha256=digest(target / "native_primal.npy"))
        except mosek.Error as exc:
            result.update(termination=str(exc.errno), solver_message=str(exc))
    result["seconds_including_import"] = time.monotonic() - start
    (target / "outcome.json").write_text(json.dumps(result, indent=2, allow_nan=False), encoding="utf-8")
    print(json.dumps(result), flush=True)
    dlls.close()


if __name__ == "__main__":
    solve(*(Path(p).resolve() for p in sys.argv[1:]))
