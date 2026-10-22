"""Read back all report and archive hashes without trusting result flags."""
from pathlib import Path
import hashlib,json,zipfile
r=Path(__file__).parent
sha=lambda b:hashlib.sha256(b).hexdigest()
for n,e in json.loads((r/'package_sha256.json').read_text()).items():
    b=(r/n).read_bytes();assert len(b)==e['bytes'] and sha(b)==e['sha256'],n
m=json.loads((r/'reproduction_manifest.json').read_text());archive=r/m['archive']['path']
assert sha(archive.read_bytes())==m['archive']['sha256']
with zipfile.ZipFile(archive) as z:
    assert len(z.namelist())==len(set(z.namelist()))==len(m['entries'])
    for e in m['entries']:
        b=z.read(e['path']);assert len(b)==e['bytes'] and sha(b)==e['sha256'],e['path']
print('All report and',len(m['entries']),'ZIP entry hashes verified')
