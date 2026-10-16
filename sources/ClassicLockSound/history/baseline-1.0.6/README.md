# Classic Lock Sound 1.0.6 — iOS 17 and 18

By Brooktrout12. Package ID: `com.brooktrout12.classiclocksound`. Update from 1.0.5.

This release replaces the lock sound with the user's corrected WAV, converted losslessly to `lock.caf`. The runtime tweak source and native lock-feedback behavior are unchanged. Installation requirements remain iOS 17.0 through 18.x, rootless, with arm64 and arm64e binaries.

Install `com.brooktrout12.classiclocksound_1.0.6_iphoneos-arm64.deb` as an update through the existing rootless package manager, then respring. Version 1.0.6 allows the package manager to recognize the audio correction as an update.

Audio sample equality, policy tests, package layout, iOS minimums, arm64e conversion, code-signature page hashes, and matching debug symbols were verified. Physical iPhone testing was not available. Check the corrected sound with the normal Lock Sound setting enabled, then verify silent mode and combined use with SidePress.

The source includes the original corrected WAV, converted CAF, build scripts, tests, fresh debug symbols, and validation reports. See `ASSET-NOTICE.md` for the exact conversion and hashes and `BUILD-IOS17-18.md` for build commands. `UPDATE-1.0.6.patch` records text changes from 1.0.5; binary audio changes are identified by hashes in `validation/source-provenance.json`. Earlier documentation and assets are retained under `history/` and do not describe the currently installed sound.
