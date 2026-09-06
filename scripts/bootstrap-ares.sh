#!/usr/bin/env bash
set -euo pipefail

readonly ARES_VERSION="147"
readonly ARES_SHA256="9d8376b5dde4869bc0613efe3a544471e120b6e4f0b02ebe0c34295b034df147"
readonly ARES_URL="https://github.com/ares-emulator/ares/releases/download/v${ARES_VERSION}/ares-macos-universal.zip"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT
readonly DOWNLOAD_DIR="$PROJECT_ROOT/.build/downloads"
readonly ARCHIVE="$DOWNLOAD_DIR/ares-macos-universal-v${ARES_VERSION}.zip"
readonly INSTALL_DIR="$PROJECT_ROOT/.build/emulators/ares-v${ARES_VERSION}"
readonly ARES_APP="$INSTALL_DIR/ares.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "The pinned ares app bundle is only available on macOS." >&2
    exit 1
fi

if [[ -x "$ARES_APP/Contents/MacOS/ares" ]]; then
    echo "ares v${ARES_VERSION} is already installed at $ARES_APP"
    exit 0
fi

mkdir -p "$DOWNLOAD_DIR" "$PROJECT_ROOT/.build/emulators"

if [[ ! -f "$ARCHIVE" ]]; then
    partial_archive="$ARCHIVE.part"
    curl --fail --location --show-error "$ARES_URL" --output "$partial_archive"
    mv "$partial_archive" "$ARCHIVE"
fi

actual_sha256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$actual_sha256" != "$ARES_SHA256" ]]; then
    echo "ares archive checksum mismatch:" >&2
    echo "  expected: $ARES_SHA256" >&2
    echo "  actual:   $actual_sha256" >&2
    echo "Remove $ARCHIVE and rerun this task." >&2
    exit 1
fi

unpack_dir="$(mktemp -d "$PROJECT_ROOT/.build/ares-v${ARES_VERSION}.unpack.XXXXXX")"
trap 'rm -rf "$unpack_dir"' EXIT

ditto -x -k "$ARCHIVE" "$unpack_dir"
[[ -d "$unpack_dir/ares-v${ARES_VERSION}/ares.app" ]] || {
    echo "The ares archive did not contain the expected app bundle." >&2
    exit 1
}

mkdir -p "$INSTALL_DIR"
mv "$unpack_dir/ares-v${ARES_VERSION}/ares.app" "$ARES_APP"
echo "Installed ares v${ARES_VERSION} at $ARES_APP"
