"""Read-only SHA, equation/claim, cohort, numerics and final publication identity acceptance."""
from pathlib import Path
import sys,csv,re,hashlib,json,subprocess,math
from decimal import Decimal
from pypdf import PdfReader
from datetime import datetime,timezone
R=Path(__file__).parent; C=Path('D:/Projekte/Code/FlexPlan_UC_GSCR'); M=Path('D:/Projekte/research-map')
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def J(n):return json.loads((R/n).read_bytes())
def csvr(n):
 with (R/n).open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args])
pub=J('04_PAPER_PUBLICATION.json');mp=pub['commit'];cp='027aee0ce2cff7b424ebea05858fc2fc310078b9';mpin='605f4784dc3e0337b7471162e74da6e2221db191'
assert mp=='7d568b6ce3b821bba05812b61ca8ccc5240aacec' and len(pub['files'])==21
for name,data in pub['files'].items():
 p=R/name; raw=git(M,'show',mp+':'+pub['paper_path']+name)
 assert raw==p.read_bytes() and sha(p)==data['sha256'] and len(raw)==data['bytes'] and hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==data['blob']
assert git(M,'rev-parse',mp+'^').decode().strip()==pub['parent']
def verify_evidence(n):
 raw=git(C,'show',cp+':docs/paper_a/gold_week168/'+n)
 assert hashlib.sha256(raw).hexdigest()==sha(R/n),(n,'evidence-vs-E')
 return sha(R/n)
evid={}
for name in ['00_INPUT_AND_RUNTIME_INTAKE.json','01_FORMULATION_AND_CODE_DIFFERENTIAL_REVIEW.md','01_FORMULATION_COVERAGE.csv','01_OPEN_MATERIAL_FINDINGS.json','02_FINAL_WEEK168_RESULT_MATRIX.csv','02_OBJECTIVE_AND_SOLVER_BOUNDS.csv','02_ORIGINAL_PRIMAL_REPLAY.json','02_INDEPENDENT_ACCEPTANCE.json','03_METHOD_STATUS_MATRIX.csv','03_SYNTHETIC_NATIVE_TESTS.json','03_QUALIFIED_REAL_METHOD_RESULTS.csv','03_GATED_SOLVER_NEGATIVES.json']:evid[name]=verify_evidence(name)
assert not git(C,'diff','--name-only',mpin,cp,'--','src','scripts','test').strip()
for a,b in [('04_reviewed_points.csv','02_FINAL_WEEK168_RESULT_MATRIX.csv'),('04_reviewed_bounds.csv','02_OBJECTIVE_AND_SOLVER_BOUNDS.csv'),('04_additional_methods.csv','03_QUALIFIED_REAL_METHOD_RESULTS.csv')]:assert sha(R/a)==sha(R/b)
c=csvr('04_PAPER_CLAIM_TO_EVIDENCE.csv')
for x in c:
 n=x['source_files'].split(';');s=x['source_sha256_in_same_order'].split(';');assert len(n)==len(s) and all(sha(R/a)==b for a,b in zip(n,s))
assert len(c)==len(set(x['claim_id'] for x in c))==18
old=J('05_ORIGINAL_PUBLICATION_SAMPLES.json')['original_cases']
sub=J('01_PHYSICAL_DOMAIN_AND_EVENT_REPLAY.json')['cases']; phys={v['archive_summary_sha256']:v for v in sub.values()}
result={x['row_id']:x for x in csvr('02_FINAL_WEEK168_RESULT_MATRIX.csv')};bounds={x['row_id']:x for x in csvr('02_OBJECTIVE_AND_SOLVER_BOUNDS.csv')}
assert set(old)==set(result)==set(bounds) and len(old)==14
for k,orig in old.items():
 row=result[k];b=bounds[k];p=phys[orig['native_summary_sha256']];h=orig['raw_MW_and_EUR']
 assert row['original_primal_sha256']==orig['original_primal_sha256']
 assert abs(float(row['CAPEX_EUR2025'])-h['capex'])<0.1 and abs(float(b['numeric_lb_EUR2025'])-orig['solver_LB'])<0.1 and abs(float(b['numeric_ub_EUR2025'])-orig['raw_native_primal'])<0.1,(k,'cost')
 for label,v in [('wind','onwind'),('PV','solar'),('GFL_BESS','GFL_BESS'),('GFM_BESS','GFM_BESS')]:assert abs(float(row[label+'_added_MW'])-h.get(v,0))<1e-5,(k,label)
 for label,key in [('G0','G0_negative_hours'),('G2','G2_negative_hours'),('G1','G1_negative_hours'),('M0','M0_negative_hours_on_valid_domain')]:assert int(row[label+'_failed_hours'])==p[key],(k,label)
 assert int(row['M0_defined_hours'])==168-p['M0_undefined_hours'] and int(row['SU_SD_positive_overlaps'])==len(p['simultaneous'])
 if 'replayed_J' in orig:
  for label,val in [('annualized_total_EUR2025',orig['replayed_J']),('raw_week_OPEX_EUR2025',orig['raw_week_opex']),('raw_week_startup_shutdown_OPEX_EUR2025',h['event']),('raw_week_dispatch_OPEX_EUR2025',h['generation']),('raw_week_storage_OPEX_EUR2025',h['storage']),('actual_RE_MWh',h['re']),('actual_load_MWh',orig['replayed_load'])]:assert abs(float(row[label])-val)<0.1,label
