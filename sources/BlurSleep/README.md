# BlurSleep 1.0.2 — iOS 18 sleep-hook repair

Gaussian blur and fade to black when pressing the sleep button, with a native
Settings slider for duration. Rootless package for the existing jailbreak.

## Install

Install `BlurSleep_1.0.2_rootless.deb` over 1.0.1 using your package manager or
Filza, then load the new binary with a respring.

- iOS 18: **Settings → General → BlurSleep**.
- iOS 17: **Settings → BlurSleep**, or your tweak-settings organizer.

Enabled by default. Duration is **0.15–2.00 seconds**, default **0.55 s**. Release
the slider to save; duration changes apply on the next sleep without a respring.
The preview, slider, and custom Settings registration from 1.0.1 are retained.

## What the device report established

Priority device: **iPhone 11 Pro / A13, iOS 18.6 (22G86)**.
Secondary target: iPhone SE 2020 / A13, iOS 17.6.1.

The 1.0.1 report confirmed that Settings, duration saving and the animation
preview work. The log also proves the two legacy backlight-duration methods are
absent, so the previous all-or-nothing guard disabled every lock hook. That was
the reason the working renderer never ran on sleep.

1.0.2 adds a path using these methods from that actual device report:

| Method | Runtime encoding |
| --- | --- |
| `setBacklightState:source:animated:completion:` | `v44@0:8q16q24B32@?36` |
| `_factorToPublishForBacklightState:` | `f24@0:8q16` |
| `screenIsOn` | `B16@0:8` |
| `turnOnScreenFullyWithBacklightSource:` | `v24@0:8q16` |

Every method is checked again at startup before use. The state-to-factor getter
identifies an off state without guessing an iOS 18 numeric enum. The legacy
path remains available for systems exposing only the older duration methods.

## Transition behavior

The hardware sleep method still executes immediately. When available, its
backlight-controller getter lets the renderer capture the foreground screen
before native sleep changes the UI. The same preview renderer animates Gaussian
radius from 0 to 36 while the image fades over black.

For a manual off transition, the new hook holds the native backlight-state
request until the image reaches black, then forwards it with `animated:NO` to
avoid a second stock fade. The original controller, target state, source and
completion object are preserved. This deliberately changes the timing of the
display-state request and any completion work attached to it. No authentication
method, lock sound, system brightness setter or complete sleep-button action is
replaced or replayed.

Repeated requests share the existing animation deadline. A wake or superseding
state first drains queued native requests, then proceeds with the newer native
request, preventing a stale timer from submitting screen-off after wake. An
optional, signature-checked initial-button-press hook settles a pending off state
before the next press is classified by the native recognizer. Off-thread state
and wake requests are serialized on the main queue. Timers run in common modes;
a bounded cleanup timer removes the overlay and releases the memory-only image.

## Priority test

On the 11 Pro, select **1.0 s**, lock from inside an app, then wake normally.
Also try waking before the animation finishes. The effect should run for the
selected duration, reach black and leave the phone able to wake immediately.
If it does not, use **Copy diagnostics** after that attempt. The log now records
the actual state, factor, source, queued deadline and native submission, rather
than only listing absent legacy methods.

No second preview test is necessary: the user already confirmed that renderer
on this device. The iOS 17 device has not been tested yet.

## Validation and limits

The arm64 and arm64e builds, rootless payload, Settings registration, converted
arm64e metadata and every ad-hoc signature page passed verification. Host tests
cover the reported iOS 18.6 hook-selection regression, input bounds, manual-lock
eligibility, shared deadline, cancellation and stale timer generations.

**The new sleep hook has not been executed on a connected iPhone or simulator.**
Those host checks do not establish native callback timing, button-recognizer
behavior, actual panel-off timing or compatibility with other installed tweaks.
The 11 Pro test above is the next runtime check.

Diagnostics are stored at `/var/mobile/Library/Logs/BlurSleep.log` (bounded to
approximately 48 KiB), with a small status plist alongside it. They contain
interface and timing information, never screenshots or app contents.

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

## Source evidence

- User-provided iPhone 11 Pro / iOS 18.6 diagnostic report, 16 October 2026.
- User confirmation that the 1.0.1 Settings slider and preview work.
- [iOS 17 runtime interaction declarations](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBSleepWakeHardwareButtonInteraction.h)
- [Legacy transition interface](https://github.com/leminlimez/Lock-Master/blob/main/Tweak.x)
- [PreferenceLoader controller handling](https://github.com/ArtikusHG/PreferenceLoader/blob/master/libprefs.xm)
- [iOS 18 PreferenceLoader location](https://github.com/opa334/Dopamine/issues/1008)
- [Theos rootless packaging](https://theos.dev/docs/rootless)
- [arm64e conversion tool](https://github.com/p0358/allemande)

## Remove

Uninstall BlurSleep in the package manager and respring. To leave it installed
with the stock animation, turn off **Enable BlurSleep**.
