//! Zig transform, clipping and projection; RDPQ performs all rasterization.
const std = @import("std");
const game = @import("game.zig");
const rabbit = @import("generated/rabbit.zig");
const Vec3 = game.Vec3;
const Q = game.Q;
const mul = game.mul;
const sin = game.sin;
const cos = game.cos;
pub const Viewport = extern struct { x: i32, y: i32, w: i32, h: i32 };
pub const Vertex = extern struct { x: i32, y: i32, z: i32 };
pub const Triangle = extern struct { v: [3]Vertex, color: u32 };
pub const capacity = 2048;
// Plain fixed-layout data is shared by symbol, not through an ABI-dependent
// pointer/aggregate function call. Coordinates are Q4 pixels, depth is UNORM16.
export var scene_triangles: [capacity]Triangle = undefined;
export var scene_view: Viewport = undefined;
export var scene_overflow: u32 = 0;
var count: u32 = 0;
const EnvironmentCache = struct {
    valid: bool = false,
    eye: Vec3 = .{},
    yaw: i32 = 0,
    view: Viewport = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    count: usize = 0,
    triangles: [512]Triangle = undefined,
};
var environment_cache: [4]EnvironmentCache = .{EnvironmentCache{}} ** 4;
fn copyTriangles(destination: [*]volatile Triangle, source: []const Triangle) void {
    const dst: [*]volatile u32 = @ptrCast(destination);
    const src: [*]const volatile u32 = @ptrCast(source.ptr);
    for (0..source.len * 10) |i| dst[i] = src[i];
}
var eye: Vec3 = .{};
var yaw: i32 = 0;
var focal: i32 = 0;
const near = Q;
const far = 80 * Q;

pub fn viewport(n: u32, i: u32) Viewport {
    // Reserve a 16px title and a 16px control strip. Three players use a wide
    // top camera plus two lower cameras, with no empty fourth quadrant.
    if (n == 1) return .{ .x = 0, .y = 16, .w = 320, .h = 208 };
    if (n == 2 or (n == 3 and i == 0)) return .{ .x = 0, .y = 16 + @as(i32, @intCast(i)) * 105, .w = 320, .h = 103 };
    const slot = if (n == 3) i + 1 else i;
    return .{ .x = @as(i32, @intCast(slot % 2)) * 160, .y = 16 + @as(i32, @intCast(slot / 2)) * 105, .w = 160, .h = 103 };
}
fn camera(p: Vec3) Vec3 {
    const dx = p.x - eye.x;
    const dy = p.y - eye.y;
    const dz = p.z - eye.z;
    const horizontal = mul(dx, sin(yaw)) + mul(dz, cos(yaw));
    return .{ .x = mul(dx, cos(yaw)) - mul(dz, sin(yaw)), .y = mul(dy, 237) + mul(horizontal, 97), .z = mul(horizontal, 237) - mul(dy, 97) };
}
fn project(p: Vec3) Vertex {
    // One reciprocal is reused for X, Y and perspective-correct depth.
    const inverse: i64 = @divTrunc(1 << 24, p.z);
    return .{
        .x = scene_view.x * 16 + scene_view.w * 8 + @as(i32, @intCast((@as(i64, p.x) * focal * 16 * inverse) >> 24)),
        .y = scene_view.y * 16 + scene_view.h * 8 - @as(i32, @intCast((@as(i64, p.y) * focal * 16 * inverse) >> 24)),
        .z = std.math.clamp(@as(i32, @intCast(@divTrunc(@as(i64, far) * 65535, far - near) - ((@divTrunc(@as(i64, near) * far * 65535, far - near) * inverse) >> 24))), 0, 65535),
    };
}

