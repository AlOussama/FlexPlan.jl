import subprocess,hashlib,json
from pathlib import Path
R=Path('D:/Projekte/Code/FlexPlan_A35_EXEC_RUN');repo='D:/Projekte/research-map';prefix='docs/reports/C2_constraints/C2A_voltage_stability/'
paths=['scientific_report/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md','external_review/freeze/2026-08-02__c2a-scientific-formulation-freeze.md','synthesis/2026-07-30__synthesis__c2a-track-a-adjudicated-proofs-and-counterexamples.md','implementation_audit/2026-07-30__c2a-project-predicate-audit.md','publication_planning/2026-08-09__paper-a-development-plan-freeze.md','publication_planning/2026-10-15__paper-a-multirepo-execution-freeze-v2.md']
items=[('e8118425adc335a99e85120d943763305f211315',prefix+p) for p in paths]+[('2badb9a90a8d3c1d4a33accee640b295de1e33a1',prefix+'paper_a/science_release/2026-10-20__a3-5-final-gates.yaml'),('5ceb19a6faf4e7c7e797a737ed5b449f9e2db609',prefix+'paper_a/science_release/2026-10-20__a3-5-amendment-final-proposed-text.md')]
(R/'science_source_snapshots').mkdir(exist_ok=True);manifest=[]
for sha,path in items:
    data=subprocess.check_output(['git','-C',repo,'show',sha+':'+path]);p=R/'science_source_snapshots'/Path(path).name;p.write_bytes(data)
    blob=subprocess.check_output(['git','-C',repo,'rev-parse',sha+':'+path]).decode().strip()
    manifest.append(dict(path=path,commit=sha,blob=blob,sha256=hashlib.sha256(data).hexdigest(),bytes=len(data),local=str(p)))
(R/'science_source_manifest.json').write_text(json.dumps(manifest,indent=2))
print('source snapshots',len(manifest))
