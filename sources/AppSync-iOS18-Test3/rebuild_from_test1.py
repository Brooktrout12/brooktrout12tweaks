#!/usr/bin/env python3
"""Repack the exact AppSync Test 1 DEB, preserving its payload and programs.

Usage:
  python3 rebuild_from_test1.py PATH_TO_TEST1.deb OUTPUT.deb

Python 3 standard library only. The source SHA-256 is pinned intentionally.
This changes package metadata, not AppSync code or runtime compatibility.
"""
from __future__ import annotations

import argparse
import copy
import gzip
import hashlib
import io
import re
import tarfile
from pathlib import Path

SOURCE_SHA256 = '0dd23330c7bff2e88e45c83d31df41875a4b56c8f3f99d8417dd28991be2161c'
VERSION = '116.0+ios18.x-test3'
DEPENDENCIES = 'firmware (>= 5.0), mobilesubstrate (>= 0.9.5100), firmware (<< 19~)'


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_ar(data: bytes) -> list[tuple[str, bytes, bytes, bytes]]:
    require(data.startswith(b'!<arch>\n'), 'Not a standard ar archive.')
    position = 8
    members = []
    while position < len(data):
        header = data[position:position + 60]
        require(len(header) == 60 and header[58:60] == b'`\n', 'Invalid ar header.')
        name = header[:16].decode('ascii').strip().rstrip('/')
        require(name and not name.startswith(('#1/', '/')), 'Unsupported extended ar member name.')
        size = int(header[48:58].decode('ascii').strip())
        start = position + 60
        body = data[start:start + size]
        require(len(body) == size, 'Truncated ar member.')
        padding = data[start + size:start + size + (size % 2)]
        require(len(padding) == size % 2, 'Missing ar padding.')
        members.append((name, header, body, padding))
        position = start + size + (size % 2)
    require(position == len(data), 'Trailing ar data.')
    return members


