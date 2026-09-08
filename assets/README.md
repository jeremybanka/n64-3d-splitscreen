# Editable sample content

The rabbit and robot are original assets created for this repository in Blender
5.2.1. Their `.blend` files are the editable source of truth; the generated Zig
files are checked-in build inputs. Normal builds, host tests and CI need no
Blender installation. The preview image belongs to the rabbit's studio scene.

| Content pack | Blender source | Generated mesh | Zig scene recipe |
| --- | --- | --- | --- |
| `meadow` (default) | `rabbit.blend` | `src/generated/rabbit.zig` | `src/content-meadow.zig` |
| `robot-courtyard` | `robot.blend` | `src/generated/robot.zig` | `src/content-robot-courtyard.zig` |

The rabbit has 130 source vertices / 188 triangles, using 404 of the 768 animated
vertices after face shading, RSP batch padding and the contact shadow. The robot
has 96 source vertices / 144 triangles and uses 260 animated vertices. The C
hardware adapter and its Bunny Meadow template HUD are shared by both packs.

## Edit and export

1. Edit a checked-in `.blend`, or save your own copy. Keep the exported mesh
   objects in the explicit `Character` collection; nested collections work too.
   Keep preview floors, cameras and lights outside that collection.
2. Save the source in Blender. Run `mise run models` to export both saved sources,
   or use the command below for a single source/collection/output.
3. Run `mise run test` and build the chosen pack with `make CONTENT=meadow` or
   `make CONTENT=robot-courtyard`. Reload the resulting ROM in the emulator.
4. Commit the edited `.blend`, generated `.zig`, and any changed content recipe
   together. Export never saves the source or regenerates the character.

```sh
# Replace this path or set BLENDER when using make models on another platform.
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --python-exit-code 1 --python scripts/export-mesh.py -- \
  --source assets/rabbit.blend --collection Character \
  --output src/generated/rabbit.zig
```

Export uses saved object transforms and evaluated mesh modifiers, triangulates
the evaluated mesh, and sorts objects by name for repeatable output. It does not
modify the editable geometry. Apply or realize instances before export; this is
a mesh workflow, not a scene graph or skeletal animation exporter. Rename objects
freely, but expect the generated ordering and batch packing to change.

## Coordinate and material contract

- One Blender unit is one metre. Put the feet on Blender Z=0 with the character
  facing Blender -Y. World-space Blender X/Z/-Y becomes game X/Y/Z; the game is
  Y-up and +Z-forward. Export multiplies by 256 and rounds to signed 16-bit Q8.
- Each mesh object needs an integer custom property `animation_part`: `0` keeps
  it with the body, `1` and `2` move opposing limbs, and `3` sways sideways. The
  content recipe controls stride, sway and bob divisors. No armature is required.
- Every face needs a material. Each used material needs an integer custom
  property `palette_index`, with used indices contiguous from zero. Different
  colors must not share an index. Per-face material slots are respected.
- Material Properties → Viewport Display → Color (`diffuse_color`) supplies the
  opaque RGB palette. Shader node colors, textures and transparency are not
  exported. Preview nodes can be set to match the viewport color.
- Each triangle receives a baked directional shade. Mirrored object transforms
  have their winding corrected; singular transforms are rejected.
- `player_material` in the content recipe chooses the palette slot replaced by
  the four player colors from `game.zig`. The recipe appends its contact-shadow
  color and selects `shadow_material`; this slot is not authored in Blender.

Export rejects non-finite/out-of-range coordinates, unsupported animation tags,
missing or conflicting material metadata, invalid indices, and triangles that
collapse after quantization. It checks capacity including shade splits, even
batch padding and the 16-triangle shadow: 768 animated vertices, 64 batches and
4096 indices. It reserves translation/rotation/hop headroom for the sample's
13-metre world bounds and standard gait. Fix the named object/material/triangle
before trying again; a failed export preserves the last successful `.zig`.

## Replace the example scene

A content module supplies `character`, `palette`, player/shadow material slots,
positive animation divisors, `shadowHeight(x, z)` and `environment(draw)`. The
robot courtyard demonstrates replacing the character, palette, motion and all
scenery without changing `src/main.c` or the ABI.

`environment` uses the small Zig drawing interface: `worldTri`, `box`, `cone`,
`group`, `Vec3` and integer `sin`/`cos`/`mul`. `group()` starts a spatial group for
frustum culling. Scenery is decorative; ground/world bounds and player separation
remain in `game.zig`. The meadow recipe retains its elevated path shadow; the
courtyard supplies a flat-floor shadow height.

To add a third pack, copy a content module, select its generated mesh, add its
name to Make's `CONTENT` choices and the host/ROM test scripts, and ensure Make
tracks its generated inputs. Actor culling bounds derive from the mesh and gait.
If a fork changes motion, world scale or capacity, update exporter headroom checks
alongside the runtime and rerun the animation-bounds test. The existing C symbol
`scene_rabbit` is an ABI name for whichever character is selected.

## Regenerate the original recipes

The generation scripts are separate from export and require an explicit output.
They refuse to replace an existing source unless `--overwrite` is also supplied.
This operation discards manual edits at that chosen path.

```sh
blender --background --python-exit-code 1 --python scripts/make-rabbit.py -- \
  --output /tmp/new-rabbit.blend
blender --background --python-exit-code 1 --python scripts/make-robot.py -- \
  --output /tmp/new-robot.blend
```

The rabbit generator optionally accepts `--preview /tmp/rabbit.png` for a studio
render. Use `export-mesh.py` afterward to generate ROM data.

`mise run test` runs the pure-Python validation suite and both packs' Zig tests.
`mise run test:models` optionally runs Blender integration tests: reproducible
exports, source SHA-256 preservation, previous-output preservation on failure,
per-face materials, palette errors and mirrored winding. The full ROM suite
also builds the alternate four-player and validation configurations. Static
build checks do not establish the alternate pack's hardware FPS or visual QA.
