# Implementation references

Inspected on 2026-09-14. These are API/implementation evidence, not a claim of
testing this build on a physical device.

- [iOS 18.2 PSUIPasscodeLockController implementation](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/PreferencesUI.framework/PSUIPasscodeLockController.m)
  — `_updateGracePeriodForSpecifier:` obtains the allowed maximum from managed
  configuration, then clamps it to zero if biometric identities exist and
  `PSUIBiometrics.isFingerprintUnlockAllowed` is true. It filters the native
  `gracePeriodValues` and title dictionaries. `setGraceValue:specifier:` calls
  the configuration connection's native setter with the passcode held by the
  existing Settings controller.
- [iOS 18.2 PSUIBiometrics implementation](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/PreferencesUI.framework/PSUIBiometrics.m)
  — confirms the query method and its boolean return type.
- [iOS 18.2 MCProfileConnection implementation](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/ManagedConfiguration.framework/MCProfileConnection.m)
  — the grace-period getter and setter use the `maxGracePeriod` setting.
- [iOS 18.2 MCServerSideHacks implementation](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/usr/libexec/profiled/MCServerSideHacks.m)
  — applies the selected interval through `MCKeybagSetPasscodeGracePeriod` and
  restores the previous value if the keybag operation fails. This is why the
  native path is retained and an on-device persistence/expiry check is needed.
- [iOS 18 runtime headers](https://github.com/qingralf/iOS18-Runtime-Headers)
  — additional method-signature checks for Preferences and ManagedConfiguration.
- [Mesalation by r-plus](https://github.com/r-plus/Mesalation)
  — historical precedent for scoped restoration of biometric grace-period
  choices. This build uses newly written code and iOS 18's different classes;
  it does not add Mesalation's Never option or its daemon hook.
- [Theos rootless documentation](https://theos.dev/docs/rootless)
  — package architecture, `/var/jb` installation, rootless library search paths,
  and the Linux arm64e ABI conversion workflow.
- [allemande](https://github.com/p0358/allemande)
  — build-time arm64e ABI converter. Not included in the installed package.
- [Dopamine](https://github.com/opa334/Dopamine)
  — current rootless jailbreak and A12/A13 firmware support information.

## 1.0.2 compatibility repair, reviewed 2026-10-17

- iOS 17.0.3 headers: https://github.com/MTACS/iOS-17-Runtime-Headers/tree/main/PrivateFrameworks/PreferencesUI.framework — `PSUIBiometrics +identities`, `PSUIPasscodeLockController -fingerprintCount` and `-_updateGracePeriodForSpecifier:`. The header does not expose `PSUIBiometrics -isFingerprintUnlockAllowed`; the previous provider guess was therefore insufficient evidence of an active menu path. Headers establish signatures, not exact iOS 17.x behavior.
- The iOS 18.2 controller implementation linked above explicitly uses `+[PSUIBiometrics identities]` for both Mesa and Pearl before the biometric clamp. Its `-fingerprintCount` also calls the shared identity query. The native effective maximum is obtained before that clamp and remains untouched.
- The same repository's `PSUIBiometrics.m` exposes `+identities` and the boolean query. These files were downloaded and inspected directly for this repair. Their hashes are recorded in `history/1.0.2/validation/reference-hashes.json`; no third-party implementation source is included in this release.

## 1.0.3 Settings crash repair, reviewed 2026-10-17

- Inspection of the prior package and its `___block_literal_global` symbol, together with the retained block regression checks, documents the callback ABI issue. See `validation/callback-fix.json`.
- Apple CoreFoundation API: https://developer.apple.com/documentation/corefoundation/cfnotificationcenter — C callback registration, local center access, and the distinction from an NSNotificationCenter object. Only the notification-name string is bridged in the fix.
- Apple notification posting reference: https://developer.apple.com/documentation/corefoundation/cfnotificationcenterpostnotification(_:_:_:_:_:) — Cocoa clients can receive CoreFoundation notifications when the posting object is a Cocoa/CoreFoundation object. The callback uses the process local center, not the Darwin center.
- The SDK CoreFoundation header supplies the exact CFNotificationCallback signature. The previous ABI converter does not transform the global block ISA at the faulting address; removing the block avoids relying on that unsupported conversion.
