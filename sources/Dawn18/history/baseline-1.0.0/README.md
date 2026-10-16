# Dawn 18 — 1.0.0

Independent light/dark controls for an iOS 18 rootless jailbreak, with a native
Settings page inspired by **Dawn by EthanRDoesMC** and its title-above-segment
layout. Dawn 18 author: Brooktrout12.

**Build status:** still **version 1.0.0**, as requested. The user confirmed that
the preceding revision works on their iPhone 11 Pro running iOS 18.6. This
revision renames the Settings label to **Ringer** and adds **iOS 10 style** as
the fourth Home Screen Quick Actions choice. It uses a live, translucent light
blur with native dark text/icon styling, preserving iOS 18's menu geometry and
actions. See `IOS10-STYLE.md` for implementation and validation details.

All ten existing preference keys and saved choices are retained, as is the
credit to **Dawn by EthanRDoesMC**. Only Quick Actions gains a fourth choice.
The rename does not reset the saved ringer selection.

Compiled for arm64 and arm64e and checked on the build host. These new changes
have not yet been tested on an iPhone. The relevant private interfaces were
inspected in iOS 18.2 headers/decompiled methods, with runtime signature checks
for the device's actual interfaces. This does not establish complete 18.6
compatibility. There is no device or simulator attached to the build workspace.
The earlier startup fix and its binary regression gate are preserved; see
`CRASH-FIX.md`.

## Install

1. Keep the original Dawn uninstalled. Dawn 18 declares a conflict with its
   package so the two appearance engines cannot be installed together.
2. While jailbroken, install `Dawn18_1.0.0_rootless.deb` using Filza or your local
   package installer. Your existing ElleKit and PreferenceLoader satisfy the
   ordinary injection and Settings dependencies. Cephei is not required.
   The version remains 1.0.0: choose **Reinstall** if your installer offers that
   instead of Upgrade. Install the newly supplied file, not the earlier download.
3. Respring, then open **Settings → Tweaks → Dawn 18**. If Settings was already
   open, close it from the app switcher before reopening it.
4. Choose Default, Light, or Dark under each title. **Home Screen Quick Actions**
   also offers **iOS 10 style**. All ten categories initially use Default on a
   fresh install. Existing Dawn 18 choices are retained; no original Dawn
   settings are imported.

There is no Home Screen app. With PreferenceLoader versions that display
individual tweaks directly in Settings, find the same **Dawn 18** entry there.
The package uses PreferenceLoader's normal registration; it does not add a
second Tweaks menu or alter your Settings organization.

## Controls

| Control | Scope |
| --- | --- |
| Applications | One choice for native app windows/controllers, including Settings. This is not a per-app list. |
| Folders | Both closed folder tile backgrounds and expanded folders. Mini app icons keep iOS's icon appearance. |
| Dock | Dock view/material hierarchy. |
| Widgets | Home Screen widget hosting views/controllers. Shared widget hosts can also affect Today View widgets. |
| App Library | App Library views/controllers and folder backgrounds reused inside them. |
| Home Screen Quick Actions | The long-press menu supplied by Home Screen icons, including icons in folders and App Library. Default / Light / Dark / iOS 10 style. The fourth choice changes the background blur and uses dark text; it preserves menu shape and actions. |
| Ringer | The top ringer/silent-mode pill. The previous HUD implementation and saved key are retained; the user reports the volume HUD has no visible light/dark difference on their device. |
| Banners | Incoming notification banners and their long-press expanded interface, classified by the originating destination. |
| Notifications | Notification cards outside banner hosts, their swipe Options/Clear buttons, and the popup opened by Options. Expanded list cards retain this scope too. |
| Notification Center Buttons | List-wide X/Clear All and section controls, separate from each card's swipe actions. |

Light and Dark override the device's light/dark selection. Notifications Default
clears local style overrides to let UIKit inherit the current appearance,
including later device theme changes; it does not restore a captured card color.
Other controls retain their existing native-override restoration behavior.
**Reset to Default** clears all ten saved choices.

