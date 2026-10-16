#!/usr/bin/env python3
"""Static source/package regression checks, not an iOS runtime test."""
from pathlib import Path
import hashlib,json,struct
r=Path(__file__).resolve().parents[1]
f=(r/'build/JBBatteryWatchPrefs').read_bytes()
checks=[]
def check(name, ok):
    assert ok,name
    checks.append(name)
    print('PASS:',name)
check('prefs binary has no standalone tableView selector literal',b'tableView\0' not in f)
for i,arch in enumerate(('arm64','arm64e')):
    cpu,sub,off,size,align=struct.unpack_from('>5I',f,8+20*i)
    b=f[off:off+size]
    check(arch+': compiled checked list refresh and verified fallback selectors',
          all(x in b for x in (b'_jbbw_refresh_list\0',b'reloadSpecifiers\0',b'respondsToSelector:\0',b'table\0',b'viewIfLoaded\0')))
s=(r/'prefs/pane.c').read_text()
check('pane redraw routes through the guarded helper and has a reentrancy guard',
      'int route=jbbw_refresh_list(self);' in s and 'if(B(get(d,"redrawBusy")))return;' in s)
check('UI failure is separate from recorder health and is included in export',
      'Settings refresh unavailable' in s and 'UI refresh route: %lld' in s and 'put(info,"uiRefreshRoute"' in s)
check('full list reload invalidates the pane cache and rebuilds from live status',
      'V1(d,"removeObjectForKey:",N("specifiers"));' in s and
      'const char *title=dstr(d,"assessmentTitle"),*detail=dstr(d,"assessmentDetail");' in s)
baseline=json.loads((r/'tests/recorder_baseline.json').read_text())
check('recorder binary is byte-identical to the 2.1.0 release',
      hashlib.sha256((r/'build/jb-battery-watch').read_bytes()).hexdigest()==baseline['recorder_sha256'])
check('all native recorder source files unchanged',
      all(hashlib.sha256((r/name).read_bytes()).hexdigest()==sha for name,sha in baseline['source_sha256'].items()))
check('package recorder matches the unchanged build',
      (r/'build/jb-battery-watch').read_bytes()==(r/'package/var/jb/usr/libexec/jb-battery-watch').read_bytes())
(r/'build/crash-fix-test-results.txt').write_text('\n'.join('PASS: '+x for x in checks)+'\n\nStatic checks only. The runtime regression is a Linux dispatch model, not UIKit.\n')
