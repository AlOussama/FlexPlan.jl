from pathlib import Path
import hashlib,json,csv,os,subprocess,sys
r=Path(os.environ.get('PAPER_A_F2_OUTPUT_ROOT',Path(__file__).resolve().parent));b=Path(os.environ.get('PAPER_A_F2_INPUT_ROOT',Path(__file__).resolve().parent.parent))
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def rd(p):return json.loads(p.read_bytes())
p=b/'TECH_FULL37_KW08_RE70_STRENGTH_COMPARISON_20261118_01';q=p/'INDEPENDENT_REVIEW';neut=rd(q/'actual_parent_G1_byte_baseline.json')['neutral_complete_case_sha256'];refs=[q/'actual_parent_G1_byte_baseline.json',b/'TECH_FULL37_KW08_RE60_70_FROZEN_E_20261118_01/independent_quota_delta_review.json']
for method in ['G2','G3']:
 f=q/f'actual_case_byte_review_{method}_c842bbd.json';d=rd(f);assert d['status']=='PASS' and d['full_case_neutral_structure_sha256']==neut and d['all_nonvariant_fields_same_including_network_costs_assets_profiles'] and d['native_chronology_same_and_complete'] and d['all_source_fields_and_SYN_xdpp_point25_unchanged'];refs.extend([f,p/'CASES'/method/'case.json'])
common=b/'TECH_FULL37_FIVE_WEEKS_RE50_20261115_01/run_common.jl';assert sha(common)=='40eb3f9d55289f031ba2f6ed965b9bb4beee5a5b7dda408cd4b8390cab435d9b';refs.append(common)
x=rd(r/'02_COMPLETE_ALGEBRAIC_ROWS.json');neutral=rd(q/'actual_parent_G1_byte_baseline.json');assert neutral['raw_sha256']=='c03dfc3cd78d68e0aeb8fb6875a3875e71db5d2c2efd8d680ba1904f95a79cfe'
margins=[]
for f in sorted((r/'02_final_rows').glob('*G1*')):
 z=rd(f);path=Path(z['folder'])/'g1_all_bus_hours.csv'
 with path.open() as h:rows=list(csv.DictReader(h))
 assert len(rows)==6216 and len({(a['snapshot'],a['region']) for a in rows})==6216
 diff=abs(z['margins']['G1']['min']-min(float(a['slack_pu']) for a in rows));assert diff<1e-10;refs.append(path);margins.append([z['row_id'],len(rows),diff])
o=dict(reviewer='/root/qa_r',canonical_nonstrength_case_digest=neut,owner_builder_sha256=sha(common),scope='Actual parent, G2 and G3 archived case inputs coincide after masking strength-family selector metadata. BASE and G1 reuse parent c03dfc3 unchanged. The archived original G3 algebra is used as a countercheck for shared physical rows after semantic variable reindexing, exclusion of every G3-specific row/bound, and explicit quota substitution. This does not assert existence of per-run native coefficient dumps for 12 old BASE/G1 jobs. Independent per-case physical equation, source and cost replays plus separately archived solver outputs anchor acceptance for each.',covered_g1_archived_margins=margins,G2_own_archived_model_profiles=['ba7550c3208ea14f1190b7c2a5b2b5751c39d8ef926031b22acf450eb246fed7',sha(b/'TECH_FULL37_KW08_RE70_SEQUENTIAL_CONDITIONED_20261120_01/03_G2_MILP/G2/integer/profile.json')],algebraic_dump_G3_own_sha256='dfe21bd9f7ad4e771689d58c01711a7ab14be70bf15c5c97c9f5cc171f0a96fd',replay_sha256=sha(Path(__file__)),source_sha256={str(f):sha(f) for f in refs},core_receipt_sha256=sha(r/'02_INDEPENDENT_ACCEPTANCE.json'))
dest=r/'02_COMMON_ROW_IDENTITY_SCOPE.json';dest.write_text(json.dumps(o,indent=2)+'\n');print(sha(dest),neut)

