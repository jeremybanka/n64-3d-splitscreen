//! Bunny Meadow sample content. Renderer and C adapter stay content-independent.
pub const character = @import("generated/rabbit.zig");
pub const palette = character.colors ++ [_]u32{0x6f9567ff};
pub const player_material = 3;
pub const shadow_material = palette.len - 1;
pub const bob_divisor: i32 = 18;
pub const stride_divisor: i32 = 7;
pub const sway_divisor: i32 = 35;

pub fn shadowHeight(x: i32, z: i32) i32 {
    return if (@abs(x) < 4 * 256 and @abs(z) < 4 * 256) 42 else 10;
}

pub fn environment(comptime draw: type) void {
    const Q: i32 = 256;
    const Vec3 = draw.Vec3;
    // Low-contrast meadow tiles make movement and perspective easy to read.
    for (0..4) |iz| for (0..4) |ix| {
        draw.group();
        const x = (@as(i32, @intCast(ix)) * 8 - 16) * Q;
        const z = (@as(i32, @intCast(iz)) * 8 - 16) * Q;
        const col: u32 = if ((ix + iz) % 2 == 0) 0x80ac79ff else 0x86b17dff;
        draw.worldTri(.{ .x = x, .z = z }, .{ .x = x + 8 * Q, .z = z + 8 * Q }, .{ .x = x + 8 * Q, .z = z }, col);
        draw.worldTri(.{ .x = x, .z = z }, .{ .x = x, .z = z + 8 * Q }, .{ .x = x + 8 * Q, .z = z + 8 * Q }, col);
    };
    draw.group();
    // A true annulus avoids overlapping coplanar grass/path discs. Its
    // small offset above the meadow is larger than RDP depth quantization.
    for (0..16) |i| {
        const a: i32 = @intCast(i * 16);
        const b = a + 16;
        const inner_a = Vec3{ .x = draw.mul(draw.sin(a), 3 * Q), .y = 32, .z = draw.mul(draw.cos(a), 3 * Q) };
        const outer_a = Vec3{ .x = draw.mul(draw.sin(a), 4 * Q), .y = 32, .z = draw.mul(draw.cos(a), 4 * Q) };
        const inner_b = Vec3{ .x = draw.mul(draw.sin(b), 3 * Q), .y = 32, .z = draw.mul(draw.cos(b), 3 * Q) };
        const outer_b = Vec3{ .x = draw.mul(draw.sin(b), 4 * Q), .y = 32, .z = draw.mul(draw.cos(b), 4 * Q) };
        draw.worldTri(inner_a, outer_a, outer_b, 0xe2cf9fff);
        draw.worldTri(inner_a, outer_b, inner_b, 0xe2cf9fff);
    }
    // Central carrot is a shared landmark, visible from every spawn camera.
    draw.group();
    draw.box(0, 0, 0, 90, 90, 45, 0xe1d9baff);
    draw.cone(0, 0, 45, 75, 380, 0xf1a05eff);
    draw.cone(-28, 0, 410, 70, 150, 0x548b63ff);
    draw.cone(45, 10, 405, 60, 120, 0x74a464ff);
    const trees = [8][2]i32{ .{ -11, -9 }, .{ -5, -13 }, .{ 8, -11 }, .{ 13, -3 }, .{ 10, 10 }, .{ 1, 14 }, .{ -10, 11 }, .{ -14, 1 } };
    for (trees, 0..) |t, i| {
        draw.group();
        const x = t[0] * Q;
        const z = t[1] * Q;
        draw.box(x, z, 0, 65, 65, 2 * Q, 0x9c7b5aff);
        draw.cone(x, z, Q, 2 * Q, 4 * Q, if (i % 2 == 0) 0x54896aff else 0x68996cff);
        draw.cone(x, z, 2 * Q, 360, 3 * Q, 0x7aaa79ff);
    }
    const stones = [6][2]i32{ .{ -7, -6 }, .{ 6, -8 }, .{ 9, 5 }, .{ -8, 5 }, .{ -4, 10 }, .{ 4, 8 } };
    for (stones, 0..) |p, i| {
        draw.group();
        draw.cone(p[0] * Q, p[1] * Q, 0, 140, 120, 0xa7b2a4ff);
        draw.box(p[0] * Q + 200, p[1] * Q + 100, 0, 25, 25, 85, 0xf4e3c6ff);
        draw.cone(p[0] * Q + 200, p[1] * Q + 100, 70, 80, 70, if (i % 2 == 0) 0xdc8b7dff else 0xe2bf6dff);
    }
    // Distant faceted mountains distinguish the views without extra assets.
    for (0..8) |i| {
        draw.group();
        const a: i32 = @intCast(i * 32);
        draw.cone(draw.mul(draw.sin(a), 30 * Q), draw.mul(draw.cos(a), 30 * Q), -Q, 8 * Q, (8 + @as(i32, @intCast(i % 3)) * 2) * Q, if (i % 2 == 0) 0x9eb8adff else 0xb2c5b5ff);
    }
}
