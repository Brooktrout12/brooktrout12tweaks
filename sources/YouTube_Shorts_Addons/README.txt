YouTube Shorts Add-ons - Test 2
Foreground Only 1.0.1; No Ads 1.0.0 (unchanged)
Prepared for Kilian's iPhone 11 Pro, iOS 18.6,
YouTube 21.40.5 and YouTubePatcher 0.6.

These are compiled, installable ROOTLESS jailbreak packages. Compatibility
with the exact YouTube build still needs an on-device test. The build machine
does not run iOS or YouTube, so successful compilation is not a device test.

PACKAGES

YTShortsForegroundOnly_1.0.1_rootless.deb
Pauses visible Shorts when YouTube loses focus, including lock, Home, app
switching and Control Center. Targets only playback objects obtained from
Shorts controllers. Leaves ordinary YouTube video background playback alone.
On returning to YouTube, normal app behavior controls playback; the add-on
does not force a paused video to restart.

Test 1 loaded on the device but did not stop Shorts. Its log contained nine
installed hooks and no recorded pause. That log did not distinguish a missed
lifecycle event from an empty player selection.

Test 2 records Shorts owners/players during appearance and playback, retains
them across system view detachment, and listens to both app and scene lifecycle
events. It also hooks matching native YouTube background callbacks when present.
Logs now include foreground/background events even when no player was found,
plus a limited list of runtime playback method names/signatures.

YTShortsNoAds_1.0.0_rootless.deb
Filters known Shorts video ad models (videoType 3) and the newer non-video
ad cards identified in YouTube-X. Removes these in the Shorts feed model
factories and queued reel collections. Unknown models are preserved.
This does not remove sponsorships recorded by creators inside their videos.
New server-side formats or renamed internals can require another update.

Both packages are independent, can be installed together, and are designed
to stay alongside YouTubePatcher. Neither replaces YouTubePatcher or injects
into YouTube Music, SpringBoard or Settings. No settings pane is needed.
These builds target the regular rootless /var/jb layout, not rootful/roothide.

INSTALLATION

1. Keep YouTubePatcher installed.
2. Fully close YouTube from the app switcher.
3. Download the desired .deb files. Open each in Filza, tap Install and
   complete the package installation. A package manager can also install them.
   Foreground Only 1.0.1 upgrades 1.0.0 in place; do not reinstall No Ads if it
   is already installed. The No Ads installer is byte-identical to Test 1.
4. Complete any respring requested by the installer, then reopen YouTube.

DEVICE CHECKS

- Shorts: play a Short, lock the screen; its audio should stop.
- Shorts: swipe Home, switch to another app, or open Control Center;
  its audio should stop.
- Return quickly, open an ordinary video; a pending Shorts pause should
  not interrupt the ordinary video.
- Ordinary video: background audio should still work through YouTubePatcher.
- YouTube Music: background audio should still work as before.
- Scroll Shorts long enough to cover where sponsored cards normally appear.
  Check that scrolling and playback continue without blank/stuck entries.

DIAGNOSTICS AND REMOVAL

Small local logs are written inside YouTube's data container:
Documents/YTShortsAddons/ForegroundOnly.log
Documents/YTShortsAddons/NoAds.log

Use Filza's Apps Manager -> YouTube -> Data to find that Documents folder.
Logs record app version, runtime class/method names, events and pause/ad counters, not watched
video IDs, titles, URLs or account details. Each log is capped at 64 KiB.
If a package does not work, send its log plus what happened. If YouTube
crashes, also send the YouTube crash report. No diagnostic data is uploaded.

Uninstall "YT Shorts Foreground Only" or "YT Shorts No Ads" through your
package manager, then fully close and reopen YouTube. This removes that
add-on while keeping YouTubePatcher installed. Logs can be deleted separately.

SOURCE AND BUILD

Source is included with the build script, audit and licenses.
Set THEOS, IOS_SDK_PATH and (if needed) IOS_TOOLCHAIN_BIN, then run:
  bash build.sh ForegroundOnly

This rebuilds only Foreground Only and audits it together with the original
No Ads package. The audit requires the original, unchanged No Ads installer.

Build environment used: Linux; L1ghtmann clang 11.1.0 iOS toolchain;
iPhoneOS 16.5 SDK; deployment target iOS 15.0; arm64; ad-hoc signature.
The iPhoneOS SDK and toolchain are not bundled.

Hook references:
https://github.com/PoomSmart/YouTube-X
commit 48b901532f9e12152684f3326d4250efcdea61e5 (2026-09-20)
https://github.com/PoomSmart/YouTubeHeader
commit 4fec33f2ccbabe91c5a96e433f2dc2f674c0aef1 (2026-10-11)
https://github.com/dayanch96/YTLite/blob/main/YTLite.h
(YTPlayerViewController pause/play interface; inspected 2026-10-15)
https://cydia.ichitaso.com/depiction/youtubepatcher.html
https://developer.apple.com/documentation/uikit/uiscene/willdeactivatenotification

The Shorts ad identification is adapted from PoomSmart's MIT-licensed code.
See Licenses/YouTube-X-MIT.txt and Licenses/YouTubeHeader-MIT.txt.
No YouTube executable, proprietary app assets or YouTubePatcher binary is
included or modified.
