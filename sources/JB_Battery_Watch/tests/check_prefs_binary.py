#!/usr/bin/env python3
"""Static checks only; this does not load the bundle in iOS Settings."""
from pathlib import Path
import hashlib, plistlib, struct
R=Path(__file__).resolve().parents[1]
fat=(R/'build/JBBatteryWatchPrefs').read_bytes();checks=[]
def check(name,ok):
    assert ok,name
    checks.append(name);print('PASS:',name)
check('universal preferences contains two slices',struct.unpack_from('>II',fat)==(0xcafebabe,2))
expected={'/usr/lib/libSystem.B.dylib','/usr/lib/libobjc.A.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/UIKit.framework/UIKit','/System/Library/PrivateFrameworks/Preferences.framework/Preferences','@rpath/libsandy.dylib'}
for i,arch in enumerate(('arm64','arm64e')):
    cpu,sub,off,length,align=struct.unpack_from('>5I',fat,8+i*20)
    assert cpu==0x100000c and sub==(0 if i==0 else 0x82000002)
    assert align==14 and off%16384==0 and off+length<=len(fat)
    b=fat[off:off+length];h=struct.unpack_from('<8I',b)
    check(f'{arch}: correct MH_BUNDLE architecture, PAC ABI 2 where required',h[:4]==(0xfeedfacf,cpu,sub,8))
    p=32;commands={};deps=[];paths=[];sections=[]
    for _ in range(h[4]):
        c,n=struct.unpack_from('<II',b,p);assert n>=8 and p+n<=32+h[5]
        commands[c]=p
        if c in (0xc,0x80000018,0x8000001f,0x8000001c):
            ix=struct.unpack_from('<I',b,p+8)[0];v=b[p+ix:b.index(0,p+ix)].decode()
            (paths if c==0x8000001c else deps).append(v)
        if c==0x19:
            vm,vs,fo,fs,mp,ip=struct.unpack_from('<4Q2I',b,p+24)
            assert fo+fs<=len(b) and not (ip&2 and ip&4)
            count=struct.unpack_from('<I',b,p+64)[0]
            for j in range(count):
                q=p+72+j*80;sn=b[q:q+16].split(b'\0')[0];seg=b[q+16:q+32].split(b'\0')[0]
                sections.append((sn,seg))
                if sn==b'__init_offsets':
                    a,sz,offset,al=struct.unpack_from('<QQII',b,q+32)
                    assert seg==b'__TEXT' and ip==5 and sz>0 and sz%4==0 and offset+sz<=len(b)
        p+=n
    assert p==32+h[5]
    check(f'{arch}: iOS 15 minimum, bounded segments, no writable executable segment',struct.unpack_from('<3I',b,commands[0x32]+8)==(2,0xf0000,0xf0000))
    check(f'{arch}: expected system dependencies and rootless library search paths',set(deps)==expected and paths==['/var/jb/usr/lib','@loader_path/.jbroot/usr/lib'])
    check(f'{arch}: chained fixups and read-only offset initializer',0x80000034 in commands and 0x80000022 not in commands and (b'__init_offsets',b'__TEXT') in sections and not any(x.startswith(b'__objc_') for x,y in sections))
    q=commands[0x1d];cs,sz=struct.unpack_from('<II',b,q+8)
    magic,ln,n=struct.unpack_from('>3I',b,cs);assert magic==0xfade0cc0 and ln<=sz and cs+sz<=len(b)
    pages=0
    for j in range(n):
        slot,offset=struct.unpack_from('>2I',b,cs+12+j*8)
        if slot:continue
        q=cs+offset
        magic,ln,version,flags,ho,io,ns,nc,limit=struct.unpack_from('>9I',b,q)
        hs,ht,platform,page=struct.unpack_from('4B',b,q+36)
        assert (magic,hs,ht,ns,limit)==(0xfade0c02,32,2,0,cs) and flags&2
        assert nc==(limit+(1<<page)-1)//(1<<page)
        for k in range(nc):
            assert b[q+ho+k*hs:q+ho+(k+1)*hs]==hashlib.sha256(b[k*(1<<page):min((k+1)*(1<<page),limit)]).digest()
        pages+=nc
    check(f'{arch}: every ad-hoc SHA256 signature page verified ({pages})',pages>0)
p=R/'package'
entry=plistlib.loads((p/'var/jb/Library/PreferenceLoader/Preferences/JBBatteryWatch.plist').read_bytes())
info=plistlib.loads((p/'var/jb/Library/PreferenceBundles/JBBatteryWatchPrefs.bundle/Info.plist').read_bytes())
check('PreferenceLoader bundle and principal class match',entry['entry']['bundle']=='JBBatteryWatchPrefs' and entry['entry']['detail']==info['NSPrincipalClass']=='JBBWPreferencesController' and info['CFBundleExecutable']=='JBBatteryWatchPrefs' and info['CFBundleVersion']=='2.1.1')
sandy=plistlib.loads((p/'var/jb/Library/libSandy/JBBatteryWatch_ReadReports.plist').read_bytes())
check('sandbox profile grants only Settings read access to report folder',sandy=={'AllowedProcesses':['com.apple.Preferences'],'Extensions':[{'type':'file','extension_class':'com.apple.app-sandbox.read','path':'/var/mobile/Documents/JBBatteryReport-v2'}]})
text='\n'.join('PASS: '+s for s in checks)+f'\n\nBundle SHA256: {hashlib.sha256(fat).hexdigest()}\nStatic checks only. UIKit/Preferences dispatch, arm64e dyld compatibility, device trust policy and share-sheet behavior remain untested on a physical iPhone.\n'
(R/'build/prefs-binary-test-results.txt').write_text(text)
