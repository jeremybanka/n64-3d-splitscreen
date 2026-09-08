# Integer arena queries and the optional obstacle demo

`make COLLISION_DEMO=1` adds three solid gray/brown boxes to the meadow. Players
slide along their sides and their cameras shorten when a box blocks the view.
`make` restores the original decorative meadow. Trees, rocks, mushrooms and the
carrot remain decorative; collision is not inferred from those meshes.

The generic implementation is `src/collision.zig`. The explicit obstacle layout,
player footprint and camera example live in `src/arena.zig`; the small scene
helper draws those same box extents separately from `environment()`. The C
adapter selects the demo before `scene_init`, through the same one-`uint32_t`
argument/result bridge used by the other configuration calls. Changing that
configuration later requires rebuilding the scene's recorded draw commands.

## Queries and contact

All positions use signed **Q8 integers**: 256 units in the API equal one world
unit. Public queries reject coordinates outside **−32 to +32 world units**, bad
box ordering, and lists longer than **eight obstacles**. No allocation or floating
point is used. Errors are explicit; an out-of-range query is not a silent miss.

| API | Result and behavior |
| --- | --- |
| `overlaps(a, b)` | Closed AABB overlap. Touching a face, edge or point counts. |
| `segment(box, start, end)` | First contact on the finite closed segment, or `null`. Degenerate boxes and zero-length segments are supported. |
| `firstSegment(boxes, start, end)` | Closest hit and obstacle index; equal times prefer the first obstacle in the supplied array. |
| `moveXZ(start, delta, radius, bounds, boxes)` | Legal endpoint, blocked-axis flags and an invalid-start recovery flag. Movement treats the boxes as vertical columns. |

A segment `Hit` contains an exact rational time (`numerator / denominator`), a
Q15 fraction rounded down (`32768` means the endpoint), an axis normal with
components −1/0/+1, and `started_inside`. Slab times are compared as rationals,
so rounding cannot discard a thin obstacle. Simultaneous entry faces prefer X,
then Y, then Z. Computation needs only 32-bit division; cross multiplication uses
64-bit integers within the stated bounds.

A start strictly inside the box reports time zero, `started_inside=true`, and a
zero normal. A start on its boundary also reports zero, with
`started_inside=false`; an inward entry can provide the face normal, while an
outward or tangential start can have a zero normal. A zero-length segment is a
closed point test. Do not interpret a zero normal as a miss.

## Movement and separation

`moveXZ` moves an axis-aligned square footprint. Its half-width/radius may be
zero through one world unit. Each call supports up to **four world units per
horizontal axis**; `delta.y` must be zero and the starting Y is preserved.
`bounds` gives the allowed **center** rectangle in X/Z. Obstacle X/Z dimensions
must be positive; their Y extents do not affect this movement policy.

The call divides movement into at most 32 substeps, each no larger than 1/8
world unit per axis. Each substep sweeps X exactly, then Z exactly, stopping at
the earliest expanded box boundary. It never skips a thin wall along those
swept paths. Positive penetration is forbidden, while boundary contact is legal
and allows sliding and moving away. X-first order is a deliberate deterministic
choice, so diagonal corner response has a small directional bias; this is not a
continuous rigid-body solver.

Invalid spawns/teleports recover to the nearest legal point in a finite grid of
obstacle and world boundary coordinates. Adjacent/overlapping boxes therefore do
not produce an unbounded push-out loop. This exceptional search has at most
19×19 candidate points and eight shape checks per candidate. A completely
blocked center region returns `NoFreePosition`. Recovery is a relocation, not a
swept path; normal movement never invokes it for an already legal start.

The demo uses a 75/256-unit player half-width and center bounds of ±13 units.
Its boxes are four units tall, above the sample's hop height. Jump/gravity rules
remain unchanged, and the columns block horizontal movement even while hopping;
there is no landing on box tops or jumping over them. Tour targets are approached
within the supported movement bound, rather than teleported through an obstacle.

Player separation uses the same sweeps. If a wall prevents one player's half
of the push, the other player absorbs the remainder when space permits. Players
can still crowd together in constrained spaces; static obstacles and world
bounds take precedence. Separation never pushes a participating actor inside a
box. Hidden participants still move and collide, inactive ports stay untouched,
and restarting the world preserves the selected demo/session policy.

## Camera obstruction example

The demo queries from a pivot two units above the player toward the desired eye.
`arena.cameraEye` uses the first segment hit and a 1/8-unit clearance to shorten
that vector. Integration is small:

```zig
const adjusted = arena.cameraEye(pivot, desired_eye) orelse desired_eye;
// Construct the camera looking from adjusted toward pivot.
```

The helper returns `null` for an inside pivot, a time-zero/too-close obstruction,
a zero-length segment, out-of-range inputs, or insufficient horizontal separation.
The scene then retains its original diagonal eye. This fallback avoids a
coincident eye/target or a vertical, degenerate `look_at` basis. It can leave
obstruction unresolved for an invalid/very tight placement; a game may choose
an alternate camera, fade the blocking object, or adjust its pivot instead.
The query is a point segment, not a swept near-plane volume or a complete camera
system. Default-mode camera composition is unchanged.

## Verification and limits

Host tests cover closed touching, parallel/tangential/reversed segments,
inside/boundary/zero-length origins, exact closest-hit ordering, invalid inputs,
one-Q8-unit walls, sliding and moving away, world corners, adjoining boxes,
invalid-start recovery, bounded movement stress, four-player separation,
participant ownership and fixed-step batching. Scene tests check the additional
geometry capacity and nondegenerate camera fallback.

`mise run check`, both host optimization modes, and `mise run test:rom` are the
local/CI checks. The ROM task includes normal and validation collision demos in
addition to the existing six configurations, with the same O64/global-pointer/
unresolved-call verification. The default playable output is restored afterward.

Visual playtesting, collision-demo FPS, and hardware camera feel remain pending:
no new emulator or hardware session was available for this change. Before using
it in a game, walk/hop along every box and the inside L corner with multiple
players, orbit each camera near a box, and check the validation ROM on the target
hardware. Slopes, mesh collision, rigid bodies, dynamic obstacles, top surfaces,
combat shapes and genre-specific physics remain game work.
