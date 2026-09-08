# Audio integration

The sample plays an original eight-second music loop and a short rising chirp
when a player actually starts a hop. Source WAVs and their stdlib Python
generator live in `assets/audio/` and `scripts/make-audio.py`; their musical
content is original and dedicated under CC0. Normal builds need only the ready
WAVs and the pinned libdragon `audioconv64` already included in the SDK.

## Assets and channels

`make` defaults to `AUDIO=1`. It converts the mono 22,050 Hz WAVs to VADPCM WAV64,
packages them into DragonFS, and streams their samples from ROM. `make AUDIO=0`
omits the filesystem and all mixer/AI initialization while keeping the same
simulation and render workload. `make audio-assets` explicitly regenerates the
source WAVs; it is not part of a normal build.

`src/sound.c` owns five channels. Channel 0 loops `meadow.wav64`; channels 1–4
belong permanently to physical players P1–P4 and play `hop.wav64`. Four players
can sound simultaneously. A new effect replaces only that port's previous
voice. Panning is mild and fixed by port, not tied to a viewport or camera;
hidden participants still make sound. The low source peaks and master/channel
attenuation leave headroom for simultaneous effects, but listening validation
is still required before treating the sample mix as final.

To replace content, put new mono PCM WAVs at the same source paths and build.
To add a sound, add its conversion prerequisite in the Makefile, open its WAV64
in `sound_init`, and choose its event bit and channel policy explicitly.
The current music and effect share a 22,050 Hz source/output target; keeping
replacement files at that rate avoids increasing per-channel resampling and
buffer requirements. Check `audio_get_frequency()` diagnostics for the actual
region-adjusted output frequency. The adapter currently uses six AI buffers
and five mixer channels; larger assets stream without loading whole waveforms
into RAM, but additional channels and higher rates cost mixer memory and RSP time.

## Events and lifecycle

`game_audio_events()` returns and clears one `uint32_t`: bits 0–3 request hops
for physical ports 0–3, bits 4–7 request stopping those ports, and bit 8 requests
a music restart. This is the only callable sound seam across Zig/C. It carries
no pointers, floating-point values or aggregate arguments. All libdragon audio
calls remain in C.

Successful hops set sticky per-port bits during simulation. A render frame with
no simulation step does not fabricate a sound. Multiple fixed steps preserve
the pending bits until the adapter drains them once after simulation; duplicate
same-port events coalesce. This intentionally bounded event word is suitable
for the sample's hop cadence, not a queue preserving arbitrary event counts.

World restart drops earlier hop requests, requests all voices stop, and
restarts music. A fresh hop after restart in the same frame still plays because
the adapter processes stop/restart flags before hop flags. Removing a
participant clears only that port's pending hop and requests its voice stop.
Disconnecting a controller does not cancel a hop that already happened.

Pause drops pending hops and stops the four effects. The service loop enqueues
silence without advancing the mixer, preserving music's sample position for
resume. Already queued sound must drain before silence arrives; pause, reset,
and participant removal therefore have up to roughly the configured audio
queue duration of audible latency. The startup log exposes buffer size, count
and actual frequency so that duration can be calculated. The AI is not closed
or reinitialized during these transitions. Resuming waits for the lifecycle
input rearming policy before fresh player actions can trigger new sounds.

## Service and diagnostics

The main loop calls `sound_service` around gameplay/render submission and
between viewports. Supported nonblocking `display_try_get` and
`rspq_syncpoint_check` waits keep service running while display buffers or
frame slots are unavailable; fence polling first flushes the RSP queue.
The mixer never runs from a controller, AI or other interrupt callback.

Each service call fills available AI buffers via `audio_write_begin`,
`mixer_poll`, and `audio_write_end`, with a six-buffer work cap. `mixer_poll`
uses the RSP and can wait for it; that cost belongs in the graphics/audio
budget. Paused service uses `audio_write_silence`. This cooperative path still
needs runtime validation under long render or asset stalls; it cannot make
arbitrary blocking game code safe for sound.

PERF samples include:

| Field | Meaning |
| --- | --- |
| `audio` | 1 enabled, 0 disabled |
| `audio_us` | Mean audio production time per rendered frame in this reporting interval, including mixer waits |
| `audio_buffers` | Produced output buffers in the interval |
| `audio_gap_us` | Maximum time between service entries in the interval |
| `audio_budget_us` | Conservative gap guard: four buffers, reserving two of the six for hardware/in-flight work |
| `audio_sfx` | Per-player effect starts in the interval |
| `audio_overlap` | Maximum simultaneously scheduled/playing effect channels observed after event handling |
| `workload` | 2 identifies this benchmark's simultaneous-hop phase |

The service-gap guard is a diagnostic proxy, **not an AI underrun counter or
proof of glitch-free playback**. Listen for gaps/clicks and inspect runtime
assertions as well as numerical acceptance.

## Benchmark comparison

1. Build `make BENCHMARK=1 AUDIO=1`, run on the chosen emulator or hardware, and
   capture ISViewer/USB PERF output for at least a complete 60-second cycle;
   two cycles give additional samples away from startup/phase boundaries.
2. Check `python3 scripts/check-performance.py audio-on.log --audio on`.
   The default requires at least 15 samples per phase at 40+ FPS, output
   buffers in every sample, service gaps within the guard, and evidence of
   four simultaneous effects in the close-quarters phase.
3. Build `make BENCHMARK=1 AUDIO=0` and repeat with the same platform/configuration.
   Check `python3 scripts/check-performance.py audio-off.log --audio off`.
   Compare FPS and CPU/mixer costs phase by phase; keep the two captures separate.
4. Listen through the loop boundary and all three phases. In the ordinary ROM,
   test simultaneous player hops, pause/release/resume, reset while paused, and
   participation removal. Record actual platform, ROM hashes, observations and
   any measured glitches in `docs/verification.md`.

Workload 2 makes close-quarters hops simultaneous. Both audio modes execute that
identical workload; historical pre-audio captures used workload 1. The checker
labels untagged logs as historical and rejects mixed audio modes/workloads in
one capture. `--audio legacy` explicitly selects old captures. Never report the
old graphics-only FPS range as a measured audio-enabled result.

Automated coverage includes 25 Zig tests per content pack in Debug/ReleaseSmall,
eight mesh-validation tests, original WAV verification, five benchmark-parser
tests, and nine ROM/ABI variants (four layouts, validation, both benchmark audio
modes, and two alternate-content builds). Listening, actual buffer
starvation and combined performance observations remain pending.
