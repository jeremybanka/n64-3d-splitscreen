#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DOCS_DIR="$PROJECT_ROOT/docs"
readonly TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/n64-2048-docs.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$DOCS_DIR/zig" "$DOCS_DIR/libdragon" "$DOCS_DIR/summercart64" "$DOCS_DIR/m64"

curl --fail --location --silent --show-error \
    "https://ziglang.org/documentation/0.16.0/" \
    --output "$DOCS_DIR/zig/language-reference-0.16.0.html"

git clone --depth 1 --branch trunk \
    https://github.com/DragonMinded/libdragon.git "$TEMP_DIR/libdragon"
git clone --depth 1 \
    https://github.com/DragonMinded/libdragon.wiki.git "$TEMP_DIR/libdragon-wiki"
git clone --depth 1 \
    https://github.com/Polprzewodnikowy/SummerCart64.git "$TEMP_DIR/summercart64"

rm -rf "$DOCS_DIR/libdragon/wiki" "$DOCS_DIR/libdragon/headers"
cp -R "$TEMP_DIR/libdragon-wiki" "$DOCS_DIR/libdragon/wiki"
rm -rf "$DOCS_DIR/libdragon/wiki/.git"
cp -R "$TEMP_DIR/libdragon/include" "$DOCS_DIR/libdragon/headers"
cp "$TEMP_DIR/libdragon/README.md" "$DOCS_DIR/libdragon/README.upstream.md"
cp "$TEMP_DIR/libdragon/LICENSE.md" "$DOCS_DIR/libdragon/LICENSE.md"
git -C "$TEMP_DIR/libdragon" rev-parse HEAD > "$DOCS_DIR/libdragon/REVISION"

rm -rf "$DOCS_DIR/summercart64/protocol"
cp -R "$TEMP_DIR/summercart64/docs" "$DOCS_DIR/summercart64/protocol"
cp "$TEMP_DIR/summercart64/README.md" "$DOCS_DIR/summercart64/README.upstream.md"
cp "$TEMP_DIR/summercart64/LICENSE" "$DOCS_DIR/summercart64/LICENSE" 2>/dev/null || true
git -C "$TEMP_DIR/summercart64" rev-parse HEAD > "$DOCS_DIR/summercart64/REVISION"

# The M64 support center is a dynamic page, but its server response remains a
# useful local snapshot alongside our concise Markdown hardware guide.
curl --fail --location --silent --show-error \
    "https://support.modretro.com/en_us/m64-manual-r1tovFQgMg" \
    --output "$DOCS_DIR/m64/manual.snapshot.html"

echo "Documentation snapshots refreshed in $DOCS_DIR"
