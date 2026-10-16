# Build and implementation

## Package

- Name/version: SwitcherSweep 1.0.7
- Author: brooktrout12
- Package/signing identifier: com.brooktrout12.switchersweep
- Architectures: arm64 and arm64e; Debian architecture iphoneos-arm64
- iOS deployment target: 18.0; package dependency range 18.x
- SpringBoard-only injection filter and constructor guard
- Frameworks: UIKit, Foundation, QuartzCore; rootless Substrate

## Build on macOS

With Theos, ldid and a current Xcode iOS SDK:

```sh
export THEOS=/path/to/theos
make clean package TARGET=iphone:clang:latest:18.0
```

## Build on Linux

The supplied package was built with Theos revision
5280bd038207e14f8bd76f5417aa2fe641c03228, L1ghtmann's llvm-project test-210562a
clang 11.1.0, and Theos iPhoneOS16.5.sdk master-146e41f. Deployment remains iOS 18.
The signing wrapper converts the merged image with p0358/allemande revision
43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9 before ad-hoc signing it with ldid.
The old-ABI linker warning occurs before that conversion; the verifier checks
the converted arm64e constant strings and final signature hashes.

```sh
export THEOS=/path/to/theos
export BT_ALLEMANDE=/path/to/allemande
export BT_LDID="$THEOS/toolchain/linux/iphone/bin/ldid"
bash scripts/build-linux.sh
```

The source archive includes matching dSYMs, not the compiler or SDK. Archive hashes:

```text
a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e  iOSToolchain-x86_64.tar.xz
5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb  iPhoneOS16.5.sdk.tar.xz
```

## UI and event handling

The button is a native UIButton containing UIVisualEffectView with
UIBlurEffectStyleSystemThinMaterialDark. Its 138 × 46 point frame is centered
above the bottom safe area; the target 375 × 812 point portrait layout puts it
at x=118.5, y=704, matching the marked area of the reference screenshot.

The tweak hooks only SBFluidSwitcherViewController lifecycle/layout updates,
its visible-card update, its gesture touch filter, and the switcher controller's
transition preparation/begin/end notifications. It checks the native destination
during transitions and switcher visibility when settled before showing the control. The stock background gesture recognizer declines touches inside
the button or the temporary animation overlay, allowing the button to receive
TouchUpInside. Other touches and hooked methods forward to their originals.
A reentrancy guard prevents layout updates caused by the button from recursing.

The native controller also participates in ordinary app/Home transitions. Entry
is detected from SBLayoutStateTransitionContext.toLayoutState's
unlockedEnvironmentMode. The native values for App Switcher and Home come from
SBSwitcherTransitionRequest.requestForActivatingAppSwitcher and
requestForActivatingHomeScreen. These factories construct data only; neither
request is submitted. Their long-long getters are checked against the runtime
signature. No numeric environment-mode constant is assumed.

An entering transition permits the button before the old visibility flag changes.
Preparation and begin notifications update the control before and after the
original native method so a newly attached window can show it within that event.
Repeated notifications reuse the button and do not restart its fade. Interaction
is enabled throughout entry, and the native background recognizer rejects button
touches. BTPress records a unique request token and monotonic start time.

Both SBSwitcherController and SBFluidSwitcherViewController begin/end callbacks
supply the native SBLayoutStateTransitionCoordinator. A weak NSHashTable retains
its identity without retaining the coordinator itself. Signature-checked
isTransitioning supplies current readiness; context.isComplete is a fallback
when the native coordinator is unavailable. The switcher controller's layoutState
and its unlockedEnvironmentMode help distinguish a settled departure. Lifecycle
and preparation notifications still control immediate material teardown, but
are not treated as sufficient evidence to discard an accepted request.

Only one token-checked wake can be outstanding, running in common run-loop modes
at 1/60 second while a request is pending. A momentary absent window is tolerated;
continuous absence or a settled non-switcher state for 0.20 second confirms exit.
A new touch outside the waiting button cancels explicitly. An unresolved waiting
state after five seconds releases the pending request. No idle polling
occurs. A settled tap can start synchronously.

The request stays owned throughout phase 1's card animation. Native retargeting,
disappearance, or lost readiness pauses the sweep by cancelling its callbacks
and restoring temporary visuals, without clearing the accepted request. Readiness
then restarts the same action. BTCommit rechecks live state and the native delegate;
only immediately before sending close commands does it mark phase 2 and consume
the request. This separates visual interruption from user cancellation. A nested
update or stale callback cannot send duplicate close commands.

Every outgoing or unknown transition still detaches the button before forwarding
the original preparation/begin callback. Disappearance also detaches it. If the
new destination getter/factories are unavailable, the control retains 1.0.1's
end-of-transition fallback, now with a fade rather than a one-frame appearance.

The button is constructed at its final frame with a nil visual effect and a
transparent title. A 0.18-second UIKit animation transaction changes the effect
to SystemThinMaterialDark and the title alpha to 1; Core Animation fades its
border over the same interval. The button and live effect stay at alpha 1.
The title is a sibling of the effect, not its ancestor. Legacy UIView animation
transactions avoid compiled block literals on the supplied Linux arm64e toolchain.

