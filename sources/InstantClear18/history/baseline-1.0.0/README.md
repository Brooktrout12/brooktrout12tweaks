# InstantClear18 1.0

Author: brooktrout12 · rootless iOS 18 · MIT license

Tap the **× beside Notification Center** to immediately invoke its native
clear action, without the extra Clear confirmation tap. The target is the
notification section header, not arbitrary close buttons in apps.

## Installation

Install `InstantClear18_1.0.0_rootless.deb` and respring. There are no options
or Settings page. Remove the package and respring to restore confirmation.
This package is independent of SidePress18 and KeyboardHue18. It requires
only the jailbreak's Substrate-compatible injection service, not
PreferenceLoader, Cephei, or a color picker.

## Implementation

SpringBoard-only injection, guarded to iOS 18. Intercepts the notification
header's touch-up and primary-action handlers and routes directly to that
same header's `_handleClearAll:` action. It does not enumerate notifications
or delete through a global notification database API. Native clear scope and
dismissal behavior are delegated to iOS. A per-header guard prevents duplicate
native clears if both control events arrive in one main-queue turn.

Class and Objective-C method signatures are checked before hooking. If the
expected interfaces are absent, the tweak leaves native behavior intact.
The implementation is based on the published
[NCNotificationListSectionHeaderView interface](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/UserNotificationsUIKit.framework/NCNotificationListSectionHeaderView.h).
That header is from iOS 17; iOS 18 compatibility of this route is runtime-guarded
but has not yet been confirmed on a physical device. No claim of a successful
on-device test is made.

## Validation

Compiled for arm64 and arm64e with the rootless package scheme. Package file
layout, dependencies, architecture slices, rootless library paths and embedded
code-signature page hashes passed verification; see BUILD_REPORT.json.

First device check: receive disposable test notifications, open Notification
Center, tap × once and confirm the notifications disappear without a second
tap. Repeat from the Lock Screen. If confirmation still appears, report that
behavior; the private interface may differ. Attach a SpringBoard crash report
if a crash occurs.

## Build

With Theos and a modern Apple toolchain:

    make package THEOS=/path/to/theos

The supplied build uses LLVM 11 / SDK 16.5, with a binary minimum of iOS 15
and explicit package/runtime restrictions to iOS 18. For this legacy arm64e
compiler, convert metadata and re-sign during staging:

    make package THEOS=/path/to/theos ALLEMANDE=/path/to/allemande SP18_LDID=/path/to/ldid

Omit ALLEMANDE with modern toolchains. Tools/SDKs are not bundled.

    python3 tools/verify_package.py packages/com.brooktrout12.instantclear18_1.0.0_iphoneos-arm64.deb
