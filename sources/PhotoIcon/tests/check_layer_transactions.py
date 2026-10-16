#!/usr/bin/env python3
"""Audit transaction state along compiled icon-rendering control-flow paths.

The shipped 1.1 sources fail this check: their CALayer creation and mutations
are reachable without an explicit transaction. This is compiler-IR validation,
not execution of Core Animation; device confirmation remains necessary.
"""
import argparse
from collections import deque
import json
from pathlib import Path
import re
import subprocess
import tempfile

from check_system_blocks import split_arguments, last_value


LAYER_MESSAGES = {
    'layer', 'setBounds:', 'setContents:', 'setContentsGravity:',
    'setContentsScale:', 'setMasksToBounds:', 'setCornerCurve:',
    'setCornerRadius:', 'renderInContext:', 'setName:', 'setAnchorPoint:',
    'setPosition:', 'setTransform:', 'setOpacity:', 'setHidden:',
}


def inspect(ir, filename, architecture):
    names = dict(re.findall(r'^(@OBJC_METH_VAR_NAME_[\w.]*) = .*?c"(.*?)\\00"', ir, re.M))
    selectors = {}
    for line in ir.splitlines():
        match = re.match(r'(@OBJC_SELECTOR_REFERENCES_[\w.]*) = ', line)
        name = re.search(r'@OBJC_METH_VAR_NAME_[\w.]*', line)
        if match and name:
            selectors[match.group(1)] = names[name.group(0)]
    results = []
    for function in re.finditer(r'^define[^\n]*@([\w.]+)\([^\n]*\{\n(.*?)^\}', ir, re.M | re.S):
        name, body = function.groups()
        definitions = dict(re.findall(r'^\s*(%[\w.]+) = (.*)$', body, re.M))
        messages = {}
        blocks = {}
        current = 'entry'
        for line in body.splitlines():
            label = re.match(r'^([\w.-]+):', line)
            if label:
                current = label.group(1)
            blocks.setdefault(current, []).append(line)
            if '@objc_msgSend ' not in line:
                continue
            call = re.search(r'\*\)\((.*)\)(?:,| #|$)', line)
            if not call:
                raise AssertionError('Unrecognized Objective-C call: ' + line)
            args = split_arguments(call.group(1))
            definition = definitions.get(last_value(args[1]), '')
            ref = re.search(r'@OBJC_SELECTOR_REFERENCES_[\w.]*', definition)
            if ref:
                messages[line] = (selectors[ref.group(0)], args)
        if not any(selector in LAYER_MESSAGES for selector, _ in messages.values()):
            continue
        pending = deque([(next(iter(blocks)), ())])
        visited = set()
        checked_messages = set()
        failures = set()
        balanced_exits = set()
        while pending:
            label, state = pending.popleft()
            if (label, state) in visited:
                continue
            visited.add((label, state))
            stack = list(state)
            lines = blocks[label]
            for line in lines:
                selector, args = messages.get(line, ('', []))
                if selector == 'begin':
                    stack.append(False)
                    if len(stack) > 4:
                        failures.add('Unbounded transaction nesting')
                        break
                elif selector == 'setDisableActions:':
                    if not stack or not re.search(r'\bi(?:1|8) (?:zeroext )?(?:1|true)$', args[2]):
                        failures.add('Actions not disabled inside explicit transaction')
                    else:
                        stack[-1] = True
                elif selector == 'commit':
                    if not stack:
                        failures.add('Commit without matching begin')
                    else:
                        stack.pop()
                elif selector in LAYER_MESSAGES:
                    checked_messages.add((label, selector))
                    if not stack or not stack[-1]:
                        failures.add(f'{selector} reachable without explicit non-animating transaction')
                if re.match(r'\s*(ret |resume )', line):
                    if stack:
                        failures.add('Exit with uncommitted transaction')
                    else:
                        balanced_exits.add(label)
            if len(stack) <= 4:
                # Includes the normal and exception edges of each invoke.
                targets = re.findall(r'\blabel %([\w.-]+)', '\n'.join(lines))
                pending.extend((target, tuple(stack)) for target in targets)
        results.append({'architecture': architecture, 'file': filename, 'function': name,
                        'layer_call_sites_checked': len(checked_messages),
                        'balanced_exit_blocks': len(balanced_exits),
                        'failures': sorted(failures), 'pass': not failures and bool(checked_messages)})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--theos', type=Path, required=True)
    args = parser.parse_args()
    checks = []
    with tempfile.TemporaryDirectory(prefix='photoicon-transactions-') as temporary:
        for architecture in ('arm64', 'arm64e'):
            for filename in ('PISystemIconReader.m', 'PISpringBoardImages.m'):
                output = Path(temporary)/f'{architecture}-{filename}.ll'
                subprocess.run([str(args.clang.resolve()), '-target', f'{architecture}-apple-ios17.0',
                    '-isysroot', str(args.sdk.resolve()), '-fobjc-arc', '-Os', '-fno-discard-value-names',
                    '-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror',
                    '-I', str(args.project.resolve()), '-I', str(args.theos.resolve()/'vendor/include'),
                    '-F', str(args.theos.resolve()/'vendor/lib'),
                    '-S', '-emit-llvm', str(args.project.resolve()/filename), '-o', str(output)], check=True)
                ir = output.read_text()
                found = inspect(ir, filename, architecture)
                assert found, f'No layer paths inspected in {filename} ({architecture})'
                assert '@dispatch_sync' not in ir, 'Renderer must not synchronously wait for the main queue'
                checks.extend(found)
    success = all(check['pass'] for check in checks)
    print(json.dumps({'result': 'PASS' if success else 'FAIL', 'checks': checks,
                      'device_runtime_tested': False}, indent=2))
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())
