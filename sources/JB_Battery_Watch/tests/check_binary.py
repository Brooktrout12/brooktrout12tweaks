#!/usr/bin/env python3
"""Static Mach-O checks. These do NOT execute or validate iOS private APIs."""
from pathlib import Path
import struct, hashlib
R=Path(__file__).resolve().parents[1]; b=(R/'build/jb-battery-watch').read_bytes()
u32=lambda p:struct.unpack_from('<I',b,p)[0]
h=struct.unpack_from('<8I',b);assert h[0]==0xfeedfacf and h[1]==0x0100000c and h[2]==0 and h[3]==2
assert h[6]&0x200000 # PIE
p=32;commands={};deps=[]
for i in range(h[4]):
    cmd,n=struct.unpack_from('<II',b,p);assert n>=8 and p+n<=32+h[5]
    commands.setdefault(cmd,[]).append(p)
    if cmd in (0xc,0x80000018,0x8000001f):
        off=u32(p+8);deps.append(b[p+off:b.index(0,p+off)].decode())
    if cmd==0x19:
        vmaddr,vmsize,fileoff,filesize,maxprot,initprot=struct.unpack_from('<4Q2I',b,p+24)
        assert fileoff+filesize<=len(b)
        assert not (initprot&2 and initprot&4), 'Writable executable segment'
    p+=n
assert p==32+h[5]
v=commands[0x32][0];assert struct.unpack_from('<3I',b,v+8)==(2,0xf0000,0xf0000)
assert deps==['/usr/lib/libSystem.B.dylib'],deps
assert 0x80000028 in commands
p=commands[0xe][0];off=u32(p+8);assert b[p+off:b.index(0,p+off)]==b'/usr/lib/dyld'
p=commands[0x1d][0];cs_off,cs_size=struct.unpack_from('<II',b,p+8)
magic,size,n=struct.unpack_from('>3I',b,cs_off);assert magic==0xfade0cc0 and size<=cs_size
verified=0
for i in range(n):
    slot,offset=struct.unpack_from('>2I',b,cs_off+12+i*8);q=cs_off+offset
    if slot!=0:continue
    magic,length,version,flags,hashOff,identOff,nSpecial,nCode,codeLimit=struct.unpack_from('>9I',b,q)
    hs,ht,platform,page=struct.unpack_from('4B',b,q+36)
    assert magic==0xfade0c02 and flags&2 and ht==2 and hs==32 and nSpecial==0
    assert codeLimit==cs_off
    assert nCode==(codeLimit+(1<<page)-1)//(1<<page)
    for k in range(nCode):
        expected=b[q+hashOff+k*hs:q+hashOff+(k+1)*hs]
        actual=hashlib.sha256(b[k*(1<<page):min((k+1)*(1<<page),codeLimit)]).digest()
        assert expected==actual, f'Code signature mismatch page {k}'
    verified+=nCode
assert verified>0
text=f'''PASS: Mach-O ARM64 (not arm64e), MH_EXECUTE, PIE
PASS: iOS platform 2; minimum iOS 15.0, declared link SDK 15.0
PASS: exactly one linked library, /usr/lib/libSystem.B.dylib
PASS: /usr/lib/dyld interpreter and LC_MAIN entry point
PASS: segment bounds; no writable-and-executable mapped segment
PASS: ad-hoc SHA-256 code signature, {verified} page hashes verified
Binary size: {len(b)} bytes
SHA256: {hashlib.sha256(b).hexdigest()}

Static structural checks only. Device signing policy and private API behavior were NOT tested.
'''
print(text);(R/'build/binary-test-results.txt').write_text(text)
