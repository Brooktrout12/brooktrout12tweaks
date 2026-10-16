# Notification list and expanded appearance revision — version 1.0.0

## Current user report and correction

The user confirmed that package SHA-256
`287e29ee80b568eb7629d5785b93dbfd1c21ef053bfc16c673a7130ef35dc3c4`
(SpringBoard arm64e UUID `eee7b4b5-60d1-31a7-b8a1-9259cdb66e51`)
posts the preview banner. It did not leave a Notification Center/Lock Screen
card. Expanding a light banner also used a dark interface.

The preview requested only the banner and Cover Sheet transport destinations.
In the inspected iOS 18.2 implementation, `NCNotificationRootList` requires
`BulletinDestinationLockScreen` for its incoming lists and
`BulletinDestinationNotificationCenter` for its history list. Without either,
the ordinary request has no eligible list. Both membership markers are now
included, alongside the actual transport identifiers obtained at runtime.

Partial withdrawals maintain this distinction: removing Lock Screen leaves
Notification Center, while removing the complete Cover Sheet clears both.
A partial list withdrawal includes the Cover Sheet transport route so that its
list model actually receives the update. A banner-only dismissal does not
remove either list marker. The preview still has its own unique identity and
replaces the preceding preview on another button tap.

The unrequested 900-second timer and its Settings wording have been removed.
There is no replacement expiry mechanism. `dismissAutomatically` remains enabled
only for the banner's ordinary on-screen timeout; it is not a saved-card expiry.
The three-second Settings acknowledgement timer is unrelated and remains.
The preview is not re-created after a SpringBoard restart; it is an in-process
test request, not an app's durable notification database entry.

`NCExpandedPlatterView` and `NCExpandedPlatterViewController` now join the
context-dependent notification scope. The expanded controller delegates to the
originating short-look controller, which delegates to its destination; long-look
controllers use the destination directly. The bounded delegate walk therefore
selects Banners for expanded banners, and Notifications for expanded list cards,
even when their view hierarchy changes. It reads only known notification
controllers, with runtime getter-signature checks. No generic platter/window
override or additional hook is introduced for this change.

These changes are compiled and checked on the build host, not yet tested on the
user's phone. The exact iOS 18.6 private implementation can differ. Use the
device checks in `README.md`; successful posting alone does not prove display.

## Earlier N11 correction (retained)

The user confirmed all appearance controls work in package SHA-256
`2922601f9632dedfcf89341023627046ac2b3702492d2c366fddff7f32280e65`, with
SpringBoard arm64e UUID `8e3c99e5-8a21-3aeb-a2de-d8c0415a5b62`.
Send Test Notification returned **N11**.

N11 identifies the previous `D18SourceCallbacksCompatible` guard. That guard
could reject a missing native source, an insufficient method inventory, or a
callback mismatch. The code alone does not distinguish which occurred on the
phone. It rejected the request before the preview was created or posted.

The source inventory was an unnecessary dependency for posting a local preview.
The inspected native `SBUserAlertNotificationSource` also posts and withdraws
requests through `NCNotificationDispatcher` without registering itself in the
dispatcher's source-delegate collection. This revision uses that direct path
and removes both the inventory gate and the additional source registration.

The preview controller retains one request. It handles its Clear action by a
unique action identifier containing the preview UUID. Clear/section/date-range
requests and UUID lookup are supported by five signature-checked dispatcher
hooks, installed on the first preview request. Every system clear handler is
called exactly once with its original arguments. Extra cleanup requires the
stored dispatcher and matching preview UUID, section, or timestamp range; lookup
of any other UUID falls through to the original implementation.

Cleanup is queued after the native callback. Queued callbacks recheck identity,
so an old preview cannot remove a newer one. Removing a single destination
updates that request's destination set, preserving its Notification Center card
when only the banner is dismissed. Removing every destination withdraws it.
The action runner forwards only an existing OS-created completion, preserving
the no-compiler-block build gate. The earlier expiry timer has been removed in
the current revision as requested.

The package remains version **1.0.0**. No additional
app, daemon, log file, network access, or notification-source registration is
introduced. The previous direct-post path now has the user's banner confirmation;
the current list, dismissal, and expanded-appearance changes still need a device test.

## Failure codes

The existing N3 and N10/N12–N17 codes retain their meanings documented in
`MENU-PREVIEW-FIX.md`. N11 belongs to the preceding implementation and is no
longer returned by this preview code. New failures identify a specific cleanup
interface without installing a partial set of hooks when an ABI check fails.

| Code | Unavailable interface |
| --- | --- |
| N18 | A later dispatcher instance has a different class from the one already hooked. |
| N19 | Clear selected notification requests. |
| N20 | Clear requests from specified destinations. |
| N21 | Clear requests in specified sections. |
| N22 | Clear requests in a date range and sections. |
| N23 | Look up a notification request by UUID. |

“Preview sent” confirms the post method returned. It does not prove that a
banner appeared. The useful device check is: send, inspect the banner and card,
dismiss the banner, clear the card, send again, and check real notifications and
Clear All. Matching debug symbols and package hashes accompany this source.

## References

- [Native direct posting and withdrawal](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/SpringBoard.framework/SBUserAlertNotificationSource.m)
- [Dispatcher clear and lookup methods](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsKit.framework/NCNotificationDispatcher.m)
- [Mutable request destinations](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsKit.framework/NCMutableNotificationRequest.m)
- [List-membership checks and insertion](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsUIKit.framework/NCNotificationRootList.m)
- [Cover Sheet dispatch and list routing](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/CoverSheet.framework/CSNotificationDispatcher.m)
- [Short-look delegate setup for expanded controllers](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsUIKit.framework/NCNotificationShortLookViewController.m)
- [Expanded platter controller and view](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsUIKit.framework/NCExpandedPlatterViewController.m)

These iOS 18.2 implementations were used as interface evidence. No decompiled
Apple implementation code is included in the tweak.
