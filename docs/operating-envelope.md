# Operating envelope and memory measurements

The template targets a 320×240, one-to-four-view arena in base **4 MiB RDRAM**.
That is the acceptance target, not a claim that the final feature combination
has already been measured on a 4 MiB console. The owner's successful hardware
report has no RAM/configuration details; see [the hardware record](hardware.md).

## Runtime evidence

Every ROM prints one `CONFIG` line, one `CAPACITY` line, and a `MEMORY stage=init`
snapshot after startup. It samples again around one second and then at roughly
ten-second intervals. This includes allocations that happen after initialization,
such as first-use audio sample buffers. Capture from boot so all records belong
to one session and attach the exact ROM hash and build options separately.

The fields are derived from the pinned SDK APIs and the current compiled layout:

| Field | Meaning |
| --- | --- |
| `ram`, `expanded`, `tv` | `get_memory_size()`, `is_memory_expanded()`, `get_tv_type()`; PAL, NTSC or M-PAL is the boot-reported video system. |
| `resident` | Physical address of `HEAP_START_ADDR`/`__bss_end`: code, constants, initialized data, BSS, alignment and the low exception-vector area below the heap. |
| `zero_bytes` | Linker span from `__rom_end` to `__bss_end`, including padding around zero-initialized storage. A component of `resident`. |
| `heap_total`, `heap_used`, `heap_free` | `sys_get_heap_stats()` reports total heap and allocated bytes; free is their difference. The SDK uses newlib `mallinfo().uordblks` for allocated bytes. |
| `reserved` | `ram - resident - heap_total`. The pinned allocator reserves 64 KiB above the heap for the stack. This is not a measured stack high-water mark. |
| `sampled_min_free` | Minimum free heap among the snapshots so far. It is not an exact allocation peak and can miss transient allocations. |
| `color_bytes`, `depth_bytes` | Display width × height × bytes/pixel × buffer count, and actual depth stride × height. Pixel payload only; included in heap use, not extra terms to add to it. |

The accounting identity is `resident + heap_used + heap_free + reserved = ram`.
Free heap includes fragmented blocks; it is not a guarantee that one allocation
of that size will succeed. An 8 MiB run with ample headroom cannot prove 4 MiB
support. Use an actual 4 MiB runtime configuration and record whether it is an
emulator or a physical console with a Jumper Pak. No code changes the detected
RAM amount or substitutes an estimate for that run.

```sh
# Capture the complete boot/runtime log for the exact ROM being tested.
nu --no-config-file scripts/check-memory.nu path/to/capture.log \
  --require-base-memory --tv NTSC --minimum-seconds 600 \
  --content meadow --audio 1 --textured 1 --collision 1
```

The checker enforces one boot/configuration, balanced accounting, consistent
region/RAM and surface sizes, monotonically increasing time, at most 15 seconds
between samples, and the requested configuration/duration. By default it requires
at least 60 seconds and **256 KiB of sampled free heap**. The 256 KiB minimum and
15-second maximum gap are project acceptance policies, not N64 platform
guarantees. Record any intentional policy change and why. The tool checks the
log's contents; it cannot certify that a log came from physical hardware.

Run the separate performance/audio/material checker against the same capture.
Passing memory accounting does not establish framerate, correct sound, absence
of audio glitches, or visual correctness. Validation ROMs have additional
allocation/timing overhead and should be recorded separately from playable and
benchmark ROMs.

## Static storage and dynamic allocations

`CAPACITY` uses `sizeof` and array lengths from the compiled C/Zig ABI. For the
current layout, each interleaved vertex pair is 32 bytes. Each mesh reserves
1,024 pairs (2,048 vertices), 64 batches and 4,096 byte indices; the two mesh
buffers occupy 75,800 bytes. Each batch loads at most 64 RSP vertices, beginning
at an even vertex offset; indices are local to that batch. Triangle indices
must come in groups of three.

Animated storage reserves 384 pairs (768 packed vertices) per physical player,
four players and three fenced frame slots: **147,456 bytes**. Cameras, culling
bounds, source/material maps, game state, SDK globals and adapter arrays add
other static storage. These named mesh/animation numbers are components, not a
complete static-memory total; `resident` captures the total compiled span and
changes when optional integrations or content change.

Three 320×240 16-bit color buffers use 460,800 payload bytes. One 16-bit depth
surface uses 153,600: **614,400 bytes combined**. Display/RSP/RDP queues, recorded
command blocks, viewport matrices and font support allocate additional heap
storage. The audio integration adds AI buffers, mixer/sample/decoder storage
and DFS state, including lazy allocations. The optional 16×16 RGBA16 texture
uses 512 bytes of static pixels and a 512-byte TMEM upload; TMEM is RDP storage,
not another 512-byte malloc. Always use the compiled/runtime report for the
selected configuration instead of adding these descriptions to heap usage.

## Coordinate and conservative-bound obligations

Packed positions and culling boxes use signed 16-bit Q8 coordinates: **−128
through 127 + 255/256 world units**. Integer gameplay values must remain safely
within their own arithmetic limits before packing. The collision API has a
narrower explicit ±32-unit range and separate shape/movement limits; see
[collision queries](collision.md). The sample constrains player centers to ±13
units. Mesh packing now reports out-of-range coordinates in both Debug and
ReleaseSmall; initialization/frame submission stops on the overflow flag.

The mesh builder rejects vertex/index/batch capacity overflow before writing
outside its arrays, and the animated mesh must fit each frame slot. C static
assertions keep draw-block and camera-slot storage aligned with the shared
mesh/frame capacities. Changing an ABI field requires updating both languages
and rerunning the layout/ROM checks.

Visibility bounds must contain every transformed vertex, including walking
limbs, ears/bob, jumps and ground shadows. Enlarging a character or animation
requires enlarging/deriving its conservative bounds; shrinking a bound to make
culling faster can make visible geometry disappear. Host tests exercise packed
body/shadow bounds through the benchmark and both supplied content packs after
integration. DMA source data and camera matrices must remain unchanged until
their frame-slot fence completes. Asset limits and coordinate tests do not
replace that lifetime requirement.
