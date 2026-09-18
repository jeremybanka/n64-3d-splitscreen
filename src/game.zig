//! Shared world and controller simulation. All runtime math is integer Q8 so
//! LLVM's N32 floating-point convention never crosses the libdragon O64 seam.
const std = @import("std");
pub const Q: i32 = 256;
pub const arena = @import("arena.zig");
pub const Vec3 = @import("collision.zig").Vec3;
pub var collision_demo = false;
pub const colors = [4]u32{ 0xef8965ff, 0x7ab8e8ff, 0xeac762ff, 0xb29adfff };
pub const sine = blk: {
    var table: [256]i32 = undefined;
    for (&table, 0..) |*v, i| v.* = @intFromFloat(@sin(@as(f64, @floatFromInt(i)) * 2 * std.math.pi / 256) * Q);
    break :blk table;
};
pub fn sin(a: i32) i32 {
    return sine[@intCast(@mod(a, 256))];
}
pub fn cos(a: i32) i32 {
    return sin(a + 64);
}
pub fn mul(a: i32, b: i32) i32 {
    return @intCast((@as(i64, a) * b) >> 8);
}
pub const Player = struct {
    pos: Vec3 = .{},
    yaw: i32 = 0,
    camera: i32 = 0,
    velocity_y: i32 = 0,
    walk: i32 = 0,
    moving: bool = false,
    input: u32 = 0,
};
pub var players: [4]Player = .{Player{}} ** 4;
// Masks always use physical ports: bit 0 is P1, bit 3 is P4.
pub var connected_mask: u32 = 0;
pub var participant_mask: u32 = 15;
pub var visible_mask: u32 = 15;
pub var view_count: u32 = 4;
pub var paused = false;
const edge_mask: u32 = (1 << 16) | (1 << 19);
const held_mask: u32 = (1 << 17) | (1 << 18) | (1 << 20) | (1 << 21) | (1 << 22);
var input_ready = [_]bool{false} ** 4;
// Audio events: hop bits 0..3, stop-player bits 4..7, music restart bit 8.
// Sticky until drained, so catch-up steps cannot lose an event.
var audio_events: u32 = 0;
pub export fn game_audio_events() u32 {
    const events = audio_events;
    audio_events = 0;
    return events;
}

pub fn isParticipant(port: usize) bool {
    return participant_mask & (@as(u32, 1) << @intCast(port)) != 0;
}
fn clearInput(port: usize) void {
    players[port].input = 0;
    input_ready[port] = false;
}
fn clearInputs() void {
    for (0..4) |port| clearInput(port);
}
pub var ticks: u32 = 0;
pub var tour = false;

