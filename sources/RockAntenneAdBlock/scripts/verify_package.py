#!/usr/bin/env python3
"""Validate the packaged payload and its actual Mach-O code hashes."""
import hashlib
import io
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tarfile
import uuid

def u32(data, pos, order='<'):
    return struct.unpack_from(order + 'I', data, pos)[0]

def check(condition, reason):
    if not condition:
        raise ValueError(reason)

def verify_signature(binary, offset, size):
    blob = binary[offset:offset + size]
    check(len(blob) == size and u32(blob, 0, '>') == 0xFADE0CC0, 'Invalid signature')
    check(u32(blob, 4, '>') <= size, 'Truncated signature')
    verified = []
    for i in range(u32(blob, 8, '>')):
        start = u32(blob, 16 + 8 * i, '>')
        if u32(blob, start, '>') != 0xFADE0C02:
            continue
        directory = blob[start:start + u32(blob, start + 4, '>')]
        hashes, slots, limit = (u32(directory, p, '>') for p in (16, 28, 32))
        width, kind, _, shift = directory[36:40]
        check(kind in (1, 2, 3, 4) and 0 < shift <= 20, 'Unsupported code hash format')
        page_size = 1 << shift
        check(limit == offset and slots == (limit + page_size - 1) // page_size, 'Incomplete code coverage')
        check(hashes + slots * width <= len(directory), 'Truncated code hashes')
        algorithm = {1: 'sha1', 2: 'sha256', 3: 'sha256', 4: 'sha384'}[kind]
        for page in range(slots):
            chunk = binary[page * page_size:min((page + 1) * page_size, limit)]
            actual = hashlib.new(algorithm, chunk).digest()[:width]
            expected = directory[hashes + page * width:hashes + (page + 1) * width]
            check(actual == expected, f'Code hash mismatch on page {page}')
        verified.append({'algorithm': algorithm, 'pages': slots})
    check(any(x['algorithm'] == 'sha256' for x in verified), 'Missing SHA256 signature')
    return verified

def main(deb):
    control = subprocess.check_output(['dpkg-deb', '-f', str(deb)], text=True)
    for text in ['Package: com.brooktrout12.rockantenneadblock', 'Version: 0.2.0',
                 'Architecture: iphoneos-arm64', 'firmware (>= 17.0)', 'firmware (<< 19.0)']:
        check(text in control, 'Wrong package metadata: ' + text)
    payload = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(deb)])
    root = 'var/jb/Library/MobileSubstrate/DynamicLibraries/RockAntenneAdBlock'
    with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
        files = {m.name.removeprefix('./'): m for m in archive if m.isfile()}
        check(set(files) == {root + '.dylib', root + '.plist'}, 'Unexpected injected files')
        for item in files.values():
            check(item.uid == 0 and item.gid == 0, 'Non-root package ownership')
        binary = archive.extractfile(files[root + '.dylib']).read()
        filter_plist = plistlib.loads(archive.extractfile(files[root + '.plist']).read())
    check(filter_plist == {'Filter': {'Bundles': ['de.rockantenne.eple']}}, 'Wrong injection scope')
    magic, cpu, subtype, filetype, count, command_bytes = struct.unpack_from('<6I', binary)
    check((magic, cpu, subtype, filetype) == (0xFEEDFACF, 0x0100000C, 0, 6), 'Expected arm64 app dylib')
    position, signature, deployment, image_uuid = 32, None, None, None
    dependencies = []
    for _ in range(count):
        command, length = struct.unpack_from('<II', binary, position)
        check(length >= 8 and position + length <= 32 + command_bytes, 'Invalid Mach-O command')
        if command == 0x32:
            platform, minimum = struct.unpack_from('<II', binary, position + 8)
            check(platform == 2 and minimum == 17 << 16, 'Wrong iOS minimum')
            deployment = '17.0'
        elif command == 0x1D:
            signature = struct.unpack_from('<II', binary, position + 8)
        elif command == 0x1B:
            image_uuid = str(uuid.UUID(bytes=binary[position + 8:position + 24]))
        elif command in (0xC, 0x80000018, 0x8000001F):
            start = position + u32(binary, position + 8)
            dependencies.append(binary[start:binary.index(b'\0', start)].decode())
        position += length
    check(position == 32 + command_bytes and signature and image_uuid and deployment, 'Missing Mach-O metadata')
    check(all(d.startswith('/System/Library/') or d.startswith('/usr/lib/') for d in dependencies), 'Unexpected dependency')
    check(not any('libswift' in d or 'CydiaSubstrate' in d or 'Preferences.framework' in d for d in dependencies), 'Unexpected helper framework')
    hashes = verify_signature(binary, *signature)
    return {'package': deb.name, 'sha256': hashlib.sha256(deb.read_bytes()).hexdigest(),
            'architecture': 'arm64 (App Store process, including A12+)', 'minimum_ios': deployment,
            'injection_bundle': 'de.rockantenne.eple', 'binary_uuid': image_uuid,
            'dependencies': dependencies, 'verified_code_signatures': hashes,
            'device_tested': False, 'status': 'static checks passed; on-device verification pending'}

if __name__ == '__main__':
    print(json.dumps(main(Path(sys.argv[1])), indent=2))