fn lerp(a: i32, b: i32, da: i32, db: i32) i32 {
    return a + @as(i32, @intCast(@divTrunc(@as(i64, b - a) * da, da - db)));
}
fn distance(v: Vertex, plane: u32) i32 {
    return switch (plane) {
        0 => v.x - scene_view.x * 16,
        1 => (scene_view.x + scene_view.w) * 16 - v.x,
        2 => v.y - scene_view.y * 16,
        else => (scene_view.y + scene_view.h) * 16 - v.y,
    };
}
fn screenTriangle(a: Vertex, b: Vertex, c: Vertex, color: u32, cull: bool) void {
    const area = @as(i64, b.x - a.x) * (c.y - a.y) - @as(i64, b.y - a.y) * (c.x - a.x);
    if (area == 0 or (cull and area <= 0)) return;
    const x0 = scene_view.x * 16;
    const y0 = scene_view.y * 16;
    const x1 = (scene_view.x + scene_view.w) * 16;
    const y1 = (scene_view.y + scene_view.h) * 16;
    if (@max(a.x, @max(b.x, c.x)) < x0 or @min(a.x, @min(b.x, c.x)) > x1 or
        @max(a.y, @max(b.y, c.y)) < y0 or @min(a.y, @min(b.y, c.y)) > y1) return;
    if (@min(a.x, @min(b.x, c.x)) >= x0 and @max(a.x, @max(b.x, c.x)) <= x1 and
        @min(a.y, @min(b.y, c.y)) >= y0 and @max(a.y, @max(b.y, c.y)) <= y1)
    {
        if (count == capacity) {
            scene_overflow += 1;
            return;
        }
        scene_triangles[count] = .{ .v = .{ a, b, c }, .color = color };
        count += 1;
        return;
    }
    var polygon: [10]Vertex = undefined;
    polygon[0] = a;
    polygon[1] = b;
    polygon[2] = c;
    var len: usize = 3;
    for (0..4) |plane| {
        var next: [10]Vertex = undefined;
        var n: usize = 0;
        var prev = polygon[len - 1];
        var dp = distance(prev, @intCast(plane));
        for (polygon[0..len]) |v| {
            const d = distance(v, @intCast(plane));
            if ((d >= 0) != (dp >= 0)) {
                next[n] = .{ .x = lerp(prev.x, v.x, dp, d), .y = lerp(prev.y, v.y, dp, d), .z = lerp(prev.z, v.z, dp, d) };
                n += 1;
            }
            if (d >= 0) {
                next[n] = v;
                n += 1;
            }
            prev = v;
            dp = d;
        }
        if (n < 3) return;
        // Keep this copy explicit: compiler-emitted libc calls cannot use the ABI seam.
        const destination: [*]volatile Vertex = @ptrCast(&polygon);
        for (next[0..n], 0..) |v, i| destination[i] = v;
        len = n;
    }
    for (1..len - 1) |i| {
        if (count == capacity) {
            scene_overflow += 1;
            return;
        }
        scene_triangles[count] = .{ .v = .{ polygon[0], polygon[i], polygon[i + 1] }, .color = color };
        count += 1;
    }
}
fn triangle(a: Vec3, b: Vec3, c: Vec3, color: u32, cull: bool) void {
    // Clip in camera space before division: geometry crossing the camera
    // never creates inverted triangles or large coordinates on the RDP.
    const zmin = @min(a.z, @min(b.z, c.z));
    const zmax = @max(a.z, @max(b.z, c.z));
    if (zmax < near or zmin > far) return;
    if (zmin >= near and zmax <= far) {
        screenTriangle(project(a), project(b), project(c), color, cull);
        return;
    }
    var poly: [6]Vec3 = undefined;
    poly[0] = a;
    poly[1] = b;
    poly[2] = c;
    var len: usize = 3;
    for (0..2) |plane| {
        var next: [6]Vec3 = undefined;
        var n: usize = 0;
        var prev = poly[len - 1];
        var dp = if (plane == 0) prev.z - near else far - prev.z;
        for (poly[0..len]) |v| {
            const d = if (plane == 0) v.z - near else far - v.z;
            if ((d >= 0) != (dp >= 0)) {
                next[n] = .{ .x = lerp(prev.x, v.x, dp, d), .y = lerp(prev.y, v.y, dp, d), .z = lerp(prev.z, v.z, dp, d) };
                n += 1;
            }
            if (d >= 0) {
                next[n] = v;
                n += 1;
            }
            prev = v;
            dp = d;
        }
        if (n < 3) return;
        const destination: [*]volatile Vec3 = @ptrCast(&poly);
        for (next[0..n], 0..) |v, i| destination[i] = v;
        len = n;
    }
    const p0 = project(poly[0]);
    for (1..len - 1) |i| screenTriangle(p0, project(poly[i]), project(poly[i + 1]), color, cull);
}
fn worldTri(a: Vec3, b: Vec3, c: Vec3, color: u32) void {
    triangle(camera(a), camera(b), camera(c), color, false);
}
fn worldCulled(a: Vec3, b: Vec3, c: Vec3, color: u32) void {
    triangle(camera(a), camera(b), camera(c), color, true);
}
fn tint(color: u32, shade: u32) u32 {
    const r = ((color >> 24) * shade) / 255;
    const g = (((color >> 16) & 255) * shade) / 255;
    const b = (((color >> 8) & 255) * shade) / 255;
    return (r << 24) | (g << 16) | (b << 8) | 255;
}
fn disk(x: i32, z: i32, y: i32, radius: i32, color: u32) void {
    for (0..16) |i| {
        const a: i32 = @intCast(i * 16);
        worldTri(.{ .x = x, .y = y, .z = z }, .{ .x = x + mul(sin(a), radius), .y = y, .z = z + mul(cos(a), radius) }, .{ .x = x + mul(sin(a + 16), radius), .y = y, .z = z + mul(cos(a + 16), radius) }, color);
    }
}
fn cone(x: i32, z: i32, y: i32, radius: i32, height: i32, color: u32) void {
    for (0..8) |i| {
        const a: i32 = @intCast(i * 32);
        worldCulled(.{ .x = x, .y = y + height, .z = z }, .{ .x = x + mul(sin(a), radius), .y = y, .z = z + mul(cos(a), radius) }, .{ .x = x + mul(sin(a + 32), radius), .y = y, .z = z + mul(cos(a + 32), radius) }, tint(color, @intCast(185 + @divTrunc(cos(a - 32) * 60, Q))));
    }
}
fn box(x: i32, z: i32, y: i32, w: i32, d: i32, h: i32, color: u32) void {
    const v = [8]Vec3{
        .{ .x = x - w, .y = y, .z = z - d },     .{ .x = x + w, .y = y, .z = z - d },     .{ .x = x + w, .y = y, .z = z + d },     .{ .x = x - w, .y = y, .z = z + d },
        .{ .x = x - w, .y = y + h, .z = z - d }, .{ .x = x + w, .y = y + h, .z = z - d }, .{ .x = x + w, .y = y + h, .z = z + d }, .{ .x = x - w, .y = y + h, .z = z + d },
    };
    const faces = [5][4]usize{ .{ 0, 1, 5, 4 }, .{ 1, 2, 6, 5 }, .{ 2, 3, 7, 6 }, .{ 3, 0, 4, 7 }, .{ 4, 5, 6, 7 } };
    for (faces, 0..) |f, i| {
        const col = tint(color, @intCast(175 + i * 20));
        worldCulled(v[f[0]], v[f[2]], v[f[1]], col);
        worldCulled(v[f[0]], v[f[3]], v[f[2]], col);
    }
}
fn environment() void {
    // Low-contrast meadow tiles make movement and perspective easy to read.
    for (0..4) |iz| for (0..4) |ix| {
        const x = (@as(i32, @intCast(ix)) * 8 - 16) * Q;
        const z = (@as(i32, @intCast(iz)) * 8 - 16) * Q;
        const col: u32 = if ((ix + iz) % 2 == 0) 0x80ac79ff else 0x86b17dff;
        worldTri(.{ .x = x, .z = z }, .{ .x = x + 8 * Q, .z = z }, .{ .x = x + 8 * Q, .z = z + 8 * Q }, col);
        worldTri(.{ .x = x, .z = z }, .{ .x = x + 8 * Q, .z = z + 8 * Q }, .{ .x = x, .z = z + 8 * Q }, col);
    };
    disk(0, 0, 16, 4 * Q, 0xe2cf9fff);
    disk(0, 0, 32, 3 * Q, 0x97bb85ff);
    // Central carrot is a shared landmark, visible from every spawn camera.
    box(0, 0, 0, 90, 90, 45, 0xe1d9baff);
    cone(0, 0, 45, 75, 380, 0xf1a05eff);
    cone(-28, 0, 410, 70, 150, 0x548b63ff);
    cone(45, 10, 405, 60, 120, 0x74a464ff);
    const trees = [8][2]i32{ .{ -11, -9 }, .{ -5, -13 }, .{ 8, -11 }, .{ 13, -3 }, .{ 10, 10 }, .{ 1, 14 }, .{ -10, 11 }, .{ -14, 1 } };
    for (trees, 0..) |t, i| {
        const x = t[0] * Q;
        const z = t[1] * Q;
        box(x, z, 0, 65, 65, 2 * Q, 0x9c7b5aff);
        cone(x, z, Q, 2 * Q, 4 * Q, if (i % 2 == 0) 0x54896aff else 0x68996cff);
        cone(x, z, 2 * Q, 360, 3 * Q, 0x7aaa79ff);
    }
    const stones = [6][2]i32{ .{ -7, -6 }, .{ 6, -8 }, .{ 9, 5 }, .{ -8, 5 }, .{ -4, 10 }, .{ 4, 8 } };
    for (stones, 0..) |p, i| {
        cone(p[0] * Q, p[1] * Q, 0, 140, 120, 0xa7b2a4ff);
        box(p[0] * Q + 200, p[1] * Q + 100, 0, 25, 25, 85, 0xf4e3c6ff);
        cone(p[0] * Q + 200, p[1] * Q + 100, 70, 80, 70, if (i % 2 == 0) 0xdc8b7dff else 0xe2bf6dff);
    }
    // Distant faceted mountains distinguish the views without extra assets.
    for (0..8) |i| {
        const a: i32 = @intCast(i * 32);
        cone(mul(sin(a), 30 * Q), mul(cos(a), 30 * Q), -Q, 8 * Q, (8 + @as(i32, @intCast(i % 3)) * 2) * Q, if (i % 2 == 0) 0x9eb8adff else 0xb2c5b5ff);
    }
}
fn drawRabbit(index: usize) void {
    const p = game.players[index];
    // Ground contact shadow is ordinary depth-tested RDP geometry.
    disk(p.pos.x, p.pos.z, if (@abs(p.pos.x) < 4 * Q and @abs(p.pos.z) < 4 * Q) @as(i32, 42) else 10, 115, 0x6f9567ff);
    var transformed: [rabbit.vertices.len]Vec3 = undefined;
    var projected: [rabbit.vertices.len]Vertex = undefined;
    var visible: [rabbit.vertices.len]bool = undefined;
    const bob = if (p.moving) @divTrunc(@abs(sin(p.walk)), 18) else 0;
    for (rabbit.vertices, 0..) |v, i| {
        var local = Vec3{ .x = v.x, .y = v.y, .z = v.z };
        if (p.moving and (v.part == 1 or v.part == 2)) local.z += @divTrunc(sin(p.walk) * (if (v.part == 1) @as(i32, 1) else -1), 7);
        if (v.part == 3) local.x += @divTrunc(sin(@as(i32, @intCast(game.ticks % 256)) + @as(i32, @intCast(index)) * 40), 35);
        transformed[i] = camera(.{ .x = p.pos.x + mul(local.x, cos(p.yaw)) + mul(local.z, sin(p.yaw)), .y = p.pos.y + local.y + @as(i32, @intCast(bob)), .z = p.pos.z - mul(local.x, sin(p.yaw)) + mul(local.z, cos(p.yaw)) });
    }
    for (transformed, 0..) |v, i| {
        visible[i] = v.z >= near and v.z <= far;
        if (visible[i]) projected[i] = project(v);
    }
    const palette = [5]u32{ 0xf7edd6ff, 0xe98f9fff, 0x26303fff, game.colors[index], 0xfffae6ff };
    for (rabbit.faces) |f| {
        const color = tint(palette[f.material], f.shade);
        if (visible[f.a] and visible[f.b] and visible[f.c]) {
            screenTriangle(projected[f.a], projected[f.b], projected[f.c], color, true);
        } else triangle(transformed[f.a], transformed[f.b], transformed[f.c], color, true);
    }
}
export fn scene_render(index: u32) u32 {
    if (index >= game.view_count) return 0;
    scene_view = viewport(game.view_count, index);
    count = 0;
    scene_overflow = 0;
    const p = game.players[index];
    yaw = p.camera;
    eye = .{ .x = p.pos.x - mul(sin(yaw), 8 * Q), .y = 5 * Q, .z = p.pos.z - mul(cos(yaw), 8 * Q) };
    focal = @divTrunc(scene_view.h * 6, 5);
    const cache = &environment_cache[index];
    if (cache.valid and std.meta.eql(cache.eye, eye) and cache.yaw == yaw and std.meta.eql(cache.view, scene_view)) {
        copyTriangles(&scene_triangles, cache.triangles[0..cache.count]);
        count = @intCast(cache.count);
    } else {
        environment();
        cache.valid = count <= cache.triangles.len;
        if (cache.valid) {
            cache.eye = eye;
            cache.yaw = yaw;
            cache.view = scene_view;
            cache.count = count;
            copyTriangles(&cache.triangles, scene_triangles[0..count]);
        }
    }
    for (0..4) |i| drawRabbit(i);
    return count;
}

