#!/usr/bin/env python3
"""Package the already-verified DEB, reproducible sources and validation notes."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
fields = dict(line.split(': ', 1) for line in (root / 'control').read_text().splitlines() if ': ' in line)
version = fields['Version']
package = root / 'packages' / f"{fields['Package']}_{version}_iphoneos-arm64.deb"
verification = json.loads((root / 'validation/package-verification.json').read_text())
digest = hashlib.sha256(package.read_bytes()).hexdigest()
assert verification['result'] == 'PASS' and verification['sha256'] == digest

deb = out / f'BlurSleep_{version}_rootless.deb'
shutil.copyfile(package, deb)
build_lines = (root / 'validation/build.log').read_text().splitlines()
state_result = next(line for line in build_lines if line.startswith('PASS: '))
(root / 'validation/state-test.txt').write_text(state_result + '\n')

validations = {'build.log', 'state-test.txt', 'package-verification.json', 'sleep-hook-regression.json', 'icon-verification.json', 'liquid-glass-regression.json'}
for prefix in ('BlurSleep.dylib.', 'BlurSleepPrefs.'):
    logs = list((root / 'validation').glob(prefix + '*.abi-conversion.log'))
    if logs:
        validations.add(max(logs, key=lambda p: p.stat().st_mtime).name)

sources = []
for p in sorted(root.rglob('*')):
    if not p.is_file():
        continue
    relative = p.relative_to(root)
    if any(part.startswith('.') or part == '__pycache__' for part in relative.parts):
        continue
    if relative.parts[0] == 'packages':
        continue
    if relative.parts[0] == 'validation' and relative.name not in validations:
        continue
    if len(relative.parts) == 1 and relative.name in ('build.log', 'source-sha256.txt'):
        continue
    sources.append((p, relative.as_posix()))

prefix = f'BlurSleep_{version}/'
archive = out / f'BlurSleep_{version}_DEB_and_Source.zip'
manifest = ''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  Source/{rel}\n' for p, rel in sources)
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.write(deb, prefix + deb.name)
    z.write(root / 'README.md', prefix + 'README.md')
    z.writestr(prefix + 'SHA256SUMS', f'{digest}  {deb.name}\n')
    z.writestr(prefix + 'SOURCE_SHA256SUMS', manifest)
    for p, relative in sources:
        z.write(p, prefix + 'Source/' + relative)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist()) == len(set(z.namelist()))
print(json.dumps({'deb': str(deb), 'sha256': digest, 'zip': str(archive),
                  'source_files': len(sources), 'device_runtime_tested': False}, indent=2))
