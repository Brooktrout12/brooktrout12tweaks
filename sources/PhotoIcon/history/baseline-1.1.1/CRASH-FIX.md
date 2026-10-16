# PhotoIcon 1.0.3 — immediate startup regression

This document records the earlier crash fixes. The user has since confirmed
that 1.0.3 works without SpringBoard crashes. Its successor was named **1.0
beta** at the user's request and addressed a separate, temporary wrong-icon
display issue; see `ICON-ISOLATION.md`. The callback fixes below are retained.

## Startup report and exact cause

After installing 1.0.2 and respringing, the user could not reach the Home Screen
outside Safe Mode. The new report is `SpringBoard-2026-09-12-134317.ips`, from
the same iPhone 11 Pro on iOS 18.6 (22G86), Dopamine 3.0.9.

The report's arm64e PhotoIcon UUID is `1DA800EF-0DDA-3384-8DB8-034D51AEBE3F`,
matching the shipped 1.0.2 package and preserved dSYM. The main thread crashes
in `objc_msgSend`, with the selector `release` and `_NSConcreteGlobalBlock` in
the registers. The next frame is PhotoIcon offset `0x6E04` (28164), followed by
dyld initializer execution. Both `0x6E04` and the call instruction at `0x6E00`
symbolicate to `Tweak.xm:223`, the first notification-observer registration.

The 1.0.2 compatibility macro was applied to two capture-free notification
blocks. Clang therefore emitted static global block objects. `_Block_copy`
returns global blocks unchanged, so the macro's `__bridge_transfer` caused ARC
to release an object whose legacy global `isa` was still unsigned. This is the
startup regression; it occurs before the menu or picker can be tested.

The earlier audit explicitly allowed immutable globals. That was incorrect:
their unchanged identity does not make them safe for Objective-C lifetime
messages in this legacy-compiler/current-arm64e combination. The previous
host-check pass was not proof of runtime compatibility.

## Narrow 1.0.3 correction

Both startup observers now capture a local strong reference to the already
existing masked-image cache and use that reference to invalidate the cache.
This makes them capturing stack blocks, rather than globals, without adding
new runtime classes, hooks, notifications, settings, or storage migrations.
The existing compatibility helper now produces actual heap copies. Their
Objective-C ownership operations use metadata initialized by libclosure.
Notification delivery remains on `NSOperationQueue.mainQueue`.

The helper's contract now explicitly excludes global and noescape callbacks.
The compiler-IR audit rejects those arguments rather than allowing a global
exception. Both notification literals are checked for escaping/copyable flags
and the copied result is traced into the Objective-C callback argument.

The picker dismissal, item-provider completion, crop and icon renderers,
error handlers, storage handoffs, and four callback setters are unchanged.
The capture-free `dispatch_once` callbacks still use the C dispatch API, not
the Objective-C ownership macro; they are outside the changed failure path.

## 1.0.3 verification and remaining uncertainty

- Updated callback-handoff audit: all 36 checks pass for 1.0.3. On the exact
  1.0.2 source, the four startup observer/architecture checks fail.
- Stored callback setters: all eight checks still pass.
- Packaged machine code: all 16 checks pass for 1.0.3. The new startup checks
  fail on both slices of the actual 1.0.2 package, whose UUIDs match the reports.
- In the new arm64e initializer, the copy calls at `0x6CB8` and `0x6D80` receive
  `sp + 64` and `sp + 24`. Both results are passed to the notification API,
  then released. The helper calls `_Block_copy`; no global input is involved.
- Package architecture, iOS deployment target, rootless layout, SpringBoard
  filter, class metadata conversion, and all signature page hashes pass the
  package verifier. The exact package hash is recorded in `verification.json`.

These checks compare source and compiled code with the observed failure; they
do not execute iOS or emulate pointer authentication. The user subsequently
confirmed that 1.0.3 runs without SpringBoard crashes and can select and change
icons. The 1.0.3 verification records and matching dSYMs are preserved under
`debug/1.0.3`; the verification files at the project root describe the new beta.

