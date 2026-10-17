#!/usr/bin/env python3
"""Inspect the shipped package, Mach-O targets and ad-hoc signature page hashes."""
import hashlib
import json
import math
import pathlib
import plistlib
import struct
import subprocess
import sys
import tempfile
import uuid

def unpack(fmt, data, offset=0):
    return struct.unpack_from(fmt, data, offset)

def cstring(data, offset):
    return data[offset:].split(b'\0', 1)[0].decode()

def verify_signature(data, offset, size):
    signature = data[offset:offset+size]
    magic, length, count = unpack('>III', signature)
    assert magic == 0xfade0cc0 and length <= size
    directories = []
    for index in range(count):
        slot, start = unpack('>II', signature, 12+index*8)
        blobmagic, blobsize = unpack('>II', signature, start)
        if blobmagic != 0xfade0c02:
            continue
        blob = signature[start:start+blobsize]
        version, flags, hashes, identifier, special, pages, limit = unpack('>IIIIIII', blob, 8)
        hashsize, hashtype, platform, pagelog = unpack('BBBB', blob, 36)
        assert flags & 2, 'Expected an ad-hoc code signature'
        assert limit == offset, 'Code signature must cover the entire preceding image'
        assert pages == math.ceil(limit/(1 << pagelog))
        assert hashtype in (1, 2, 3), f'Unknown hash algorithm: {hashtype}'
        for page in range(pages):
            chunk = data[page*(1 << pagelog):min((page+1)*(1 << pagelog), limit)]
            digest = (hashlib.sha1(chunk) if hashtype == 1 else hashlib.sha256(chunk)).digest()[:hashsize]
            assert digest == blob[hashes+page*hashsize:hashes+(page+1)*hashsize], f'Invalid signature page {page}'
        directories.append({'algorithm':hashtype, 'verified_pages':pages,
                            'identifier':cstring(blob, identifier)})
    assert directories, 'No verified CodeDirectory'
    return directories

def verify_slice(data, expected_subtype):
    magic, cpu, subtype, kind, count, commandbytes, flags, reserved = unpack('<8I',data)
    assert magic == 0xfeedfacf and cpu == 0x100000c and kind == 6
    assert subtype & 0xffffff == expected_subtype and flags & 1
    offset = 32
    dependencies, rpaths, sections = [], [], []
    minimum, signature, image_uuid = None, None, None
    for _ in range(count):
        command, size = unpack('<II',data,offset)
        assert size >= 8 and offset+size <= 32+commandbytes
        if command in (0xc,0x80000018,0x8000001f):
            dependencies.append(cstring(data,offset+unpack('<I',data,offset+8)[0]))
        elif command == 0x8000001c:
            rpaths.append(cstring(data,offset+unpack('<I',data,offset+8)[0]))
        elif command == 0x25:
            minimum, sdk = unpack('<II',data,offset+8)
        elif command == 0x32:
            platform, minimum, sdk = unpack('<III',data,offset+8)
            assert platform == 2
        elif command == 0x1d:
            signature = unpack('<II',data,offset+8)
        elif command == 0x1b:
            image_uuid = str(uuid.UUID(bytes=data[offset+8:offset+24]))
        elif command == 0x19:
            nsects = unpack('<I',data,offset+64)[0]
            for i in range(nsects):
                pos = offset+72+i*80
                name = cstring(data[pos:pos+16],0)
                length = unpack('<Q',data,pos+40)[0]
                start = unpack('<I',data,pos+48)[0]
                sections.append((name,start,length))
        offset += size
    assert minimum == 0x110000 and signature and image_uuid
    assert '/var/jb/Library/Frameworks' in rpaths
    assert any('.jbroot' in path for path in rpaths)
    assert all(x.startswith(('/usr/lib/','/System/Library/','@rpath/')) for x in dependencies)
    assert b'_NSConcrete' not in data, 'Block literals must not be present'
    for name,start,length in sections:
        if name == '__cstring': assert b'/workspace/' not in data[start:start+length]
    assert '/System/Library/Frameworks/UIKit.framework/UIKit' in dependencies
    assert '@rpath/CydiaSubstrate.framework/CydiaSubstrate' in dependencies
    required = (b'_MSHookMessageEx',b'_method_getArgumentType',b'_method_getReturnType',
        b'_method_getNumberOfArguments',b'_dispatch_async_f',b'__dyld_register_func_for_add_image',
        b'CCUISensorAttributionCompactControl',b'CCUIPrivacyAttributionButton',
        b'CCUIHeaderPocketView',b'compactSensorAttributionControl',b'privacyAttributionButton',
        b'isDisplayingSensorStatus',b'layoutSubviews',b'didMoveToWindow',b'setHidden:',b'setAlpha:',
        b'/var/mobile/Library/Logs/CCNoRecent.log',b'com.apple.springboard',b'1.0.0')
    for needle in required: assert needle in data, needle
    for needle in (b'_NSConcrete',b'AVCapture',b'SBSensorActivityDataProvider',
                   b'_UICreateScreenUIImage',b'CFPreferences',b'NSURLSession',b'TCCAccess'):
        assert needle not in data, needle
    classes = strings = 0
    if expected_subtype == 2:
        for name,start,length in sections:
            if name == '__objc_data':
                assert length % 40 == 0
                for pos in range(start,start+length,40):
                    isa,superclass = unpack('<QQ',data,pos)
                    assert isa & 0x800D6AE100000000 == 0x800D6AE100000000
                    assert superclass & 0xC00DB5AB00000000 == 0xC00DB5AB00000000
                    classes += 1
            if name == '__cfstring':
                assert length % 32 == 0
                for pos in range(start,start+length,32):
                    isa = unpack('<Q',data,pos)[0]
                    assert isa & 0xFFFFFFFF00000000 == 0xC0156AE100000000
                    strings += 1
        assert classes == 0
        assert strings > 0
    signatures = verify_signature(data,*signature)
    identity = 'com.brooktrout12.ccnorecent'
    assert all(item['identifier'] == identity for item in signatures)
    return {'binary':'CCNoRecent.dylib',
            'architecture':'arm64e' if expected_subtype == 2 else 'arm64',
            'uuid':image_uuid,'minimum_ios':'17.0','dependencies':dependencies,'rpaths':rpaths,
            'converted_objc_records':classes,'converted_constant_strings':strings,
            'signatures':signatures,'block_literals':False}

