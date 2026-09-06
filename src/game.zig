//! Shared world and controller simulation. All runtime math is integer Q8 so
//! LLVM's N32 floating-point convention never crosses the libdragon O64 seam.
const std = @import("std");
pub const Q: i32 = 256;
pub const Vec3 = struct { x: i32 = 0, y: i32 = 0, z: i32 = 0 };
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
pub var view_count: u32 = 4;
pub var ticks: u32 = 0;
pub var tour = false;

pub fn reset() void {
    ticks = 0;
    tour = false;
    for (&players, 0..) |*p, i| {
        const a: i32 = @as(i32, @intCast(i)) * 64 + 32;
        p.* = .{ .pos = .{ .x = mul(sin(a), 3 * Q), .z = mul(cos(a), 3 * Q) }, .yaw = a + 128, .camera = a + 128 };
    }
}
fn axis(word: u32, shift: u5) i32 {
    const v: i8 = @bitCast(@as(u8, @truncate(word >> shift)));
    return if (@abs(@as(i32, v)) < 12) 0 else v;
}
pub fn step() void {
    ticks +%= 1;
    for (&players, 0..) |*p, i| {
        const x = axis(p.input, 0);
        const y = axis(p.input, 8);
        if (p.input & (1 << 17) != 0) p.camera -= 2;
        if (p.input & (1 << 18) != 0) p.camera += 2;
        p.camera = @mod(p.camera, 256);
        if (p.input & (1 << 19) != 0) p.camera = p.yaw;
        p.moving = x != 0 or y != 0;
        if (tour and !p.moving) {
            const a: i32 = @intCast((ticks / 4 + i * 64 + 32) % 256);
            p.pos.x = mul(sin(a), 3 * Q);
            p.pos.z = mul(cos(a), 3 * Q);
            p.yaw = a + 128;
            p.camera = p.yaw;
            p.moving = true;
        } else if (p.moving) {
            // Normalize the stick's square corners without a runtime sqrt.
            const magnitude = @max(@abs(x), @abs(y)) + @min(@abs(x), @abs(y)) / 2;
            const scale: i32 = @intCast(@max(magnitude, 80));
            const dx = @divTrunc((mul(x, cos(p.camera)) + mul(y, sin(p.camera))) * 22, scale);
            const dz = @divTrunc((-mul(x, sin(p.camera)) + mul(y, cos(p.camera))) * 22, scale);
            p.pos.x = std.math.clamp(p.pos.x + dx, -13 * Q, 13 * Q);
            p.pos.z = std.math.clamp(p.pos.z + dz, -13 * Q, 13 * Q);
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
        if ((p.input & (1 << 16) != 0 or (tour and ticks % 300 == i * 60)) and p.pos.y == 0) p.velocity_y = 57;
        // Jump is edge-triggered, even if a frame contains multiple simulation steps.
        p.input &= ~@as(u32, (1 << 16) | (1 << 19));
        p.pos.y += p.velocity_y;
        p.velocity_y -= 3;
        if (p.pos.y <= 0) {
            p.pos.y = 0;
            p.velocity_y = 0;
        }
    }
    // Symmetric separation: all four rabbits stay in the same physical world,
    // including rabbits whose cameras are currently hidden.
    for (0..4) |i| for (i + 1..4) |j| {
        const dx = players[j].pos.x - players[i].pos.x;
        const dz = players[j].pos.z - players[i].pos.z;
        const d = @max(@abs(dx), @abs(dz));
        if (d < 150 and @abs(players[i].pos.y - players[j].pos.y) < Q) {
            const push: i32 = @intCast((150 - d) / 2 + 1);
            if (@abs(dx) >= @abs(dz)) {
                const s: i32 = if (dx >= 0) 1 else -1;
                players[i].pos.x -= push * s;
                players[j].pos.x += push * s;
            } else {
                const s: i32 = if (dz >= 0) 1 else -1;
                players[i].pos.z -= push * s;
                players[j].pos.z += push * s;
            }
        }
    };
    for (&players) |*p| {
        p.pos.x = std.math.clamp(p.pos.x, -13 * Q, 13 * Q);
        p.pos.z = std.math.clamp(p.pos.z, -13 * Q, 13 * Q);
    }
}
export fn game_reset(_: u32) u32 {
    reset();
    view_count = 4;
    benchmark_ticks = 0;
    return 0;
}
export fn game_input(word: u32) u32 {
    const p = &players[word >> 30];
    p.input = (word & 0x3fffffff) | (p.input & ((1 << 16) | (1 << 19)));
    return 0;
}
export fn game_tick(count: u32) u32 {
    for (0..@min(count, 15)) |_| step();
    return 0;
}
export fn game_command(command: u32) u32 {
    switch (command) {
        1 => view_count = view_count % 4 + 1,
        2 => tour = !tour,
        3 => reset(),
        else => {},
    }
    return view_count;
}
export fn game_status() u32 {
    return view_count | (@as(u32, @intFromBool(tour)) << 8);
}

test "all view counts preserve a single shared world" {
    reset();
    view_count = 4;
    const before = players;
    for (1..5) |n| {
        _ = game_command(1);
        try std.testing.expectEqual(@as(u32, @intCast(n)), view_count);
    }
    try std.testing.expectEqualDeep(before, players);
}
test "packed controller input moves only the addressed rabbit" {
    reset();
    const before = players;
    _ = game_input((2 << 30) | (80 << 8));
    step();
    try std.testing.expect(players[2].pos.x != before[2].pos.x);
    try std.testing.expectEqualDeep(before[0].pos, players[0].pos);
    try std.testing.expectEqualDeep(before[1].pos, players[1].pos);
    try std.testing.expectEqualDeep(before[3].pos, players[3].pos);
}
test "jump lands and does not repeat without another press" {
    reset();
    _ = game_input(1 << 16);
    step();
    try std.testing.expect(players[0].pos.y > 0);
    for (0..80) |_| step();
    try std.testing.expectEqual(@as(i32, 0), players[0].pos.y);
}
test "world bounds and overlapping players remain bounded" {
    reset();
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
    reset();
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
            if (time % 120 == i * 20) word |= 1 << 16;
            _ = game_input(word);
        }
        step();
        benchmark_ticks +%= 1;
    }
    return (benchmark_ticks / 1200) % 3;
}

test "recenter press survives a frame with no simulation step" {
    reset();
    players[0].camera = 0;
    players[0].yaw = 80;
    _ = game_input(1 << 19);
    _ = game_tick(0);
    _ = game_input(0);
    step();
    try std.testing.expectEqual(@as(i32, 80), players[0].camera);
}
