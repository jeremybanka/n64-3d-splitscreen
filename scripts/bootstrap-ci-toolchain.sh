#!/usr/bin/env bash
set -euo pipefail

# Official Linux x86_64 compiler image, inspected 2026-09-06. It contains the
# GCC toolchain only; bootstrap-libdragon.sh still builds our pinned SDK source.
readonly TOOLCHAIN_IMAGE="ghcr.io/dragonminded/libdragon@sha256:c5de552d54d6b80bf8a8f14ed88b2d77d55a08930919d8644649811279e08117"
: "${N64_INST:?N64_INST must be set}"

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    echo 'CI compiler setup requires Linux x86_64; use mise run setup locally.' >&2
    exit 1
fi

docker pull "$TOOLCHAIN_IMAGE"
container="$(docker create "$TOOLCHAIN_IMAGE")"
trap 'docker rm "$container" >/dev/null' EXIT
mkdir -p "$N64_INST"
docker cp "$container:/n64_toolchain/." "$N64_INST/"

# Match the GCC version in the pinned libdragon tools/build-toolchain.sh.
identity="$(dirname "${BASH_SOURCE[0]}")/sdk-identity.py"
python3 "$identity" record-compiler --install "$N64_INST" --origin "$TOOLCHAIN_IMAGE"