**Send Test Notification** sends an on-device preview headed “Dawn 18.” Stay in
Settings to see the banner, then open Notification Center or long-press the
notification to inspect its clear controls. It is silent and replaces the previous
preview. Clear it normally when finished; Dawn 18 does not expire it. The banner
still hides after its normal on-screen timeout, without clearing the saved card.
It does not send a message to anyone or
impersonate a notification from one of your apps. Each tap gets an acknowledgement
from SpringBoard; an unavailable interface produces a short failure code in
the pane. “Preview sent” means the native dispatcher call returned; the
build host cannot verify that it actually appeared on the device.

Live windows and view hierarchies are refreshed when you change a setting.
New/returning views also receive the choice. Reopen an app if it retains cached
appearance. Some third-party apps use custom colors or a separate internal
theme; a UIKit appearance override does not rewrite those colors. Widget
extensions and wallpaper-derived materials may need a new render or additional
version-specific work if they do not honor their host's appearance.

This does not control iOS 18's separate light/dark/tinted **app icon** setting,
Lock Screen media player, or system-wide dark mode.

## Design and process isolation

- Original Objective-C/C implementation. No code, icon, background image, or
  preference classes copied from Dawn. The UI concept is credited to Dawn and
  its author EthanRDoesMC.
- Uses Apple's public `overrideUserInterfaceStyle` APIs on recognized UI
  scopes. It does not globally replace `traitCollection`, guess material recipe
  numbers, patch ivars, change file-provider state, or use Cephei/Swift.
- Closed folder backgrounds are identified by their actual `backgroundView`
  getter on `SBFolderIconImageView`. iOS 18 explicitly sets this background's
  appearance independently from the parent. The existing setter interception
  preserves that native choice and restores it when Default is selected. The
  icon-image parent and mini-icon grid receive no folder-wide override.
- Quick Actions observes `_UIContextMenuUIController`'s menu construction in
  SpringBoard. It follows the controller's presentation and interaction delegates,
  verifies that the interaction belongs to an `SBIconView`, then marks that
  menu's actual `UIView` for the existing public appearance override. Action
  cells and submenus inherit its traits. Generic menu class names remain
  excluded. No icon, Home Screen window, or menu-style trait proxy is added.
  This replaces the ineffective `preferredTraitCollection` approach: iOS 18.2's
  `_UIContextMenuStyle` copy implementation omits that property, and the menu
  UI controller does not read it. See `MENU-PREVIEW-FIX.md` for the evidence.
- **iOS 10 style** maps to native light foreground styling plus the original
  public `UIBlurEffectStyleLight` blur. Only an actual `_UIContextMenuListView`
  beneath the verified icon-menu marker receives the material change. Its
  `backgroundView` and optional `cvBackgroundView` are updated in place, after
  getter-signature, visual-effect-class, and descendant checks. Native effects
  and background colors are restored when leaving the choice or scope. One
  signature-checked menu-list `layoutSubviews` hook covers lazy backgrounds,
  submenus and scrolling; it calls the original first and changes no geometry.
  No global effect setter, material recipe, layer filter, screenshot overlay,
  menu action or input handler is replaced. Read `IOS10-STYLE.md` for limits.
- The same existing menu-construction hook also identifies notification Options
  through the interaction's source view and its bounded ancestor chain. Only
  notification action buttons/containers or notification cells opt a menu into
  Notifications. A cell is a source marker, not a broad appearance override.
  Both menu-scope markers are reset on reuse. No generic menu/UIButton override
  or additional menu hook is installed.
- iOS 18's notification cell uses `PLSwipeInteraction`, which installs a
  `PLActionButtonsPresentingView` containing `PLPlatterActionButtonsView` and
  individual `PLPlatterActionButton` objects. These are contextual markers,
  not global notification classes. Only a notification source ancestor opts
  them into Notifications. The actual button's `backgroundView` gets the same
  scoped treatment. Generic PlatterKit uses, materials, and buttons remain
  untouched. No material recipe numbers or button actions are replaced.
- Ringer retains the existing `SBRingerHUDViewController`, `SBRingerPillView`, and
  `SBElasticVolumeViewController`. Their materials inherit the public appearance
  override. The shared elastic-slider/value-controller classes are not matched,
  so brightness and Control Center sliders do not acquire this preference.
  Default restores the native HUD override through the existing state engine.
  The stored `RingerVolume` name is intentionally unchanged for compatibility.
