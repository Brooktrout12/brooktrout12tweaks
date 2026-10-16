# Build and verification

## Delivered build

- Release: **1.1.1**, Debian package version `1.1.1`
- Package and code-signing identifier: `com.brooktrout12.photoicon`
- Author and maintainer: **Brooktrout12**
- Theos: `5280bd038207e14f8bd76f5417aa2fe641c03228`
- Linux iOS toolchain: L1ghtmann/llvm-project release `test-210562a`, clang 11.1.0
- SDK: Theos `iPhoneOS16.5.sdk`, release `master-146e41f`
- Deployment target: iOS 18.0 (all public APIs used are present in the 16.5 SDK)
- Architectures: arm64 and arm64e in each of two universal Mach-O dylibs
- Rootless package architecture: `iphoneos-arm64`
- arm64e metadata conversion: p0358/allemande,
  `43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9`
- Signing: ldid, ad-hoc SHA-256 CodeDirectories, after ABI conversion

The Linux linker reports the old arm64e ABI before conversion. The signing
wrapper runs allemande on the merged binary before ldid signs it. No system-wide
`oldabi` dependency is installed. The converter is a practical compatibility
workaround, not a substitute for a device test.

Dependency archive SHA-256 values:

```text
a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e  iOSToolchain-x86_64.tar.xz
5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb  iPhoneOS16.5.sdk.tar.xz
```

## Rebuild on macOS

With Xcode's iOS SDK, Theos, and ldid installed:

```sh
export THEOS=/path/to/theos
make clean package TARGET=iphone:clang:latest:18.0
```

Use the native Xcode arm64e toolchain on macOS; do not apply the Linux converter
to its already current-ABI output.

## Rebuild on Linux

Install the pinned toolchain and SDK into Theos, and compile allemande with
`g++ -std=c++20 -O2 -o allemande main.cpp` in its source directory. Then:

```sh
export THEOS=/path/to/theos
export PI_ALLEMANDE=/path/to/allemande
export PI_LDID="$THEOS/toolchain/linux/iphone/bin/ldid"
./scripts/build-linux.sh
```

The source archive intentionally excludes the toolchain and SDK binaries.

## Host checks

```sh
cc -std=c11 -O2 -Wall -Wextra -Werror tests/test_crop.c -lm -o /tmp/photoicon-test-crop
/tmp/photoicon-test-crop
python3 scripts/verify_package.py packages/com.brooktrout12.photoicon_1.1.1_iphoneos-arm64.deb
```

The unchanged crop test contains eight manually calculated cases, plus 17,200 boundary
cases covering portrait, landscape, panoramic, zoomed, resized, and overscrolled
viewports; it passed for the earlier builds and was not rerun for this app-icon coverage change. The package verifier checks rootless layout, the separate SpringBoard
and UIKit injection filters, both device architectures, deployment target, library
search paths, arm64e class metadata conversion, and every signed code page in all
four slices.

See `verification.json` for the exact final package hash and verification result.
`tests/check_callback_codegen.py` verifies all four callback setters for both
architectures against actual compiler-generated LLVM IR. This test fails all
eight checks against the shipped 1.0.0 source and passes all eight with this release.
`tests/check_system_blocks.py` additionally compiles the original four callback-using translation units
and all five new implementation files, including the Logos-generated hooks. It traces callback
arguments to the explicit runtime-copy result, checks that capturing blocks
are not marked noescape/global, audits the expected handoff counts, and checks
the helper itself. All 54 checks pass for this release, including both new
UIView animation callbacks and the existing bookmark callbacks on both architectures.
The 1.0.1 source fails this
regression check, including the picker-dismissal callback in both reports.
`system-block-verification.json` records these checks.
The audit previously accepted immutable global block inputs; that assumption
was wrong because `_Block_copy` returns them unchanged and ARC subsequently
releases their unsigned-isa objects. The corrected audit rejects both 1.0.2
startup observers on both architectures (four failing checks) and requires
genuinely copyable capturing blocks. Those historical baseline records are not
included in this renamed distribution.
All code-generation checks use the shipped build's `-Os` optimization level.
`tests/check_linked_callbacks.py` verifies the actual packaged binary against
UUID-matched dSYMs: all four callback setters, the runtime-copy helper, all 17
system-copy calls per architecture, and the picker method's copy call. The
bookmark UIAction and menu-provider wrapper copy calls are checked separately
in their corresponding function ranges, excluding block-invoke functions.
It also checks both runtime-copy calls in `-[PIEditorCoordinator closeAnimated]`.
It also verifies that both initializer copy calls receive stack-literal
addresses instead of global-literal pointers. All 22 linked-code checks pass
for this release. The initializer checks reject the packaged 1.0.2 binary.
See `linked-callback-verification.json` for the current build.

The beta 3 arm64e wrapper's indirect call into the original native provider was
also inspected in that build's binary: at offset `0xb7b4` it uses `blraa x9, x8`
with the block's invoke-field address as the authentication modifier. The
disassembly was retained with that development build, outside this distribution.
This checks the emitted instruction; it does not execute pointer authentication
or the UIKit callback on a device.

`tests/check_icon_isolation.py` compiles the actual Logos hooks for both
architectures and audits their LLVM IR. All 26 checks pass: native arguments
are forwarded unchanged, custom artwork is applied after native updates,
reuse/rebinding clears the owned layer before calling SpringBoard, reentrant
attachments are suppressed, and app identity is checked before and after
rendering. It also checks that model-wide image reloads and Clock's native
`contentsImage` override are absent. The exact 1.0.3 source fails these 26
structural checks in the earlier baseline comparison.
These are generated-code checks, not a reproduction of UIKit's runtime bug.
See `icon-isolation-verification.json` and `ICON-ISOLATION.md`.

