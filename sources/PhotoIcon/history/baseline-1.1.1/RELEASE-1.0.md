# PhotoIcon 1.0

The user confirmed that beta 3's app and bookmark icon editing work correctly
and reports that the subsequent 1.0 UI and logging changes work as well.

## Brooktrout12 package identity

The package, code-signing identifier, menu identifiers, notification name,
and storage queue label now use `com.brooktrout12.photoicon`. Author and
maintainer credits use **Brooktrout12**. The release version remains `1.0`.
The crop editor, animation, bookmark support, and saved-data format are unchanged.

Remove the installed PhotoIcon package before installing
`com.brooktrout12.photoicon_1.0_iphoneos-arm64.deb`, because it has a new package
identifier. Then respring. Saved photos and crops remain in
`/var/mobile/Library/Application Support/PhotoIcon` and are read by the new build.

## Crop editor dismissal

The crop editor previously removed its auxiliary window immediately on Save or
Cancel. It now slides the navigation view down over 0.32 seconds and removes
the window when the animation finishes. The window's background is transparent
so the Home Screen becomes visible during the transition. Reduce Motion uses
a 0.15-second fade.

Save starts dismissal only after storage succeeds and keeps controls disabled
through the transition. A failed save re-enables the editor and shows the error.
Cancel dismisses without committing crop changes. The Photos picker's existing
UIKit dismissal remains unchanged.

Closing invalidates the editing session immediately, prevents repeated close
requests, and cancels pending photo loading. The animation completion checks
that its captured window is still the current editor before cleanup. Locking
continues to close the editor immediately. Immediate cleanup clears window
identity before removing animations, preventing reentrant or late completion
from closing a newly opened editor.

Both animation callbacks use the same explicit runtime-copy mechanism as the
earlier arm64e crash fixes.

## Diagnostic removal

The bookmark-step logging function and all calls to it are removed, along with
the verbose startup message. No menu-step trace is written. Store initialization
removes the old `Bookmark-Diagnostics.txt` file if it exists. This cleanup names
that file explicitly and does not alter saved icons, source photos, or crops.

Matching debug symbols remain in the source archive for maintenance; they are
not installed on the device or active logging code. Old development binaries
and their verification records are excluded from this renamed distribution.

## Validation

The release is compiled for arm64 and arm64e and packaged for rootless iOS 18.
All eight callback-setter, 44 system-block, 26 icon-isolation, and 22 linked-code
checks pass. The two new animation callback copies are checked in the actual
packaged binary with matching dSYMs. Package layout, injection filter,
deployment target, ABI conversion, and signed code pages pass verification.
The final binary is also checked for absence of the former menu trace messages.

The renamed package and every file in its source archive are scanned for any
remaining references to the previous personal name, including the decompressed
package contents and both architectures' code signatures.

These checks do not render UIKit. The earlier 1.0 build was reported working by
the user; this rebuild changes identity strings and credits only and has not
been separately installed on the device.
