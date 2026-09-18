# Bounded template release and fork gate

No release/tag has been published by the template-review work. Implementation
PRs and automated checks can land before hardware evidence exists; sealing the
reference template requires the following bounded acceptance pass against one
final commit and its own ROM hashes. Unchecked rows are still pending.

- [ ] **Clean build:** a fresh checkout installs/verifies the pinned SDK and
  tools, passes `just check`, both host optimization modes, build-dependency
  regressions and every ROM/ABI variant in the final suite. Save the tool/pin
  identities and CI run/artifact links.
- [ ] **Replace content:** export an edited source without overwriting it and
  build both `--content meadow` and `--content robot-courtyard`; verify mesh bounds,
  animation/material tags and both scenes in the emulator. Record the exact
  outputs. Automated asset tests alone do not check their appearance.
- [ ] **Combined workload:** run the final four-player audio + texture +
  collision benchmark (`--audio 1 --textured 1 --collision 1 --benchmark 1`) for
  at least ten minutes in documented NTSC and PAL configurations. Include the
  alternate content in a captured run. Meet the established ≥40 game-FPS
  threshold per benchmark phase, confirm stable emulator speed, and pass the
  performance checker's exact content/audio/texture/collision identity guards.
- [ ] **Command correctness:** run the combined validation ROM separately and
  retain a clean diagnostic log. Its instrumentation overhead is excluded from
  the FPS gate. Walk around all obstacle/material/view boundaries visually.
- [ ] **Base memory:** obtain boot-through-soak memory captures from actual
  4 MiB runtime configurations, including the final combined features and lazy
  sound allocation. Require at least 256 KiB sampled free heap by project policy;
  state the limitation that sampled free space is neither exact peak usage nor
  largest contiguous allocation. Include an actual 4 MiB physical run before
  claiming base-console hardware support.
- [ ] **Physical play/listening:** complete the controller/pause/restart/reconnect
  checklist, listen to overlapping effects/music, and record a 30-minute
  four-player physical run with its console/region/RAM/cart details. Keep
  unsupported regions/configurations explicitly untested.
- [ ] **Reference record:** attach commit, build options, ROM SHA-256 values,
  emulator/physical records and any remaining limitations. Only then choose and
  publish a reference tag/release through a separately authorized action.

Build a final candidate using the exact feature flags and keep its hash next to
its capture. For example:

```sh
just build --content meadow --audio 1 --textured 1 --collision 1 --benchmark 1
shasum -a 256 n64-3d-splitscreen.z64
nu --no-config-file scripts/check-memory.nu path/to/ntsc-capture.log \
  --require-base-memory --tv NTSC --minimum-seconds 600 \
  --content meadow --audio 1 --textured 1 --collision 1
nu --no-config-file scripts/check-performance.nu path/to/ntsc-capture.log \
  --audio on --textured on --collision on --content meadow
```

These flags belong to the final integrated PR chain. The checker validates
captures supplied to it; tests built from synthetic fixture logs are not runtime
evidence. Worktree paths/debug symbols can affect ROM bytes, so use each
capture's actual build hash rather than assuming an archived hash identifies it.
The [hardware record](hardware.md) and [operating envelope](operating-envelope.md)
state what is known and how to gather missing evidence.

## Starting a game fork

- Record the reference commit/tag and retain the SDK/compiler/ABI checks.
- Replace the sample content through the exporter and run bounds/capacity checks.
- Set the game's participation, pause/reset, movement and camera policies;
  preserve physical-port ownership and neutral rearming where applicable.
- Choose the memory/region/performance targets, then rerun the combined workload
  after changing scene complexity, textures, animation, audio or frame storage.
- Preserve frame fences, immutable recorded data and the scalar Zig/C boundary.
  Add game-specific physics, saves, menus and systems when the game needs them.

This gate ends with one documented reference build and measured configurations;
it does not require a general engine, every controller accessory, or unsupported
regions to be implemented before a game fork can begin development.
