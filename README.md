# 2048 for Nintendo 64

A from-scratch 2048 implementation for Nintendo 64, written in Zig 0.16.0 and
rendered/input-driven through libdragon. It targets stock N64 behavior, so the
same ROM can run on original hardware, an accuracy-focused emulator, or a
ModRetro M64 through a SummerCart64.

## Play

- D-pad or analog stick: slide the board
- A after reaching 2048: keep playing
- Start: start a new game

The board follows the original rules: equal adjacent tiles combine once per
move, every successful move spawns a 2 (90%) or 4 (10%), and the score is the
sum of newly created tiles.

## Toolchain

[mise](https://mise.jdx.dev/) is the single entry point. The project pins Zig
0.16.0 and Rust 1.98.0 in `mise.toml`; Rust is only used to build the official
SummerCart deployment utility.

```sh
mise install
mise run test
mise run setup     # first run builds the pinned libdragon GCC SDK
mise run build
mise run verify    # inspect the linked ABI and ROM header
```

The ROM is written to `n64-2048.z64`. The first native libdragon toolchain build
is substantial (several gigabytes of temporary disk and potentially an hour).
On macOS, libdragon's official bootstrap uses Homebrew for its native build
prerequisites.

## Run in an emulator

On macOS, install and launch the tested emulator build through mise:

```sh
mise run emulator-setup
mise run emulate
```

The project pins the official ares v147 universal build, verifies its SHA-256
checksum, enables Homebrew Development Mode, and launches its OpenGL 3.2 video
backend. ares v148 removed that backend; its Metal presentation flickers on
this development machine, including when running libdragon's stock example
ROMs. The pinned emulator is installed under `.build/` and is not committed.

## Run on SummerCart64 and M64

Update the M64 and SummerCart64 firmware first, connect the SummerCart64 USB-C
port to the development computer, power on the M64, then run:

```sh
mise run deploy
```

For logs in a second terminal:

```sh
mise run debug
```

For SD-card use, copy `n64-2048.z64` anywhere in the card's ROM library and
launch it from N64FlashcartMenu. No save type or Expansion Pak is required.

## Documentation

Start at [`docs/README.md`](docs/README.md). The repository includes offline
snapshots of the Zig language reference, libdragon's wiki and documented
headers, SummerCart64's protocol/quick-start material, and an M64 quick guide.
Refresh them with `mise run docs`.
