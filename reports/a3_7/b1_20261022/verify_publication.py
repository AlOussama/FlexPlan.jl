import hashlib,json,pathlib,zipfile
r=pathlib.Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
m=json.loads((r/'reproduction_manifest.json').read_text())
for n,v in json.loads((r/'package_sha256.json').read_text()).items():
    b=(r/n).read_bytes();assert len(b)==v['bytes'] and sha(b)==v['sha256'],n
a=r/m['archive']['path'];assert sha(a.read_bytes())==m['archive']['sha256']
with zipfile.ZipFile(a) as z:
    assert len(z.namelist())==len(set(z.namelist()))==len(m['entries'])
    for e in m['entries']:
        b=z.read(e['path']);assert len(b)==e['bytes'] and sha(b)==e['sha256'],e['path']
print('PASS: package hashes and',len(m['entries']),'complete ZIP entry hashes')
