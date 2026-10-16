# PhotoIcon 1.1 — wider app-icon coverage

Author and maintainer: **Brooktrout12**.
Package: `com.brooktrout12.photoicon`, version `1.1`.

## Changes

- Closed-folder previews now receive replacement images and independent
  replacement CALayers for their miniature app and bookmark icons.
- SpringBoard's image and layer providers return the matching photo for
  consumers beyond the existing Home Screen overlays, including app-switcher
  icon requests. Folder and observed image caches refresh after save/restore.
- A separate `PhotoIconSystem` provider loads into UIKit processes. It handles
  common IconServices/UIImage app-icon requests, SearchUI icon loading, and
  UIActivity/SharingUI share-sheet app images. This includes Settings app entries.
- Frameworks loaded later are handled by a deferred dyld notification. Hook
  installation checks selector existence and the method's actual ABI first.
- Share extensions map through LaunchServices' exact containing-bundle record.
  There is no bundle-name prefix matching or global "currently selected app".
- Only finished cropped icons are exported. Catalog publication is atomic and
  occurs after all referenced PNGs exist. Existing choices are exported on
  startup. Restore Original removes the corresponding catalog entry.
- Clients invalidate caches through a Darwin change notification and a bounded
  file-change fallback. Their render keys include the exact identifier, saved
  image token, dimensions, display scale, and mask settings.
- New photo layers are allocated per request; native images and native layers
  supplied by the system are not mutated. The original Home Screen reuse and
  binding checks remain intact.

The picker, crop editor, dismissal animation, crop math, and legacy arm64e block
compatibility helper are byte-for-byte identical to the device-confirmed 1.0
source. No temporary menu tracing is added.

## Upgrade

Install over Brooktrout12 PhotoIcon 1.0 and respring. There is no package-ID or
private-store migration. Restart already-running consumer apps to load the
new provider. Previously saved photos do not need to be selected again.

## Validation and limits

Both providers compile for arm64 and arm64e. Host checks cover callback code
generation, image-view isolation, actual linked callbacks with matching dSYMs,
rootless layout, executable installer script, minimum OS version, and every
signed code page. Newly added translation units are included in the unsafe
Objective-C block-handoff audit. Source and package contents are scanned for
personal-name remnants.

The new coverage has not been run on a device or simulator. In particular,
share-sheet artwork was investigated through iOS 18 interfaces; no device
share-sheet screenshot was supplied, so its previous behavior was not confirmed.
App-switcher support is supplied through the shared SpringBoard and UIKit icon
providers; no unverified app-switcher view ivars are accessed.

On-device confirmation should compare a changed icon in a closed folder,
Spotlight suggestions/search, the app-switcher header, Settings > Apps, and
an app entry in the share sheet. Restore one changed icon and compare again.
A consumer that keeps an image without requesting it again can require reopening
its screen or restarting the app. App-owned custom artwork and unrelated UI
symbols are not covered.
