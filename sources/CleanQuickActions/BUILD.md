# Build Clean Quick Actions 1.0.2

The distributed DEB uses Theos commit
`5280bd038207e14f8bd76f5417aa2fe641c03228`, L1ghtmann Clang 11.1.0,
iPhoneOS 16.5 SDK headers, and an iOS **17.0** deployment minimum. Both arm64
and arm64e are included. The SDK and toolchain are not bundled.

## Current Apple toolchain

With Theos, an iPhoneOS SDK, and a modern arm64e compiler installed:

```sh
export THEOS=/absolute/path/to/theos
make clean
make -j1 package TARGET=iphone:clang:latest:17.0
python3 scripts/verify_package.py packages/com.brooktrout12.cleanquickactions_1.0.2_iphoneos-arm64.deb
```

The included ABI audit is tuned to the converted legacy Linux output. A
different compiler can encode Objective-C metadata differently; do not use
legacy conversion on modern Apple compiler output.

## Legacy Linux toolchain used here

```sh
export THEOS=/absolute/path/to/theos
export BT_ALLEMANDE=/absolute/path/to/allemande
export BT_LDID=/absolute/path/to/ldid
bash scripts/build-linux.sh
```

The build script cleans, compiles, converts the legacy arm64e ABI with
allemande, signs with ldid, packages, and validates. Conversion happens before
signing. The compiler's pre-conversion arm64e linker warnings are expected;
the validator checks the final converted binary and its signature.
Do not additionally set the older `ALLEMANDE` Makefile variable.

Primary toolchain sources:

- https://github.com/theos/theos/tree/5280bd038207e14f8bd76f5417aa2fe641c03228
- https://github.com/L1ghtmann/llvm-project/releases/tag/test-210562a
- https://github.com/theos/sdks/releases/tag/master-146e41f
- https://github.com/p0358/allemande/tree/43b2ca59ad3f6a55735b1f7b5cba8c34b55bd8f9

## Existing host regression checks

```sh
cc -std=c11 -Wall -Wextra -Werror Rules.c tests/test_rules.c -o /tmp/cqa-rules
/tmp/cqa-rules
```

These exercise native visibility restoration and process scope, not UIKit
execution. Device verification remains necessary for the new divider fix.
