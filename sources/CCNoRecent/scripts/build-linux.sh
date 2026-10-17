#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos installation}"
: "${BT_ALLEMANDE:?Set BT_ALLEMANDE for the legacy Linux arm64e toolchain}"
: "${BT_LDID:?Set BT_LDID to your ldid binary}"
ccn_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$ccn_project"
mkdir -p validation
make clean
make -j1 package TARGET_CODESIGN="bash $ccn_project/scripts/sign-linux.sh"
python3 scripts/verify_package.py packages/com.brooktrout12.ccnorecent_1.0.0_iphoneos-arm64.deb \
    > validation/package-verification.json
