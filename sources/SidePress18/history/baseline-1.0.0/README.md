# SidePress18

Double-press the side button for Camera, a selected app, Flashlight, or media
controls. **iOS Default** is the default action.

Version **1.0** (Debian package `1.0.0`) · Author **brooktrout12** · MIT license

## Install

Install `SidePress18_1.0.0_rootless.deb` and respring. Choose **Reinstall** if
1.0.0 is already installed. Open **Settings → SidePress18**. Settings changes
apply immediately. PreferenceLoader is required; Cephei is not used.

## This revision

- The user's iOS 18.6 diagnostic confirms that the selected application is
  found, `initWithApplicationForMainSecureDisplay:` creates its scene, the
  scene handle is secure, and the bundle identity matches. It also confirms
  that the Camera transition never reaches the launcher method previously
  hooked, so Camera appeared and the selected scene was never submitted.
- Replaces that interception with **direct submission of the selected secure
  scene** through
  `_reallyActivateAppSceneWithEntity:interactive:withCompletion:`, whose
  presence and ABI were confirmed by the device diagnostic. No Camera
  transition is requested for another selected app. The genuine Camera action
  retains its own working native presentation route.
- A native completion only records progress. Success requires observing the
  selected bundle in the native secure host; a completion cannot cancel a
  pending scene merely because it has not become visible yet. Stale requests
  are ignored, and a five-second visibility timeout records the observed
  secure host, lock state and available launcher interfaces.
- Preserves the validated secure-scene and bundle checks, actual system
  authentication, and the current-app no-op. No authentication state is forged
  and no unlocked foreground-launch fallback is used.
- Leaves Settings and click-speed code unchanged. The latest device log shows
  Fastest applied at 160 ms and a measured **161 ms from button release to the
  native sleep request** (223 ms from button down). This measurement excludes
  the remaining display fade animation.
- Keeps version 1.0, iOS Default as the initial action, the action picker that
  stays open, media controls, flashlight, search and native foreground launch.

This direct presentation path still needs an on-device test. The method's
existence and the input scene are verified; its final presentation behavior,
sideways animation and Home returning to the Lock Screen are not yet confirmed.

## Lock behavior

**Require Unlock** applies to every custom action and defaults to off.

| Starting state | Require Unlock | Requested behavior |
|---|---|---|
| Home or another app | Either | Ordinary native foreground launch; system actions run directly. |
| Lock Screen | Off | Camera or the selected app uses the native secure display and sideways transition. Home returns to the Lock Screen. |
| Lock Screen | On | Present native Face ID/passcode UI, then run only after real authentication and complete UI dismissal. Cancel performs no action. |
| Notification Center | Off | Camera and other selected apps use the Cover Sheet's native presentation. |

The app's own authentication and protected data restrictions still apply.
With Require Unlock off, anyone holding the phone can use the selected app
and whatever content it exposes. The tweak does not forge authentication,
unlock then re-lock, or display an imitation Lock Screen.

If native scene preparation fails, **Last Result** explains the failure before
presentation begins. Other selected apps are submitted directly; their route
never invokes Camera presentation. A submitted scene is not reported as
successfully visible until its actual hosted bundle is checked.

The table describes intended behavior. The user has confirmed Camera and
Require Unlock on; arbitrary apps with Require Unlock off were still not
working in the preceding build. The new direct submission path needs device
verification. It does not assume every app supports a secure-display scene.

## Timing and system gestures

Uses SpringBoard's native double-click recognition. **Faster** and **Fastest**
target multiple-click windows of 220 and 160 milliseconds by scaling the
actual recognizers’ gap and preemption waits after native configuration. They require
quicker double and triple presses. Default, Slow and Slowest retain Apple's
timing. A single press waits for the selected native recognition window;
there is no additional tweak double-click timer.
Sleep and its sound are deferred during that decision and discarded for a
recognized double press.

Siri, screenshots, accessibility triple-clicks, emergency gestures, payment
confirmation consumers, and apps registered for lock-button events retain
priority. Disabling the tweak or choosing iOS Default restores native actions.
The speed selected in Accessibility still applies independently of the action
switch. Select Default, Slow or Slowest to restore Apple's timing. Custom
speeds are stored separately from Apple's preferences; uninstalling removes
the override without leaving an unsupported value in system settings.

## Validation and device checks

The previous revision has been confirmed on the user's device for native
Camera presentation, already-open Camera behavior, flashlight on/off, app
search, foreground launch animations, Require Unlock on, and all media actions.

