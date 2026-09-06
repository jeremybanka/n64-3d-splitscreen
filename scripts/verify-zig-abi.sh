#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${N64_INST:-$root/.build/libdragon}/bin/mips64-elf-"
object="${1:-$root/build/scene.o}"
undefined="$("${prefix}nm" -u "$object")"
if [[ -n "$undefined" ]]; then
    echo "Zig object has implicit external calls that bypass the audited ABI bridge:" >&2
    echo "$undefined" >&2
    exit 1
fi
# The private Zig module intentionally needs no GP-relative data access.
# Any GP use here signals a compiler configuration/regression to inspect.
disassembly="$("${prefix}objdump" -d "$object")"
if grep -Eq '[[:space:],]gp([[:space:],)]|$)' <<< "$disassembly"; then
    echo 'Zig object uses $gp; compile with mips3+noabicalls and -fno-PIC.' >&2
    exit 1
fi
echo 'Zig ABI: no implicit external calls; global-pointer register reserved'
