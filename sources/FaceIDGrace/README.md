# Face ID Grace 1.0.3 — Face ID and Touch ID, iOS 17–18

By Brooktrout12. Package identifier: `com.brooktrout12.faceidgrace`.

This release fixes the bundle-notification callback that could crash Settings. It keeps the shared Face ID/Touch ID menu hooks introduced in 1.0.2. The DEB contains arm64 and arm64e slices with an iOS 17.0 deployment minimum; its firmware dependency permits iOS 17 and 18.

## Callback repair

The previous notification observer used an Objective-C global block with legacy arm64e metadata. CoreFoundation could encounter invalid pointer authentication while retaining or releasing that block. The package's symbols and block regression checks document the affected callback without publishing a device crash report.

The Linux compiler emits legacy arm64e block metadata that the project's ABI converter does not repair. Version 1.0.3 registers a C function with the local CoreFoundation notification center, removing the Objective-C block object and its retain/release path. Bundle notifications still trigger synchronous hook installation; the existing deferred dyld callback still handles other image loads. No notification-center objects are cast between Foundation and CoreFoundation.

## Install and check

Install `com.brooktrout12.faceidgrace_1.0.3_iphoneos-arm64.deb` over the previous version. Fully close Settings from the app switcher, then reopen it; complete a respring if the package manager requests one.

1. Open Settings, then **Touch ID & Passcode → Require Passcode** on the Touch ID device. Confirm Settings stays open and delay choices appear. There is no separate tweak pane.
2. Choose **After 1 minute**, leave the page, and reopen it to check that the selection persists.
3. Lock and reopen within the minute without a biometric match: use an unenrolled finger for the Touch ID device's Home button, or cover the Face ID sensors. Repeat after more than a minute and confirm authentication is required again.
4. Choose **Immediately** to check restoration of normal behavior. Repeat under **Face ID & Passcode** on a Face ID device.

No physical device was available for testing 1.0.3. Build and binary checks establish that the known faulty block is absent; they do not establish all native menu, save, and lock-timing behavior. The requested device matrix remains Touch ID and Face ID on both iOS 17 and iOS 18.

## Menu behavior retained from 1.0.2

During the native `_updateGracePeriodForSpecifier:` call only, on that thread, the tweak overrides the shared `PSUIBiometrics +identities` query, the controller's `-fingerprintCount`, and available `isFingerprintUnlockAllowed` providers. It installs matching hooks independently as Settings loads frameworks. Unsupported method signatures are skipped. Nested calls and Objective-C exceptions restore the prior scope; other threads and calls outside the menu scope receive the original results.

Native maximum-delay policy filtering, localized labels, and authenticated saving remain in place. No enrolled biometric is removed. Management policy can still restrict the choices. If delay choices appear but saving or actual expiry fails, that is a separate behavior requiring a device report.

## Verification included

- The package verifier checks both shipped slices for absence of Objective-C block imports/literals and the block-based notification selector. It also checks the replacement C notification API, Settings-only rootless injection, firmware/deployment bounds, hook symbols, converted arm64e constant strings, and every signed code page.
- The block regression check rejects both original 1.0.2 slices for the relevant block metadata and accepts both 1.0.3 slices.
- The existing host scope test covers nesting, thread isolation, restoration, 100,000 cycles, and overflow rejection. It does not emulate iOS.
- Included debug symbols match the two packaged UUIDs. `validation/callback-fix.json` explains the code-level correction; private device-report details are omitted.

See `validation/`, `BUILD-IOS17-18.md`, `REFERENCES.md`, and `UPDATE-1.0.3.patch`. Historical build records and symbols are retained under `history/`; they describe older binaries.

## Removal

Select **Immediately before uninstalling** if you want immediate authentication restored. The selected delay is a native iOS setting; uninstalling the tweak does not reset it. License: MIT.
