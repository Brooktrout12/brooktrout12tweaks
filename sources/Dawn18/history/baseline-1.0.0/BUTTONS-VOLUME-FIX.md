# Notification swipe buttons and Ringer & Volume — 1.0.0

## Scope

Previous package SHA-256:
`e2e3c05d7d91ba98f0a886d7045453776df2c9700170c679a81a8b911303883d`.
Previous SpringBoard arm64e UUID:
`02e74ff5-b62e-3e81-a423-269b4c264c8d`.

The user reports the preceding revision works except for the actual Options
and Clear swipe buttons. The popup opened by Options and Notifications Default
are now working. This revision does not change either implementation.

## Swipe-button correction

The earlier mapping named `NCNotificationListCellActionButton` and its old
container. In the inspected iOS 18.2 implementation, `NCNotificationListCell`
instead owns `PLSwipeInteraction`. When actions are revealed, that interaction
adds a `PLActionButtonsPresentingView` to its source cell. It contains a
`PLPlatterActionButtonsView`, with individual `PLPlatterActionButton` controls.
The actual button creates an `MTMaterialView` background; its title can use
that background's automatically updating visual styling provider.

The three PlatterKit classes now receive a contextual marker. They resolve to
Notifications only if their bounded ancestor chain contains a notification
cell or recognized notification action view. A button's actual `backgroundView`
is checked through its runtime-signature-validated getter and receives the
same scope. This catches a material with its own explicit appearance without
overriding generic materials or every UIButton. No static colors or material
recipe IDs are substituted. The native button layout, actions and accessibility
remain intact.

The existing style engine supplies Light/Dark and inherited Default. The
independent Notification Center Buttons setting continues to govern list-wide
X/Clear All/section controls. The shared PlatterKit classes are not themselves
notification-menu source markers, and generic uses outside notification cells
remain excluded. The working Options popup retains its original source test.

This class mismatch is confirmed in the iOS 18.2 reference; that is evidence for
the correction, not a live inspection of the user's iOS 18.6 hierarchy.

## Ringer & Volume

A native Settings row uses the same title-above-Default/Light/Dark layout.
`RingerVolume` is appended at preference index 9; indices 0–8 and all prior key
names remain unchanged. A missing new key reads as Default. Reset includes all
ten choices. No settings migration or package version increase is needed.

The appearance roots are `SBRingerHUDViewController`, `SBRingerPillView`, and
`SBElasticVolumeViewController`. The inspected ringer pill has a material and
dynamic label/glyph colors. The volume controller hosts `SBElasticSliderView`
and its material hierarchy. Public appearance overrides on those roots allow
the native views to render the selected style. Default restores their native
override. Shared slider/base-controller classes are deliberately excluded to
avoid styling brightness or Control Center through this choice.

No audio, mute, hardware-button, HUD timing, or volume setters are hooked.
No new hook installation sites, daemon, polling, runtime logs or network access
are introduced. The test-notification source and no-expiry behavior are unchanged.
Version remains exactly 1.0.0; author Brooktrout12, inspired by Dawn by EthanRDoesMC.

## Checks and limits

- Portable production-C tests cover category markers and exclusions, stable
  preference indices, native HUD Default restoration, notification inheritance,
  native setter transitions, process exclusions, and preview reply identity.
- Package validation checks the new class/key/Settings strings in the binaries,
  rootless layout, both architectures, all code-signature pages, and the
  no-compiler-block-runtime-import gate for the earlier startup crash.
- Source comparison checks preserve preview posting, menu construction,
  expanded-notification ownership, and folder handling.
- Matching dSYMs are included in the source ZIP, not installed on the phone.
- No iPhone or simulator is attached. These are build/source checks, not proof
  of appearance behavior on iOS 18.6. See README for the focused device checks.

## References inspected

Runtime names and ownership were checked against these iOS 18.2 interfaces and
decompiled methods. No decompiled Apple implementation is copied into the tweak.

- [Notification cell](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsUIKit.framework/NCNotificationListCell.m)
- [Swipe interaction construction](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/PlatterKit.framework/PLSwipeInteraction.m)
- [Individual action button](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/PlatterKit.framework/PLPlatterActionButton.m)
- [Action buttons container](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/PlatterKit.framework/PLPlatterActionButtonsView.m)
- [Action presentation view](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/PlatterKit.framework/PLActionButtonsPresentingView.m)
- [Ringer controller](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/SpringBoard.framework/SBRingerHUDViewController.m)
- [Ringer pill](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/SpringBoard.framework/SBRingerPillView.m)
- [Volume controller](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/SpringBoard.framework/SBElasticVolumeViewController.m)
- [Volume controller base](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/SpringBoard.framework/SBElasticValueViewController.m)
- [Elastic slider material hierarchy](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/SpringBoard.framework/SBElasticSliderView.m)
- [UIKit appearance override](https://developer.apple.com/documentation/uikit/uiview/overrideuserinterfacestyle)
