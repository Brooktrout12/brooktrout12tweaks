#!/usr/bin/env bash
set -euo pipefail
bt_project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# No attenuation, conversion, normalization or processing.
cp -- "$bt_project/assets/lock-original.caf" \
    "$bt_project/layout/Library/Application Support/ClassicLockSound/lock.caf"
python3 "$bt_project/scripts/verify_audio.py"
