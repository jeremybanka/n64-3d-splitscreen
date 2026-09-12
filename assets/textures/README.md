# Optional ground texture

`just build --textured 1` enables the same small material example in either content
pack. The default `--textured 0` keeps the existing flat-shaded appearance.
The original staggered stone pattern lives in `ground.ppm`, an editable 16×16
ASCII P3 Netpbm image. It is neutral gray so vertex colors retain the meadow or
courtyard palette.

```sh
just build --textured 1 --content meadow
just build --textured 1 --content robot-courtyard
just build --textured 1 --benchmark 1
just build --textured 1 --validate 1 --profile 1 --autotour 1
just build # restore flat-shaded default
```

## Data and resource costs

| Property | Contract |
| --- | --- |
| Source | P3 RGB, 16×16, channel maximum 255, top-to-bottom rows |
| Resident format | Opaque RGBA5551 (`FMT_RGBA16`), no palette or texture codec |
| Pixel bytes | 512 bytes in the linked ELF and resident RDRAM; eight-byte alignment |
| Surface | 32-byte row stride; a 12-byte surface descriptor on the N64 |
| TMEM | 512 of 4096 bytes, at offset zero, using `TILE0`; no TLUT |
| Upload | Once per viewport that draws ground; at most 2048 pixel bytes per four-view frame |
| Mesh overhead | No extra triangles or vertex storage; UVs use existing packed fields |
| Batch metadata | 64 fixed-width material IDs, 256 bytes, alongside the world mesh |

The generated header is included only when textures are enabled. `surface_make`
wraps immutable resident pixel data, with one cache writeback at initialization;
there is no texture allocation or decode in the render loop. RSP/RDP commands
can safely reference the data for the entire program lifetime. The small
adapter state and linked texture-upload routines add code/data beyond the pixel
payload; inspect the linked ELF for the total cost in a specific build. Libdragon
compresses the executable during ROM packaging, so the final ROM-size increment
depends on executable compression and packaging alignment.

## UVs and material state

Tiny3D's packed UV fields are signed 10.5 fixed-point **texel** coordinates,
independent of the Q8 position format. The ground uses `(u, v) = (world_x,
world_z)` in those packed fields. At 256 position units per metre and 32 UV
units per texel, this gives eight texels per metre and one 16-pixel repeat every
two metres. The 32×32-metre floor stays in packed UV range -4096..4096, or
-128..128 texels, well within signed 16-bit storage. Negative coordinates wrap.
S increases with world +X and T with world +Z. The tile repeats infinitely on
both axes and uses bilinear filtering with perspective correction.

`groundTri` marks only the sixteen floor groups as material 1; ordinary scenery
is material 0. Every batch has one material, so its existing AABB, recorded
vertex/triangle commands and per-view frustum culling continue to apply.
`TEX_SHADE` modulates texels by the authored ground vertex colors. The C adapter
binds state after culling each batch, restores the SHADE combiner and untextured
Tiny3D flags before actors, then lets the HUD enter its normal 2D mode. Actors,
shadows and all three animated frame slots retain zero UVs.

The HUD uploads font data to TMEM, so `material_view_begin` invalidates texture
residency for every camera. The first visible textured batch reloads the tile;
subsequent ground batches reuse it only within that view. This prevents one
view's font from appearing on the next view's floor. Existing depth testing,
scissors and frame completion fences are retained.

## Replace the tile

Edit `ground.ppm` in a pixel editor that exports ASCII P3 Netpbm, keeping 16×16
RGB pixels and maximum channel value 255. Then run:

```sh
nu --no-config-file scripts/make-texture.nu
nu --no-config-file scripts/make-texture.nu --check
just test
just build --textured 1 --validate 1
```

Commit both the source and `src/generated/ground_texture.h`. Ordinary ROM builds
use the checked-in header without Blender or an image conversion tool.
The converter rejects dimension/channel errors, discards the low three bits of
each RGB channel and sets the one-bit alpha to opaque. Different dimensions,
formats, transparency or multiple simultaneous textures require updating the
adapter's explicit surface/TMEM contract and tests. This example deliberately
provides one material path.

## Benchmark and validation

Every new PERF sample identifies both `textured=0|1` and the content pack. Use:

```sh
nu --no-config-file scripts/check-performance.nu capture.log --audio on --textured on --content meadow
nu --no-config-file scripts/check-performance.nu courtyard.log --audio on --textured on --content robot-courtyard
nu --no-config-file scripts/check-performance.nu flat.log --audio on --textured off --content meadow
nu --no-config-file scripts/check-performance.nu docs/performance.txt --audio legacy --textured legacy
```

The checker rejects mixed or missing identities. Historical untagged logs require
`legacy` and are identified as the old untextured meadow workload; their FPS does
not establish performance for this revision or for textured content.

Host tests check packed UV ranges, exactly 32 textured floor triangles,
untextured actor/frame data, source-to-header reproducibility and workload
identity. Adapter tests use test doubles to exercise flat/textured bindings,
depth flags and HUD-to-viewport reloads through all four layout counts. They do
not execute the RSP or RDP. The ROM suite builds seventeen variants, including
textured layouts 1–4 and validation/benchmark configurations for both packs.

Runtime RDPQ validation, visual inspection and FPS measurements for the textured
workload remain pending. Before accepting hardware performance, run a longer
four-player benchmark, check all three phases, orbit and hop through the floor,
inspect every split layout for correct filtering/depth, and verify actors and
HUD text remain unchanged. Record any RDPQ diagnostics from the validation ROM.
