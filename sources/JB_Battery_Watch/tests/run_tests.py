#!/usr/bin/env python3
from pathlib import Path
import subprocess, os, shutil, tempfile, time, struct, plistlib
ROOT=Path(__file__).resolve().parents[1]
B=ROOT/'build';W=B/'test-work';W.mkdir(exist_ok=True)
OUT=W/'report';STATE=W/'state';FIX=W/'fixtures'
CC=shutil.which('clang') or 'clang'
common=[CC,'-DJBBW_HOST_TEST','-D_DEFAULT_SOURCE','-std=c11','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-Wall','-Wextra','-Werror']
subprocess.run([*common,str(ROOT/'src/core.c'),str(ROOT/'tests/test_core.c'),'-o',str(B/'test-core')],check=True)
subprocess.run([str(B/'test-core')],check=True)
subprocess.run([*common,f'-DJBBW_REPORT_DIR="{OUT}"',f'-DJBBW_STATE_DIR="{STATE}"',str(ROOT/'src/core.c'),str(ROOT/'src/inventory.c'),str(ROOT/'src/logger.c'),str(ROOT/'tests/mock_platform.c'),'-o',str(B/'test-logger')],check=True)
ENV={**os.environ,'JBBW_FIXTURE_ROOT':str(FIX),'ASAN_OPTIONS':'detect_leaks=1:halt_on_error=1'}
def reset():
    for p in (OUT,STATE,FIX):
        shutil.rmtree(p,ignore_errors=True);p.mkdir(parents=True)
    db=FIX/'var/jb/var/lib/dpkg';(db/'info').mkdir(parents=True)
    (db/'status').write_text('Package: test.package\nVersion: 1.2.3\nName: Test package\nStatus: install ok installed\n\n')
    (db/'info/test.package.list').write_text('/var/jb/Library/MobileSubstrate/DynamicLibraries/Test.plist\n/var/jb/Library/MobileSubstrate/DynamicLibraries/Test.dylib\n/var/jb/usr/libexec/test-daemon\n')
    inj=FIX/'var/jb/Library/MobileSubstrate/DynamicLibraries';inj.mkdir(parents=True)
    (inj/'Test.plist').write_text('fixture');(inj/'Test.dylib').touch()
def run(extra=None,args=()):
    return subprocess.run([str(B/'test-logger'),*args],env={**ENV,**(extra or {})},capture_output=True,text=True,timeout=10)
def report():return (OUT/'JB-Battery-Report.txt').read_text()
def status():return (OUT/'STATUS.txt').read_text()
checks=[]
def check(name,condition):
    assert condition,name
    checks.append(name);print('PASS:',name)
reset();r=run();check('sanitized simulated 24-hour run exits cleanly',r.returncode==0 and not r.stderr)
txt=report();check('initial baseline plus 288 complete five-minute intervals',txt.count('\nSAMPLE\t')==289)
check('automatic completion and 30-point simulated battery change','COMPLETE:' in status() and 'net_percentage_points=30.000' in txt and (STATE/'completed').exists())
check('package inventory included automatically','PKG\ttest.package\t1.2.3' in txt)
check('file ownership and explicitly unproven candidates','\ttest.package\t/var/jb/usr/libexec/test-daemon' in txt and 'causality=UNPROVEN' in txt)
check('cumulative CPU deltas aggregate to known fixture result','test-daemon\t302.400000\t259200' in txt)
old=txt;r=run();check('finished session does not run again',r.returncode==0 and report()==old)
reset();r=run({'MOCK_DENIED':'1'});check('permission failure stops instead of misleading logging','ERROR: Insufficient process access' in status() and report().count('\nSAMPLE\t')==1)
reset();r=run({'MOCK_NO_BATTERY':'1'});check('unavailable battery is not invented','Battery reading: UNAVAILABLE' in status() and 'BATTERY_CHANGE' not in report())
reset();r=run({'MOCK_PAUSE_STEP':'2'});check('interruption preserves session, without a finished marker','PAUSED:' in status() and not (STATE/'completed').exists())
r=run({'MOCK_START_SECONDS':'600'});txt=report();check('resume preserves original deadline and appends a new baseline','RESUME_NEW_COUNTER_BASELINE' in txt and 'logger_runs=2' in txt and txt.count('\nSAMPLE\t')==289 and 'COMPLETE:' in status())
reset();r=run({'MOCK_DELAY':'1'});check('sleep/scheduling gaps are visible and do not demand 288 wakes','GAP\t' in report() and report().count('\nSAMPLE\t')<100 and 'COMPLETE:' in status())
reset();(STATE/'session.bin').write_bytes(b'broken');r=run();check('corrupt persistent state does not overwrite previous data','Saved state is corrupt' in status() and (STATE/'session.bin').read_bytes()==b'broken')
reset();r=run({'MOCK_DENIED':'1'},('--probe',));check('installation probe rejects insufficient access',r.returncode==21 and (OUT/'PROBE.txt').exists())
reset();r=run({},('--probe',));check('installation probe succeeds with readable processes',r.returncode==0 and not (STATE/'session.bin').exists())
reset();p=subprocess.Popen([str(B/'test-logger')],env={**ENV,'MOCK_REAL_SLEEP':'1'},stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
time.sleep(.25);r=run({'MOCK_PAUSE_STEP':'1'});p.terminate();stdout,stderr=p.communicate(timeout=5)
check('kernel lock prevents duplicate collectors; graceful stop clean',r.returncode==0 and report().count('LOGGER_RUN\t')==1 and not stderr)
reset();r=run({'MOCK_CHECK':'1'});health=plistlib.loads((OUT/'HEALTH.plist').read_bytes())
check('live check nonce is acknowledged after a complete saved sample',r.returncode==0 and not r.stderr and health['LastCheckNonce']==1234567 and health['ReportWriteOK']==1 and health['StateWriteOK']==1 and 'MANUAL_CHECK\tnonce=1234567' in report())
check('machine-readable completed health agrees with report',health['Schema']==1 and health['Version']=='2.1.0' and health['State']=='COMPLETE' and health['SampleCount']==289)
reset();r=run({'MOCK_NO_CHECK':'1'});health=plistlib.loads((OUT/'HEALTH.plist').read_bytes())
check('missing check notification API does not stop passive logging',r.returncode==0 and health['CheckSupported']==0 and health['LastCheckNonce']==0 and health['State']=='COMPLETE')
reset();r=run({'MOCK_DENIED':'1'});health=plistlib.loads((OUT/'HEALTH.plist').read_bytes())
check('machine-readable access failure is an error, not a successful check',health['State']=='ERROR' and health['LastCheckNonce']==0 and 'Insufficient process access' in health['Message'])
(B/'host-test-results.txt').write_text('\n'.join('PASS: '+s for s in checks)+'\n\nTests use synthetic counters and accelerated virtual time, not an iPhone.\nApple API availability, launchd behavior and actual power overhead still require a device test.\n')
print(f'{len(checks)} integration checks passed, plus core tests. Darwin APIs were mocked; no device test claimed.')
