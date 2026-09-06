//! Platform-independent 2048 game engine.
//!
//! The N64 frontend calls the exported scalar-only functions at the end of this
//! file. Keeping the boundary to 32-bit integers makes it safe for the tiny ABI
//! bridge used by the libdragon frontend.

pub const Direction = enum(u32) {
    left = 0,
    right = 1,
    up = 2,
    down = 3,
};

pub const Status = enum(u32) {
    playing = 0,
    won = 1,
    lost = 2,
};

const cell_count = 16;
const side = 4;
const winning_exponent = 11; // 2^11 = 2048

pub const Game = struct {
    /// Each cell stores log2(tile value), or zero for an empty cell.
    cells: [cell_count]u8 = [_]u8{0} ** cell_count,
    score: u32 = 0,
    best: u32 = 0,
    rng: u32 = 0x2048_4E36,
    status: Status = .playing,

    pub fn reset(self: *Game, seed: u32) void {
        const previous_best = @max(self.best, self.score);
        self.* = .{
            .best = previous_best,
            .rng = if (seed == 0) 0x2048_4E36 else seed,
        };
        self.spawnTile();
        self.spawnTile();
    }

    pub fn move(self: *Game, direction: Direction) bool {
        if (self.status != .playing) return false;

        var changed = false;
        for (0..side) |line| {
            changed = self.collapseLine(direction, line) or changed;
        }

        if (!changed) {
            if (!self.canMove()) self.status = .lost;
            return false;
        }

        self.spawnTile();
        // A winning merge takes priority over game-over. If the freshly
        // spawned tile leaves no moves, the loss is reported after the player
        // chooses to continue.
        if (self.status == .playing and !self.canMove()) self.status = .lost;
        self.best = @max(self.best, self.score);
        return true;
    }

    pub fn keepPlaying(self: *Game) void {
        if (self.status == .won) self.status = .playing;
    }

    fn collapseLine(self: *Game, direction: Direction, line: usize) bool {
        var compacted = [_]u8{0} ** side;
        var compacted_len: usize = 0;
        var before = [_]u8{0} ** side;

        for (0..side) |position| {
            const value = self.cells[lineIndex(direction, line, position)];
            before[position] = value;
            if (value != 0) {
                compacted[compacted_len] = value;
                compacted_len += 1;
            }
        }

        var output = [_]u8{0} ** side;
        var read: usize = 0;
        var write: usize = 0;
        while (read < compacted_len) {
            if (read + 1 < compacted_len and compacted[read] == compacted[read + 1]) {
                const merged = compacted[read] + 1;
                output[write] = merged;
                self.score +%= tileValue(merged);
                if (merged >= winning_exponent) self.status = .won;
                read += 2;
            } else {
                output[write] = compacted[read];
                read += 1;
            }
            write += 1;
        }

        var changed = false;
        for (0..side) |position| {
            if (before[position] != output[position]) changed = true;
            self.cells[lineIndex(direction, line, position)] = output[position];
        }
        return changed;
    }

    fn spawnTile(self: *Game) void {
        var empty_count: usize = 0;
        for (self.cells) |value| {
            if (value == 0) empty_count += 1;
        }
        if (empty_count == 0) return;

        var target = @as(usize, self.random() % @as(u32, @intCast(empty_count)));
        for (&self.cells) |*value| {
            if (value.* != 0) continue;
            if (target == 0) {
                // The original game uses a 90/10 distribution for 2 and 4.
                value.* = if (self.random() % 10 == 0) 2 else 1;
                return;
            }
            target -= 1;
        }
    }

    fn random(self: *Game) u32 {
        var value = self.rng;
        value ^= value << 13;
        value ^= value >> 17;
        value ^= value << 5;
        self.rng = value;
        return value;
    }

    fn canMove(self: *const Game) bool {
        for (self.cells, 0..) |value, index| {
            if (value == 0) return true;
            const row = index / side;
            const column = index % side;
            if (column + 1 < side and value == self.cells[index + 1]) return true;
            if (row + 1 < side and value == self.cells[index + side]) return true;
        }
        return false;
    }
};

fn lineIndex(direction: Direction, line: usize, position: usize) usize {
    return switch (direction) {
        .left => line * side + position,
        .right => line * side + (side - 1 - position),
        .up => position * side + line,
        .down => (side - 1 - position) * side + line,
    };
}

