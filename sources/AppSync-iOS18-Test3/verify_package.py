#!/usr/bin/env python3
"""Independent verification via ar, dpkg-deb, dpkg and fresh extraction.

Does not install packages or execute their maintainer programs.
Usage: python3 verify_package.py TEST1.deb NEW.deb ORIGINAL.deb AUDIT_DIR
"""
from __future__ import annotations

import difflib
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tarfile
import tempfile


def run(*args: str) -> bytes:
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def compare(version: str, relation: str, boundary: str) -> bool:
    result = subprocess.run(['dpkg', '--compare-versions', version, relation, boundary],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.decode())
    return result.returncode == 0


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def snapshot(root: Path) -> dict:
    entries = {}
    for path in sorted(root.rglob('*')):
        info = path.lstat()
        relative = path.relative_to(root).as_posix()
        record = {'mode': stat.S_IMODE(info.st_mode), 'uid': info.st_uid, 'gid': info.st_gid,
                  'mtime_ns': info.st_mtime_ns}
        if path.is_symlink():
            record.update(type='symlink', target=os.readlink(path))
        elif path.is_dir():
            record.update(type='directory')
        elif path.is_file():
            record.update(type='file', size=info.st_size, sha256=sha(path.read_bytes()))
        else:
            raise RuntimeError('Unexpected special file: ' + relative)
        entries[relative] = record
    return entries


