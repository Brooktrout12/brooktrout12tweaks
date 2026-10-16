#!/usr/bin/env python3
"""SDK-free C/runtime preference bundle. See BUILD_NOTES.md for the explicit
arm64e cross-link constraints. No proprietary framework implementations included.
The actual arm64e code is compiled with PAC ABI 2; it is not arm64 code relabeled.
"""
from pathlib import Path
import os,struct,subprocess,shutil,hashlib
R=Path(__file__).resolve().parent; B=R/'build/prefs';B.mkdir(parents=True,exist_ok=True)
clang=os.environ.get('CLANG',shutil.which('clang') or 'clang');ld=os.environ.get('LD64_LLD',shutil.which('ld64.lld') or 'ld64.lld')
def cmds(b):
    p=32
    for _ in range(struct.unpack_from('<I',b,16)[0]):
        c,n=struct.unpack_from('<II',b,p);yield p,c,n;p+=n

def symbols(b):
    out=[]
    for p,c,_ in cmds(b):
        if c==2:
            so,n,st,sz=struct.unpack_from('<4I',b,p+8)
            for i in range(n):
                ix,t,se,desc,v=struct.unpack_from('<IBBHQ',b,so+i*16)
                if ix:out.append((b[st+ix:b.index(0,st+ix)].decode(),t,desc,v))
    return out

def linkcopy(src,arch):
    b=bytearray(src.read_bytes());original=struct.unpack_from('<I',b,8)[0]
    assert original==(0x82000002 if arch=='arm64e' else 0)
    # Fail closed if anything requiring an arm64e-aware static-data linker appears.
    for p,c,n in cmds(b):
        if c==0x19:
            count=struct.unpack_from('<I',b,p+64)[0]
            for i in range(count):
                s=p+72+i*80;name=b[s:s+16].split(b'\0')[0]
                assert not name.startswith(b'__objc_'),(src,name)
                ro,rn=struct.unpack_from('<II',b,s+56)
                for k in range(rn):
                    info=struct.unpack_from('<I',b,ro+k*8+4)[0];typ=info>>28
                    assert typ!=11,'Static authenticated pointer relocation: unsupported in this constrained cross-link'
    size=struct.unpack_from('<I',b,20)[0];kept=[]
    for p,c,n in cmds(b):
        if c!=0x32:kept.append(bytes(b[p:p+n]))
        else:assert struct.unpack_from('<3I',b,p+8)==(2,0xf0000,0)
    lc=b''.join(kept);b[32:32+size]=lc+b'\0'*(size-len(lc));struct.pack_into('<II',b,16,len(kept),len(lc))
    # LLD17 only accepts arm64 input; all relocations were checked above as ordinary
    # arm64-compatible relocations. Actual PAC instructions are kept unchanged.
    struct.pack_into('<I',b,8,0)
    dst=src.with_suffix('.link.o');dst.write_bytes(b);return dst

def tbd(name,path,syms):
    f=B/(name+'.tbd');f.parent.mkdir(parents=True,exist_ok=True)
    f.write_text("--- !tapi-tbd-v3\narchs: [ arm64 ]\nplatform: ios\ninstall-name: '"+path+"'\ncurrent-version: 1.0\ncompatibility-version: 1.0\nexports:\n  - archs: [ arm64 ]\n    symbols: [ "+', '.join(sorted(syms))+" ]\n...\n")
    return f

system=set('''___error _arc4random _bzero _chmod _closedir _fclose _ferror _fflush _fgets _fopen _fprintf _fputs _fread _fseek _ftell _fwrite _memcpy _mkdir _notify_cancel _notify_post _notify_register_check _notify_set_state _opendir _qsort _readdir _remove _snprintf _strcmp _strerror _strlen _strncmp _time'''.split())
objc=set('''_class_addMethod _objc_allocateClassPair _objc_autoreleasePoolPop _objc_autoreleasePoolPush _objc_getAssociatedObject _objc_getClass _objc_msgSend _objc_msgSendSuper2 _objc_registerClassPair _objc_setAssociatedObject _sel_registerName'''.split())
foundation={'_NSTemporaryDirectory'};sandy={'_libSandy_applyProfile'}
libs=[tbd('libSystem','/usr/lib/libSystem.B.dylib',system|{'dyld_stub_binder'}),tbd('libobjc','/usr/lib/libobjc.A.dylib',objc),tbd('Foundation','/System/Library/Frameworks/Foundation.framework/Foundation',foundation),tbd('UIKit','/System/Library/Frameworks/UIKit.framework/UIKit',set()),tbd('Preferences','/System/Library/PrivateFrameworks/Preferences.framework/Preferences',set()),tbd('libsandy','@rpath/libsandy.dylib',sandy)]