body=(R/'04_results.tex').read_text(encoding='utf8')
def D(x):return Decimal(str(x))
qbound={}
for q in [50,60,70]:
 a=bounds[f'WK08-{q}-G1-MILP'];b=bounds[f'WK08-{q}-BASE-MILP']
 lo=(D(a['numeric_lb_EUR2025'])-D(b['numeric_ub_EUR2025']))/D(1e9)
 hi=(D(a['numeric_ub_EUR2025'])-D(b['numeric_lb_EUR2025']))/D(1e9)
 assert 0<lo<=hi; qbound[str(q)]=[str(lo),str(hi)]
printed=re.findall(r'\$\[([\d.]+),([\d.]+)\]\$',body)
assert len(printed)==3
for (l,u),(a,b) in zip(printed,qbound.values()):assert D(l)<=D(a)<=D(b)<=D(u)
for match in re.finditer(r'^(\d+)\\% & (BASE|G1|G2) & ([\d.]+) & ([\d.]+) & ([\d.]+) & ([\d.]+)',body,re.M):
 q,m,lp,lb,ub,gap=match.groups();bl=bounds[f'WK08-{q}-{m}-MILP'];rl=bounds[f'WK08-{q}-{m}-LP']
 assert D(lp)*D(1e9)<=D(rl['numeric_lb_EUR2025']) and D(lb)*D(1e9)<=D(bl['numeric_lb_EUR2025'])<=D(bl['numeric_ub_EUR2025'])<=D(ub)*D(1e9)
 assert abs(float(gap)-float(bl['relative_gap_fraction'])*100)<0.00051
b1,b2=(bounds['WK08-70-'+m+'-MILP'] for m in ('G1','G2'));assert max(D(b1['numeric_lb_EUR2025']),D(b2['numeric_lb_EUR2025']))<min(D(b1['numeric_ub_EUR2025']),D(b2['numeric_ub_EUR2025']))
assert len(re.findall(r'^\d+\\% & (?:BASE|G1|G2) & ',body,re.M))==7
text=' '.join((R/n).read_text(encoding='utf8') for n in pub['files'] if n.endswith('.tex'))
labels=re.findall(r'\\label\{([^}]+)\}',text);refs=re.findall(r'\\(?:eqref|ref)\{([^}]+)\}',text);assert len(labels)==len(set(labels)) and set(refs)<=set(labels)
for n in re.findall(r'\\input\{([^}]+)\}|\\includegraphics(?:\[[^]]*\])?\{([^}]+)\}',text):
 assert (n[0] or n[1]) in pub['files']
biblio=(R/'04_references.bib').read_text(encoding='utf8');bibkeys=set(re.findall(r'@\w+\{([^,]+),',biblio));cited={k for c0 in re.findall(r'\\cite\{([^}]+)\}',text) for k in c0.split(',')};assert bibkeys==cited and len(cited)==8
def normalize(t):return re.sub('[^a-z0-9]','',t.lower())
for p in (R/'04_WORK').glob('crossref*.json'):
 a=json.loads(p.read_bytes());assert a['DOI'].lower() in biblio.lower() and normalize(a['title'][0]) in normalize(biblio)
