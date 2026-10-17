#!/usr/bin/env bash
set -euo pipefail
bt_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bt_test="$(mktemp)"
trap 'rm -f -- "$bt_test"' EXIT
cc -std=c11 -Wall -Wextra -Werror -pthread "$bt_project/tests/test_scope.c" -o "$bt_test"
"$bt_test"
