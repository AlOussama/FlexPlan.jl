from pathlib import Path
import json, hashlib, zipfile, shutil
B=Path('D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE')
R=Path('D:/Projekte/Code/FlexPlan_A35_EXEC_RUN')
H=B/'reports/ap3_runs/20261020_macro'
out=R/'historical_evidence'; out.mkdir(exist_ok=False)
for name in ['accepted_suite','matrices_final','matrices_replay','metrics_final','planning_final','comparisons_final','certificates_final','benchmarks_final','enumeration_final']:
    shutil.copytree(H/name,out/name)
checks=[]
for z in H.rglob('*.zip'):
    with zipfile.ZipFile(z) as f:
        bad=f.testzip()
        row=dict(path=str(z.relative_to(B)),sha256=hashlib.sha256(z.read_bytes()).hexdigest(),bytes=z.stat().st_size,crc_bad=bad,entries=f.namelist())
        if z.parent==H/'metrics_final': f.extractall(out/'metrics_final')
        checks.append(row)
(R/'archive_verification.json').write_text(json.dumps(checks,indent=2))
print('ZIPs checked',len(checks),'metrics files',[x.name for x in (out/'metrics_final').iterdir()])
