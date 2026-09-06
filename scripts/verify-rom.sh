#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROM="$PROJECT_ROOT/n64-2048.z64"
readonly ELF="$PROJECT_ROOT/build/n64-2048.elf"
readonly TOOL_PREFIX="${N64_INST:?N64_INST must be set}/bin/mips64-elf-"

[[ -f "$ROM" ]] || { echo "Missing ROM: $ROM" >&2; exit 1; }
[[ -f "$ELF" ]] || { echo "Missing ELF: $ELF" >&2; exit 1; }

magic="$(od -An -tx1 -N4 "$ROM" | tr -d '[:space:]')"
[[ "$magic" == "80371240" ]] || {
    echo "Unexpected N64 ROM byte order/magic: $magic" >&2
    exit 1
}

elf_header="$("${TOOL_PREFIX}readelf" -h "$ELF")"
[[ "$elf_header" == *"o64"* ]] || {
    echo "Linked ELF is not marked with the libdragon O64 ABI" >&2
    exit 1
}

echo "ROM header: big-endian N64 (80 37 12 40)"
"${TOOL_PREFIX}size" "$ELF"
shasum -a 256 "$ROM"
