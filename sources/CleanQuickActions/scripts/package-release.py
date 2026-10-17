#!/usr/bin/env python3
"""Export the verified DEB and matching source ZIP."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
version = '1.0.2'
package = root / 'packages' / f'com.brooktrout12.cleanquickactions_{version}_iphoneos-arm64.deb'
report = json.loads((root / 'validation/package-verification.json').read_text())
digest = hashlib.sha256(package.read_bytes()).hexdigest()
assert report['result'] == 'PASS' and report['sha256'] == digest
deb = out / f'CleanQuickActions_{version}_rootless.deb'
shutil.copyfile(package, deb)

sources = []
for path in sorted(root.rglob('*')):
    if not path.is_file():
        continue
    rel = path.relative_to(root)
    if any(part.startswith('.') or part == '__pycache__' for part in rel.parts):
        continue
    if rel.parts[0] == 'packages' or rel.as_posix() in ('validation/test_rules', 'source-manifest.json'):
        continue
    sources.append((path, rel.as_posix()))
manifest = {
    'version': version,
    'deb_sha256': digest,
    'files': {rel: hashlib.sha256(path.read_bytes()).hexdigest() for path, rel in sources},
}
manifest_path = root / 'source-manifest.json'
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
sources.append((manifest_path, 'source-manifest.json'))
archive = out / f'CleanQuickActions_{version}_source.zip'
prefix = f'CleanQuickActions-{version}/'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path, rel in sources:
        z.write(path, prefix + rel)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist()) == len(set(z.namelist()))
    for rel, expected in manifest['files'].items():
        assert hashlib.sha256(z.read(prefix + rel)).hexdigest() == expected
print(json.dumps({'deb': str(deb), 'source_zip': str(archive), 'sha256': digest,
                  'archived_files': len(sources), 'on_device_tested': False}, indent=2))
