#!/usr/bin/env bash
set -euo pipefail
: "${BT_ALLEMANDE:?Set BT_ALLEMANDE to the compiled allemande executable}"
: "${BT_LDID:?Set BT_LDID to the toolchain ldid executable}"
bs_binary="${!#}"
bs_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p -- "$bs_project/validation"
bs_log="$bs_project/validation/$(basename -- "$bs_binary").abi-conversion.log"
"$BT_ALLEMANDE" "$bs_binary" > "$bs_log" 2>&1
if rg -q 'ERROR|Unexpected' "$bs_log"; then
    cat "$bs_log" >&2
    exit 1
fi
"$BT_LDID" "$@"
