# CCNoRecent 1.0.0

Hides the camera/microphone activity row at the top of Control Center,
including its icons, app name, “recently” text and disclosure arrow.

For rootless jailbreaks on **iOS 17 and 18**.
The DEB contains both arm64 and arm64e slices.

## Install

Open `CCNoRecent_1.0.0_rootless.deb` in your package manager, install and
respring. It is enabled automatically; there is no Settings pane or dependency
on BlurSleep. Uninstall and respring to restore the standard activity row.

## Scope

This hides the whole Control Center attribution control, for both current and
recent activity. Other items represented by that same control (such as location,
Game Mode or inactive microphone mode selection on some versions) are hidden
with it. It does not change the Control Center module grid or the carrier,
Wi-Fi, battery, edit, power or dismiss controls.

It changes the visibility of the Control Center views. It does not intercept
camera/microphone access, permission checks, sensor activity records or the
status bar's green/orange privacy indicators outside this row.

## Implementation

- Hooks the concrete `CCUISensorAttributionCompactControl` and
  `CCUIPrivacyAttributionButton` classes, when present. Their own visibility
  setters enforce hidden/zero alpha. Window attachment and layout also disable
  interaction and accessibility for the hidden controls.
- Reapplies suppression through the verified child accessors of
  `CCUIHeaderPocketView`, and reports that this header is not displaying sensor
  status. Normal header layout still runs.
- Checks class inheritance, method argument counts and return/argument types
  before installing hooks. Private frameworks and classes are resolved at
  runtime, not linked into the binary.
- Watches for late-loaded frameworks with a coalesced dyld callback. Discovery
  and hooking happen on the main queue, outside the loader callback. There is
  no polling timer, background worker, network request or screenshot capture.
- Injects only into SpringBoard, on iOS 17 or 18.

## Validation

The build and package audit check both architectures, iOS 17 deployment target,
rootless paths, dependencies, hook symbols, the SpringBoard-only injection filter,
arm64e conversion and every ad-hoc signature page. See `validation/`.

**Not tested on a connected iPhone or simulator.** Check Camera → close Camera →
open Control Center, then repeat after using a microphone app. Also reopen
Control Center after rotating the phone. The activity row should stay hidden.

If the row remains, send the log from Filza:
`/var/mobile/Library/Logs/CCNoRecent.log`.
It records the OS, installed hook classes and first observed header/control,
not app names, sensor history or media. Log size is bounded at approximately
32 KiB. An absent or incompatible class is skipped and logged.

## Interface provenance

The inspected ControlCenterUI headers from
[userlandkernel/ios17-dyld-headers](https://github.com/userlandkernel/ios17-dyld-headers/tree/89931f35a750ed18297df97f009524ed37e60d67/ControlCenterUI)
identify their actual binary as **iOS 18.2, LC_SOURCE_VERSION 600.2.15.0.0**,
despite the repository's name and description. They establish the two controls,
their header owner and its child accessors. They are not an exact 18.x device
dump; runtime checks still apply. The iOS 17 target uses the compact-control
hooks with the same inheritance and ABI checks; it has not been verified on
17.x hardware. No private method implementation or Apple binary is
redistributed in this source bundle.

## Build

Use Theos with an iPhoneOS SDK, Substrate headers/library and `ldid`.
On a current macOS arm64e toolchain, run `make package` and adjust the SDK
portion of `TARGET` if needed.

For the supplied Linux build method, set `THEOS`, `BT_ALLEMANDE` and `BT_LDID`,
then run `bash scripts/build-linux.sh`. The supplied build uses Theos 5280bd0,
L1ghtmann clang 11.1.0, the iPhoneOS 16.5 declaration SDK and p0358/allemande
43b2ca5. Minimum deployment remains iOS 17.0. Legacy arm64e linker warnings
precede ABI conversion and signing; the final shipped binaries are verified
after conversion. No Objective-C block literals or custom Objective-C classes
are compiled into this tweak.
