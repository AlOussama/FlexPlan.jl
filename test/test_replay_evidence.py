"""Actual malformed input files must fail before the archived evaluator runs."""
import csv
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts/paper_a"))
import replay_evidence as e


class ReplayEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def table(self,name,fields,rows):
        path=self.root/name
        with path.open("w",newline="") as stream:
            writer=csv.writer(stream)
            writer.writerow(fields)
            writer.writerows(rows)
        return path

    def test_changed_and_missing_expected_bytes(self):
        source=self.root/"original.mps"
        source.write_text("original angle row")
        manifest=self.root/"manifest.json"
        manifest.write_text(json.dumps(dict(schema=e.SCHEMA,inputs=dict(native=e.record(source)))))
        e.verify_manifest(manifest,["native"])
        source.write_text("corrupted angle row")
        with self.assertRaises(e.EvidenceError): e.verify_manifest(manifest,["native"])
        source.unlink()
        with self.assertRaises(e.EvidenceError): e.verify_manifest(manifest,["native"])
        with self.assertRaises(e.EvidenceError): e.verify_manifest(manifest,["primal"])

    def test_mapping_duplicate_and_out_of_dimension(self):
        for records in ([[1,0],[1,1]],[[1,0],[2,0]],[[1,2]],[[2,0]]):
            path=self.table("mapping.csv",["index","native"],records)
            with self.assertRaises(e.EvidenceError): e.validate_mapping(path,2)

    def test_complete_matrix_and_corrupt_ledger_controls(self):
        fields=["metric","hour","id","index","coefficient"]
        records=[["M",1,"1_1",0,1],["M",1,"1_2",0,0],["M",1,"2_2",0,1]]
        terminal_fields=["type","hour","id","end_bus","p_index","q_index","online_index","q_factor_pu","rating_pu"]
        terminal=[["branch",1,"1",1,1,2,0,0,1]]
        t=self.table("terminal.csv",terminal_fields,terminal)
        a=self.table("audit.csv",fields,records)
        self.assertEqual(e.validate_ledgers(a,t,{1:0,2:1},1,2)["matrix_positions"],3)
        with self.assertRaises(e.EvidenceError):
            e.validate_ledgers(a,t,{1:0,2:1},1,2,bus_ids=[1])
        balance=records+[[metric,1,"1",0,0] for metric in ("P","Q")]+[[metric,0,"0",0,0] for metric in ("cost","wind_pv")]
        a=self.table("audit.csv",fields,balance)
        e.validate_ledgers(a,t,{1:0,2:1},1,2,bus_ids=[1])
        for bad in (records[:-1],records+[records[0]],records+[["M",1,"1_1",9,1]],records+[["M",1,"1_1",1,"nan"]]):
            a=self.table("audit.csv",fields,bad)
            with self.assertRaises(e.EvidenceError): e.validate_ledgers(a,t,{1:0,2:1},1,2)
        a=self.table("audit.csv",fields,records)
        for bad in (terminal+terminal,[["branch",1,"1",1,1,9,0,0,1]]):
            t=self.table("terminal.csv",terminal_fields,bad)
            with self.assertRaises(e.EvidenceError): e.validate_ledgers(a,t,{1:0,2:1},1,2)


if __name__=="__main__":
    unittest.main()