No raw user crash reports are embedded in the source archive.

## Earlier 1.0.2 picker fix (introduced the startup regression above)

## New reports and shared cause

The user confirmed that 1.0.1 opened the Photos picker on the iPhone 11 Pro
running iOS 18.6 (22G86), Dopamine 3.0.9. Selecting an image or pressing Cancel
then sent SpringBoard into Safe Mode.

Both reports (`SpringBoard-2026-09-12-131746.ips` and
`SpringBoard-2026-09-12-131808.ips`) have the same faulting stack:

1. `objc_msgSend`, sending `retain` to `_NSConcreteStackBlock`.
2. `-[UIViewController dismissViewControllerAnimated:completion:] + 44`.
3. PhotoIcon image offset `0xEDA8` (60840).
4. `-[PHPickerViewController _finishPickingWithResults:]`.

Both report `EXC_BAD_ACCESS / SIGSEGV` with a possible pointer authentication
failure. Their arm64e UUID is `27E4FAEC-1600-3D8D-9F84-3F5E7788AECB`, matching
the shipped 1.0.1 binary and preserved dSYM. Symbolicating the call instruction
at `0xEDA4` gives `-[PIEditorCoordinator picker:didFinishPicking:]`,
`PIEditorCoordinator.m:185`, the picker-dismissal message.

Selection and cancellation share this dismissal callback. The callback has not
yet run when UIKit tries to retain it, so neither image decoding nor the empty
selection branch has been reached. This is a callback ABI handoff error, not
evidence of a faulty photo, permission denial, or two separate picker failures.

## 1.0.2 change

The 1.0.1 fix addressed the four callback property setters owned by PhotoIcon,
but was incomplete: directly passed stack callbacks could still reach UIKit
with the legacy compiler's unsigned block `isa`.

`PI_SYSTEM_BLOCK` now passes callbacks through an out-of-line C-pointer helper,
`PICopyBlockForSystem`, which calls `_Block_copy` before an Objective-C API
receives the block. Capturing stack blocks become runtime-initialized heap
blocks. The macro preserves the callback signature, evaluates its expression
once, and transfers the copy's +1 ownership to ARC. It does not send `copy` or
`retain` to the original stack block. The out-of-line boundary also prevents ARC
from removing the copy for synchronous/noescape APIs.

This covers the shared picker-dismissal callback, item-provider completion,
alert handlers, crop and icon image renderers, saved-manifest enumeration,
notification handlers, and storage completion handoffs. The notification blocks
incorrectly remained global; their new ARC release caused the subsequent startup
crash, corrected in 1.0.3 above. The four safe callback setters from 1.0.1 remain in place. Dispatch's C
block APIs already use the Blocks runtime; they are unchanged.

No system-wide hook, PAC disabling, exception swallowing, jailbreak modification,
or user-photo migration is introduced.

## 1.0.2 verification and limits

- The callback-property regression check still passes all eight checks.
- `check_system_blocks.py` passes 36 checks across arm64 and arm64e: 26 callback
  handoffs, eight per-file coverage checks, and two runtime-helper checks.
- The new audit rejects the shipped 1.0.1 source, including the exact failing
  dismissal handoff on both architectures. Its baseline output is preserved in
  `debug/1.0.1/system-block-verification.json`.
- Optimized IR confirms that the copy result, not the original stack pointer,
  is the argument delivered to each protected Objective-C call. Capturing
  literals are also checked for noescape/global flags that would prevent copying.
- The linked arm64e picker method calls the helper at `0xED20`, moves its result
  into the completion argument, then calls UIKit at `0xED3C`. The helper at
  `0x105F0` branches to the `_Block_copy` import.
- `check_linked_callbacks.py` passes all 14 packaged-machine-code checks for
  the two architectures, including all 13 system-copy calls per slice.
