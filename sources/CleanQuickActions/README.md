# Clean Quick Actions 1.0.2

By Brooktrout12. Rootless update for iOS 17 and 18.
Package ID: `com.brooktrout12.cleanquickactions`.

## This update

Adds an **iOS 17-only** fix for the thick section divider between groups of
Home Screen Quick Actions. This is a section decoration, separate from the
thin row separators already handled by the tweak. Long German labels such as
“Home-Bildschirm bearbeiten” retain their native wrapping and action sizes.

The iOS 18 separator behavior is unchanged. The new section-model hook is never installed on iOS 18.

## Install and use

Install `CleanQuickActions_1.0.2_rootless.deb` over the existing release in your
rootless package manager, then respring. The same **Clean Quick Actions**
switch in Settings controls both thin and thick dividers. Your current choice
is retained. There is no new settings pane or additional option.

The switch defaults to on. Turn it off to restore native separators. Close
and reopen the Quick Actions menu after changing the switch. Settings changes
do not require another respring. The Settings icon and registration are
unchanged. The new fix is intended for the Touch ID device, iOS 17.x; the
package also continues to admit iOS 18 and includes arm64 and arm64e slices.

## Implementation

The existing SpringBoard-only injection, icon-menu ownership checks, three
separator-view hooks and restoration logic are retained from 1.0.1.
`IOS17Sections.m` adds a guarded getter hook for
`_UIContextMenuSection.wantsSectionSeparator` on iOS 17. Section objects are
resolved from each verified icon menu's diffable data-source snapshot. Weak
owner references keep the override tied to that menu without retaining it.

The getter returns false only while the existing switch is enabled and its
owner is still an icon menu. UIKit's underlying value is never overwritten.
Unmarked sections return the original result. Layout is invalidated only when
ownership or the effective switch state changes, allowing cached section
decorations to update. UIKit continues to size the actions and their labels.
The dedicated separator gap may disappear with its decoration.

No label, font, line-limit, action, cell-height, menu-color or global UIKit
appearance override is added. Existing third-party actions remain in their
original order. The new code uses C callbacks, not Objective-C block literals.

## Verification and limits

Both architectures compiled with warnings treated as errors. The package
checks verify rootless paths, dependencies, the unchanged Settings switch,
iOS 17 deployment metadata, legacy arm64e metadata conversion, absence of
block imports, and every signed code-page hash. The existing visibility and
restoration tests pass. `validation/source-scope.json` records the source and
asset comparison against 1.0.1, and the source archive contains matching
debug symbols.

No iPhone or simulator is attached to this build environment. **The new iOS 17
fix needs visual confirmation on the Touch ID device.** Header checks used iOS 17.0.3, not
a dump of the exact 17.x build. Runtime guards skip mismatched interfaces.
The package checks do not prove runtime appearance or third-party compatibility.

On the Touch ID device, long-press Settings and check that the band below the two-line
German action disappears, both lines remain readable, and all actions work.
Also check scrolling and switch-off restoration. The compatible iPhone does not
need this update for its already-working iOS 18 behavior.

## Build and sources

See `BUILD.md` for current build commands. The exact changes from the bundled
1.0.1 project are in `IOS17-section-divider.patch`. Earlier documentation and
reports remain under `history/`; they do not describe the new package.

Primary interface references:

- [iOS 17.0.3 section model](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/UIKitCore.framework/_UIContextMenuSection.h)
- [iOS 17.0.3 menu list](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/UIKitCore.framework/_UIContextMenuListView.h)
- [Apple diffable data-source snapshots](https://developer.apple.com/documentation/uikit/uicollectionviewdiffabledatasource/snapshot())
- [Apple collection-layout invalidation](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/invalidatelayout())

The implementation is original tweak code; Apple framework implementations
are not bundled. The package depends on PreferenceLoader and a
Substrate-compatible hooking library supplied by the rootless environment.