def main():
    package = pathlib.Path(sys.argv[1]).resolve()
    for field, expected in [('Package','com.brooktrout12.ccnorecent'),
                            ('Architecture','iphoneos-arm64'),('Version','1.0.0')]:
        assert subprocess.check_output(['dpkg-deb','-f',str(package),field],text=True).strip() == expected
    dependencies = subprocess.check_output(['dpkg-deb','-f',str(package),'Depends'],text=True)
    for item in ('firmware (>= 17.0)','firmware (<< 19.0)','mobilesubstrate (>= 0.9.5000)'):
        assert item in dependencies
    assert 'preferenceloader' not in dependencies
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(['dpkg-deb','-x',str(package),directory],check=True)
        root = pathlib.Path(directory)
        base = root/'var/jb/Library/MobileSubstrate/DynamicLibraries'
        expected = {str((base/name).relative_to(root)) for name in ('CCNoRecent.dylib','CCNoRecent.plist')}
        assert {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()} == expected
        assert plistlib.loads((base/'CCNoRecent.plist').read_bytes()) == {
            'Filter':{'Bundles':['com.apple.springboard'],'Executables':['SpringBoard']}}
        for p in root.rglob('*'):
            if p.is_dir(): assert p.stat().st_mode & 0o005 == 0o005
            if p.is_file(): assert p.stat().st_mode & 0o004
        data = (base/'CCNoRecent.dylib').read_bytes()
        magic,count = unpack('>II',data)
        assert magic == 0xcafebabe and count == 2
        types, slices = set(), []
        for i in range(count):
            cpu,subtype,offset,size,alignment = unpack('>5I',data,8+i*20)
            assert cpu == 0x100000c and offset+size <= len(data)
            types.add(subtype & 0xffffff)
            slices.append(verify_slice(data[offset:offset+size],subtype & 0xffffff))
        assert types == {0,2}
        import io,tarfile
        controls = subprocess.check_output(['dpkg-deb','--ctrl-tarfile',str(package)])
        with tarfile.open(fileobj=io.BytesIO(controls)) as archive:
            assert all(p.name.removeprefix('./') in ('','.','control','md5sums') for p in archive.getmembers())
    print(json.dumps({'result':'PASS','package':package.name,
        'sha256':hashlib.sha256(package.read_bytes()).hexdigest(),'slices':slices,
        'rootless_payload_only':True,'minimum_ios':'17.0','springboard_only':True,
        'settings_pane':False,'no_maintainer_scripts':True,'device_runtime_tested':False},indent=2))

if __name__ == '__main__': main()
