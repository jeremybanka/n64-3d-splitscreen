# Bunny Meadow — N64 3D split-screen template

A Zig-first Nintendo 64 template with one shared 3D world, four little rabbit
characters, and **1–4 independent third-person cameras**. Triangles, depth
buffering, antialiasing, clears, and text are drawn by **libdragon RDPQ**.
There is no CPU framebuffer rasterizer.

<img src="docs/screenshots/4-players.png" width="640" height="480" alt="Four players in the same 3D meadow">

## Play

The ROM opens in four-player mode. All four rabbits exist in the world even
when fewer cameras are displayed; each controller always owns its matching
rabbit. A controller is not required to see the initial demonstration.

| N64 control | Action |
| --- | --- |
| Stick / D-pad | Move relative to that player's camera |
| A | Hop |
| C-left / C-right, or L / R | Orbit that player's camera |
| B | Recenter camera behind the rabbit |
| Player 1 Start | Cycle 4 → 1 → 2 → 3 → 4 views |
| Player 1 Z | Toggle the automatic walking/camera tour |
| Player 1 C-down | Reset the shared world |

One player fills the screen. Two players use horizontal halves. Three use a
wide top view and two lower views. Four use quadrants. Projection uses each
view's actual dimensions, with RDP scissoring preventing any drawing across
the separators.

## Build and run

Zig 0.16.0 and the libdragon revision are pinned. Rust is only needed for the
optional SummerCart64 deployment tool.

```sh
mise trust
mise install
mise run setup       # first SDK build can take a long time
mise run build
mise run verify
mise run emulate     # pinned ares v147, OpenGL 3.2, homebrew mode
```

Output: **`n64-3d-splitscreen.z64`**. Normal builds use the checked-in rabbit
mesh and do not require Blender. If the SDK is already installed, set
`N64_INST=/path/to/libdragon` and run `make` with Zig on `PATH`, or reuse it
at `.build/libdragon`.

The emulator helper uses the project's pinned ares installation. The
installed v148 Metal backend flickered on the development machine; v147's
OpenGL backend is used for visual verification. Map ares's four virtual
controllers to your keyboards/gamepads in Settings → Input. Existing user
controller mappings are not replaced by the project.

Build options also make individual layouts easy to inspect without controllers:

```sh
make INITIAL_VIEWS=1           # 1, 2, 3, or 4
make INITIAL_VIEWS=3 AUTOTOUR=1 # animated demonstration
make PROFILE=1                # scene/submission times and triangle count
make VALIDATE=1               # libdragon RDP command validation (slow)
make                          # restores the normal four-player configuration
```

Reload the ROM in ares after building. Changes to these options automatically
rebuild the adapter. The simulation uses a fixed 60 Hz step independently of
rendering, with bounded catch-up after a pause.

## Make it your game

- `src/game.zig`: player state, input packing, movement, hopping, separation,
  camera yaw, tour, and view count. Replace or extend these rules.
- `src/scene.zig`: viewport layouts, cameras, fixed-point transforms,
  perspective projection, clipping, back-face culling, static-world cache,
  world primitives, and animated rabbit instances.
- `src/main.c`: the small libdragon adapter for controllers, timing, RDPQ
  submission, font drawing, depth-buffer attachment, and presentation.
- `src/bridge.h`: the explicit fixed-width ABI/data contract.
- `scripts/make-rabbit.py`: reproducible Blender model and mesh exporter.
- `assets/rabbit.blend`: editable character and studio scene.
- `src/generated/rabbit.zig`: ROM-ready indexed mesh (130 vertices / 188 triangles).

The player jerseys are colored per instance. Feet and arms move while walking,
ears sway, and all players are depth-tested against the same environment.
Trees, rocks, mushrooms, and the carrot monument are decorative; the sample
physics implements ground, world bounds, and player separation, not general
mesh collision. No audio, save system, or networking is included.

```sh
make models  # Blender on macOS; set BLENDER for another executable location
```

The Blender script rebuilds both the editable `.blend` and the generated Zig
mesh. To preserve manual edits, work in a copy of the `.blend` or adapt the
export script instead of regenerating over your edits.

![Rabbit model](assets/rabbit-preview.png)

## Verification and limits

`make test` runs 12 host tests covering controller isolation, jumping,
world bounds, view layouts, projection/clipping, winding, cache invalidation,
and an animated tour through every layout. `mise run verify` checks the ROM
header, O64 ELF, implicit runtime calls, and the reserved global pointer.

See [the ares verification record](docs/verification.md) and
[the Zig/libdragon architecture](docs/architecture.md), especially before
changing compiler flags or the ABI bridge. RSP triangle setup and RDP drawing
are hardware accelerated; transforms and clipping run on the CPU in Zig.
This is a small working foundation, not a high-throughput 3D engine.

The framebuffer is 320×240 at 16 bpp, triple buffered, with one shared 16-bit
Z surface. No Expansion Pak is required by the allocation budget. Real N64,
SummerCart64, and M64 hardware have not been tested in this adaptation.

For hardware deployment, connect a SummerCart64 and run `mise run deploy`;
`mise run debug` opens its debug terminal. For SD-card use, copy the `.z64`
into the cart's ROM library. The ROM has no save type.