def main() -> None:
    source, output, original, audit = map(Path, sys.argv[1:])
    audit.mkdir(parents=True, exist_ok=True)
    expected_source_hash = '0dd23330c7bff2e88e45c83d31df41875a4b56c8f3f99d8417dd28991be2161c'
    require(sha(source.read_bytes()) == expected_source_hash, 'Source is not the pinned Test 1.')
    source_members = run('ar', 't', str(source)).decode().splitlines()
    output_members = run('ar', 't', str(output)).decode().splitlines()
    require(source_members == output_members, 'ar member list differs.')
    payload_hashes = {label: sha(run('ar', 'p', str(path), 'data.tar.lzma'))
                      for label, path in [('test1', source), ('test3', output), ('original', original)]}
    require(len(set(payload_hashes.values())) == 1, 'Compressed payload hash differs.')
    require(run('ar', 'p', str(source), 'debian-binary') ==
            run('ar', 'p', str(output), 'debian-binary') == b'2.0\n', 'DEB format mismatch.')
    metadata_text = run('dpkg-deb', '--field', str(output)).decode()
    before_text = run('dpkg-deb', '--field', str(source)).decode()
    (audit / 'control-before.txt').write_text(before_text)
    (audit / 'control-after.txt').write_text(metadata_text)
    (audit / 'control.diff').write_text(''.join(difflib.unified_diff(
        before_text.splitlines(keepends=True), metadata_text.splitlines(keepends=True),
        fromfile='Test1/control', tofile='Test3/control')))
    version = run('dpkg-deb', '--field', str(output), 'Version').decode().strip()
    architecture = run('dpkg-deb', '--field', str(output), 'Architecture').decode().strip()
    dependencies = run('dpkg-deb', '--field', str(output), 'Depends').decode().strip()
    require(version == '116.0+ios18.x-test3', 'Unexpected package version.')
    require(architecture == 'iphoneos-arm64', 'Architecture changed.')
    require(dependencies == 'firmware (>= 5.0), mobilesubstrate (>= 0.9.5100), firmware (<< 19~)',
            'Incorrect dependency boundary.')
    run('dpkg', '--validate-version', version)
    for field in ['Package', 'Architecture', 'Conflicts', 'Provides', 'Replaces', 'Installed-Size']:
        require(run('dpkg-deb', '--field', str(source), field) ==
                run('dpkg-deb', '--field', str(output), field), field + ' changed.')

    firmware_rules = re.findall(r'firmware \((>=|<=|<<|>>|=) ([^)]+)\)', dependencies)
    def allowed(v: str) -> bool:
        return all(compare(v, op, limit) for op, limit in firmware_rules)

    # These are version-string boundary tests, not claims that all releases exist.
    allowed_examples = ['5.0', '17.6.1', '17.7', '18', '18.0', '18.0~beta1',
                        '18.2', '18.6', '18.6.1', '18.7', '18.7.1', '18.7.2',
                        '18.7.99', '18.8', '18.9', '18.10', '18.99', '18.999.999']
    blocked_examples = ['4.9', '19~beta1', '19.0~beta1', '19', '19.0', '19.1', '20.0', '26.0', '27.0']
    tests = []
    for value, expect in [(v, True) for v in allowed_examples] + [(v, False) for v in blocked_examples]:
        actual = allowed(value)
        require(actual == expect, f'Boundary test failed for {value}.')
        tests.append({'version_string': value, 'expected_allowed': expect,
                      'actual_allowed': actual, 'passed': True})
    generated = [f'18.{minor}{suffix}' for minor in range(101)
                 for suffix in ['', '.0', '.1', '.99', '~beta1']]
    for value in generated:
        require(allowed(value), f'Generated 18.x boundary test failed: {value}')
    upgrades = {old: compare(version, '>>', old) for old in
                ['116.0', '116.0+ios18.6test1', '116.0+ios18.7test2']}
    require(all(upgrades.values()), 'New version would be a downgrade.')

    with tempfile.TemporaryDirectory(prefix='appsync-test3-verification-') as temporary:
        tmp = Path(temporary)
        trees = {}
        for label, path in [('test1', source), ('test3', output), ('original', original)]:
            destination = tmp / label
            run('dpkg-deb', '--raw-extract', str(path), str(destination))
            trees[label] = snapshot(destination)
        before, after = trees['test1'], trees['test3']
        require(set(before) == set(after), 'Extracted path set changed.')
        changes = [p for p in before if before[p] != after[p]]
        require(changes == ['DEBIAN/control'], 'Unexpected extracted change: ' + repr(changes))
        executable_paths = [p for p, data in after.items()
                            if data['type'] == 'file' and data['mode'] & 0o111]
        executable_checks = []
        for name in executable_paths:
            hashes = {label: tree[name]['sha256'] for label, tree in trees.items()}
            require(len(set(hashes.values())) == 1, 'Executable content changed: ' + name)
            executable_checks.append({'path': name, 'sha256': hashes['test3'],
                                      'identical_to_test1_and_original': True})
        require(len(executable_paths) == 5, 'Unexpected executable count.')
        payload_files = [p for p, data in after.items()
                         if not p.startswith('DEBIAN/') and data['type'] == 'file']
        require(all(p.startswith('var/jb/') for p in payload_files), 'Non-rootless payload path.')
        (audit / 'extracted-manifest.json').write_text(json.dumps(after, indent=2) + '\n')
        # Re-run the supplied repacker and verify deterministic bytes.
        reproduced = tmp / 'reproduced.deb'
        run(sys.executable, str(audit / 'rebuild_from_test1.py'), str(source), str(reproduced))
        require(reproduced.read_bytes() == output.read_bytes(), 'Rebuild was not reproducible.')

    report = {
        'result': 'PASS',
        'scope': 'Host-side archive, metadata, version-rule and byte-identity verification; not an iPad runtime test.',
        'source': {'filename': source.name, 'sha256': sha(source.read_bytes()), 'bytes': source.stat().st_size},
        'output': {'filename': output.name, 'sha256': sha(output.read_bytes()), 'bytes': output.stat().st_size,
                   'version': version, 'architecture': architecture, 'depends': dependencies},
        'source_test2_package_used': False,
        'original_package_used_only_for_comparison': True,
        'payload_sha256': payload_hashes,
        'only_changed_extracted_path': 'DEBIAN/control',
        'changed_control_fields': ['Depends', 'Description', 'Name', 'Version'],
        'unchanged_payload_file_count': len(payload_files),
        'unchanged_executable_count_including_maintainer_programs': len(executable_checks),
        'executable_checks': executable_checks,
        'boundary_examples': tests,
        'additional_generated_18x_boundary_tests_passed': len(generated),
        'total_firmware_version_tests_passed': len(tests) + len(generated),
        'upgrade_ordering_tests': upgrades,
        'deterministic_rebuild_verified': True,
        'device_installation_performed': False,
        'device_runtime_test_performed': False,
        'limitations': ['Metadata-only compatibility allowance; does not guarantee runtime compatibility.',
                        'The pre-existing lower firmware bound and all other dependency/conflict checks are retained.',
                        'No code-signing, entitlements, launch hooks, payload paths or installation programs were changed.']
    }
    (audit / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    text = [
        'AppSync Unified - iOS/iPadOS 18.x Rootless Test 3',
        'VERIFICATION REPORT',
        '',
        'Result: PASS (host-side checks only; no iPad runtime testing performed)',
        '',
        'BASE PACKAGE',
        f'  {source.name}',
        f'  SHA-256: {report["source"]["sha256"]}',
        '  Test 2 was not opened or used as a build input.',
        '',
        'OUTPUT',
        f'  {output.name}',
        f'  SHA-256: {report["output"]["sha256"]}',
        f'  Size: {report["output"]["bytes"]} bytes',
        f'  Version: {version}',
        f'  Architecture: {architecture}',
        f'  Depends: {dependencies}',
        '',
        'WHAT CHANGED',
        '  Only DEBIAN/control differs after independent dpkg-deb extraction.',
        '  Four fields changed: Depends, Name, Description, Version.',
        '  Firmware ceiling changed from <= 18.6 to << 19~.',
        '  Lower firmware bound, other dependencies, package ID and conflict checks retained.',
        '',
        'BYTE-FOR-BYTE VERIFICATION',
        '  Entire data.tar.lzma matches Test 1 AND the originally uploaded official package.',
        f'  Compressed payload SHA-256: {payload_hashes["test3"]}',
        f'  All {len(payload_files)} payload files preserved, including permissions and ownership metadata.',
        '  Both dylibs, the injector, postinst and prerm match Test 1 AND the original.',
        '  Existing code-signature bytes and entitlements are therefore unchanged.',
        '  Only the control archive was repacked; data.tar.lzma was copied as-is.',
        '  Second rebuild from Test 1 reproduced the exact output SHA-256.',
        '',
        'VERSION TESTS',
        f'  {len(tests) + len(generated)} firmware-version test cases passed using dpkg.',
        '  Synthetic values test comparison boundaries; they do not imply those OS releases exist.',
    ]
    text += [f'  {t["version_string"]:<16} {"ALLOWED" if t["actual_allowed"] else "BLOCKED"}' for t in tests]
    text += [
        '  Also passed 505 generated 18.x strings (minor 0..100 with patch and beta suffixes).',
        '  New package version sorts newer than 116.0, Test 1, and the previously stated Test 2 version.',
        '',
        'LIMITATIONS',
        '  This is an unofficial metadata-only repack, not a new upstream release or code port.',
        '  Permitting installation on all 18.x versions does not prove runtime compatibility on all of them.',
        '  No maintainer programs were executed and no package was installed during verification.',
        '',
        'INSTALLATION',
        '  Open the Test 3 DEB in Filza and install it with the normal dependency checks enabled.',
        '  Then use a userspace reboot in the jailbreak app.',
        '  Test an expendable, known-good app; keep the prior working DEB for rollback.',
        '',
        'REPRODUCTION',
        '  python3 rebuild_from_test1.py /path/to/Test1.deb /path/to/output.deb',
        '  The script rejects any input whose SHA-256 does not match the verified Test 1.',
        '  It requires Python 3 only. Verification additionally requires ar, dpkg and dpkg-deb.',
        '',
        'REFERENCE FOR DEBIAN DEPENDENCY AND VERSION COMPARISON RULES',
        '  https://www.debian.org/doc/debian-policy/ch-relationships.html#syntax-of-relationship-fields',
        '  https://www.debian.org/doc/debian-policy/ch-controlfields.html#version',
    ]
    report_path = output.parent / 'AppSync-iOS18-Test3-Verification.txt'
    report_path.write_text('\n'.join(text) + '\n')
    (audit / 'VERIFICATION.txt').write_text(report_path.read_text())
    print(json.dumps({k: report[k] for k in ['result', 'output', 'only_changed_extracted_path',
          'unchanged_payload_file_count', 'unchanged_executable_count_including_maintainer_programs',
          'total_firmware_version_tests_passed', 'upgrade_ordering_tests',
          'deterministic_rebuild_verified']}, indent=2))


if __name__ == '__main__':
    main()
