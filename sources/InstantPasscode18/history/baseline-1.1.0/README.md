# InstantPasscode18 1.1.0

An iOS 18 rootless tweak by **brooktrout12**. Its intended behavior is to show
the native passcode keypad immediately when you swipe up on the lock screen,
while iOS continues handling Face ID normally.

Version 1.1.0 adds **Face ID or Enter Passcode** as the neutral prompt when
Face ID is enrolled, enabled, permitted for the lock-screen view, and not locked
out. The original font is retained; the text scales down only if necessary to
fit on one line. The same label treatment covers numeric and alphanumeric
passcode views.

## Install

1. Open `InstantPasscode18_1.1.0_rootless.deb` in Filza
   and tap **Install**, or install it using a package manager that accepts local
   Debian packages.
2. Respring after installation. It is enabled automatically; there is no
   Settings pane or additional configuration.

Install this version over 1.0.0; it updates the same package.

Remove **InstantPasscode18** in Sileo/Zebra and respring to restore stock
behavior.

## Compatibility and validation

- Target: iOS **18.x**, rootless, with Substrate-compatible tweak injection
  (including Dopamine's injection environment).
- Requested test device: **iPhone 11 Pro, iOS 18.6, Dopamine 3.0.9 rootless**.
- Contains both **arm64** and **arm64e** code, with rootless package architecture
  `iphoneos-arm64`. Files install under `/var/jb`.
- Private method names/signatures were checked against available iOS 18 runtime
  headers. Runtime method-signature checks prevent hooks from installing if
  those interfaces are absent or incompatible.
- The user confirmed that version 1.0.0 works flawlessly on the requested
  iPhone 11 Pro / iOS 18.6 setup. Its original presentation hooks are retained.
- The build, package structure, dependencies, and code-signature page hashes
  are verified for 1.1.0. **The new title and text sizing have not yet been
  tested on a physical iPhone.** Compatibility with every iOS 18 point release
  is not yet confirmed.

### Check the updated title

After installing and respringing, complete any initial required passcode unlock,
then relock and swipe up with the phone on your desk. The title should read
**Face ID or Enter Passcode**, fit on one line, and keep its normal size when
there is enough room. Check that Face ID still unlocks when you bring your face
into view. With Face ID disabled for iPhone Unlock, the native prompt should
remain. When iOS requires the passcode or displays an error, it should retain
the native wording.

The tweak does not add continuous scanning or retries after iOS stops an attempt.
iOS still controls Face ID availability, attention requirements, lockouts,
passcode verification, and the behavior after typing begins.

## Implementation

`SBUIPasscodeLockViewBase` exposes `usesBiometricPresentation` separately from
`biometricAuthenticationAllowed`. Three hooks configure the former through
Apple's original setter when the passcode view's delegate is a
`CSPasscodeViewController` or a subclass:

- `setUsesBiometricPresentation:` filters the requested presentation mode.
- `setDelegate:` handles presentation settings applied before owner assignment.
- `willTransitionToPasscodeView` applies the configuration before the transition.

The title extension hooks `_defaultStatusText` and the two passcode subclasses'
`_layoutStatusView` methods. It checks the view's biometric permission,
capability, and lockout status, plus the biometric resource's Face ID hardware
support, enrolled identities, and enabled capability. Unknown policy interfaces
retain the native title. All checks are read-only.

Layout refreshes a neutral prompt that was created before delegate assignment,
without replacing an error title that differs from the native neutral prompt.
UILabel's built-in single-line fitting preserves Apple's font and label width,
with a minimum scale factor of 0.70. Previous fitting settings are restored for
native titles. The title extension has separate interface checks so an absent
cosmetic API does not disable the original instant-keypad functionality.

The getter is not spoofed: Apple's setter updates its own stored state.
Authentication methods, biometric resource methods, success/failure callbacks,
and passcode input are not hooked. No passcode data is read, stored, or logged.
There are no polling timers, asynchronous view captures, extra biometric
assertions, networking, preference bundles, or Cephei dependencies.

The process filter loads the tweak only into SpringBoard. The delegate check
further limits changes to its lock-screen passcode view. Unknown delegates
retain the original requested presentation mode.

## Build from source

With Theos, an iOS SDK, and a current Apple arm64e-capable Xcode toolchain:

```sh
export THEOS=/path/to/theos
make clean package
```

The output appears in `packages/`. An iOS 16.5 SDK is sufficient because the
private selectors are resolved at runtime. The binary's minimum deployment
version is 15.0 for rootless toolchain compatibility; the package dependency
and runtime guard restrict activation to iOS 18.

For the Linux LLVM 11 / ld64-609 toolchain used for this release, the arm64e
Objective-C metadata is converted using **allemande**, then both slices are
re-signed using **ldid**:

```sh
make clean package \
  ALLEMANDE=/path/to/allemande \
  IP18_LDID=/path/to/ldid
```

Do not pass `ALLEMANDE` when using a native current Apple arm64e toolchain.
The conversion runs only on the staged deliverable. The package does not depend
on the device-wide `oldabi` compatibility package.

Package integrity checks (Python 3 and `dpkg-deb`):

```sh
python3 tools/verify_package.py packages/com.brooktrout12.instantpasscode18_1.1.0_iphoneos-arm64.deb
```

## Technical references

- [iOS 18 runtime headers](https://github.com/qingralf/iOS18-Runtime-Headers),
  revision `cfdd406d3a0bbac8473571dda5482e155b1cc402`:
  `PrivateFrameworks/SpringBoardUIServices.framework/SBUIPasscodeLockViewBase.h`
  and `protocols/SBUIPasscodeLockView.h`.
- [Theos rootless packaging and arm64e guidance](https://theos.dev/docs/rootless).
- [allemande](https://github.com/p0358/allemande).

MIT licensed. See `LICENSE`.
