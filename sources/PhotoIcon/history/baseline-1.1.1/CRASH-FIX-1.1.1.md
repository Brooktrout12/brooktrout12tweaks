# PhotoIcon 1.1.1 — background icon rendering

By Brooktrout12. Package: `com.brooktrout12.photoicon`.

## Evidence

The supplied `SpringBoard-2026-09-20-185249.ips` is from an iPhone 11 Pro on
iOS 18.6. The crashing thread is
`com.apple.ControlCenter.sensorEntityIconCache`. Core Animation aborted while
trying to create an implicit transaction on that worker thread.

The loaded `PhotoIconSystem.dylib` arm64e UUID is
`80BE80C6-325C-352A-BB23-2B01FCDA7C32`, matching the delivered 1.1 symbols.
The three PhotoIcon frames resolve as follows:

| Image offset | Symbol |
| --- | --- |
| `0x6688` | `PISharedImage`, `PISystemIconReader.m:132` (`layer.bounds = ...`) |
| `0x5e74` | `PIIconServicesImage` |
| `0x50d4` | `PIISPreparedImage` |

The caller is `CCUIIconImageForApplicationIdentifier`, reached from
`CCUISensorEntityIconCache` preheating an app icon. This establishes a PhotoIcon
1.1 rendering bug. It does not establish that Photos or its open share sheet
caused the failure. The user encountered it while returning to Photos through
the app switcher; that transition coincided with the background icon request.

## Correction

`PISharedImage` now begins an explicit `CATransaction` before creating or
configuring its detached layer, disables animation actions, and commits in
`@finally`. The transaction encloses rasterization as well. The bitmap context
also has balanced cleanup. This permits the existing continuous-corner render
to execute in a caller-owned worker queue without creating the forbidden
implicit transaction.

`PILayerForIcon` and `PIReplacementMiniLayer` use the same transaction discipline
because those constructors can also be reached by background image caches.
Native layers remain untouched; each returned replacement is independently owned.

The fix does not change SpringBoard's assertion setting, synchronously dispatch
to the main queue, add a callback block, or change icon identity mapping. Photo
selection, crop controls, Save/Cancel animation, and all 1.1 coverage hooks remain.

Apple's SDK documents explicit transactions as per-thread, nestable groups.
The correction follows its `begin`/`commit` contract; see also Apple's
[Core Animation transaction guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/AdvancedAnimationTricks/AdvancedAnimationTricks.html).

## Verification

- The actual 1.1 package UUIDs match the crash report and archived dSYMs.
- The new compiler-IR regression audit rejects the 1.1 layer paths and passes
  the corrected paths for both architectures, including exception cleanup.
- Package layout, architecture slices, signing hashes, previous callback fixes,
  and matching symbols are checked for the rebuilt package.
- No menu-step logging is reintroduced. No original photos or device identifiers
  from the crash report are included in this source archive.

These are host checks. The fix has not been run on iOS by the build environment.
Install 1.1.1 over 1.1, respring, and repeat the reported Photos/share-sheet/app-
switching sequence. Saved icon choices are retained. Reopen other affected apps
so they load the updated system provider too.
