"""Replay a weekly G3 native primal in the unscaled MPS and all 168 original PSD matrices."""
if not __debug__:
    raise RuntimeError("Original-point replay requires Python assertions enabled; do not use -O")

import json
import sys
import argparse
import importlib.util
from pathlib import Path

import numpy as np

from replay_evidence import digest, record, verify_manifest, validate_mapping, validate_ledgers, SCHEMA


def freeze_manifest(study, model, solved, target):
    """Freeze expected input bytes without evaluating the point."""
    sources = dict(case=study/"CONFIRMED_QBOX/AC_CASE/case.json",
                   original_native_model=model/"native.mps", profile=model/"profile.json",
                   export_metadata=model/"export.json", mapping=model/"native_columns.csv",
                   audit_terms=model/"audit_terms.csv", matrix_ledger=model/"audit_terms.csv",
                   terminal_coordinates=model/"terminal_coordinates.csv",
                   outcome=solved/"outcome.json", primal=solved/"native_primal.npy",
                   evaluator=study/"BASE_PAIR_20261126/independent_base_point.py",
                   replay_program=Path(__file__), integrity_program=Path(__file__).with_name("replay_evidence.py"))
    scaled=model.with_name(model.name+"_scaled")
    if scaled.is_dir():
        for name in ("native.mps","profile.json","native_columns.csv","scaled_angle_rows.csv","transformation_register.json"):
            if (scaled/name).is_file():
                sources["solver_"+name]=scaled/name
    for name in ("lp_duals.npz","native_dual.npy"):
        if (solved/name).is_file():
            sources["optional_"+name]=solved/name
    raw=Path("D:/Projekte/Code/pypsatomatpowerx/data/elec_s_37_csv")
    for name in ("generators.csv","generators-p_max_pu.csv","snapshots.csv"):
        sources["physical_"+name]=raw/name
    sources["physical_dates"]=study.parent/"TECH_FULL37_FIVE_WEEKS_RE50_20261115_01/AP1_EXPORT/week_8/case_manifest.json"
    sources["gold_criteria"]=study.parent/"PAPER_A_BUNDLE_20261123_GOLD01/02_final_rows/WK08-70-G2-LP.json"
    manifest=dict(schema=SCHEMA,context=dict(study=str(study),model=str(model),solved=str(solved)),
                  inputs={key:record(path) for key,path in sources.items()})
    with target.open("x",encoding="utf-8") as stream:
        json.dump(manifest,stream,indent=2)


def replay(study, model, solved, manifest_path, output):
    required=("case","original_native_model","profile","export_metadata","mapping","audit_terms",
              "matrix_ledger","terminal_coordinates","outcome","primal","evaluator","replay_program",
              "integrity_program","physical_generators.csv","physical_generators-p_max_pu.csv",
              "physical_snapshots.csv","physical_dates","gold_criteria")
    manifest, bound = verify_manifest(manifest_path,required)
    expected=dict(case=study/"CONFIRMED_QBOX/AC_CASE/case.json",original_native_model=model/"native.mps",
                  profile=model/"profile.json",export_metadata=model/"export.json",mapping=model/"native_columns.csv",
                  audit_terms=model/"audit_terms.csv",matrix_ledger=model/"audit_terms.csv",
                  terminal_coordinates=model/"terminal_coordinates.csv",outcome=solved/"outcome.json",
                  primal=solved/"native_primal.npy",replay_program=Path(__file__),
                  integrity_program=Path(__file__).with_name("replay_evidence.py"))
    for role,path in expected.items():
        if path.resolve()!=bound[role].resolve():
            raise ValueError("Manifest role/path mismatch: "+role)
    spec=importlib.util.spec_from_file_location("bound_original_evaluator",bound["evaluator"])
    qa=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(qa)
    if Path(qa.DATES).resolve()!=bound["physical_dates"].resolve() or Path(qa.GOLD).resolve()!=bound["gold_criteria"].resolve() or Path(qa.RAW).resolve()!=bound["physical_generators.csv"].parent.resolve():
        raise ValueError("Archived evaluator external-input contract mismatch")

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
        assert bound.get("solver_native.mps",Path()).resolve()==(scaled/"native.mps").resolve()
        assert "solver_scaled_angle_rows.csv" in bound or "solver_transformation_register.json" in bound
        assert qa.read(scaled / "profile.json")["parent_mps_sha256"] == meta["native_mps_sha256"]
        assert digest(scaled / "native.mps") == result["mps_sha256"]
    report = dict(termination=result["termination"], result_count=result["result_count"],
                  source_mps_sha256=meta["native_mps_sha256"], case_sha256=meta["case_sha256"],
                  outcome_sha256=digest(solved/"outcome.json"), evaluator_sha256=digest(Path(qa.__file__)))
    if result["result_count"]:
        assert digest(solved / "native_primal.npy") == result["native_primal_sha256"]
        native = np.load(solved / "native_primal.npy",allow_pickle=False)
        assert native.ndim==1 and len(native)==meta["variables"] and np.isfinite(native).all()
        mapping=validate_mapping(model/"native_columns.csv",len(native))
        case_data=qa.read(case)
        assert len(case_data["nw"])==168
        roster=validate_ledgers(model/"audit_terms.csv",model/"terminal_coordinates.csv",mapping,
                                bus_ids=case_data["nw"]["1"]["bus"])
        primal = {index:native[column] for index,column in mapping.items()}
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
        physical = qa.physical_metrics(model, case_data, primal, values)
        assert abs(check["annualized_EUR2025"]-values["cost",0,"0"]) < .02
        report.update(original_matrix=check,physical=physical,hourly_minimum_eigenvalues=eigen.tolist(),
                      minimum_eigenvalue=eigen.min(),original_cost_EUR2025=values["cost",0,"0"],
                      primal_sha256=result["native_primal_sha256"],audit_terms_sha256=digest(model/"audit_terms.csv"))
    verify_manifest(manifest_path,required)
    report["input_manifest_sha256"]=digest(manifest_path)
    report["gold_qualified"]=False
    report["qualification_role"]="Bound original-point sensitivity evidence; acceptance requires frozen GOLD criteria review"
    report["ledger_roster"]=roster if result["result_count"] else None
    output.mkdir(exist_ok=False)
    with (output/"native_solver_audit.json").open("x") as stream:
        json.dump(dict(termination=result["termination"],result_count=result["result_count"],
                       gold_qualified=False,audit_role="native solver status only"),stream,indent=2)
    with (output/"original_model_audit.json").open("x") as stream:
        json.dump(report,stream,indent=2,allow_nan=False)
    with (output/"original_gscr_replay.json").open("x") as stream:
        json.dump(report,stream,indent=2,allow_nan=False)


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("study",type=Path)
    parser.add_argument("model",type=Path)
    parser.add_argument("solved",type=Path)
    parser.add_argument("--manifest",type=Path,required=True)
    parser.add_argument("--freeze-manifest",action="store_true")
    parser.add_argument("--output",type=Path)
    args=parser.parse_args()
    study,model,solved=(p.resolve() for p in (args.study,args.model,args.solved))
    if args.freeze_manifest:
        freeze_manifest(study,model,solved,args.manifest)
    else:
        if args.output is None:
            parser.error("--output is required for replay")
        replay(study,model,solved,args.manifest,args.output)
