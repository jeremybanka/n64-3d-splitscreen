//! Bounded Q8 arena queries. No allocation, floating point or 64-bit division.
const std = @import("std");
pub const Q: i32 = 256;
pub const coordinate_limit = 32 * Q;
pub const max_obstacles = 8;
pub const max_move = 4 * Q;
pub const fraction_one = 32768;
pub const Vec3 = struct { x: i32 = 0, y: i32 = 0, z: i32 = 0 };
pub const Aabb = struct { min: Vec3, max: Vec3 };
pub const Error = error{ OutOfRange, InvalidBox, TooManyObstacles, NoFreePosition };
pub const Hit = struct {
    // Exact entry time is numerator / denominator. The Q15 value rounds down.
    numerator: i32,
    denominator: i32,
    fraction_q15: i32,
    normal: Vec3,
    started_inside: bool,
};
pub const WorldHit = struct { obstacle: usize, hit: Hit };
pub const Move = struct { pos: Vec3, blocked_x: bool, blocked_z: bool, recovered: bool };

fn validPoint(p: Vec3) bool {
    return @abs(p.x) <= coordinate_limit and @abs(p.y) <= coordinate_limit and @abs(p.z) <= coordinate_limit;
}
fn validateBox(box: Aabb) Error!void {
    if (!validPoint(box.min) or !validPoint(box.max)) return error.OutOfRange;
    if (box.min.x > box.max.x or box.min.y > box.max.y or box.min.z > box.max.z) return error.InvalidBox;
}
fn validateWorld(boxes: []const Aabb) Error!void {
    if (boxes.len > max_obstacles) return error.TooManyObstacles;
    for (boxes) |box| try validateBox(box);
}
/// Closed boxes: touching a face, edge or point counts as overlap.
pub fn overlaps(a: Aabb, b: Aabb) Error!bool {
    try validateBox(a);
    try validateBox(b);
    return a.max.x >= b.min.x and b.max.x >= a.min.x and
        a.max.y >= b.min.y and b.max.y >= a.min.y and
        a.max.z >= b.min.z and b.max.z >= a.min.z;
}
fn greater(an: i32, ad: i32, bn: i32, bd: i32) bool {
    return @as(i64, an) * bd > @as(i64, bn) * ad;
}
fn segmentUnchecked(box: Aabb, start: Vec3, end: Vec3) ?Hit {
    const origins = [3]i32{ start.x, start.y, start.z };
    const ends = [3]i32{ end.x, end.y, end.z };
    const minimum = [3]i32{ box.min.x, box.min.y, box.min.z };
    const maximum = [3]i32{ box.max.x, box.max.y, box.max.z };
    var enter_n: i32 = 0;
    var enter_d: i32 = 1;
    var exit_n: i32 = 1;
    var exit_d: i32 = 1;
    var normal = [3]i32{ 0, 0, 0 };
    var normal_set = false;
    var inside = true;
    for (0..3) |axis| {
        const origin = origins[axis];
        inside = inside and origin > minimum[axis] and origin < maximum[axis];
        const delta = ends[axis] - origin;
        if (delta == 0) {
            if (origin < minimum[axis] or origin > maximum[axis]) return null;
            continue;
        }
        const denominator: i32 = @intCast(@abs(delta));
        const near = if (delta > 0) minimum[axis] - origin else origin - maximum[axis];
        const far = if (delta > 0) maximum[axis] - origin else origin - minimum[axis];
        if (greater(near, denominator, enter_n, enter_d) or
            (!normal_set and @as(i64, near) * enter_d == @as(i64, enter_n) * denominator))
        {
            enter_n = near;
            enter_d = denominator;
            normal = .{ 0, 0, 0 };
            normal[axis] = if (delta > 0) -1 else 1;
            normal_set = true;
        }
        if (greater(exit_n, exit_d, far, denominator)) {
            exit_n = far;
            exit_d = denominator;
        }
        if (greater(enter_n, enter_d, exit_n, exit_d)) return null;
    }
    return .{ .numerator = enter_n, .denominator = enter_d, .fraction_q15 = @divTrunc(enter_n * fraction_one, enter_d), .normal = .{ .x = normal[0], .y = normal[1], .z = normal[2] }, .started_inside = inside };
}
/// Closed finite segment [start,end]. Inside/on-boundary starts hit at t=0;
/// an inside start has a zero normal. Zero-length queries act as point tests.
/// Simultaneous entry faces prefer X, then Y, then Z. No epsilon is required.
pub fn segment(box: Aabb, start: Vec3, end: Vec3) Error!?Hit {
    try validateBox(box);
    if (!validPoint(start) or !validPoint(end)) return error.OutOfRange;
    return segmentUnchecked(box, start, end);
}
pub fn firstSegment(boxes: []const Aabb, start: Vec3, end: Vec3) Error!?WorldHit {
    try validateWorld(boxes);
    if (!validPoint(start) or !validPoint(end)) return error.OutOfRange;
    var result: ?WorldHit = null;
    for (boxes, 0..) |box, index| {
        if (segmentUnchecked(box, start, end)) |hit| {
            if (result == null or greater(result.?.hit.numerator, result.?.hit.denominator, hit.numerator, hit.denominator))
                result = .{ .obstacle = index, .hit = hit };
        }
    }
    return result;
}
fn insideXZ(p: Vec3, radius: i32, box: Aabb) bool {
    return p.x > box.min.x - radius and p.x < box.max.x + radius and
        p.z > box.min.z - radius and p.z < box.max.z + radius;
}
fn freeXZ(p: Vec3, radius: i32, bounds: Aabb, boxes: []const Aabb) bool {
    if (p.x < bounds.min.x or p.x > bounds.max.x or p.z < bounds.min.z or p.z > bounds.max.z) return false;
    for (boxes) |box| if (insideXZ(p, radius, box)) return false;
    return true;
}
fn recover(start: Vec3, radius: i32, bounds: Aabb, boxes: []const Aabb) Error!Vec3 {
    if (freeXZ(start, radius, bounds, boxes)) return start;
    // An axis-aligned free region has a vertex in this finite boundary grid.
    // Search only when recovering an invalid spawn/teleport, never during a
    // normal move. This avoids oscillation at adjacent/overlapping obstacles.
    var xs: [max_obstacles * 2 + 3]i32 = undefined;
    var zs: [max_obstacles * 2 + 3]i32 = undefined;
    xs[0..3].* = .{ std.math.clamp(start.x, bounds.min.x, bounds.max.x), bounds.min.x, bounds.max.x };
    zs[0..3].* = .{ std.math.clamp(start.z, bounds.min.z, bounds.max.z), bounds.min.z, bounds.max.z };
    for (boxes, 0..) |box, i| {
        xs[3 + i * 2] = std.math.clamp(box.min.x - radius, bounds.min.x, bounds.max.x);
        xs[4 + i * 2] = std.math.clamp(box.max.x + radius, bounds.min.x, bounds.max.x);
        zs[3 + i * 2] = std.math.clamp(box.min.z - radius, bounds.min.z, bounds.max.z);
        zs[4 + i * 2] = std.math.clamp(box.max.z + radius, bounds.min.z, bounds.max.z);
    }
    var best: ?Vec3 = null;
    var distance: i64 = std.math.maxInt(i64);
    for (xs[0 .. boxes.len * 2 + 3]) |x| for (zs[0 .. boxes.len * 2 + 3]) |z| {
        const candidate = Vec3{ .x = x, .y = start.y, .z = z };
        if (!freeXZ(candidate, radius, bounds, boxes)) continue;
        const dx: i64 = x - start.x;
        const dz: i64 = z - start.z;
        const d = dx * dx + dz * dz;
        if (d < distance) {
            best = candidate;
            distance = d;
        }
    };
    return best orelse error.NoFreePosition;
}
fn sweepAxis(p: Vec3, delta: i32, radius: i32, bounds: Aabb, boxes: []const Aabb, comptime x_axis: bool) i32 {
    const origin = if (x_axis) p.x else p.z;
    const other = if (x_axis) p.z else p.x;
    var next = std.math.clamp(origin + delta, if (x_axis) bounds.min.x else bounds.min.z, if (x_axis) bounds.max.x else bounds.max.z);
    for (boxes) |box| {
        const low = (if (x_axis) box.min.x else box.min.z) - radius;
        const high = (if (x_axis) box.max.x else box.max.z) + radius;
        const other_low = (if (x_axis) box.min.z else box.min.x) - radius;
        const other_high = (if (x_axis) box.max.z else box.max.x) + radius;
        // Tangential contact is legal: movement forbids positive penetration.
        if (other <= other_low or other >= other_high) continue;
        if (delta > 0 and origin <= low and next > low) next = @min(next, low);
        if (delta < 0 and origin >= high and next < high) next = @max(next, high);
    }
    return next;
}
/// Move a square footprint among static vertical columns. Bounds constrain the
/// center, not its radius. Y is preserved. Each <=1/8-unit substep sweeps X then
/// Z exactly; at most 32 substeps. Touching slides; thin walls cannot be skipped.
/// Invalid starting positions recover to the nearest legal boundary-grid point.
pub fn moveXZ(start: Vec3, delta: Vec3, radius: i32, bounds: Aabb, boxes: []const Aabb) Error!Move {
    try validateWorld(boxes);
    try validateBox(bounds);
    if (!validPoint(start) or radius < 0 or radius > Q or delta.y != 0 or @abs(delta.x) > max_move or @abs(delta.z) > max_move) return error.OutOfRange;
    for (boxes) |box| if (box.min.x == box.max.x or box.min.z == box.max.z) return error.InvalidBox;
    var p = try recover(start, radius, bounds, boxes);
    const recovered = p.x != start.x or p.z != start.z;
    const steps: i32 = @intCast(@max(1, (@max(@abs(delta.x), @abs(delta.z)) + 31) / 32));
    var blocked_x = false;
    var blocked_z = false;
    var i: i32 = 0;
    while (i < steps) : (i += 1) {
        const dx = @divTrunc(delta.x * (i + 1), steps) - @divTrunc(delta.x * i, steps);
        const dz = @divTrunc(delta.z * (i + 1), steps) - @divTrunc(delta.z * i, steps);
        const x = sweepAxis(p, dx, radius, bounds, boxes, true);
        blocked_x = blocked_x or x != p.x + dx;
        p.x = x;
        const z = sweepAxis(p, dz, radius, bounds, boxes, false);
        blocked_z = blocked_z or z != p.z + dz;
        p.z = z;
    }
    return .{ .pos = p, .blocked_x = blocked_x, .blocked_z = blocked_z, .recovered = recovered };
}

