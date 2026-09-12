# Multiplayer lifecycle

Controller connections, participating players, and visible cameras are separate
policies. Physical port 0 always owns P1; port 3 always owns P4. Disconnecting a
controller clears its input but keeps its rabbit in the world. The default
sample has all four participants and all four cameras, even with no controllers.
An `OFF` label identifies a visible player's disconnected controller.

## Small session interface

Every mask uses its low four bits for physical ports, with bit 0 representing P1.
Upper bits are ignored. These functions retain the audited scalar ABI: at most
one `uint32_t` argument and one `uint32_t` result.

| Function | Behavior |
| --- | --- |
| `game_connections(mask)` | Set the adapter's latest connection snapshot; return its sanitized mask. Does not join players or choose cameras. |
| `game_participants(mask)` | Set participants and return their mask. Removed players stop simulating, colliding and rendering; their pose/velocity is retained for reactivation. Clear input on every changed port. Remove inactive players' visible views. |
| `game_views(mask)` | Select visible participants; return `mask & participants & 15`. Does not change anyone's input or simulation. |
| `game_view_port(slot)` | Map a compact viewport slot to a physical port in ascending order; return 4 for an invalid slot. |
| `game_pause(value)` | Zero resumes, nonzero pauses. Return 0/1. Each change clears all inputs; repeated calls with the same state have no additional effect. |
| `game_command(GAME_RESTART)` | Reset world positions, velocities, animation, simulation ticks and tour; preserve connections, participation, cameras and paused state. Clear all inputs. |
| `game_reset(0)` | Cold boot: restart the world, unpause, restore four participants/views, clear connection state and restart the benchmark clock. |
| `game_status()` | Pack view count in bits 0–7, tour in bit 8, pause in bit 9, connections in bits 12–15, participants in bits 16–19, and visible ports in bits 20–23. |

For a game using only controllers in ports 2 and 4:

```c
game_participants(0xA); // P2 and P4 stay owned by physical ports 1 and 3.
game_views(0xA);        // Slots 0/1 show P2/P4 with matching labels and colors.
game_views(0x8);        // Show P4 full-screen; P2 still simulates and collides.
game_pause(1);
game_command(GAME_RESTART); // Restart while retaining the paused session policy.
game_pause(0);
```

A zero participant mask is valid: no player simulates or renders. A zero view
mask is also valid: the adapter clears the screen and draws the HUD without
requesting a viewport or camera. Adding a participant does not automatically add
its camera. Choose a view mask explicitly after changing participation.

The sample's Start command cycles through the first 1, 2, … N participating
ports in ascending order, with no effect when there are no participants. Custom
view masks can select any subset but do not provide an arbitrary camera order.
Zig gameplay can query `isParticipant(port)`, `paused`, and the masks; use the
setter functions for changes so input cleanup and view invariants stay intact.

## Input transitions

After `joypad_poll`, the C adapter submits connection state before the four
controller samples. The packed input word contains signed X/Y bytes in bits
0–15, A press in bit 16, look-left/right held in bits 17/18, B press in bit 19,
A/B held in bits 20/21, any sample command held in bit 22, and port in bits 30/31.
The extra held indicators are required even though hop and recenter use edges.

Connection changes, participation changes, restart, and pause/resume discard
pending presses and held movement for the affected ports. Before that port can
control gameplay or issue sample commands again, it must submit **one neutral
poll**: both axes within the existing dead zone, no held gameplay or command
buttons, and no action edges. That poll only rearms input; later polls act
normally. Release all controls after boot, reconnect, restart or pause/resume.
This includes C-up after pausing so the next C-up press can resume.

`game_input(word)` returns 0 while disconnected or rearming, and 1 when sample
commands may be handled. The adapter only acts on P1's command edges after a 1
result, which prevents reconnects from fabricating Start, Z, reset or pause.
Commands remain available while paused and even when P1 is not a participant.
Gameplay input is discarded while paused or inactive. Ordinary hop/recenter
presses still survive render frames with no simulation update and are consumed
only once across multiple fixed steps.

Pause freezes simulation ticks, player motion and camera/animation state while
input polling and presentation continue. The existing bounded 60 Hz accumulator
consumes each frame's elapsed time even while paused, so resuming has no queued
simulation backlog. Disconnecting does not pause gravity, separation or the
automatic tour; a game can choose to call `game_pause(1)` on a connection change.

## Sample controls and verification

P1 C-up toggles pause; P1 C-down restarts. Start still cycles views, Z toggles
the tour, A hops, B recenters, and C-left/right or L/R orbit the camera.

Host tests cover disconnect/reconnect with pending presses and held controls,
neutral rearming, pause/resume/restart, noncontiguous port ownership and camera
mapping, inactive collision/simulation, hidden participants, and empty masks.
The deterministic benchmark bypasses hardware input and restores its four-player
policy so absent controllers or an earlier paused session cannot change its
workload. The C adapter skips controller commands in benchmark builds.

The transition suite and all ROM/ABI variants can be run using `just test`,
`just test ReleaseSmall`, and `just test-rom`. Hardware controller
hot-plug and pause/resume still need an interactive hardware check; host tests
exercise the state machine, not the electrical controller connection.
