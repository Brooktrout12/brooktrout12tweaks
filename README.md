# Brooktrout12 Tweaks

Open-source iOS jailbreak tweaks, with prebuilt packages and editable source.

**Package-manager URL:** https://brooktrout12.github.io/Brooktrout12Tweaks/

This URL becomes live after GitHub Pages is configured and the first deployment succeeds. Add it in Sileo or Zebra to install compatible packages and receive updates.

## First upload

See [SETUP.md](SETUP.md) for copying the complete folder with GitHub Desktop, enabling Pages and publishing. All repo files are ready; no tweak compilation is needed for the initial upload.

## Included packages

These are the selected saved builds available when assembled on 16 October 2026. All 15 are rootless (`iphoneos-arm64`); the package dependency fields specify supported iOS versions. The existence of a package is not a claim that every feature has been device-tested. Review each project's original release notes and validation notes.

| Package | Version | Source | Status |
|---|---|---|---|
| com.brooktrout12.blursleep | 1.0.2 | [Source](sources/BlurSleep) | Experimental — physical-device verification remains necessary. |
| com.chatgpt.jbbatterywatch | 2.1.1 | [Source](sources/JB_Battery_Watch) | Experimental — physical-device verification remains necessary. |
| local.kilian.ytshortsforegroundonly | 1.0.1 | [Source](sources/YouTube_Shorts_Addons) | Experimental — physical-device verification remains necessary. |
| local.kilian.ytshortsnoads | 1.0.0 | [Source](sources/YouTube_Shorts_Addons) | Experimental — physical-device verification remains necessary. |
| com.brooktrout12.3dbadgeclear18 | 1.0.1 | [Source](sources/BadgeClear18) | Release build; see project notes for device validation. |
| com.brooktrout12.batterycapacity18 | 1.0.6 | [Source](sources/BatteryCapacity18) | Release build; see project notes for device validation. |
| com.brooktrout12.classiclocksound | 1.0.8 | [Source](sources/ClassicLockSound) | Release build; see project notes for device validation. |
| com.brooktrout12.cleanquickactions | 1.0.1 | [Source](sources/CleanQuickActions) | Release build; see project notes for device validation. |
| com.brooktrout12.dawn18 | 1.0.1 | [Source](sources/Dawn18) | Release build; see project notes for device validation. |
| com.brooktrout12.faceidgrace | 1.0.1 | [Source](sources/FaceIDGrace) | Release build; see project notes for device validation. |
| com.brooktrout12.instantclear18 | 1.0.1 | [Source](sources/InstantClear18) | Release build; see project notes for device validation. |
| com.brooktrout12.instantpasscode18 | 1.1.1 | [Source](sources/InstantPasscode18) | Release build; see project notes for device validation. |
| com.brooktrout12.photoicon | 1.1.2 | [Source](sources/PhotoIcon) | Release build; see project notes for device validation. |
| com.brooktrout12.sidepress18 | 1.0.1 | [Source](sources/SidePress18) | Release build; see project notes for device validation. |
| com.brooktrout12.switchersweep | 1.0.8 | [Source](sources/SwitcherSweep) | Release build; see project notes for device validation. |

## Building tweaks

Most projects in sources/ include a Theos Makefile and BUILD-IOS17-18.md or README with toolchain details. BlurSleep includes its own Makefile and release/build notes. The YouTube add-ons use build.sh; JB Battery Watch uses the Python build scripts documented in BUILD_NOTES.md. Required external compilers/SDKs are described in those projects and are not included here.

Tests and original validation logs belong to the original source archives; repository assembly does not represent a fresh runtime test of those tweaks. The repository validation separately confirms index fields, compressed indexes, package hashes and unchanged DEB bytes.

## Publishing updates

Push package/source updates to main. The GitHub Actions workflow generates Packages, its gzip/bzip2/xz versions, Release checksums, individual package pages and a homepage, then deploys to GitHub Pages. No write token or auto-commit bot is required. A new package ID needs a source/status entry in catalog.json.

## Licensing

Original code uses MIT; existing project/third-party licenses and media notices remain applicable. See [LICENSING.md](LICENSING.md) and each project's notices. The root license does not relicense third-party audio.

## Provenance

provenance/input-archives.json records the input archive hashes. Original package IDs, versions, dependencies and DEB contents are preserved. The package set is drawn from the combined iOS 17/18 bundle plus BlurSleep 1.0.2, JB Battery Watch 2.1.1 and the YouTube Shorts add-on archive.
