//! Explicit optional collision demo. Decorative meadow meshes do not collide.
const collision = @import("collision.zig");
const std = @import("std");
const Q = collision.Q;
const Vec3 = collision.Vec3;
pub const radius = 75;
pub const bounds = collision.Aabb{ .min = .{ .x = -13 * Q, .y = -16 * Q, .z = -13 * Q }, .max = .{ .x = 13 * Q, .y = 16 * Q, .z = 13 * Q } };
pub const obstacles = [_]collision.Aabb{
    .{ .min = .{ .x = 4 * Q, .z = -3 * Q }, .max = .{ .x = 5 * Q, .y = 4 * Q, .z = 3 * Q } },
    .{ .min = .{ .x = 4 * Q, .z = 3 * Q }, .max = .{ .x = 8 * Q, .y = 4 * Q, .z = 4 * Q } },
    .{ .min = .{ .x = -6 * Q, .z = -4 * Q }, .max = .{ .x = -4 * Q, .y = 4 * Q, .z = -2 * Q } },
};
pub const colors = [_]u32{ 0x70939dff, 0x70939dff, 0xb48866ff };

pub fn move(pos: Vec3, dx: i32, dz: i32) Vec3 {
    // A tour can request a distant point after manual movement. Approach it
    // within the supported sweep range instead of teleporting through a wall.
    return (collision.moveXZ(pos, .{ .x = std.math.clamp(dx, -collision.max_move, collision.max_move), .z = std.math.clamp(dz, -collision.max_move, collision.max_move) }, radius, bounds, &obstacles) catch unreachable).pos;
}
/// Example camera clearance: shorten the pivot-to-eye segment by 1/8 unit
/// before its first hit. null means the caller must retain a nondegenerate
/// fallback (inside pivot, zero segment, or insufficient horizontal clearance).
pub fn cameraEye(pivot: Vec3, desired: Vec3) ?Vec3 {
    const obstruction = collision.firstSegment(&obstacles, pivot, desired) catch return null;
    const dx = desired.x - pivot.x;
    const dy = desired.y - pivot.y;
    const dz = desired.z - pivot.z;
    const length: i32 = @intCast(@max(@abs(dx), @max(@abs(dy), @abs(dz))));
    if (length == 0) return null;
    const first = obstruction orelse return desired;
    if (first.hit.started_inside) return null;
    const margin = @divTrunc(32 * collision.fraction_one, length) + 1;
    const fraction = first.hit.fraction_q15 - margin;
    if (fraction <= 0) return null;
    const eye = Vec3{ .x = pivot.x + @divTrunc(dx * fraction, collision.fraction_one), .y = pivot.y + @divTrunc(dy * fraction, collision.fraction_one), .z = pivot.z + @divTrunc(dz * fraction, collision.fraction_one) };
    if (@max(@abs(eye.x - pivot.x), @abs(eye.z - pivot.z)) < 16) return null;
    return eye;
}

test "camera query shortens at a wall and rejects inside or coincident fallback" {
    const pivot = Vec3{ .x = 3 * Q, .y = 2 * Q };
    const desired = Vec3{ .x = 7 * Q, .y = 3 * Q };
    const eye = cameraEye(pivot, desired).?;
    try std.testing.expect(eye.x < 4 * Q and eye.x > pivot.x);
    try std.testing.expect((try collision.firstSegment(&obstacles, pivot, eye)) == null);
    try std.testing.expect(cameraEye(pivot, pivot) == null);
    try std.testing.expect(cameraEye(.{ .x = 4 * Q + 1, .y = 2 * Q }, desired) == null);
    try std.testing.expect(cameraEye(.{ .x = 4 * Q, .y = 2 * Q }, desired) == null);
}
