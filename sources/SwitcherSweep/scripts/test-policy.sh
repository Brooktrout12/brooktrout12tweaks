#!/usr/bin/env bash
set -euo pipefail
bt_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bt_test_dir="$(mktemp -d)"
trap 'rm -f -- "$bt_test_dir/test-policy" "$bt_test_dir/test-pending"; rmdir -- "$bt_test_dir"' EXIT
cc -std=c11 -Wall -Wextra -Werror -fsanitize=undefined,address \
    "$bt_project/tests/test_policy.c" -lm -o "$bt_test_dir/test-policy"
ASAN_OPTIONS=detect_leaks=0 "$bt_test_dir/test-policy"
cc -std=c11 -Wall -Wextra -Werror -fsanitize=undefined,address \
    "$bt_project/tests/test_pending.c" -lm -o "$bt_test_dir/test-pending"
ASAN_OPTIONS=detect_leaks=0 "$bt_test_dir/test-pending"
