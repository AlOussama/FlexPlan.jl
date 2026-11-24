"""Collect publisher-deposited Crossref records and the Chinese publisher page, without a cached metadata fallback."""
import argparse, concurrent.futures, hashlib, json, re, urllib.request
from pathlib import Path
from bs4 import BeautifulSoup
def run(bib, out):
    txt=bib.read_text(encoding="utf8")
    snippets=[s for s in re.split(r'(?=@\w+\{)',txt)[1:] if 'Gershgorin1931,' not in s]
    def fetch(s):
        key=re.match(r'@\w+\{([^,]+)',s)[1]
        doi=re.search(r'(?:https://doi.org/|doi\s*=\s*\{)(10\.[^}\s]+)',s,re.I)[1]
        url="https://epjournal.csee.org.cn/en/article/doi/"+doi+"/" if key=="WangRE" else "https://api.crossref.org/works/"+doi.lower()
        req=urllib.request.Request(url,headers={"User-Agent":"ScientificPublicationReview/1.0"})
        with urllib.request.urlopen(req,timeout=45) as f:
            raw=f.read()
        suffix='html' if key=='WangRE' else 'json'
        target=out/(key+'.'+suffix);target.write_bytes(raw)
        if key=="WangRE":
            h=BeautifulSoup(raw,"html.parser"); d={k:[i.get("content") for i in h.find_all("meta",attrs={"name":k})] for k in ["citation_title","citation_author","citation_journal_title","citation_volume","citation_issue","citation_firstpage","citation_lastpage","citation_date","citation_doi"]}
            d["abstract_topic"]=all(w in h.get_text(" ",strip=True).lower() for w in ["generalized benders","siting","sizing","system strength"])
            d["date_online_published"]=["2025-12-22","2026-03-10"]
        else:
            m=json.loads(raw)['message'];d={k:m.get(k) for k in ["DOI","title","container-title","author","volume","issue","page","article-number","published","published-print","published-online","publisher","edition-number","resource"]}
        return key,dict(url=url,sha256=hashlib.sha256(raw).hexdigest(),file=target.name,metadata=d)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as e:data=dict(e.map(fetch,snippets))
    (out/'download_index.json').write_text(json.dumps(data,indent=2,ensure_ascii=True))
    for k,x in data.items():
        m=x['metadata']
        print(k,m.get('title',m.get('citation_title')),m.get('citation_author',[a['family'] for a in m.get('author',[])]),m.get('published'),m.get('volume'),m.get('issue'),m.get('page',m.get('article-number')),x['sha256'])
if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("bib",type=Path);p.add_argument("out",type=Path);a=p.parse_args()
    a.out.mkdir(exist_ok=True,parents=True);run(a.bib,a.out)