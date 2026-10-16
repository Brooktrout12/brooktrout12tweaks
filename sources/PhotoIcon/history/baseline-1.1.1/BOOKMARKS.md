# Home Screen bookmark support

The user confirmed that bookmark editing works correctly in beta 3. Release
1.0 retains that implementation and removes its temporary menu diagnostic log.

## Menu integration

PhotoIcon hooks `SBIconView.contextMenuInteraction:configurationForMenuAtLocation:`
and wraps the original configuration's action provider for bookmarks. It first
invokes the native provider with the original suggested actions, then appends
PhotoIcon's inline group to the returned UIMenu. `menuByReplacingChildren:`
preserves the native root menu metadata and children. The original configuration
and preview are retained. Repeated requests reuse the saved native provider
instead of nesting wrappers; non-bookmark configurations return unchanged.

This final-menu integration replaced beta 2's suggestion-only approach, whose
Change Icon action did not appear on the user's device.

## Identity and behavior

Bookmark keys use `webclip:` plus the persistent `SBHBookmark.identifier`, with
`UIWebClip.identifier` as a fallback when the wrapper supplies no identifier.
Both paths validate a non-empty string. App keys keep their existing bundle
identifiers, requiring no migration. URLs, titles, browser bundle identifiers,
and object addresses are never used as bookmark keys. App Clips are excluded.

The menu offers Change Icon, plus Adjust Icon and Restore Original Icon when
a photo is saved. Actions use the same picker, crop editor, storage, and isolated
per-view rendering as apps. The view must still match the captured bookmark
identity when building the menu, selecting an action, and after menu dismissal.
Custom artwork is cleared when an icon view is reused.

Original bookmark menu actions, launch URLs, and icon files are preserved.
Separate bookmarks for the same website can have independent custom artwork.
Deleting and recreating a bookmark creates a new identity.

## Maintenance

The native provider wrapper and UIAction handlers use `PI_SYSTEM_BLOCK` to
preserve the arm64e callback fixes. Current verification records are documented
in `BUILD.md`; matching symbols are in `debug/1.1.1`.

The temporary beta 3 menu trace has been removed. Release 1.0 deletes the old
trace file during store initialization. See `RELEASE-1.0.md` for the new crop
editor dismissal and its validation scope.

## Interface references

The code uses the pinned UIKit SDK's public action-provider contract and
checked iOS 18 runtime declarations for
[SBIconView](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBIconView.h),
[UIContextMenuConfiguration](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/UIKitCore.framework/UIContextMenuConfiguration.h),
[SBHBookmarkIcon](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBHBookmarkIcon.h),
[SBHBookmark](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardHome.framework/SBHBookmark.h), and
[UIWebClip](https://github.com/qingralf/iOS18-Runtime-Headers/blob/main/PrivateFrameworks/UIKitCore.framework/UIWebClip.h).
Required selectors are checked before use.

Version 1.1 also routes the same persistent bookmark identity into closed-folder
miniatures. Native bookmark menu behavior and the editor remain unchanged.
