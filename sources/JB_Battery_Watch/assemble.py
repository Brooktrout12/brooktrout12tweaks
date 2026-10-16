#!/usr/bin/env python3
from pathlib import Path
import shutil,hashlib,subprocess,math,plistlib,tempfile,zipfile,os
R=Path(__file__).resolve().parent;P=R/'package';D=P/'DEBIAN';P.chmod(0o755)
OUTPUT=Path(os.environ.get('OUTPUT_DIR',str(R.parent)));OUTPUT.mkdir(parents=True,exist_ok=True)
doc=P/'var/jb/usr/share/doc/com.chatgpt.jbbatterywatch';doc.mkdir(parents=True,exist_ok=True)
for name in ('README.md','AUDIT.md','SOURCES.md','BUILD_NOTES.md'):
    shutil.copyfile(R/name,doc/name)
validation=R/'validation';shutil.rmtree(validation,ignore_errors=True);validation.mkdir(exist_ok=True)
for name in ('host-test-results.txt','binary-test-results.txt','maintainer-test-results.txt','imported-symbols.txt','prefs-test-results.txt','prefs-binary-test-results.txt','ui-refresh-test-results.txt','crash-fix-test-results.txt'):
    shutil.copyfile(R/'build'/name,validation/name)
shutil.copyfile(R/'build/prefs/build-results.txt',validation/'prefs-build-results.txt')
files=[p for p in P.rglob('*') if p.is_file() and D not in p.parents]
for p in files:
    assert str(p.relative_to(P)).startswith('var/jb/'),p
    p.chmod(0o755 if p.name in ('jb-battery-watch','JBBatteryWatchPrefs') else 0o644)
for p in P.rglob('*'):
    if p.is_dir():p.chmod(0o755)
(D/'md5sums').write_text(''.join(hashlib.md5(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(P))+'\n' for p in sorted(files)))
control=(D/'control').read_text();control='\n'.join(s for s in control.splitlines() if not s.startswith('Installed-Size:'))+'\n'
control+=f'Installed-Size: {math.ceil(sum(p.stat().st_size for p in files)/1024)}\n';(D/'control').write_text(control)
for name in ('preinst','postinst','prerm','postrm'):
    subprocess.run(['sh','-n',str(D/name)],check=True)
pl=plistlib.loads((P/'var/jb/Library/LaunchDaemons/com.chatgpt.jbbatterywatch.plist').read_bytes())
assert pl['RunAtLoad'] is True and 'KeepAlive' not in pl and 'StartInterval' not in pl
assert pl['ProgramArguments']==['/var/jb/usr/libexec/jb-battery-watch']
out=OUTPUT/'JB_Battery_Watch_2.1.1_rootless.deb'
subprocess.run(['dpkg-deb','--root-owner-group','-Zxz','--build',str(P),str(out)],check=True)
info=subprocess.check_output(['dpkg-deb','--info',str(out)],text=True)
contents=subprocess.check_output(['dpkg-deb','--contents',str(out)],text=True)
with tempfile.TemporaryDirectory() as t:
    subprocess.run(['dpkg-deb','--extract',str(out),t],check=True)
    for p in files:assert (Path(t)/p.relative_to(P)).read_bytes()==p.read_bytes()
sha=hashlib.sha256(out.read_bytes()).hexdigest()
(OUTPUT/'JB_Battery_Watch_2.1.1_SHA256.txt').write_text(f'{sha}  {out.name}\n')
(validation/'package-test-results.txt').write_text('PASS: maintainer shell syntax, rootless file paths, daemon plist\nPASS: package built and extracted; all payloads byte-identical\n\n'+info+'\n'+contents+f'\nSHA256 {sha}\n')
zip_path=OUTPUT/'JB_Battery_Watch_2.1.1_Source_and_Audit.zip'
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(R.rglob('*')):
        if not p.is_file() or '__pycache__' in p.parts:continue
        rel=p.relative_to(R)
        if rel.parts[0] in ('build','package'):continue
        z.write(p,'JB_Battery_Watch_2.1.1_Source/'+str(rel))
print(info);print(contents);print('DEB:',out,out.stat().st_size,'bytes\nSHA256:',sha)
print('SOURCE:',zip_path,zip_path.stat().st_size,'bytes')
