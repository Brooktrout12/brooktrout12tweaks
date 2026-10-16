# Menu and preview correction — version 1.0.0

Historical note: the menu correction described here is now user-confirmed
working. The subsequent N11 preview revision is documented in `NOTIFICATION-FIX.md`.

The preceding package has SHA-256
`f42319fdf4b5ea2e62d8c42fc40f960e090b62721119d42b985d87dc15840f49`.
Its SpringBoard arm64e UUID is `99b8143c-0a69-3332-927c-d64efd53cb2e`.
The user confirmed its folder fix worked but reported that Quick Actions had
no effect and the test notification returned “not available on this system.”

## Evidence and changes

The screenshot's error corresponds to the old code's unavailable-interface
reply. It confirms a reply from SpringBoard, but the old reply did not identify
which required interface failed. The following concrete mismatches were found
by tracing the iOS 18.2 implementations; these are candidates for the reported
iOS 18.6 failures, not an on-device trace of those failures.

1. **Notification content.** `NCNotificationContent.header` is a computed getter
   using `customHeader` and `defaultHeader`. `NCMutableNotificationContent`
   implements `setCustomHeader:` and `setDefaultHeader:`, with no `setHeader:`
   in either inspected implementation. The previous code required `setHeader:`
   and aborted if it was absent. This build uses `setCustomHeader:`. The other
   mandatory mutable setters were cross-checked against their implementations.
   The optional image uses `setIcon:`, allowing the native class to form its icon
   array. The request explicitly uses the normal active interruption level
   instead of relying on a zero-initialized passive value.
2. **Quick Actions.** `_UIContextMenuStyle.copyWithZone:` omits
   `preferredTraitCollection`; `_UIContextMenuUIController` reads the separate
   parent-trait-environment property when configuring its container. The prior
   style-property override therefore did not reach the action list in the
   inspected implementation. This build applies the public appearance override
   to the actual menu view, after `_createMenuViewIfNecessaryForMenu:` returns
   and before its caller populates the action list.
3. **Scope.** The owning chain is `_UIContextMenuUIController.delegate` →
   `_UIContextMenuPresentation.delegate` → `UIContextMenuInteraction.delegate`.
   The last object must be an `SBIconView`, and the interaction's `view` must
   be that same icon. Only then is its menu marked for Quick Actions. The
   ordinary reversible state engine preserves native overrides and Default.
4. **Settings.** Removed the paragraph explaining the already-working folder
   coverage. The author and original Dawn credit remain unchanged.

The earlier no-compiler-block fix is preserved in both architectures. This
revision adds no daemon, timer loop, persistent runtime log, or service hook.

## Preview failure codes

Codes are shown only when sending a preview fails. They share the existing
request/reply channel and let a screenshot identify the failed stage.

| Code | Stage |
| --- | --- |
| N2 | Unavailable reply from the preceding build; respring after reinstalling. |
| N3 | Exception while creating/posting the preview; cleanup attempted. |
| N10 | SpringBoard dispatcher or one of its required methods unavailable. |
| N11 | Previous source inventory check failed: missing source, insufficient methods, or an incompatible callback. |
| N12 | Banner or Notification Center destination identifier unavailable. |
| N13 | Required notification model class unavailable. |
| N14 | Required notification content setter unavailable. |
| N15 | Required notification option setter unavailable. |
| N16 | Required clear-action setter unavailable. |
| N17 | Required notification request setter unavailable. |

“Preview sent” confirms the dispatcher invocation returned; it is not a receipt
proving that the banner was displayed. Final visual behavior, dismissal, and
the iOS 18.6 runtime remain for the user's device check. The package and source
archive include matching validation metadata and debug symbols.

## Implementation references

These were inspected as interface evidence. The tweak's implementation is
original; decompiled Apple implementation code is not included in the package.

- [NCNotificationContent](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsKit.framework/NCNotificationContent.m)
- [NCMutableNotificationContent](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsKit.framework/NCMutableNotificationContent.m)
- [NCMutableNotificationRequest](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsKit.framework/NCMutableNotificationRequest.m)
- [_UIContextMenuStyle](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/_UIContextMenuStyle.m)
- [_UIContextMenuUIController](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/_UIContextMenuUIController.m)
- [_UIContextMenuPresentation](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/_UIContextMenuPresentation.m)
- [UIContextMenuInteraction](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/UIContextMenuInteraction.m)
