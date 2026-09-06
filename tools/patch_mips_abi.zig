//! Re-label a Zig-produced MIPS N32 ELF object as O64 for the GNU linker.
//!
//! The exported game API intentionally uses only zero/one 32-bit scalar
//! arguments and 32-bit scalar results, whose register placement is identical
//! across this bridge. No structs, pointers, floats, varargs, or stack arguments
//! may cross it. See docs/architecture.md.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);
    if (args.len != 2) return error.ExpectedElfPath;

    const path = args[1];
    var file = try std.Io.Dir.cwd().openFile(init.io, path, .{ .mode = .read_write });
    defer file.close(init.io);

    var header: [52]u8 = undefined;
    _ = try file.readPositionalAll(init.io, &header, 0);
    if (!std.mem.eql(u8, header[0..4], "\x7fELF")) return error.NotElf;
    if (header[4] != 1) return error.NotElf32;
    if (header[5] != 2) return error.NotBigEndian;
    if (header[18] != 0 or header[19] != 8) return error.NotMips;

    // EF_MIPS_ABI2 (N32) is 0x20; O64 is encoded by EF_MIPS_ABI_O64
    // (0x00002000). Zig's N32 object is statically addressed, so clear the
    // metadata bits for PIC/CPIC and 32-bit register mode as well.
    var flags = std.mem.readInt(u32, header[36..40], .big);
    flags &= ~@as(u32, 0x0000_F000);
    flags &= ~@as(u32, 0x0000_0020);
    flags &= ~@as(u32, 0x0000_0106);
    flags |= 0x0000_2000;
    std.mem.writeInt(u32, header[36..40], flags, .big);
    _ = try file.writePositionalAll(init.io, &header, 0);

    // The C side uses O64's double-precision convention. The engine contains
    // no floating-point values or operations, so normalize this byte as part
    // of keeping GNU ld's ABI merger deterministic.
    const section_header_offset = std.mem.readInt(u32, header[32..36], .big);
    const section_header_size = std.mem.readInt(u16, header[46..48], .big);
    const section_count = std.mem.readInt(u16, header[48..50], .big);
    if (section_header_size < 40) return error.InvalidSectionHeaders;

    for (0..section_count) |index| {
        var section: [40]u8 = undefined;
        const offset = section_header_offset + @as(u32, @intCast(index * section_header_size));
        _ = try file.readPositionalAll(init.io, &section, offset);
        const section_type = std.mem.readInt(u32, section[4..8], .big);
        if (section_type != 0x7000_002A) continue; // SHT_MIPS_ABIFLAGS

        const contents_offset = std.mem.readInt(u32, section[16..20], .big);
        const contents_size = std.mem.readInt(u32, section[20..24], .big);
        if (contents_size < 24) return error.InvalidMipsAbiFlags;
        var abi_flags: [24]u8 = undefined;
        _ = try file.readPositionalAll(init.io, &abi_flags, contents_offset);
        abi_flags[7] = 1; // Val_GNU_MIPS_ABI_FP_DOUBLE
        _ = try file.writePositionalAll(init.io, &abi_flags, contents_offset);
        return;
    }

    return error.MissingMipsAbiFlags;
}
