# SwitcherSweep 1.0.7

Developer: **brooktrout12**

A frosted **Close All** button near the bottom of the iPhone App Switcher.
Tap it to sweep the cards upward, close the apps, and return to the Home Screen.
Designed for iOS 18 rootless jailbreaks; no settings to configure.

## Install

Install `com.brooktrout12.switchersweep_1.0.7_iphoneos-arm64.deb` over the previous
version and respring. Open the App Switcher normally to reveal the button.

## Behavior

- Uses Apple's system blur material with a subtle border and rounded pill shape.
- Begins a short fade when iOS starts entering the App Switcher.
- Gently lightens the whole blurred button while pressed; releasing or dragging
  outside fades the tint back. The title and button keep their normal size.
- Sweeps visible cards upward with a short stagger; native closing also covers
  app cards that are off screen. Apps playing music are included.
- Returns to the Home Screen using the native animated transition.
- Removes the button before transitions to Home or an app and when no cards remain.
- Prevents repeated taps during closing. Leaving the switcher before the sweep
  commits cancels the pending close requests.
- Uses a brief card fade when the iOS Reduce Motion option is enabled.

App selection comes from the App Switcher's app layouts and display items.
The tweak asks SpringBoard to perform user-initiated app closing.

## Changes in 1.0.7

Replaces the press scale with a subtle white tint over the entire blurred pill.
The tint appears over 0.06 seconds and clears over 0.14 seconds on release,
cancellation or dragging outside. Dragging back inside restores the highlight.
Button entry, early-tap handling, app closing and transition cleanup are unchanged.
Diagnostic file logging remains removed.

## Validation

Build, existing policy tests, package and signature checks passed. Source review
confirms that the runtime change is limited to button feedback. The new feedback
still needs confirmation on the phone; the host cannot run SpringBoard.

Uninstall and respring to remove the button. See BUILD.md for implementation and
rebuilding, and SOURCES.md for the private API references.
