set minimum-version := '1.58.0'
set shell := ['nu', '--no-config-file', '-c']
set script-interpreter := ['nu', '--no-config-file']
set default-script := true
set positional-arguments
export ZIG_GLOBAL_CACHE_DIR := env('ZIG_GLOBAL_CACHE_DIR', justfile_directory() + '/.zig-cache/global')

# Show available project tasks. Install their tools with `mise install`.
default:
    ^just --list

# Build the ROM; options: --views 1..4, --autotour/--profile/--validate/--benchmark 0|1.
build *args:
    def --wrapped main [...args: string] { ^nu --no-config-file scripts/build.nu ...$args }

# Run host tests in Debug or ReleaseSmall.
test optimize='Debug':
    def main [optimize: string] { ^zig test src/scene.zig -O $optimize }

fmt:
    ^zig fmt --check src tools/patch_mips_abi.zig

check-scripts:
    ^nu --no-config-file scripts/check-scripts.nu

check-workflows:
    ^actionlint

check: fmt check-scripts check-workflows

test-build:
    ^nu --no-config-file scripts/test-sdk-identity.nu
    ^nu --no-config-file scripts/test-build-dependencies.nu

test-rom:
    ^nu --no-config-file scripts/test-rom.nu

setup:
    ^nu --no-config-file scripts/bootstrap-libdragon.nu
    ^nu --no-config-file scripts/bootstrap-tiny3d.nu

verify: build
    ^nu --no-config-file scripts/verify-rom.nu

clean:
    ^nu --no-config-file scripts/build.nu clean

emulator-setup:
    ^nu --no-config-file scripts/bootstrap-ares.nu

emulate: build emulator-setup
    ^nu --no-config-file scripts/run-ares.nu

docs:
    ^nu --no-config-file scripts/sync-docs.nu

sc64deployer:
    ^mise exec rust@1.98.0 -- nu --no-config-file scripts/bootstrap-sc64deployer.nu

deploy: build sc64deployer
    ^.build/bin/sc64deployer upload n64-3d-splitscreen.z64 --save-type none

debug: sc64deployer
    ^.build/bin/sc64deployer debug

# Blender is the explicit bpy language boundary, replaced by the asset PR adapter.
models:
    let blender = $env.BLENDER? | default '/Applications/Blender.app/Contents/MacOS/Blender'
    ^$blender --background --python scripts/make-rabbit.py
