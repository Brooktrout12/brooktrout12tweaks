#!/usr/bin/env python3
"""Trace framework callback arguments to explicit Blocks-runtime copies in IR.

Compiles the actual sources, including the Logos-generated Objective-C++ hooks,
for both architectures. Checks data flow, not just the presence of a copy call.
The original 1.0.1 source and the startup-crashing 1.0.2 source fail these
checks. In particular, a global literal is never accepted as a normalized
callback: _Block_copy returns globals unchanged. No iOS runtime is executed.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import tempfile


EXPECTED = {
    'PIEditorCoordinator.m': {
        'actionWithTitle:style:handler:': 2,
        'dismissViewControllerAnimated:completion:': 1,
        'loadFileRepresentationForTypeIdentifier:completionHandler:': 1,
        'saveImage:source:crop:forBundleIdentifier:completion:': 1,
        'removeIconForBundleIdentifier:completion:': 1,
        'animateWithDuration:delay:options:animations:completion:': 2,
    },
    'PICropViewController.m': {'imageWithActions:': 1},
    'PIStore.m': {'enumerateKeysAndObjectsUsingBlock:': 1, 'finish:identifier:completion:': 2},
    'Tweak.xm': {'imageWithActions:': 1, 'addObserverForName:object:queue:usingBlock:': 2,
                 'actionWithTitle:image:identifier:handler:': 1, 'setActionProvider:': 1},
    'PISharedPaths.m': {},
    'PIIconPublisher.m': {},
    'PISpringBoardImages.m': {},
    'PISystemIconReader.m': {},
    'PISystemIcons.m': {},
}
STORED_CALLBACKS = {'setOnReady:', 'setOnSave:', 'setOnCancel:', 'setOnChoosePhoto:'}


def split_arguments(arguments):
    depth, start, result = 0, 0, []
    for i, char in enumerate(arguments):
        if char in '([{<':
            depth += 1
        elif char in ')]}>':
            depth -= 1
        elif char == ',' and depth == 0:
            result.append(arguments[start:i].strip())
            start = i + 1
    result.append(arguments[start:].strip())
    return result


def last_value(expression):
    match = re.search(r'(%[\w.]+|null)$', expression)
    return match.group(1) if match else None


def inspect_ir(ir, filename, architecture):
    names = dict(re.findall(r'^(@OBJC_METH_VAR_NAME_[\w.]*) = .*?c"(.*?)\\00"', ir, re.M))
    selectors = {}
    for line in ir.splitlines():
        match = re.match(r'(@OBJC_SELECTOR_REFERENCES_[\w.]*) = ', line)
        if match:
            name = re.search(r'@OBJC_METH_VAR_NAME_[\w.]*', line)
            if name:
                selectors[match.group(1)] = names[name.group(0)]
    results, counts = [], Counter()
    for function in re.finditer(r'^define[^\n]*\{\n(.*?)^\}', ir, re.M | re.S):
        body = function.group(1)
        definitions = dict(re.findall(r'^\s*(%[\w.]+) = (.*)$', body, re.M))

        def origin(value):
            seen = set()
            while value in definitions and value not in seen:
                seen.add(value)
                definition = definitions[value]
                if not definition.startswith('bitcast '):
                    break
                value = last_value(definition.split(' to ')[0])
            return value

        def copied(value):
            return '@PICopyBlockForSystem(' in definitions.get(origin(value), '')

        for line in body.splitlines():
            if '@objc_msgSend ' not in line:
                continue
            call = re.search(r'\*\)\((.*)\)(?:,| #|$)', line)
            if not call:
                continue
            arguments = split_arguments(call.group(1))
            if len(arguments) < 3:
                continue
            selector_load = definitions.get(last_value(arguments[1]), '')
            selector_ref = re.search(r'@OBJC_SELECTOR_REFERENCES_[\w.]*', selector_load)
            if not selector_ref:
                continue
            selector = selectors.get(selector_ref.group(0), '')
            # Discover block-typed Objective-C arguments independently of the
            # expected list, so newly added unprotected handoffs are rejected.
            block_args = [a for a in arguments[2:] if re.search(r'\([^)]*\)\* ', a)]
            if selector in STORED_CALLBACKS:
                continue  # Verified separately by check_callback_codegen.py.
            for argument in block_args:
                value = last_value(argument)
                if value == 'null':
                    continue
                counts[selector] += 1
                copy_ok = copied(value)
                input_kind, escapes = 'unprotected', False
                if copy_ok:
                    copy_def = definitions[origin(value)]
                    copy_argument = re.search(r'@PICopyBlockForSystem\(i8\* (?:nonnull )?(.*?)\)', copy_def)
                    raw = origin(last_value(copy_argument.group(1))) if copy_argument else None
                    if raw and definitions.get(raw, '').startswith('alloca '):
                        input_kind = 'capturing stack block'
                        # A noescape/global flag would make _Block_copy a no-op.
                        # Find this block's flags field and its initialization.
                        for target, definition in definitions.items():
                            if (definition.startswith('getelementptr ') and
                                    re.search(re.escape(raw) + r', i64 0, i32 1$', definition)):
                                flags = re.search(r'store i32 (-?\d+), i32\* ' + re.escape(target) + r'[, ]', body)
                                if not flags:
                                    for alias in definitions:
                                        if alias != target and origin(alias) == target:
                                            flags = re.search(r'store <2 x i32> <i32 (-?\d+), i32 0>, <2 x i32>\* ' + re.escape(alias) + r'[, ]', body)
                                            if flags:
                                                break
                                if flags:
                                    escapes = not (int(flags.group(1)) & ((1 << 23) | (1 << 28)))
                    elif copy_argument and '@__block_literal_global' in copy_argument.group(1):
                        input_kind, escapes = 'unsafe global block: copy returns original', False
                    elif raw and definitions.get(raw, '').startswith('load '):
                        # A captured/forwarded callback is already an escaping
                        # block, rather than a fresh noescape stack literal.
                        input_kind, escapes = 'forwarded callback', True
                results.append({'architecture': architecture, 'file': filename,
                                'selector': selector, 'runtime_copy_is_argument': copy_ok,
                                'input_kind': input_kind, 'copy_not_elided_or_noescape': escapes,
                                'pass': copy_ok and escapes})
    results.append({'architecture': architecture, 'file': filename,
                    'expected_handoffs': EXPECTED[filename], 'observed_handoffs': dict(counts),
                    'pass': counts == Counter(EXPECTED[filename])})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--theos', type=Path, required=True)
    args = parser.parse_args()
    args.project = args.project.resolve()
    results = []
    with tempfile.TemporaryDirectory(prefix='photoicon-system-blocks-') as directory:
        temporary = Path(directory)
        generated = temporary/'Tweak.mm'
        with generated.open('w') as output:
            subprocess.run(['perl', str(args.theos.resolve()/'bin/logos.pl'),
                            str(args.project/'Tweak.xm')], stdout=output, check=True)
        for architecture in ('arm64', 'arm64e'):
            common = [str(args.clang.resolve()), '-target', f'{architecture}-apple-ios17.0',
                      '-isysroot', str(args.sdk.resolve()), '-fobjc-arc', '-Os',
                      '-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror',
                      '-I', str(args.project), '-I', str(args.theos.resolve()/'vendor/include'),
                      '-F', str(args.theos.resolve()/'vendor/lib'),
                      '-S', '-emit-llvm']
            for filename in EXPECTED:
                source = generated if filename == 'Tweak.xm' else args.project/filename
                output = temporary/f'{architecture}-{filename}.ll'
                subprocess.run([*common, str(source), '-o', str(output)], check=True)
                results.extend(inspect_ir(output.read_text(), filename, architecture))
            helper = args.project/'PIBlockCompatibility.m'
            valid_helper = False
            if helper.is_file():
                output = temporary/f'{architecture}-helper.ll'
                subprocess.run([*common, str(helper), '-o', str(output)], check=True)
                ir = output.read_text()
                valid_helper = bool(re.search(r'call[^\n]*@_Block_copy\(', ir)) and '@objc_msgSend' not in ir
            results.append({'architecture': architecture, 'helper_calls_c_blocks_runtime': valid_helper,
                            'pass': valid_helper})
    success = all(result['pass'] for result in results)
    print(json.dumps({'result': 'PASS' if success else 'FAIL', 'checks': results,
                      'device_runtime_tested': False}, indent=2))
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())
