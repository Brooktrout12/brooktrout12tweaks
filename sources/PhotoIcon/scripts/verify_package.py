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

def verify_slice(data, expected_subtype, minimum_classes=8):
    magic, cpu, subtype, kind, count, commandbytes, flags, reserved = unpack('<8I', data)
    assert magic == 0xfeedfacf and cpu == 0x100000c and kind == 6
    assert (subtype & 0xffffff) == expected_subtype
    assert flags & 1, 'Mach-O must declare no unresolved symbols'
    offset = 32
    dependencies, rpaths, sections = [], [], []
    minimum, sdk, signature = None, None, None
    for _ in range(count):
        command, size = unpack('<II', data, offset)
        assert size >= 8 and offset+size <= 32+commandbytes
        if command in (0xc, 0x80000018, 0x8000001f):
            dependencies.append(cstring(data, offset+unpack('<I', data, offset+8)[0]))
        elif command == 0x8000001c:
            rpaths.append(cstring(data, offset+unpack('<I', data, offset+8)[0]))
        elif command == 0x25:
            minimum, sdk = unpack('<II', data, offset+8)
        elif command == 0x32:
            platform, minimum, sdk = unpack('<III', data, offset+8)
            assert platform == 2, 'Expected a device iOS binary'
        elif command == 0x1d:
            signature = unpack('<II', data, offset+8)
        elif command == 0x19:
            section_count = unpack('<I', data, offset+64)[0]
            for i in range(section_count):
                section = offset+72+i*80
                name = cstring(data[section:section+16], 0)
                length = unpack('<Q', data, section+40)[0]
                file_offset = unpack('<I', data, section+48)[0]
                sections.append((name, file_offset, length))
        offset += size
    assert minimum == 0x110000, f'Unexpected deployment version: {minimum}'
    assert signature
    assert '@rpath/CydiaSubstrate.framework/CydiaSubstrate' in dependencies
    assert '/var/jb/Library/Frameworks' in rpaths
    assert any('.jbroot' in path for path in rpaths), 'Relocated rootless rpath is missing'
    assert all(path.startswith(('/usr/lib/', '/System/Library/', '@rpath/')) for path in dependencies)
    assert not any(b'/workspace/' in data[start:start+length] for name,start,length in sections if name=='__cstring')
    converted_classes = 0
    if expected_subtype == 2:
        for name, start, length in sections:
            if name == '__objc_data':
                for pos in range(start, start+length, 40):
                    isa, superclass = unpack('<QQ', data, pos)
                    assert isa & 0x800D6AE100000000 == 0x800D6AE100000000, 'arm64e class metadata was not converted'
                    assert superclass & 0xC00DB5AB00000000 == 0xC00DB5AB00000000
                    converted_classes += 1
        assert converted_classes >= minimum_classes
    return {'architecture':'arm64e' if expected_subtype==2 else 'arm64',
            'minimum_ios':'17.0', 'dependencies':dependencies, 'rpaths':rpaths,
            'converted_objc_class_records':converted_classes,
            'signatures':verify_signature(data, *signature)}

def main():
    package = pathlib.Path(sys.argv[1]).resolve()
    architecture = subprocess.check_output(['dpkg-deb','-f',str(package),'Architecture'], text=True).strip()
    assert architecture == 'iphoneos-arm64'
    with tempfile.TemporaryDirectory() as folder:
        subprocess.run(['dpkg-deb','-x',str(package),folder], check=True)
        root = pathlib.Path(folder)
        base = root/'var/jb/Library/MobileSubstrate/DynamicLibraries'
        files = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}
        assert files == {str((base/name).relative_to(root)) for name in
                         ('PhotoIcon.dylib','PhotoIcon.plist','PhotoIconSystem.dylib','PhotoIconSystem.plist')}
        with (base/'PhotoIcon.plist').open('rb') as stream:
            assert plistlib.load(stream) == {'Filter':{'Bundles':['com.apple.springboard']}}
        with (base/'PhotoIconSystem.plist').open('rb') as stream:
            assert plistlib.load(stream) == {'Filter':{'Bundles':['com.apple.UIKit']}}
        assert (root/'var/jb/var/mobile/Library/Caches/PhotoIcon').is_dir()
        subprocess.run(['dpkg-deb','-e',str(package),str(root/'control')], check=True)
        postinst = root/'control/postinst'
        assert postinst.is_file() and postinst.stat().st_mode & 0o111
        script = postinst.read_text()
        assert script.startswith('#!/var/jb/bin/sh\n')
        assert 'chown 501:501 "$pi_directory"' in script
        assert '/var/mobile/Library/Application Support/PhotoIcon' not in script
        subprocess.run(['sh','-n',str(postinst)],check=True)
        binaries = {}
        for name in ('PhotoIcon','PhotoIconSystem'):
            data = (base/(name+'.dylib')).read_bytes()
            magic, count = unpack('>II',data)
            assert magic == 0xcafebabe and count == 2
            slices = []
            subtypes = set()
            identifier = 'com.brooktrout12.photoicon' + ('.system' if name=='PhotoIconSystem' else '')
            for i in range(count):
                cpu, subtype, offset, size, alignment = unpack('>5I',data,8+i*20)
                assert cpu == 0x100000c and offset+size <= len(data)
                subtypes.add(subtype & 0xffffff)
                result = verify_slice(data[offset:offset+size], subtype & 0xffffff,
                                      minimum_classes=8 if name=='PhotoIcon' else 0)
                assert all(signature['identifier']==identifier for signature in result['signatures'])
                if name=='PhotoIconSystem':
                    assert result['converted_objc_class_records']==0, 'Read-only provider defines no custom classes'
                    assert not any('PhotosUI' in dependency for dependency in result['dependencies'])
                slices.append(result)
            assert subtypes == {0,2}
            binaries[name] = slices
        print(json.dumps({'package':package.name,'sha256':hashlib.sha256(package.read_bytes()).hexdigest(),
            'result':'PASS','binaries':binaries,'installer':'PASS','device_runtime_tested':False}, indent=2))

if __name__ == '__main__':
    main()
