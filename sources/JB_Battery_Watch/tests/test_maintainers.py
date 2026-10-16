#!/usr/bin/env python3
"""Run actual maintainer scripts against a sandboxed, fake launchctl/device.
Fixed iOS paths are translated to temporary fixture paths only for these tests.
This is NOT an installation test on an iPhone.
"""
from pathlib import Path
import tempfile,os,subprocess,shutil,re,plistlib
R=Path(__file__).resolve().parents[1];checks=[]
def check(name,ok):
    assert ok,name;checks.append(name);print('PASS:',name)
with tempfile.TemporaryDirectory(prefix='jbbw-install-test-') as temp:
    root=Path(temp);ios=root/'ios';ios.mkdir()
    report=ios/'var/mobile/Documents/JBBatteryReport-v2';state=ios/'var/jb/var/lib/jb-battery-watch'
    mock=root/'mock';mock.mkdir();job=mock/'registered'
    lc=ios/'bin/launchctl';lc.parent.mkdir(parents=True)
    lc.write_text('''#!/bin/sh
case "$1" in
  bootout|unload) rm -f "$MOCK_JOB"; exit 0;;
  print) test -f "$MOCK_JOB"; exit $?;;
  bootstrap|load)
    [ "$MOCK_LAUNCH_FAIL" = 1 ] && exit 42
    touch "$MOCK_JOB"
    printf 'RECORDING - synthetic installation test\\n' > "$MOCK_REPORT/STATUS.txt"
    exit 0;;
esac
exit 1
''');lc.chmod(0o755)
    binary=ios/'var/jb/usr/libexec/jb-battery-watch';binary.parent.mkdir(parents=True)
    binary.write_text('''#!/bin/sh
[ "$1" = --probe ] || exit 30
printf 'SYNTHETIC TEST PROBE\\n' > "$MOCK_REPORT/PROBE.txt"
[ "$MOCK_PROBE_FAIL" = 1 ] && exit 21
exit 0
''');binary.chmod(0o755)
    # Keep test fixture ownership as the current host user, not actual iOS uid/gid.
    (mock/'chown').write_text('#!/bin/sh\nexit 0\n');(mock/'chown').chmod(0o755)
    env={**os.environ,'MOCK_JOB':str(job),'MOCK_REPORT':str(report),'MOCK_PROBE_FAIL':'0','MOCK_LAUNCH_FAIL':'0'}
    def run(name,arg,extra=None):
        s=re.sub(r'(?<![A-Za-z0-9_/-])/(?:var|bin)(?:/[A-Za-z0-9_.-]+)*',lambda m:str(ios)+m.group(0),(R/'package/DEBIAN'/name).read_text())
        s=s.replace('export PATH',f'PATH="{mock}:$PATH"\nexport PATH')
        p=root/name;p.write_text(s)
        return subprocess.run(['/bin/sh',str(p),*(arg if isinstance(arg,(tuple,list)) else [arg])],env={**env,**(extra or {})},capture_output=True,text=True,timeout=4)
    job.touch();a=run('preinst','upgrade');check('upgrade preinst unloads old job',a.returncode==0 and not job.exists())
    b=run('postinst','configure');check('successful probe then bootstrap creates recording status',b.returncode==0 and job.exists() and 'RECORDING' in (report/'STATUS.txt').read_text())
    (report/'JB-Battery-Report.txt').write_text('keep this report')
    (state/'session.bin').write_text('persisted session')
    a=run('preinst',('upgrade','2.0.0'));check('v2 upgrade marks session preservation and stops old job',a.returncode==0 and not job.exists() and (state/'preserve-upgrade').exists() and not (state/'new-install').exists())
    b=run('postinst','configure');check('v2 Settings upgrade preserves report and saved deadline bytes',b.returncode==0 and job.exists() and (state/'session.bin').read_text()=='persisted session' and (report/'JB-Battery-Report.txt').read_text()=='keep this report' and not (state/'preserve-upgrade').exists())
    a=run('preinst',('upgrade','2.1.0'));b=run('postinst','configure')
    check('2.1.0 to 2.1.1 preserves active report and exact saved state',a.returncode==b.returncode==0 and job.exists() and (state/'session.bin').read_text()=='persisted session' and (report/'JB-Battery-Report.txt').read_text()=='keep this report')
    (state/'completed').write_text('original completion marker')
    a=run('preinst',('upgrade','2.1.0'));b=run('postinst','configure')
    check('completed recording stays marked complete across the Settings fix',a.returncode==b.returncode==0 and (state/'completed').read_text()=='original completion marker' and (report/'JB-Battery-Report.txt').read_text()=='keep this report')
    a=run('prerm','remove');check('remove unloads only this job and preserves report',a.returncode==0 and not job.exists() and (report/'JB-Battery-Report.txt').read_text()=='keep this report')
    a=run('postrm','purge');check('purge removes private session state but keeps user report',a.returncode==0 and not (state/'session.bin').exists() and (report/'JB-Battery-Report.txt').exists())
    a=run('preinst','install');b=run('postinst','configure',{'MOCK_PROBE_FAIL':'1'})
    check('failed native probe does not launch and visibly reports failure',a.returncode==b.returncode==0 and not job.exists() and 'Recording has NOT started' in (report/'STATUS.txt').read_text())
    check('startup failure publishes machine-readable health for Settings',plistlib.loads((report/'HEALTH.plist').read_bytes())['State']=='ERROR')
    archives=list(report.parent.glob('JBBatteryReport-v2-previous-*'))
    check('reinstall archives, rather than overwrites, previous reports',any((p/'JB-Battery-Report.txt').exists() for p in archives))
    a=run('preinst','install');b=run('postinst','configure',{'MOCK_LAUNCH_FAIL':'1'})
    check('launchd rejection is visible and is not called recording',a.returncode==b.returncode==0 and not job.exists() and 'launchd rejected' in (report/'STATUS.txt').read_text())
text='\n'.join('PASS: '+s for s in checks)+'\n\nSandboxed script tests; launchctl, native probe, iOS filesystem paths and chown were mocked.\nNot a physical-device install test.\n'
(R/'build/maintainer-test-results.txt').write_text(text)
