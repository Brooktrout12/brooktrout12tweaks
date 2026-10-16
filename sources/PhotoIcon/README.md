# Photo Icon 1.1.2 — iOS 17 and 18

By Brooktrout12. Update from 1.1.1. Package ID: `com.brooktrout12.photoicon`.

## Compatibility update

Adds the iOS 17 updateImageAnimated: and backing-layer presentation path, legacy leaf/icon renderers, and one-argument folder-cache hooks. Modern image-update hooks remain independently available for iOS 18. Legacy folder refresh tracks weak icon references without model-wide reloads. Per-view identity/reuse isolation, callback ownership, and background layer transactions remain.

The DEB dependency is `firmware (>= 17.0), firmware (<< 19.0)`. Runtime major-version checks accept 17 and 18, and both arm64/arm64e binaries target iOS 17.0. The package name, identifier, and existing preference domains are retained for normal upgrades.

## Install

Open `com.brooktrout12.photoicon_1.1.2_iphoneos-arm64.deb` in the existing rootless package manager and install it as an update. Let the package manager resolve the dependencies listed in `control`; no firmware-force option is required for iOS 17.6.1. Respring after SpringBoard tweaks and reopen Settings for preference changes. The archive contains no automatic installer.

## Device check

Change, adjust, cancel, and restore an app and a Safari bookmark. Check open/closed folders, Clock, Spotlight, switcher, Settings, and share-sheet icons. Switch rapidly between apps, then respring. Repeat on iOS 18; native image arguments must remain intact.

Compatibility review used the iOS **17.0.3** headers at https://github.com/MTACS/iOS-17-Runtime-Headers and the original projects' iOS 18 references. The downloaded iOS 17 header archive SHA-256 is `5d2634d56c32b829f9ec0d816a695a55b225beda4abc525e9be1ef7cb2cf17d2`. This is interface evidence, not execution of iOS 17.6.1. Runtime selector/signature guards remain where the original project supplies them. Unsupported private interfaces may leave a feature inactive rather than force a mismatched hook.

No physical iPhone was connected. **The new release has not been device-tested on iOS 17 or iOS 18.** The priority acceptance device is iPhone SE (2020/A13), iOS 17.6.1, with the user's existing rootless Dopamine setup. All iOS 17.x and 18.x are admitted by the package/runtime range; behavior on every model and point release cannot be certified by static checks. Hardware tests and interactions with other installed tweaks remain outstanding.

## Source and evidence

This archive contains the exact updated project sources, original assets/licenses, fresh matching debug symbols, and retained regression scripts. `IOS17-18.patch` compares the edited implementation/build/test files with the original source ZIP. `BUILD-IOS17-18.md` gives current build commands. `validation/` contains current results and the distributed DEB hash. `source-manifest.json` hashes every other archived file.

Baseline usage, implementation details, earlier diagnoses, and old reports are preserved in `history/baseline-1.1.1/`. Those historical version numbers and results do not describe the new binary.
