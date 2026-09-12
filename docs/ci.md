# Continuous integration

The workflow structure follows [Lasertag](https://github.com/jeremybanka/lasertag):
separate `check.yml` and `test.yml`, one shared composite setup action, immutable
action revisions with version comments, a pinned mise release, read-only
repository permissions, explicit Nushell scripts, and per-workflow/per-ref
concurrency that cancels obsolete runs.

Both workflows run on pushes to `main` and opened, updated, or reopened pull
requests. They can also be dispatched manually from the Actions page. There are
no path filters, so documentation-only changes still produce a complete set of
checks. GitHub's normal `pull_request` event supports forks without repository
secrets. No workflow publishes releases or deploys to hardware.

## Check

| Job | Local command | Coverage |
| --- | --- | --- |
| Formatting | `just fmt` | Zig source, generated mesh, and ABI patch tool formatting |
| Scripts | `just check-scripts` | Native Nu parsing, isolated SDK identity fixtures, mesh validation/serialization regressions, original WAV verification and eight audio/benchmark test groups |
| Workflows | `just check-workflows` | actionlint, including expressions, action inputs, and embedded shell commands |

`just check` runs all three. Each job has a five-minute timeout. Tool
versions live in `mise.toml`; `.github/actions/setup/action.yml` selects the mise
release and caches installed tools through mise-action. Rust is scoped to the
SummerCart64 task, so normal development and CI do not install it.

## Test

The two **Zig (Debug)** and **Zig (ReleaseSmall)** jobs each run the full host
suite for both content packs, plus native Nu asset/workload checks and C material-state tests,
with a five-minute timeout. Debug preserves runtime safety checks;
ReleaseSmall exercises the optimization mode used for the N64 object. A matrix
failure does not cancel the other configuration.

**N64 ROM** runs on Ubuntu 24.04. On an empty cache it copies the official GCC
toolchain out of a Linux x86_64 libdragon container pinned by its immutable
image digest in `scripts/bootstrap-ci-toolchain.nu`. The compiler version is
checked against GCC 16.2.0, matching our libdragon pin. Docker is only used for
this CI bootstrap; Zig, SDK compilation, and game builds run on the host.
Local `just setup` can still build the compiler from source without Docker.

The job then builds the pinned libdragon SDK source. Its exact cache key includes
the runner architecture and hashes of `scripts/bootstrap-ci-toolchain.nu` and
`scripts/bootstrap-libdragon.nu` plus `scripts/sdk-identity.nu`, `scripts/common.nu`
and `mise.toml`, which contain
the bootstrap logic and SDK/compiler version pins. It
does not restore an older SDK when that key changes. The installed SDK is saved
after successful setup, before project builds, so a game compilation failure
does not force another compiler bootstrap. Tiny3D is built from its own pinned
revision on every run; project object files are never restored from a cache.

Downloading the compiler avoids upstream's 40–70 minute source bootstrap on an
empty cache. This job has a 20-minute timeout; later runs reuse the complete
installed SDK. Each setup verifies its recorded revision, compiler target/version,
and file hashes even on a cache hit. The compiler image digest is recorded in
its provenance. Changing runner distribution or SDK
bootstrap inputs requires a new key. To force a rebuild without a source
change, delete this repository's `n64-sdk-…` cache from GitHub Actions.

`just test-build` first checks SDK identity rejection/reuse against isolated
fixtures. It then exercises the real Nu/Zig/ABI pipeline with a newly imported
nested module, edits it without touching the root, changes embedded data, removes
the import, and verifies unchanged output. Finally it verifies a no-op sample
build preserves the C/Zig objects, ELF and ROM bytes and modification times.
New/transitive C headers and runtime archive replacement are also checked in
private copies. This step uses the installed SDK but never writes to it.

Audio dependency fixtures additionally cover changed/missing converted sources,
stale-file exclusion, audio-off builds without WAV inputs, restoring audio, and
unchanged output bytes/timestamps. They use private project storage.

`just test-rom` starts with `just clean`, then builds:

- One-, two-, three-, and four-player layouts.
- Four-player validation/profiling with the automatic tour.
- The four-player benchmark with audio enabled and disabled (identical workload 2).
- Robot courtyard in four-player and validation/tour configurations.
- Textured meadow in all four layouts, plus validation/tour and benchmark.
- Textured robot courtyard in validation/tour and benchmark configurations.

Every variant passes `scripts/verify-rom.nu`: big-endian ROM magic, O64 linked
ELF, no implicit external calls from Zig, and no use of the reserved MIPS global
pointer. The task leaves the normal four-player ROM as the default output.

The `n64-roms-<commit>` artifact contains all seventeen `.z64` variants and
`SHA256SUMS`, retained for 14 days. These checks establish that the game builds
and meets the static ABI contract. They do not boot the ROM, listen to audio, or measure FPS.
Blender-specific integration tests are optional locally (`just test-models`);
CI checks generated data without requiring Blender.
Visual correctness, input behavior in the emulator, RDPQ runtime validation,
and the 40+ FPS target still use the [ares verification procedure](verification.md).
The recorded performance log is evidence from that run, not a CI benchmark of
future commits.

## Maintenance

- Update Nu, Just, Zig and linter pins in `mise.toml`. Run `mise install`, `just check`,
  both host test modes, and `just test-rom` before accepting a compiler update.
- Update action SHA pins and their version comments together. The shared setup
  action pins mise separately, matching the Lasertag pattern.
- Update the SDK revision/GCC version in `scripts/sdk-identity.nu` and the Tiny3D
  revision in its bootstrap script together after
  checking compatibility. If the SDK's compiler version changes, update the CI
  compiler image digest as well. Resolve that digest from the
  official `ghcr.io/dragonminded/libdragon` registry; never use a floating tag in
  CI. Either pin change invalidates the SDK cache automatically.
- Run `just setup` before `just test-rom` locally. The latter rebuilds
  the project's `build/` directory; generated ROMs remain ignored by Git.

The workflows provide six job results: Formatting, Scripts, Workflows,
Zig (Debug), Zig (ReleaseSmall), and N64 ROM. Branch protection is configured
separately in repository settings; these files do not change it.
