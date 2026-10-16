# Classic Lock Sound 1.0.8

By Brooktrout12. Package ID: `com.brooktrout12.classiclocksound`.

This release fixes the unresponsive slider reported on iOS 17 and iOS 18, using the native Settings slider cell. It retains the original, full-level `lock.caf` and **Settings → Classic Lock Sound → Lock sound volume**. The slider covers 0–100%, with selections rounded to whole percentages when saved. 0% produces silence; 100% uses the exact original recording, without amplification or normalization. The default is 100%. Intermediate settings scale PCM amplitude linearly; this is not a measurement of perceived loudness or the phone's speaker output. The phone's ringer level and native lock-sound policy still apply.

The slider uses the native `PSSliderCell`. The value row above it shows the saved percentage and updates when the slider is released. Native control events also handle accessibility adjustments. Only the percentage row is refreshed after a change, so the active slider is never replaced during tracking. Changes apply to subsequent lock requests without a respring. **Reset to 100%** restores full level. Preferences persist across Settings relaunches and resprings. The pane retains the lock-and-sound icon at 29, 58, and 87 pixels.

Install `com.brooktrout12.classiclocksound_1.0.8_iphoneos-arm64.deb` as an update through the existing rootless package manager. It declares iOS 17.0 through 18.x, arm64 and arm64e, Substrate-compatible injection, and PreferenceLoader 2.2.6 or later. Respring once after installation and reopen Settings.

## Slider repair

The user reported that 1.0.7 displayed 100% but would not respond to touch on either iOS 17 or iOS 18. That version embedded a custom UISlider in a `PSStaticTextCell`, a display-only row type. 1.0.8 removes the entire custom slider cell and manual height/layout code. It registers a native `PSSliderCell`, explicitly enabled, with minimum 0, maximum 100, a numeric getter and setter, and the existing `VolumePercent` preference. The reset action still writes 100% and refreshes the pane.

This addresses the erroneous cell setup identified in source review. It has not yet been verified by touching the rebuilt pane on a physical device. Reference for native Preferences specifiers and control keys: https://github.com/theos/headers/blob/master/Preferences/PSSpecifier.h

## Audio and cache behavior

The packaged CAF is the original from 1.0.5, not the quieter WAV-derived asset from 1.0.6. At startup and after a preference change, the tweak validates the bundled CAF and prepares the requested level under `/var/mobile/Library/Caches/ClassicLockSound`. A filename contains the original asset hash, gain algorithm version, and percentage. This distinguishes each level from older releases and avoids changing the bytes behind an already-used filename. At 100% the cached file is byte-identical to the original; at 0% all PCM samples are zero. Metadata and duration are preserved.

Preparation occurs outside the playback hook, on SpringBoard's main queue. There is no polling or extra audio player. If preparation fails, the last successfully prepared level remains active; startup failure leaves native behavior. Up to 101 cached CAF files occupy about 15.5 MiB. Sound files use no data protection so the native player can read them while locked. No Apple system audio files are replaced.

The existing guarded `SBSoundController -_playFeedback:` route remains: only sound type 5 / event 1002 is redirected into the native file playback path. Unrelated sound events remain unchanged. This update does not add global AudioServices hooks or bypass the sound controller's ABI checks.

## Verified and still requiring a device

Both binaries compile for arm64 and arm64e with a deployment minimum of iOS 17.0. Validation covers package layout and firmware dependencies, original audio identity, every gain level and every signed 16-bit sample value, malformed-CAF rejection, native event selection, arm64e metadata conversion, signed-page hashes, and matching debug-symbol UUIDs. The icon and PreferenceLoader entry are present in the DEB. The packaged Settings binary contains the new volume getter/setter callbacks and excludes the old custom slider class and layout code. The audio engine, SpringBoard hook, preference storage/notification helpers, and audio/icon assets are unchanged from 1.0.7.

No physical iPhone was available. The slider UI, preference propagation, and actual playback must still be checked on the user's iPhone SE (2020), iOS 17.6.1, and iPhone 11 Pro, iOS 18. The earlier report that the quieter 1.0.6 sound did not take effect on the SE has no confirmed root cause. Distinct cache filenames address one possible cause; this is not a claim that the earlier SE behavior has been reproduced or resolved.

On each phone, test 100%, 50%, and 0% after releasing the slider, then Reset to 100%. At 0%, the lock should be silent. Reopen Settings and respring to check persistence. Verify native silent-mode behavior, screenshots, and combined use with SidePress. If 0% still plays the old sound, retain the installed package version, iOS/model details, and SpringBoard logs; the private-interface guard or a different playback route may be involved.

See `BUILD-IOS17-18.md`, `ASSET-NOTICE.md`, `UPDATE-1.0.8.patch`, and `validation/`. Previous release reports and assets under `history/` are historical and are not installed.
