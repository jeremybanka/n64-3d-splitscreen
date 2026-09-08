#!/usr/bin/env bash
set -euo pipefail

readonly LIBDRAGON_REPOSITORY="https://github.com/DragonMinded/libdragon.git"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT
readonly IDENTITY="$PROJECT_ROOT/scripts/sdk-identity.py"
LIBDRAGON_REVISION="$(python3 "$IDENTITY" revision)"
readonly LIBDRAGON_REVISION
readonly SOURCE_DIR="$PROJECT_ROOT/.build/libdragon-src"
readonly INSTALL_DIR="${N64_INST:-$PROJECT_ROOT/.build/libdragon}"
readonly RECEIPT="$PROJECT_ROOT/.build/libdragon-identity.json"

if [[ "${1:-}" == --verify-source && $# == 2 ]]; then
    python3 "$IDENTITY" verify-source --install "$INSTALL_DIR" --source "$2" --receipt "$RECEIPT"
    exit 0
elif [[ $# != 0 ]]; then
    echo "Usage: $0 [--verify-source /path/to/clean/pinned/libdragon-source]" >&2
    exit 1
fi

if [[ -e "$INSTALL_DIR/include/n64.mk" || -e "$INSTALL_DIR/mips64-elf/lib/libdragon.a" ||
      -e "$INSTALL_DIR/mips64-elf/include/libdragon.h" || -e "$INSTALL_DIR/.n64-template-sdk.json" ]]; then
    if python3 "$IDENTITY" verify --install "$INSTALL_DIR" --receipt "$RECEIPT"; then
        exit 0
    fi
    cat >&2 <<EOF
Refusing to overwrite or silently reuse the SDK at $INSTALL_DIR.
For an unmarked existing SDK, verify it without modifying it:
  N64_INST="$INSTALL_DIR" $0 --verify-source /path/to/clean/pinned/libdragon-source
This rebuilds runtime archives in temporary project storage and compares them.
If the SDK is incompatible, choose a new empty N64_INST directory and rerun setup.
Keep the old installation until its other projects have migrated.
EOF
    exit 1
fi

if [[ -x "$INSTALL_DIR/bin/mips64-elf-gcc" ]]; then
    # Supports CI's pinned image and a separately installed compatible compiler.
    python3 "$IDENTITY" compiler --install "$INSTALL_DIR"
fi

mkdir -p "$PROJECT_ROOT/.build"
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    git clone "$LIBDRAGON_REPOSITORY" "$SOURCE_DIR"
fi
if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain --untracked-files=no)" ]]; then
    echo "SDK source has tracked changes: $SOURCE_DIR; preserve them before setup." >&2
    exit 1
fi
git -C "$SOURCE_DIR" fetch origin "$LIBDRAGON_REVISION"
git -C "$SOURCE_DIR" checkout --detach "$LIBDRAGON_REVISION"

export N64_INST="$INSTALL_DIR"
export BUILD_PATH="$PROJECT_ROOT/.build/libdragon-toolchain-build"
export DOWNLOAD_PATH="$PROJECT_ROOT/.build/downloads"
export JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN || echo 1)}"

if [[ ! -x "$INSTALL_DIR/bin/mips64-elf-gcc" ]]; then
    "$SOURCE_DIR/tools/build-toolchain.sh"
    python3 "$IDENTITY" record-compiler --install "$INSTALL_DIR" --origin "Built from libdragon $LIBDRAGON_REVISION tools/build-toolchain.sh"
fi
python3 "$IDENTITY" compiler --install "$INSTALL_DIR"
(cd "$SOURCE_DIR" && ./build.sh)
python3 "$IDENTITY" record --install "$INSTALL_DIR" --source "$SOURCE_DIR"
