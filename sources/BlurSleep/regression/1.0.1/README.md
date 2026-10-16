# BlurSleep 1.0.1 — Settings registration repair

A rootless SpringBoard tweak for a progressively stronger Gaussian blur and
fade to black when the sleep button locks the phone.

## Install

1. Open `BlurSleep_1.0.1_rootless.deb` in your package manager, or install it through Filza.
2. Respring.
3. On iOS 18, open **Settings → General → BlurSleep**. On iOS 17, use **Settings → BlurSleep** (or your tweak-settings organizer).

Enabled by default. Animation duration: **0.15–2.00 seconds**, default **0.55 s**.
Moving left is faster; moving right is slower. Release the slider to save. Settings
changes apply on the next lock without another respring. A reset button restores
the default duration.

This uses a native Preferences slider, including the slider fix from Classic Lock
Sound 1.0.8. The numeric value row updates after release without rebuilding the
slider while the finger is tracking it.

## Intended devices and test status

- iPhone SE (2020/A13), iOS 17.6.1, existing rootless jailbreak.
- iPhone 11 Pro (A13), iOS 18.6, existing rootless jailbreak.
- Package contains arm64 and arm64e slices and uses the standard `/var/jb` layout.

Version 1.0.0 was reported to have no visible animation and no visible Settings pane on the iPhone 11 Pro, iOS 18.6. Version 1.0.1 repairs the confirmed Settings registration error and makes runtime startup observable. The cause of the missing lock animation has **not yet been confirmed** from device diagnostics. This is a **repair and diagnostic test build**; the 11 Pro is the priority device. Compilation, package structure, signatures,
arm64e conversion and host-side animation-state checks passed. No iPhone or iOS
simulator was connected: appearance, actual display timing and interactions with
installed tweaks still require testing on the two devices. Private API guards
leave the native transition in place when a required interface differs.

## Changes in 1.0.1

- Added the missing `isController=true` registration, matching the existing working preference bundles. The prior archive verifier checked the bundle name and class but did not require this essential registration flag; that gap is now fixed.
- Normalized the SpringBoard injection filter to XML and added an explicit SpringBoard executable match. The previous OpenStep filter was not shown to be rejected by iOS; this is a packaging consistency improvement, not a confirmed explanation for the absent effect.
- Added a startup status row, a detailed list of unavailable/mismatched runtime interfaces, and a renderer preview that does not request sleep. The preview also works when rendering is available but the lock hooks are not.
- Added two bounded startup retries at two-second intervals for late class registration; kept the signature guards and normal lock behavior.
- Records library entry before interface validation, so the diagnostic report distinguishes a library that never loaded from one that loaded and intentionally left its hooks inactive.
- Updated the iOS 18 Settings location to General, as documented by the Dopamine maintainer: https://github.com/opa334/Dopamine/issues/1008.

## Priority test on the iPhone 11 Pro

Install 1.0.1 over 1.0.0 and respring for the newly installed binary. Open Settings → General → BlurSleep. Tap **Preview animation**, then try the sleep button once. Tap **Refresh status** and **Copy diagnostics**, and send that output if either test fails. The log is needed before changing unknown iOS 18 lock interfaces; successful package checks do not establish that the animation works on the phone.

## Remaining device checks

Try locking once from the Home Screen, once inside an app, and once while already
on the Lock Screen. Check both a short duration and a long duration (for example
0.25 s and 1.25 s). During the long animation, wake the phone immediately: the
overlay should disappear without a stuck black screen. Also check landscape in
an app if you use it regularly.

If the effect is missing or differs between phones, open **BlurSleep → Copy diagnostics** and paste the result along with the phone/iOS version.
The same log is at `/var/mobile/Library/Logs/BlurSleep.log`. It contains interface
availability, timing and cancellation information, not screenshots or app content.
The log is bounded to approximately 48 KiB. A small status plist alongside it records the last startup/render result. Screenshots used for the animation
exist only in memory and are cleared when the animation ends or is cancelled.

## How it works

- Hooks the runtime-checked public/private `SBBacklightController` fade methods.
  Both float and double factor signatures are supported; the source argument
  must match the 64-bit signature before the hook is installed.
- A memory-only screen image is presented in a noninteractive, non-key, secure
  overlay window. Core Animation animates a genuine `gaussianBlur` filter's radius
  from 0 to 36 while the image fades over black.
- Sets the native display fade duration to the selected duration. Calls the
  original method once with its original target, source, silent flag and
  completion. Does not postpone/replay the sleep request, change authentication,
  set global brightness or replace the lock sound.
- Applies to manual sleep-button transitions (source 3, or transitions called
  within the native hardware sleep method). Auto-lock and other display changes
  keep their native behavior.
- Cleans up on wake, native sleep reversal, another display transition or a
  bounded timer. Timer generations prevent an old animation from clearing a
  newer one. Nested backlight calls share one deadline.
- Uses no Objective-C block literals, Swift or Cephei dependency.

## Build

Theos, a suitable iPhoneOS SDK and `ldid` are required. On a current macOS/Theos
toolchain, use `make package`, adjusting the SDK portion of `TARGET` if needed.
Use a current arm64e compiler when available; the conversion below is only for
the legacy Linux compiler used to build this particular release.

For the supplied Linux build method, set `THEOS`, `BT_ALLEMANDE` and `BT_LDID`,
then run `bash scripts/build-linux.sh`. This builds with the same toolchain used
for the prior rootless tweaks: Theos 5280bd0, L1ghtmann clang 11.1.0, iPhoneOS16.5
SDK and p0358/allemande 43b2ca5. The SDK provides declarations; the deployment
minimum is iOS 17.0. The linker reports a legacy arm64e ABI before allemande
converts the final binaries and `ldid` signs them. The packaged bytes are then
checked, including authenticated Objective-C metadata and every signature page.

`validation/package-verification.json` records the exact distributed package and
binary UUIDs. `validation/state-test.txt` records the host-side state checks.
The host cannot execute the iOS UIKit code.

## Interface references

The implementation is new. Interface research and the existing build setup used:

- [Lock-Master's backlight transition interface](https://github.com/leminlimez/Lock-Master/blob/main/Tweak.x)
- [iOS 17.0.3 runtime header dump](https://github.com/MTACS/iOS-17-Runtime-Headers)
- [Theos CAFilter declarations](https://github.com/theos/headers/blob/master/QuartzCore/CAFilter.h)
- [PreferenceLoader custom-controller handling](https://github.com/ArtikusHG/PreferenceLoader/blob/master/libprefs.xm)
- [Theos rootless packaging](https://theos.dev/docs/rootless)
- [allemande arm64e conversion](https://github.com/p0358/allemande)
- Your current Classic Lock Sound 1.0.8 Settings slider and package verification code.

The consulted headers are interface evidence, not execution on iOS 17.6.1 or 18.6.

## Remove

Uninstall BlurSleep in the package manager and respring. To leave it installed
but use the stock animation, turn off **Enable BlurSleep**.
