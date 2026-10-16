#!/usr/bin/env python3
"""Validate the rootless SwitcherSweep payload, device slices and code signatures."""
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
    magic,cpu,subtype,kind,count,commandbytes,flags,reserved=unpack('<8I',data)
    assert magic==0xfeedfacf and cpu==0x100000c and kind==6
    assert (subtype & 0xffffff)==expected_subtype and flags & 1
    offset=32
    dependencies,rpaths,sections=[],[],[]
    minimum,signature,image_uuid=None,None,None
    for _ in range(count):
        command,size=unpack('<II',data,offset)
        assert size>=8 and offset+size<=32+commandbytes
        if command in (0xc,0x80000018,0x8000001f):
            dependencies.append(cstring(data,offset+unpack('<I',data,offset+8)[0]))
        elif command==0x8000001c:
            rpaths.append(cstring(data,offset+unpack('<I',data,offset+8)[0]))
        elif command==0x25:
            minimum=unpack('<I',data,offset+8)[0]
        elif command==0x32:
            platform,minimum=unpack('<II',data,offset+8)
            assert platform==2
        elif command==0x1d:
            signature=unpack('<II',data,offset+8)
        elif command==0x1b:
            image_uuid=str(uuid.UUID(bytes=data[offset+8:offset+24]))
        elif command==0x19:
            for i in range(unpack('<I',data,offset+64)[0]):
                section=offset+72+i*80
                name=cstring(data[section:section+16],0)
                length=unpack('<Q',data,section+40)[0]
                start=unpack('<I',data,section+48)[0]
                sections.append((name,start,length))
        offset+=size
    assert minimum==0x110000 and signature and image_uuid
    assert '@rpath/CydiaSubstrate.framework/CydiaSubstrate' in dependencies
    for framework in ['UIKit','Foundation','QuartzCore']:
        assert f'/System/Library/Frameworks/{framework}.framework/{framework}' in dependencies
    assert '/var/jb/Library/Frameworks' in rpaths
    assert any('.jbroot' in path for path in rpaths)
    assert all(path.startswith(('/usr/lib/','/System/Library/','@rpath/')) for path in dependencies)
    assert not any(b'/workspace/' in data[start:start+length] for name,start,length in sections if name=='__cstring')
    assert b'_NSConcrete' not in data, 'Unexpected compiled block literals'
    assert not any(name=='__objc_data' and length for name,start,length in sections), 'Unexpected custom class records'
    for symbol in [
        b'_MSHookMessageEx\0',b'_class_addMethod\0',b'_objc_setAssociatedObject\0',
        b'_method_getNumberOfArguments\0',b'_method_getArgumentType\0',b'_method_getReturnType\0',
        b'_OBJC_CLASS_$_UIVisualEffectView\0',b'_OBJC_CLASS_$_UIBlurEffect\0',
        b'_OBJC_CLASS_$_CAAnimationGroup\0',b'_OBJC_CLASS_$_CABasicAnimation\0',
        b'SBFluidSwitcherViewController\0',b'SBMainSwitcherControllerCoordinator\0',
        b'switcherContentController:deletedDisplayItem:inAppLayout:forReason:\0',
        b'_dismissSwitcherNoninteractivelyToAppLayout:dismissFloatingSwitcher:animated:\0',
        b'homeScreenAppLayout\0',b'btss_press:\0',b'btss_commit:\0',b'btss_returnHome:\0',
        b'btss_pendingWake:\0',b'pendingClose\0',b'pendingSince\0',
        b'pendingWakeScheduled\0',b'drainingPending\0',
        b'isTransitioning\0',b'isComplete\0',b'nativeTransitionCoordinator\0',
        b'Close All\0',b'snapshotViewAfterScreenUpdates:\0',b'recentAppLayouts\0',
        b'prepareForCoordinatedLayoutStateTransitionWithContext:\0',
        b'layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:\0',
        b'layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:\0',
        b'setEffect:\0',b'removeFromSuperview\0',b'appLayout\0',b'transitionContext\0',
        b'toLayoutState\0',b'unlockedEnvironmentMode\0',
        b'requestForActivatingAppSwitcher\0',b'requestForActivatingHomeScreen\0',
        b'beginAnimations:context:\0',b'commitAnimations\0',
        b'brooktrout12.switchersweep.buttonEntry\0',b'brooktrout12.switchersweep.borderEntry\0']:
        assert symbol in data, 'Required blur, animation or native close capability missing: '+str(symbol)
    for symbol in [b'_MSHookFunction\0',b'_kill\0',b'_killpg\0',b'_system\0',b'_posix_spawn\0',
                   b'_rebind_symbols\0',b'_AudioServicesPlaySystemSound\0',b'_vm_write\0',
                   b'brooktrout12.switchersweep.visibility\0']:
        assert symbol not in data, 'Unexpected global hook or process-kill entry point: '+str(symbol)
    for symbol in [b'SwitcherSweep-diagnostics.json\0', b'pendingTrace\0',
                   b'pendingObservation\0', b'_dispatch_queue_create\0',
                   b'_OBJC_CLASS_$_NSJSONSerialization\0', b'_OBJC_CLASS_$_NSFileManager\0',
                   b'writeToFile:atomically:\0']:
        assert symbol not in data, 'Unexpected diagnostic writer: '+str(symbol)
    converted_strings=0
    if expected_subtype==2:
        for name,start,length in sections:
            if name=='__cfstring':
                assert length%32==0
                for pos in range(start,start+length,32):
                    assert unpack('<Q',data,pos)[0] & 0xffffffff00000000 == 0xc0156ae100000000
                    converted_strings+=1
        assert converted_strings>0
    signatures=verify_signature(data,*signature)
    assert all(x['identifier']=='com.brooktrout12.switchersweep' for x in signatures)
    return {'architecture':'arm64e' if expected_subtype==2 else 'arm64',
            'uuid':image_uuid,'minimum_ios':'17.0','dependencies':dependencies,'rpaths':rpaths,
            'converted_constant_strings':converted_strings,'custom_objc_class_records':0,
            'compiled_block_literals':False,'diagnostic_writer_present':False,'signatures':signatures}

