#!/usr/bin/env bash
set -euo pipefail
bt_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bt_test_dir="$(mktemp -d)"
trap 'rm -f -- "$bt_test_dir/test-policy"; rmdir -- "$bt_test_dir"' EXIT
cc -std=c11 -Wall -Wextra -Werror -fsanitize=undefined,address \
    "$bt_project/tests/test_policy.c" -o "$bt_test_dir/test-policy"
# LeakSanitizer cannot inspect threads in this managed /proc environment.
# This test makes no heap allocations; retain ASan + UBSan bounds/UB checks.
ASAN_OPTIONS=detect_leaks=0 "$bt_test_dir/test-policy"