const test_box = Aabb{ .min = .{ .x = Q, .y = -Q, .z = -Q }, .max = .{ .x = 2 * Q, .y = Q, .z = Q } };
const test_bounds = Aabb{ .min = .{ .x = -8 * Q, .y = -8 * Q, .z = -8 * Q }, .max = .{ .x = 8 * Q, .y = 8 * Q, .z = 8 * Q } };

test "closed overlap and segment contact, tangent, parallel and reverse direction" {
    var touching = test_box;
    touching.min.x = 2 * Q;
    touching.max.x = 3 * Q;
    try std.testing.expect(try overlaps(test_box, touching));
    touching.min.x += 1;
    try std.testing.expect(!try overlaps(test_box, touching));
    const hit = (try segment(test_box, .{}, .{ .x = 4 * Q })).?;
    try std.testing.expectEqual(@as(i32, fraction_one / 4), hit.fraction_q15);
    try std.testing.expectEqual(@as(i32, -1), hit.normal.x);
    try std.testing.expectEqual(@as(i32, 1), (try segment(test_box, .{ .x = 4 * Q }, .{})).?.normal.x);
    try std.testing.expect((try segment(test_box, .{}, .{ .x = Q })) != null);
    try std.testing.expect((try segment(test_box, .{ .z = Q }, .{ .x = 4 * Q, .z = Q })) != null);
    try std.testing.expect((try segment(test_box, .{ .z = Q + 1 }, .{ .x = 4 * Q, .z = Q + 1 })) == null);
    try std.testing.expect((try segment(test_box, .{}, .{ .y = Q })) == null);
}

