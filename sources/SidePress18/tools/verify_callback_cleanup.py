#!/usr/bin/env python3
"""Check both callback failures found in the user's device reports.

Reject direct stack releases and verify _Block_copy's return value reaches
the completion argument of each external Objective-C call. This deliberately
checks the short, straight-line handoff emitted by the supported toolchain;
it is not a general control-flow or memory-safety proof.
Usage: python3 tools/verify_callback_cleanup.py PACKAGE LLVM_OBJDUMP
"""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from verify_package import unpack_tar


def heap_handoffs(lines):
    handoffs = []
    for index, line in enumerate(lines):
        if 'symbol stub for: __Block_copy' not in line:
            continue
        heap_registers = {'x0'}
        for following in lines[index + 1:index + 25]:
            instruction = re.match(r'\s*[0-9a-f]+:\s+(\S+)\s*(.*)', following)
            if not instruction:
                continue
            opcode, operands = instruction.groups()
            if opcode in ('bl', 'blr', 'braa', 'blraa'):
                if 'symbol stub for: _objc_msgSend' in following or '; Objc message:' in following:
                    if 'x4' in heap_registers:
                        kind = 'third_argument'
                    elif 'x3' in heap_registers:
                        kind = 'second_argument'
                    else:
                        break
                    handoffs.append({'callback': kind, 'copy': line.strip(), 'call': following.strip()})
                break
            if opcode == 'mov':
                match = re.match(r'(x\d+),\s*(x\d+)\b', operands)
                if match:
                    destination, source = match.groups()
                    if source in heap_registers:
                        heap_registers.add(destination)
                    else:
                        heap_registers.discard(destination)
                    continue
            # Conservatively forget registers written by another instruction.
            if opcode not in ('str', 'stp', 'nop', 'cbz', 'cbnz', 'cmp', 'tst'):
                destinations = re.findall(r'\b[wx]\d+\b', operands.split('[')[0])
                for register in destinations[:2 if opcode == 'ldp' else 1]:
                    heap_registers.discard('x' + register[1:])
    return handoffs


def inspect(package, objdump):
    payload = unpack_tar(package, '--fsys-tarfile')
    violations, checked = [], []
    with tempfile.TemporaryDirectory(prefix='sidepress18-code-') as directory:
        for name, (data, _) in payload.items():
            if not name.endswith(('.dylib', '/SidePress18Prefs')):
                continue
            path = Path(directory) / Path(name).name
            path.write_bytes(data)
            for arch in ('arm64', 'arm64e'):
                output = subprocess.check_output([
                    objdump, '--macho', '--disassemble', '--no-show-raw-insn',
                    '--arch=' + arch, str(path)], text=True)
                lines = output.splitlines()
                check = {'binary': Path(name).name, 'architecture': arch}
                checked.append(check)
                if name.endswith('/SidePress18.dylib'):
                    handoffs = heap_handoffs(lines)
                    check['heap_callback_handoffs'] = handoffs
                    # Foreground app launch, native Camera presentation and direct
                    # secure-scene submission all pass argument-three blocks. Authentication now uses a
                    # C action callback and C-owned dispatch event handler.
                    if sorted(h['callback'] for h in handoffs) != ['third_argument'] * 3:
                        violations.append({'binary': Path(name).name, 'architecture': arch,
                                           'reason': 'Missing verified heap copy at an external callback boundary'})
                elif b'predicateWithBlock:' in data:
                    violations.append({'binary': Path(name).name, 'architecture': arch,
                                       'reason': 'The crashing NSBlockPredicate search path is still present'})
                for index, line in enumerate(lines):
                    if 'symbol stub for: _objc_release' not in line or index == 0:
                        continue
                    previous = lines[index - 1]
                    if re.search(r'\b(?:add|mov)\s+x0,\s*sp\b', previous):
                        violations.append({'binary': Path(name).name, 'architecture': arch,
                                           'instructions': [previous.strip(), line.strip()]})
    if len(checked) != 6:
        raise ValueError('Expected to inspect both architectures of all three binaries')
    return {'result': 'FAIL' if violations else 'PASS',
            'scope': 'Direct stack release, heap handoffs at three external callback boundaries, and removal of the crashing block predicate',
            'checked': checked, 'violations': violations}


if __name__ == '__main__':
    report = inspect(Path(sys.argv[1]), sys.argv[2])
    print(json.dumps(report, indent=2))
    sys.exit(bool(report['violations']))
