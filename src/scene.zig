//! Zig scene batching and animation. Tiny3D transforms/clips on the RSP;
//! RDPQ owns hardware rasterization, depth, clears, and text.
const std = @import("std");
const game = @import("game.zig");
const content = @import("content");
const character = content.character;
const character_bounds = blk: {
    var radius: i32 = 115; // Contact-shadow radius.
    var top: i32 = 0;
    for (character.vertices) |v| {
        const motion = @divTrunc(256, content.stride_divisor) + @divTrunc(256, content.sway_divisor);
        radius = @max(radius, @as(i32, @intCast(@abs(@as(i32, v.x)) + @abs(@as(i32, v.z)))) + motion + 2);
        top = @max(top, @as(i32, v.y) + @divTrunc(256, content.bob_divisor));
    }
    break :blk .{ .radius = radius, .top = top };
};
pub const Vec3 = game.Vec3;
const Q = game.Q;
pub const mul = game.mul;
pub const sin = game.sin;
pub const cos = game.cos;
pub const Viewport = extern struct { x: i32, y: i32, w: i32, h: i32 };
pub const Camera = extern struct { eye: [3]i32, target: [3]i32 };
// Exactly Tiny3D's two interleaved vertices; ground materials use UVs, normals are unused.
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
// One material per spatial batch; the C adapter binds it after culling.
export var scene_environment_materials: [64]u32 = undefined;
export var scene_rabbit: Mesh align(16) = undefined;
export var scene_frames: [3][4][frame_pairs]Packed align(16) = undefined;
export var scene_views: [4]Viewport = undefined;
export var scene_cameras: [4]Camera = undefined;
export var scene_bounds: [4][6]i16 = undefined;
export var scene_overflow: u32 = 0;
var vertex_sources: [2048]u16 = undefined;
var vertex_materials: [2048]u8 = undefined;
var vertex_shades: [2048]u8 = undefined;
const Key = struct { p: Vec3, color: u32, source: u16, material: u8, shade: u8 };
var keys: [64]Key = undefined;
var mesh: *Mesh = undefined;
var source_id: u16 = 0xffff;
var material_id: u8 = 0;
var shade_id: u8 = 255;
var textured_ground = false;
var world_material: u32 = 0;

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
        prev.uv_b = prev.uv_a;
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
    if (mesh == &scene_environment) scene_environment_materials[mesh.batch_count] = world_material;
    mesh.batch_count += 1;
}
fn packedCoordinate(value: i32) i16 {
    if (value < std.math.minInt(i16) or value > std.math.maxInt(i16)) {
        scene_overflow = 1;
        return 0;
    }
    return @intCast(value);
}
fn position(p: Vec3) [3]i16 {
    return .{ packedCoordinate(p.x), packedCoordinate(p.y), packedCoordinate(p.z) };
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
        if (k.color == color and k.source == source_id and k.material == material_id and k.shade == shade_id and std.meta.eql(k.p, p)) return @intCast(i);
    }
    const index = mesh.vertex_count;
    setVertex(&mesh.vertices[index / 2], index, p, color);
    if (mesh == &scene_environment and world_material == 1) {
        // Tiny3D UVs are signed 10.5 texel coordinates. With a 16x16 tile,
        // Q8 world X/Z maps to one repetition every two world metres.
        const uv: [2]i16 = .{ packedCoordinate(p.x), packedCoordinate(p.z) };
        if (index % 2 == 0) mesh.vertices[index / 2].uv_a = uv else mesh.vertices[index / 2].uv_b = uv;
    }
    keys[b.vertex_count] = .{ .p = p, .color = color, .source = source_id, .material = material_id, .shade = shade_id };
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
fn worldMaterialTri(a: Vec3, b: Vec3, c: Vec3, color: u32, material: u32) void {
    world_material = material;
    if (mesh.batch_count != 0 and scene_environment_materials[mesh.batch_count - 1] != material) {
        if (mesh.batches[mesh.batch_count - 1].vertex_count == 0) {
            scene_environment_materials[mesh.batch_count - 1] = material;
        } else group();
    }
    if (!reserveTriangle()) return;
    for ([_]Vec3{ a, b, c }) |p| {
        mesh.indices[mesh.index_count] = emitVertex(p, color);
        mesh.index_count += 1;
    }
    mesh.batches[mesh.batch_count - 1].index_count += 3;
}
pub fn worldTri(a: Vec3, b: Vec3, c: Vec3, color: u32) void {
    worldMaterialTri(a, b, c, color, 0);
}
pub fn groundTri(a: Vec3, b: Vec3, c: Vec3, color: u32) void {
    worldMaterialTri(a, b, c, color, @intFromBool(textured_ground));
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
pub fn cone(x: i32, z: i32, y: i32, radius: i32, height: i32, color: u32) void {
    for (0..8) |i| {
        const a: i32 = @intCast(i * 32);
        worldCulled(.{ .x = x, .y = y + height, .z = z }, .{ .x = x + mul(sin(a), radius), .y = y, .z = z + mul(cos(a), radius) }, .{ .x = x + mul(sin(a + 32), radius), .y = y, .z = z + mul(cos(a + 32), radius) }, tint(color, @intCast(185 + @divTrunc(cos(a - 32) * 60, Q))));
    }
}
pub fn box(x: i32, z: i32, y: i32, w: i32, d: i32, h: i32, color: u32) void {
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
pub fn group() void {
    if (mesh.batch_count != 0 and mesh.batches[mesh.batch_count - 1].vertex_count != 0) newBatch();
}

fn colorFor(player: usize, material: u8, shade: u8) u32 {
    const color = if (material == content.player_material) game.colors[player] else content.palette[material];
    return tint(color, shade);
}
fn localVertex(id: usize) Vec3 {
    if (id < character.vertices.len) {
        const v = character.vertices[id];
        return .{ .x = v.x, .y = v.y, .z = v.z };
    }
    if (id == character.vertices.len) return .{};
    const angle = @as(i32, @intCast(id - character.vertices.len - 1)) * 16;
    return .{ .x = mul(sin(angle), 115), .z = mul(cos(angle), 115) };
}
// Keep visible collision shapes separate from the decorative content recipe.
fn collisionObstacles() void {
    if (!game.collision_demo) return;
    for (game.arena.obstacles, game.arena.colors) |obstacle, color| {
        group();
        box(@divTrunc(obstacle.min.x + obstacle.max.x, 2), @divTrunc(obstacle.min.z + obstacle.max.z, 2), obstacle.min.y, @divTrunc(obstacle.max.x - obstacle.min.x, 2), @divTrunc(obstacle.max.z - obstacle.min.z, 2), obstacle.max.y - obstacle.min.y, color);
    }
}
export fn scene_init(options: u32) u32 {
    scene_overflow = 0;
    textured_ground = options & 1 != 0;
    world_material = 0;
    source_id = 0xffff;
    begin(&scene_environment);
    content.environment(@This());
    collisionObstacles();
    padMesh();
    if (scene_overflow != 0) return 1;
    // Character batches are indexed by original Blender vertex + face shade.
    world_material = 0;
    begin(&scene_rabbit);
    for (character.faces) |f| {
        if (!reserveTriangle()) return 1;
        material_id = f.material;
        shade_id = f.shade;
        for ([_]u16{ f.a, f.b, f.c }) |id| {
            source_id = id;
            const v = character.vertices[id];
            mesh.indices[mesh.index_count] = emitVertex(.{ .x = v.x, .y = v.y, .z = v.z }, colorFor(0, f.material, f.shade));
            mesh.index_count += 1;
        }
        mesh.batches[mesh.batch_count - 1].index_count += 3;
    }
    // The contact shadow follows X/Z but stays on the ground during hops.
    for (0..16) |i| {
        if (!reserveTriangle()) return 1;
        material_id = content.shadow_material;
        shade_id = 255;
        for ([_]usize{ character.vertices.len, character.vertices.len + 1 + i, character.vertices.len + 1 + (i + 1) % 16 }) |id| {
            source_id = @intCast(id);
            mesh.indices[mesh.index_count] = emitVertex(localVertex(id), colorFor(0, content.shadow_material, 255));
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
export fn scene_status() u32 {
    return scene_overflow;
}
export fn scene_prepare(frame: u32) u32 {
    if (frame >= 3) return 0;
    for (&game.players, 0..) |*p, player| {
        if (!game.isParticipant(player)) continue;
        const s = sin(p.yaw);
        const c = cos(p.yaw);
        const walk = sin(p.walk);
        const bob: i32 = if (p.moving) @intCast(@divTrunc(@abs(walk), content.bob_divisor)) else 0;
        const ear = @divTrunc(sin(@as(i32, @intCast(game.ticks % 256)) + @as(i32, @intCast(player)) * 40), content.sway_divisor);
        const shadow_height = content.shadowHeight(p.pos.x, p.pos.z);
        var world: [character.vertices.len + 17]Vec3 = undefined;
        for (character.vertices, 0..) |v, i| {
            var x: i32 = v.x;
            var z: i32 = v.z;
            if (v.part == 3) x += ear;
            if (p.moving and (v.part == 1 or v.part == 2)) z += @divTrunc(walk * (if (v.part == 1) @as(i32, 1) else -1), content.stride_divisor);
            world[i] = .{ .x = p.pos.x + mul(x, c) + mul(z, s), .y = p.pos.y + v.y + bob, .z = p.pos.z - mul(x, s) + mul(z, c) };
        }
        for (character.vertices.len..world.len) |id| {
            const local = localVertex(id);
            world[id] = .{ .x = p.pos.x + local.x, .z = p.pos.z + local.z, .y = shadow_height };
        }
        for (0..scene_rabbit.vertex_count) |i| {
            const dst = &scene_frames[frame][player][i / 2];
            if (i % 2 == 0) dst.pos_a = position(world[vertex_sources[i]]) else dst.pos_b = position(world[vertex_sources[i]]);
        }
        scene_bounds[player] = .{ packedCoordinate(p.pos.x - character_bounds.radius), packedCoordinate(@min(p.pos.y, shadow_height)), packedCoordinate(p.pos.z - character_bounds.radius), packedCoordinate(p.pos.x + character_bounds.radius), packedCoordinate(@max(p.pos.y + character_bounds.top, shadow_height)), packedCoordinate(p.pos.z + character_bounds.radius) };
    }
    // Frame geometry is indexed by physical port; views/cameras by compact slot.
    for (0..game.view_count) |slot| {
        const p = &game.players[game.game_view_port(@intCast(slot))];
        scene_views[slot] = viewport(game.view_count, @intCast(slot));
        const cs = sin(p.camera);
        const cc = cos(p.camera);
        const eye = Vec3{ .x = p.pos.x - mul(cs, 8 * Q), .y = 5 * Q, .z = p.pos.z - mul(cc, 8 * Q) };
        if (game.collision_demo) {
            const pivot = Vec3{ .x = p.pos.x, .y = p.pos.y + 2 * Q, .z = p.pos.z };
            // Retain the desired diagonal view if the query cannot provide a
            // usable eye; an inside/t=0 hit must never collapse look_at.
            const adjusted = game.arena.cameraEye(pivot, eye) orelse eye;
            scene_cameras[slot] = .{ .eye = .{ adjusted.x, adjusted.y, adjusted.z }, .target = .{ pivot.x, pivot.y, pivot.z } };
        } else {
            scene_cameras[slot] = .{ .eye = .{ eye.x, eye.y, eye.z }, .target = .{ eye.x + mul(cs, 237), eye.y - 97, eye.z + mul(cc, 237) } };
        }
    }
    return scene_environment.index_count / 3 + @popCount(game.participant_mask) * scene_rabbit.index_count / 3;
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
    try std.testing.expectEqual(@as(u32, (character.faces.len + 16) * 3), scene_rabbit.index_count);
    try std.testing.expectEqual(@as(u32, character.packed_vertex_count), scene_rabbit.vertex_count);
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
    _ = game.game_reset(0);
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
    _ = game.game_reset(0);
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

test "noncontiguous visible ports retain their cameras in compact slots" {
    _ = scene_init(0);
    _ = game.game_reset(0);
    _ = scene_prepare(0);
    const second = scene_cameras[1];
    const fourth = scene_cameras[3];
    _ = game.game_participants(10);
    _ = scene_prepare(1);
    try std.testing.expectEqualDeep(second, scene_cameras[0]);
    try std.testing.expectEqualDeep(fourth, scene_cameras[1]);
    try std.testing.expectEqualDeep(viewport(2, 0), scene_views[0]);
    try std.testing.expectEqualDeep(viewport(2, 1), scene_views[1]);
    _ = game.game_views(8);
    _ = scene_prepare(2);
    try std.testing.expectEqualDeep(fourth, scene_cameras[0]);
    try std.testing.expectEqualDeep(viewport(1, 0), scene_views[0]);
    _ = game.game_views(0);
    _ = scene_prepare(0); // Active participants may all have hidden cameras.
    try std.testing.expectEqual(@as(u32, 0), game.view_count);
    _ = game.game_participants(0);
    _ = scene_prepare(0); // Zero participants must never request an invalid camera.
    try std.testing.expectEqual(@as(u32, 0), game.view_count);
}

test "pausing preserves the walking pose throughout paused simulation ticks" {
    _ = scene_init(0);
    _ = game.game_reset(0);
    _ = game.game_connections(1);
    _ = game.game_input(0);
    _ = game.game_input(80 << 8);
    game.step();
    try std.testing.expect(game.players[0].moving);
    _ = scene_prepare(0);
    const camera = scene_cameras[0];
    const bounds = scene_bounds[0];
    _ = game.game_pause(1);
    for (0..15) |_| game.step();
    _ = scene_prepare(1);
    const pairs = (scene_rabbit.vertex_count + 1) / 2;
    try std.testing.expectEqualDeep(scene_frames[0][0][0..pairs], scene_frames[1][0][0..pairs]);
    try std.testing.expectEqualDeep(camera, scene_cameras[0]);
    try std.testing.expectEqualDeep(bounds, scene_bounds[0]);
    _ = game.game_pause(0);
    game.step();
    try std.testing.expect(!game.players[0].moving);
}

test "optional ground material has bounded planar UVs and never reaches actors" {
    for ([_]u32{ 0, 1 }) |enabled| {
        try std.testing.expectEqual(@as(u32, 0), scene_init(enabled));
        var textured_triangles: u32 = 0;
        for (scene_environment.batches[0..scene_environment.batch_count], 0..) |batch, b| {
            const material = scene_environment_materials[b];
            try std.testing.expect(material <= 1);
            for (batch.vertex_offset..batch.vertex_offset + batch.vertex_count) |i| {
                const pair = scene_environment.vertices[i / 2];
                const uv = if (i % 2 == 0) pair.uv_a else pair.uv_b;
                const p = if (i % 2 == 0) pair.pos_a else pair.pos_b;
                if (material == 1) {
                    try std.testing.expectEqual(enabled, 1);
                    try std.testing.expectEqual(@as(i16, 0), p[1]);
                    try std.testing.expectEqualDeep([2]i16{ p[0], p[2] }, uv);
                    try std.testing.expect(@abs(@as(i32, uv[0])) <= 4096 and @abs(@as(i32, uv[1])) <= 4096);
                } else try std.testing.expectEqualDeep([2]i16{ 0, 0 }, uv);
            }
            if (material == 1) textured_triangles += batch.index_count / 3;
        }
        try std.testing.expectEqual(enabled * 32, textured_triangles);
        for (scene_frames) |frame| for (frame) |actor| {
            for (actor[0 .. scene_rabbit.vertex_count / 2]) |pair| {
                try std.testing.expectEqualDeep([2]i16{ 0, 0 }, pair.uv_a);
                try std.testing.expectEqualDeep([2]i16{ 0, 0 }, pair.uv_b);
            }
        };
    }
}

test "optional obstacle geometry fits and obstructed cameras retain a usable basis" {
    _ = game.game_reset(0);
    _ = scene_init(0);
    const decorative_indices = scene_environment.index_count;
    _ = game.game_collision_demo(1);
    defer {
        _ = game.game_reset(0);
        _ = scene_init(0);
    }
    try std.testing.expectEqual(@as(u32, 0), scene_init(0));
    try std.testing.expectEqual(decorative_indices + game.arena.obstacles.len * 30, scene_environment.index_count);
    // Optional features coexist: solid boxes stay flat in a textured world.
    try std.testing.expectEqual(@as(u32, 0), scene_init(1));
    try std.testing.expectEqual(decorative_indices + game.arena.obstacles.len * 30, scene_environment.index_count);
    for (scene_environment.batches[0..scene_environment.batch_count], 0..) |batch, b| {
        for (batch.vertex_offset..batch.vertex_offset + batch.vertex_count) |i| {
            const pair = scene_environment.vertices[i / 2];
            const p = if (i % 2 == 0) pair.pos_a else pair.pos_b;
            if (p[1] != 0) try std.testing.expectEqual(@as(u32, 0), scene_environment_materials[b]);
        }
    }
    game.players[0].pos = .{ .x = 3 * Q };
    game.players[0].camera = 192; // Desired eye lies behind the first wall.
    _ = scene_prepare(0);
    try std.testing.expect(scene_cameras[0].eye[0] > 3 * Q and scene_cameras[0].eye[0] < 4 * Q);
    for (0..4) |port| {
        // Include an inside pivot and all four independent orbit directions.
        game.players[port].pos = .{ .x = 4 * Q + 1 };
        game.players[port].camera = @as(i32, @intCast(port)) * 64;
    }
    _ = scene_prepare(1);
    for (scene_cameras) |camera| {
        try std.testing.expect(@max(@abs(camera.eye[0] - camera.target[0]), @abs(camera.eye[2] - camera.target[2])) >= 16);
    }
}

test "packed coordinate limits report overflow in release builds as well as debug" {
    scene_overflow = 0;
    try std.testing.expectEqual(@as(i16, -32768), packedCoordinate(-32768));
    try std.testing.expectEqual(@as(i16, 32767), packedCoordinate(32767));
    try std.testing.expectEqual(@as(u32, 0), scene_overflow);
    try std.testing.expectEqual(@as(i16, 0), packedCoordinate(32768));
    try std.testing.expectEqual(@as(u32, 1), scene_overflow);
    scene_overflow = 0;
    try std.testing.expectEqual(@as(i16, 0), packedCoordinate(-32769));
    try std.testing.expectEqual(@as(u32, 1), scene_overflow);
    _ = scene_init(0);
}