- Notifications Default uses an internal inherited-style selection that is never
  saved to preferences. It actively keeps `overrideUserInterfaceStyle` unspecified
  on recognized notification roots, including new/reused cards and native setter
  calls, instead of restoring a stale Light/Dark override. Once unspecified,
  normal UIKit inheritance tracks theme changes without polling or a theme daemon.
- Expanded notification views/controllers remain context-dependent, not globally
  assigned to Banners. Their bounded, signature-checked delegate chain identifies
  the originating short-look controller and banner destination even after iOS
  reparents the expanded interface. Expanded Notification Center cards retain
  the Notifications choice. Generic PlatterKit views remain excluded.
- `Dawn18SpringBoard.dylib` has a SpringBoard-only injection filter. Its view
  rules are intentionally narrow: generic `SBFolderView`/`SBFolderController`
  are excluded because they also encompass the whole Home Screen.
- `Dawn18Apps.dylib` uses the UIKit injection filter to reach installed apps.
  **A UIKit filter alone does not exclude daemons.** Its C initializer therefore
  checks the main executable's path before Foundation, preferences, or hooks.
  Non-app executables, extensions, XPC services, and listed service apps return
  immediately. The dynamic loader may map the library into another UIKit-linked
  process, but this tweak installs no hooks or preference observers there.
- A passing initializer defers Objective-C work until the main queue runs,
  outside dyld initialization. Preference reads use a serial background queue;
  UIKit mutations run on the main thread.
- C function callbacks and selector-based observers/operations replace all
  compiler-generated Objective-C blocks. The package checker rejects block
  runtime references in every slice, including the Settings bundle, to prevent
  the recorded old-arm64e block-ISA incompatibility from being reintroduced.
- The notification preview runs only when its Darwin request is posted. It
  retrieves SpringBoard's existing `NCNotificationDispatcher` and uses current
  banner/Cover Sheet transport identifiers plus the explicit Lock Screen and
  Notification Center list-membership identifiers. It posts directly, without adding
  a dispatcher source or requiring the native notification source's getter.
  Five clear/lookup hooks are installed lazily after all their runtime signatures
  are verified. Every clear call invokes its original handler with the original
  arguments; additional cleanup affects only the current preview UUID. Its
  UUID lookup falls through to the original for every other request. All preview
  state changes run on the main thread. Cleanup is deferred outside callback
  stacks, and removing one destination preserves the others. Partial list
  withdrawals also carry the Cover Sheet transport identifier so they reach
  its list model. No lock-screen persistence flags or system migration settings
  are overridden.
- The preview action runner forwards an **existing OS-created completion** to
  the OS dispatch implementation. It does not create a block literal, copy a
  block with compiler ARC block machinery, or call a block function pointer.
  Both architectures still pass the no-block-runtime-import gate.
- No extra daemon, continuous polling, runtime log file, automatic restart,
  network traffic, analytics, or privileged helper. There is one delayed reply
  read per button tap, but no notification expiry timer. Persistent tweak
  preferences are the ten choices in `com.brooktrout12.dawn18`; iOS may manage
  its own notification history for the local preview.
- Hooked selector signatures are checked at runtime. Private class
  names are matched at runtime and absent classes are left untouched. Missing
  class coverage can mean an individual option has no effect, not that the
  package has verified that feature on every iOS 18 release.

Removing Cephei avoids that dependency's initialization path from your earlier
capture. It does not prove this new tweak cannot have an unrelated defect.

## Useful first device check

Choose **Home Screen Quick Actions → iOS 10 style**, then long-press an icon.
Check that the menu has a translucent blur with more wallpaper color visible
and dark text, while its corners, dimensions and actions behave as before.
Try a tall menu, scrolling, and a submenu if one is available.

Switch Quick Actions between iOS 10 style, Light, Dark and Default, closing and
reopening the menu each time. The three native choices should return to their
previous appearances. Reopen Settings and scroll its options to confirm the
fourth choice remains selected and other rows still have three choices.

Check the **Ringer** label and retained selection. Notification cards, their
swipe Options/Clear buttons, the Options popup, banner expansion and folders
should continue to use their existing choices. The new blur must not affect
the notification Options popup or generic app/share menus.

The test-notification delivery and no-expiry behavior are unchanged. If anything
fails, report the exact view, both appearance choices, and any N-code shown.

