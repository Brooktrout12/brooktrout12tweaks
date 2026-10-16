#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?Set THEOS to an installed Theos directory}"
: "${BT_ALLEMANDE:?Set BT_ALLEMANDE to the compiled allemande executable}"
: "${BT_LDID:?Set BT_LDID to the toolchain ldid executable}"
bt_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$bt_project"
bash ./scripts/test-policy.sh
python3 scripts/verify_audio.py
make clean
make -j1 package TARGET_CODESIGN="$bt_project/scripts/sign-linux.sh"
python3 scripts/verify_package.py packages/com.brooktrout12.classiclocksound_1.0.8_iphoneos-arm64.deb
