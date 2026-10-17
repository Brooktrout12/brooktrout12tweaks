#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos installation}"
: "${BT_ALLEMANDE:?Set BT_ALLEMANDE for the legacy Linux arm64e toolchain}"
: "${BT_LDID:?Set BT_LDID to your ldid binary}"
bs_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$bs_project"
mkdir -p validation
"${HOST_CC:-cc}" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    BSAnimationState.c tests/state_test.c -lm -o validation/state_test
ASAN_OPTIONS=detect_leaks=0 ./validation/state_test | tee validation/state-test.txt
make clean
make -j1 package TARGET_CODESIGN="bash $bs_project/scripts/sign-linux.sh"
python3 scripts/verify_package.py packages/com.brooktrout12.blursleep_1.2.0_iphoneos-arm64.deb \
    > validation/package-verification.json
