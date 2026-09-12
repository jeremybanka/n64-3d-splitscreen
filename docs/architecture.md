# Zig / Tiny3D / RDPQ architecture

## Rendering pipeline

`game.zig` advances one shared world at 60 Hz. All four controller ports own
persistent rabbits, independently of how many cameras are visible. Jump and
recenter button edges survive render frames that contain no simulation step.

At startup, `scene.zig` builds indexed world and rabbit meshes in Tiny3D's
packed vertex layout. Every batch uses at most 64 RSP vertices, with even,
aligned DMA loads. Vertices are shared when their position, source vertex and
material, shade and baked face color agree. This keeps different player-tint
slots separate even if their initial colors match. The Blender mesh and its flat shading are preserved.
Scenery is grouped spatially so invisible ground tiles, trees, mountains and
other objects can be skipped per camera. The C adapter records reusable RSP
command blocks once, including triangle indices and synchronization.

Each frame, Zig computes the four animated rabbit poses once. It transforms
130 source vertices per actor into world space and scatters their positions
into the packed mesh, retaining static colors and topology. Ground shadows
follow X/Z while staying on the ground during hops. All visible cameras read
that same frame's vertices; no per-camera rabbit deformation is performed.

The C adapter constructs each camera/projection matrix and tests conservative
world and actor bounds against its frustum. Tiny3D transforms visible vertices,
clips triangles, culls back faces and performs triangle setup on the **RSP**.
The **RDP** shades and rasterizes them with antialiasing and depth comparison.
RDPQ continues to own drawing state, clears, the Z surface, HUD and presentation.
No CPU projection, triangle clipping or framebuffer rasterizer remains.

## Coordinates and asynchronous data

Zig positions retain Q8 precision. The camera matrix converts them to four RSP
units per world unit (scale 1/64), with near/far values 4/320. This keeps
Tiny3D's normalized W and integer screen scales away from severe quantization.
The camera X basis and submitted triangle winding are reversed together to
preserve the game's +Z-forward convention and camera-relative controls.

Three independent slots hold animated vertices and four camera matrix sets.
Each slot has an RSP completion fence. The CPU waits for that fence before
reusing the slot, then writes back its modified vertex cache lines before
queuing DMA. Static vertex memory remains immutable after initialization.
Do not remove the fences or reuse one mutable camera matrix for four views.

Three 320×240 color surfaces and one 16-bit depth surface are used. Depth is
cleared once per frame because the viewports are disjoint. Fill-mode scissor
X origins are multiples of four pixels; the center separator is drawn afterward.
`rdpq_detach_show` schedules presentation after hardware completion. The
repeated render loop is paced by the available display buffers.

## Calling convention boundary

The pinned libdragon GCC toolchain uses MIPS O64; LLVM/Zig supports N32 but
not O64. The engine is built for big-endian MIPS III/N32, with 64-bit GPRs,
32-bit pointers, **`mips3+noabicalls`**, and **`-fno-PIC`**.

Only functions taking zero or one `uint32_t` argument and returning `uint32_t`
cross the boundary. No float, pointer, struct, varargs, or stack-passed
arguments cross it. The controller word packs signed X/Y axes into bytes
0/1, flags into bits 16–19, and the player index into bits 30–31.

Data is shared separately through exported global symbols, never an
ABI-dependent aggregate call. `bridge.h` and Zig tests verify the layouts:
two interleaved vertices occupy 32 bytes, a batch descriptor and viewport each
occupy 16 bytes, and a camera occupies 24 bytes. Packed positions are signed
16-bit Q8; the RSP vertex colors and unused normal/UV fields match Tiny3D.

`patch_mips_abi.zig` relabels the object's metadata for the GNU O64 linker.
This is valid only together with this deliberately restricted interface.
The private engine has **no unresolved external calls**. In particular,
compiler-generated `memcpy`/`memset` calls would bypass the interface. The animation loop iterates over player pointers to avoid lowering an
aggregate copy into a libc call. `verify-zig-abi.nu` rejects such unresolved calls before
linking. It also rejects any use of `$gp` in the private Zig object.

## Why reserving `$gp` matters

An ordinary N32 function can save `$gp`, use it as a temporary, and restore it
on return. Libdragon's interrupt handlers assume the program-wide global
pointer remains valid at every instruction, including during a Zig call.
Without `noabicalls`, a VI interrupt during geometry generation can corrupt
memory even though ordinary calls and host tests pass. This occurred in ares
during development and was fixed by reserving the register, not by disabling
interrupts. LLVM explicitly reserves GP when ABI calls are disabled; see its
[register allocator implementation](https://llvm.org/docs/doxygen/MipsRegisterInfo_8cpp_source.html).

`ReleaseSmall` keeps the scene code compact for the VR4300 instruction cache.
All runtime Zig math is integer; camera matrix operations remain
in the O64 adapter. If libdragon gains an LLVM-supported ABI, remove this
bridge and use the C API directly from Zig.

## Extending the sample

Select a content module with `just build --content meadow` (the default) or
`just build --content robot-courtyard`. Each supplies the mesh, palette, animation
divisors, shadow height and `environment(draw)` recipe. See the
[asset workflow](../assets/README.md) to export edited Blender sources or add a
pack. Keep scenery groups small enough for useful frustum culling.

The mesh builder reports capacity exhaustion before writing outside its arrays.
Actor bounds derive from mesh coordinates and motion amplitudes; the host test
verifies every packed body/shadow vertex throughout the benchmark for both
packs. The exporter also predicts packing, and host tests compare its count
with the actual renderer. C ABI names and hardware adapter code are shared.

The normal build uses the checked-in exported rabbit mesh. Tiny3D is pinned
at `ec557373e986b5e041cc102a7ff787eb07921937`, before it adopted vector types
that exist only in libdragon preview. Its source and library are local to
`.build/tiny3d`; the SDK is not modified. `scripts/bootstrap-tiny3d.nu` fetches
and builds only the library. See the [upstream project](https://github.com/HailToDodongo/tiny3d)
and its [MIT license](licenses/Tiny3D.txt).

Run `just build --benchmark 1` after a renderer change, record ISViewer diagnostics,
and use `scripts/check-performance.nu` to check all three 20-second workloads.
`PROFILE=1` adds CPU/submission timings; `VALIDATE=1` enables RDPQ validation
and is deliberately excluded from performance acceptance.
