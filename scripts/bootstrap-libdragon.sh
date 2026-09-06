#!/usr/bin/env bash
set -euo pipefail

readonly LIBDRAGON_REPOSITORY="https://github.com/DragonMinded/libdragon.git"
readonly LIBDRAGON_REVISION="494f1f586d3d6d5fc65b516a8ce29ccf42f85e15"
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SOURCE_DIR="$PROJECT_ROOT/.build/libdragon-src"
readonly INSTALL_DIR="${N64_INST:-$PROJECT_ROOT/.build/libdragon}"

if [[ -x "$INSTALL_DIR/bin/mips64-elf-gcc" && -f "$INSTALL_DIR/include/n64.mk" ]]; then
    echo "libdragon is already installed at $INSTALL_DIR"
    exit 0
fi

mkdir -p "$PROJECT_ROOT/.build"
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    git clone "$LIBDRAGON_REPOSITORY" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch origin "$LIBDRAGON_REVISION"
git -C "$SOURCE_DIR" checkout --detach "$LIBDRAGON_REVISION"

export N64_INST="$INSTALL_DIR"
export BUILD_PATH="$PROJECT_ROOT/.build/libdragon-toolchain-build"
export DOWNLOAD_PATH="$PROJECT_ROOT/.build/downloads"
export JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN || echo 1)}"

if [[ ! -x "$INSTALL_DIR/bin/mips64-elf-gcc" ]]; then
    "$SOURCE_DIR/tools/build-toolchain.sh"
fi

(cd "$SOURCE_DIR" && ./build.sh)
