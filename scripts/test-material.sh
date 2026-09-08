#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/n64-material-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
for textured in 0 1; do
    "${HOST_CC:-cc}" -std=c11 -Wall -Wextra -Werror -DTEXTURED="$textured" \
        -Itests/material-fakes -Isrc src/material.c tests/material-state.c \
        -o "$test_dir/material-test"
    "$test_dir/material-test"
done
echo 'Material state: flat/textured bindings, depth, and HUD-to-view reloads pass'
