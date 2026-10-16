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

def verify_slice(data, expected_subtype, preferences=False):
    magic, cpu, subtype, kind, count, commandbytes, flags, reserved = unpack('<8I', data)
    assert magic == 0xfeedfacf and cpu == 0x100000c and kind == 6
    assert (subtype & 0xffffff) == expected_subtype
    assert flags & 1, 'Mach-O must declare no unresolved symbols'
    offset = 32
    dependencies, rpaths, sections = [], [], []
    minimum, sdk, signature, image_uuid = None, None, None, None
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
        elif command == 0x1b:
            image_uuid = str(uuid.UUID(bytes=data[offset+8:offset+24]))
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
    assert signature and image_uuid
    if not preferences:
        assert '@rpath/CydiaSubstrate.framework/CydiaSubstrate' in dependencies
    assert '/var/jb/Library/Frameworks' in rpaths
    assert any('.jbroot' in path for path in rpaths), 'Relocated rootless rpath is missing'
    assert all(path.startswith(('/usr/lib/', '/System/Library/', '@rpath/')) for path in dependencies)
    assert not any(b'/workspace/' in data[start:start+length] for name,start,length in sections if name=='__cstring')
    converted_classes = 0
    converted_constant_strings = 0
    assert b'_NSConcrete' not in data, 'Unexpected Objective-C block literals'
    if preferences:
        assert '/System/Library/PrivateFrameworks/Preferences.framework/Preferences' in dependencies
        assert '/System/Library/Frameworks/UIKit.framework/UIKit' in dependencies
        for required in (b'_OBJC_CLASS_$_BTLockSoundPrefsController\0',
                         b'setVolume:specifier:\0', b'readVolume:\0', b'readVolumeText:\0',
                         b'LockVolume\0', b'LockVolumeValue\0',
                         b'_CFPreferencesSetAppValue\0', b'_CFNotificationCenterPostNotification\0'):
            assert required in data, 'Missing Settings control or preference writer'
        for removed in (b'_OBJC_CLASS_$_BTLockVolumeCell\0', b'_OBJC_CLASS_$_UISlider\0',
                        b'cellClass\0', b'heightForRowAtIndexPath:\0'):
            assert removed not in data, 'Custom slider construction/layout must be absent'
    else:
        assert '/System/Library/PrivateFrameworks/SpringBoardUI.framework/SpringBoardUI' in dependencies
    assert '/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox' not in dependencies
    for required in (b'_OBJC_CLASS_$_SBUISound\0',
                     b'_playFeedback:\0', b'_playSystemSound:\0',
                     b'eventType\0', b'soundType\0', b'setSoundType:\0',
                     b'songPath\0', b'setSongPath:\0',
                     b'/var/jb/Library/Application Support/ClassicLockSound/lock.caf\0',
                     b'_dladdr\0', b'_MSHookMessageEx\0',
                     b'_method_getReturnType\0', b'_method_getArgumentType\0',
                     b'_method_getNumberOfArguments\0'):
        if not preferences:
            assert required in data, 'Required feedback redirect or ABI validation is absent'
    for required in (b'_CFPreferencesCopyAppValue\0', b'_CFPreferencesAppSynchronize\0',
                     b'VolumePercent\0', b'com.brooktrout12.classiclocksound/volume-changed\0'):
        assert required in data, 'Missing shared volume preferences or notification name'
    if not preferences:
        for required in (b'_CFNotificationCenterAddObserver\0',
                         b'/var/mobile/Library/Caches/ClassicLockSound\0',
                         b'original-90d02d979ff94def-pcm1-%03d.caf\0'):
            assert required in data, 'Missing volume refresh or cache identity'
    for forbidden in (b'_MSHookFunction\0', b'_rebind_symbols\0',
                      b'_AudioServicesPlaySystemSound\0', b'_AudioServicesPlaySystemSoundWithCompletion\0',
                      b'_AudioServicesPlayAlertSound\0', b'_AudioServicesPlayAlertSoundWithCompletion\0',
                      b'_AudioServicesPlaySystemSoundWithOptions\0', b'_AudioServicesPlaySystemSoundWithVibration\0',
                      b'SSScreenCapturer\0', b'shouldPlayLockSound\0',
                      b'_AudioServicesCreateSystemSoundID\0', b'_CC_SHA256\0',
                      b'_vm_read_overwrite\0', b'_dlsym\0',
                      b'/var/mobile/Library/Logs/ClassicLockSound-diagnostics.json\0',
                      b'initWithSystemSoundID:behavior:vibrationPattern:\0',
                      b'initWithSystemSoundPath:behavior:vibrationPattern:\0',
                      b'_AVAudioSession\0', b'_AVAudioPlayer\0'):
        assert forbidden not in data, 'Global audio hooks, diagnostics and superseded hooks must be absent'
    if expected_subtype == 2:
        for name, start, length in sections:
            if name == '__objc_data':
                for pos in range(start, start+length, 40):
                    isa, superclass = unpack('<QQ', data, pos)
                    assert isa & 0x800D6AE100000000 == 0x800D6AE100000000, 'arm64e class metadata was not converted'
                    assert superclass & 0xC00DB5AB00000000 == 0xC00DB5AB00000000
                    converted_classes += 1
        assert converted_classes == (2 if preferences else 0), 'Unexpected class/metaclass count'
        # Allemande updates authenticated constant-string/class records, not
        # the CPU subtype header. A versioned-subtype flag is not its output.
        for name, start, length in sections:
            if name == '__cfstring':
                assert length % 32 == 0
                for pos in range(start, start+length, 32):
                    isa = unpack('<Q', data, pos)[0]
                    assert isa & 0xFFFF_FFFF_00000000 == 0xC015_6AE1_00000000, 'Unconverted constant-string ISA'
                    converted_constant_strings += 1
        assert converted_constant_strings >= 1
    signatures = verify_signature(data, *signature)
    identity = 'com.brooktrout12.classiclocksound' + ('.prefs' if preferences else '')
    assert all(item['identifier'] == identity for item in signatures)
    return {'binary':'ClassicLockSoundPrefs' if preferences else 'ClassicLockSound.dylib',
            'architecture':'arm64e' if expected_subtype==2 else 'arm64',
            'uuid':image_uuid,
            'minimum_ios':'17.0', 'dependencies':dependencies, 'rpaths':rpaths,
            'converted_objc_class_records':converted_classes,
            'converted_constant_string_records':converted_constant_strings,
            'objc_block_literals':False,
            'native_feedback_to_file_route_present':not preferences,
            'diagnostic_capture_removed':True,
            'direct_audio_playback_absent':True,
            'global_audio_hooks_absent':True,
            'signatures':signatures}

