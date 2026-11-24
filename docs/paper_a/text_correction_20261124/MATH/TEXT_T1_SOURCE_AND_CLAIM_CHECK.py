"""Build the T1 engineering claim index from the actual historical lines and F1/code bindings."""
import csv, hashlib, json, re, subprocess
from pathlib import Path
gold=Path('E:/ResearchResults/FlexPlan_UC_GSCR/PAPER_A_BUNDLE_20261123_GOLD01')
out=Path(__file__).resolve().parent
paper=out.parent/'PAPER'
basepin='7d568b6ce3b821bba05812b61ca8ccc5240aacec'
consumer='dbecc1f2d26db134ac7a817c6ce2b5d0ba05882a'
def h(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
def csvrows(f):
    with f.open(encoding='utf-8-sig',newline='') as source:
        return list(csv.DictReader(source))
def write(name,rows):
    with (out/name).open('w',encoding='utf8',newline='') as f:
        w=csv.DictWriter(f,rows[0].keys()); w.writeheader();w.writerows(rows)
review='01_FORMULATION_AND_CODE_DIFFERENTIAL_REVIEW.md'
physical='01_PHYSICAL_DOMAIN_AND_EVENT_REPLAY.json'
cost='02_OBJECTIVE_AND_SOLVER_BOUNDS.csv'
results='02_FINAL_WEEK168_RESULT_MATRIX.csv'
methods='03_METHOD_STATUS_MATRIX.csv'
native='03_GATED_SOLVER_NEGATIVES.json'
oracle='TEXT_T1_MATH_ORACLES.json'
t2='TEXT_T2_MATH_ORACLE_RESULTS.json'
fcov='01_FORMULATION_COVERAGE.csv'
events='01_INDEPENDENT_EVENT_CENSUS.json'
m2src='03_QUALIFIED_REAL_METHOD_RESULTS.csv'
def refs(names):
    return ';'.join(h((out if n.startswith('TEXT') else gold)/n) for n in names.split(';'))
forms=csvrows(gold/fcov)
# Re-open the 23 family source files at the actual generating contract revision and compare
# the byte-digest on every locator. These are independent read-only Git commands.
pinned={}
checks=[]
for f in forms:
    row=[]
    for loc in f['current_code_locator_and_file_sha256'].split(';'):
        m=re.fullmatch(r'(.+):(\d+)@([a-f0-9]{64})',loc.strip())
        if not m: raise ValueError(loc)
        path,lineno,sha=m.groups()
        if path not in pinned:
            pinned[path]=subprocess.check_output(['git','-C','D:/Projekte/Code/FlexPlan_UC_GSCR','show',consumer+':'+path])
        data=pinned[path]; d=hashlib.sha256(data).hexdigest()
        assert sha==d and int(lineno)<=len(data.splitlines()),(loc,d)
        row.append({'locator':loc,'original_code_line':data.decode('utf8').splitlines()[int(lineno)-1]})
    checks.append({'family':f['family'],'locators':row,'case_contract':f['case_scope_and_check'],'source_pin':consumer})
(out/'TEXT_T1_PINNED_MODEL_AND_CASE.json').write_text(json.dumps(checks,indent=2)+'\n',encoding='utf8')
legacy={r['claim_id']:r for r in csvrows(gold/'04_PAPER_CLAIM_TO_EVIDENCE.csv')}
# Each field matches selected sentences/displays within its source line; DATA and reference
# verification are explicitly owned by the corresponding independent audiences.
mapping={
'C01':('C4 primary bibliography','Original publisher record per citation; factual primary-source review assigned DATA/PAPER/F4.','04_references.bib','SOURCE_REVIEW_SEPARATE'),
'C02':('C2 converter exposure and renewable quota','Nonnegative input participation, per-unit / 100 MVA, local availability and actual hourly dispatch, matched weekly demand.',fcov+';'+physical,'VERIFIED_MODEL_AND_CASE'),
'C03':('C2 event and investment costs','EUR2025. Annual CAPEX once; 8760/168 times raw weekly OPEX including per-MW event price times block MW once. Physical clock stays hourly.',fcov+';'+cost,'VERIFIED_MODEL_AND_CASE'),
'C04':('C2 regional operations, events and chronology','Hourly DCP KCL with net-export sign, restricted AC topology, DC links, P/E, chronological storage, eligible thermal event set.',fcov+';'+physical,'VERIFIED_MODEL_AND_CASE'),
'C05':('C1/C2 AC physics and sources','Reciprocal AC pi-stamps, full series admittance, physical charging, registered source/base/ordering. Seven islands, 37 retained, 52 distinct edges, no passive elimination.',fcov+';'+physical,'VERIFIED_MODEL_AND_CASE'),
'C06':('C1 row certificates and inverse screen','Symmetric Z matrix, fixed r>0. For M0 matched symmetric SPD B with nonnegative inverse, nonnegative p, alpha>0.',review+';'+oracle,'PROVED'),
'C07':('C1 G3 edge and generalized Schur proofs','Full edge support, nonnegative directed endpoint budgets and node remainder; singular PSD block requires range guard. PSD vs PD explicitly differentiated.',review+';'+oracle,'PROVED'),
'C08':('C1 M1, M2 and ratio proxies','M1 common offdiagonals, nonnegative enforced diagonal delta, SPD Z floor; M2 fixed nonnegative unit diagonal W; interval membership with ell>0, nonnegative exposures.',review+';'+oracle+';'+m2src,'PROVED'),
'C09':('C3 paired numerical bounds','Common case/cost, native numerical LB and reconstructed upper feasible point, outward differences. Independent numeric field audit by DATA/F4.',cost,'NUMERIC_DATA_ROLE'),
'C10':('C3 interval order vs incumbent costs','Different model optima within overlapping intervals cannot be ranked solely by the two incumbent costs.',cost,'VERIFIED_BOUND_INTERPRETATION'),
'C11':('C3 portfolio units and scope','Original accepted integer portfolio; additional nameplate distinct from total and from actual energy. Numeric fields assigned DATA/F4.',results,'NUMERIC_DATA_ROLE'),
'C12':('C1/C3 diagnostics and domains','Each defined hourly test is method-specific and checked at original primal; M0 outside SPD domain undefined, G0 is a matrix test.',physical+';'+results,'VERIFIED_DOMAIN_AND_CASE'),
'C13':('C2 simultaneous aggregate events','Eliminating min(u,v) preserves differences and integer counts; nonnegative reductions relax all relevant event upper bounds. Positive event costs decrease.',events+';'+review,'PROVED_AND_OBSERVED'),
'C14':('C1/C3 direct native statuses','Backend status cannot bypass original-coordinate tests; no feasible optimum or infeasibility proof inferred from negative candidates.',native,'VERIFIED_METHOD_SCOPE'),
'C15':('C1/C3 witness and M2 relaxation','Matched constraints/cost. Transferred feasible point supplies G0/G3 numerical UB; M2 relaxation LB scoped to registered W; no M2 integer incumbent.',m2src,'VERIFIED_METHOD_SCOPE'),
'C16':('C1/C4 scope of hypotheses','Inclusion permits weak optimum order for common objectives. Non-nesting supplies no general ordering. H3/H4 require controlled experiments.',review+';'+oracle,'VERIFIED_LOGICAL_SCOPE'),
'C17':('C2/C4 physics and generalization','Weekly active-power DCP and frozen-E proxy; no evidence of calibrated fault, AC, transient, full-year or contingency performance.',fcov+';'+physical,'VERIFIED_SCOPE'),
'C18':('C3 original coordinates and provenance','Archived point identities, replay/case profile; supplement/public files do not grant private network access.',results+';02_RE50_LP_COORDINATE_PROOF.json','PROVENANCE_DATA_ROLE')}
# Old claims are attached to specific lines; overlapping dense paragraphs can have several
# families. Subclassify the statement by distinctive terminology rather than assigning by section alone.
def classify(fn,n,s):
    low=s.lower()
    if fn=='04_PAPER_A.tex':
        if n==15:return 'C11'
        if n==21:
            if 'conic solve' in low:return 'C14'
            if 'annualize' in low:return 'C03'
            return 'C06' if 'matrix' in low or 'edge-conic' in low else 'C16'
        if n==25:return 'C16'
        if n==27:return 'C01' if 'cite' in s or 'existing work' in low else 'C16'
        if n==30:return 'C05' if 'strength' in low or 'island' in low else 'C04'
        if 32<=n<=37:return 'C13' if 'simultaneous' in low else 'C04'
        if 39<=n<=53:return 'C02'
        if 55<=n<=61:return 'C03'
        if n==64:return 'C05'
        if 65<=n<=70:return 'C07'
        if 72<=n<=78:return 'C06'
        if 80<=n<=91:return 'C07'
        if n==94:return 'C06'
        if n==96:return 'C08'
        if n==99:return 'C12' if 'diagnostic' in low else 'C09'
        if n==104 or n==109:return 'C16'
        if n==106:return 'C17'
        if n==113:return 'C18'
    if fn=='04_results.tex':
        if 'event' in low or 'commitment' in low or 'up/down' in low:return 'C13'
        if 'overlap' in low or '369.0' in s:return 'C10'
        if 43<=n<=50:return 'C11'
        if n>50:return 'C12'
        return 'C09'
    if fn=='04_result_abstract.tex':return 'C12' if 'hour' in low else 'C09'
    if fn=='04_result_conclusion.tex':return 'C10'
    if fn=='04_qualified_extensions.tex':return 'C15'
    if fn=='04_numerical_limits.tex':return 'C15' if 'witness' in low else 'C14'
    if fn.endswith('.md'):
        if 'event' in low or 'startup' in low:return 'C13'
        if 'inverse' in low or 'g1' in low or 'z-matrix' in low:return 'C06'
        if 'gfm' in low or 'ac edges' in low:return 'C05'
        if 'quota' in low or 'availability' in low:return 'C02'
        if 'bound' in low:return 'C09'
        if 'physical' in low:return 'C17'
        return 'C18'
    raise ValueError((fn,n,s))
issue=[
('MATH-01','P0','04_PAPER_A.tex',94,'At $p=(1/2,4/3)$','The old second example inherited B=[[2,-1],[-1,2]], which is internally correct. Binding its p to the normalized GOLD matrix instead gives det=-5/12 and Zp=(14/9,19/9). No explicit second B was printed.','Explicit normalized B=[[1,-1/2],[-1/2,1]], p=(1/4,2/3), det=0, eig 0,13/12, Zp=(7/9,19/18). Retain old scaled example as a correct historical control.','PRINTED_normalized_M / NEGATIVE_legacy_numerators_with_normalized_matrix',110),
('MATH-02','P1','04_PAPER_A.tex',70,'More generally minimize','Nonempty positive-denominator domain alone does not ensure a finite lower extremum.','If Bzz is PSD and the coupling belongs to its range, minimize the corresponding reduced quotient. Otherwise the infimum is minus infinity. For S=0 the domain is empty.','NEGATIVE_positive_denominator_not_finite_infimum',72),
('MATH-03','P1','04_PAPER_A.tex',78,'For an unanchored Laplacian','L was also defined using full Y including line charging; charging generally shifts row sums.','Only the series Laplacian has zero row sums. Preserve line charging in B0*1 and any independently evidenced anchoring.','PHYSICS_series_vs_pi_row_sums',85),
('MATH-04','P1','04_PAPER_A.tex',32,'In the integer model','Transition/window equations read as applying to all devices; event variables exist only for thermal eligibility. Incomplete hourly connection and initial-count scope.','n_on<=a_conn*n_inst, event equations only on thermals with starts/stops, initial n0 supplied by case, truncated windows and aggregate overlaps retained.','109 event-eligible thermals / physical original rows / independent census',34),
('MATH-05','P1','04_PAPER_A.tex',94,'Where $B$ is invertible','The broader algebraic G1=>M0 antecedent and the operational SPD inverse-domain requirement are introduced separately. Positive p and alpha and common coordinates need explicit scope.','State complete operational SPD symmetric Z / inverse-positive / p>=0 / alpha>0 / common ordering-base domain for G1 => M0 => G0.','PRINTED_M0_not_G1 / PRINTED_G0_not_M0 / negative domain in physical hourly replay',101),
('MATH-06','P1','04_PAPER_A.tex',99,'Diagnostic hours count','Any regional row does not describe the global G0 PSD eigenvalue diagnostic.','G1/G2/M0 use tested regional rows; G0 uses the minimum eigenvalue of the full hourly M. Track undefined M0 separately.','Compare physical replay and displayed eigenvalue test',118),
('MATH-07','P2','04_PAPER_A.tex',21,'positivity of a symmetric','Positivity risks treating the singular PSD boundary as excluded.','Positive semidefiniteness of the thresholded symmetric matrix includes the demonstrated singular boundary.','PRINTED_spectrum_and_determinant',21),
('MATH-08','P2','04_PAPER_A.tex',109,'preserve tractability','LP strength rows preserve linear form but leave a MILP in the integer case. Abstract matrix non-nesting alone need not imply a strict empirical optimum ordering.','Row certificates add linear constraints and are generally nonnested; case-portfolio ordering needs case evidence.','PRINTED_G1_G2_nonnesting',128),
('MATH-09','P2','04_PAPER_A.tex',64,'uses $S_b=100$','Scope of 25 MVA block source example should be explicit to avoid treating every synchronous source as identically rated.','Use the 25 MVA GFM battery rating only for the indicated block and equipment-specific rated values for synchronous units.','PHYSICS_rating_and_pu plus original block-coefficient replay',66),
('MATH-10','P1','04_PAPER_A.tex',96,'A registered nontrivial matrix','Fixed-ex-ante reference and membership/lift requirements were only implicit in the proxy narrative.','M2 W fixed before its solve using earlier G2 integer h1. Direct P/ell only within chosen interval; fractional selection needs its own proof, no physical fault calibration or uniform M0 guarantee.','PROOF_M2_and_identity / NEGATIVE_free_ratio_RHS',115),
('MATH-11','P1','04_qualified_extensions.tex',1,'bound separation for this proxy','Numerical separation compares two different quantities; distinguish M2 model LB and a cross-model feasible witness UB with same case and cost.','Report a cross-model paired numerical lower separation under matched scope and only for that reference; no exact optimality gap, M2 integer incumbent, or global physical penalty.','BOUNDS_conditional_subtraction plus MATH_R_M2_TRANSFER_FINAL.json',1)]
rows=[]; used=set()
for fn in ['04_PAPER_A.tex','04_result_abstract.tex','04_results.tex','04_result_conclusion.tex','04_numerical_limits.tex','04_qualified_extensions.tex','04_REPRODUCIBILITY_AND_LIMITATIONS.md']:
    p=gold/fn
    for n,raw in enumerate(p.read_text(encoding='utf-8-sig').splitlines(),1):
        line=raw.strip()
        if not line or (fn=='04_PAPER_A.tex' and n<15): continue
        if line.startswith(('#','|','~~~','\x60\x60\x60','python ','tectonic ')): continue
        if re.match(r'^\\(?:author|date|documentclass|maketitle|section|subsection|appendix|label|bibliograph|input|end|bottomrule)', line): continue
        if re.match(r'^\\begin',line) and r'\caption' not in line: continue
        if line in (r'\[',r'\]'): continue
        if r'\caption{' in line: line=line.split(r'\caption{')[1].split(r'}\label')[0]
        if not line.strip('.'):continue
        for fragment in re.split(r'(?<=[.!?])\s+(?=[A-Z$\\])',line):
            c=classify(fn,n,fragment); used.add(c)
            scope,assump,rr,truth=mapping[c]
            findings=[entry for entry in issue if entry[2]==fn and entry[3]==n and entry[4].lower() in fragment.lower()]
            rows.append(dict(file=fn,line=n,claim_id=f'MATH-C{len(rows)+1:03}',math_or_numeric_scope=scope,source=rr,priority=';'.join(f[1] for f in findings) or 'REVIEW',verbatim_claim_or_expression=fragment,assumptions=assump,evidence_file_SHA=refs(rr),truth_status='BASELINE_CORRECTION_OR_CLARIFICATION' if findings else truth,severity=';'.join(f[1] for f in findings) or 'NONE',correction_needed=';'.join(f[0] for f in findings) or 'NONE',reviewer_id='/root/math_r',legacy_claim_id=c,baseline_sha256=h(p)))
assert set(legacy)==used, set(legacy)-used
write('TEXT_T0_MATH_CLAIM_INVENTORY.csv',rows)
findings=[]
for key,prio,file,line,claim,cause,correct,test,newline in issue:
    if key in ('MATH-03','MATH-04','MATH-06','MATH-09'):src=physical
    elif key=='MATH-11':src=m2src
    else:src=oracle
    active=paper/file
    findings.append(dict(finding_id=key,priority=prio,source_file=file,line=line,claim=claim,root_cause=cause,correct_scientific_statement=correct,exact_evidence_sha=refs(src),affected_sources=file,patch_scope='MATHEMATICAL_CORRECTION' if key in ('MATH-01','MATH-02') else 'CLAIM_SCOPE_CORRECTION',owner='PAPER-W',independent_test=test,status='CORRECTED_AT_OBSERVED_CANDIDATE' if key!='MATH-11' or 'matched' in active.read_text().lower() or 'cross-model comparison' in active.read_text().lower() else 'AWAITING_EXTENSION_EDIT',observed_candidate_sha256=h(active),candidate_line=newline,reviewer_id='/root/math_r'))
write('TEXT_T1_MATH_FINDINGS.csv',findings)
print('claims',len(rows),'legacy',len(used),'findings',len(findings),'families',len(checks),'source files',len(pinned))
for n in ('TEXT_T0_MATH_CLAIM_INVENTORY.csv','TEXT_T1_MATH_FINDINGS.csv','TEXT_T1_PINNED_MODEL_AND_CASE.json'):
    print(n,h(out/n))

