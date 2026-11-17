"""Reuse the accepted five-week CSV/cost replay for the one-week source pair."""
from pathlib import Path
import csv
import hashlib
import json
import math
import sys

root, raw, parent = map(Path, sys.argv[1:4])
source_path = parent / "replay.py"
source_bytes = source_path.read_bytes()
assert hashlib.sha256(source_bytes).hexdigest() == "45e172224308443c5c9164467b08d0388f31c658c403497467af6c7e3bf31aa0"
source = source_bytes.decode("utf-8-sig")
for old, new in [
    ("r['hours']==840", "r['hours']==168"),
    ("r['weight']-73/7", "r['weight']-365/7"),
    ("'840-hour technical 50 percent original wind and solar'",
     "'168-hour KW8 technical 50 percent Wind/PV fixed-E source comparison'"),
]:
    assert source.count(old) == 1
    source = source.replace(old, new, 1)

selection = json.loads((parent / "week_selection.json").read_bytes())
chosen = [week for week in selection["selected"] if week["iso_week"] == 8]
assert len(chosen) == 1
selection["selected"] = chosen
selection["hour_count"] = 168
selection["parent_selection_sha256"] = hashlib.sha256((parent / "week_selection.json").read_bytes()).hexdigest()
(root / "week_selection.json").write_text(json.dumps(selection, indent=2) + "\n", encoding="utf-8")

# The original replay reads these two arguments only. Keep it unchanged apart
# from explicit horizon/factor labels, then add complete-primal acceptance.
saved_args = sys.argv
sys.argv = [str(source_path), str(root), str(raw)]
namespace = {"__name__": "__main__", "__file__": str(source_path)}
exec(compile(source, str(source_path), "exec"), namespace)
sys.argv = saved_args
receipt = json.loads((root / "comparison.json").read_bytes())
receipt["source_model"] = "colib_epri_frozen_E_blocks_v1"
receipt["hours"] = 168
receipt["OPEX_factor"] = 8760 / 168
receipt["CAPEX_factor"] = 1
receipt["integer_rounding_performed"] = False
receipt["replay_parent_sha256"] = hashlib.sha256(source_bytes).hexdigest()
for name, result in receipt["results"].items():
    folder = root / name
    primal = folder / "full_primal.csv"
    count = 0
    indices = set()
    bound_error = integer_error = 0.0
    discrete_count = 0
    if primal.exists():
        with primal.open(newline="", encoding="utf-8") as stream:
            for row in csv.DictReader(stream):
                value = float(row["value"])
                assert math.isfinite(value)
                index = int(row["variable_index"])
                assert index not in indices
                indices.add(index)
                bound_error = max(bound_error, float(row["lower_bound"]) - value,
                                  value - float(row["upper_bound"]))
                if row.get("is_integer") == "true" or row.get("is_binary") == "true":
                    discrete_count += 1
                    integer_error = max(integer_error, abs(value - round(value)))
                count += 1
    if "model_variable_count" in result and result.get("result_count", 0):
        assert count == result["model_variable_count"]
        assert discrete_count == result["discrete_variable_count"]
    result["complete_primal_variable_count"] = count
    result["csv_bound_violation"] = bound_error
    result["csv_discrete_variable_count"] = discrete_count
    result["csv_integer_residual"] = integer_error
    result["energy_and_active_G1_replay_passed"] = result.get("physical_replay_passed", False)
    accepted = (
        count > 0 and result.get("numerically_accepted", False)
        and result["energy_and_active_G1_replay_passed"] and bound_error <= 1e-6
    )
    result["accepted_for_proxy_LP_comparison"] = accepted and result["mode"] == "relaxed"
    result["accepted_for_proxy_MIP_comparison"] = (
        accepted and result["mode"] == "integer" and discrete_count > 0 and integer_error <= 1e-6
    )
    # Legacy summary keys include '840h'; their values cover this 168h run.
    result["represented_operation_components_EUR2025"] = result.get("operation_840h_components_EUR2025")
    result["represented_operation_EUR2025"] = result.get("operation_840h_EUR2025")

(root / "comparison.json").write_text(json.dumps(receipt, indent=2, allow_nan=False) + "\n", encoding="utf-8")
print(json.dumps({key: {k: value.get(k) for k in (
    "status", "objective_EUR2025", "accepted_for_proxy_LP_comparison", "accepted_for_proxy_MIP_comparison",
    "complete_primal_variable_count", "min_gscr_slack_pu", "primal_violation_count_at_1e_6")}
    for key, value in receipt["results"].items()}, indent=2))
