//! Zig scene batching and animation. Tiny3D transforms/clips on the RSP;
//! RDPQ owns hardware rasterization, depth, clears, and text.
const std = @import("std");
const game = @import("game.zig");
const rabbit = @import("generated/rabbit.zig");
const Vec3 = game.Vec3;
const Q = game.Q;
const mul = game.mul;
const sin = game.sin;
const cos = game.cos;
pub const Viewport = extern struct { x: i32, y: i32, w: i32, h: i32 };
pub const Camera = extern struct { eye: [3]i32, target: [3]i32 };
// Exactly Tiny3D's two interleaved vertices; normals/UV are unused.
pub const Packed = extern struct {
    pos_a: [3]i16,
    norm_a: u16 = 0,
    pos_b: [3]i16,
    norm_b: u16 = 0,
    color_a: u32,
    color_b: u32,
    uv_a: [2]i16 = .{ 0, 0 },
    uv_b: [2]i16 = .{ 0, 0 },
};
pub const Batch = extern struct { vertex_offset: u32, vertex_count: u32, index_offset: u32, index_count: u32 };
pub const Mesh = extern struct {
    vertices: [1024]Packed,
    batches: [64]Batch,
    indices: [4096]u8,
    vertex_count: u32,
    index_count: u32,
    batch_count: u32,
};
pub const frame_pairs = 384;
export var scene_environment: Mesh align(16) = undefined;
export var scene_rabbit: Mesh align(16) = undefined;
export var scene_frames: [3][4][frame_pairs]Packed align(16) = undefined;
export var scene_views: [4]Viewport = undefined;
export var scene_cameras: [4]Camera = undefined;
export var scene_bounds: [4][6]i16 = undefined;
export var scene_overflow: u32 = 0;
var vertex_sources: [2048]u16 = undefined;
var vertex_materials: [2048]u8 = undefined;
var vertex_shades: [2048]u8 = undefined;
const Key = struct { p: Vec3, color: u32, source: u16 };
var keys: [64]Key = undefined;
var mesh: *Mesh = undefined;
var source_id: u16 = 0xffff;
var material_id: u8 = 0;
var shade_id: u8 = 255;

