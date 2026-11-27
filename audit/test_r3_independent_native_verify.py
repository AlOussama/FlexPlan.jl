"""Material mutation checks for the independent native PSD verifier."""
import copy
from r3_independent_native_verify import verify


def fixture():
    return {
        "bar_dimensions": [2], "afe_bar_triplet_count": 0,
        "bar_objective_triplet_count": 0,
        "original_variables": [{"jump_index": 1, "native_column": 1}],
        "expected_blocks": [{"hour": 1, "dimension": 2, "entries": [
            {"i": 1, "j": 1, "constant": .25, "terms": [[1, 2.]]},
            {"i": 1, "j": 2, "constant": -.1, "terms": []},
            {"i": 2, "j": 2, "constant": 0., "terms": [[1, 1.]]}]}],
        "rows": [
            {"row": 1, "columns": [1], "values": [2.], "bound_key": "MSK_BK_FX", "lower": -.25, "upper": -.25},
            {"row": 2, "columns": [], "values": [], "bound_key": "MSK_BK_FX", "lower": .1, "upper": .1},
            {"row": 3, "columns": [1], "values": [-1.], "bound_key": "MSK_BK_FX", "lower": 0., "upper": 0.}],
        "bar_triplets": {"row": [1, 2, 3], "bar": [1, 1, 1], "i": [1, 2, 2], "j": [1, 1, 2], "value": [-1., -.5, 1.]}}


def main():
    original = fixture()
    assert verify(original)["positions"] == 3
    mutations = [
        ("missing symmetric half", lambda d: d["bar_triplets"]["value"].__setitem__(1, -1.)),
        ("one ULP wrong constant", lambda d: d["expected_blocks"][0]["entries"][1].__setitem__("constant", -.10000000000000002)),
        ("inequality instead of equality", lambda d: d["rows"][1].__setitem__("bound_key", "MSK_BK_LO")),
        ("missing triangle coordinate", lambda d: d["bar_triplets"]["i"].__setitem__(1, 1)),
        ("one ULP wrong coefficient", lambda d: d["rows"][0]["values"].__setitem__(0, 2.0000000000000004)),
        ("extra AFE coupling", lambda d: d.__setitem__("afe_bar_triplet_count", 1)),
        ("extra objective coupling", lambda d: d.__setitem__("bar_objective_triplet_count", 1)),
        ("extra native block", lambda d: d["bar_dimensions"].append(2)),
        ("wrong block dimension", lambda d: d["bar_dimensions"].__setitem__(0, 3)),
        ("extra scalar variable", lambda d: (d["rows"][0]["columns"].append(2), d["rows"][0]["values"].append(1.))),
    ]
    for name, mutate in mutations:
        damaged = copy.deepcopy(original)
        mutate(damaged)
        try:
            verify(damaged)
        except AssertionError:
            continue
        raise AssertionError("material mutation accepted: " + name)
    print(f"PASS: 1 exact positive, {len(mutations)} material negatives")


if __name__ == "__main__":
    main()
