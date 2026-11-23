"""Verify the archived inputs to the KW8 publication replay without rebuilding a model."""

import argparse
import hashlib
import json
from pathlib import Path


def verify(input_root, entries):
    root = input_root.resolve(strict=True)
    failures = []
    for entry in entries:
        name = entry["relative_path"]
        path = (root / name).resolve()
        if Path(name).is_absolute() or not path.is_relative_to(root):
            raise ValueError(f"Expected an archive-relative path: {name}")
        if not path.is_file():
            failures.append({"path": name, "reason": "missing"})
            continue
        with path.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != entry["sha256"]:
            failures.append({"path": name, "reason": "digest differs", "actual": actual})
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    entries = json.loads(args.manifest.read_bytes())["archive_objects"]
    if not entries or len({e["relative_path"] for e in entries}) != len(entries):
        parser.error("Expected distinct objects in a nonempty archive manifest")
    failures = verify(args.input_root, entries)
    print(json.dumps({"objects": len(entries), "failures": failures}, ensure_ascii=False))
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
