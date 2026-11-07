# Build and implementation notes

## Delivered configuration

- Package/signature identifier: `com.brooktrout12.cc17shapes`
- Author and maintainer: `brooktrout12`
- Version: `1.0.3`
- Deployment target: iOS 18.0; runtime and package restricted to iOS 18.x
- Mach-O architectures: arm64 and arm64e
- Debian architecture: `iphoneos-arm64`
- Theos revision: `5280bd038207e14f8bd76f5417aa2fe641c03228`
- Linux toolchain: L1ghtmann/llvm-project `test-210562a`, clang 11.1.0
- SDK used to compile public API calls: Theos iPhoneOS16.5.sdk, `master-146e41f`
- arm64e conversion: p0358/allemande `43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9`
- Signing: ldid, ad-hoc, after conversion

The older public SDK is sufficient for the UIKit, QuartzCore and Objective-C
runtime APIs used here. Private classes are resolved dynamically on the device;
no private-framework stubs or guessed C-function signatures are linked.

## macOS

Install Theos, ldid and an Xcode iOS SDK, then run from this source directory:

```sh
export THEOS=/path/to/theos
make clean package TARGET=iphone:clang:latest:18.0
```

The native Xcode arm64e toolchain already uses the current ABI. The Linux
conversion wrapper is not used for this build route.

## Linux

Install the pinned Linux toolchain in Theos's `toolchain/linux/iphone` directory
and the 16.5 SDK in `sdks/iPhoneOS16.5.sdk`. Build allemande, then run:

```sh
export THEOS=/path/to/theos
export BT_ALLEMANDE=/path/to/allemande
export BT_LDID="$THEOS/toolchain/linux/iphone/bin/ldid"
./scripts/build-linux.sh
```

This wrapper runs the geometry tests, builds both slices, then converts the
merged Mach-O before signing it. The linker's warning
about the old arm64e ABI occurs before conversion. The package has no `oldabi`
dependency. The implementation contains no custom Objective-C classes or
Objective-C blocks, avoiding the block handoff issues of this older toolchain.
Delayed hook installation uses `dispatch_async_f` and a C callback.

The source archive excludes downloaded SDK/toolchain binaries. Pinned archive
SHA-256 values:

```text
a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e  iOSToolchain-x86_64.tar.xz
5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb  iPhoneOS16.5.sdk.tar.xz
```

## Checks

```sh
bash scripts/test-geometry.sh
python3 scripts/verify_package.py packages/com.brooktrout12.cc17shapes_1.0.3_iphoneos-arm64.deb
```

The package verifier checks both device slices, iOS minimum version, rootless
paths, SpringBoard-only injection, author/package identifiers, converted arm64e
constant-string metadata and every signed code page. It does not emulate UIKit or verify a visual
result. The geometry test checks equal radii across small/wide/tall/large modules,
separate gallery scaling, sharp fill boundaries, invalid metrics and idempotence
across nested setters and changes in the base cell size.

## Consistent corners in 1.0.2

The preceding circular-only policy intentionally left rounded rectangles,
large platters and sliders unchanged. The new policy accepts finite control
surfaces from 12 points on the shorter side to 2048 points on the longer side.
For an existing positive finite radius, the result is one quarter of the smaller
of the surface's shorter side and its grid's single-cell side. Zero or negative
radii are preserved, as are invalid dimensions/metrics.

The main and gallery base `iconImageInfo` getters supply independent grid-cell
sizes. Grid-size-specific image info and the outer module controllers use that
same base, rather than the large module's width. Views resolve the nearest native
`SBIconListView.layout` and accept only the exact Control Center main/gallery
layout classes or their subclasses. A per-layout guard prevents recursive base
and grid-size metric queries. Before native metrics are available, the defaults
are 68 points for the main grid and 56 for gallery previews. Later native base
getter calls replace those defaults; no timer or global view hook is involved.
These fallbacks are implementation defaults, not a claim of an exact Apple
constant on every display configuration.

Layer-based surfaces use Core Animation's continuous corner curve. The tweak
keeps the successful single-control proportion; the important correction is
that a 2x2 panel uses the same corner radius as its 1x1 neighbor.

## Connectivity exception

`BTInConnectivityGroup` continues to inspect the live responder chain and
controller parents for the grouped connectivity module (`CCUIConnectivity*` /
`ConnectivityModule` classes or its module identifier). It does not classify
standalone controls by a Wi-Fi/AirDrop title or glyph.

The presentation exception is narrowed to `CCUIRoundButton` and
`CCUILabeledRoundButton` subtrees inside that group. The outer group platter
and its material are now eligible for the shared corner rule. Native round-button
getters/setters and completed layout still restore a circular radius if a button
was first constructed before its connectivity owner was known. The native setter
updates the normal, highlighted and selected backgrounds.

## Sliders

ABI-checked hooks on `CCUIBaseSliderView.continuousSliderCornerRadius` and the
base, continuous and stepped slider setters provide the shared grid radius.
Completed slider layout, attachment and elastic layout correct any radius assigned
before Control Center ancestry was known. A reentrancy guard protects native
setter/layout callbacks. Every original implementation runs.

These hooks require live Control Center ancestry. The native slider setter
updates the background, elastic content and clipping surfaces. Generic view,
layer and shared-material shape rewriting explicitly skips slider subtrees so
partial fills are not mistaken for small rounded modules. The native slider
retains its value, gestures, flat fill boundary and elasticity behavior.

## Flashlight correction in 1.0.3

