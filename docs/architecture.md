# Zig / libdragon 3D architecture

## Rendering pipeline

`game.zig` advances a single shared world at 60 Hz. Each of the four controller
ports addresses exactly one rabbit. Camera visibility is independent of actor
existence, so changing the split count never duplicates or resets the world.

For each visible camera, `scene.zig` computes a viewport and a camera basis,
transforms mesh vertices using Q8 integers, clips against the near/far planes,
projects once per rabbit vertex, culls back faces, and clips projected polygons
to the viewport. Screen coordinates use Q4 pixels; depth is a perspective
UNORM16 value. Trivially accepted/rejected triangles avoid polygon clipping.
Static scenery is cached independently per camera and invalidated on changes
to camera position, yaw, or viewport dimensions. Rabbit geometry is updated
every frame. A bounded 2,048-triangle output array prevents buffer overruns;
cache overflow falls back to generating the scenery directly.

The C adapter reads the shared array, converts its fields to the floats required
by `TRIFMT_ZBUF_SHADE`, and calls `rdpq_triangle`. In the pinned SDK this queues
triangle setup on the RSP; the RDP performs shading, Z comparison/update, and
pixel rasterization. Text, background clears, borders, and presentation also
use RDPQ. No CPU code paints the framebuffer.

Three color surfaces and one depth surface are used. Depth is cleared once
at the beginning of each queued frame. Viewports are disjoint, so one depth
surface is sufficient. Fill-mode scissor X starts are multiples of four pixels;
the center separator is drawn afterward over the aligned view boundary.
The RDP command queue orders consecutive frames and
`rdpq_detach_show` presents only after hardware completion. The CPU can reuse
the shared triangle array once submission finishes because RDPQ has copied
its vertex data into the queue.

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
a vertex is three 32-bit integers, a triangle is three vertices plus RGBA32
(40 bytes), and a viewport is four 32-bit integers (16 bytes).

`patch_mips_abi.zig` relabels the object's metadata for the GNU O64 linker.
This is valid only together with this deliberately restricted interface.
The private engine has **no unresolved external calls**. In particular,
compiler-generated `memcpy`/`memset` calls would bypass the interface. Clipping
and cache copies use explicit volatile stores so the compiler does not lower
them to libc calls. `verify-zig-abi.sh` rejects such unresolved calls before
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

The first experiment of making one copy explicit only changed register
allocation and hid the symptom in a minimal scene. The global-pointer flag
is the root fix. Both that flag and the no-external-call check are retained.

`ReleaseSmall` keeps the scene code compact for the VR4300 instruction cache.
All runtime Zig math is integer; the float conversions needed by RDPQ remain
in the O64 adapter. If libdragon gains an LLVM-supported ABI, remove this
bridge and use the C API directly from Zig.

## Extending the sample

Replace `environment()` with another bounded indexed mesh or scene builder.
Invalidate/extend the static cache if scenery becomes dynamic. Increase the
triangle budget deliberately, with a memory and frame-time check in ares.
For substantially higher triangle throughput, replace the transform/submission
backend with a batched RSP 3D renderer while retaining the world and camera
interfaces. Moving the triangle setup to the CPU was benchmarked during
development and was slower for this scene; the normal RSP path is retained.
