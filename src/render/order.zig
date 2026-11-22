//! The order a source's item files are rendered in: by the value of an
//! attribute (`order_by`), such as Doorstop's `level`, compared as dotted
//! numbers part by part (`2.10` after `2.9`); files whose item has no
//! value come last, by path.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");

/// `paths` in the order of the attribute `attribute` of their items
pub fn sortFiles(arena: std.mem.Allocator, graph: *const Graph, paths: []const []const u8, attribute: []const u8) std.mem.Allocator.Error![]const []const u8 {
    const Entry = struct { path: []const u8, key: ?[]const u8 };
    const entries = try arena.alloc(Entry, paths.len);
    for (paths, entries) |path, *e| {
        e.* = .{ .path = path, .key = null };
        for (graph.items) |*item| {
            if (std.mem.eql(u8, item.file, path)) {
                e.key = item.attribute(attribute);
                break;
            }
        }
    }
    std.mem.sort(Entry, entries, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            const ka = a.key orelse return if (b.key != null) false else std.mem.lessThan(u8, a.path, b.path);
            const kb = b.key orelse return true;
            return switch (compare(ka, kb)) {
                .lt => true,
                .gt => false,
                .eq => std.mem.lessThan(u8, a.path, b.path),
            };
        }
    }.lt);
    const out = try arena.alloc([]const u8, paths.len);
    for (entries, out) |e, *o| o.* = e.path;
    return out;
}

/// Dotted values compared part by part: numbers as numbers, other parts
/// as text
pub fn compare(a: []const u8, b: []const u8) std.math.Order {
    var pa = std.mem.splitScalar(u8, a, '.');
    var pb = std.mem.splitScalar(u8, b, '.');
    while (true) {
        const x = pa.next();
        const y = pb.next();
        if (x == null and y == null) return .eq;
        const xs = x orelse return .lt;
        const ys = y orelse return .gt;
        const xn = std.fmt.parseInt(u64, xs, 10) catch null;
        const yn = std.fmt.parseInt(u64, ys, 10) catch null;
        const order = if (xn != null and yn != null) std.math.order(xn.?, yn.?) else std.mem.order(u8, xs, ys);
        if (order != .eq) return order;
    }
}

// req: render.order
test compare {
    const testing = std.testing;
    try testing.expectEqual(.lt, compare("2.9", "2.10"));
    try testing.expectEqual(.lt, compare("1", "1.1"));
    try testing.expectEqual(.gt, compare("3", "2.10.1"));
    try testing.expectEqual(.eq, compare("1.2", "1.2"));
    try testing.expectEqual(.lt, compare("1.a", "1.b"));
}