def control_fields(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    current = None
    for line in text.splitlines():
        if line.startswith((' ', '\t')):
            require(current is not None, 'Orphan control continuation line.')
            fields[current] += '\n' + line
        elif line:
            require(':' in line, 'Malformed control field.')
            current, value = line.split(':', 1)
            require(current not in fields, 'Duplicate control field.')
            fields[current] = value.lstrip()
    return fields


def tar_inventory(blob: bytes) -> dict[str, tuple[dict, bytes | None]]:
    result = {}
    with tarfile.open(fileobj=io.BytesIO(blob), mode='r:*') as archive:
        for member in archive.getmembers():
            require(member.name not in result, 'Duplicate tar member.')
            handle = archive.extractfile(member) if member.isfile() else None
            metadata = {key: getattr(member, key) for key in (
                'name', 'mode', 'uid', 'gid', 'size', 'mtime', 'type',
                'linkname', 'uname', 'gname', 'devmajor', 'devminor', 'pax_headers'
            )}
            result[member.name] = (metadata, handle.read() if handle else None)
    return result


def rebuild(source: Path, destination: Path) -> None:
    require(source.resolve() != destination.resolve(), 'Output must not overwrite the source.')
    require(not destination.exists(), 'Output already exists; choose a new path.')
    source_bytes = source.read_bytes()
    require(sha256(source_bytes) == SOURCE_SHA256, 'Source is not the verified Test 1 package.')
    members = read_ar(source_bytes)
    require([m[0] for m in members] == ['debian-binary', 'control.tar.gz', 'data.tar.lzma'],
            'Unexpected Test 1 archive structure.')
    original_control = members[1][2]
    original_inventory = tar_inventory(original_control)
    old_text = original_inventory['./control'][1].decode('utf-8')
    old_fields = control_fields(old_text)
    require(old_fields['Version'] == '116.0+ios18.6test1', 'Wrong source package version.')
    require(old_fields['Architecture'] == 'iphoneos-arm64', 'Wrong source architecture.')
    require(old_fields['Depends'] ==
            'firmware (>= 5.0), mobilesubstrate (>= 0.9.5100), firmware (<= 18.6)',
            'Unexpected source dependencies.')

    replacements = {
        'Depends': DEPENDENCIES,
        'Name': 'AppSync Unified (iOS 18.x Test 3)',
        'Description': (
            'Unofficial iOS/iPadOS 18.x firmware-limit repack of Test 1.\n'
            ' Only package metadata is changed; original 116.0 code is preserved.\n'
            ' Permits all 18.x firmware versions; runtime compatibility is not guaranteed.\n'
            ' This is not an official Karen/akemi release.'
        ),
        'Version': VERSION,
    }
    new_text = old_text
    for field, value in replacements.items():
        pattern = re.compile(r'^' + re.escape(field) + r':[^\n]*(?:\n[ \t][^\n]*)*', re.MULTILINE)
        new_text, count = pattern.subn(lambda _: f'{field}: {value}', new_text)
        require(count == 1, f'Could not replace exactly one {field} field.')
    new_fields = control_fields(new_text)
    require(set(new_fields) == set(old_fields), 'Control field set changed unexpectedly.')
    changed = {k for k in old_fields if old_fields[k] != new_fields[k]}
    require(changed == set(replacements), 'Unexpected metadata change.')

    # Rebuild only the small control archive, carrying over every TarInfo field.
    # The entire compressed data.tar.lzma member is copied without decompression.
    tar_output = io.BytesIO()
    with tarfile.open(fileobj=io.BytesIO(original_control), mode='r:gz') as src:
        with tarfile.open(fileobj=tar_output, mode='w', format=tarfile.GNU_FORMAT) as out:
            for entry in src.getmembers():
                new_entry = copy.deepcopy(entry)
                content_handle = src.extractfile(entry) if entry.isfile() else None
                content = content_handle.read() if content_handle else None
                if entry.name == './control':
                    content = new_text.encode('utf-8')
                    new_entry.size = len(content)
                out.addfile(new_entry, io.BytesIO(content) if content is not None else None)
    compressed = io.BytesIO()
    with gzip.GzipFile(filename='', mode='wb', compresslevel=9, fileobj=compressed, mtime=0) as gz:
        gz.write(tar_output.getvalue())
    new_control = compressed.getvalue()
    new_inventory = tar_inventory(new_control)
    require(set(new_inventory) == set(original_inventory), 'Control archive member set changed.')
    for name in original_inventory:
        if name == './control':
            old_meta = dict(original_inventory[name][0])
            new_meta = dict(new_inventory[name][0])
            old_meta.pop('size')
            new_meta.pop('size')
            require(old_meta == new_meta, 'Control file metadata changed unexpectedly.')
        else:
            require(original_inventory[name] == new_inventory[name],
                    f'Non-control member changed: {name}')

    output = bytearray(b'!<arch>\n')
    for name, header, body, padding in members:
        if name == 'control.tar.gz':
            body = new_control
            header = header[:48] + f'{len(body):<10}'.encode('ascii') + header[58:]
            padding = b'\n' if len(body) % 2 else b''
        output.extend(header + body + padding)
    verified = read_ar(bytes(output))
    require(verified[0] == members[0], 'debian-binary changed.')
    require(verified[2] == members[2], 'Payload or its ar header changed.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(output)
    print(f'Created: {destination}')
    print(f'Version: {VERSION}')
    print(f'Depends: {DEPENDENCIES}')
    print(f'Source SHA-256: {sha256(source_bytes)}')
    print(f'Output SHA-256: {sha256(output)}')
    print(f'Unchanged data.tar.lzma SHA-256: {sha256(members[2][2])}')
    print('Changed control fields: ' + ', '.join(sorted(changed)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        rebuild(args.source, args.output)
    except (OSError, ValueError, KeyError, tarfile.TarError) as exc:
        parser.exit(1, f'Error: {exc}\n')


if __name__ == '__main__':
    main()