test "inside, boundary and zero-length segments are defined without division by zero" {
    const inside = (try segment(test_box, .{ .x = Q + 1 }, .{ .x = Q + 1 })).?;
    try std.testing.expect(inside.started_inside);
    try std.testing.expectEqual(@as(i32, 0), inside.fraction_q15);
    try std.testing.expectEqualDeep(Vec3{}, inside.normal);
    const boundary = (try segment(test_box, .{ .x = Q }, .{})).?;
    try std.testing.expect(!boundary.started_inside);
    try std.testing.expectEqual(@as(i32, 0), boundary.fraction_q15);
    try std.testing.expect((try segment(test_box, .{}, .{})) == null);
    const point = Aabb{ .min = .{}, .max = .{} };
    try std.testing.expect((try segment(point, .{ .x = -coordinate_limit }, .{ .x = coordinate_limit })) != null);
    try std.testing.expectError(error.OutOfRange, segment(point, .{}, .{ .x = coordinate_limit + 1 }));
    try std.testing.expectError(error.InvalidBox, overlaps(.{ .min = .{ .x = 1 }, .max = .{} }, point));
}

test "nearest segment preserves exact ordering and stable obstacle ties" {
    const boxes = [_]Aabb{ .{ .min = .{ .x = 400 }, .max = .{ .x = 401, .y = 1, .z = 1 } }, .{ .min = .{ .x = 399 }, .max = .{ .x = 400, .y = 1, .z = 1 } } };
    try std.testing.expectEqual(@as(usize, 1), (try firstSegment(&boxes, .{}, .{ .x = coordinate_limit })).?.obstacle);
    try std.testing.expectEqual(@as(usize, 0), (try firstSegment(&.{ test_box, test_box }, .{}, .{ .x = 4 * Q })).?.obstacle);
    try std.testing.expectError(error.TooManyObstacles, firstSegment(&(.{test_box} ** (max_obstacles + 1)), .{}, .{}));
}

