# Classic Quick Actions material and Ringer label — 1.0.0

The user confirmed the preceding build works. Its package SHA-256 was
`4eef6369261cd28b9c3b26b71398f3b0487bf16c52989b18bee63d312278ae49`,
with SpringBoard arm64e UUID `af5ed1e1-19f3-3bb3-9e74-7a443e02b4e2`.

## Requested changes

- Rename the Ringer & Volume Settings row to **Ringer**. The old internal
  preference key and implementation remain unchanged, preserving the choice.
- Add **iOS 10 style** as the fourth Home Screen Quick Actions segment. Match
  the supplied reference's translucent blur and lighting without changing the
  current menu's shape, layout or functionality.

## Material implementation

The new choice uses UIKit's original `UIBlurEffectStyleLight`, with the native
background view's extra background-color fill cleared. This produces a live
blur of the actual content behind the menu. Native light foreground styling
provides dark text and icons, while keeping destructive actions' red styling.
No screenshot pixels, fixed wallpaper tint, custom menu or image asset are used.

The iOS 18.2 menu-list reference constructs a `UIVisualEffectView` accessible
through `backgroundView`. Its scrolling/compositing path can construct another
effect view exposed as `cvBackgroundView`. Both are updated in place, after
checking getter ABIs, class type and actual descendant ownership. UIKit retains
its geometry, clipping, corners, group names, scroll masks and action handlers.

Only `_UIContextMenuListView` beneath the existing verified Home Screen icon
menu marker qualifies. That marker comes from the SBIconView interaction source
in the already-working menu-construction hook. Notification Options explicitly
stops the ownership search; generic menu/material/effect classes do not qualify.
The search is bounded to 64 ancestors. The material implementation is linked
only into the SpringBoard tweak, not into applications or the Settings bundle.

One runtime-signature-checked `layoutSubviews` hook on the specific menu-list
class calls UIKit's original implementation first. It then updates the material
after lazy creation, submenu construction, or scrolling-background replacement.
Existing lifecycle and preference refreshes also update matching menu lists.
There are no new timers, service hooks, logging, network calls or compiler blocks.

The material state stores native effects and colors separately from values
applied by Dawn 18. Repeated layout does not repeatedly set an unchanged effect.
Observed native updates replace the saved native value, without capturing Dawn
18's own blur as that value. Leaving classic mode or leaving the owning list
restores only properties still carrying Dawn 18's values. Weak background keys
avoid retaining outgoing collection backgrounds. Reentrant updates are guarded.

## Preferences

The existing ten keys, indices and defaults remain intact. Values 0/1/2 keep
their meanings. Value 3 is accepted only for Quick Actions, at read, write and
Settings-edit boundaries. Fractional, non-finite, out-of-range, wrong-type and
Boolean preference inputs are rejected/defaulted. UIKit never receives style
enum 3: that selection resolves to Light (1) plus the scoped material treatment.

The Settings cell inserts or removes the fourth segment when reused, so it
cannot leave a fourth choice on another row. Quick Actions apportions segment
widths to fit the longer label. Reset still clears all choices. Version remains
exactly 1.0.0, with Brooktrout12 attribution and the original Dawn author credit.

## Verification and visual limits

Portable C tests cover value-3 scoping, invalid values, existing preference
indices, menu class markers, native-style restoration and the prior rules.
Source-contract tests cover key order, Settings coverage and the Ringer rename.
The final archive is checked for rootless paths, both architectures, signatures,
matching debug symbols and the earlier no-block-runtime-import startup gate.
Compiled-content checks require the new menu material and Settings label and
confirm the material implementation is absent from app/Settings binaries.

No device or simulator is connected. The material is an iOS 10-inspired match
using the native legacy blur still available in UIKit; it is not a claim of
pixel-identical iOS 10 rendering. The wallpapers/icon layouts differ between
the supplied screenshots, and live backdrop colors plus iOS 18's rendering
affect the result. The new material needs the user's visual comparison on the
phone. The focused check is in README.

## References inspected

- [iOS 18.2 menu-list backgrounds and layout](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/_UIContextMenuListView.m)
- [Menu construction and submenu ownership](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/_UIContextMenuView.m)
- [Menu platform metrics](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/_UIContextMenuPlatformMetrics.m)
- [UIBlurEffect interface/implementation reference](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/UIBlurEffect.m)
- [Legacy blur implementation reference](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/_UIBlurEffectLegacyImpl.m)
- [Apple's light blur API](https://developer.apple.com/documentation/uikit/uiblureffect/style/light)
- [Apple's visual effect view API](https://developer.apple.com/documentation/uikit/uivisualeffectview)

The local iOS SDK declarations for UIBlurEffect/UIVisualEffectView were also
inspected. No decompiled Apple implementation code is included in the tweak.
