# Clean Quick Actions 1.0.0

By Brooktrout12. A separate rootless tweak for iOS 18 that hides the divider
lines in Home Screen icon Quick Actions menus. It preserves the menu shape,
row spacing, actions, text, icons and blur. It can coexist with Dawn 18,
including its iOS 10 style, and does not require Dawn or Cephei.

## Install and use

1. Install `CleanQuickActions_1.0.0_rootless.deb` with your package manager
   while jailbroken, then respring when prompted.
2. Open **Settings → Tweaks**. **Clean Quick Actions** has its own icon and a
   switch directly in that list. There is no separate settings page.
3. The switch defaults to **on**. Long-press a Home Screen app icon. Turn the
   switch off to restore the native separators; reopen the menu after changing
   the switch. Preference changes do not require another respring.

The entry uses PreferenceLoader's native `PSSwitchCell`. Its location follows
the existing Tweaks grouping provided by your Settings organizer. Dependencies:
PreferenceLoader and a Substrate-compatible hook library (provided by ElleKit
on compatible rootless jailbreaks).

## Implementation and scope

Only SpringBoard is injected. A verified icon-owned `UIContextMenuInteraction`
marks the menu created by `_UIContextMenuUIController`. Explicit negative
markers prevent unrelated menus from inheriting that scope. Three narrow
separator classes are covered: `_UIContextMenuSeparatorView`,
`_UIContextMenuReusableSeparatorView`, and
`_UIContextMenuGradientMaskSectionSeparatorView`.

The original `hidden` value is preserved per view, including native changes
while enabled. OFF and reuse outside an icon menu restore that native value.
Layout and separator attachment callbacks cover lazily created rows and
scrolling. Weak view tracking allows immediate restoration without retaining
menus. There are no global color/height overrides, appearance changes,
preference pane controllers, additional processes, timers, network requests,
or hooks in applications, share services, or File Provider services.

All private calls and hooks check method signatures. Startup checks the
executable path before Objective-C work and defers initialization outside
dyld's initializer lock. Preference reads run serially off the main thread;
only main-thread callbacks touch UIKit. C callbacks avoid compiler-generated
block metadata on the Linux arm64e toolchain used for the supplied binary.

## Build

Install Theos with an iOS SDK and suitable arm64/arm64e toolchain:

```sh
make clean package THEOS=/path/to/theos
python3 scripts/verify_package.py packages/com.brooktrout12.cleanquickactions_1.0.0_iphoneos-arm64.deb
```

The supplied package was built using Clang 11.1 and the iPhoneOS 16.5 SDK,
with deployment target 15.0, and is restricted to iOS 18 by package metadata
and runtime checks. Both arm64 and arm64e are included. For Linux toolchains
emitting the old arm64e ABI, pass `ALLEMANDE=/path/to/allemande`; the Makefile
converts staged binaries and re-signs them. With a current Apple toolchain,
leave `ALLEMANDE` unset. Always clean before packaging again.

The three Settings PNGs are included. Optional regeneration uses
`python3 scripts/make_icon.py` with Pillow; the editable SVG is in `Artwork`.

Run the host visibility-state checks with:

```sh
cc -std=c11 -Wall -Wextra -Werror Rules.c tests/test_rules.c -o /tmp/cleanquickactions-rules
/tmp/cleanquickactions-rules
```

`VALIDATION.json` records checks of the distributed package: architecture,
rootless paths, filter, direct Settings switch, dependencies, code-signature
page hashes and absence of unsafe block imports. Matching dSYMs are included
in `Symbols` in the source ZIP for crash symbolication. These checks are not
device tests: final visual behavior and the direct toggle still need testing
on the target iPhone running iOS 18.x.

## Primary references

- [Theos simple-preferences template](https://github.com/theos/templates/tree/master/ios/tweak_with_simple_preferences)
- [PreferenceLoader implementation](https://github.com/DHowett/preferenceloader/blob/master/prefs.xm)
- [iOS 18.2 UIKitCore runtime research](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/tree/main/System/Library/PrivateFrameworks/UIKitCore.framework)
- [Apple UIView hidden property](https://developer.apple.com/documentation/uikit/uiview/ishidden)
- [Theos rootless packaging](https://theos.dev/docs/rootless)

Private UIKit details were checked against iOS 18.2 reference material; they
have not been verified on a connected iOS 18.x device. The package includes
original implementation code, not copied UIKit source.
