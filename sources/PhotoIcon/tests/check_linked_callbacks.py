#!/usr/bin/env python3
"""Verify callback-copy branches in the actual packaged Mach-O slices.

Uses UUID-matched dSYMs for method ranges and the packaged image's own import
stubs for branch targets. This is static machine-code validation, not an iOS
runtime test. Detailed call-argument data flow is checked in check_system_blocks.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile


SETTERS = ['-[PIHostController setOnReady:]', '-[PICropViewController setOnSave:]',
           '-[PICropViewController setOnCancel:]', '-[PICropViewController setOnChoosePhoto:]']
PICKER = '-[PIEditorCoordinator picker:didFinishPicking:]'


def sections(data):
    count = struct.unpack_from('<I', data, 16)[0]
    offset = 32
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x19:
            for i in range(struct.unpack_from('<I', data, offset+64)[0]):
                record = offset+72+i*80
                name = data[record:record+16].split(b'\0')[0].decode()
                address, length, file_offset = struct.unpack_from('<QQI', data, record+32)
                yield name, address, length, file_offset
        offset += size


def branches(data, start, stop):
    for name, address, length, offset in sections(data):
        if name != '__text':
            continue
        for pc in range(max(start, address), min(stop, address+length), 4):
            word = struct.unpack_from('<I', data, offset+pc-address)[0]
            if word & 0x7c000000 == 0x14000000:  # AArch64 B or BL immediate.
                immediate = word & 0x03ffffff
                if immediate & 0x02000000:
                    immediate -= 0x04000000
                yield pc, pc+immediate*4


def instruction_at(data, pc):
    for name, address, length, offset in sections(data):
        if name == '__text' and address <= pc < address+length:
            return struct.unpack_from('<I', data, offset+pc-address)[0]
    raise ValueError(f'No text instruction at {pc:#x}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--symbols', type=Path, required=True)
    parser.add_argument('--toolchain', type=Path, required=True)
    args = parser.parse_args()
    checks = []
    with tempfile.TemporaryDirectory(prefix='photoicon-linked-') as directory:
        root = Path(directory)
        subprocess.run(['dpkg-deb', '-x', str(args.package.resolve()), str(root)], check=True)
        binary = root/'var/jb/Library/MobileSubstrate/DynamicLibraries/PhotoIcon.dylib'
        fat = binary.read_bytes()
        magic, count = struct.unpack_from('>II', fat)
        assert magic == 0xcafebabe and count == 2
        for i in range(count):
            _, subtype, offset, size, _ = struct.unpack_from('>5I', fat, 8+i*20)
            architecture = 'arm64e' if subtype & 0xffffff == 2 else 'arm64'
            data = fat[offset:offset+size]
            dwarf = args.symbols/architecture/'PhotoIcon.dylib.dSYM/Contents/Resources/DWARF/PhotoIcon.dylib'
            uuids = subprocess.check_output([str(args.toolchain/'llvm-dwarfdump'), '--uuid', str(binary), str(dwarf)], text=True)
            matching = re.findall(r'UUID: ([\w-]+) \(' + architecture + r'\)', uuids)
            assert len(matching) == 2 and matching[0] == matching[1], 'dSYM UUID mismatch'
            symbols = subprocess.check_output([str(args.toolchain/'llvm-nm'), '--numeric-sort', str(dwarf)], text=True)
            ordered = [(int(address, 16), name) for address, name in
                       re.findall(r'^([\da-f]+) [tT] (.*)$', symbols, re.M)]
            starts = {name: address for address, name in ordered}
            ranges = {name: (address, ordered[j+1][0] if j+1 < len(ordered) else 2**64)
                      for j, (address, name) in enumerate(ordered)}
            imports = subprocess.check_output([str(args.toolchain/'llvm-objdump'), '--macho',
                       '--arch='+architecture, '--indirect-symbols', str(binary)], text=True)
            stubs = {}
            for address, name in re.findall(r'^(0x[\da-f]+)\s+\d+\s+(\S+)$', imports, re.M):
                stubs.setdefault(name, int(address, 16))
            for setter in SETTERS:
                targets = [target for _, target in branches(data, *ranges[setter])]
                valid = stubs['_objc_retainBlock'] in targets and not any(
                    stubs[name] in targets for name in ('_objc_msgSend', '_objc_setProperty_nonatomic_copy'))
                checks.append({'architecture': architecture, 'method': setter, 'pass': valid})
            helper = starts['_PICopyBlockForSystem']
            helper_targets = [target for _, target in branches(data, *ranges['_PICopyBlockForSystem'])]
            checks.append({'architecture': architecture, 'helper_calls_Block_copy':
                           stubs['__Block_copy'] in helper_targets,
                           'pass': stubs['__Block_copy'] in helper_targets and stubs['_objc_msgSend'] not in helper_targets})
            copies = [hex(pc) for pc, target in branches(data, 0, 2**64) if target == helper]
            checks.append({'architecture': architecture, 'system_copy_calls': copies,
                           'expected_count': 17, 'pass': len(copies) == 17})
            closing_copies = [hex(pc) for pc, target in
                              branches(data, *ranges['-[PIEditorCoordinator closeAnimated]']) if target == helper]
            checks.append({'architecture': architecture, 'dismissal_animation_runtime_copy_calls': closing_copies,
                           'pass': len(closing_copies) == 2})
            bookmark_hooks = [name for name in ranges if
                '_logos_method$PIBookmarkMenus$SBIconView$contextMenuInteraction$configurationForMenuAtLocation$' in name
                and 'block_invoke' not in name]
            bookmark_copies = [hex(pc) for name in bookmark_hooks
                               for pc, target in branches(data, *ranges[name]) if target == helper]
            checks.append({'architecture': architecture, 'bookmark_provider_runtime_copy_calls': bookmark_copies,
                           'pass': len(bookmark_hooks) == 1 and len(bookmark_copies) == 1})
            menu_helpers = [name for name in ranges if 'PIMenuWithBookmarkActions' in name and 'block_invoke' not in name]
            menu_copies = [hex(pc) for name in menu_helpers
                           for pc, target in branches(data, *ranges[name]) if target == helper]
            checks.append({'architecture': architecture, 'bookmark_action_runtime_copy_calls': menu_copies,
                           'pass': len(menu_helpers) == 1 and len(menu_copies) == 1})
            picker_copies = [hex(pc) for pc, target in branches(data, *ranges[PICKER]) if target == helper]
            checks.append({'architecture': architecture, 'method': PICKER, 'uuid': matching[0],
                           'runtime_copy_calls': picker_copies, 'pass': len(picker_copies) == 1})
            constructors = [name for name in ranges
                            if name.startswith('__ZL') and '_logosLocalCtor_' in name]
            assert len(constructors) == 1, 'Expected one tweak initializer'
            startup_copies = []
            for pc, target in branches(data, *ranges[constructors[0]]):
                if target != helper:
                    continue
                previous = instruction_at(data, pc-4)
                # In the pinned optimized build, both callbacks are addressed
                # by ADD X0, SP, #imm immediately before the copy-helper call.
                # 1.0.2 instead passes a pointer to a static global literal.
                stack_argument = previous & 0xffc003ff == 0x910003e0
                startup_copies.append({'address': hex(pc), 'argument_instruction': hex(previous),
                                       'passes_stack_literal': stack_argument})
            checks.append({'architecture': architecture, 'startup_copies': startup_copies,
                           'pass': len(startup_copies) == 2 and
                           all(item['passes_stack_literal'] for item in startup_copies)})
    success = all(check['pass'] for check in checks)
    print(json.dumps({'result': 'PASS' if success else 'FAIL',
                      'package': args.package.name,
                      'sha256': hashlib.sha256(args.package.read_bytes()).hexdigest(),
                      'checks': checks, 'device_runtime_tested': False}, indent=2))
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())