def main():
    package=pathlib.Path(sys.argv[1]).resolve()
    expected={'Package':'com.brooktrout12.switchersweep','Name':'SwitcherSweep','Version':'1.0.8',
              'Architecture':'iphoneos-arm64','Author':'brooktrout12','Maintainer':'brooktrout12',
              'Description':'Close all apps with a frosted App Switcher button, a quick upward sweep, and a smooth return to the Home Screen.'}
    for key,value in expected.items():
        assert subprocess.check_output(['dpkg-deb','-f',str(package),key],text=True).strip()==value
    with tempfile.TemporaryDirectory() as folder:
        subprocess.run(['dpkg-deb','-x',str(package),folder],check=True)
        root=pathlib.Path(folder)
        base=root/'var/jb/Library/MobileSubstrate/DynamicLibraries'
        files={str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}
        assert files=={str((base/name).relative_to(root)) for name in ['SwitcherSweep.dylib','SwitcherSweep.plist']}
        assert plistlib.loads((base/'SwitcherSweep.plist').read_bytes())=={'Filter':{'Bundles':['com.apple.springboard']}}
        import io,tarfile
        control=subprocess.check_output(['dpkg-deb','--ctrl-tarfile',str(package)])
        with tarfile.open(fileobj=io.BytesIO(control)) as archive:
            assert all(p.name.removeprefix('./') in ('','.','control','md5sums') for p in archive.getmembers())
        data=(base/'SwitcherSweep.dylib').read_bytes()
        magic,count=unpack('>II',data)
        assert magic==0xcafebabe and count==2
        slices=[];subtypes=set()
        for i in range(count):
            cpu,subtype,offset,size,alignment=unpack('>5I',data,8+i*20)
            assert cpu==0x100000c and offset+size<=len(data)
            subtypes.add(subtype & 0xffffff)
            slices.append(verify_slice(data[offset:offset+size],subtype & 0xffffff))
        assert subtypes=={0,2}
    print(json.dumps({'result':'PASS','package':package.name,
        'sha256':hashlib.sha256(package.read_bytes()).hexdigest(),'slices':slices,
        'springboard_only':True,'rootless_only_payload':True,'no_maintainer_scripts':True,
        'no_raw_process_kill_or_global_C_hooks':True,'device_runtime_tested':False},indent=2))

if __name__=='__main__':main()