pub fn reset() void {
    audio_events = 0x1f0; // Drop previous hops, stop all effects, restart music.
    ticks = 0;
    tour = false;
    for (&players, 0..) |*p, i| {
        const a: i32 = @as(i32, @intCast(i)) * 64 + 32;
        p.* = .{ .pos = .{ .x = mul(sin(a), 3 * Q), .z = mul(cos(a), 3 * Q) }, .yaw = a + 128, .camera = a + 128 };
    }
    clearInputs();
}
fn axis(word: u32, shift: u5) i32 {
    const v: i8 = @bitCast(@as(u8, @truncate(word >> shift)));
    return if (@abs(@as(i32, v)) < 12) 0 else v;
}
pub fn step() void {
    if (paused) return;
    ticks +%= 1;
    for (&players, 0..) |*p, i| {
        if (!isParticipant(i)) continue;
        if (collision_demo) p.pos = arena.move(p.pos, 0, 0);
        const x = axis(p.input, 0);
        const y = axis(p.input, 8);
        if (p.input & (1 << 17) != 0) p.camera -= 2;
        if (p.input & (1 << 18) != 0) p.camera += 2;
        p.camera = @mod(p.camera, 256);
        if (p.input & (1 << 19) != 0) p.camera = p.yaw;
        p.moving = x != 0 or y != 0;
        if (tour and !p.moving) {
            const a: i32 = @intCast((ticks / 4 + i * 64 + 32) % 256);
            const target_x = mul(sin(a), 3 * Q);
            const target_z = mul(cos(a), 3 * Q);
            if (collision_demo) {
                p.pos = arena.move(p.pos, target_x - p.pos.x, target_z - p.pos.z);
            } else {
                p.pos.x = target_x;
                p.pos.z = target_z;
            }
            p.yaw = a + 128;
            p.camera = p.yaw;
            p.moving = true;
        } else if (p.moving) {
            // Normalize the stick's square corners without a runtime sqrt.
            const magnitude = @max(@abs(x), @abs(y)) + @min(@abs(x), @abs(y)) / 2;
            const scale: i32 = @intCast(@max(magnitude, 80));
            const dx = @divTrunc((mul(x, cos(p.camera)) + mul(y, sin(p.camera))) * 22, scale);
            const dz = @divTrunc((-mul(x, sin(p.camera)) + mul(y, cos(p.camera))) * 22, scale);
            movePlayer(p, dx, dz);
            // Quantized facing is appropriate for the deliberately low-poly model.
            var best_dot: i32 = -0x7fffffff;
            var a: i32 = 0;
            while (a < 256) : (a += 8) {
                const dot = dx * sin(a) + dz * cos(a);
                if (dot > best_dot) {
                    best_dot = dot;
                    p.yaw = a;
                }
            }
        }
        if (p.moving) p.walk = @mod(p.walk + 9, 256);
        if ((p.input & (1 << 16) != 0 or (tour and ticks % 300 == i * 60)) and p.pos.y == 0) {
            p.velocity_y = 57;
            audio_events |= @as(u32, 1) << @intCast(i);
        }
        // Jump is edge-triggered, even if a frame contains multiple simulation steps.
        p.input &= ~@as(u32, (1 << 16) | (1 << 19));
        p.pos.y += p.velocity_y;
        p.velocity_y -= 3;
        if (p.pos.y <= 0) {
            p.pos.y = 0;
            p.velocity_y = 0;
        }
    }
    // Hidden participants remain in the world; inactive ports do not collide.
    for (0..4) |i| for (i + 1..4) |j| {
        if (!isParticipant(i) or !isParticipant(j)) continue;
        const dx = players[j].pos.x - players[i].pos.x;
        const dz = players[j].pos.z - players[i].pos.z;
        const d = @max(@abs(dx), @abs(dz));
        if (d < 150 and @abs(players[i].pos.y - players[j].pos.y) < Q) {
            const push: i32 = @intCast((150 - d) / 2 + 1);
            if (@abs(dx) >= @abs(dz)) {
                const s: i32 = if (dx >= 0) 1 else -1;
                separate(i, j, push, s, true);
            } else {
                const s: i32 = if (dz >= 0) 1 else -1;
                separate(i, j, push, s, false);
            }
        }
    };
    for (&players, 0..) |*p, i| {
        if (!isParticipant(i)) continue;
        p.pos.x = std.math.clamp(p.pos.x, -13 * Q, 13 * Q);
        p.pos.z = std.math.clamp(p.pos.z, -13 * Q, 13 * Q);
    }
}
fn movePlayer(p: *Player, dx: i32, dz: i32) void {
    if (collision_demo) {
        p.pos = arena.move(p.pos, dx, dz);
    } else {
        p.pos.x = std.math.clamp(p.pos.x + dx, -13 * Q, 13 * Q);
        p.pos.z = std.math.clamp(p.pos.z + dz, -13 * Q, 13 * Q);
    }
}
fn separate(i: usize, j: usize, push: i32, sign: i32, comptime x_axis: bool) void {
    if (!collision_demo) {
        if (x_axis) {
            players[i].pos.x -= push * sign;
            players[j].pos.x += push * sign;
        } else {
            players[i].pos.z -= push * sign;
            players[j].pos.z += push * sign;
        }
        return;
    }
    const old_i = if (x_axis) players[i].pos.x else players[i].pos.z;
    const old_j = if (x_axis) players[j].pos.x else players[j].pos.z;
    movePlayer(&players[i], if (x_axis) -push * sign else 0, if (x_axis) 0 else -push * sign);
    movePlayer(&players[j], if (x_axis) push * sign else 0, if (x_axis) 0 else push * sign);
    const moved_i = (old_i - (if (x_axis) players[i].pos.x else players[i].pos.z)) * sign;
    const moved_j = ((if (x_axis) players[j].pos.x else players[j].pos.z) - old_j) * sign;
    // A wall may prevent one half of separation. Let the other actor absorb
    // the remainder, with the same sweeps; never push an actor into a wall.
    var remainder = 2 * push - moved_i - moved_j;
    const before_j = if (x_axis) players[j].pos.x else players[j].pos.z;
    movePlayer(&players[j], if (x_axis) remainder * sign else 0, if (x_axis) 0 else remainder * sign);
    remainder -= ((if (x_axis) players[j].pos.x else players[j].pos.z) - before_j) * sign;
    movePlayer(&players[i], if (x_axis) -remainder * sign else 0, if (x_axis) 0 else -remainder * sign);
}
// Configure before scene_init; changing demo geometry requires rebuilding it.
pub export fn game_collision_demo(value: u32) u32 {
    collision_demo = value != 0;
    reset();
    return @intFromBool(collision_demo);
}
// Cold boot restores the demonstration policy. reset()/command 3 restart the
// world while retaining connections, participants, visible views and pause.
pub export fn game_reset(_: u32) u32 {
    collision_demo = false;
    connected_mask = 0;
    participant_mask = 15;
    visible_mask = 15;
    view_count = 4;
    paused = false;
    reset();
    benchmark_ticks = 0;
    return 0;
}
pub export fn game_connections(mask: u32) u32 {
    const next = mask & 15;
    const changed = next ^ connected_mask;
    connected_mask = next;
    for (0..4) |port| {
        if (changed & (@as(u32, 1) << @intCast(port)) != 0) clearInput(port);
    }
    return connected_mask;
}
pub export fn game_participants(mask: u32) u32 {
    const next = mask & 15;
    const changed = next ^ participant_mask;
    const removed = participant_mask & ~next;
    audio_events = (audio_events & ~removed) | (removed << 4);
    participant_mask = next;
    for (0..4) |port| {
        if (changed & (@as(u32, 1) << @intCast(port)) != 0) clearInput(port);
    }
    _ = game_views(visible_mask);
    return participant_mask;
}
pub export fn game_views(mask: u32) u32 {
    visible_mask = mask & participant_mask & 15;
    view_count = @popCount(visible_mask);
    return visible_mask;
}
pub export fn game_view_port(slot: u32) u32 {
    var found: u32 = 0;
    for (0..4) |port| {
        if (visible_mask & (@as(u32, 1) << @intCast(port)) == 0) continue;
        if (found == slot) return @intCast(port);
        found += 1;
    }
    return 4; // Invalid slot, including every slot when no views are selected.
}
pub export fn game_pause(value: u32) u32 {
    const next = value != 0;
    if (next != paused) {
        paused = next;
        if (paused) audio_events = (audio_events & ~@as(u32, 15)) | 0xf0;
        clearInputs();
    }
    return @intFromBool(paused);
}
pub export fn game_input(word: u32) u32 {
    const port = word >> 30;
    const p = &players[port];
    if (connected_mask & (@as(u32, 1) << @intCast(port)) == 0) return 0;
    // Transitions require one neutral sample. Include held action and sample
    // command buttons so reconnecting a held button cannot fabricate an edge.
    if (!input_ready[port]) {
        if (axis(word, 0) == 0 and axis(word, 8) == 0 and word & (held_mask | edge_mask) == 0)
            input_ready[port] = true;
        return 0;
    }
    if (isParticipant(port) and !paused)
        p.input = (word & 0xfffff) | (p.input & edge_mask);
    // Command handling stays available while paused or outside participation.
    return 1;
}
export fn game_tick(count: u32) u32 {
    for (0..@min(count, 15)) |_| step();
    return 0;
}
export fn game_command(command: u32) u32 {
    switch (command) {
        1 => {
            const active: u32 = @popCount(participant_mask);
            if (active != 0) {
                const wanted = view_count % active + 1;
                var mask: u32 = 0;
                for (0..4) |port| {
                    if (!isParticipant(port)) continue;
                    mask |= @as(u32, 1) << @intCast(port);
                    if (@popCount(mask) == wanted) break;
                }
                _ = game_views(mask);
            }
        },
        2 => tour = !tour,
        3 => reset(),
        4 => _ = game_pause(@intFromBool(!paused)),
        else => {},
    }
    return view_count;
}
export fn game_status() u32 {
    return view_count | (@as(u32, @intFromBool(tour)) << 8) |
        (@as(u32, @intFromBool(paused)) << 9) | (connected_mask << 12) |
        (participant_mask << 16) | (visible_mask << 20);
}

