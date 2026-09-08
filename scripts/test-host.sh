#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
python3 -m unittest discover -s scripts -p 'test_mesh_format.py'
for content in meadow robot-courtyard; do
    zig test "$@" --dep content -Mroot=src/scene.zig -Mcontent="src/content-$content.zig"
done
