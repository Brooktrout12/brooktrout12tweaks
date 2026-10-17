#!/usr/bin/env bash
set -euo pipefail
: "${BT_ALLEMANDE:?Set BT_ALLEMANDE to the compiled allemande executable}"
: "${BT_LDID:?Set BT_LDID to the toolchain ldid executable}"
ccn_binary="${!#}"
ccn_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p -- "$ccn_project/validation"
ccn_log="$ccn_project/validation/$(basename -- "$ccn_binary").abi-conversion.log"
"$BT_ALLEMANDE" "$ccn_binary" > "$ccn_log" 2>&1
if rg -q 'ERROR|Unexpected' "$ccn_log"; then
    cat "$ccn_log" >&2
    exit 1
fi
"$BT_LDID" "$@"