If an option does not change its element, note the option, selected/system
appearance, and the exact view (for example, a closed folder icon versus an open
folder). The source keeps those scopes separate so they can be corrected
without adding broader service hooks.

## Remove

Select **Reset to Default**, remove Dawn 18 in your package manager, and
respring. Reopen affected apps so an already-loaded copy is unloaded. No native
system theme preference is rewritten; the tweak's saved choices may remain for
a future reinstall.

## Build

Requires Theos, an iOS SDK, an iOS compiler/linker, and ldid. The 16.5 SDK supplies
the public APIs used here; the package/runtime guards restrict use to iOS 18.
The private Preferences framework is used only by the Settings bundle.

```sh
export THEOS=/absolute/path/to/theos
make clean package
```

Use a modern Xcode toolchain for native arm64e builds. When using a Linux Clang
toolchain that emits the old arm64e ABI, supply the allemande converter:

```sh
make clean package ALLEMANDE=/absolute/path/to/allemande
```

The Makefile converts and re-signs all three staged binaries before packaging.
Do not set ALLEMANDE when using a current Apple arm64e toolchain. Do not add a
system-wide old-ABI shim. This release uses Clang 11.1.0, iPhoneOS16.5.sdk,
Theos, allemande, and ldid, as with the earlier rootless build in this workspace.

The rendered Settings icons are included. To regenerate them, install Pillow
for your local Python and run `python3 scripts/make_icon.py`.

Portable checks:

```sh
cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
  Rules.c tests/test_rules.c -o /tmp/dawn18-test-rules
ASAN_OPTIONS=detect_leaks=0 /tmp/dawn18-test-rules
python3 tests/test_preferences.py
python3 scripts/verify_package.py packages/com.brooktrout12.dawn18_1.0.0_iphoneos-arm64.deb
```

The C checks cover process exclusions, category separation, reversible appearance
state, the Quick Actions-only value 3, and malformed preference rejection. The
preference source-contract checks guard key order, Settings coverage, the Ringer
label and read/write/reset bounds; they do not
execute CFPreferences or UIKit. The package checker validates rootless paths, filters,
dependency linkage, bundle metadata, architectures, signatures and every signed
code page, and rejects compiler block runtime imports. These checks do not replace a device test. See `VALIDATION.json` in
the delivered source archive for the results for this build.
LeakSanitizer is disabled in the command above because this build host runs
under tracing; AddressSanitizer and UndefinedBehaviorSanitizer remain enabled.
The portable checks also cover the folder-icon context marker, exclusion of
generic menu views, and preview reply identifiers. The archive includes the
matching dSYM files under `debug-symbols/` for diagnosing a later
crash while the package version remains 1.0.0. They are not installed on the phone.

## References

- [Apple: UIView appearance override](https://developer.apple.com/documentation/uikit/uiview/overrideuserinterfacestyle)
- [Apple: UIViewController appearance override](https://developer.apple.com/documentation/uikit/uiviewcontroller/overrideuserinterfacestyle)
- [Dawn, inspiration](https://github.com/EthanRDoesMC/Dawn)
- [iOS 18.2 folder icon header](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBFolderIconImageView.h)
- [iOS 18.2 menu-style header](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/UIKitCore.framework/_UIContextMenuStyle.h)
- [iOS 18.2 menu construction](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UIKitCore.framework/_UIContextMenuUIController.m)
- [iOS 18.2 mutable notification content](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/System/Library/PrivateFrameworks/UserNotificationsKit.framework/NCMutableNotificationContent.m)
- [iOS 18.2 notification dispatcher header](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/UserNotificationsKit.framework/NCNotificationDispatcher.h)
- [iOS 18.2 decompiled interfaces and implementations](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore)
- The specific swipe-control and HUD interface references are linked in
  `BUTTONS-VOLUME-FIX.md`.
- The menu material references and screenshot-matching limits are documented
  in `IOS10-STYLE.md`.
- [Theos](https://github.com/theos/theos)
- [allemande](https://github.com/p0358/allemande)

The public UIKit declarations and PreferenceLoader interface were checked
against the local SDK/Theos headers. The iOS 18.2 material and menu implementation
paths and notification dispatch/clear callbacks were inspected for this update;
every private class has not been verified against 18.6.

License: MIT.
