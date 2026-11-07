#!/usr/bin/env bash
set -euo pipefail
bt_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bt_test_binary="$(mktemp "${TMPDIR:-/tmp}/ccfavorites-class-test.XXXXXX")"
trap 'rm -f -- "$bt_test_binary"' EXIT
"${BT_HOST_CC:-cc}" -std=c11 -Wall -Wextra -Werror -I"$bt_project/tests/support" \
    "$bt_project/tests/test_class_matching.c" -o "$bt_test_binary"
"$bt_test_binary"
