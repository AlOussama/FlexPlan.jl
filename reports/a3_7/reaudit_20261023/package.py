"""Package fresh evidence, preserving external originals and recording redaction."""
from execute import *
import hashlib,re,zipfile
Q=Path(__file__).parent
sha=lambda b:hashlib.sha256(b).hexdigest()
excluded=['validation/prior/','validation/historical/','validation/validation/','submitted_tools/']
records=[]
archive=Q/'reaudit_evidence.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(R.rglob('*')):
        if not p.is_file():continue
        rel=p.relative_to(R).as_posix()
        if any(rel.startswith(prefix) for prefix in excluded):continue
        raw=p.read_bytes();published=raw
        if p.suffix.lower() in ('.log','.txt'):
            # The numeric license identifier is immaterial to scientific reproduction.
            published=re.sub(rb'(LicenseID(?: to value)?\s*)[0-9]+',rb'\1[REDACTED]',raw)
        z.writestr(rel,published)
        records.append(dict(path=rel,bytes=len(published),sha256=sha(published),
            original_sha256=sha(raw),redaction='numeric LicenseID only' if raw!=published else None))
with zipfile.ZipFile(archive) as z:
    assert len(z.namelist())==len(set(z.namelist()))==len(records)
    for e in records:
        b=z.read(e['path']);assert sha(b)==e['sha256'] and len(b)==e['bytes']
manifest=dict(candidate='0ca85adad5b6bcdff5a3ce8df54f5b8ac8eb8568',
    external_originals=str(R),excluded_existing_input_copies=excluded,
    archive=dict(path=archive.name,sha256=sha(archive.read_bytes()),bytes=archive.stat().st_size),entries=records)
(Q/'reproduction_manifest.json').write_bytes(json.dumps(manifest,indent=2).encode('utf-8'))
for name in ['review_summary.json','reviewer_oracle.json','diagnostic_comparisons.json','provenance.json','foreign_before.json']:
    (Q/name).write_bytes((R/name).read_bytes().replace(b'\r\n',b'\n'))
files={p.relative_to(Q).as_posix():dict(bytes=p.stat().st_size,sha256=sha(p.read_bytes()))
       for p in Q.rglob('*') if p.is_file() and p.name not in ('package_sha256.json','publication_receipt.json')
       and '__pycache__' not in p.parts}
(Q/'package_sha256.json').write_bytes(json.dumps(files,indent=2).encode('utf-8'))
print('Verified',len(records),'fresh ZIP entries;',archive.stat().st_size,'bytes')
