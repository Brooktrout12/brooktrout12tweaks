# Default and notification Options — version 1.0.0

## Report

The preceding package SHA-256 was
`51e5a5c72f3aacf63be84004c8c10ab4bf4a4bb24517da05e1a176750b78f868`,
with SpringBoard arm64e UUID `bef991e3-69d8-3d7d-bc6d-56920ab19da3`.
The user confirmed the test now appears in Notification Center. The screenshots
show an older YouTube card remaining light alongside a dark test on Default,
and dark Options/Clear controls and an Options popup alongside forced-light cards.
The user clarified that the popup opens by pressing Options, not by long-pressing
the notification. No additional long-press presentation hooks are introduced.

## Changes

The former Default transition restored a remembered `nativeStyle`. If that
explicit value was Light, the card stayed pinned to Light even though its parent
was now Dark. An unmanaged card with an existing explicit style was also left
untouched. This is a concrete stale-override path in the old code; the screenshots
do not prove which native setter originally produced the individual card's value.

Notifications Default now selects an internal `D18InheritAppearance` policy.
The existing reversible state engine applies an unspecified UIKit override (0),
even on previously unmanaged/reused cards, and keeps native setter calls from
pinning those notification roots to an old style. An unspecified override follows
inherited traits, so later system appearance changes require neither timers nor
saved snapshots of the device theme. The policy is never written as a preference:
the existing Default/Light/Dark values remain 0/1/2. The behavior of those values
in other categories, including application-native overrides, is preserved.

`NCNotificationListCellActionButton` moves from the list-wide Buttons category
to Notifications; its action-button container is included too. The global
Notification Center X/Clear All controls keep their independent Buttons choice.

The existing `_UIContextMenuUIController` menu-construction hook follows the
presentation delegate to the `UIContextMenuInteraction`, then inspects its source
view and up to 32 ancestors. A notification action button/container or notification
cell marks only that menu view as Notifications. It never changes generic menu,
UIButton, cell, or window classes globally. Home Screen icon-menu recognition
keeps its existing ownership check and takes precedence. Both scope markers are
reset when the construction callback runs, preventing a reused unrelated menu
from retaining notification scope. The popup receives its style before UIKit
fills the menu with action rows.

Preview posting, partial destination withdrawal, no-expiry behavior, preferences,
Settings layout, package version and attribution are unchanged. The existing
expanded-banner ownership code is unchanged too. No new process filters, service
hooks, daemon, logging, network access, or compiler-generated blocks are added.

## Validation and limits

- Portable C tests cover stale unmanaged cards, native setter attempts, repeated
  forced-style/Default changes, restoration when leaving scope, category boundaries,
  and positive/negative notification Options source-class matches.
- Package checks validate both architectures, code-signature pages, rootless
  layout, version 1.0.0, and the no-block-runtime-import startup regression gate.
- The existing iOS 18.2 UIKit menu construction/interaction references were used.
  Additional notification-button reference downloads were unavailable during this
  revision. The actual iOS 18.6 source-view class/hierarchy must still be checked
  through the user's test; unmatched sources are left untouched.
- No iPhone or simulator is connected. Passing these checks is not evidence that
  the new appearance behavior has already been verified on the device.

The focused device sequence is in `README.md`. Matching debug symbols and package
hashes accompany the source archive.

## Interface references used

- Apple's UIKit SDK `UIView.h` documents per-view style overrides and their scope:
  [overrideUserInterfaceStyle](https://developer.apple.com/documentation/uikit/uiview/overrideuserinterfacestyle).
- [iOS 18.2 menu view construction](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/_UIContextMenuUIController.m).
- [iOS 18.2 context-menu interaction source view](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/UIContextMenuInteraction.m).

No decompiled Apple implementation code is included in this tweak.
