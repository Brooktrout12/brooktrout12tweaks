# CCFavorites

**Version 1.0.0 — brooktrout12**

A standalone rootless tweak for iOS 18 that keeps Control Center on its first
Favorites page. No settings to configure.

- Hides the complete page selector: Favorites/heart, Music and Connectivity.
- Disables swiping, page-selector navigation and editing edge autoscroll to
  other pages.
- Returns Control Center to the first page when it opens.
- Keeps the controls on Favorites, including its Music and Connectivity modules.

CCFavorites is independent of CC17Shapes. They have different package identifiers
and dylibs and can be installed together. CCFavorites contains no icon-shape hooks.

## Install

1. Open `com.brooktrout12.ccfavorites_1.0.0_iphoneos-arm64.deb` in your package
   manager, or use Filza's package installer.
2. Install, then respring/restart SpringBoard.
3. Open Control Center normally. Favorites should be the only accessible page,
   with no page symbols on the right.

This replacement keeps the original **1.0.0** package version. If your package
manager reports it as already installed, choose **Reinstall** for this new
`.deb`, then respring.

Compatibility: iOS 18.x, rootless.
The package contains arm64 and arm64e device slices and installs beneath
`/var/jb/Library/MobileSubstrate/DynamicLibraries`.

## Editing and removal

Favorites remains editable. Make room on that page before adding more controls
if it is full. Controls on other pages are inaccessible while this tweak is active.

The tweak does not delete or rewrite saved Control Center layouts. Removing
CCFavorites and respringing restores access to your other saved pages and the
page selector. CC17Shapes is a separate package and can remain installed.

## Verification

This corrected build fixes the Swift class-identity check that could skip the
folder and selector restrictions while swipe paging was blocked. Its
regression test reproduces the old mismatch and checks the corrected matching,
including normal Home Screen views, gallery views and late-loaded classes.

The delivered package passed compilation, rootless-layout, architecture,
dependency, arm64e metadata and code-signature checks. See `verification.json`
and `class-matching-verification.json`. The corrected build has **not yet been
device-tested**; the host regression test does not emulate UIKit.

After installation, check opening/closing Control Center, vertical swipes,
edit mode, adding/removing a control, the brightness/volume sliders and expanded
Music/Connectivity controls. Home Screen paging should work normally.

Full source, build instructions and implementation references are included.
Licensed under MIT; author and maintainer: **brooktrout12**.
