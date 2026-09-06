#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Start clean so cached project objects cannot hide compiler/ABI regressions.
make clean
mkdir -p build/roms

build_variant() {
    local name="$1"
    shift
    # Variants may finish within one filesystem timestamp tick. Force the
    # adapter, link, and ROM packaging even on those filesystems.
    rm -f build/main.o build/n64-3d-splitscreen.elf n64-3d-splitscreen.z64
    make -j"${JOBS:-4}" INITIAL_VIEWS=4 AUTOTOUR=0 PROFILE=0 VALIDATE=0 BENCHMARK=0 "$@"
    ./scripts/verify-rom.sh
    cp n64-3d-splitscreen.z64 "build/roms/$name.z64"
}

for views in 1 2 3 4; do
    build_variant "bunny-meadow-$views-players" INITIAL_VIEWS="$views"
done
build_variant bunny-meadow-validation VALIDATE=1 PROFILE=1 AUTOTOUR=1
build_variant bunny-meadow-benchmark BENCHMARK=1

# Leave the usual playable four-player ROM as the default output.
rm -f build/main.o build/n64-3d-splitscreen.elf n64-3d-splitscreen.z64
make -j"${JOBS:-4}" INITIAL_VIEWS=4 AUTOTOUR=0 PROFILE=0 VALIDATE=0 BENCHMARK=0
./scripts/verify-rom.sh
(cd build/roms && shasum -a 256 ./*.z64 > SHA256SUMS)

# Catch stale configuration artifacts, including sub-second Make timestamp
# regressions. Each of these six configurations changes the ROM contents.
if [[ "$(cut -d ' ' -f 1 build/roms/SHA256SUMS | sort -u | wc -l)" -ne 6 ]]; then
    echo 'ROM variants unexpectedly have identical contents' >&2
    exit 1
fi
cmp n64-3d-splitscreen.z64 build/roms/bunny-meadow-4-players.z64