def main():
    package = pathlib.Path(sys.argv[1]).resolve()
    architecture = subprocess.check_output(['dpkg-deb','-f',str(package),'Architecture'], text=True).strip()
    assert architecture == 'iphoneos-arm64'
    for field, expected in [('Package','com.brooktrout12.classiclocksound'), ('Author','brooktrout12'), ('Maintainer','brooktrout12'), ('Version','1.0.8'), ('Description','Restores the classic iOS 7-9 lock sound with a 0-100 percent volume slider in Settings.')]:
        actual = subprocess.check_output(['dpkg-deb','-f',str(package),field], text=True).strip()
        assert actual == expected, (field, actual)
    dependencies = subprocess.check_output(['dpkg-deb','-f',str(package),'Depends'], text=True)
    for required in ('firmware (>= 17.0)', 'firmware (<< 19.0)', 'preferenceloader (>= 2.2.6)'):
        assert required in dependencies
    with tempfile.TemporaryDirectory() as folder:
        subprocess.run(['dpkg-deb','-x',str(package),folder], check=True)
        root = pathlib.Path(folder)
        base = root/'var/jb/Library/MobileSubstrate/DynamicLibraries'
        files = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}
        resource = root/'var/jb/Library/Application Support/ClassicLockSound/lock.caf'
        bundle = root/'var/jb/Library/PreferenceBundles/ClassicLockSoundPrefs.bundle'
        loader = root/'var/jb/Library/PreferenceLoader/Preferences/ClassicLockSound.plist'
        expected = {str((base/name).relative_to(root)) for name in ('ClassicLockSound.dylib','ClassicLockSound.plist')}
        expected |= {str(resource.relative_to(root)), str(loader.relative_to(root))}
        expected |= {str((bundle/name).relative_to(root)) for name in
                     ('ClassicLockSoundPrefs','Info.plist','icon.png','icon@2x.png','icon@3x.png')}
        assert files == expected, files ^ expected
        info = plistlib.loads((bundle/'Info.plist').read_bytes())
        assert info['NSPrincipalClass'] == 'BTLockSoundPrefsController'
        assert info['MinimumOSVersion'] == '17.0' and info['CFBundleShortVersionString'] == '1.0.8'
        entry = plistlib.loads(loader.read_bytes())['entry']
        assert entry['bundle'] == 'ClassicLockSoundPrefs' and entry['detail'] == info['NSPrincipalClass']
        assert entry['icon'] == '/var/jb/Library/PreferenceBundles/ClassicLockSoundPrefs.bundle/icon.png'
        for name, dimension in [('icon.png',29), ('icon@2x.png',58), ('icon@3x.png',87)]:
            icon = (bundle/name).read_bytes()
            assert icon[:8] == b'\x89PNG\r\n\x1a\n' and unpack('>II',icon,16) == (dimension,dimension)
        expected_sound_hash = '90d02d979ff94defa18b05ca91ba8633a7eb73f28574b015af09d542d8331543'
        assert hashlib.sha256(resource.read_bytes()).hexdigest() == expected_sound_hash, 'Expected the original full-level CAF'
        assert resource.read_bytes().startswith(b'caff\x00\x01'), 'Expected CAF version 1'
        # No install/uninstall scripts and no packaged files outside /var/jb.
        controls = subprocess.check_output(['dpkg-deb','--ctrl-tarfile',str(package)])
        import io, tarfile
        with tarfile.open(fileobj=io.BytesIO(controls)) as archive:
            assert all(p.name.removeprefix('./') in ('', '.', 'control', 'md5sums') for p in archive.getmembers())
        with (base/'ClassicLockSound.plist').open('rb') as stream:
            assert plistlib.load(stream) == {'Filter':{'Bundles':['com.apple.springboard']}}
        slices = []
        for binary, preferences in ((base/'ClassicLockSound.dylib',False), (bundle/'ClassicLockSoundPrefs',True)):
            data = binary.read_bytes()
            magic, count = unpack('>II',data)
            assert magic == 0xcafebabe and count == 2
            subtypes = set()
            for i in range(count):
                cpu, subtype, offset, size, alignment = unpack('>5I',data,8+i*20)
                assert cpu == 0x100000c and offset+size <= len(data)
                subtypes.add(subtype & 0xffffff)
                slices.append(verify_slice(data[offset:offset+size], subtype & 0xffffff, preferences))
            assert subtypes == {0,2}
        print(json.dumps({'package':package.name,'sha256':hashlib.sha256(package.read_bytes()).hexdigest(),
            'result':'PASS','slices':slices,'packaged_audio_sha256':expected_sound_hash,
            'default_audio_gain':1.0, 'volume_percent_range':[0,100],
            'settings_icon_sizes':[29,58,87],
            'observed_device_route':{'sound_type':5, 'event_type':1002},
            'rootless_only_payload':True,
            'no_system_file_replacement_or_maintainer_scripts':True,
            'device_runtime_tested':False}, indent=2))

if __name__ == '__main__':
    main()
