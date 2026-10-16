#!/usr/bin/env python3
"""Audit actual generated hooks for native-image isolation and reuse cleanup.

These checks reject the 1.0.3 image substitutions and missing reuse cleanup.
They inspect compiler output; they do not reproduce UIKit's runtime caching.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from check_system_blocks import last_value, split_arguments


def inspect(ir, architecture):
    functions = {}
    pattern = r'^define[^\n]*?@(?:"([^"]+)"|([\w.$]+))\((.*?)\)[^\n]*\{\n(.*?)^\}'
    for match in re.finditer(pattern, ir, re.M | re.S):
        name = match.group(1) or match.group(2)
        functions[name] = (split_arguments(match.group(3)), match.group(4))
    checks = []

    def record(name, passed):
        checks.append({'architecture': architecture, 'check': name, 'pass': bool(passed)})

    def function(fragment):
        found = [value for name, value in functions.items() if fragment in name]
        return found[0] if len(found) == 1 else ([], '')

    def original_calls(body, selector):
        pointers = re.findall(r'(%\d+) = load[^\n]*@"[^"\n]*_logos_orig\$PIViewImages(?:17|18)?\$SBIconImageView\$' +
                              re.escape(selector) + r'[^"\n]*"', body)
        calls = []
        for pointer in pointers:
            for match in re.finditer(r'(?:call|invoke) void ' + re.escape(pointer) + r'\((.*?)\)', body):
                calls.append((match.start(), [last_value(a) for a in split_arguments(match.group(1))]))
        return calls

    for group, selector in (
        ('PIViewImages18', 'updateImageContentsWithImage$imageAppearance$isRealContentsImage$animated$'),
        ('PIViewImages18', 'applyImageSublayer$animated$'),
        ('PIViewImages17', 'updateImageAnimated$')):
        parameters, body = function('_logos_method$'+group+'$SBIconImageView$'+selector)
        calls = original_calls(body, selector)
        expected = [last_value(a) for a in parameters]
        record(selector+' preserves every native argument',
               len(calls) == 1 and calls[0][1] == expected and
               len(expected) >= (3 if group == 'PIViewImages17' else 4))
        record(selector+' overlays only after native update',
               len(calls) == 1 and body.find('PIUpdatePhotoPresentation') > calls[0][0])

    for selector in ('setIcon$location$animated$', 'prepareForReuse'):
        parameters, body = function('_logos_method$PIViewImages$SBIconImageView$'+selector)
        calls = original_calls(body, selector)
        clear = body.find('PIClearPhotoPresentation')
        record(selector+' clears photo before native reuse/rebind',
               len(calls) == 1 and 0 <= clear < calls[0][0] and
               calls[0][1] == [last_value(a) for a in parameters])
        record(selector+' suppresses reentrant photo attachment',
               bool(re.search(r'objc_setAssociatedObject[^\n]*PIPhotoBindingKey[^\n]*i8\* %', body[:clear])) and
               'objc_setAssociatedObject' in body[calls[0][0]:] if calls else False)

    _, clear = function('PIClearPhotoPresentation')
    record('cleanup releases both per-view associations',
           all(re.search(r'objc_setAssociatedObject[^\n]*'+key+r', i8\* null', clear)
               for key in ('PIPhotoLayerKey', 'PIPhotoIdentifierKey')))
    _, update = function('PIUpdatePhotoPresentation')
    record('custom layer and app identifier are associated with the view',
           all(re.search(r'objc_setAssociatedObject[^\n]*'+key+r', i8\* (?:nonnull )?%', update)
               for key in ('PIPhotoLayerKey', 'PIPhotoIdentifierKey')))
    record('app binding is checked before and after image preparation',
           len(re.findall(r'(?:invoke|call)[^\n]*@[^\n]*PIIdentifierForImageView', update)) >= 2)
    record('no model-wide icon reload is emitted', 'c"reloadIconImage\\00"' not in ir)
    record('Clock native contentsImage remains unhooked',
           not any('_logos_method$PIClockImages$SBHClockApplicationIconImageView$contentsImage' in name
                   for name in functions))
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--theos', type=Path, required=True)
    args = parser.parse_args()
    checks = []
    with tempfile.TemporaryDirectory(prefix='photoicon-isolation-') as directory:
        source = Path(directory)/'Tweak.mm'
        with source.open('w') as output:
            subprocess.run(['perl', str(args.theos.resolve()/'bin/logos.pl'),
                            str(args.project.resolve()/'Tweak.xm')], stdout=output, check=True)
        for architecture in ('arm64', 'arm64e'):
            output = Path(directory)/(architecture+'.ll')
            subprocess.run([str(args.clang.resolve()), '-target', architecture+'-apple-ios17.0',
                            '-isysroot', str(args.sdk.resolve()), '-fobjc-arc', '-Os',
                            '-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror',
                            '-I', str(args.project.resolve()), '-I', str(args.theos.resolve()/'vendor/include'),
                            '-F', str(args.theos.resolve()/'vendor/lib'),
                            '-S', '-emit-llvm', str(source), '-o', str(output)], check=True)
            checks.extend(inspect(output.read_text(), architecture))
    success = all(check['pass'] for check in checks)
    print(json.dumps({'result': 'PASS' if success else 'FAIL', 'checks': checks,
                      'device_runtime_tested': False}, indent=2))
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())
