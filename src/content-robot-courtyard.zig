//! A second content pack: replace mesh, colors, motion and scenery in Zig.
pub const character = @import("generated/robot.zig");
pub const palette = character.colors ++ [_]u32{0x6b8290ff};
pub const player_material = 1;
pub const shadow_material = palette.len - 1;
pub const bob_divisor: i32 = 32;
pub const stride_divisor: i32 = 10;
pub const sway_divisor: i32 = 64;

pub fn shadowHeight(_: i32, _: i32) i32 {
    return 10;
}

pub fn environment(comptime draw: type) void {
    const Q: i32 = 256;
    for (0..4) |iz| for (0..4) |ix| {
        draw.group();
        const x = (@as(i32, @intCast(ix)) * 8 - 16) * Q;
        const z = (@as(i32, @intCast(iz)) * 8 - 16) * Q;
        const color: u32 = if ((ix + iz) % 2 == 0) 0xa6b9c3ff else 0x94aab7ff;
        draw.groundTri(.{ .x = x, .z = z }, .{ .x = x + 8 * Q, .z = z + 8 * Q }, .{ .x = x + 8 * Q, .z = z }, color);
        draw.groundTri(.{ .x = x, .z = z }, .{ .x = x, .z = z + 8 * Q }, .{ .x = x + 8 * Q, .z = z + 8 * Q }, color);
    };
    // A four-sided beacon replaces the carrot; towers replace trees.
    draw.group();
    draw.box(0, 0, 0, 160, 160, 100, 0x647b8fff);
    draw.box(0, 0, 100, 80, 80, 360, 0xe9ca72ff);
    draw.cone(0, 0, 460, 150, 170, 0x72c7cfff);
    const towers = [8][2]i32{ .{ -11, -9 }, .{ -5, -13 }, .{ 8, -11 }, .{ 13, -3 }, .{ 10, 10 }, .{ 1, 14 }, .{ -10, 11 }, .{ -14, 1 } };
    for (towers, 0..) |p, i| {
        draw.group();
        draw.box(p[0] * Q, p[1] * Q, 0, Q, Q, 3 * Q, 0x657f97ff);
        draw.box(p[0] * Q, p[1] * Q, 3 * Q, 280, 280, 80, if (i % 2 == 0) 0x72c7cfff else 0xe9ca72ff);
    }
}
