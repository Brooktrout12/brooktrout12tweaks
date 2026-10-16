# Build Classic Lock Sound 1.0.7

The supplied DEB was built with Theos commit `5280bd038207e14f8bd76f5417aa2fe641c03228`, L1ghtmann clang 11.1.0 (`test-210562a`), iPhoneOS16.5.sdk (`master-146e41f`), and p0358/allemande commit `43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9`. The old arm64e ABI is converted before final ad-hoc signing, using the original project's conversion strategy. Linker warnings in build.log precede that conversion. Existing per-project verifiers inspect the distributed binaries and signed code-page hashes.

The SDK version supplies compile-time declarations; the deployment minimum is **17.0**, not 16.5. Both Classic Lock Sound binaries contain arm64 and arm64e slices; all four slices declare iOS 17.0. The complete eleven-tweak bundle now contains 18 binaries and 36 slices.

Primary build references:
- https://github.com/theos/theos/tree/5280bd038207e14f8bd76f5417aa2fe641c03228
- https://github.com/L1ghtmann/llvm-project/releases/tag/test-210562a
- https://github.com/theos/sdks/releases/tag/master-146e41f
- https://github.com/p0358/allemande/tree/43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9

Archive SHA-256:
```
a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e  iOSToolchain-x86_64.tar.xz
5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb  iPhoneOS16.5.sdk.tar.xz
```
The compiler, SDK, and conversion-tool binaries are not bundled.

## macOS / current Apple arm64e toolchain

Use an installed Theos checkout and iPhoneOS SDK. The source defaults to SDK 16.5; override the SDK component if needed, retaining deployment 17.0. Leave legacy ABI conversion variables unset with a modern Apple compiler.

```sh
export THEOS=/absolute/path/to/theos
make clean
make -j1 package TARGET=iphone:clang:latest:17.0 ADDITIONAL_CODESIGN_FLAGS=-Cadhoc
python3 scripts/verify_package.py packages/com.brooktrout12.classiclocksound_1.0.7_iphoneos-arm64.deb
```

## Pinned Linux toolchain used for this release

Install the pinned toolchain at `$THEOS/toolchain/linux/iphone` and the SDK at `$THEOS/sdks/iPhoneOS16.5.sdk`; initialize Theos submodules. Build allemande with `g++ -std=c++20 -O2 -o allemande main.cpp`. Restore executable bits if the ZIP extraction tool strips them.

```sh
export THEOS=/absolute/path/to/theos
export BT_ALLEMANDE=/absolute/path/to/allemande
export BT_LDID="$THEOS/toolchain/linux/iphone/bin/ldid"
make clean
make -j1 package ADDITIONAL_CODESIGN_FLAGS=-Cadhoc TARGET_CODESIGN="$PWD/scripts/sign-linux.sh"
python3 scripts/verify_package.py packages/com.brooktrout12.classiclocksound_1.0.7_iphoneos-arm64.deb
```

Start from a clean extracted source tree. All installed payload files must be under `/var/jb`; do not reuse staging data from a different build. Avoid adding this legacy toolchain's entire bin directory to PATH: its optional plistutil needs a host library. Theos can resolve the compiler directly.

Current package, policy, code-generation, and debug-symbol results are in `validation/`. The included `debug-symbols/` UUIDs match this distributed DEB. Historical reports are under `history/` and describe older binaries. Rebuilding may change UUIDs and byte hashes. Device execution was not performed.

## Volume validation

Run `python3 scripts/verify_audio.py` to check the restored CAF hash, exact 100% output, silent 0% output, all 101 gain levels, the complete signed 16-bit sample domain, and malformed CAF rejection. The test uses a host C compiler and FFmpeg; it does not emulate iOS. `bash scripts/test-policy.sh` checks lock-event selection. `bash scripts/build-linux.sh` runs those checks, builds both binaries serially, converts legacy arm64e metadata, signs, and verifies the final package.

Preferences use the existing Apple Preferences framework and PreferenceLoader; no Cephei dependency is needed. The rootless payload adds one preference bundle, a loader entry, and three icon sizes. See README.md for device checks and the unresolved prior SE report.