fn resetConnectedTest() void {
    _ = game_reset(0);
    _ = game_connections(15);
    for (0..4) |port| _ = game_input(@as(u32, @intCast(port)) << 30);
}

test "all view counts preserve a single shared world" {
    resetConnectedTest();
    const before = players;
    for (1..5) |n| {
        _ = game_command(1);
        try std.testing.expectEqual(@as(u32, @intCast(n)), view_count);
    }
    try std.testing.expectEqualDeep(before, players);
}
test "packed controller input moves only the addressed rabbit" {
    resetConnectedTest();
    const before = players;
    _ = game_input((2 << 30) | (80 << 8));
    step();
    try std.testing.expect(players[2].pos.x != before[2].pos.x);
    try std.testing.expectEqualDeep(before[0].pos, players[0].pos);
    try std.testing.expectEqualDeep(before[1].pos, players[1].pos);
    try std.testing.expectEqualDeep(before[3].pos, players[3].pos);
}
test "jump lands and does not repeat without another press" {
    resetConnectedTest();
    _ = game_input(1 << 16);
    step();
    try std.testing.expect(players[0].pos.y > 0);
    for (0..80) |_| step();
    try std.testing.expectEqual(@as(i32, 0), players[0].pos.y);
}
test "world bounds and overlapping players remain bounded" {
    resetConnectedTest();
    _ = game_input(80 << 8);
    for (0..2000) |_| step();
    try std.testing.expect(@abs(players[0].pos.x) <= 13 * Q);
    try std.testing.expect(@abs(players[0].pos.z) <= 13 * Q);
    players[1].pos = players[0].pos;
    step();
    try std.testing.expect(!std.meta.eql(players[0].pos, players[1].pos));
    for (players) |p| {
        try std.testing.expect(@abs(p.pos.x) <= 13 * Q and @abs(p.pos.z) <= 13 * Q);
    }
}

