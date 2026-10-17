# Face ID Grace 1.0.2 — Face ID and Touch ID, iOS 17–18

By Brooktrout12. Package identifier: `com.brooktrout12.faceidgrace`.

This update extends the grace-period menu support to Touch ID as well as Face ID. The package keeps its existing name and identifier but handles both biometric types. It targets iOS 17.0 through 18.x and includes arm64 and arm64e.

## Install and check

Install `com.brooktrout12.faceidgrace_1.0.2_iphoneos-arm64.deb` as an update. Fully close Settings from the app switcher, then reopen it; complete a respring if your package manager requests one. Open **Touch ID & Passcode → Require Passcode** on an Touch ID device or **Face ID & Passcode → Require Passcode** on a Face ID device. There is no separate tweak pane.

Choose **After 1 minute** for a first check. Leave and reopen the page to confirm the selection persists. Lock and reopen the phone within the minute without supplying a biometric match: use an unenrolled finger for the Touch ID device's Home button, or cover the Face ID sensors. Repeat after more than a minute and confirm authentication is required again. Then choose Immediately to check restoration of normal behavior. Menu visibility, persistence and actual lock timing are three separate acceptance checks.

The requested test matrix is iOS 17 / Touch ID, iOS 17 / Face ID, iOS 18 / Touch ID, and iOS 18 / Face ID. All four share this implementation; no device-family blacklist or Face-ID-only branch is used. No physical device was available for testing this release. The update addresses missing shared-enrollment coverage and a late-loading installation limitation found in source review.

## What changed

The previous implementation depended on `isFingerprintUnlockAllowed` being called on one of two specific providers. That query's presence in a header does not establish that the menu calls it on every OS version.

1. `PSUIBiometrics +identities` now returns an empty array only while the original grace-menu updater runs on the same thread. This shared enrollment query covers both Face ID and Touch ID. The inspected iOS 18.2 implementation checks the returned array before applying its biometric-only clamp to Immediately; iOS 17.0.3 headers expose the same class method.
2. `PSUIPasscodeLockController -fingerprintCount` returns zero within that same scope, covering the controller's Touch ID count route when used. Both inspected versions expose its signed 64-bit signature.
3. The existing boolean providers remain supported whenever their signatures match on either iOS major version, rather than assigning the ManagedConfiguration provider exclusively to iOS 17.
4. Hook installation tracks each route separately and continues after later bundle/image loads. Installing an early provider no longer prevents later providers from being added. A nonblocking installation lock prevents reentrant bundle loading from deadlocking.

Only `_updateGracePeriodForSpecifier:` establishes the override scope. Nesting and Objective-C exceptions restore the preceding scope. Queries outside that scope, including other threads, return their original results. No enrolled biometric is deleted or disabled.

Native maximum-delay policy filtering, localized labels, saved-value getter and authenticated setter remain unchanged. The tweak does not fabricate successful saves, write passcode preference files, hook the lock screen or authentication daemon, or alter authentication results. Management policies may still restrict choices. Unsupported private method signatures are not hooked.

## Verification

The host scope test exercises nesting, restoration, thread isolation, 100,000 enter/leave cycles and overflow rejection. It tests the same C scope helpers used by the tweak, not an emulated iPhone. Package validation checks rootless Settings-only injection, both architectures, iOS 17.0 deployment targets, firmware bounds, new hook symbols, arm64e constant-string conversion and every signed code page. Debug-symbol UUIDs match the two packaged slices.

This source review does not establish that 1.0.2 has passed device testing. If Immediately remains the only choice after reopening Settings, report the installed version and whether any managed passcode policy is present. If options appear but a selected delay resets or has no effect, that is a separate native persistence/enforcement issue.

## Removal

Select **Immediately before uninstalling** if you want immediate authentication restored. The selected delay is a native iOS setting; uninstalling the tweak does not itself reset it.

See `BUILD-IOS17-18.md`, `REFERENCES.md`, `UPDATE-1.0.2.patch`, and `validation/`. Earlier reports under `history/` describe earlier releases. License: MIT.
