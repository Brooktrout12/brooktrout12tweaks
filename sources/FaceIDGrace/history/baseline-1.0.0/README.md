# FaceIDGrace 1.0.0

Restore the native **Require Passcode** delay choices while Face ID is enabled.
Built for a rootless Dopamine jailbreak on iOS 18, with an arm64e slice for the
iPhone 11 Pro and an arm64 slice.

**Status:** compiled and statically validated. Not tested on a physical iPhone.
The private methods were verified in iOS 18.2's implementation; their behavior
on your exact iOS 18.6 installation still needs an on-device check.

## Install and use

1. Install `FaceIDGrace_1.0.0_rootless.deb` using Filza's
   installer or a package manager that accepts local packages.
2. Fully close Settings from the app switcher, then reopen it. If the installer
   asks for a respring, complete it.
3. Open **Settings → Face ID & Passcode**, enter your passcode, and choose
   **Require Passcode → After 5 minutes**, or another available interval.

German menu: **Einstellungen → Face ID & Code → Code anfordern → Nach 5 Minuten**.

There is no separate preference pane. Installation does not pick a delay for
you: choose it in Apple's menu. The tweak reuses the device's original choices
and localized labels, including Immediately. Existing management restrictions
can still limit the available intervals.

## What the delay means

The setting controls the grace period after locking: before it expires, the
phone can be opened without fresh Face ID or passcode authentication. Anyone
holding the phone can open it during that period. It does not change Auto-Lock.

Face ID remains enabled. The tweak changes the menu's biometric restriction
check, not Face ID enrollment, Apple Pay, app authentication, or authentication
results. iOS continues to handle the saved interval and any situations that
force immediate authentication, such as a reboot or Emergency SOS.

## Quick check on your phone

Use **After 1 minute** for the first test:

1. Unlock normally, select the delay, leave the menu, and return. Confirm the
   selected value persisted.
2. Cover the Face ID sensors, lock the phone, then wake and swipe up within a
   few seconds. Check that fresh authentication is not required.
3. Unlock normally again, cover the sensors, lock, and leave the phone alone
   for at least 70 seconds. Wake and swipe up. Authentication should now be
   required. Uncover the sensors and check that Face ID still works.
4. Change to Immediately and check that it again requires authentication on
   the next lock. Then select the interval you want to keep.

If the menu is unchanged, first check that Dopamine's tweak injection is enabled
for Settings and reopen Settings. If the chosen value resets or the phone still
requires authentication immediately, report that behavior; the native save can
be rejected by iOS, and this build does not pretend a rejected save succeeded.

## Undo

Choose **Require Passcode → Immediately before uninstalling**, then remove
FaceIDGrace and reopen Settings. The selected interval is a native iOS setting,
so do not assume that removing the tweak or leaving the jailbroken state alone
resets a previously selected delay.

## Implementation

The package injects only into `com.apple.Preferences`. Its two hooks are:

- `PSUIPasscodeLockController -_updateGracePeriodForSpecifier:` enters a scope
  stored in a pthread-local key while Apple's original method constructs the
  menu. It restores the previous scope in `@finally`, including nested calls.
- `PSUIBiometrics -isFingerprintUnlockAllowed` returns false only in that scope
  on the same thread. All other calls return Apple's original result.

The controller's native policy filtering, localized titles, `graceValue:`, and
authenticated `setGraceValue:specifier:` stay in use. No passcode is captured
or stored by this code. There is no SpringBoard/daemon injection, preference-file
rewriting, background timer, network access, telemetry, or runtime log file.

The loader checks the process, iOS major version, classes, selectors, argument
counts, and return types before installing hooks. It observes bundle loads and
coalesces deferred dyld notifications to handle a late-loaded PreferencesUI
framework. If the required methods are absent or have incompatible signatures,
it leaves the original behavior in place.

## Build from source

You need Theos, an iOS SDK, and an iOS compiler/linker. On macOS, use Xcode's
current arm64e-capable toolchain and ldid as configured by Theos:

```sh
export THEOS=/absolute/path/to/theos
make clean package
```

The output is in `packages/`. The Makefile sets the rootless package scheme and
compiles both arm64 and arm64e. A 16.5 SDK is sufficient because the tweak uses
public Foundation/runtime APIs and resolves the private methods at runtime.
The package and runtime guards intentionally restrict installation/use to iOS 18.

For a Linux toolchain that emits the old arm64e ABI, provide the `allemande`
converter. The supplied Makefile converts the staged dylib and re-signs it
before Theos puts it under `/var/jb` and packages it:

```sh
make clean package ALLEMANDE=/absolute/path/to/allemande
```

Only set `ALLEMANDE` for such a toolchain. Do not use a system-wide `oldabi`
dependency. This release was built with Clang 11.1.0, iPhoneOS16.5.sdk, Theos,
and allemande, then signed with ldid. It contains no Swift or new
Objective-C classes.

To repeat the package and signature checks on Linux with Python 3 and dpkg:

```sh
python3 scripts/verify_package.py packages/com.brooktrout12.faceidgrace_1.0.0_iphoneos-arm64.deb
```

These checks validate packaging and binary integrity, not on-device behavior.

Author: Brooktrout12. License: MIT.