fn tileValue(exponent: u8) u32 {
    if (exponent == 0) return 0;
    if (exponent >= 31) return 0x8000_0000;
    return @as(u32, 1) << @intCast(exponent);
}

var active_game = Game{};

/// Local memory primitive used when Zig lowers aggregate initialization. The
/// build renames Zig's unresolved `memset` reference to this symbol so newlib's
/// O64 implementation is never called from N32-generated code.
export fn zig_memset_impl(destination: [*]volatile u8, byte: u8, length: usize) [*]volatile u8 {
    @setRuntimeSafety(false);
    for (0..length) |index| destination[index] = byte;
    return destination;
}

export fn game_reset(seed: u32) u32 {
    active_game.reset(seed);
    return 0;
}

export fn game_move(direction: u32) u32 {
    const parsed = switch (direction) {
        0 => Direction.left,
        1 => Direction.right,
        2 => Direction.up,
        3 => Direction.down,
        else => return 0,
    };
    return @intFromBool(active_game.move(parsed));
}

export fn game_keep_playing() u32 {
    active_game.keepPlaying();
    return 0;
}

export fn game_get_cell(index: u32) u32 {
    if (index >= cell_count) return 0;
    return tileValue(active_game.cells[index]);
}

export fn game_get_score() u32 {
    return active_game.score;
}

export fn game_get_best() u32 {
    return active_game.best;
}

export fn game_get_status() u32 {
    return @intFromEnum(active_game.status);
}

test "reset starts with exactly two tiles" {
    const std = @import("std");
    var game = Game{};
    game.reset(1);
    var occupied: usize = 0;
    for (game.cells) |value| {
        if (value != 0) occupied += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), occupied);
    try std.testing.expectEqual(@as(u32, 0), game.score);
}

test "a line merges each tile only once" {
    const std = @import("std");
    var game = Game{};
    game.cells[0..4].* = .{ 1, 1, 1, 1 };
    _ = game.collapseLine(.left, 0);
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0, 0 }, game.cells[0..4]);
    try std.testing.expectEqual(@as(u32, 8), game.score);

    game.cells[0..4].* = .{ 1, 1, 1, 0 };
    game.score = 0;
    _ = game.collapseLine(.left, 0);
    try std.testing.expectEqualSlices(u8, &.{ 2, 1, 0, 0 }, game.cells[0..4]);
    try std.testing.expectEqual(@as(u32, 4), game.score);
}

test "all four directions orient lines correctly" {
    const std = @import("std");
    var game = Game{};
    game.cells = .{
        1, 0, 0, 0,
        1, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0,
    };
    _ = game.collapseLine(.down, 0);
    try std.testing.expectEqual(@as(u8, 2), game.cells[12]);

    game.cells = .{
        1, 1, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0,
    };
    _ = game.collapseLine(.right, 0);
    try std.testing.expectEqual(@as(u8, 2), game.cells[3]);
}

test "only a successful move spawns a tile" {
    const std = @import("std");
    var game = Game{ .rng = 7 };
    game.cells[0] = 1;
    try std.testing.expect(!game.move(.left));

    var occupied: usize = 0;
    for (game.cells) |value| {
        if (value != 0) occupied += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), occupied);

    try std.testing.expect(game.move(.right));
    occupied = 0;
    for (game.cells) |value| {
        if (value != 0) occupied += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), occupied);
}

test "full board without neighbors is lost" {
    const std = @import("std");
    var game = Game{};
    game.cells = .{
        1, 2, 1, 2,
        2, 1, 2, 1,
        1, 2, 1, 2,
        2, 1, 2, 1,
    };
    try std.testing.expect(!game.canMove());
    try std.testing.expect(!game.move(.left));
    try std.testing.expectEqual(Status.lost, game.status);
}

test "empty cells have value zero" {
    const std = @import("std");
    try std.testing.expectEqual(@as(u32, 0), tileValue(0));
    try std.testing.expectEqual(@as(u32, 2), tileValue(1));
}

test "creating 2048 raises the won state" {
    const std = @import("std");
    var game = Game{};
    game.cells[0..4].* = .{ 10, 10, 0, 0 };
    _ = game.collapseLine(.left, 0);
    try std.testing.expectEqual(Status.won, game.status);
    try std.testing.expectEqual(@as(u8, 11), game.cells[0]);
}
