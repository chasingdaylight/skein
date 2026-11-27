//! A URL's query, as `skein serve` reads and writes it.

const std = @import("std");

/// The value of `key` in `query` (`a=1&b=2`), decoded
pub fn param(arena: std.mem.Allocator, query: []const u8, key: []const u8) !?[]const u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        const at = std.mem.findScalar(u8, pair, '=') orelse continue;
        if (!std.mem.eql(u8, pair[0..at], key)) continue;
        const raw = try arena.dupe(u8, pair[at + 1 ..]);
        std.mem.replaceScalar(u8, raw, '+', ' ');
        return std.Uri.percentDecodeInPlace(raw);
    }
    return null;
}

/// `s` percent-encoded as a value of a query: all but the unreserved characters
pub fn escaped(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or std.mem.findScalar(u8, "-._~", c) != null) {
            try out.append(arena, c);
        } else try out.print(arena, "%{X:0>2}", .{c});
    }
    return out.items;
}

test "a value read from a query, and written into one" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("spec/a b.md", (try param(a, "x=1&file=spec%2Fa+b.md", "file")).?);
    try std.testing.expect(try param(a, "x=1", "file") == null);
    try std.testing.expectEqualStrings("https%3A%2F%2Fx.example%2F_skein", try escaped(a, "https://x.example/_skein"));
}
