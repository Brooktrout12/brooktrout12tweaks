# Build and implementation notes

## Configuration

- Package and signature ID: `com.brooktrout12.ccfavorites`
- Name/version: CCFavorites 1.0.0
- Author and maintainer: brooktrout12
- Debian architecture: `iphoneos-arm64`
- Mach-O architectures: arm64 and arm64e
- Deployment target: iOS 18.0; runtime and package restricted to iOS 18.x
- Injection filter: `com.apple.springboard` only
- Theos revision: `5280bd038207e14f8bd76f5417aa2fe641c03228`
- Linux toolchain: L1ghtmann/llvm-project `test-210562a`, clang 11.1.0
- Public SDK: Theos iPhoneOS16.5.sdk, release `master-146e41f`
- arm64e converter: p0358/allemande `43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9`
- Signing: ldid, ad hoc, after ABI conversion

The public UIKit/Foundation/runtime APIs used by this tweak are available in
the 16.5 SDK. All private classes are resolved on the device and every private
message/hook is checked for its actual return and argument encodings. No private
framework binary or private C-function address is linked into the package.

## Build on macOS

Install Theos, ldid and an Xcode iOS SDK. In this source directory:

```sh
export THEOS=/path/to/theos
make clean package TARGET=iphone:clang:latest:18.0
```

The native Xcode arm64e toolchain uses the current ABI. Do not use the Linux
conversion wrapper with that toolchain.

## Build on Linux

Install the pinned toolchain under Theos's `toolchain/linux/iphone` and the SDK
under `sdks/iPhoneOS16.5.sdk`. Build allemande, then run:

```sh
export THEOS=/path/to/theos
export BT_ALLEMANDE=/path/to/allemande
export BT_LDID="$THEOS/toolchain/linux/iphone/bin/ldid"
./scripts/build-linux.sh
```

`sign-linux.sh` converts the final merged binary before signing. The linker's
old-arm64e-ABI warning precedes conversion. The delivered package does not depend
on an old-ABI compatibility package. Its constant-string metadata is converted
and its signed code pages are checked after conversion.

The implementation creates no Objective-C classes or block literals. Where
native page-navigation APIs accept a completion block, the original native
pointer is forwarded unchanged; it is neither invoked nor replaced by the tweak.
Delayed installation uses `dispatch_async_f` with a C callback.

Toolchain and SDK binaries are not included in the source archive. Pinned
download archive SHA-256 values:

```text
a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e  iOSToolchain-x86_64.tar.xz
5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb  iPhoneOS16.5.sdk.tar.xz
```

## Paging restriction

### Selector correction, with version kept at 1.0.0

The original `BTNamedKind` compared `class_getName(cls)` to the mangled Swift
names from the framework exports. Apple's Objective-C runtime implements
`class_getName` using `demangledName`, so it can return
`ControlCenterUI.IconListRootFolderView` where the export spelling is
`_TtC15ControlCenterUI22IconListRootFolderView`. These strings do not match.
That made folder/controller ownership checks false, bypassing selector hiding
and page-index enforcement. The separately targeted native scrolling gesture
could still be disabled independently of those restrictions.

`BTRuntimeClassMatch.h` now resolves the exported name with `objc_getClass` and
compares class identities through the superclass chain. It also handles runtime
subclasses and never caches an unavailable class. All existing ownership checks
use this one corrected predicate, including selector visibility, native scroll
ownership and programmatic page navigation. The working gesture hooks and the
package version are unchanged.

`tests/test_class_matching.c` runs the actual production predicate against a
small host runtime fixture. It exposes demangled display names while resolving
the mangled class aliases, demonstrating the old mismatch. It also checks
unrelated Home Screen/gallery classes, nil/missing classes, inheritance and a
late-load retry. The fixture uses only `tests/support/objc/runtime.h`; the tweak
build uses the real SDK runtime header and packages no test code.

### Native paging hooks

The iOS 18.6 ControlCenterUI export list provides these class names:

- `ControlCenterUI.IconListFolderView` and `IconListRootFolderView`
- `ControlCenterUI.IconListFolderController` and `IconListRootFolderController`
- `CCUIIconScrollView`, `CCUIPagingViewController`, `CCUIMainViewController`

The exported names of the Swift classes are resolved by identity in `Tweak.m`.
The folder paging selectors are taken from the iOS 18.2 SpringBoardHome runtime
headers. The CCUI classes' inheritance/overrides are resolved at runtime;
the build host does not prove which inherited hooks execute on iOS 18.6.
Unavailable methods or mismatched signatures are skipped.

`firstIconPageIndex` selects the native first icon page, which is Favorites in
the requested layout. Once that folder has populated list views, page requests
are constrained to its first index. Native initialization/teardown sentinels
are retained. Completion-bearing methods continue through the original native
implementation, preserving its completion handling.

The scroll offset comes from `_scrollOffsetForPageAtIndex:` rather than an
assumed zero. This respects native content insets, spacing and orientation.
Offset changes are intercepted on CCUI's folder/scroll-view classes only, and
an unlaid-out view retains its proposed offset until the native geometry exists.

The folder receives a unique scrolling-disabled reason. A native autoscroll
assertion is retained for the folder lifetime to prevent edit-mode edge paging.
Ordinary scroll enabling, pan scrolling and bouncing are disabled on the
folder's own scroll view. Setup is idempotent and layout application has a
reentrancy guard.

The exported `_pagingViewScrollPanGesture` ivar on `CCUIMainViewController` is
disabled, with a matching gesture-delegate guard where available. The distinct
presentation, dismissal and editing gesture recognizers are not altered.

The folder's complete page-control view is hidden, transparent, noninteractive
and hidden from accessibility. Shared `SBIconListPageControl` visibility hooks
require a live Control Center folder owner and its exact page-control identity.
Home Screen page dots pass through normally. There are no global UIView or
UIScrollView hooks.

No model page count, layout file, module configuration, glyph or corner radius
is changed. Other pages remain stored; removal restores their accessibility.
This tweak has no dependency on CC17Shapes and installs different files.

## Package checks

```sh
bash ./scripts/test-class-matching.sh
python3 scripts/verify_package.py packages/com.brooktrout12.ccfavorites_1.0.0_iphoneos-arm64.deb
```

The verifier checks package metadata, only the expected rootless dylib/filter
files, both device architectures, the deployment target, dependency paths,
relocated-rootless rpaths, converted arm64e string metadata and every signed code
page. It rejects custom Objective-C classes and block literals in the delivered
Linux build. Debug symbols for both slices are included under `debug/`.

These are host checks, not UIKit emulation. The corrected build still requires
an on-device check. See the short device check in `README.md`.

## Primary references

- [Apple Objective-C runtime: class_getName and Swift name demangling](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.mm)
- [Theos rootless packaging](https://theos.dev/docs/rootless)
- [iOS 18.6 ControlCenterUI exports](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS18.6.sdk/System/Library/PrivateFrameworks/ControlCenterUI.framework/ControlCenterUI.tbd)
- [iOS 18.2 SBFolderView runtime declarations](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBFolderView.h)
- [iOS 18.2 SBFolderController runtime declarations](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBFolderController.h)
- [iOS 18.2 SBIconScrollView runtime declarations](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBIconScrollView.h)
- [iOS 18.2 SBIconListPageControl runtime declarations](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBIconListPageControl.h)
- [Allemande ABI converter](https://github.com/p0358/allemande)
- [Linux iOS toolchain release](https://github.com/L1ghtmann/llvm-project/releases/tag/test-210562a)
- [Theos SDK release](https://github.com/theos/sdks/releases/tag/master-146e41f)