test "jump press survives a render frame with no simulation step" {
    resetConnectedTest();
    _ = game_input(1 << 16);
    _ = game_tick(0);
    _ = game_input(0);
    step();
    try std.testing.expect(players[0].pos.y > 0);
}

// Deterministic four-controller workload for emulator performance checks.
// Three 20-second phases: shared tour, independent movement/orbit, close quarters.
var benchmark_ticks: u32 = 0;
pub export fn game_benchmark(count: u32) u32 {
    // Synthetic workload owns simulation policy and bypasses physical input
    // gating; absent controllers must not change performance measurements.
    paused = false;
    participant_mask = 15;
    _ = game_views(15);
    for (0..@min(count, 15)) |_| {
        const phase = (benchmark_ticks / 1200) % 3;
        if (benchmark_ticks % 1200 == 0) {
            reset();
            view_count = 4;
            if (phase == 2) for (&players) |*p| {
                p.pos.x = @divTrunc(p.pos.x, 3);
                p.pos.z = @divTrunc(p.pos.z, 3);
            };
        }
        tour = phase == 0;
        for (0..4) |i| {
            const time = benchmark_ticks % 1200;
            var word: u32 = @as(u32, @intCast(i)) << 30;
            if (phase == 1) {
                // All ports move and turn independently, including at world bounds.
                const x: i8 = if ((time / 300 + i) % 2 == 0) 55 else -55;
                word |= @as(u8, @bitCast(x));
                word |= 80 << 8;
                word |= @as(u32, 1) << (if (i % 2 == 0) @as(u5, 17) else 18);
            } else if (phase == 2) {
                word |= 1 << 18;
            }
            // Workload 2 adds simultaneous four-port hops in close quarters.
            // AUDIO=0/1 execute this identical graphics/gameplay workload.
            if (time % 120 == (if (phase == 2) 0 else i * 20)) word |= 1 << 16;
            players[i].input = word & 0xfffff;
        }
        step();
        benchmark_ticks +%= 1;
    }
    return (benchmark_ticks / 1200) % 3;
}

