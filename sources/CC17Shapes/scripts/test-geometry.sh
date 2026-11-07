#!/usr/bin/env bash
set -euo pipefail
bt_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bt_test_binary="$(mktemp "${TMPDIR:-/tmp}/cc17shapes-geometry.XXXXXX")"
trap 'rm -f -- "$bt_test_binary"' EXIT
"${BT_HOST_CC:-cc}" -std=c11 -Wall -Wextra -Werror \
    "$bt_project/tests/test_geometry.c" -lm -o "$bt_test_binary"
"$bt_test_binary"
