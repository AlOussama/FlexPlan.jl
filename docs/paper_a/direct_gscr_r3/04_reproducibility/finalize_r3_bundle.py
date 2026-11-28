"""Collect already qualified R3 evidence; never builds or optimizes a model."""
import csv
import hashlib
import json
from pathlib import Path
import platform
import importlib.metadata
import subprocess
import sys
import shutil
import zipfile

ROOT=Path('E:/ResearchResults/FlexPlan_UC_GSCR/DIRECT_GSCR_FINAL_ACCEPTANCE_BUNDLE_R3_01')
ARCH=Path('E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01')
R2=ROOT.parent/'SCI_GOLD_AC_DIRECT_02_LOCAL_20261127_02'
SOURCE='ebaffb57feb3a27f2d7d87b745930664f625f935'
FORMS=('LPAC','SOC-WR','QCRM')
def read(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):
    with Path(p).open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
def dump(p,x): Path(p).write_text(json.dumps(x,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')
def text(p,x): Path(p).write_text(x,encoding='utf-8')
def git(*a): return subprocess.check_output(['git',*a]).decode().strip()
def table(p,fields,rows):
    with Path(p).open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)

def enrich_preservation():
    preservation=read(ROOT/'00_intake/ORIGINAL_INPUT_PRESERVATION.json')
    if preservation['status']!='PASS': raise RuntimeError('Historical preservation not qualified')
    for x in preservation['authorized_live_source_changes']:
        relative=Path(x['path']).resolve().relative_to(Path.cwd().resolve()).as_posix()
        blob=subprocess.check_output(['git','show','a2cadc4391a3cac1ae06f9f7fc0ea88a62ef4f7e:'+relative])
        matches=[(name,hashlib.sha256(b).hexdigest()) for name,b in [('Git_blob_bytes',blob),('LF_to_CRLF',blob.replace(b'\n',b'\r\n'))] if hashlib.sha256(b).hexdigest()==x['r2_sha256']]
        if not matches: raise RuntimeError('Original source bytes not recoverable')
        x['original_byte_restoration'],x['recovered_original_sha256']=matches[0]
    dump(ROOT/'00_intake/ORIGINAL_INPUT_PRESERVATION.json',preservation)

def collect():
    if git('rev-parse','HEAD')!=SOURCE:
        raise RuntimeError('Collection must use the actual frozen source HEAD')
    if git('status','--porcelain','--untracked-files=no'):
        raise RuntimeError('Tracked source/index must be clean during collection')
    preservation=read(ROOT/'00_intake/ORIGINAL_INPUT_PRESERVATION.json')
    if preservation['status']!='PASS' or any(x.get('recovered_original_sha256')!=x['r2_sha256'] for x in preservation['authorized_live_source_changes']):
        raise RuntimeError('Qualified preservation/restoration receipt missing')
    g0=[];g3=[];builds=[];deltas=[]
    for form in FORMS:
        for method,backends,section in [('G0',('mosek',),'01_native_g0'),('G3',('gurobi','mosek'),'02_native_g3')]:
            for backend in backends:
                d=ROOT/section/f'{form}_{backend}_frozen'
                if any((d/name).exists() for name in ('outcome.json','primal.csv','native_primal.npy')):
                    raise RuntimeError('Reference-only directory unexpectedly contains a new solve output')
                verdict=read(d/('INDEPENDENT_COEFFICIENT_VERDICT.json' if method=='G0' else 'g3_actual_native_verdict.json'))
                if verdict['status']!='PASS': raise RuntimeError('Native qualification failed')
                if method=='G0' and (verdict['blocks']!=168 or verdict['positions']!=118104):
                    raise RuntimeError('Incomplete weekly G0 reference')
                if method=='G3' and (verdict['native_cones_exact']!=8736 or verdict['native_node_rows_exact']!=6216 or verdict['native_q_nonnegative_bounds']!=17472):
                    raise RuntimeError('Incomplete weekly G3 reference')
                receipt=read(ROOT/'04_reproducibility'/f'{method}_{form}_{backend}_frozen_BUILD_RECEIPT.json')
                if receipt['source_commit']!=SOURCE or receipt['source_commit_after']!=SOURCE or receipt['exit_code']!=0:
                    raise RuntimeError('Native reference source/exit mismatch')
                delta=read(ROOT/'05_scientific_results'/f'{method}_{form}_{backend}_FROZEN_SOURCE_DELTA.json')
                if any(x['coefficient_differences'] for x in delta['metrics'].values()):
                    raise RuntimeError('Original source coefficient delta remains')
                if delta['metrics']['M']['exactly_equal_expressions']!=118104:
                    raise RuntimeError('Incomplete full matrix delta')
                compact={k:v for k,v in verdict.items() if k!='native_coordinate_ledger'}
                item=dict(formulation=form,backend=backend,directory=str(d),verdict=compact,
                          verdict_sha256=sha(d/('INDEPENDENT_COEFFICIENT_VERDICT.json' if method=='G0' else 'g3_actual_native_verdict.json')))
                (g0 if method=='G0' else g3).append(item)
                builds.append(receipt);deltas.append(delta)
    qa=read(ROOT/'06_qa/INDEPENDENT_FINAL_REVIEW.json')
    if qa['status']!='PASS' or qa['source_commit']!=SOURCE:
        raise RuntimeError('Frozen independent final QA not passed')
    bridgefile=ROOT/'05_scientific_results/SOC_WR_NATIVE_BRIDGE_CERTIFICATE_TRANSFER.json'
    if read(bridgefile)['status']!='PASS':
        raise RuntimeError('New-native network/certificate target delta not passed')
    dump(ROOT/'01_native_g0/G0_NATIVE_COEFFICIENT_AUDIT.json',dict(status='PASS',source_commit=SOURCE,
         full_networks=3,blocks=504,positions=354312,models=g0,historical_native_identity='UNVERIFIED'))
    text(ROOT/'01_native_g0/G0_NATIVE_TRANSMISSION_VERDICT.md',
         '# New G0 native transmission\n\nPASS: all three frozen weekly MOSEK tasks were persisted, reopened and independently checked as exact binary rational affine links to 168 unscaled PSD matrix variables of order 37 per network (118104 positions per network). All coefficients, constants, trace factors and absence of extra bar objective/AFE couplings passed. No optimization was called. Historical missing native-task identity remains UNVERIFIED.\n')
    proof=ROOT/'02_native_g3/FINITE_EXACT_G3_PROOF.md'
    text(ROOT/'02_native_g3/G3_FINITE_EQUIVALENCE_PROOF.md',proof.read_text(encoding='utf-8'))
    dump(ROOT/'02_native_g3/G3_NATIVE_READBACK_RESULTS.json',dict(status='PASS',source_commit=SOURCE,models=g3))
    rows=[]
    for x in g3:
        v=x['verdict'];rows.append(dict(formulation=x['formulation'],backend=x['backend'],scope='FULL_168H_REFERENCE',status=v['status'],cones=v['native_cones_exact'],node_rows=v['native_node_rows_exact'],q_bounds=v['native_q_nonnegative_bounds'],readback_sha256=v['raw_readback_sha256']))
    for backend in ('gurobi','mosek'):
        small=read(ROOT/'02_native_g3'/'small'/backend/'g3_actual_native_verdict.json')
        if small['status']!='PASS': raise RuntimeError('Small native backend qualification failed')
        rows.append(dict(formulation='DCP',backend=backend,scope='SMALL_NATIVE_ATTACHMENT_PLUS_DCP_REGRESSION',status='PASS',cones=small['native_cones_exact'],node_rows=small['native_node_rows_exact'],q_bounds=small['native_q_nonnegative_bounds'],readback_sha256=small['raw_readback_sha256']))
    table(ROOT/'02_native_g3/G3_NATIVE_BACKEND_MATRIX.csv',list(rows[0]),rows)
    pins=dict(reference_commit='a2cadc4391a3cac1ae06f9f7fc0ea88a62ef4f7e',source_freeze_commit=SOURCE,
        branch='codex/paper-a-q5-digest-139',repository='AlOussama/FlexPlan.jl',archive=str(ARCH),
        case_sha256='66885c9b5d27b21ac1000cf16e8da5d886b7ab50085783957907cebef8a41d3b',
        parent_sha256='ae0f61e54e6aadfc1b4f3cde60f185bbe62c764fde84c96146d714c172b9d531',
        r2_bundle_sha256='c22480d3eb55e146c2321013746cbfe5b214103f0d6481555e982662ad57ebf7',
        owner_request_sha256=sha(ROOT/'00_intake/R3_OWNER_REQUEST.md'))
    dump(ROOT/'00_intake/REFERENCE_PINS.json',pins)
    reused=('RECOVERED_PROOF_EXECUTION.json','QCRM_RECOVERED_CERTIFICATE_AUDIT.json',
        'PHYSICAL_MATRIX_RECONSTRUCTION.json','BOUND_AND_POINT_AUDIT.csv',
        'FOLLOWUP_RECOVERY_PROVENANCE.json','DIRECT_GSCR_LOCAL_REVIEW_RETURN.md')
    dump(ROOT/'00_intake/R2_SCIENTIFIC_REUSE.json',dict(policy='Reuse unchanged accepted original evidence; F02 is not reopened',
        files=[dict(path=str(R2/name),bytes=(R2/name).stat().st_size,sha256=sha(R2/name)) for name in reused]))
    text(ROOT/'00_intake/PRESERVATION_SCOPE_RESOLUTION.md',
        '# Preservation scope resolution\n\nThe first unscoped diagnostic compared all 1251 R2 inventory entries, including the live checkout, under the former read-only policy. Its13 differences are precisely the live source files R3 authorizes to change. PRESERVATION_UNSCOPED_DIAGNOSTIC.json is retained as the original diagnostic. The corrected ORIGINAL_INPUT_PRESERVATION.json reports 1238 byte-identical historical inputs (6333591003 bytes), zero unexpected changes, and all 13 authorized source changes individually. Every original source hash can be reconstructed exactly from the pinned a2cadc4 Git blob with explicitly checked LF/CRLF restoration. Historical archives, points, proofs and manifests were not changed.\n')
    import numpy,scipy
    files=git('show','--pretty=format:','--name-only',SOURCE).splitlines()
    runtime=dict(source_commit=SOURCE,tracked_source_and_index_clean=True,
        julia=read(ROOT/'04_reproducibility/JULIA_RUNTIME.json'),python=dict(executable=sys.executable,executable_sha256=sha(sys.executable),version=sys.version,numpy=numpy.__version__,scipy=scipy.__version__,platform=platform.platform(),packages={d.metadata['Name']:d.version for d in importlib.metadata.distributions() if d.metadata['Name']}),
        solver_libraries=read(ROOT/'04_reproducibility/SOLVER_LIBRARY_HASHES.json'),
        source_files={p:dict(bytes=Path(p).stat().st_size,sha256=sha(p)) for p in files if p},
        full_pre_freeze_patch_sha256=sha(ROOT/'04_reproducibility/FULL_R3_STAGED_PATCH.diff'),builds=builds,
        historical_runtime='Historical incompleteness remains; no new investigation of historical1201EUR drift',
        collector_sha256=sha(__file__),optimization_scope=dict(new_weekly_optimizations=0,
            new_weekly_primal_outputs=0,solver_calls='Only completed small regression fixtures; existing study results reused'))
    dump(ROOT/'04_reproducibility/RUNTIME_MANIFEST.json',runtime)
    commands=f'''# R3 reproduction commands

Scientific source: `{SOURCE}`. Working directory: `D:/Projekte/Code/FlexPlan_UC_GSCR`.
Use the recorded Julia 1.11.5 executable, committed Manifest-v1.11.toml and original input paths from REFERENCE_PINS.json. New output must be a fresh writable E: directory; the reference launcher checks E: capacity/writability. The nine actual commands, environments, UTC times and exits are preserved in the individual *_frozen_BUILD_RECEIPT.json files.

```powershell
& ./scripts/paper_a/run_r3_native_references.ps1 -OutputRoot 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH'
```

This builds three G0/MOSEK and six G3/(Gurobi,MOSEK) weekly references. PAPER_A_AC_REFERENCE_ONLY=1 returns before optimize!. The launcher currently checks unstaged changes; the independent index/worktree supplement additionally verifies staged cleanliness for the actual delivered runs. Verify `git status --porcelain --untracked-files=no` is empty before reproduction.

For each G0 reference directory D, the independent persisted-task check is:

```powershell
& 'C:/ProgramData/anaconda3/python.exe' audit/r3_independent_native_verify.py D/native_psd_readback.json --expected D/expected_psd.json --task D/native.task.gz --output D/INDEPENDENT_COEFFICIENT_VERDICT.json
```

For each frozen reference, compare to the original same-formulation G3 ledger (LPAC, SOC-WR, QCRM respectively):

```powershell
& 'C:/ProgramData/anaconda3/python.exe' scripts/paper_a/compare_original_ledgers.py ORIGINAL_G3_DIRECTORY NEW_REFERENCE_DIRECTORY NEW_SOURCE_DELTA.json
```

Original LPAC G3 point, with expected bytes frozen BEFORE evaluation (fresh manifest/output paths):

```powershell
$study='E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01'
& 'C:/ProgramData/anaconda3/python.exe' -B scripts/paper_a/replay_direct_ac.py $study "$study/DIRECT_GSCR_PM0217_01/LPAC_G3" "$study/DIRECT_GSCR_PM0217_01/LPAC_G3_solve" --freeze-manifest 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH/LPAC_G3_inputs.json'
& 'C:/ProgramData/anaconda3/python.exe' -B scripts/paper_a/replay_direct_ac.py $study "$study/DIRECT_GSCR_PM0217_01/LPAC_G3" "$study/DIRECT_GSCR_PM0217_01/LPAC_G3_solve" --manifest 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH/LPAC_G3_inputs.json' --output 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH/LPAC_G3_original'
```

The manifest-generation command freezes expected bytes without evaluating. Replay refuses missing or changed expected data and Python -O. The final delivered point uses LPAC_G3_inputs_guarded.json and LPAC_G3_original_guarded. Historical F02 and exact lower certificates are reused without re-optimization or renewed mathematical review.

Runtime inventory command, using the E: depot/temp variables below:

```powershell
& 'C:/Users/User/.julia/juliaup/julia-1.11.5+0.x64.w64.mingw32/bin/julia.exe' --startup-file=no --project=. scripts/paper_a/r3_runtime_inventory.jl 'E:/ResearchResults/FlexPlan_UC_GSCR/R3_REPRODUCE_FRESH/JULIA_RUNTIME.json'
```

'''
    text(ROOT/'04_reproducibility/REPRODUCTION_COMMANDS.md',commands+(ROOT/'06_qa/REGRESSION_COMMANDS.md').read_text(encoding='utf-8'))
    bounds={'LPAC':(125908036326,125908201990,127407323716,128269955797),
            'SOC-WR':(126073509961,126076996187,127395770699,128111711714),
            'QCRM':(126073509961,137183220337,127395770699,137183220337)}
    rows=[];premiums=[]
    for form,(bl,bu,gl,gu) in bounds.items():
        for method,lo,hi in [('BASE',bl,bu),('G0',gl,gu)]:
            rows.append(dict(formulation=form,method=method,lower_EUR2025=lo,point_ceiling_EUR2025=hi,
                lower_evidence='EXACT_CERTIFIED_FLOORED_LB_REUSED_R2',upper_evidence='NUMERICALLY_QUALIFIED_POINT_NOT_RIGOROUS_EXACT_UB',new_optimization=False))
        premiums.append(dict(claim='G0_minus_BASE',formulation=form,lower_EUR2025=max(0,gl-bu),upper_EUR2025=gu-bl,evidence='NUMERICAL_POINT_QUALIFIED_INTERVAL_NOT_RIGOROUS_EXACT_UB_INTERVAL'))
    for form,lo,hi in [('LPAC',128350606292,128350714491),('SOC-WR',128548307287,128555000000)]:
        rows.append(dict(formulation=form,method='G2',lower_EUR2025=lo,point_ceiling_EUR2025=hi,lower_evidence='EXACT_CERTIFIED_FLOORED_LB_REUSED_R2',upper_evidence='NUMERICALLY_QUALIFIED_POINT_NOT_RIGOROUS_EXACT_UB',new_optimization=False))
        gl,gu=bounds[form][2:];premiums.append(dict(claim='G2_minus_G0',formulation=form,lower_EUR2025=lo-gu,upper_EUR2025=hi-gl,evidence='NUMERICAL_POINT_QUALIFIED_INTERVAL_NOT_RIGOROUS_EXACT_UB_INTERVAL'))
    rows.append(dict(formulation='QCRM',method='G2',lower_EUR2025=None,point_ceiling_EUR2025=137183220337,lower_evidence='NO_G2_LB_CLAIM_HERE',upper_evidence='DONOR_COST_CEILING_REUSED_IN_G0_AND_BASE_NO_NEW_G2_UB_CLAIM',new_optimization=False))
    for row in rows: row['sensitivity_point_EUR2025']=None
    sensitivity=read(ROOT/'03_replay_integrity/LPAC_G3_original_guarded/original_model_audit.json')['original_cost_EUR2025']
    for form in FORMS:
        rows.append(dict(formulation=form,method='G3',lower_EUR2025=bounds[form][2],point_ceiling_EUR2025=None,
            lower_evidence='EXACT_FLOORED_LB_TRANSFERRED_FROM_R2_G0_VIA_ACCEPTED_G0_G3_PROJECTION_EQUIVALENCE',upper_evidence='SENSITIVITY_ONLY_NOT_GOLD_UB' if form=='LPAC' else 'NO_ACCEPTED_GOLD_POINT_CLAIM',
            new_optimization=False,sensitivity_point_EUR2025=sensitivity if form=='LPAC' else None))
    for row in rows: row['new_native_solver_LB_EUR2025']=None
    certpaths={'LPAC':('reused_lower_original_runtime/LPAC_G0/exact_dual_1.json','lower_original_EUR2025_annual_floor'),
        'SOC-WR':('reused_soc_stage_retry/SOC/g0_certified_lower_boxdiag_PM0217.json','original_cost_EUR_annual_equivalent_lower_floor'),
        'QCRM':('recovered_transfer/QCRM/g0_certified_lower_boxdiag_PM0217.json','G0_lower_EUR_annualized')}
    transfers=[]
    for form,(path,key) in certpaths.items():
        cert=R2/path
        if read(cert)[key]!=bounds[form][2]: raise RuntimeError('Preserved G0 certificate value mismatch')
        transfers.append(dict(formulation=form,original_G0_certificate=dict(path=str(cert),bytes=cert.stat().st_size,sha256=sha(cert)),
            transferred_G3_lower_EUR2025=bounds[form][2],new_native_solver_LB=None,new_optimization=False,
            evidence_class='EXACT_FLOORED_LB_TRANSFERRED_FROM_R2_G0_VIA_ACCEPTED_G0_G3_PROJECTION_EQUIVALENCE',
            new_native_network_applicability_sha256=sha(bridgefile),
            native_G3_verdicts=[dict(path=str(ROOT/'02_native_g3'/f'{form}_{backend}_frozen'/'g3_actual_native_verdict.json'),sha256=sha(ROOT/'02_native_g3'/f'{form}_{backend}_frozen'/'g3_actual_native_verdict.json')) for backend in ('gurobi','mosek')],
            source_deltas=[dict(path=str(ROOT/'05_scientific_results'/f'G3_{form}_{backend}_FROZEN_SOURCE_DELTA.json'),sha256=sha(ROOT/'05_scientific_results'/f'G3_{form}_{backend}_FROZEN_SOURCE_DELTA.json')) for backend in ('gurobi','mosek')],
            qualification='Accepted original Supporting-LP and PSD certificate targets retained; no full finite SOC-QCP nesting claim'))
    dump(ROOT/'05_scientific_results/G3_LOWER_CERTIFICATE_TRANSFER_BINDINGS.json',dict(status='PASS',source_commit=SOURCE,transfers=transfers))
    table(ROOT/'05_scientific_results/FINAL_BOUND_AND_POINT_MATRIX.csv',list(rows[0]),rows)
    table(ROOT/'05_scientific_results/FINAL_PREMIUM_INTERVALS.csv',list(premiums[0]),premiums)
    text(ROOT/'05_scientific_results/SCIENTIFIC_CLAIM_QUALIFICATION.md',
         '# Scientific claim qualification\n\nExact lower-bound certificates and F02 are reused unchanged from the SHA-bound R2 evidence. New reference deltas check all 118104 M expressions per model, exact costs, quota and 6216 P/6216 Q balances; same-index nonterminal coefficients are explicitly distinguished from independently named terminal coordinates. Their source constructors and variable roster are unchanged by the scoped production delta; R2 original selector recovery supplies the physical binding. No new primal or optimum is asserted.\n\nAll listed point ceilings are numerical tolerance-qualified witnesses, not rigorously exact feasible upper bounds. LPAC G0 hour 108 retains its approximately -2.237e-10 eigenvalue qualification. LPAC G3 remains SENSITIVITY_ONLY — NOT_GOLD_UB; its original native residual 2.1320e-5 and generator excess 0.00115556 MW fail original GOLD gates. Its cost approximately 127926227129.6 EUR gives only a sensitivity comparison with BASE, approximately [2018025139,2018190804]EUR.\n\nThe scenario uses online Q boxes Q/P=.4, load pf=.98, 43 HVDC links and invested-capacity Q at new renewable terminals. Missing terminal MVA circles are an explicit scenario assumption. Continuous relaxed LPAC/SOC-WR/QCRM evidence implies neither exact nonlinear AC feasibility nor integer optimality nor dynamic stability. Historical G0 native identity remains UNVERIFIED; historical rounded G3 bridges remain the documented R2 failure, not retroactively repaired.\n')
    with (ROOT/'05_scientific_results/SCIENTIFIC_CLAIM_QUALIFICATION.md').open('a',encoding='utf-8') as stream:
        stream.write('\nThe exact floored G0 lower certificates are also transferred to G3 by the accepted projection equivalence, after all native/source checks and the explicit network-bridge applicability gate. G3 lower bounds are LPAC 127407323716, SOC-WR 127395770699 and QCRM 127395770699 EUR2025; these are transferred certificates, not new solver lower bounds. G3 GOLD point ceilings remain unclaimed. G3_LOWER_CERTIFICATE_TRANSFER_BINDINGS.json binds the preserved certificates, native checks and deltas.\n\nThe bridge gate records all 8736 actual new SOC-WR voltage products, the same old primary voltage coordinate pairs, gamma=2535301200456458353478625262249/2535301200456458802993406410752<1 with nonnegative voltage factors, and the already accepted BASE 8736 + G2 8736 supporting planes with exact direction norm squared <= 1. This establishes applicability to the new target without assuming whole old/new native-task identity or full finite SOC-QCP nesting. F02 and the original certificates remain unchanged.\n')
    findings=[('F01','PASS_NEW_NATIVE_G0','HISTORICAL_G0_IDENTITY_UNVERIFIED'),('F02','PASS_REUSED_CLOSED','NO_RECONSIDERATION'),('F03','PASS_NEW_FINITE_G3','HISTORICAL_ROUNDED_BRIDGE_FAIL_RETAINED'),('F04','PASS_PREBOUND_REPLAY','NEGATIVE_CONTROLS_PASS'),('F05','PASS_ORIGINAL_ALGEBRA_AUDITOR','TRANSFORMED_SOLVER_AUDIT_SEPARATE'),('F06','PASS_NEW_RUNTIME_FREEZE','HISTORICAL_INCOMPLETENESS_RETAINED'),('F07','CLOSED_SENSITIVITY_ONLY','NOT_GOLD_UB')]
    table(ROOT/'06_qa/FINAL_FINDINGS_MATRIX.csv',['finding','new_disposition','historical_or_scope_qualification'],[dict(zip(['finding','new_disposition','historical_or_scope_qualification'],r)) for r in findings])
    status='R3_TECHNICALLY_ACCEPTED_WITH_EXPLICIT_SCOPE_LIMITATIONS'
    text(ROOT/'README.md',f'# Direct gSCR final acceptance R3\n\n{status}\n\nStart with DIRECT_GSCR_FINAL_ACCEPTANCE_R3_HANDOFF.md. Source freeze: {SOURCE}. Native *_frozen directories are final; earlier unsuffixed development probes are excluded from final acceptance. Historical originals/R1/R2 remain immutable. The artifact manifest excludes compilation caches/temp and recursive seal/publication files. Formal acceptance is reserved to S-GOV.\n')
    text(ROOT/'DIRECT_GSCR_FINAL_ACCEPTANCE_R3_HANDOFF.md',f'''# DIRECT_GSCR_FINAL_ACCEPTANCE_R3_HANDOFF

**{status}**

To S-GOV. Scientific source freeze `{SOURCE}` on `codex/paper-a-q5-digest-139`, continuation of reference `a2cadc4391a3cac1ae06f9f7fc0ea88a62ef4f7e`. Owner R3 supersedes the original prohibition on the specifically authorized production repairs. Historical evidence remains immutable.

| Dimension | Decision |
|---|---|
| Mathematical methodology | PASS, accepted method and F02 reused |
| New native G0 implementation | PASS, three saved/reopened tasks, 504 PSD blocks, 354312 complete affine matrix positions |
| New finite G3 implementation | PASS, six full native backend/formulation references plus regular/singular/edge/isolated/reducible fixtures and negative controls |
| Historical native G0 identity | UNVERIFIED, unchanged historical limitation |
| Historical finite G3 equivalence | R2 rounded-bridge failure retained |
| Replay integrity | PASS, prebound expected inputs and fail-closed negatives |
| New runtime contract | PASS, full patch, pinned source, packages/solver runtime, parameters and per-build receipts |
| Scientific results | Reused exact LB certificates; numerical tolerance-qualified points; no new optimum |
| Targeted regression and independent final QA | PASS, see 06_qa |
| Publication readiness of result claims | CONDITIONAL on the explicit numerical/scenario scope |

L0–L4 are consolidated through R2 intake and AP0–AP6: identity/inventory is pinned; original physical/model and F02 proofs are reused with exact new-source deltas; lower certificates retain exact floored status; upper witnesses retain numerical qualification; regression, negative controls and independent final review bind the new source. The original LPAC G3 point is SENSITIVITY_ONLY — NOT_GOLD_UB. No broad weekly reoptimization, new scientific method, tolerance relaxation, integer claim or exact AC-feasibility claim was introduced.

There were zero new KW08/168-hour optimizations. The nine new native references were built and exported without optimize!; solver calls were restricted to the completed small regression fixtures. All scientific study points and results were reused from the protected archive.

The following EUR2025 intervals combine exact floored lower bounds with numerically tolerance-qualified point ceilings. They are not intervals established by rigorously exact feasible upper bounds.

| Network | Direct G0 LB | Numerical G0 point ceiling | G0 minus BASE interval |
|---|---:|---:|---|
| LPAC | 127407323716 | 128269955797 | [1499121726,2361919471] |
| SOC-WR | 127395770699 | 128111711714 | [1318774512,2038201753] |
| QCRM | 127395770699 | 137183220337 | [0,11109710376] |

The same qualified G2 minus G0 comparisons are LPAC [80650495,943390775] and SOC-WR [436595573,1159229301] EUR2025. LPAC G0 retains its approximately -2.237e-10 numerical PSD qualification. The LPAC G3 point costs approximately 127926227129.6 EUR2025 but fails original GOLD gates (native residual 2.1320e-5, generator P excess 0.00115556 MW); it supplies no GOLD upper bound or optimality claim.

The same exact floored lower certificates also apply to corrected G3 by the accepted G0/G3 projection equivalence, with certificate/native/source bindings in G3_LOWER_CERTIFICATE_TRANSFER_BINDINGS.json. These are not new solver bounds. The new SOC-WR network bridge was separately checked against the already qualified old Supporting-Planes: all 8736 actual product domains and all BASE/G2 plane directions satisfy the existing implication recipe. No blanket old/new native-physics identity or full finite SOC-QCP nesting is assumed; F02 remains closed.

The full evidence is organized in 00_intake through 06_qa. FINAL_BOUND_AND_POINT_MATRIX.csv and FINAL_PREMIUM_INTERVALS.csv distinguish exact lower evidence from numerical point ceilings. Historical runtime/native limitations are documented, not retroactively closed. Large tasks/native files remain on E: and are individually SHA-256-bound in ARTIFACT_SHA256_MANIFEST.json. BUNDLE_SHA256.txt seals that manifest. PUBLICATION_RECEIPT.json binds final delivery HEAD and verified remote HEAD separately, avoiding a recursive self-hash. Productive sources, tests, methods and compact results are accessible in the development branch, not solely in a ZIP.

No new material implementation HOLD remains after the independent final QA. Formal S-GOV acceptance remains reserved to S-GOV.
''')

def seal():
    excluded={'ARTIFACT_SHA256_MANIFEST.json','BUNDLE_SHA256.txt','PUBLICATION_RECEIPT.json'}
    records=[]
    for p in sorted(ROOT.rglob('*')):
        rel=p.relative_to(ROOT)
        if not p.is_file() or rel.parts[0] in {'julia_depot','tmp'} or '__pycache__' in rel.parts or str(rel) in excluded: continue
        records.append(dict(path=rel.as_posix(),bytes=p.stat().st_size,sha256=sha(p)))
    target=ROOT/'ARTIFACT_SHA256_MANIFEST.json'
    dump(target,dict(source_commit=SOURCE,files=records,excluded=['julia_depot/**','tmp/**','**/__pycache__/**',*sorted(excluded)],self_hash_rule='BUNDLE_SHA256.txt is SHA256 of this manifest'))
    text(ROOT/'BUNDLE_SHA256.txt',sha(target)+'  ARTIFACT_SHA256_MANIFEST.json\n')
    print('BUNDLE_MANIFEST_SHA256',sha(target),'FILES',len(records))

def publish_docs():
    target=Path('docs/paper_a/direct_gscr_r3').resolve()
    target.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(__file__,ROOT/'04_reproducibility/finalize_r3_bundle.py')
    selected=[ROOT/'README.md',ROOT/'DIRECT_GSCR_FINAL_ACCEPTANCE_R3_HANDOFF.md']
    for section in ('00_intake','01_native_g0','02_native_g3','03_replay_integrity','04_reproducibility','05_scientific_results','06_qa'):
        selected.extend(p for p in (ROOT/section).iterdir() if p.is_file() and p.suffix.lower() in {'.md','.json','.csv','.diff','.py'} and p.name!='R3_OWNER_REQUEST.md' and p.stat().st_size<2*1024**2)
    selected.extend((ROOT/'03_replay_integrity/LPAC_G3_original_guarded'/name) for name in ('original_model_audit.json','native_solver_audit.json'))
    copied=[]
    for p in sorted(set(selected)):
        relative=p.relative_to(ROOT);dest=target/relative
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(p,dest)
        if sha(p)!=sha(dest): raise RuntimeError('Repository evidence copy differs')
        copied.append(dict(bundle_path=relative.as_posix(),repository_path=dest.relative_to(Path.cwd()).as_posix(),bytes=p.stat().st_size,sha256=sha(p)))
    mapping=dict(source_commit=SOURCE,files=copied,policy='Compact evidence only; native models and raw arrays remain in the E: archive. Seal/map files excluded from self-list.')
    dump(ROOT/'REPOSITORY_EVIDENCE_MAP.json',mapping)
    shutil.copyfile(ROOT/'REPOSITORY_EVIDENCE_MAP.json',target/'REPOSITORY_EVIDENCE_MAP.json')
    print('COMPACT_REPOSITORY_FILES',len(copied))

def archive_bundle():
    target=ROOT.with_suffix('.zip')
    if target.exists(): raise RuntimeError('Preserve existing bundle ZIP')
    manifest=read(ROOT/'ARTIFACT_SHA256_MANIFEST.json')
    paths=[ROOT/x['path'] for x in manifest['files']]+[ROOT/'ARTIFACT_SHA256_MANIFEST.json',ROOT/'BUNDLE_SHA256.txt']
    with zipfile.ZipFile(target,'x',zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as z:
        for p in paths: z.write(p,ROOT.name+'/'+p.relative_to(ROOT).as_posix())
    print('BUNDLE_ZIP_SHA256',sha(target),'BYTES',target.stat().st_size)

def preserve():
    manifest=R2/'ORIGINAL_EVIDENCE_MANIFEST.json'
    entries=read(manifest)['files'];changed=[];checked_bytes=0;authorized=[]
    repo=Path.cwd().resolve()
    allowed=set(git('diff','--name-only','a2cadc4391a3cac1ae06f9f7fc0ea88a62ef4f7e',SOURCE).splitlines())
    for x in entries:
        p=Path(x['path'])
        if not p.is_file() or p.stat().st_size!=x['bytes'] or sha(p)!=x['sha256']:
            relative=p.resolve().relative_to(repo).as_posix() if p.resolve().is_relative_to(repo) else None
            if relative in allowed:
                blob=subprocess.check_output(['git','show','a2cadc4391a3cac1ae06f9f7fc0ea88a62ef4f7e:'+relative])
                exact_old=any(hashlib.sha256(b).hexdigest()==x['sha256'] for b in (blob,blob.replace(b'\n',b'\r\n')))
                authorized.append(dict(path=str(p),r2_sha256=x['sha256'],new_sha256=sha(p),original_base_commit_preserved=True,exact_original_bytes_recoverable_from_base_blob=exact_old,disposition='R3_AUTHORIZED_LIVE_SOURCE_CHANGE_NOT_IMMUTABLE_RESULT'))
            else: changed.append(x['path'])
        else: checked_bytes+=x['bytes']
    report=dict(status='PASS' if not changed else 'FAIL',checked_files=len(entries),unchanged_files=len(entries)-len(authorized)-len(changed),checked_unchanged_bytes=checked_bytes,unexpected_changes=changed,authorized_live_source_changes=authorized,reference_manifest_sha256=sha(manifest),scope='R2 immutable original results preserved; R3-authorized live checkout source edits explicitly separated')
    dump(ROOT/'00_intake/ORIGINAL_INPUT_PRESERVATION.json',report)
    print(json.dumps(report))
    if changed: raise RuntimeError('Historical input preservation failed')

if __name__=='__main__':
    if sys.argv[1:] == ['seal']: seal()
    elif sys.argv[1:] == ['collect']: collect()
    elif sys.argv[1:] == ['preserve']: preserve()
    elif sys.argv[1:] == ['enrich-preservation']: enrich_preservation()
    elif sys.argv[1:] == ['publish-docs']: publish_docs()
    elif sys.argv[1:] == ['archive']: archive_bundle()
    else: raise SystemExit('usage: finalize_r3_bundle.py collect|seal|preserve|enrich-preservation|publish-docs|archive')