pub fn viewport(n: u32, i: u32) Viewport {
    if (n == 1) return .{ .x = 0, .y = 16, .w = 320, .h = 208 };
    if (n == 2 or (n == 3 and i == 0)) return .{ .x = 0, .y = 16 + @as(i32, @intCast(i)) * 105, .w = 320, .h = 103 };
    const slot = if (n == 3) i + 1 else i;
    return .{ .x = @as(i32, @intCast(slot % 2)) * 160, .y = 16 + @as(i32, @intCast(slot / 2)) * 105, .w = 160, .h = 103 };
}
fn begin(m: *Mesh) void {
    mesh = m;
    mesh.vertex_count = 0;
    mesh.index_count = 0;
    mesh.batch_count = 0;
}
fn padMesh() void {
    if (mesh.vertex_count % 2 != 0) {
        const i = mesh.vertex_count;
        const prev = &mesh.vertices[i / 2];
        prev.pos_b = prev.pos_a;
        prev.norm_b = 0;
        prev.color_b = prev.color_a;
        prev.uv_b = .{ 0, 0 };
        vertex_sources[i] = vertex_sources[i - 1];
        vertex_materials[i] = vertex_materials[i - 1];
        vertex_shades[i] = vertex_shades[i - 1];
        mesh.vertex_count += 1;
    }
}
fn newBatch() void {
    if (mesh.batch_count == mesh.batches.len) {
        scene_overflow = 1;
        return;
    }
    padMesh();
    mesh.batches[mesh.batch_count] = .{ .vertex_offset = mesh.vertex_count, .vertex_count = 0, .index_offset = mesh.index_count, .index_count = 0 };
    mesh.batch_count += 1;
}
fn position(p: Vec3) [3]i16 {
    return .{ @intCast(p.x), @intCast(p.y), @intCast(p.z) };
}
fn setVertex(dst: *Packed, index: u32, p: Vec3, color: u32) void {
    if (index % 2 == 0) {
        dst.pos_a = position(p);
        dst.norm_a = 0;
        dst.color_a = color;
        dst.uv_a = .{ 0, 0 };
    } else {
        dst.pos_b = position(p);
        dst.norm_b = 0;
        dst.color_b = color;
        dst.uv_b = .{ 0, 0 };
    }
}
fn emitVertex(p: Vec3, color: u32) u8 {
    const b = &mesh.batches[mesh.batch_count - 1];
    for (keys[0..b.vertex_count], 0..) |k, i| {
        if (k.color == color and k.source == source_id and std.meta.eql(k.p, p)) return @intCast(i);
    }
    const index = mesh.vertex_count;
    setVertex(&mesh.vertices[index / 2], index, p, color);
    keys[b.vertex_count] = .{ .p = p, .color = color, .source = source_id };
    vertex_sources[index] = source_id;
    vertex_materials[index] = material_id;
    vertex_shades[index] = shade_id;
    b.vertex_count += 1;
    mesh.vertex_count += 1;
    return @intCast(b.vertex_count - 1);
}
fn reserveTriangle() bool {
    if (scene_overflow != 0) return false;
    if (mesh.vertex_count + 4 > mesh.vertices.len * 2 or mesh.index_count + 3 > mesh.indices.len) {
        scene_overflow = 1;
        return false;
    }
    if (mesh.batch_count == 0 or mesh.batches[mesh.batch_count - 1].vertex_count > 61) newBatch();
    return scene_overflow == 0;
}
fn worldTri(a: Vec3, b: Vec3, c: Vec3, color: u32) void {
    if (!reserveTriangle()) return;
    for ([_]Vec3{ a, b, c }) |p| {
        mesh.indices[mesh.index_count] = emitVertex(p, color);
        mesh.index_count += 1;
    }
    mesh.batches[mesh.batch_count - 1].index_count += 3;
}
fn worldCulled(a: Vec3, b: Vec3, c: Vec3, color: u32) void {
    worldTri(a, b, c, color);
}
fn tint(color: u32, shade: u32) u32 {
    const r = ((color >> 24) * shade) / 255;
    const g = (((color >> 16) & 255) * shade) / 255;
    const b = (((color >> 8) & 255) * shade) / 255;
    return (r << 24) | (g << 16) | (b << 8) | 255;
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
fn group() void {
    if (mesh.batch_count != 0 and mesh.batches[mesh.batch_count - 1].vertex_count != 0) newBatch();
}
fn environment() void {
    // Low-contrast meadow tiles make movement and perspective easy to read.
    for (0..4) |iz| for (0..4) |ix| {
        group();
        const x = (@as(i32, @intCast(ix)) * 8 - 16) * Q;
        const z = (@as(i32, @intCast(iz)) * 8 - 16) * Q;
        const col: u32 = if ((ix + iz) % 2 == 0) 0x80ac79ff else 0x86b17dff;
        worldTri(.{ .x = x, .z = z }, .{ .x = x + 8 * Q, .z = z + 8 * Q }, .{ .x = x + 8 * Q, .z = z }, col);
        worldTri(.{ .x = x, .z = z }, .{ .x = x, .z = z + 8 * Q }, .{ .x = x + 8 * Q, .z = z + 8 * Q }, col);
    };
    group();
    // A true annulus avoids overlapping coplanar grass/path discs. Its
    // small offset above the meadow is larger than RDP depth quantization.
    for (0..16) |i| {
        const a: i32 = @intCast(i * 16);
        const b = a + 16;
        const inner_a = Vec3{ .x = mul(sin(a), 3 * Q), .y = 32, .z = mul(cos(a), 3 * Q) };
        const outer_a = Vec3{ .x = mul(sin(a), 4 * Q), .y = 32, .z = mul(cos(a), 4 * Q) };
        const inner_b = Vec3{ .x = mul(sin(b), 3 * Q), .y = 32, .z = mul(cos(b), 3 * Q) };
        const outer_b = Vec3{ .x = mul(sin(b), 4 * Q), .y = 32, .z = mul(cos(b), 4 * Q) };
        worldTri(inner_a, outer_a, outer_b, 0xe2cf9fff);
        worldTri(inner_a, outer_b, inner_b, 0xe2cf9fff);
    }
    // Central carrot is a shared landmark, visible from every spawn camera.
    group();
    box(0, 0, 0, 90, 90, 45, 0xe1d9baff);
    cone(0, 0, 45, 75, 380, 0xf1a05eff);
    cone(-28, 0, 410, 70, 150, 0x548b63ff);
    cone(45, 10, 405, 60, 120, 0x74a464ff);
    const trees = [8][2]i32{ .{ -11, -9 }, .{ -5, -13 }, .{ 8, -11 }, .{ 13, -3 }, .{ 10, 10 }, .{ 1, 14 }, .{ -10, 11 }, .{ -14, 1 } };
    for (trees, 0..) |t, i| {
        group();
        const x = t[0] * Q;
        const z = t[1] * Q;
        box(x, z, 0, 65, 65, 2 * Q, 0x9c7b5aff);
        cone(x, z, Q, 2 * Q, 4 * Q, if (i % 2 == 0) 0x54896aff else 0x68996cff);
        cone(x, z, 2 * Q, 360, 3 * Q, 0x7aaa79ff);
    }
    const stones = [6][2]i32{ .{ -7, -6 }, .{ 6, -8 }, .{ 9, 5 }, .{ -8, 5 }, .{ -4, 10 }, .{ 4, 8 } };
    for (stones, 0..) |p, i| {
        group();
        cone(p[0] * Q, p[1] * Q, 0, 140, 120, 0xa7b2a4ff);
        box(p[0] * Q + 200, p[1] * Q + 100, 0, 25, 25, 85, 0xf4e3c6ff);
        cone(p[0] * Q + 200, p[1] * Q + 100, 70, 80, 70, if (i % 2 == 0) 0xdc8b7dff else 0xe2bf6dff);
    }
    // Distant faceted mountains distinguish the views without extra assets.
    for (0..8) |i| {
        group();
        const a: i32 = @intCast(i * 32);
        cone(mul(sin(a), 30 * Q), mul(cos(a), 30 * Q), -Q, 8 * Q, (8 + @as(i32, @intCast(i % 3)) * 2) * Q, if (i % 2 == 0) 0x9eb8adff else 0xb2c5b5ff);
    }
}
fn colorFor(player: usize, material: u8, shade: u8) u32 {
    const palette = [6]u32{ 0xf7edd6ff, 0xe98f9fff, 0x26303fff, game.colors[player], 0xfffae6ff, 0x6f9567ff };
    return tint(palette[material], shade);
}
fn localVertex(id: usize) Vec3 {
    if (id < rabbit.vertices.len) {
        const v = rabbit.vertices[id];
        return .{ .x = v.x, .y = v.y, .z = v.z };
    }
    if (id == rabbit.vertices.len) return .{};
    const angle = @as(i32, @intCast(id - rabbit.vertices.len - 1)) * 16;
    return .{ .x = mul(sin(angle), 115), .z = mul(cos(angle), 115) };
}
export fn scene_init(_: u32) u32 {
    scene_overflow = 0;
    source_id = 0xffff;
    begin(&scene_environment);
    environment();
    padMesh();
    if (scene_overflow != 0) return 1;
    // Rabbit batches are indexed by original Blender vertex + face shade.
    begin(&scene_rabbit);
    for (rabbit.faces) |f| {
        if (!reserveTriangle()) return 1;
        material_id = f.material;
        shade_id = f.shade;
        for ([_]u16{ f.a, f.b, f.c }) |id| {
            source_id = id;
            const v = rabbit.vertices[id];
            mesh.indices[mesh.index_count] = emitVertex(.{ .x = v.x, .y = v.y, .z = v.z }, colorFor(0, f.material, f.shade));
            mesh.index_count += 1;
        }
        mesh.batches[mesh.batch_count - 1].index_count += 3;
    }
    // The contact shadow follows X/Z but stays on the ground during hops.
    for (0..16) |i| {
        if (!reserveTriangle()) return 1;
        material_id = 5;
        shade_id = 255;
        for ([_]usize{ rabbit.vertices.len, rabbit.vertices.len + 1 + i, rabbit.vertices.len + 1 + (i + 1) % 16 }) |id| {
            source_id = @intCast(id);
            mesh.indices[mesh.index_count] = emitVertex(localVertex(id), colorFor(0, 5, 255));
            mesh.index_count += 1;
        }
        mesh.batches[mesh.batch_count - 1].index_count += 3;
    }
    padMesh();
    if (scene_rabbit.vertex_count > frame_pairs * 2) {
        scene_overflow = 1;
        return 1;
    }
    for (0..3) |frame| for (0..4) |player| {
        for (0..scene_rabbit.vertex_count) |i| {
            const v = localVertex(vertex_sources[i]);
            setVertex(&scene_frames[frame][player][i / 2], @intCast(i), .{ .x = v.x, .y = v.y, .z = v.z }, colorFor(player, vertex_materials[i], vertex_shades[i]));
        }
    };
    return 0;
}
export fn scene_prepare(frame: u32) u32 {
    if (frame >= 3) return 0;
    for (&game.players, 0..) |*p, player| {
        const s = sin(p.yaw);
        const c = cos(p.yaw);
        const walk = sin(p.walk);
        const bob: i32 = if (p.moving) @intCast(@divTrunc(@abs(walk), 18)) else 0;
        const ear = @divTrunc(sin(@as(i32, @intCast(game.ticks % 256)) + @as(i32, @intCast(player)) * 40), 35);
        var world: [rabbit.vertices.len + 17]Vec3 = undefined;
        for (rabbit.vertices, 0..) |v, i| {
            var x: i32 = v.x;
            var z: i32 = v.z;
            if (v.part == 3) x += ear;
            if (p.moving and (v.part == 1 or v.part == 2)) z += @divTrunc(walk * (if (v.part == 1) @as(i32, 1) else -1), 7);
            world[i] = .{ .x = p.pos.x + mul(x, c) + mul(z, s), .y = p.pos.y + v.y + bob, .z = p.pos.z - mul(x, s) + mul(z, c) };
        }
        for (rabbit.vertices.len..world.len) |id| {
            const local = localVertex(id);
            world[id] = .{ .x = p.pos.x + local.x, .z = p.pos.z + local.z, .y = if (@abs(p.pos.x) < 4 * Q and @abs(p.pos.z) < 4 * Q) 42 else 10 };
        }
        for (0..scene_rabbit.vertex_count) |i| {
            const dst = &scene_frames[frame][player][i / 2];
            if (i % 2 == 0) dst.pos_a = position(world[vertex_sources[i]]) else dst.pos_b = position(world[vertex_sources[i]]);
        }
        scene_bounds[player] = .{ @intCast(p.pos.x - Q), @intCast(@min(p.pos.y, 0)), @intCast(p.pos.z - Q), @intCast(p.pos.x + Q), @intCast(p.pos.y + 4 * Q), @intCast(p.pos.z + Q) };
        scene_views[player] = viewport(game.view_count, @intCast(player));
        const cs = sin(p.camera);
        const cc = cos(p.camera);
        const eye = Vec3{ .x = p.pos.x - mul(cs, 8 * Q), .y = 5 * Q, .z = p.pos.z - mul(cc, 8 * Q) };
        scene_cameras[player] = .{ .eye = .{ eye.x, eye.y, eye.z }, .target = .{ eye.x + mul(cs, 237), eye.y - 97, eye.z + mul(cc, 237) } };
    }
    return scene_environment.index_count / 3 + 4 * scene_rabbit.index_count / 3;
}

test "split viewports fit, never overlap, and satisfy RDP fill alignment" {
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
test "packed mesh batches satisfy RSP vertex cache and DMA constraints" {
    try std.testing.expectEqual(@as(u32, 0), scene_init(0));
    for ([_]*const Mesh{ &scene_environment, &scene_rabbit }) |m| {
        try std.testing.expect(m.vertex_count <= m.vertices.len * 2 and m.batch_count <= m.batches.len);
        var indices: u32 = 0;
        for (m.batches[0..m.batch_count]) |b| {
            try std.testing.expect(b.vertex_offset % 2 == 0 and b.vertex_count <= 64);
            try std.testing.expect(b.index_count % 3 == 0);
            for (m.indices[b.index_offset .. b.index_offset + b.index_count]) |i| try std.testing.expect(i < b.vertex_count);
            indices += b.index_count;
        }
        try std.testing.expectEqual(m.index_count, indices);
    }
    try std.testing.expectEqual(@as(u32, (rabbit.faces.len + 16) * 3), scene_rabbit.index_count);
}
test "C bridge and Tiny3D vertex layouts agree" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Packed));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Packed, "color_a"));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Viewport));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(Camera));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Batch));
    try std.testing.expectEqual(@as(usize, 37900), @sizeOf(Mesh));
}
test "animated data is shared across views and frame slots remain independent" {
    _ = scene_init(0);
    game.reset();
    game.tour = true;
    _ = scene_prepare(0);
    const before = scene_frames[0][0][0];
    for (0..320) |_| game.step();
    _ = scene_prepare(1);
    try std.testing.expectEqualDeep(before, scene_frames[0][0][0]);
    try std.testing.expect(!std.meta.eql(before, scene_frames[1][0][0]));
    for (0..4) |i| {
        for (i + 1..4) |j| try std.testing.expect(!std.meta.eql(scene_cameras[i], scene_cameras[j]));
    }
}

test "mesh growth reports overflow before writing beyond its storage" {
    scene_overflow = 0;
    begin(&scene_environment);
    mesh.vertex_count = 2046;
    try std.testing.expect(!reserveTriangle());
    try std.testing.expectEqual(@as(u32, 1), scene_overflow);
    _ = scene_init(0);
}
test "animated bounds contain every packed body and ground shadow vertex" {
    _ = scene_init(0);
    game.reset();
    for (0..3600) |step| {
        _ = game.game_benchmark(1);
        if (step % 60 != 0) continue;
        _ = scene_prepare(0);
        for (0..4) |p| {
            const bounds = scene_bounds[p];
            for (0..scene_rabbit.vertex_count) |i| {
                const v = scene_frames[0][p][i / 2];
                const pos = if (i % 2 == 0) v.pos_a else v.pos_b;
                for (0..3) |axis| try std.testing.expect(pos[axis] >= bounds[axis] and pos[axis] <= bounds[axis + 3]);
            }
        }
    }
}
