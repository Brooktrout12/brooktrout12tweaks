#!/usr/bin/env python3
"""Bundle the verified installer, matching source, and validation record."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True,exist_ok=True)
version = '1.0.0'
package = root/'packages'/f'com.brooktrout12.ccnorecent_{version}_iphoneos-arm64.deb'
verified = json.loads((root/'validation/package-verification.json').read_text())
digest = hashlib.sha256(package.read_bytes()).hexdigest()
assert verified['result'] == 'PASS' and verified['sha256'] == digest
deb = out/f'CCNoRecent_{version}_rootless.deb'
shutil.copyfile(package,deb)
sources = []
for p in sorted(root.rglob('*')):
    if not p.is_file(): continue
    relative = p.relative_to(root)
    if any(part.startswith('.') or part == '__pycache__' for part in relative.parts): continue
    if relative.parts[0] == 'packages': continue
    sources.append((p,relative.as_posix()))
prefix = f'CCNoRecent_{version}/'
archive = out/f'CCNoRecent_{version}_DEB_and_Source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    z.write(deb,prefix+deb.name)
    z.write(root/'README.md',prefix+'README.md')
    z.writestr(prefix+'SHA256SUMS',f'{digest}  {deb.name}\n')
    z.writestr(prefix+'SOURCE_SHA256SUMS',''.join(
        f'{hashlib.sha256(p.read_bytes()).hexdigest()}  Source/{rel}\n' for p,rel in sources))
    for p,rel in sources: z.write(p,prefix+'Source/'+rel)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None and len(z.namelist()) == len(set(z.namelist()))
print(json.dumps({'deb':str(deb),'zip':str(archive),'sha256':digest,
    'source_files':len(sources),'device_runtime_tested':False},indent=2))
