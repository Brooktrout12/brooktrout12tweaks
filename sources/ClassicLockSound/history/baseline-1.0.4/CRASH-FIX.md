# Screenshot crash and stock-sound regression

## 1.0 / 1.0.1: screenshot crash

The supplied SpringBoard crash report records EXC_BAD_ACCESS at address 0x454
(decimal 1108) during screenshot capture. The main thread reaches objc_msgSend
with x0 holding that value. The register state identifies
AudioServicesPlaySystemSound in x2, and the stack includes SSScreenCapturer.
This is consistent with a system-sound ID reaching an Objective-C receiver
position on the screenshot sound path.

The loaded ClassicLockSound arm64e UUID,
6a910c3c-abdb-38d5-bc25-58dfda2abcc8, matches the 1.0/1.0.1 binary. Those versions
installed six shared AudioServices C hooks. Version 1.0.1 changed audio and
metadata only; its playback binary was identical to 1.0. The user confirmed that
uninstalling the tweak stopped screenshot crashes.

The later native-code snapshots also show that several hooked exports are very
short, neighboring branch stubs: PlaySystemSound is 12 bytes, immediately after
PlayAlertSound. This makes the old cluster of inline hooks a poor boundary for
a lock-only replacement. The exact failing trampoline is not established from
the available crash data. All such hooks remain removed in 1.0.4.

## 1.0.2 and 1.0.3: stock audio

Version 1.0.2 replaced `_playLockSound` but added a separate
`shouldPlayLockSound` gate. An unknown or false result forwarded to stock
playback. The user heard the stock sound. That gate is no longer present.

Version 1.0.3 instead redirected SBUISound's ID/path initializers for ID 1100 or
Apple's exact lock.caf path. Screenshots worked, but playback remained stock.
The user then requested the original asset with no volume change.

## Device evidence from 1.0.4 diagnostic 1

The attached report proves all of the following on iOS 18.6 build 22G86:

- The tweak loaded and all diagnostic hooks installed successfully.
- The CAF is readable, 160,284 bytes, and exactly matches the original hash.
- AudioServices successfully registered it as a sound (status 0), then the
  diagnostic disposed that test registration without playing it.
- Six lock invocations were followed by six `_playFeedback:` requests.
- Each request has soundType 5, eventType 1002 and both sound IDs zero.
- No calls reached either ID/path initializer hook.

The previous selection was therefore looking in the wrong namespace and on an
unreached route. Neither a different filename nor quieter audio could fix that.
RUNTIME-EVIDENCE.json records the relevant facts without private device paths.

## 1.0.4: redirect the observed event

This release hooks only the observed `_playFeedback:` method. It identifies the
lock event by the full-width type/event pair, then directs the same sound object
into the controller's existing `_playSystemSound:` file branch. The native code
snapshots establish the type dispatch, file registration and completion handling.
The sound's original behavior, vibration, event identity and ownership remain
intact; the file path and playback type are the only changed properties.

The original feedback method runs only for other events or if native file
playback reports failure before starting. On that failure path, the old type and
path are restored. On success, native stop and completion cleanup see the file
sound type. Shared C audio exports and screenshot methods are untouched.

Diagnostic hooks and code snapshots are removed from the shipped binary. The
original CAF is installed without gain changes. Architecture, signature, audio
identity and selection checks pass on the build host. This release must still be
confirmed on the phone for audible classic playback, repeated screenshots and
normal Lock Sound/silent-mode behavior.
