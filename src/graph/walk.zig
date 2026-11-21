//! Following links through the graph. A link points up: from an item to
//! what it rests on (a test to the rule it verifies, a requirement to the
//! one it refines). So "above" an item is what its links lead to, and
//! "below" it is what leads to it.

const std = @import("std");

const Graph = @import("Graph.zig");
const Item = @import("Item.zig");

pub const Incoming = Graph.Incoming;

/// The links that point to `id`, in the order of the items
pub fn incoming(_: std.mem.Allocator, graph: *const Graph, id: []const u8) std.mem.Allocator.Error![]const Incoming {
    return if (graph.incoming.get(id)) |list| list.items else &.{};
}

/// The IDs of the items whose text refers to `id`, each once
pub fn referencedBy(_: std.mem.Allocator, graph: *const Graph, id: []const u8) std.mem.Allocator.Error![]const []const u8 {
    return if (graph.referrers.get(id)) |list| list.items else &.{};
}

pub const Direction = enum { above, below };

/// Every item that can be reached from `id` by following links one way,
/// nearest first, each once; `id` itself is not among them. Links to
/// items that do not exist are passed over.
pub fn reach(arena: std.mem.Allocator, graph: *const Graph, id: []const u8, direction: Direction) std.mem.Allocator.Error![]const []const u8 {
    var seen: std.array_hash_map.String(void) = .empty;
    try seen.put(arena, id, {});
    // the map keeps the order of discovery, so it is the queue too
    var at: usize = 0;
    while (at < seen.count()) : (at += 1) {
        const current = seen.keys()[at];
        switch (direction) {
            .above => {
                const item = graph.find(current) orelse continue;
                for (item.links) |link| {
                    if (graph.find(link.target) != null) try seen.put(arena, link.target, {});
                }
            },
            .below => for (try incoming(arena, graph, current)) |in| try seen.put(arena, in.from.id, {}),
        }
    }
    return seen.keys()[1..];
}

// req: trace.closure
const testing = std.testing;

test "above and below, through several links and around a loop" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report: @import("../Report.zig") = .{ .arena = a };
    // test -> srs.2 -> srs.1 -> need; srs.1 <-> srs.3 (a loop); lone
    const items = [_]Item{
        .{ .id = "need", .type_name = "t", .file = "f", .line = 1 },
        .{ .id = "srs.1", .type_name = "t", .file = "f", .line = 2, .links = &.{ .{ .type_name = "l", .target = "need" }, .{ .type_name = "l", .target = "srs.3" } } },
        .{ .id = "srs.2", .type_name = "t", .file = "f", .line = 3, .links = &.{ .{ .type_name = "l", .target = "srs.1" }, .{ .type_name = "l", .target = "gone" } }, .references = &.{.{ .target = "need", .line = 3, .column = 1 }} },
        .{ .id = "srs.3", .type_name = "t", .file = "f", .line = 4, .links = &.{.{ .type_name = "l", .target = "srs.1" }} },
        .{ .id = "test", .type_name = "t", .file = "f", .line = 5, .links = &.{.{ .type_name = "l", .target = "srs.2" }} },
        .{ .id = "lone", .type_name = "t", .file = "f", .line = 6 },
    };
    const graph = try Graph.init(a, &items, &report);

    const above = try reach(a, &graph, "test", .above);
    try testing.expectEqual(4, above.len);
    try testing.expectEqualStrings("srs.2", above[0]);
    try testing.expectEqualStrings("srs.1", above[1]);
    try testing.expectEqualStrings("need", above[2]);
    try testing.expectEqualStrings("srs.3", above[3]);

    const below = try reach(a, &graph, "need", .below);
    try testing.expectEqual(4, below.len);
    try testing.expectEqualStrings("srs.1", below[0]);
    try testing.expectEqualStrings("srs.2", below[1]);
    try testing.expectEqualStrings("srs.3", below[2]);
    try testing.expectEqualStrings("test", below[3]);

    try testing.expectEqual(0, (try reach(a, &graph, "lone", .above)).len);
    try testing.expectEqual(0, (try reach(a, &graph, "lone", .below)).len);
    try testing.expectEqual(2, (try incoming(a, &graph, "srs.1")).len);
    try testing.expectEqualStrings("srs.2", (try referencedBy(a, &graph, "need"))[0]);
}
