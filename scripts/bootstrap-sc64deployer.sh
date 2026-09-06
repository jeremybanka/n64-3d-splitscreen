#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY="https://github.com/Polprzewodnikowy/SummerCart64.git"
readonly REVISION="a1e7996d2cbece686820a5c785029c68514f17b0"
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SOURCE_DIR="$PROJECT_ROOT/.build/summercart64-src"
readonly OUTPUT_DIR="$PROJECT_ROOT/.build/bin"

if [[ -x "$OUTPUT_DIR/sc64deployer" ]]; then
    echo "sc64deployer is already installed at $OUTPUT_DIR/sc64deployer"
    exit 0
fi

mkdir -p "$PROJECT_ROOT/.build" "$OUTPUT_DIR"
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    git clone "$REPOSITORY" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch origin "$REVISION"
git -C "$SOURCE_DIR" checkout --detach "$REVISION"
cargo build --locked --release --manifest-path "$SOURCE_DIR/sw/deployer/Cargo.toml"
cp "$SOURCE_DIR/sw/deployer/target/release/sc64deployer" "$OUTPUT_DIR/sc64deployer"
