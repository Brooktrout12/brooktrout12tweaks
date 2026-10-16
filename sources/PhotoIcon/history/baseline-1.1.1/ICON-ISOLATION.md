# PhotoIcon 1.0 beta — temporary wrong-app artwork

This document records the previous beta's fix. The user has since confirmed
that 1.0 beta works well with no observed bugs. Later betas add bookmark support
while retaining this per-view rendering; see `BOOKMARKS.md`. The original beta's
verification records are preserved under `debug/1.0-beta`; project-root records
describe the latest beta.

## Report and evidence

The user confirmed that 1.0.3 now opens the picker and changes icons without
SpringBoard crashes on an iPhone 11 Pro, iOS 18.6, Dopamine 3.0.9. Sometimes
changing one app also temporarily changes another app's artwork. The supplied
screenshot shows LocalSend displaying Settings artwork. A respring restores
the intended assignments, including the user's saved custom icons.

This points to a presentation or cache issue rather than incorrect saved
bundle identifiers. It does not establish which internal SpringBoard operation
produces the mix-up. There is no crash report for this behavior, and the issue
has not been reproduced in a local iOS runtime.

## Change

The previous hooks substituted custom images and layers into SpringBoard's
normal image-update methods. They did not explicitly clear custom presentation
when an image view was reused, and the refresh notification requested
model-wide icon image reloads. These paths could allow temporary custom artwork
to be retained or shared beyond the intended view.

This build keeps SpringBoard's native image and layer arguments unchanged.
PhotoIcon draws the masked photo in a separate CALayer associated with one
SBIconImageView and its app identifier. It checks that the image view's app
matches its labelled parent, and checks identity again after preparing the
image. Rebinding and reuse remove the owned layer before the native method
runs; a binding guard prevents reentrant updates from restoring it mid-reuse.

The layer follows native icon geometry and uses the existing SpringBoard icon
mask. Original native layer contents are never changed by the overlay code.
Saving or restoring refreshes tracked views for the affected app, without
reloading the icon model's shared image state. Clock's native image return value
also remains unchanged; the existing custom-icon hand visibility handling is
retained. Picker, crop, persistence, and callback compatibility code are unchanged.

## Verification and device check

- The beta compiles and links for arm64 and arm64e with an iOS 18.0 minimum.
- All 26 generated-code icon-isolation checks pass. The shipped 1.0.3 source
  fails these checks because it uses the previous rendering approach.
- All eight callback-setter, 36 system-block, and 16 linked-binary regression
  checks pass, retaining the earlier picker and startup crash protections.
- Rootless layout, injection filter, ABI conversion, and signed code pages pass
  package validation. Exact hashes and UUIDs are included with the source.

These checks validate the compiled implementation and package. They do not
execute SpringBoard, verify animation appearance, or prove that the reported
device behavior is resolved. After installing and respringing once, change
Settings and check LocalSend immediately. Then swipe between pages, open a
folder, and change or restore another app. Check both icon sizes and Clock when
convenient. If wrong artwork returns, capture a short recording from before
the edit through the incorrect result; no crash report is needed for a
display-only issue.

## Version and installation

The requested release label is **1.0 beta**. Its Debian version is `1.0~beta`,
which sorts below the previous 1.0.3. A package installer may therefore call the
replacement a downgrade. Install the supplied .deb directly and respring once.
The package identifier and saved-photo format are unchanged, so existing icon
choices and crop settings are retained.
