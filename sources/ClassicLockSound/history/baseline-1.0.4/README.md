# ClassicLockSound 1.0.4

Developer: **brooktrout12**

Restores the classic iOS 7–9 lock sound without modifying Apple's system audio
files. No settings to configure. The audio is the original, unmodified file;
this version applies no volume adjustment.

## Install

Install `com.brooktrout12.classiclocksound_1.0.4_iphoneos-arm64.deb` over the
previous ClassicLockSound package, including the diagnostic version, and
respring. The package identifier is unchanged, so it replaces that version.

For the playback check, enable the normal iOS Lock Sound setting and turn silent
mode off. Lock the phone several times and take screenshots. The fix was built
using the actual iOS 18.6 diagnostic report, but this release still needs a
playback check on the phone; a host build cannot exercise SpringBoard.

## What changed

The phone report identified the missed route: all six recorded lock requests
used feedback event 1002, with both system-sound IDs zero. The previous versions
watched ID 1100 or a file initializer, which these requests never reached.

Version 1.0.4 redirects the observed lock feedback request into SpringBoard's
native file player, using the same sound object. SpringBoard manages playback,
completion and cleanup. Unrelated feedback requests pass through unchanged.
The shared AudioServices hooks from 1.0 are absent, as is diagnostic collection.

## Audio and removal

The resource lives at
`/var/jb/Library/Application Support/ClassicLockSound/lock.caf`.
Apple's `/System/Library/Audio/UISounds/lock.caf` remains untouched. Uninstall
and respring to restore stock behavior. The previous diagnostic JSON, if still
present in `/var/mobile/Library/Logs`, is no longer updated and may be deleted.

The packaged CAF matches the reattached original byte-for-byte:

`90d02d979ff94defa18b05ca91ba8633a7eb73f28574b015af09d542d8331543`

It is 160,284 bytes: 44.1 kHz, stereo, signed 16-bit PCM, 39,047 sample frames
(approximately 0.885 seconds). No normalization, attenuation or conversion.

## Source and validation

The archive includes the code, exact asset, build/verification scripts, validation
results and matching debug symbols. See BUILD.md for rebuilding and CRASH-FIX.md
for the evidence behind this change. ASSET-NOTICE.md describes the audio's
separate ownership.