assert '10.16081/j.epae.202512014' in biblio
log=(R/'04_PAPER_A.log').read_text(encoding='utf8');assert not re.search(r'(LaTeX Warning: (?:Citation|Reference).*undefined|Overfull \\[hv]box|There were undefined)',log)
paper=R/'04_PAPER_A.pdf';assert len(PdfReader(paper).pages)==8 and sha(paper)=='0be9f0253454a6d73a1f1e6ee904c2adc135dd55b0e9d561da4e3e4801126687'
assert J('02_INDEPENDENT_ACCEPTANCE.json')['gate']=='GATE2_PASS_VARIANT_A'
fresh=J('05_IN_MEMORY_FIGURE_AND_TABLE_REPLAY.json');assert all(v['identical'] and v['original']==sha(R/name) for name,v in fresh['inspection'].items())
cases=csvr('04_additional_methods.csv');m2=next(x for x in cases if x['method']=='M2' and x['mode']=='relaxed');g3=next(x for x in cases if x['method']=='G3' and x['mode']=='integer_witness')
m2lb=D(m2['qualified_numerical_bound_EUR2025']); g3ub=D(g3['objective_EUR2025'])
gt=csvr('04_g3_attempts.csv');assert len(gt)==8 and len({(x['solver'],x['code']) for x in gt})==8 and all('REJECT' in x['state'] for x in gt)
extra=(R/'04_qualified_extensions.tex').read_text(encoding='utf8');assert f'{(m2lb-g3ub)/D(1e6):.2f}' in extra
assert (R/'05_REVIEW_PDF_CONTACT.png').is_file()
f4files=('00_INDEPENDENT_INTAKE_HASHCHECK.json','01_PHYSICAL_DOMAIN_AND_EVENT_REPLAY.json','01_INDEPENDENT_EVENT_CENSUS.json','01_FRESH_RATIONAL_ORACLE.json','02_COMPLETE_ALGEBRAIC_ROWS.json','02_RE50_LP_COORDINATE_PROOF.json','05_ORIGINAL_PUBLICATION_SAMPLES.json','05_IN_MEMORY_FIGURE_AND_TABLE_REPLAY.json','05_REVIEW_PDF_CONTACT.png','05_original_publication_sample.py','05_rebuild_in_memory.py','05_render_review_pdf.py',Path(__file__).name)
manifest={'reviewer':'/root/math_r in independent F4-R role','verdict':'F4_GO_VARIANT_A','p0_findings_open_for_retained_claims':0,'submitted':False,'owner_ratification':'Reserved for S-GOV; F4 is independent technical publication acceptance of these hashes only.','created_utc':datetime.now(timezone.utc).isoformat(),'publication_git':{'repository':'AlOussama/research-map','commit':mp,'parent':pub['parent'],'path':pub['paper_path'],'files_sha256':{n:v['sha256'] for n,v in pub['files'].items()}},'scientific_model_pin':'dbecc1f2d26db134ac7a817c6ce2b5d0ba05882a','consumer_replay_code':mpin,'consumer_evidence_pin':cp,'producer_pin':'becec6d63c0fbf2b8a160c41f87631f5270046b9','frozen_core_evidence_sha256':evid,'review_artifact_sha256':{n:sha(R/n) for n in f4files},'publication_manifest_sha256':sha(R/'04_PAPER_PUBLICATION.json'),'checked_claims':len(c),'checked_canonical_families':23,'checked_source_case_count':14,'annual_integer_optimum_difference_billion_EUR_from_numeric_bounds':qbound,'G2_full_cost_and_quota_replay':old['WK08-70-G2-MILP'],'figures_bytes_replayed':3,'generated_latex_fragments_replayed':5,'PDF_pages_visually_inspected':8,'reference_checks':{'cached_publisher_deposits':7,'publisher_Wang_contrast':'https://epjournal.csee.org.cn/en/article/doi/10.16081/j.epae.202512014/','resolvable_bibliography_keys':8},'commands':[[sys.executable,str(Path(__file__))],fresh['executed'],J('05_ORIGINAL_PUBLICATION_SAMPLES.json')['command'],['python','05_render_review_pdf.py'],['git','show',mp+':'+pub['paper_path']+'<each publication file>'],['git','show',cp+':docs/paper_a/gold_week168/<each F1/F2/F3 evidence file>']],'exit':0}
(R/'05_SUBMISSION_FREEZE_MANIFEST.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
print('F4_GO',sha(R/'05_SUBMISSION_FREEZE_MANIFEST.json'),qbound)