test "swept footprint stops at a one-tick wall, slides, and can move away from contact" {
    var thin = test_box;
    thin.max.x = thin.min.x + 1;
    const stopped = try moveXZ(.{}, .{ .x = max_move }, 64, test_bounds, &.{thin});
    try std.testing.expectEqual(@as(i32, Q - 64), stopped.pos.x);
    try std.testing.expect(stopped.blocked_x);
    const sliding = try moveXZ(stopped.pos, .{ .x = Q, .z = Q / 2 }, 64, test_bounds, &.{thin});
    try std.testing.expectEqual(stopped.pos.x, sliding.pos.x);
    try std.testing.expectEqual(@as(i32, Q / 2), sliding.pos.z);
    const away = try moveXZ(sliding.pos, .{ .x = -Q }, 64, test_bounds, &.{thin});
    try std.testing.expectEqual(sliding.pos.x - Q, away.pos.x);
    try std.testing.expectError(error.OutOfRange, moveXZ(.{}, .{ .x = max_move + 1 }, 64, test_bounds, &.{thin}));
}

test "world corners, adjoining obstacles and inside-spawn recovery remain legal" {
    const edge = try moveXZ(.{ .x = 8 * Q - 1, .z = 8 * Q - 1 }, .{ .x = Q, .z = Q }, 64, test_bounds, &.{});
    try std.testing.expectEqual(@as(i32, 8 * Q), edge.pos.x);
    try std.testing.expectEqual(@as(i32, 8 * Q), edge.pos.z);
    var side = test_box;
    side.min.z = Q;
    side.max.z = 2 * Q;
    side.min.x = 0;
    const boxes = [_]Aabb{ test_box, side };
    const restored = try moveXZ(.{ .x = Q + 1, .z = Q }, .{}, 64, test_bounds, &boxes);
    try std.testing.expect(restored.recovered);
    try std.testing.expect(freeXZ(restored.pos, 64, test_bounds, &boxes));
    var position = Vec3{};
    for (0..80) |_| {
        position = (try moveXZ(position, .{ .x = 22, .z = 22 }, 64, test_bounds, &boxes)).pos;
        try std.testing.expect(freeXZ(position, 64, test_bounds, &boxes));
    }
    try std.testing.expectError(error.NoFreePosition, moveXZ(.{}, .{}, 64, test_bounds, &.{test_bounds}));
}

test "bounded sweep stress remains outside thin and adjoining obstacle interiors" {
    const boxes = [_]Aabb{
        .{ .min = .{ .x = Q, .z = -2 * Q }, .max = .{ .x = Q + 1, .y = Q, .z = 2 * Q } },
        .{ .min = .{ .x = -Q, .z = 2 * Q }, .max = .{ .x = 3 * Q, .y = Q, .z = 3 * Q } },
    };
    var p = Vec3{};
    var state: u32 = 1;
    for (0..400) |_| {
        state = state *% 1664525 +% 1013904223;
        const dx = @as(i32, @intCast((state >> 8) % (2 * max_move + 1))) - max_move;
        state = state *% 1664525 +% 1013904223;
        const dz = @as(i32, @intCast((state >> 8) % (2 * max_move + 1))) - max_move;
        p = (try moveXZ(p, .{ .x = dx, .z = dz }, 75, test_bounds, &boxes)).pos;
        try std.testing.expect(freeXZ(p, 75, test_bounds, &boxes));
    }
}