test "recenter press survives a frame with no simulation step" {
    resetConnectedTest();
    players[0].camera = 0;
    players[0].yaw = 80;
    _ = game_input(1 << 19);
    _ = game_tick(0);
    _ = game_input(0);
    step();
    try std.testing.expectEqual(@as(i32, 80), players[0].camera);
}

test "disconnect discards pending edges and reconnect requires neutral input" {
    resetConnectedTest();
    const before = players;
    const held: u32 = (80 << 8) | (1 << 16) | (1 << 17) | (1 << 19) | (1 << 20) | (1 << 21);
    _ = game_input(held);
    _ = game_tick(0);
    _ = game_connections(14);
    try std.testing.expectEqual(@as(u32, 0), game_input(held));
    step();
    try std.testing.expectEqualDeep(before[0].pos, players[0].pos);
    try std.testing.expectEqual(before[0].camera, players[0].camera);
    try std.testing.expectEqual(@as(u32, 15), participant_mask);
    try std.testing.expectEqual(@as(u32, 15), visible_mask);
    _ = game_connections(15);
    for (0..80) |_| {
        try std.testing.expectEqual(@as(u32, 0), game_input(held));
        step();
    }
    try std.testing.expectEqualDeep(before[0].pos, players[0].pos);
    try std.testing.expectEqual(@as(u32, 0), game_input(0));
    try std.testing.expectEqual(@as(u32, 1), game_input(held));
    step();
    try std.testing.expect(players[0].pos.y > 0);
    try std.testing.expect(players[0].pos.x != before[0].pos.x);
    for (1..4) |port| try std.testing.expectEqualDeep(before[port].pos, players[port].pos);
}

test "pause freezes ticks and discards both pending and held input on resume" {
    resetConnectedTest();
    _ = game_input((80 << 8) | (1 << 16));
    _ = game_tick(0);
    _ = game_pause(1);
    const before = players;
    const time = ticks;
    _ = game_tick(15);
    try std.testing.expectEqualDeep(before, players);
    try std.testing.expectEqual(time, ticks);
    _ = game_input(0);
    // The adapter must still be able to issue an unpause command.
    try std.testing.expectEqual(@as(u32, 1), game_input(1 << 22));
    try std.testing.expectEqual(@as(u32, 0), players[0].input);
    _ = game_pause(0);
    try std.testing.expectEqual(@as(u32, 0), game_input((80 << 8) | (1 << 20)));
    step();
    try std.testing.expectEqualDeep(before[0].pos, players[0].pos);
    _ = game_input(0);
    _ = game_input((80 << 8) | (1 << 16) | (1 << 20));
    step();
    try std.testing.expect(players[0].pos.y > 0);
}

