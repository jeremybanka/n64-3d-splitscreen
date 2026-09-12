# Hardware and region verification record

Record updated 2026-09-08. The owner reports: **“It runs well on actual hardware!”**
This is a successful qualitative run. The following details were not supplied;
none are inferred from attached tools, existing SDKs or emulator captures.

| Owner-run field | Recorded value |
| --- | --- |
| Console/model/revision | Unknown |
| PAL, NTSC or M-PAL region | Unknown |
| RAM/Jumper Pak/Expansion Pak | Unknown |
| Flash cart and firmware | Unknown |
| Controllers, physical ports and view layouts tested | Unknown |
| Commit, ROM SHA-256 and build options | Unknown |
| Run date and duration | Unknown |
| Measured FPS, audio/listening and memory logs | Unknown |

That report applies to the template before this review's feature work. It does
not verify the final combined PR revision. The earlier numerical **51–60 FPS,
115-sample** record is from ares with the pre-audio, untextured benchmark.
The [verification history](verification.md) also records the 2026-09-08
unchanged-main smoke observation. No new feature GUI/listening/PAL/NTSC or
physical test has been performed while the Mac is locked.

## Record for each new session

Copy this section into a dated capture directory or append a completed record.
Keep all unperformed rows marked pending.

- Test operator, date, and physical hardware or emulator/version: **pending**
- Console revision, region, RAM/Pak and cart/firmware: **pending**
- Commit, dirty/clean status, tool pins and exact build options: **pending**
- ROM filename and SHA-256; capture filename/hash: **pending**
- Boot `CONFIG`, `CAPACITY` and `MEMORY` records, including actual `ram`/`tv`: **pending**
- Run duration, min/max game FPS and sampled heap-free minimum: **pending**
- Audio listening result, simultaneous effects and any glitches: **pending**
- Controller models/ports, display/capture setup and observed failures: **pending**

| Physical/controller check | Result |
| --- | --- |
| P1 only, single view; movement/hop/orbit/recenter | Pending |
| P1/P2, horizontal halves; independent ownership | Pending |
| P1/P2/P3, asymmetric layout; independent ownership | Pending |
| Four physical controllers, quadrants; simultaneous movement/hopping | Pending |
| Cycle all layouts; hidden participants retain ownership/state | Pending |
| Disconnect/reconnect each port, including a held stick/button; neutral rearming | Pending |
| Pause/resume and restart with pending/held inputs; no stale jumps/commands | Pending |
| Noncontiguous/empty participant/view masks in a diagnostic fork or host/API checks | Pending physical coverage |
| Collision walls/L corner and camera orbit; textured ground in every view | Pending |
| Music loop and overlapping effects from all ports; pause/restart audio | Pending |
| At least 30 minutes with four views/controllers; no crashes, leaks, dropouts or corruption | Pending |

## Repeatable NTSC and PAL procedure

1. Build one exact final candidate and save its options and SHA-256 before
   running it. Use `just check`, both host modes, `just test-rom`, and
   the exact combined-feature benchmark/validation options in the release gate.
   A `REGIONFREE` ROM header establishes boot eligibility, not timing/display
   correctness in each region.
2. Start one **fresh** emulator session explicitly configured for NTSC and
   **4 MiB**, or boot a documented NTSC console with a Jumper Pak. Record the
   emulator setting or physical configuration, then confirm the boot log reports
   `tv=NTSC ram=4194304 expanded=0`. Do not relabel an 8 MiB capture.
3. Capture ISViewer from before boot (ares Tools → Tracer → Log to File), or
   save the SummerCart64 debug output using `just debug`. Preserve raw
   `CONFIG`, `CAPACITY`, `MEMORY` and `PERF` lines. Record the ROM hash alongside
   the log; this code does not embed a self-hash. Avoid debugger pauses and
   unrelated host load during performance measurements.
4. Run the three benchmark phases for at least ten minutes, then run the
   separate command-validation build. Check the memory log with
   `--require-base-memory --tv NTSC --minimum-seconds 600` and the exact
   content/audio/material/collision flags. Check FPS/audio service with the
   performance checker. Validation FPS is not a performance gate.
5. Repeat from a fresh session explicitly configured for **PAL 4 MiB** (or a
   documented PAL Jumper Pak console), requiring `tv=PAL`. Check full framing,
   readable HUD/separators, stable motion and audio pitch/tempo. The simulation
   uses elapsed time at 60 Hz; PAL video can present at a different refresh rate.
   Verify equal gameplay timing over a measured wall-clock interval instead of
   expecting PAL and NTSC FPS numbers to be identical. Record emulator speed
   separately from the game's emulated-clock FPS counter.
6. Run the physical/controller checklist and the 30-minute four-player soak.
   Do not substitute synthetic benchmark inputs for real controller coverage.
   Log any Expansion Pak run separately. M-PAL remains untested until recorded
   independently; passing NTSC/PAL does not automatically certify it.

The NTSC/PAL, base-memory, listening, controller and final-FPS rows remain pending
until those captures and observations exist. Capture/check commands are a
procedure, not evidence that the procedure has already been run.