test "every split fits the framebuffer without overlapping another view" {
    for (1..5) |n| for (0..n) |i| {
        const a = viewport(@intCast(n), @intCast(i));
        try std.testing.expect(@mod(a.x, 4) == 0);
        try std.testing.expect(a.x >= 0 and a.y >= 16 and a.x + a.w <= 320 and a.y + a.h <= 224);
        for (i + 1..n) |j| {
            const b = viewport(@intCast(n), @intCast(j));
            try std.testing.expect(a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y);
        }
    };
}
test "near-plane crossings clip to valid bounded depth and viewport coordinates" {
    scene_view = viewport(4, 0);
    focal = 120;
    count = 0;
    triangle(.{ .x = -Q, .y = 0, .z = -Q }, .{ .x = Q, .y = Q, .z = 3 * Q }, .{ .x = Q, .y = -Q, .z = 3 * Q }, 0xffffffff, false);
    try std.testing.expect(count > 0);
    for (scene_triangles[0..count]) |t| for (t.v) |v| {
        try std.testing.expect(v.x >= 0 and v.x <= scene_view.w * 16);
        try std.testing.expect(v.y >= scene_view.y * 16 and v.y <= (scene_view.y + scene_view.h) * 16);
        try std.testing.expect(v.z >= 0 and v.z <= 65535);
    };
    count = 0;
    triangle(.{ .z = -Q }, .{ .x = Q, .z = -Q }, .{ .y = Q, .z = -Q }, 0xffffffff, false);
    try std.testing.expectEqual(@as(u32, 0), count);
}
test "all four cameras produce different bounded scenes within the triangle budget" {
    game.reset();
    game.view_count = 4;
    var first: ?Triangle = null;
    for (0..4) |i| {
        const n = scene_render(@intCast(i));
        try std.testing.expect(n > 200 and n < capacity);
        try std.testing.expectEqual(@as(u32, 0), scene_overflow);
        if (first) |f| try std.testing.expect(!std.meta.eql(f, scene_triangles[0]));
        first = scene_triangles[0];
    }
}
test "shared render structs have the C bridge layout" {
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(Triangle));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Viewport));
}