test "world restart preserves session policy and requires fresh input" {
    resetConnectedTest();
    _ = game_participants(10);
    _ = game_views(8);
    _ = game_input(3 << 30);
    _ = game_input((3 << 30) | (80 << 8) | (1 << 16));
    step();
    _ = game_pause(1);
    _ = game_command(3);
    try std.testing.expectEqual(@as(u32, 0), ticks);
    try std.testing.expectEqual(@as(i32, 0), players[3].pos.y);
    try std.testing.expectEqual(@as(u32, 15), connected_mask);
    try std.testing.expectEqual(@as(u32, 10), participant_mask);
    try std.testing.expectEqual(@as(u32, 8), visible_mask);
    try std.testing.expect(paused);
    _ = game_pause(0);
    try std.testing.expectEqual(@as(u32, 0), game_input((3 << 30) | (80 << 8) | (1 << 16) | (1 << 20)));
    step();
    try std.testing.expectEqual(@as(i32, 0), players[3].pos.y);
    _ = game_input(3 << 30);
    _ = game_input((3 << 30) | (1 << 16) | (1 << 20));
    step();
    try std.testing.expect(players[3].pos.y > 0);
}

test "noncontiguous participants retain ownership and hidden players simulate" {
    resetConnectedTest();
    _ = game_participants(10);
    try std.testing.expectEqual(@as(u32, 1), game_view_port(0));
    try std.testing.expectEqual(@as(u32, 3), game_view_port(1));
    try std.testing.expectEqual(@as(u32, 4), game_view_port(2));
    _ = game_views(8);
    players[0].pos = players[1].pos; // An inactive player must not separate P2.
    const before = players;
    _ = game_input(80 << 8); // P1 stays inactive even though it is connected.
    _ = game_input((1 << 30) | (80 << 8));
    step();
    try std.testing.expectEqualDeep(before[0].pos, players[0].pos);
    try std.testing.expect(players[1].pos.x != before[1].pos.x);
    try std.testing.expectEqualDeep(before[3].pos, players[3].pos);
    try std.testing.expectEqual(@as(u32, 3), game_view_port(0));
    // Deactivation drops a pending jump and reactivation drops the held stick.
    _ = game_input((1 << 30) | (1 << 16));
    _ = game_participants(8);
    const frozen = players[1];
    _ = game_tick(15);
    try std.testing.expectEqualDeep(frozen, players[1]);
    _ = game_participants(10);
    try std.testing.expectEqual(@as(u32, 0), game_input((1 << 30) | (80 << 8) | (1 << 20)));
    step();
    try std.testing.expectEqualDeep(frozen.pos, players[1].pos);
    try std.testing.expectEqual(@as(u32, 8), visible_mask);
}

test "empty masks and view cycling keep safe explicit mappings" {
    resetConnectedTest();
    _ = game_participants(10);
    try std.testing.expectEqual(@as(u32, 1), game_command(1));
    try std.testing.expectEqual(@as(u32, 2), visible_mask);
    try std.testing.expectEqual(@as(u32, 2), game_command(1));
    try std.testing.expectEqual(@as(u32, 10), visible_mask);
    _ = game_participants(0);
    const before = players;
    try std.testing.expectEqual(@as(u32, 0), game_command(1));
    try std.testing.expectEqual(@as(u32, 4), game_view_port(0));
    _ = game_tick(15);
    try std.testing.expectEqualDeep(before, players);
    _ = game_participants(0xffff);
    try std.testing.expectEqual(@as(u32, 0), visible_mask);
    try std.testing.expectEqual(@as(u32, 15), game_views(0xffff));
    _ = game_connections(0);
    _ = game_pause(1);
    const status = game_status();
    try std.testing.expectEqual(@as(u32, 4), status & 255);
    try std.testing.expect(status & (1 << 9) != 0);
    try std.testing.expectEqual(@as(u32, 0), (status >> 12) & 15);
    try std.testing.expectEqual(@as(u32, 15), (status >> 16) & 15);
    try std.testing.expectEqual(@as(u32, 15), (status >> 20) & 15);
}

