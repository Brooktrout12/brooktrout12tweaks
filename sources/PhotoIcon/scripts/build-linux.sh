#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?Set THEOS to an installed Theos directory}"
: "${PI_ALLEMANDE:?Set PI_ALLEMANDE to the compiled allemande executable}"
: "${PI_LDID:?Set PI_LDID to the toolchain ldid executable}"
pi_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for pi_tool in "$PI_ALLEMANDE" "$PI_LDID"; do
    if [[ ! -x "$pi_tool" ]]; then
        printf 'Missing executable: %s\n' "$pi_tool" >&2
        exit 1
    fi
done
cd -- "$pi_project"
python3 tests/check_callback_codegen.py --clang "$THEOS/toolchain/linux/iphone/bin/clang" --sdk "$THEOS/sdks/iPhoneOS16.5.sdk"
python3 tests/check_system_blocks.py --clang "$THEOS/toolchain/linux/iphone/bin/clang" --sdk "$THEOS/sdks/iPhoneOS16.5.sdk" --theos "$THEOS"
python3 tests/check_layer_transactions.py --clang "$THEOS/toolchain/linux/iphone/bin/clang" --sdk "$THEOS/sdks/iPhoneOS16.5.sdk" --theos "$THEOS"
python3 tests/check_icon_isolation.py --clang "$THEOS/toolchain/linux/iphone/bin/clang" --sdk "$THEOS/sdks/iPhoneOS16.5.sdk" --theos "$THEOS"
make clean
make -j2 package TARGET_CODESIGN="$pi_project/scripts/sign-linux.sh"
python3 scripts/verify_package.py packages/com.brooktrout12.photoicon_1.1.2_iphoneos-arm64.deb
python3 tests/check_linked_callbacks.py --package packages/com.brooktrout12.photoicon_1.1.2_iphoneos-arm64.deb --symbols .theos/obj --toolchain "$THEOS/toolchain/linux/iphone/bin"
