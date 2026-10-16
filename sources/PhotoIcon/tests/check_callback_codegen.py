#!/usr/bin/env python3
"""Regression check for the observed arm64e callback-property PAC crash.

Compile the real callback-owning source files to LLVM IR. Check that all
block-property setters copy through the Blocks runtime, without Objective-C
messaging of a legacy stack block. The shipped 1.0.0 source fails this test.
This verifies generated code, not an iOS runtime execution.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    args = parser.parse_args()
    owners = {
        'PIEditorCoordinator.m': ['-[PIHostController setOnReady:]'],
        'PICropViewController.m': ['-[PICropViewController setOnSave:]',
                                 '-[PICropViewController setOnCancel:]',
                                 '-[PICropViewController setOnChoosePhoto:]'],
    }
    results = []
    with tempfile.TemporaryDirectory(prefix='photoicon-callbacks-') as directory:
        for architecture in ('arm64', 'arm64e'):
            for filename, methods in owners.items():
                output = Path(directory) / f'{architecture}-{filename}.ll'
                subprocess.run([
                    str(args.clang.resolve()), '-target', f'{architecture}-apple-ios17.0',
                    '-isysroot', str(args.sdk.resolve()), '-fobjc-arc', '-Os',
                    '-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror',
                    '-S', '-emit-llvm', str((args.project/filename).resolve()), '-o', str(output),
                ], check=True)
                ir = output.read_text()
                for method in methods:
                    pattern = r'^define[^\n]*' + re.escape(method) + r'[^\n]*\{\n(.*?)^\}'
                    match = re.search(pattern, ir, re.M | re.S)
                    assert match, f'Missing setter: {method}'
                    body = match.group(1)
                    proper_copy = '@llvm.objc.retainBlock(' in body or '@_Block_copy(' in body
                    generic_copy = '@objc_setProperty_nonatomic_copy(' in body
                    objc_message = '@objc_msgSend(' in body
                    results.append({'architecture':architecture, 'method':method,
                                    'blocks_runtime_copy':proper_copy,
                                    'generic_property_copy':generic_copy,
                                    'objc_message':objc_message,
                                    'pass':proper_copy and not generic_copy and not objc_message})
    success = all(result['pass'] for result in results)
    print(json.dumps({'result':'PASS' if success else 'FAIL', 'setters':results,
                      'device_runtime_tested':False}, indent=2))
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())