The earlier crash diagnoses are documented in `CRASH-FIX.md`. The source archive
includes matching dSYM bundles under `debug/1.1.1` for this exact build. These
symbols are source-archive artifacts and are not installed by the .deb.
Version 1.0.0 was subsequently tested by the user on an iPhone 11 Pro running
iOS 18.6 with Dopamine 3.0.9 and crashed when opening the editor. Version 1.0.1
allowed the picker to open on that device, but selecting a photo and pressing
Cancel both crashed during picker dismissal. Version 1.0.2 addresses the shared
callback handoff failure, but its global notification callbacks introduced an
immediate startup crash on the user's device. Version 1.0.3 corrects that
specific regression while preserving the earlier editor fixes. The user has
now confirmed that 1.0.3 works without SpringBoard crashes, but reported a
temporary wrong-app display after changing an icon, corrected by a respring.
The subsequent 1.0 beta isolated per-view artwork; the user has now confirmed
that it works well with no observed bugs. The user then tested beta 2: app
editing still worked, but no bookmark action appeared. Beta 3 replaced the
suggestion-stage hook with a wrapper around the actual menu provider. The user
has now confirmed it works correctly. Release 1.0 removes the temporary trace
and adds an animated crop dismissal while retaining the icon and bookmark code.
The user subsequently reported that 1.0 works after a week of use. The user
confirmed the 1.1 icon coverage, then supplied a SpringBoard crash report.
The matched 1.1 symbols identify background layer configuration in
`PISharedImage`. Version 1.1.1 adds balanced explicit transactions to this
renderer and the two related detached-layer constructors. The authoring
environment cannot install or run the fix on the device.
The editing and dismissal code remains byte-for-byte identical to that 1.0
source. See `RELEASE-1.1.md` for the new integration points and limitations.

`tests/check_layer_transactions.py` compiles both changed translation units
for arm64 and arm64e at `-Os`. Its control-flow analysis follows normal and
exception edges and checks that all 50 layer call sites across the six compiled
functions execute within explicit transactions with actions disabled. It also
checks balanced exits and the absence of synchronous main-queue dispatch.
All six function checks pass; the same audit rejects the actual 1.1 source.
See `layer-transaction-verification.json`, `layer-transaction-baseline-1.1.json`,
and `CRASH-FIX-1.1.1.md`. This does not execute Core Animation or reproduce the
device's abort on the build host.

## Wider icon providers

`PhotoIcon.dylib` remains SpringBoard-only and owns editing, private storage,
folder miniatures, and SpringBoard image/layer hooks. `PhotoIconSystem.dylib`
loads into UIKit processes and is read-only. It has no custom Objective-C
classes or photo-picker dependency. Both binaries are signed after arm64e
metadata conversion; `verification.json` covers all four architecture slices.

The public cropped-icon cache is under the jailbreak root's
`var/mobile/Library/Caches/PhotoIcon`. The post-install script sets mobile
ownership on that directory only. The private source-photo directory is not
made public. The root is resolved from each dylib's actual load path.

`identity-verification.json` records package credits and the scan of package
and source contents. `coverage-verification.json` records implementation scope,
source preservation, exact-identity rendering, and interface-reference checks.
These checks do not execute iOS UI code or establish complete coverage of every
private call path. Any historical artifact paths in `CRASH-FIX.md` and
`ICON-ISOLATION.md` refer to earlier development archives.

The package identifier uses lowercase letters as required by the
[Debian package-name rules](https://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-source).

## Primary implementation references

- [Dopamine](https://github.com/opa334/Dopamine)
- [Theos rootless packaging and arm64e notes](https://theos.dev/docs/rootless)
- [iOS 18 runtime headers](https://github.com/qingralf/iOS18-Runtime-Headers)
- [allemande](https://github.com/p0358/allemande)
- [Linux iOS toolchain](https://github.com/L1ghtmann/llvm-project/releases/tag/test-210562a)
- [Theos SDKs](https://github.com/theos/sdks/releases/tag/master-146e41f)

The runtime declarations were checked against `SBIcon`, `SBIconView`,
`SBIconImageView`, `SBHBookmarkIcon`, `SBHBookmark`, `UIWebClip`,
`UIContextMenuConfiguration`, `SBHClockApplicationIconImageView`, and
`SBSApplicationShortcutItem` in the iOS 18 header repository. Source code for
PhotoIcon's UI, storage, image handling, and hooks was written for this task.

Additional interfaces for 1.1 were read from the iOS 18 runtime header source:
`ISIcon`, `ISConcreteIcon`, `ISBundleIdentifierIcon`, `ISApplicationIdentityIcon`,
`ISImageDescriptor`, `ISImage`/`IFImage`, `UIImage`, `SearchUIAppIconImage`,
`SBIcon`, `SBLeafIcon`, `SBHIconImageCache`, `SBFolderIconImageCache`,
`SBFolderIconImageSharedCache`, `UIActivity`, `SFUIActivityImageProvider`,
`LSApplicationIdentity`, and `LSApplicationExtensionRecord`.

The use of the jailbreak-root cache is grounded in Dopamine's
[existing process-check-in sandbox extensions](https://github.com/opa334/Dopamine/blob/main/BaseBin/launchdhook/src/jbserver/jbdomain_systemwide.c).
PhotoIcon does not issue extensions or change those permissions itself.