This revision is compiled for rootless arm64 and arm64e, with iOS 18 enforced
by package dependencies and runtime checks. The target test device is iPhone
11 Pro / iOS 18.6 / Dopamine 3.0.9. This revision has **not** been run on an
actual iPhone by its builder. Private API signatures and scene ownership are
checked at runtime; those checks cannot prove every app's compatibility or
native animation and authentication ordering.

Priority checks on the phone:

1. With Require Unlock off, select an app other than Camera and launch it
   from the locked screen. Confirm the selected app appears, then swipe Home
   and confirm the phone returns to the Lock Screen. Repeat from Notification
   Center and while the selected app is already visible.
2. If presentation fails or the wrong app appears, use Copy Last Result. It
   records the direct submission, whether native completion arrived, and the
   actual secure host observed. Include a crash report if applicable.
3. Confirm Camera and Require Unlock on still work as before. The click-speed
   implementation is unchanged from the device-tested 161 ms result.

For a failure, tap **Settings → SidePress18 → Copy Last Result** immediately
after it and send the copied text. Include a crash report if SpringBoard or
Settings crashes. Removing the
tweak and respringing removes its hooks without modifying system files.

## Build and checks

With Theos and a current Apple iOS toolchain:

```sh
make package THEOS=/path/to/theos
```

The delivered package uses Linux LLVM 11, iPhoneOS16.5 SDK, and a binary
minimum of iOS 15 (runtime/package availability restricted to iOS 18).
For that older compiler, pass `ALLEMANDE=/path/to/allemande` and
`SP18_LDID=/path/to/ldid`. Staging converts legacy arm64e metadata and re-signs
all three binaries. The main tweak injects only into SpringBoard; a separate
Settings dylib adds native speed rows only when the expected identifiers and
controller method signatures are present. Omit ALLEMANDE with modern Xcode.
Toolchains/SDKs are not bundled.

New callbacks passed into Objective-C APIs are heap-copied with the C
`_Block_copy` runtime before ARC takes ownership. Three external callback
boundaries are checked in both architectures, including direct secure-scene
submission. Authentication uses a C function callback and libdispatch, avoiding the previous legacy stack-block ownership crashes.

```sh
cc -std=c11 -Wall -Wextra -Werror tests/click_speed_policy_test.c -lm -o /tmp/sp-speed
/tmp/sp-speed
cc -std=c11 -Wall -Wextra -Werror tests/press_policy_test.c -o /tmp/sp-press
/tmp/sp-press
cc -std=c11 -Wall -Wextra -Werror tests/launch_policy_test.c -o /tmp/sp-launch
/tmp/sp-launch
cc -std=c11 -Wall -Wextra -Werror tests/unlock_policy_test.c -o /tmp/sp-unlock
/tmp/sp-unlock
python3 tools/verify_package.py packages/com.brooktrout12.sidepress18_1.0.0_iphoneos-arm64.deb
python3 tools/verify_callback_cleanup.py packages/com.brooktrout12.sidepress18_1.0.0_iphoneos-arm64.deb /path/to/llvm-objdump
```

## References

- [iOS 18 runtime headers](https://github.com/qingralf/iOS18-Runtime-Headers),
  revision `cfdd406d3a0bbac8473571dda5482e155b1cc402`.
- [Native application launcher](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBDashBoardApplicationLauncher.h)
  and [secure-display scene factory](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBDeviceApplicationSceneEntity.h).
- [Lock Screen manager](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBLockScreenManager.h)
  and [Cover Sheet](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/CoverSheet.framework/CSCoverSheetViewController.h).
- [Shared flashlight controller](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardUI.framework/SBUIFlashlightController.h).
- [Side-button recognizers](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBLockHardwareButton.h)
  and [click timing fields](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBClickGestureRecognizer.h).
- [Generated Settings URL and specifier manifest](https://github.com/FifiTheBulldog/ios-settings-urls/blob/master/archive/preference-manifest-dump.txt)
  for `HOME_CLICK_TITLE` and the native speed identifiers.
- [Theos](https://github.com/theos/theos), [Allemande](https://github.com/opa334/allemande),
  and [Apple Blocks runtime](https://github.com/apple-oss-distributions/libclosure/blob/main/runtime.cpp).

The SpringBoard/CoverSheet references above describe iOS 17 interfaces, not
verified iOS 18 method bodies. See device checks before publishing as stable.
The tweak contains no networking or telemetry.
