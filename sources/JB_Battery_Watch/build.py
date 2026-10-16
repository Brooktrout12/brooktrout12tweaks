#!/usr/bin/env python3
"""Build a native arm64 iOS executable using LLVM and narrow ABI declarations.
No SDK, font, proprietary binary, injection library or third-party runtime is bundled.
The generated .tbd is a link-time list of libSystem's used interface symbols, not an implementation.
"""
from pathlib import Path
import os, struct, subprocess, shutil
ROOT=Path(__file__).resolve().parent
BUILD=ROOT/'build';BUILD.mkdir(exist_ok=True)
CLANG=os.environ.get('CLANG',shutil.which('clang') or 'clang')
LD=os.environ.get('LD64_LLD',shutil.which('ld64.lld') or 'ld64.lld')
objects=[]
for name in ('core','darwin','inventory','logger'):
    obj=BUILD/f'{name}.o';objects.append(obj)
    subprocess.run([CLANG,'-target','arm64-apple-ios15.0','-ffreestanding','-fno-stack-protector','-fno-builtin','-Oz','-Wall','-Wextra','-Werror','-std=c11','-c',str(ROOT/'src'/f'{name}.c'),'-o',str(obj)],check=True)
def syms(path):
    b=path.read_bytes();magic,cpu,subtype,typ,ncmd,size,flags,res=struct.unpack_from('<8I',b)
    assert magic==0xfeedfacf and cpu==0x100000c
    pos=32;defs=set();undef=set()
    for _ in range(ncmd):
        cmd,sz=struct.unpack_from('<II',b,pos)
        if cmd==2:
            symoff,nsyms,stroff,strsize=struct.unpack_from('<4I',b,pos+8)
            for i in range(nsyms):
                idx,t,sect,desc,value=struct.unpack_from('<IBBHQ',b,symoff+i*16)
                if not idx:continue
                name=b[stroff+idx:b.index(0,stroff+idx)].decode()
                if t&1:
                    (undef if t&0x0e==0 else defs).add(name)
        pos+=sz
    return defs,undef
all_defs=set();all_undef=set()
for o in objects:
    d,u=syms(o);all_defs|=d;all_undef|=u
external=sorted(all_undef-all_defs)
# Explicit allowlist: fail instead of pretending an arbitrary unknown symbol exists.
allowed=set('''___error _bzero _access _calloc _chmod _chown _closedir _ctime _dlopen _dlsym _fclose _ferror _fflush _fgets _fileno _flock _fopen _fprintf _fputc _fputs _fread _free _fseek _ftell _fwrite _geteuid _getpid _mach_absolute_time _mach_continuous_time _mach_timebase_info _malloc _memcmp _memcpy _memmove _memset _mkdir _nanosleep _opendir _printf _pselect _sigprocmask _qsort _readdir _readlink _remove _rename _signal _snprintf _strchr _strcmp _strlen _strncmp _strrchr _strstr _sysctlbyname _time dyld_stub_binder'''.split())
assert not set(external)-allowed, f'Unexpected undefined symbols: {set(external)-allowed}'
exports=external+(['dyld_stub_binder'] if 'dyld_stub_binder' not in external else [])
tbd="--- !tapi-tbd-v3\narchs: [ arm64 ]\nplatform: ios\ninstall-name: '/usr/lib/libSystem.B.dylib'\ncurrent-version: 1.0\ncompatibility-version: 1.0\nexports:\n  - archs: [ arm64 ]\n    symbols: [ "+', '.join(exports)+" ]\n...\n"
(BUILD/'libSystem.tbd').write_text(tbd)
(BUILD/'imported-symbols.txt').write_text('\n'.join(external)+'\n')
out=BUILD/'jb-battery-watch'
# Swift's downstream LLD 17 rejects any input object with platform metadata.
# The compiler target has already been explicitly fixed to arm64-apple-ios15.0.
# Omit only that redundant input metadata; keep all code, relocations, file offsets
# and the OUTPUT's explicit iOS platform unchanged. No machine code or signing patch.
link_objects=[]
for obj in objects:
    b=bytearray(obj.read_bytes()); ncmds,sizeofcmds=struct.unpack_from('<II',b,16)
    pos=32; kept=[]
    for _ in range(ncmds):
        cmd,sz=struct.unpack_from('<II',b,pos)
        if cmd != 0x32: kept.append(bytes(b[pos:pos+sz]))
        else:
            platform,minos,sdk=struct.unpack_from('<III',b,pos+8)
            assert (platform,minos,sdk)==(2,0xF0000,0), (platform,minos,sdk)
        pos+=sz
    commands=b''.join(kept)
    b[32:32+sizeofcmds]=commands+b'\x00'*(sizeofcmds-len(commands))
    struct.pack_into('<II',b,16,len(kept),len(commands))
    lo=obj.with_suffix('.link.o');lo.write_bytes(b);link_objects.append(lo)
subprocess.run([LD,'-arch','arm64','-platform_version','ios','15.0','15.0','-syslibroot',str(BUILD),'-L'+str(BUILD),'-lSystem','-e','_main','-pie','-adhoc_codesign','-no_fixup_chains','-o',str(out),*map(str,link_objects)],check=True)
print('Built:',out, out.stat().st_size,'bytes')
