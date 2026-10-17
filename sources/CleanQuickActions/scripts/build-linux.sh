#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos installation}"
: "${BT_ALLEMANDE:?Set BT_ALLEMANDE for the legacy Linux arm64e toolchain}"
: "${BT_LDID:?Set BT_LDID to your ldid binary}"
cqa_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$cqa_project"
mkdir -p validation
make clean
make -j1 package ADDITIONAL_CODESIGN_FLAGS=-Cadhoc TARGET_CODESIGN="bash $cqa_project/scripts/sign-linux.sh"
python3 scripts/verify_package.py packages/com.brooktrout12.cleanquickactions_1.0.2_iphoneos-arm64.deb \
    > validation/package-verification.json
