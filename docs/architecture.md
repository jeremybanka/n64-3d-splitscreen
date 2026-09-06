# Zig/libdragon architecture

libdragon's current toolchain targets the GCC-only MIPS O64 ABI. Zig 0.16.0
uses LLVM for MIPS code generation, and LLVM supports O32, N32, and N64 but not
O64. Compiling a direct `@cImport("libdragon.h")` application would therefore
produce calls with an incompatible ABI even though Zig can parse the headers.

This project isolates that toolchain mismatch:

1. `src/game.zig` contains all game state and rules and is compiled by Zig for
   big-endian MIPS III/N32. This keeps 64-bit callee-saved registers intact.
2. `src/main.c` is compiled O64 by libdragon's official GCC and owns controller,
   display, timing, and debug APIs.
3. Only functions with zero or one 32-bit integer argument and a 32-bit integer
   result cross the boundary. Those values use the same MIPS argument/result
   registers in both conventions. Pointers, floats, aggregates, varargs, and
   stack arguments are forbidden at this seam.
4. `tools/patch_mips_abi.zig` relabels the engine object for the GNU linker. The
   compiler-generated memory primitive is redirected to a Zig-local volatile
   implementation before linking so it cannot cross into O64 newlib.

This is intentionally small and auditable. If libdragon adopts an LLVM-supported
ABI, or Zig gains O64, the bridge should be deleted and the libdragon C API can
be imported directly.
