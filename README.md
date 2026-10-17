# Brooktrout12 Tweaks

Open-source iOS jailbreak tweaks, with prebuilt packages and editable source.

**Package-manager URL:** https://brooktrout12.github.io/brooktrout12tweaks/

Add this URL in Sileo or Zebra to install compatible packages and receive updates.

## Included packages

The repository contains 16 rootless packages (`iphoneos-arm64`), selected on 17 October 2026. Each package's dependency fields specify its supported iOS versions. Package availability does not establish device testing; consult the project's release and validation notes.

| Package | Version | Source | Status |
|---|---|---|---|
| com.brooktrout12.3dbadgeclear18 | 1.0.1 | [Source](sources/BadgeClear18) | Release build; see project notes for device validation. |
| com.brooktrout12.batterycapacity18 | 1.0.6 | [Source](sources/BatteryCapacity18) | Release build; see project notes for device validation. |
| com.brooktrout12.blursleep | 1.2.0 | [Source](sources/BlurSleep) | Experimental; see release notes for device validation. |
| com.brooktrout12.ccnorecent | 1.0.0 | [Source](sources/CCNoRecent) | Release build; physical-device verification remains necessary. |
| com.brooktrout12.classiclocksound | 1.0.8 | [Source](sources/ClassicLockSound) | Release build; see project notes for device validation. |
| com.brooktrout12.cleanquickactions | 1.0.2 | [Source](sources/CleanQuickActions) | 1.0.2 iOS 17 section-divider fix; see project validation notes. |
| com.brooktrout12.dawn18 | 1.0.1 | [Source](sources/Dawn18) | Release build; see project notes for device validation. |
| com.brooktrout12.faceidgrace | 1.0.3 | [Source](sources/FaceIDGrace) | 1.0.3 Settings crash fix; device retest remains necessary. |
| com.brooktrout12.instantclear18 | 1.0.1 | [Source](sources/InstantClear18) | Release build; see project notes for device validation. |
| com.brooktrout12.instantpasscode18 | 1.1.1 | [Source](sources/InstantPasscode18) | Release build; see project notes for device validation. |
| com.brooktrout12.photoicon | 1.1.2 | [Source](sources/PhotoIcon) | Release build; see project notes for device validation. |
| com.brooktrout12.rockantenneadblock | 0.2.0 | [Source](sources/RockAntenneAdBlock) | Experimental Test 2; ad-skipping behavior is not guaranteed. |
| com.brooktrout12.sidepress18 | 1.0.1 | [Source](sources/SidePress18) | Release build; see project notes for device validation. |
| com.brooktrout12.switchersweep | 1.0.8 | [Source](sources/SwitcherSweep) | Release build; see project notes for device validation. |
| local.kilian.ytshortsforegroundonly | 1.0.1 | [Source](sources/YouTube_Shorts_Addons) | Experimental — physical-device verification remains necessary. |
| local.kilian.ytshortsnoads | 1.0.0 | [Source](sources/YouTube_Shorts_Addons) | Experimental — physical-device verification remains necessary. |

## Source folders

Every published package links to a browsable project under `sources/`. BlurSleep 1.2.0 and CCNoRecent 1.0.0 have been unpacked from the uploaded ZIPs. The Face ID Grace 1.0.3, Clean Quick Actions 1.0.2 and ROCK ANTENNE AdBlock 0.2.0 sources match the selected DEBs. Build instructions, technical validation records, assets and historical material are retained within each project. Private device-report metadata is omitted from published notes. JB Battery Watch's source remains available, but its previously removed package has not been republished.

## Building tweaks

Most projects include a Theos Makefile and a README or build guide. The YouTube add-ons use `build.sh`; JB Battery Watch's archived source uses the Python scripts documented in `BUILD_NOTES.md`. External compilers and SDKs are not included. Repository publication copies the saved DEBs unchanged; it does not recompile tweaks or constitute a new device test.

## Publishing updates

Push package/source updates to `main`. The GitHub Actions workflow builds and checks the APT indexes, Release checksums, package pages and homepage, then deploys GitHub Pages. DEBs under `debs/` define the package inventory. Add a `catalog.json` entry to attach a source folder and validation status to a new package; packages can still be published without that optional metadata.

To check a change locally:

```sh
python3 scripts/build_repo.py
python3 scripts/verify_repo.py
```

See [SETUP.md](SETUP.md) for initial setup. The phone-setup workflow's ZIP import runs only before `.phone-setup-complete` exists.

## Licensing

Original code uses MIT; existing project licenses and third-party notices remain applicable. See [LICENSING.md](LICENSING.md) and each project's notices. The root license does not relicense third-party audio.

## Provenance

[Input archives](provenance/input-archives.json) records both historical assembly inputs and current update hashes. [The 17 October update](provenance/update-2026-10-17.json) records the five package/source pairs and source integrity checks. Original package IDs, versions, dependencies and DEB bytes are preserved.