test "sample command holds cannot become reconnect or restart presses" {
    _ = game_reset(0);
    _ = game_connections(1);
    for (0..3) |_| try std.testing.expectEqual(@as(u32, 0), game_input(1 << 22));
    try std.testing.expectEqual(@as(u32, 0), game_input(0));
    try std.testing.expectEqual(@as(u32, 1), game_input(1 << 22));
    _ = game_command(3);
    try std.testing.expectEqual(@as(u32, 0), game_input(1 << 22));
}

test "benchmark does not depend on connected controllers or session policy" {
    resetConnectedTest();
    for (0..85) |_| _ = game_benchmark(15);
    const before = players;
    const time = ticks;
    _ = game_reset(0);
    _ = game_participants(2);
    _ = game_views(0);
    _ = game_pause(1);
    for (0..85) |_| _ = game_benchmark(15);
    try std.testing.expectEqualDeep(before, players);
    try std.testing.expectEqual(time, ticks);
    try std.testing.expectEqual(@as(u32, 15), participant_mask);
    try std.testing.expectEqual(@as(u32, 15), visible_mask);
    try std.testing.expect(!paused);
}

test "audio hop events preserve port identity and drain exactly once" {
    resetConnectedTest();
    _ = game_audio_events();
    _ = game_input((2 << 30) | (1 << 16));
    _ = game_tick(0);
    try std.testing.expectEqual(@as(u32, 0), game_audio_events());
    _ = game_tick(15);
    try std.testing.expectEqual(@as(u32, 4), game_audio_events());
    try std.testing.expectEqual(@as(u32, 0), game_audio_events());
    // A second press while airborne is not another successful hop.
    _ = game_input((2 << 30) | (1 << 16));
    step();
    try std.testing.expectEqual(@as(u32, 0), game_audio_events());
}

test "pause and restart discard pending sounds and request channel cleanup" {
    resetConnectedTest();
    _ = game_audio_events();
    _ = game_input(1 << 16);
    step();
    _ = game_pause(1);
    _ = game_tick(15);
    try std.testing.expectEqual(@as(u32, 0xf0), game_audio_events());
    _ = game_pause(0);
    _ = game_command(3);
    try std.testing.expectEqual(@as(u32, 0x1f0), game_audio_events());
    try std.testing.expectEqual(@as(u32, 0), game_audio_events());
    _ = game_input(0);
    _ = game_input(1 << 16);
    step();
    _ = game_command(3);
    _ = game_input(0);
    _ = game_input((3 << 30) | 0);
    _ = game_input((3 << 30) | (1 << 16));
    step();
    // A fresh post-restart hop coexists with the sticky restart command.
    try std.testing.expectEqual(@as(u32, 0x1f8), game_audio_events());
}

test "participation removes only its own pending and playing audio" {
    resetConnectedTest();
    _ = game_audio_events();
    _ = game_input((1 << 30) | (1 << 16));
    _ = game_input((3 << 30) | (1 << 16));
    step();
    _ = game_participants(13); // Remove P2 while retaining P4's hop.
    try std.testing.expectEqual(@as(u32, 0x28), game_audio_events());
    _ = game_command(3);
    _ = game_audio_events();
    _ = game_input(1 << 30);
    _ = game_input((1 << 30) | (1 << 16));
    step();
    try std.testing.expectEqual(@as(u32, 0), game_audio_events());
}

test "benchmark workload two exercises all four simultaneous sound events" {
    _ = game_reset(0);
    _ = game_audio_events();
    var simultaneous = false;
    for (0..180) |_| {
        const phase = game_benchmark(15);
        const events = game_audio_events();
        if (phase == 2 and events & 15 == 15) simultaneous = true;
    }
    try std.testing.expect(simultaneous);
}

