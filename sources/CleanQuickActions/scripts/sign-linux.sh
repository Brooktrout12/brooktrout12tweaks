#!/usr/bin/env bash
set -euo pipefail
: "${BT_ALLEMANDE:?Set BT_ALLEMANDE to the compiled allemande executable}"
: "${BT_LDID:?Set BT_LDID to the toolchain ldid executable}"
cqa_binary="${!#}"
cqa_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p -- "$cqa_project/validation"
cqa_log="$cqa_project/validation/$(basename -- "$cqa_binary").abi-conversion.log"
"$BT_ALLEMANDE" "$cqa_binary" > "$cqa_log" 2>&1
if rg -q 'ERROR|Unexpected' "$cqa_log"; then
    cat "$cqa_log" >&2
    exit 1
fi
"$BT_LDID" "$@"
