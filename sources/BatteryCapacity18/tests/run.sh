#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$(mktemp)
trap 'rm -f "$test_binary"' EXIT HUP INT TERM
cc -std=c11 -O2 -Wall -Wextra -Werror "$project_dir/CapacityRules.c" \
    "$project_dir/tests/capacity_rules_test.c" -lm -o "$test_binary"
"$test_binary"
cc -std=c11 -O2 -Wall -Wextra -Werror "$project_dir/AmperageRules.c" \
    "$project_dir/tests/amperage_rules_test.c" -lm -o "$test_binary"
"$test_binary"
cc -std=c11 -O2 -Wall -Wextra -Werror "$project_dir/WarningRules.c" \
    "$project_dir/tests/warning_rules_test.c" -o "$test_binary"
"$test_binary"