Version 1.0.7 animates a white tint on the visual effect view's contentView:
12% opacity while pressed, transparent otherwise. It uses 0.06 seconds on touch
down/drag enter and 0.14 seconds on release/drag exit/cancellation, beginning
from the current animation state. The tint is clipped by the existing pill,
sits behind the label and does not intercept touches. No transform is applied.
The button and live blur ancestors remain at alpha 1. The tint belongs to the
same effect view and is removed by the existing transition cleanup.

Removal clears the effect and detaches/releases the button. The live-blur cleanup
that fixed 1.0.0's shadow remains in place. See Apple's UIVisualEffectView guidance
in SOURCES.md. There is no full-screen opacity overlay or persistent display link.

Runtime selectors with the btss_ prefix handle the button and three one-shot
scheduled phases. There are no compiled custom Objective-C classes or block
literals. Manual reference counting and native associated dictionaries retain
state; all temporary card snapshots and retained close targets are released at
completion or cancellation. Pending callbacks retain a generation token and
become inert after visual rollback or cancellation. No idle timer is installed. The pending wake exists only for an accepted action.
Version 1.0.6 removes the event trace, observation history, serial writer queue
and JSON file output. Request completion retains the same pending-token guard
and cleanup. Exceptional native failures can still emit an error to the system
console; there is no per-attempt logging or diagnostic file creation.

## Sweep and close sequence

1. A deliberate button tap in the active switcher captures app-layout/display-item
   targets from both the current controller and recent layouts. SBDisplayItem
   equality deduplicates scene references. Native killing eligibility is honored;
   Home Screen items and explicit shell/system identifiers are excluded.
   Only containers whose app layout matches a captured target may be hidden or
   snapshotted; Home containers remain native.
2. Visible card containers are snapshotted in their original stacking order.
   Core Animation moves the snapshots upward over 0.24 seconds, staggered by
   0.028 seconds, capped at 0.112 seconds. The real cards are temporarily hidden
   behind this overlay and restored on cancellation. No snapshot is saved to disk.
   The model-layer opacity/transform is also set to its final invisible position,
   so later native snapshots cannot recapture the pre-animation card.
3. At 0.38 seconds, if the switcher is still active and the generation matches,
   the native delegate receives
   switcherContentController:deletedDisplayItem:inAppLayout:forReason: for each
   captured display item, with its real controller and layout. Reason 0 is the
   native user-close reason used by killContainer:forReason:. This delegates
   app/scene destruction and recent-card removal to SpringBoard and does not
   require offscreen card views to be instantiated.
4. After 0.08 seconds, the live blur, snapshot overlay and card overrides are
   synchronously removed. Then the coordinator is asked to dismiss to
   SBAppLayout.homeScreenAppLayout with animation enabled. The native Home button
   handler is a signature-checked fallback if that transition is unavailable.
5. The delayed callback only releases bookkeeping. If native deletion starts a
   transition before the Home request, its preparation callback performs visual
   cleanup first. Once Home is requested, layout callbacks never hide newly
   created containers. Original hidden flags are restored only if a container
   still represents the same layout, never onto a recycled Home/app container.

With Reduce Motion enabled, snapshots fade over 0.16 seconds and closing begins
at 0.18 seconds. The closing and Home behavior is the same.

## ABI guards and verification

Every invoked private getter/action is checked for its expected result type,
argument count and argument encodings before dispatch. Main controller methods
use object arguments, bool results where declared, and a full-width long long
for the deletion reason. Unsupported capabilities leave the action unavailable;
there is no fallback to shell commands, process IDs or unchecked ivar offsets.

```sh
bash scripts/test-policy.sh
python3 scripts/verify_package.py packages/com.brooktrout12.switchersweep_1.0.7_iphoneos-arm64.deb
```

The focused C tests check shell exclusions, inclusion of ordinary/music apps,
invalid input, safe-area placement at five screen sizes, 12 presentation scenarios
(entry before visibility catches up, settled entry, app launch, cancellation,
unknown destination and view disappearance), eight early/settled/cancelled tap
scenarios, nineteen pending-delivery observations (including transient absence, a
sweep retarget after start, confirmed departure and a bounded timeout), and that every allowed
card-animation delay ends before the close phase. ASan and UBSan are enabled;
LeakSanitizer is disabled because the managed build host cannot inspect its
/proc thread state. The test has no heap allocations.

The package verifier validates the exact two-file rootless payload, metadata,
SpringBoard filter, both Mach-O targets, linked frameworks and rootless search
paths, private selectors, absence of custom class/block metadata, converted
arm64e constant strings, and every signed code page. Matching dSYM UUIDs are
checked before archiving source. The compiled close and Home argument forwarding
is reviewed separately.

The user confirmed the working closing behavior before requesting this touch
feedback change. Version 1.0.7 changes only the button tint and removes the press
scale. Source comparison against 1.0.6 checks that request policies and the rest
of the runtime are unchanged. Both compiled slices are checked for the absence
of diagnostic trace state, JSON serialization, the writer queue and file-output
selectors. Matching dSYM UUIDs and source-archive checksums are verified before
delivery.

These host checks do not execute the iOS App Switcher. Version 1.0.7 has not been
tested on the phone.
