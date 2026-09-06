#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ARES_APP="$PROJECT_ROOT/.build/emulators/ares-v147/ares.app"
readonly ROM="$PROJECT_ROOT/n64-3d-splitscreen.z64"

[[ -x "$ARES_APP/Contents/MacOS/ares" ]] || {
    echo "ares v147 is not installed; run 'mise run emulator-setup'." >&2
    exit 1
}

[[ -f "$ROM" ]] || {
    echo "Missing ROM: $ROM" >&2
    exit 1
}

# ares v148 removed the macOS OpenGL backend. Its Metal presentation flickers
# on this development machine, including with libdragon's stock example ROMs.
open -na "$ARES_APP" --args \
    --setting "Video/Driver=OpenGL 3.2" \
    --setting "General/HomebrewMode=true" \
    "$ROM"
