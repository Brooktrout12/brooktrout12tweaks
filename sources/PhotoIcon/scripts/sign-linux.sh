#!/usr/bin/env bash
set -euo pipefail
: "${PI_ALLEMANDE:?Set PI_ALLEMANDE to the compiled allemande executable}"
: "${PI_LDID:?Set PI_LDID to the iOS toolchain ldid executable}"
pi_binary="${!#}"
pi_log="${pi_binary}.abi-conversion.log"
"$PI_ALLEMANDE" "$pi_binary" > "$pi_log" 2>&1
if grep -Eq 'ERROR|Unexpected' "$pi_log"; then
    cat "$pi_log" >&2
    exit 1
fi
"$PI_LDID" "$@"