fn resetCollisionTest() void {
    _ = game_reset(0);
    _ = game_collision_demo(1);
    _ = game_connections(15);
    for (0..4) |port| _ = game_input(@as(u32, @intCast(port)) << 30);
}
fn expectClearActor(p: Player) !void {
    try std.testing.expect(@abs(p.pos.x) <= 13 * Q and @abs(p.pos.z) <= 13 * Q);
    for (arena.obstacles) |obstacle| {
        const penetrates = p.pos.x > obstacle.min.x - arena.radius and p.pos.x < obstacle.max.x + arena.radius and
            p.pos.z > obstacle.min.z - arena.radius and p.pos.z < obstacle.max.z + arena.radius;
        try std.testing.expect(!penetrates);
    }
}

test "obstacle movement preserves hidden participants and physical port isolation" {
    resetCollisionTest();
    defer _ = game_reset(0);
    _ = game_participants(5);
    _ = game_views(4); // P1 is active but hidden; P2 is inactive.
    players[0].pos = .{ .x = 3 * Q };
    players[0].camera = 0;
    players[1].pos = .{ .x = 4 * Q + 1 }; // An inactive port stays untouched.
    const before = players;
    _ = game_input(80);
    for (0..160) |i| {
        if (i == 60) _ = game_input(80 | (1 << 16));
        step();
        try expectClearActor(players[0]);
    }
    try std.testing.expectEqual(@as(i32, 4 * Q - arena.radius), players[0].pos.x);
    try std.testing.expectEqual(@as(i32, 0), players[0].pos.z);
    for (1..4) |port| try std.testing.expectEqualDeep(before[port].pos, players[port].pos);
    try std.testing.expectEqual(@as(u32, 2), game_view_port(0));
}

test "player separation sweeps against obstacles and world corners" {
    resetCollisionTest();
    defer _ = game_reset(0);
    _ = game_participants(3);
    const contact = Vec3{ .x = 4 * Q - arena.radius };
    players[0].pos = contact;
    players[1].pos = contact;
    step();
    try expectClearActor(players[0]);
    try expectClearActor(players[1]);
    try std.testing.expect(@abs(players[0].pos.x - players[1].pos.x) >= 150);
    players[0].pos = .{ .x = 13 * Q, .z = 13 * Q };
    players[1].pos = players[0].pos;
    step();
    try expectClearActor(players[0]);
    try expectClearActor(players[1]);
    try std.testing.expect(@abs(players[0].pos.x - players[1].pos.x) >= 150);
    _ = game_participants(15);
    for (&players) |*p| p.pos = .{ .x = 4 * Q + 1, .z = 3 * Q };
    for (0..60) |_| {
        step();
        for (players) |p| try expectClearActor(p);
    }
    for (players, 0..) |a, i| for (players[i + 1 ..]) |b| {
        try std.testing.expect(!std.meta.eql(a.pos, b.pos));
    };
}

test "collision remains deterministic across fixed-step batching and tour changes" {
    resetCollisionTest();
    defer _ = game_reset(0);
    players[0].pos = .{ .x = 3 * Q };
    players[0].camera = 0;
    _ = game_input(80);
    _ = game_tick(15);
    const before = players;
    resetCollisionTest();
    players[0].pos = .{ .x = 3 * Q };
    players[0].camera = 0;
    _ = game_input(80);
    for (0..15) |_| _ = game_tick(1);
    try std.testing.expectEqualDeep(before, players);
    players[0].pos = .{ .x = 13 * Q, .z = 13 * Q };
    players[0].input = 0;
    tour = true;
    for (0..100) |_| {
        step();
        for (players) |p| try expectClearActor(p);
    }
    _ = game_command(3);
    try std.testing.expect(collision_demo); // Session restart retains demo policy.
}
