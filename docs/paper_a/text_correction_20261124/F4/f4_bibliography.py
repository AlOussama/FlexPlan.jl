"""Compare final emitted BibTeX fields with primary publisher/DOI deposits read in this review."""
import html,re,json,hashlib,unicodedata
from bs4 import BeautifulSoup
from pathlib import Path
def norm(x):return re.sub(r'[^a-z0-9]+','',unicodedata.normalize('NFKD',html.unescape(html.unescape(x))).lower())
def fields(s):
    pat=r'(?:^|,\s*)(author|title|year|journal|booktitle|pages|publisher|number|issue|volume|doi|eid)\s*=\s*(\{\{[^}]+\}\}|\{[^}]+\})'
    return {k:v.strip('{}') for k,v in re.findall(pat,s,re.M|re.I)}
def audit(bib,tex,db):
    src=json.loads((db/'download_index.json').read_bytes());out={}
    cite={i for grp in re.findall(r'\\cite\{([^}]+)\}',tex) for i in grp.split(',')}
    for s0 in re.split(r'(?=@\w+\{)',bib)[1:]:
        key=re.search(r'@\w+\{(\w+)',s0)[1];b=fields(s0)
        if key=='Gershgorin1931':
            b['journal']=re.search(r'journal\s*=\s*\{(.*?)\},\s*\n',s0,re.S)[1]
            hist=db/'Gerschgorin_original_source.json';v=json.loads(hist.read_bytes())
            assert norm(b['title'])==norm(v['title']) and norm(b['author'])==norm('Gerschgorin, S.') and b['pages']=='749--754' and b.get('issue',b.get('number'))=='6' and 'Issue 6' in s0 and b['year']=='1931'
            assert norm(b['journal'])==norm(v['venue']) and 'https://www.mathnet.ru/eng/im5235' in s0 and ('751' in s0)
            assert ('Gershgorin' in tex or 'Gerschgorin' in tex) and 'r_i(Mr)_i' in tex
            out[key]=dict(source=v['archive'],facsimile=v['facsimile'],readback_sha256=hashlib.sha256(hist.read_bytes()).hexdigest(),theorem='Satz II, p. 751',metadata='VERIFIED')
            continue
        raw=(db/src[key]['file']).read_bytes();h=hashlib.sha256(raw).hexdigest();assert h==src[key]['sha256'];d=src[key]['metadata']
        if key=='WangRE':
            soup=BeautifulSoup(raw,'html.parser');t=soup.get_text(' ',strip=True);ws=' '.join(t.split()).casefold()
            want={'title':d['citation_title'][0],'doi':d['citation_doi'][0],'journal':'Electric Power Automation Equipment','year':'2026','volume':d['citation_volume'][0],'number':d['citation_issue'][0],'pages':d['citation_firstpage'][0]+'--'+d['citation_lastpage'][0],'author':' and '.join(d['citation_author'])}
            assert all(i in ws for i in ['electric power automation equipment','generalized benders decomposition','siting','sizing'])
            assert re.search(r'(22 December 2025|2025-12-22)',t,re.I) and re.search(r'(10 March 2026|2026-03-10)',t,re.I)
        else:
            d=json.loads(raw)['message']
            want={'title':d['title'][0],'author':' and '.join(a['family']+', '+a['given'] for a in d['author']),'year':str(d['published']['date-parts'][0][0]),'publisher':d['publisher'],'doi':d['DOI']}
            if d.get('container-title'):want['booktitle' if '@inproceedings' in s0 else 'journal']=d['container-title'][0]
            if d.get('volume'):want['volume']=d['volume']
            if d.get('issue'):want['number']=d['issue']
            if d.get('article-number'):want['eid']=d['article-number'];assert 'Article '+d['article-number'] in s0
            elif d.get('page'):want['pages']=d['page']
        for k,v in want.items():assert norm(b[k])==norm(v),(key,k,b[k],v)
        out[key]=dict(fields=sorted(want),origin=src[key]['url'],primary_response_sha256=h,metadata='VERIFIED')
    assert set(out)==cite and set(src)==(cite-{"Gershgorin1931"})
    return out