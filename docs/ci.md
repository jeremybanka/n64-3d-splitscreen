# Continuous integration

The workflow structure follows [Lasertag](https://github.com/jeremybanka/lasertag):
separate `check.yml` and `test.yml`, one shared composite setup action, immutable
action revisions with version comments, a pinned mise release, read-only
repository permissions, explicit Bash shells, and per-workflow/per-ref
concurrency that cancels obsolete runs.

Both workflows run on pushes to `main` and opened, updated, or reopened pull
requests. They can also be dispatched manually from the Actions page. There are
no path filters, so documentation-only changes still produce a complete set of
checks. GitHub's normal `pull_request` event supports forks without repository
secrets. No workflow publishes releases or deploys to hardware.

## Check

| Job | Local command | Coverage |
| --- | --- | --- |
| Formatting | `mise run fmt` | Zig source, generated mesh, and ABI patch tool formatting |
| Scripts | `mise run check:scripts` | ShellCheck for all shell scripts; Python syntax without importing Blender |
| Workflows | `mise run check:workflows` | actionlint, including expressions, action inputs, and embedded shell commands |

`mise run check` runs all three. Each job has a five-minute timeout. Tool
versions live in `mise.toml`; `.github/actions/setup/action.yml` selects the mise
release and caches installed tools through mise-action. Rust is scoped to the
SummerCart64 task, so normal development and CI do not install it.

## Test

The two **Zig (Debug)** and **Zig (ReleaseSmall)** jobs each run the full host
suite with a five-minute timeout. Debug preserves runtime safety checks;
ReleaseSmall exercises the optimization mode used for the N64 object. A matrix
failure does not cancel the other configuration.

**N64 ROM** runs on Ubuntu 24.04. On an empty cache it copies the official GCC
toolchain out of a Linux x86_64 libdragon container pinned by its immutable
image digest in `scripts/bootstrap-ci-toolchain.sh`. The compiler version is
checked against GCC 16.2.0, matching our libdragon pin. Docker is only used for
this CI bootstrap; Zig, SDK compilation, and game builds run on the host.
Local `mise run setup` can still build the compiler from source without Docker.

The job then builds the pinned libdragon SDK source. Its exact cache key includes
the runner architecture and hashes of `scripts/bootstrap-ci-toolchain.sh` and
`scripts/bootstrap-libdragon.sh`, which contain the compiler and SDK pins. It
does not restore an older SDK when that key changes. The installed SDK is saved
after successful setup, before project builds, so a game compilation failure
does not force another compiler bootstrap. Tiny3D is built from its own pinned
revision on every run; project object files are never restored from a cache.

Downloading the compiler avoids upstream's 40–70 minute source bootstrap on an
empty cache. This job has a 20-minute timeout; later runs reuse the complete
installed SDK. Changing runner distribution or SDK
bootstrap inputs requires a new key. To force a rebuild without a source
change, delete this repository's `n64-sdk-…` cache from GitHub Actions.

`mise run test:rom` starts with `make clean`, then builds:

- One-, two-, three-, and four-player layouts.
- Four-player validation/profiling with the automatic tour.
- The four-player benchmark configuration.

Every variant passes `scripts/verify-rom.sh`: big-endian ROM magic, O64 linked
ELF, no implicit external calls from Zig, and no use of the reserved MIPS global
pointer. The task leaves the normal four-player ROM as the default output.

The `n64-roms-<commit>` artifact contains all six `.z64` variants and
`SHA256SUMS`, retained for 14 days. These checks establish that the game builds
and meets the static ABI contract. They do not boot the ROM or measure FPS.
Visual correctness, input behavior in the emulator, RDPQ runtime validation,
and the 40+ FPS target still use the [ares verification procedure](verification.md).
The recorded performance log is evidence from that run, not a CI benchmark of
future commits.

## Maintenance

- Update Zig and linter pins in `mise.toml`. Run `mise install`, `mise run check`,
  both host test modes, and `mise run test:rom` before accepting a compiler update.
- Update action SHA pins and their version comments together. The shared setup
  action pins mise separately, matching the Lasertag pattern.
- Update SDK and Tiny3D revisions in their bootstrap scripts together after
  checking compatibility. If the SDK's compiler version changes, update the CI
  compiler image digest and version guard as well. Resolve that digest from the
  official `ghcr.io/dragonminded/libdragon` registry; never use a floating tag in
  CI. Either pin change invalidates the SDK cache automatically.
- Run `mise run setup` before `mise run test:rom` locally. The latter rebuilds
  the project's `build/` directory; generated ROMs remain ignored by Git.

The workflows provide six job results: Formatting, Scripts, Workflows,
Zig (Debug), Zig (ReleaseSmall), and N64 ROM. Branch protection is configured
separately in repository settings; these files do not change it.
