"""Independent F4 audit of a caller-specified Git object. No repository checkout or write."""
from pathlib import Path
import argparse,csv,hashlib,html,json,os,re,shutil,subprocess,sys
from decimal import Decimal
from f4_numbers import audit,artists,rd,H,jf
from f4_math import verify
from f4_bibliography import audit as bib_audit
HERE=Path(__file__).resolve().parent
def dump(p,obj):p.write_text(json.dumps(obj,indent=2,ensure_ascii=True,default=str)+'\n',encoding='utf8')
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args])
def export(repo,pin,prefix,dest):
    dest.mkdir(parents=True,exist_ok=False);inv={}
    for line in git(repo,'ls-tree','-r','-z',pin,'--',prefix).split(b'\0'):
        if not line:continue
        meta,path=line.decode().split('\t',1);mode,typ,blob=meta.split();assert typ=='blob'
        name=Path(path).relative_to(prefix).as_posix();data=git(repo,'cat-file','blob',blob)
        assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==blob
        target=dest/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
        inv[name]={'blob':blob,'sha256':H(target),'bytes':len(data),'mode':mode}
    assert inv
    return inv
def run(a):
    src=a.out/'source';build=a.out/'build';a.out.mkdir(exist_ok=True,parents=True);inventory=export(a.paper_repo,a.commit,a.paper_path,src)
    base=a.out/'baseline';orig=export(a.paper_repo,a.baseline,a.paper_path,base)
    assert not set(orig)-set(inventory)
    log=[];env=dict(os.environ);env.update(MPLCONFIGDIR=str(a.out/'mpl'),TECTONIC_CACHE_DIR=str(a.out/'cache'),FONTCONFIG_FILE=str(a.out/'fonts.conf'))
    (a.out/'fonts.conf').write_text('<fontconfig><dir>C:/Windows/Fonts</dir><cachedir>'+str((a.out/'fontcache').as_posix())+'</cachedir></fontconfig>')
    if not (a.out/'cache').exists():shutil.copytree(a.tex_cache,a.out/'cache')
    def cmd(argv,cwd,name):
        cp=subprocess.run([str(x) for x in argv],cwd=cwd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        f=a.out/(name+'.log');f.write_bytes(cp.stdout)
        log.append({'command':list(map(str,argv)),'cwd':str(cwd),'exit':cp.returncode,'log_sha256':H(f),'log_path':f.name})
        if cp.returncode:raise RuntimeError((argv,cp.returncode,cp.stdout[-2400:]))
        return cp.stdout.decode('utf8',errors='replace')
    paper=(src/'04_PAPER_A.tex').read_text(encoding='utf8');alltex={};figures=set();refs=[];labels=[];todo=['04_PAPER_A.tex']
    while todo:
        n=todo.pop()
        if n in alltex:continue
        txt=(src/n).read_text(encoding='utf8');alltex[n]=txt
        todo.extend(re.findall(r'\\input\{([^}]+)\}',txt));figures.update(re.findall(r'\\includegraphics(?:\[[^]]*\])?\{([^}]+)\}',txt))
        labels+=re.findall(r'\\label\{([^}]+)\}',txt);refs+=re.findall(r'\\(?:eqref|ref)\{([^}]+)\}',txt)
    assert set(alltex)=={n for n in inventory if n.endswith('.tex')} and all(n in inventory for n in figures)
    assert len(set(labels))==len(labels) and set(refs)<=set(labels)
    evidence={}
    def bind(path,sha):
        path=Path(path)
        if str(path) not in evidence:evidence[str(path)]=H(path)
        assert evidence[str(path)]==sha,(path,sha)
    for r in rd(a.gold/'02_FINAL_WEEK168_RESULT_MATRIX.csv'):
        row=a.gold/'02_final_rows'/(r['row_id']+'.json');bind(row,r['original_replay_sha256'])
        f=jf(row)
        for path,sha in f['source_hashes'].items():bind(path,sha)
    for r in rd(src/'04_additional_methods.csv'):
        path=a.gold.parent/'SGOV145_20261121_01'/'QA_R'/r['qa_file']
        if path.is_file():bind(path,r['qa_sha256'])
    corefiles=['00_INPUT_AND_RUNTIME_INTAKE.json','01_FORMULATION_AND_CODE_DIFFERENTIAL_REVIEW.md','01_FORMULATION_COVERAGE.csv','01_OPEN_MATERIAL_FINDINGS.json','01_FRESH_RATIONAL_ORACLE.json','01_INDEPENDENT_EVENT_CENSUS.json','02_FINAL_WEEK168_RESULT_MATRIX.csv','02_OBJECTIVE_AND_SOLVER_BOUNDS.csv','02_ORIGINAL_PRIMAL_REPLAY.json','02_INDEPENDENT_ACCEPTANCE.json','03_METHOD_STATUS_MATRIX.csv','03_SYNTHETIC_NATIVE_TESTS.json','03_QUALIFIED_REAL_METHOD_RESULTS.csv','03_GATED_SOLVER_NEGATIVES.json','05_publication_audit.py','05_ORIGINAL_PUBLICATION_SAMPLES.json']
    for n in corefiles:
        bind(a.gold/n,hashlib.sha256(git(a.consumer_repo,'show',a.technical+':docs/paper_a/gold_week168/'+n)).hexdigest())
    assert jf(a.gold/'02_INDEPENDENT_ACCEPTANCE.json')['gate']=='GATE2_PASS_VARIANT_A'
    legacy=rd(base/'04_PAPER_CLAIM_TO_EVIDENCE.csv');claims=rd(src/'04_PAPER_CLAIM_TO_EVIDENCE.csv')
    assert {r['claim_id'] for r in legacy}<={r['claim_id'] for r in claims} and len({r['claim_id'] for r in claims})==len(claims)
    for x in claims:
        names=x['source_files'].split(';');sums=x['source_sha256_in_same_order'].split(';')
        assert len(names)==len(sums)
        for n,sha in zip(names,sums):
            candidates=[src/n,a.gold/n,a.evidence/'MATH'/n,a.evidence/'ORCH'/n,a.evidence/'WRITER'/n,a.evidence/'PAPER'/n]
            origfile=next((f for f in candidates if f.exists() and H(f)==sha),None)
            assert origfile is not None,(x['claim_id'],n,sha)
            bind(origfile,sha)
    granular=rd(src/'TEXT_T2_CLAIM_TO_EVIDENCE.csv')
    original_ids={r['claim_id'] for r in rd(a.evidence/'ORCH/TEXT_T0_CLAIM_INVENTORY.csv')}
    mapped=[];locs=[]
    for x in granular:
        n=x['file'];filename=src/n;assert H(filename)==x['final_source_sha256']
        mapped.extend(filter(None,x['T0_related'].split(';')))
        if n.endswith(('.md','.tex','.bib')):
            lines=filename.read_text(encoding='utf8').splitlines();offset=int(x['line'])-1
            stripped=' '.join(l.strip() for l in lines[offset:offset+max(1,len(x['verbatim_claim_or_expression'].splitlines()))])
            assert ' '.join(x['verbatim_claim_or_expression'].splitlines()) in stripped,(x['claim_id'],offset)
        if n.endswith('.csv'):
            row=rd(filename)[int(x['line'])-2];assert x['verbatim_claim_or_expression']==' | '.join(f'{k}={v}' for k,v in row.items())
        for e,sha in zip(x['evidence_file'].split(';'),x['evidence_file_SHA'].split(';'),strict=True):
            candidate=next((d/e for d in [src,a.gold,a.evidence/'MATH',a.evidence/'ORCH',a.evidence/'WRITER'] if (d/e).is_file() and H(d/e)==sha),None)
            assert candidate is not None,(x['claim_id'],e,sha)
            bind(candidate,sha)
        locs.append((x['claim_id'],n,x['line']))
    assert len(mapped)==len(original_ids) and set(mapped)==original_ids
    legacy_source={r['claim_id'] for r in legacy}
    mapped_legacy={i for x in granular for i in x['legacy_claim_ids'].split(';') if i}
    assert legacy_source<=mapped_legacy
    gran_summary=dict(final_rows=len(granular),baseline_reconciled_ids=len(mapped),legacy_claim_ids=sorted(legacy_source),final_sha_and_record_or_line_checked=locs,figure_exception="Three final vector figures bound by content hashes; figure text placeholders describe the object. All data series, axis semantics, masking, regenerated PDF and final rendered pages independently checked.",source_evidence_hashes_checked=sum(len(x['evidence_file'].split(';')) for x in granular))
    dump(a.out/'granular_ledger_checks.json',gran_summary)
    from f4_findings import run as close_findings
    closure=close_findings(src,a.gold,a.evidence,a.out,a.consumer_repo,a.technical_fix)
    dump(a.out/'findings_1_to_1.json',closure)
    bad=a.out/'corrupt_publication_control';bad.mkdir()
    for name in ['04_reviewed_points.csv','04_reviewed_bounds.csv','04_additional_methods.csv']:shutil.copyfile(src/name,bad/name)
    bf=bad/'04_reviewed_points.csv';before=H(bf);bf.write_bytes(bf.read_bytes().replace(b'12.0.3',b'12.0.4',1));assert H(bf)!=before
    try:audit(bad,a.gold)
    except AssertionError:pass
    else:raise AssertionError('mutated public solver-version cell accepted')
    falsely_claimed_pdf=orig['04_PAPER_A.pdf']['sha256']
    try:bind(src/'04_PAPER_A.pdf',falsely_claimed_pdf)
    except AssertionError:pass
    else:raise AssertionError('old baseline digest accepted for final PDF')
    dump(a.out/'publication_negative_controls.json',{'changed_F2_solver_version':'rejected','observed_mutated_SHA':H(bf),'expected_F2_SHA':before,'stale_publication_pdf_SHA':'rejected','old_pdf_sha256':falsely_claimed_pdf,'actual_pdf':H(src/'04_PAPER_A.pdf'),'unknown_G3_row':closure['D07']})
    frozen=jf(src/'TEXT_T2_FREEZE_CANDIDATE.json')
    if 'files' in frozen:
        for n,entry in frozen['files'].items():
            digest=entry['sha256'] if isinstance(entry,dict) else entry
            assert inventory[n]['sha256']==digest and inventory[n]['blob']==entry['blob'] and inventory[n]['bytes']==entry['bytes'],(n,digest)
    math=verify(paper);math['baseline_exact_git_text']=verify((base/'04_PAPER_A.tex').read_text(encoding='utf8'),True)
    mutants={'coordinate_mixed_scale':('p=(1/4,2/3)','p=(1/2,4/3)'),'incorrect_published_eigenvalue':('and $13/12$','and $13/11$'),'wrong_printed_inverse_vector':('Zp=(7/9,19/18)','Zp=(7/9,19/17)'),'wrong_rotated_cone_factor':('q_{ij}/2,q_{ji},M_{ij}','q_{ij}/3,q_{ji},M_{ij}'),'wrong_scaled_row_image':('M_a r=(-1,1)','M_a r=(-1,2)')}
    for name,(before,after) in mutants.items():
        assert before in paper,(name,before);t=paper.replace(before,after)
        try:verify(t)
        except (AssertionError,ValueError):math.setdefault('rejected_text_mutations',[]).append(name)
        else:raise AssertionError(('false mathematical acceptance',name))
    math['reviewer']='/root/qa_r';math['paper_sha256']=H(src/'04_PAPER_A.tex');math['code_sha256']=H(HERE/'f4_math.py');dump(a.out/'TEXT_T3_MATH_VERIFICATION.json',math)
    num=audit(src,a.gold);num['chart_artist_values']=artists(src,a.gold)
    num['bibliography']=bib_audit((src/'04_references.bib').read_text(encoding='utf8'),'\n'.join(alltex.values()),a.doi)
    # Clean room only source programs, their public CSV inputs, the root TeX and bibliography.
    build.mkdir();starting=[n for n in inventory if n in ('04_PAPER_A.tex','04_references.bib','04_build_results.py','04_g3_table.py') or (n.startswith('04_') and n.endswith('.csv'))]
    for n in starting:shutil.copyfile(src/n,build/n)
    cmd([sys.executable,'04_build_results.py'],build,'regenerate')
    generated=(set(alltex)-{'04_PAPER_A.tex'})|figures
    for n in generated:
        assert (build/n).read_bytes()==(src/n).read_bytes(),('generated bytes differ',n)
    txt=cmd([a.tectonic,'--keep-logs','--keep-intermediates','04_PAPER_A.tex'],build,'tectonic')
    assert 'Running BibTeX' in txt and 'Running xdvipdfmx' in txt
    lg=(build/'04_PAPER_A.log').read_text(encoding='utf8');broken=re.findall(r'^.*(?:Warning:|Underfull |Overfull |undefined|missing character|^!).*$',lg,re.M|re.I)
    assert not broken,broken
    bbl=(build/'04_PAPER_A.bbl').read_text(encoding='utf8')
    assert set(re.findall(r'\\bibitem\{([^}]+)\}',bbl))==set(num['bibliography'])
    cmd([a.pdf_python,HERE/'f4_render.py',src/'04_PAPER_A.pdf',build/'04_PAPER_A.pdf',a.out/'render'],build,'render')
    render=jf(a.out/'render/pages.json')
    num.update(regenerated_byte_identical={n:H(build/n) for n in sorted(generated)},render=render,refs=refs,labels=labels,warning_lines=broken)
    dump(a.out/'TEXT_T3_NUMERIC_AND_FIGURE_AUDIT.json',num)
    observed={'stage':'AUTOMATED_CHECKS_PASS__VISUAL_FINDING_CLOSURE_SEPARATE','reviewer':'/root/qa_r','writer':'/root/governance','math':'/root/math_r','argv':[sys.executable,*sys.argv],'commit':a.commit,'parent':git(a.paper_repo,'rev-parse',a.commit+'^').decode().strip(),'baseline':a.baseline,'technical_readonly':a.technical,'paper_path':a.paper_path,'files':inventory,'baseline_files':orig,'evidence':evidence,'script_digests':{n.name:H(n) for n in HERE.glob('f4_*.py')},'code_tree':git(a.paper_repo,'rev-parse',a.commit+':'+a.paper_path).decode().strip(),'linked_inputs':sorted(alltex),'figures':sorted(figures),'legacy_baseline_claim_count':len(legacy),'revised_legacy_register_claim_count':len(claims),'final_granular_crosswalk_row_count':len(granular),'baseline_crosswalk_count':len(mapped),'granular_evidence_hash_links_tested':gran_summary['source_evidence_hashes_checked'],'processes':log,'independent_pdf':render,'root_sources_sha256':{n:H(a.out/n) for n in ['TEXT_T3_MATH_VERIFICATION.json','TEXT_T3_NUMERIC_AND_FIGURE_AUDIT.json']},'doi_response_binding':H(a.doi/'download_index.json')}
    dump(a.out/'observed.json',observed)
    print('Automated F4 audited at',a.commit,'files',len(inventory),'claims',len(claims),'bound evidence',len(evidence),'PDF pages',len(render['pages']))
if __name__=='__main__':
    a=argparse.ArgumentParser()
    for arg in ['paper-repo','consumer-repo','gold','doi','out','evidence','tex-cache','pdf-python','tectonic']:a.add_argument('--'+arg,type=Path,required=True)
    for arg in ['commit','baseline','technical','technical-fix','paper-path']:a.add_argument('--'+arg,required=True)
    run(a.parse_args())