#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT
readonly SOURCE_DIR="$PROJECT_ROOT/.build/tiny3d"
# Last revision before Tiny3D adopted preview-only libdragon vector types.
# Compatible with this template's pinned libdragon SDK; no GLTF tools needed.
readonly REVISION="ec557373e986b5e041cc102a7ff787eb07921937"
export N64_INST="${N64_INST:-$PROJECT_ROOT/.build/libdragon}"
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    git clone --no-checkout --filter=blob:none https://github.com/HailToDodongo/tiny3d.git "$SOURCE_DIR"
    git -C "$SOURCE_DIR" sparse-checkout set src
fi
if [[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" != "$REVISION" ]]; then
    git -C "$SOURCE_DIR" fetch --depth 1 origin "$REVISION"
    git -C "$SOURCE_DIR" -c filter.lfs.required=false -c filter.lfs.smudge= -c filter.lfs.process= checkout --detach "$REVISION"
fi
make -C "$SOURCE_DIR" -j"${JOBS:-4}"