`CCUISteppedSliderView` overrides `setContinuousSliderCornerRadius:` separately
from `CCUIContinuousSliderView`. Version 1.0.2 hooked the base and continuous
implementations only, so a stepped override could retain the incoming native
radius for its own content while the base hook corrected the background.
The new hook adjusts the argument before the stepped override runs, so both
implementations receive the same value.

Completed stepped elastic layout, `_layoutStepViews` and window attachment
also call the guarded slider refresh. A stepped control gets an explicit first
refresh even if its base radius already equals the target. Later refreshes
check for a changed target or a positive mismatched corner radius on the exact
`_stepViewsContainer`. The native setter remains responsible for the step views,
separators and clipping; individual brightness segments are not restyled by the
generic shape walker. The refresh shares the existing slider reentrancy guard.

## Focus first-layout correction in 1.0.3

`FCUIActivityControl` supplies `_cornerRadiusForControlFrame:`. Its hook uses the
incoming frame and the shared grid policy, so a reused compact DND control does
not supply its previous pill radius when its larger Focus row is being laid out.
The original method still executes.

The exact control's layout, superview/window attachment and background creation
also refresh its outer surface, `_backgroundView` and `_contentView`. This work
is guarded and limited to those surfaces. The background class's continuous and
ordinary radius setters also receive the shared radius. Glyphs, text, options
buttons, menu actions and activity state are not changed by these new hooks.
The spelling `_configureBackgroundViewIfNecesssary` (three consecutive s's) is
copied from the runtime declaration; all hooks still validate the actual ABI.

Focus changes require live Control Center ancestry or containment in an exact
`CCUIContentModuleContainerViewController` / `CCUIControlHostViewController` class
(or subclass). Responder and controller walks are bounded. A detached view is
not permanently marked as owned, preventing stale ownership on reuse elsewhere.

The new declarations come from the iOS 18.2 ControlCenterUIKit and FocusUI dumps.
The relevant classes and backing ivars are also present in the iOS 18.6 exports.
This supports the hook selection, but cannot establish its runtime behavior
on a physical device. Both 1.0.3 corrections still require device review.

## Shape handling

Control Center's own `SBIconImageInfo` geometry is corrected at its main and
gallery layouts and module containers. This lets native editing chrome and
previews consume the same shape. Separate scalar hooks cover
`CCUIControlHostView`, `CCUIControlTemplateView`, `CCUIButtonModuleView`,
`CCUIRoundButton`, the native content container and slider radius APIs.

Layout passes also adjust native backgrounds and full circular shape masks.
The view walk is bounded and excludes image views, labels, glyphs, progress
views, badges and resize handles. A candidate shape path must be one closed
circle covering the background, with no partial stroke or dash pattern.
Multi-path rings and smaller glyph paths are rejected. Shape-mask replacements
use a rounded-rectangle Bezier path; layer-based backgrounds use the native
continuous corner curve.

There are no hooks on global UIView or CALayer methods. The shared
`MTMaterialView` hooks check their live Control Center ancestry. Objective-C
method hooks are installed only after the actual method's return and argument
encodings match; each replacement has its own typed original pointer.
The dyld callback queues a coalesced main-thread retry for late-loaded classes.

Some ControlCenterUI method names are compatibility candidates based on prior
headers and iOS 18.6 exported ivars. Their availability is checked at runtime.
The source does not claim that host checks prove these hooks all execute on
iOS 18.6. Device review should cover main controls, editing/resizing, the gallery,
connectivity expansion, brightness/volume expansion and Now Playing/AirPlay.

## Primary references

- [Dopamine releases](https://github.com/opa334/Dopamine/releases/tag/3.0.9)
- [Theos rootless packaging and arm64e requirements](https://theos.dev/docs/rootless)
- [iOS 18.2 runtime headers](https://github.com/qingralf/iOS18-Runtime-Headers)
- [Native slider radius declarations](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/ControlCenterUIKit.framework/CCUIBaseSliderView.h)
- [Stepped slider corner/layout declarations](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/ControlCenterUIKit.framework/CCUISteppedSliderView.h)
- [Focus row corner calculation](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/FocusUI.framework/FCUIActivityControl.h)
- [Focus row background setters](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/FocusUI.framework/_FCUIActivityControlBackgroundView.h)
- [iOS 18.6 FocusUI exports](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS18.6.sdk/System/Library/PrivateFrameworks/FocusUI.framework/FocusUI.tbd)
- [Continuous slider clipping/layout declarations](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/ControlCenterUIKit.framework/CCUIContinuousSliderView.h)
- [Native icon-list layout access](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBIconListView.h)
- [iOS 18.6 ControlCenterUI exported classes and ivars](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS18.6.sdk/System/Library/PrivateFrameworks/ControlCenterUI.framework/ControlCenterUI.tbd)
- [iOS 18.6 ControlCenterUIKit exports](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS18.6.sdk/System/Library/PrivateFrameworks/ControlCenterUIKit.framework/ControlCenterUIKit.tbd)
- [iOS 18.6 ControlCenterUIServices exports](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS18.6.sdk/System/Library/PrivateFrameworks/ControlCenterUIServices.framework/ControlCenterUIServices.tbd)
- [Theos SBIconImageInfo structure](https://github.com/theos/headers/blob/master/SpringBoard/SBIconImageInfo.h)
- [Legacy ControlCenterUI runtime declarations](https://github.com/nst/iOS-Runtime-Headers/tree/master/PrivateFrameworks/ControlCenterUI.framework)
- [allemande converter](https://github.com/p0358/allemande)
- [Linux iOS toolchain release](https://github.com/L1ghtmann/llvm-project/releases/tag/test-210562a)
- [Theos SDK release](https://github.com/theos/sdks/releases/tag/master-146e41f)