- The rootless package verifier checks both Mach-O slices, deployment target,
  dependencies, SpringBoard-only injection, converted class metadata, and every
  SHA-256 code-signature page. See `verification.json` for the package hash.

These were the host checks at the time of the 1.0.2 release. They missed the
unsafe global-block ownership case. The user's subsequent device test revealed
the startup regression documented above. Do not install 1.0.2 again.

Matching dSYMs for 1.0.2 and the previous builds are included. The source archive
does not contain the user's raw crash reports.

## Earlier 1.0.1 editor-opening diagnosis

### Evidence

The user reported that the Change Icon menu appeared but selecting it put
SpringBoard into Safe Mode on an iPhone 11 Pro running iOS 18.6 (22G86),
with Dopamine 3.0.9.

The supplied report contains `EXC_BAD_ACCESS / SIGSEGV` and a possible pointer
authentication failure involving `_NSConcreteStackBlock`. The crashed thread
calls `objc_msgSend` from `objc_setProperty_nonatomic_copy`, followed by two
PhotoIcon frames.

PhotoIcon's arm64e UUID in the report is
`8120F649-63B4-391E-9869-4162CFF7341E`, matching the delivered 1.0.0 binary and
its preserved dSYM. Symbolication of the return addresses, adjusted to their
call instructions, resolves to:

| Image offset | Symbol | Source in 1.0.0 |
| --- | --- | --- |
| `0xE4F4` | `-[PIEditorCoordinator editBundleIdentifier:fromIconView:cornerRatio:useSavedPhoto:]` | `PIEditorCoordinator.m:141`, assigning `host.onReady` |
| `0x8F70` | `PIOpenEditor` dispatch callback | `Tweak.xm:80` |

The registers identify `copyWithZone:` and `_NSConcreteStackBlock`. Inspection
of the matching machine code shows the compiler storing the raw stack-block
class pointer before passing that block to the synthesized property setter.
That setter uses generic Objective-C copy messaging on a block whose legacy
ABI `isa` field is not yet valid for that message dispatch on this device.

### Change

The four callback properties retain their copy contract. Their setters now
explicitly assign to strongly owned, block-typed ivars under ARC. The compiler
emits `objc_retainBlock` for this operation, which uses the Blocks runtime copy
path. It copies an escaping stack block to the heap and initializes its object
metadata without first sending `copyWithZone:` to the incoming stack block.

The affected callbacks are `onReady`, `onSave`, `onCancel`, and `onChoosePhoto`.
Pointer authentication remains enabled. The update does not introduce a
system-wide compatibility shim, patch libobjc, or suppress crash signals.

### Verification at the time of the 1.0.1 release

`tests/check_callback_codegen.py` compiles the actual two callback-owning source
files for arm64 and arm64e, then examines every callback setter. It requires a
Blocks-runtime copy operation and rejects generic property-copy calls or
Objective-C message dispatch in those setters.

- Shipped 1.0.0 source: all eight architecture/setter checks fail.
- Updated 1.0.1 source: all eight checks pass.
- Final linked setter machine code: checked for calls to `objc_retainBlock`.
- Rootless package layout, deployment target, both Mach-O slices, converted
  arm64e class metadata, and signed code pages: checked by the package verifier.

The user subsequently confirmed that this change allowed the picker to open.
The follow-up selection/cancellation crashes and the 1.0.2 correction are
documented above.

## Technical references

- [Clang ARC block ownership semantics](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#blocks)
- [Clang arm64e block and Objective-C pointer authentication](https://clang.llvm.org/docs/PointerAuthentication.html#blocks)
- [Apple libclosure Blocks runtime](https://github.com/apple-oss-distributions/libclosure/blob/main/runtime.cpp)

These references support the runtime-copy mechanism. The diagnosis itself is
based on the uploaded crash reports and the UUID-matched PhotoIcon binaries.
