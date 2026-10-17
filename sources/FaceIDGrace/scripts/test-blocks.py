#!/usr/bin/env python3
"""Regression check against the actual 1.0.2 and replacement DEB binaries."""
import hashlib
import io
import json
from pathlib import Path
import struct
import subprocess
import sys
import tarfile

from verify_package import require, verify_block_free


def slices(path):
    payload = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(path)])
    with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
        entry = next(m for m in archive.getmembers() if m.name.endswith('/FaceIDGrace.dylib'))
        data = archive.extractfile(entry).read()
    require(struct.unpack_from('>II', data) == (0xCAFEBABE, 2), 'Expected two slices')
    result = {}
    for index in range(2):
        _, subtype, offset, size, _ = struct.unpack_from('>IIIII', data, 8 + index * 20)
        architecture = {0: 'arm64', 2: 'arm64e'}[subtype & 0xFFFFFF]
        result[architecture] = data[offset:offset + size]
    require(set(result) == {'arm64', 'arm64e'}, 'Missing architecture')
    return result


def main(old, new):
    results = []
    for architecture, binary in slices(old).items():
        try:
            verify_block_free(binary)
        except ValueError as error:
            require('Objective-C block metadata/observer is forbidden' in str(error),
                    'Old binary was rejected for an unrelated reason')
            results.append({'version': '1.0.2', 'architecture': architecture,
                            'expected_rejection': True, 'reason': str(error)})
        else:
            raise AssertionError('Regression: old block-bearing binary was accepted')
    for architecture, binary in slices(new).items():
        results.append({'version': '1.0.3', 'architecture': architecture,
                        **verify_block_free(binary)})
    print(json.dumps({'result': 'PASS', 'checks': results,
                      'baseline_sha256': hashlib.sha256(old.read_bytes()).hexdigest(),
                      'replacement_sha256': hashlib.sha256(new.read_bytes()).hexdigest(),
                      'on_device_tested': False}, indent=2))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: test-blocks.py /path/to/1.0.2.deb /path/to/1.0.3.deb')
    main(Path(sys.argv[1]), Path(sys.argv[2]))