def rehash(b):
    for p,c,_ in cmds(b):
        if c!=0x1d:continue
        off,size=struct.unpack_from('<II',b,p+8);magic,length,n=struct.unpack_from('>3I',b,off);assert magic==0xfade0cc0
        for i in range(n):
            slot,r=struct.unpack_from('>II',b,off+12+i*8)
            if slot!=0:continue
            q=off+r;magic,length,version,flags,hashoff,ident,ns,nc,limit=struct.unpack_from('>9I',b,q)
            hs,ht,platform,page=struct.unpack_from('4B',b,q+36);assert (magic,hs,ht,ns,limit)==(0xfade0c02,32,2,0,off)
            for k in range(nc):b[q+hashoff+k*hs:q+hashoff+(k+1)*hs]=hashlib.sha256(b[k*(1<<page):min((k+1)*(1<<page),limit)]).digest()
        return
    raise AssertionError('No signature')

slices=[];notes=[]
for arch in ['arm64','arm64e']:
    objects=[]
    for file in ['pane','health_model','export_io','ui_refresh']:
        o=B/f'{file}.{arch}.o';flags=['-Xclang','-fptrauth-abi-version=2'] if arch=='arm64e' else []
        subprocess.run([clang,'-target',arch+'-apple-ios15.0',*flags,'-Oz','-ffreestanding','-fno-builtin','-fno-stack-protector','-Wall','-Wextra','-Werror','-std=c11','-c',str(R/'prefs'/f'{file}.c'),'-o',str(o)],check=True)
        objects.append(o)
    defs=set();undef=set()
    for o in objects:
        for name,t,desc,v in symbols(o.read_bytes()):
            if not t&1:continue
            if t&0xe:defs.add(name)
            elif not (desc&0x40 and name.endswith('.ptrauth')):undef.add(name)
    assert not (undef-defs-system-objc-foundation-sandy),undef-defs-system-objc-foundation-sandy
    linked=[linkcopy(o,arch) for o in objects];out=B/f'JBBatteryWatchPrefs.{arch}'
    args=[ld,'-arch','arm64','-platform_version','ios','15.0','15.0','-bundle','-fixup_chains','-init_offsets','-adhoc_codesign','-rpath','/var/jb/usr/lib','-rpath','@loader_path/.jbroot/usr/lib','-o',str(out),*map(str,linked),*map(str,libs)]
    subprocess.run(args,check=True)
    b=bytearray(out.read_bytes());assert any(c==0x80000034 for p,c,n in cmds(b)),'Missing chained fixups'
    if arch=='arm64e':struct.pack_into('<I',b,8,0x82000002);rehash(b)
    out.write_bytes(b);slices.append(bytes(b));notes.append(f'{arch}: {len(b)} bytes; SHA256 {hashlib.sha256(b).hexdigest()}')
# Standard FAT_MAGIC and 16 KiB-aligned slices. The inner signatures hash each
# slice relative to itself, independently of the outer universal wrapper.
offsets=[];cursor=0x4000
for b in slices:offsets.append(cursor);cursor=(cursor+len(b)+0x3fff)&~0x3fff
fat=bytearray(cursor);struct.pack_into('>II',fat,0,0xcafebabe,2)
for i,(b,off) in enumerate(zip(slices,offsets)):
    sub=0 if i==0 else 0x82000002;struct.pack_into('>5I',fat,8+i*20,0x100000c,sub,off,len(b),14);fat[off:off+len(b)]=b
out=R/'build/JBBatteryWatchPrefs';out.write_bytes(fat);out.chmod(0o755)
(B/'build-results.txt').write_text('\n'.join(notes)+'\nBuilt actual ARM64 and ARM64e/PAC ABI 2 code. No physical-device execution.\n')
print('\n'.join(notes));print('Preference bundle:',out,len(fat),'bytes')
