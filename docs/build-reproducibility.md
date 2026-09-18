# Reproducible SDK reuse and incremental builds

Run `mise install` for pinned Nushell 0.115.1 and Just 1.58.0.
Project scripts use native Nushell. The only Python file, `blender-adapter.py`,
calls Blender's `bpy` API through JSON; Nu owns model recipes, conversion,
validation and export. The source revision and GCC
version are pinned in `scripts/sdk-identity.nu`; the official CI compiler image
remains pinned by digest in `scripts/bootstrap-ci-toolchain.nu`.

## SDK identity

After a successful source build, setup writes `.n64-template-sdk.json` inside
`N64_INST`. It records the libdragon revision, GCC version/target, compiler
provenance when available, and SHA-256 hashes of installed files (compiler,
compiler internals, SDK tools, libraries, headers, and linker scripts). CI's
compiler receipt records the immutable image digest; local compiler builds
record the libdragon source revision containing the toolchain build script.

Every later `just setup` validates the receipt, live compiler identity, and
file hashes. It rejects missing metadata, a different revision/version/target,
and changed or missing installed files. It does not overwrite an existing SDK
that failed verification. The receipt travels with a newly built SDK and can be
reused after relocation, including in CI's cache. Receipts establish build
provenance and detect accidental replacement; they are local metadata, not a
cryptographic signature from upstream.

`just build` consumes the selected SDK; run setup before building after changing or
replacing that SDK. An external installation remains supported through explicit
`N64_INST` on setup and build commands. When absent, Nu selects this checkout's
`.build/libdragon`; mise does not override an external installation.

## Existing installations without receipts

If the original clean pinned libdragon checkout is available, verify the SDK
without changing it:

```sh
N64_INST=/path/to/existing/sdk nu scripts/bootstrap-libdragon.nu \
  --verify-source /path/to/libdragon-source
N64_INST=/path/to/existing/sdk nu scripts/bootstrap-libdragon.nu
N64_INST=/path/to/existing/sdk nu scripts/bootstrap-tiny3d.nu
N64_INST=/path/to/existing/sdk just build
```

The verification command checks the source revision and tracked-file cleanliness,
compares installed headers/linker scripts with that source, and rebuilds both
runtime archives in a temporary project directory using the existing compiler.
It compares all archive contents, including debug data, after normalizing GNU
ar timestamps in temporary copies. It does not run an install target, modify the
source checkout, or change files inside the existing SDK. The installed compiler
must have the pinned version and target; its binaries and the existing host tools
are fingerprinted, rather than claiming their original build provenance.

On success, a receipt is saved only in this checkout's ignored
`.build/libdragon-identity.json`. Repeat verification in another checkout that
uses the same unmarked installation. A failed comparison leaves the SDK intact.
A rebuild with another host/toolchain configuration can legitimately produce
different archive bytes; that result still requires explicit recovery rather
than silently certifying an unknown installation.

If provenance cannot be verified, build into a **new, empty directory**:

```sh
N64_INST=/path/to/new/sdk nu scripts/bootstrap-libdragon.nu
N64_INST=/path/to/new/sdk nu scripts/bootstrap-tiny3d.nu
N64_INST=/path/to/new/sdk just build
```

Keep the old SDK until other projects using it have migrated. Do not delete a
shared installation or blindly create/edit a receipt to bypass verification.
A compiler-only directory, including CI's pinned compiler bootstrap, is supported:
setup checks GCC's pinned version/target before building the SDK into it.

## Build dependencies

The Nu build invokes `zig build-obj` on each check of `build/scene.o`. Zig's own cache
knows every import and `@embedFile`, including files introduced after a previous
build. There is no hand-maintained source list or approximate import parser.
The unchanged `mips3+noabicalls`, `-fno-PIC`, ReleaseSmall compilation and audited
ABI patch/verification run against a temporary output. Only changed object bytes
replace `build/scene.o`, so a cache hit preserves downstream ELF/ROM timestamps.
`--content meadow|robot-courtyard` selects the Zig `content` module explicitly;
the dependency regression checks switching packs and restoring the default.

C compilation fingerprints GCC's preprocessed output, flags, compiler and
assembler binaries. GCC discovers transitive headers each time, including newly
included files; no dependency list is maintained by hand. Link fingerprints
include project objects, Tiny3D, the SDK library tree, GCC runtime/startup
archives, linker tools and specs. Packaging fingerprints include the ELF and SDK
ROM tools. Content comparisons preserve unchanged output timestamps. Different
build flags invalidate the appropriate stages without relying on timestamp ticks.

`build.nu` mirrors the pinned SDK's C, link and packing flags. When updating the
SDK, review its `n64.mk` against that implementation. Third-party Makefiles and
bootstrap shell scripts are invoked only inside their upstream checkouts; the
project has no Makefile and mise defines no tasks. See the official
[Nu external argument rules](https://www.nushell.sh/book/running_externals.html),
[Just script recipes](https://just.systems/man/en/script-recipes.html), and
[mise GitHub backend](https://mise.jdx.dev/dev-tools/backends/github.html).

Byte comparisons are scoped to the same checkout path: Zig debug symbols can
encode build paths, so this does not promise identical ROM hashes across paths.

Run `just test-build` after setup to exercise these behaviors. SDK identity
fixtures also run in `just check-scripts` without a real SDK. The dependency
regression compiles temporary projects through the actual recipes, checks new
and transitive C headers, and replaces a runtime archive in a private SDK copy.
It also verifies that a no-op full build preserves all project artifacts. CI runs these
checks before all seventeen ROM variants; it still rejects global-pointer use and
unresolved Zig calls on every verified object.
