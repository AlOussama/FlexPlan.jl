"""Targeted source-to-reference delta audit; no optimization or acceptance changes."""
import argparse
from collections import defaultdict
import json
from pathlib import Path

from replay_evidence import digest, rows, record, EvidenceError


def coordinates(path):
    aliases=defaultdict(set)
    for row in rows(path):
        key=(row["type"],row["hour"],row["id"],row["end_bus"])
        for field in ("p_index","q_index","online_index"):
            index=int(row[field])
            if index:
                aliases[index].add(key+(field,))
    return {index:tuple(sorted(keys)) for index,keys in aliases.items()}


def ledger(path, aliases):
    expressions=defaultdict(dict)
    for row in rows(path):
        key=(row["metric"],int(row["hour"]),row["id"])
        if key[0] not in ("M","cost","wind_pv","P","Q"):
            continue
        index=int(row["index"])
        # Non-terminal variables retain their explicit index; they are reported
        # separately and cannot silently acquire a guessed physical identity.
        coordinate=("constant",) if not index else (("terminal",aliases[index]) if index in aliases else ("unresolved_index",index))
        if coordinate in expressions[key]:
            raise EvidenceError("Duplicate sparse coordinate: "+str(key))
        expressions[key][coordinate]=float(row["coefficient"])
    return expressions


def compare(original, reference):
    sources={side+"_"+name:record(folder/name) for side,folder in (("original",original),("reference",reference))
             for name in ("audit_terms.csv","terminal_coordinates.csv")}
    old=ledger(original/"audit_terms.csv",coordinates(original/"terminal_coordinates.csv"))
    new=ledger(reference/"audit_terms.csv",coordinates(reference/"terminal_coordinates.csv"))
    expected={("M",h,f"{i}_{j}") for h in range(1,169) for i in range(1,38) for j in range(i,38)}
    if {k for k in old if k[0]=="M"}!=expected or {k for k in new if k[0]=="M"}!=expected:
        raise EvidenceError("Full118104 original matrix key roster missing")
    result={}
    for metric in ("M","cost","wind_pv","P","Q"):
        keys={k for k in old if k[0]==metric}|{k for k in new if k[0]==metric}
        differences=[]
        unresolved=set()
        shared=0
        for key in sorted(keys):
            a,b=old.get(key,{}),new.get(key,{})
            coordinates_all=set(a)|set(b)
            unresolved.update(c for c in coordinates_all if c[0]=="unresolved_index")
            if a==b:
                shared+=1
            else:
                for coordinate in sorted(coordinates_all,key=str):
                    av,bv=a.get(coordinate,0.0),b.get(coordinate,0.0)
                    if av!=bv:
                        differences.append(dict(expression=key,coordinate=coordinate,original=av,reference=bv,delta=bv-av))
        result[metric]=dict(expressions=len(keys),exactly_equal_expressions=shared,
                            coefficient_differences=len(differences),unresolved_index_coordinates=len(unresolved),
                            semantic_status="EXACT_SEMANTIC_MATCH" if not differences and not unresolved else
                            ("EXACT_INDEX_MATCH_WITH_UNRESOLVED_SEMANTICS" if not differences else "DIFFERENT_OR_UNALIGNED"),
                            first_differences=differences[:20])
    # Verify bytes stayed fixed throughout the comparison.
    for entry in sources.values():
        if digest(entry["path"])!=entry["sha256"]:
            raise EvidenceError("Input changed during delta audit")
    return dict(inputs=sources,metrics=result,scope="Exact sparse source delta audit; no solve, no F02 reconsideration")


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("original",type=Path)
    parser.add_argument("reference",type=Path)
    parser.add_argument("output",type=Path)
    args=parser.parse_args()
    report=compare(args.original,args.reference)
    with args.output.open("x",encoding="utf-8") as stream:
        json.dump(report,stream,indent=2,allow_nan=False)
