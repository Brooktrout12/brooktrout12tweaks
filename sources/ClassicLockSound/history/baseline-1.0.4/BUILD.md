# Build and implementation notes

## Configuration

- Package/signing identifier: `com.brooktrout12.classiclocksound`
- Author and maintainer: `brooktrout12`
- Version: `1.0.4`
- Deployment target: iOS 18.0; package dependency range: iOS 18.x
- Device slices: arm64 and arm64e; Debian architecture: `iphoneos-arm64`
- Injection filter and constructor guard: `com.apple.springboard` only
- Theos: `5280bd038207e14f8bd76f5417aa2fe641c03228`
- Linux toolchain: L1ghtmann/llvm-project `test-210562a`, clang 11.1.0
- SDK: Theos iPhoneOS16.5.sdk, `master-146e41f`
- arm64e converter: p0358/allemande `43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9`
- Signing: ldid, ad-hoc, after conversion

The original CAF is installed byte-for-byte. Tweak.m uses manual reference
counting and emits no custom Objective-C classes or block literals.

## macOS

With Theos, ldid, and a current Xcode iOS SDK installed:

```sh
export THEOS=/path/to/theos
make clean package TARGET=iphone:clang:latest:18.0
```

The native Xcode arm64e toolchain does not need the Linux conversion wrapper.

## Linux

Install the pinned Linux toolchain and the 16.5 SDK in Theos, and build allemande:

```sh
export THEOS=/path/to/theos
export BT_ALLEMANDE=/path/to/allemande
export BT_LDID="$THEOS/toolchain/linux/iphone/bin/ldid"
./scripts/build-linux.sh
```

The wrapper runs the policy and audio checks, compiles both device slices,
converts the merged image to the newer arm64e ABI, signs it, packages the resource,
and verifies the package. The old-ABI linker warning precedes conversion. There
is no `oldabi` dependency.

Resource lookup is relative to the loaded dylib, supporting the MobileSubstrate
and TweakInject layouts, with Theos's compile-time rootless prefix as fallback.
The code avoids the older Linux libroot archive and extra block metadata.
The source archive does not include the SDK or compiler. Archive SHA-256 values:

```text
a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e  iOSToolchain-x86_64.tar.xz
5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb  iPhoneOS16.5.sdk.tar.xz
```

## Observed playback route

The supplied diagnostic report, recorded on iOS 18.6 build 22G86, contains six
lock invocations followed by six `SBSoundController -_playFeedback:` calls.
Every sound object is SBUISound, with soundType 5, eventType 1002, systemSoundID 0
and resolvedSystemSoundID 0. Neither ID/path initializer hook was reached.
The exact asset was readable, matched SHA-256, and registered successfully with
the audio server (status 0). RUNTIME-EVIDENCE.json contains a sanitized summary;
the source archive excludes the raw device report.

The report also supplied native method encodings and bounded code snapshots.
Disassembly establishes that the controller dispatches type 5 to feedback and
type 0 to `_playSystemSound:`. Its file branch reads songPath, registers the CAF,
tracks the same sound object and installs its completion before playing. Its
completion-registration failure path returns false before starting playback.

## Release implementation

Only `SBSoundController -_playFeedback:` is hooked. The replacement checks the
object class and the exact type/event pair. For a match, it sets songPath to the
bundled CAF and soundType to 0, then invokes `_playSystemSound:` on the same
controller with the same sound object. A successful request retains type 0 so
stop, cleanup and replay use the native system-sound route. On failure, it
restores the prior path and type before forwarding to the original feedback
method. Other requests forward directly with their original receiver, selector
and argument. No sound IDs are cast to Objective-C objects.

The surrounding controller retains its environment check, and the native
lock action is not replaced. The existing behavior, vibration pattern, event
identity and callback ownership remain on the original object. There is no
second `shouldPlayLockSound` query, new audio session or independent player.
Native mute/Lock Sound behavior still requires verification on the phone.

The constructor schedules installation once on the main queue. It checks every
used private method's return and argument types against those observed on the
phone. Missing signatures or an unreadable CAF leave native playback enabled.
There are no private ivar offsets, initializer hooks, shared C function hooks,
import rebinding, diagnostic code reads, repeating timers, or JSON writes.
The only directly linked frameworks are Foundation and SpringBoardUI, plus the
rootless Substrate hook library.

## Verification

```sh
bash scripts/test-policy.sh
python3 scripts/verify_audio.py
python3 scripts/verify_package.py packages/com.brooktrout12.classiclocksound_1.0.4_iphoneos-arm64.deb
```

The policy test replays the six observed type/event pairs and checks that the
new selection reaches them despite sound IDs of zero. It also excludes other
sound types, screenshot/system IDs and unrelated feedback; checks full 64-bit
values against truncation; and searches 524,296 type/event combinations for
unintended matches. AddressSanitizer and UndefinedBehaviorSanitizer are enabled.
Leak detection is disabled because the managed host cannot inspect `/proc`
thread state; this C test performs no heap allocations.

The audio verifier requires exact original bytes/hash and original PCM format,
channel count and frame count, using ffprobe. `scripts/prepare-audio.sh` only
copies the original asset; it performs no encoding or volume adjustment.

The package verifier checks the exact rootless payload and control entries,
SpringBoard filtering, resource identity, both Mach-O targets and UUIDs, load
paths, minimum OS, used native selectors, absence of old hooks/diagnostics,
converted arm64e constant strings, and every signed code page. Matching pre-strip
dSYM UUIDs are checked when preparing the source archive. The compiled hook's
object argument forwarding and native-play/fallback branches are also reviewed.

These checks do not emulate SpringBoard or prove audible playback on the phone.
The report proves the route and resource availability for the diagnostic build;
the release's validation results explicitly mark device_runtime_tested as false.
