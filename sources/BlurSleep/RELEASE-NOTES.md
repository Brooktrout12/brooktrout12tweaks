# BlurSleep 1.2.0 — Liquid Glass

Seven animations for the sleep button, including an iOS 26-inspired Liquid
Glass effect and the classic CRT TV shutdown.
Built for rootless jailbreaks on iOS 17–18.

## Install and choose an animation

Install `BlurSleep_1.2.0_rootless.deb` over your existing version and respring to load the update.
Open **Settings → General → BlurSleep → Animation** on iOS 18. On iOS 17 the
pane is under **Settings → BlurSleep**, or your tweak-settings organizer.

| Animation | Effect |
| --- | --- |
| Gaussian Blur | Original blur and fade to black; remains the default. |
| CRT TV | Top and bottom squeeze into a glowing horizontal center line; the line shrinks to a point and disappears. |
| Iris Close | A circular opening closes from the edges into the center. |
| Shrink to Center | The picture shrinks into the center with rounded corners and fades away. |
| Slide Down | The picture slides off the bottom, revealing black. |
| Card Flip | The picture rotates sideways in perspective and fades as it becomes edge-on. |
| Liquid Glass | The screen draws into a rounded glass lens with refracted edges and a moving highlight, flows into a small droplet, and fades to black. |

The duration slider controls the **whole animation**, including every glass or CRT stage:
**0.15–2.00 seconds**, default **0.55 s**. Existing duration and enabled settings
and the selected animation are preserved. Missing or invalid style values fall
back to Gaussian Blur. Select **Liquid Glass** to try the new effect.

Style and duration changes apply to the next preview or sleep immediately.
**Preview animation** plays the selected effect without locking. Start around
0.8–1.0 seconds to see the glass motion or CRT stages clearly, then adjust to taste.

## Changes in 1.2.0

- Added **Liquid Glass** to the existing Animation picker. The shared duration
  slider, Preview button and diagnostics include the new style.
- The glass surface has curved edges, a slight fluid swell, four narrow bands
  of magnified screen content around the rim, a travelling reflection and a
  restrained translucent tint. The background darkens as the lens contracts
  into a capsule and then a small droplet, ending on black.
- This is a custom approximation of the iOS 26 visual style using Core
  Animation on iOS 17/18, not Apple's native iOS 26 material. Refraction is
  approximated with layered samples of the existing screenshot, not a live
  optical shader. The design reference is Apple's
  [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/).
- All texture layers share the original in-memory screenshot. There are no
  extra screen captures, per-frame CPU image processing, new dependencies,
  private filter types or iOS 26-only API calls.
- Glass layers use the existing overlay lifecycle, duration deadline and wake
  cancellation. The sleep/wake code and six earlier effects remain unchanged.
- Kept the rounded Settings icon from 1.1.1.

## Changes in 1.1.1

Rounded the Settings icon with transparent corners at all three resolutions.
The icon uses a new resource filename to avoid reusing the old cached square
asset. Animation code and sleep/wake behavior are unchanged from 1.1.0.

## Animation features added in 1.1.0

- Added a native Settings list picker with six named effects and a description
  of the selected style.
- Reused the same memory-only screen image, secure overlay, duration deadline
  and cleanup lifecycle for every effect.
- Kept the original Gaussian radius, opacity and easing unchanged.
- Added a narrow glowing CRT line, with no full-screen white flash. The picture
  collapses vertically first, then the line contracts horizontally.
- Added circular masking, centered scaling, vertical sliding and a 3D card flip
  using Core Animation. New effects require no extra images or dependencies.
- Preview reads the current selection directly, including immediately after
  changing styles. An active animation finishes with the style it started with.
- Diagnostics identify the selected/rendered animation by name.

The native sleep/wake hooks, deferred display-off handling, interruption behavior
and runtime interface checks are byte-for-byte identical in source to 1.0.2.
Only rendering, preference selection and related logging were extended.

## Validation and device status

For 1.2.0, both arm64 and arm64e compiled. The packaged Settings bundle, picker
selectors, effect names, rootless paths, converted arm64e metadata and every
ad-hoc signature page passed verification. Existing host checks cover hook
selection, duration bounds, transition eligibility and timer generations.
`validation/sleep-hook-regression.json` records unchanged native control paths.
`validation/liquid-glass-regression.json` records preserved existing styles,
preference IDs, icon assets and lifecycle code relative to 1.1.1.

**The new effects have not been run on a connected iPhone or iOS simulator.**
Preview each animation on your device, then try the sleep button. If an effect differs
from its description, use **Copy diagnostics** and identify that style.

## Behavior and diagnostics

The working iOS 18 path holds a manual display-off request until the selected
animation reaches black, then forwards it without an additional stock fade.
Native controller, state, source and completion objects remain preserved. This
changes display-transition timing and any completion work attached to it; no
authentication method, sound or global brightness setter is patched.

The renderer is noninteractive and never becomes the key window. Wake and
superseding transitions clear it through the existing cancellation path. All
styles have transparent final model values, so completed animations cannot
reveal the original screenshot when Core Animation removes them. Cleanup
releases the image, any mask and the overlay's decorative layers.

Diagnostics are bounded to approximately 48 KiB at
`/var/mobile/Library/Logs/BlurSleep.log`, with a status plist alongside it. They
contain interface names, style names and timing/state information. Screen images
exist only in memory and are never written to the log or to disk.

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

## Remove

Uninstall BlurSleep in the package manager and respring, or turn off
**Enable BlurSleep** to retain the package with the stock transition.
