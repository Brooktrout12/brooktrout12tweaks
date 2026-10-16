# 3D Badge Clear 18 — 1.0.0

By Brooktrout12. An independent rootless iOS 18 remake inspired by
[3DBadgeClear](https://github.com/isklikas/3DBadgeClear) by
**Ioannis Sklikas (isklikas)**. The original project's MIT notice is included
in `THIRD-PARTY-NOTICES.md`.

## Install and use

Remove your existing badge-clearing tweak to avoid two Clear Badge actions.
Install `3DBadgeClear18_1.0.0_rootless.deb` while jailbroken, then respring.
Long-press a Home Screen app icon that has a badge and select **Clear Badge**.
There is no settings page or configuration.

- Clears the selected app icon's current badge.
- Appears only for app icons with a positive numeric or nonempty text badge.
- Uses the native `app.badge` system symbol: black in a light menu, white in a
  dark menu. It follows the actual menu appearance, including Dawn 18's override
  and iOS 10 style, rather than choosing an image using the device's global mode.
- Leaves future badge updates enabled. The badge can return when the app or
  iOS updates it, including after a SpringBoard reload. There is no timer.
- Does not mark messages as read, remove Notification Center entries, change
  notification permissions or open the app.

This operates on individual app icons, including apps inside folders. It does
not add a bulk-clear action to folder icons. It has no dependency on Dawn 18,
Clean Quick Actions, Cephei or PreferenceLoader.

## Implementation

The package injects one library into SpringBoard only. Two `SBIconView`
methods are hooked: `effectiveApplicationShortcutItems` and
`shouldActivateApplicationShortcutItem:atIndex:`. The first copies the existing
array and appends a native `SBSApplicationShortcutItem`. The second consumes
only this tweak's action and calls `setBadge:nil` on its app icon. Other actions
are forwarded unchanged, with their original indexes.

The app bundle identifier is captured with the shortcut and checked again on
activation to prevent a reused view clearing a different app. Badge setters,
notification delivery, badge visibility, menu colors and menu layout are not
hooked. There are no preferences, persisted suppression lists, log files,
polling, helper processes, network requests or compiler-generated blocks.

Private method signatures are checked before use. Unsupported interfaces leave
the native menu alone. A pure-C executable check runs before Objective-C work;
initialization is deferred to the main queue outside dyld's initializer lock.
All menu and badge operations are restricted to the main thread.

## Build

```sh
make clean package THEOS=/path/to/theos
python3 scripts/verify_package.py packages/com.brooktrout12.3dbadgeclear18_1.0.0_iphoneos-arm64.deb
```

The supplied package was built with Theos, Clang 11.1 and the iPhoneOS 16.5 SDK
for arm64 and arm64e. It is restricted to iOS 18 by package and runtime checks;
the compiler deployment target is 15.0. A Substrate-compatible hooking library,
such as the compatibility interface supplied by ElleKit, is the only tweak
dependency.

Linux toolchains that emit the old arm64e ABI require
`ALLEMANDE=/path/to/allemande`. The Makefile converts the staged library and
re-signs it. Leave this option unset with a current Apple toolchain. Always
clean before packaging again.

`VALIDATION.json` records checks of the delivered archive, architecture,
rootless linkage, signature page hashes, injection filter and lack of compiler
block imports. Matching dSYMs are included under `Symbols` in the source ZIP.
Build/package checks do not establish device behavior: actual badge clearing
and automatic icon tint still need testing on the target iPhone running iOS 18.6.

## References

- [Original 3DBadgeClear source](https://github.com/isklikas/3DBadgeClear/blob/master/Tweak.x)
- [iOS 18 runtime headers](https://github.com/qingralf/iOS18-Runtime-Headers)
- [iOS 18.2 SpringBoardHome research](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/tree/main/System/Library/PrivateFrameworks/SpringBoardHome.framework)
- [Theos rootless packaging](https://theos.dev/docs/rootless)

Private interfaces were checked against available iOS 18 references, not a
connected iOS 18.6 device. The implementation is independent of the older
tweak and includes no Apple implementation source or artwork from that tweak.
