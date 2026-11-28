"""Observe the nine frozen receipts and run independent read-only native checks."""
import datetime,json,pathlib,subprocess,time,sys
root=pathlib.Path('E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01')
qa=root/'06_qa';sha='ebaffb57feb3a27f2d7d87b745930664f625f935'
expected=[('G0',f,'mosek') for f in ('LPAC','SOC-WR','QCRM')]+[('G3',f,s) for f in ('LPAC','SOC-WR','QCRM') for s in ('gurobi','mosek')]
report={'source_commit':sha,'status':'IN_PROGRESS','expected_exports':9,'completed':[]}
summary=qa/'INDEPENDENT_NATIVE_RUNTIME_SUMMARY.json'
seen=set()
def save():summary.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
save()
while len(seen)<9:
    for method,form,solver in expected:
        name=f'{method}_{form}_{solver}_frozen'
        receipt=root/'04_reproducibility'/f'{name}_BUILD_RECEIPT.json'
        if name in seen or not receipt.is_file():continue
        try:r=json.loads(receipt.read_text(encoding='utf-8-sig'))
        except (ValueError,OSError):continue
        assert r['exit_code']==0 and r['source_commit']==r['source_commit_after']==sha
        assert r['optimization_performed'] is False and not r['tracked_dirty_before'] and not r['tracked_dirty_after']
        folder=root/('01_native_g0' if method=='G0' else '02_native_g3')/f'{form}_{solver}_frozen'
        output=qa/f'independent_{name}.json'
        if method=='G0':
            command=[sys.executable,'-B','audit/r3_independent_native_verify.py',str(folder/'native_psd_readback.json'),'--expected',str(folder/'expected_psd.json'),'--task',str(folder/'native.task.gz'),'--output',str(output)]
        else:command=[sys.executable,'-B',str(qa/'independent_g3_raw_verify.py'),str(folder),str(output)]
        result=subprocess.run(command,capture_output=True,text=True)
        (qa/f'independent_{name}.log').write_text(result.stdout+result.stderr,encoding='utf-8')
        entry={'name':name,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'returncode':result.returncode,'result_file':str(output),'command':command}
        report['completed'].append(entry);seen.add(name);save();print(name,result.returncode,flush=True)
        if result.returncode:
            report['status']='HOLD_INDEPENDENT_NATIVE_CHECK_FAILED';save();raise SystemExit(1)
    if len(seen)<9:time.sleep(5)
report['status']='NATIVE_FROZEN_QA_PASS_PENDING_FINAL_REVIEW';save();print(report['status'],flush=True)