test "back-face culling keeps the outward-facing winding" {
    scene_view = viewport(1, 0);
    count = 0;
    const a = Vertex{ .x = 100, .y = 300, .z = 30000 };
    const b = Vertex{ .x = 200, .y = 400, .z = 30000 };
    const c = Vertex{ .x = 100, .y = 400, .z = 30000 };
    screenTriangle(a, b, c, 0xffffffff, true);
    try std.testing.expectEqual(@as(u32, 1), count);
    screenTriangle(a, c, b, 0xffffffff, true);
    try std.testing.expectEqual(@as(u32, 1), count);
}

test "tour, camera turns, and every layout keep valid clipped geometry" {
    game.reset();
    game.tour = true;
    for (1..5) |n| {
        game.view_count = @intCast(n);
        for (0..4) |phase| {
            for (0..64) |_| game.step();
            game.players[0].camera += @as(i32, @intCast(phase)) * 17;
            for (0..n) |i| {
                const num = scene_render(@intCast(i));
                try std.testing.expect(num > 0);
                try std.testing.expectEqual(@as(u32, 0), scene_overflow);
                for (scene_triangles[0..num]) |t| for (t.v) |v| {
                    try std.testing.expect(v.x >= scene_view.x * 16 and v.x <= (scene_view.x + scene_view.w) * 16);
                    try std.testing.expect(v.y >= scene_view.y * 16 and v.y <= (scene_view.y + scene_view.h) * 16);
                    try std.testing.expect(v.z >= 0 and v.z <= 65535);
                };
            }
        }
    }
}

test "static environment cache follows camera and layout changes" {
    game.reset();
    game.view_count = 4;
    _ = scene_render(0);
    const old = environment_cache[0].eye;
    game.players[0].pos.x += Q;
    _ = scene_render(0);
    try std.testing.expect(!std.meta.eql(old, environment_cache[0].eye));
    game.view_count = 1;
    _ = scene_render(0);
    try std.testing.expectEqual(@as(i32, 320), environment_cache[0].view.w);
}
