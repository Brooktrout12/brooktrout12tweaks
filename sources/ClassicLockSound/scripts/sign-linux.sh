#!/usr/bin/env bash
set -euo pipefail
: "${BT_ALLEMANDE:?Set BT_ALLEMANDE to the compiled allemande executable}"
: "${BT_LDID:?Set BT_LDID to the toolchain ldid executable}"
bt_binary="${!#}"
bt_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p -- "$bt_project/validation"
bt_log="$bt_project/validation/$(basename -- "$bt_binary").abi-conversion.log"
"$BT_ALLEMANDE" "$bt_binary" > "$bt_log" 2>&1
if rg -q 'ERROR|Unexpected' "$bt_log"; then
    cat "$bt_log" >&2
    exit 1
fi
"$BT_LDID" "$@"
