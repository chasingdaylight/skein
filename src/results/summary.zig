//! What the results say of the project, per implementation: of the items
//! tests are expected of, how many passed, failed, or are untested.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Project = @import("../Project.zig");
const Results = @import("Results.zig");
const Schema = @import("../schema/Schema.zig");
const coverage = @import("../graph/coverage.zig");

pub const Summary = struct {
    implementation: []const u8,
    /// "cesium0 0.3.1"
    label: []const u8,
    total: usize = 0,
    passed: usize = 0,
    failed: []const []const u8 = &.{},
    untested: []const []const u8 = &.{},
};

/// One summary per implementation, over the items that a citation set
/// expects to be cited (its `to` types, or any type), and those that have
/// results; removed items, and items outside `profile`, are not counted
pub fn compute(arena: std.mem.Allocator, results: *const Results, idx: *const Results.Index, project: *const Project, graph: *const Graph, profile: ?*const Schema.Profile) ![]const Summary {
    var counted: std.ArrayList(*const Graph.Item) = .empty;
    for (graph.items) |*item| {
        const item_type = project.schema.itemType(item.type_name) orelse continue;
        if (item.isTombstone(item_type)) continue;
        if (profile) |p| if (!coverage.inProfile(p, item, item_type)) continue;
        const expected = for (project.citations) |set| {
            if (set.expected and (set.to.len == 0 or Schema.names.contains(set.to, item.type_name))) break true;
        } else false;
        if (expected or idx.by_item.contains(item.id)) try counted.append(arena, item);
    }
    var out: std.ArrayList(Summary) = .empty;
    for (try results.implementations(arena)) |implementation| {
        var s: Summary = .{ .implementation = implementation, .label = try results.implementationName(arena, implementation), .total = counted.items.len };
        var failed: std.ArrayList([]const u8) = .empty;
        var untested: std.ArrayList([]const u8) = .empty;
        for (counted.items) |item| switch (results.verdict(idx, item.id, implementation)) {
            .passed => s.passed += 1,
            .failed => try failed.append(arena, item.id),
            .untested => try untested.append(arena, item.id),
        };
        s.failed = failed.items;
        s.untested = untested.items;
        try out.append(arena, s);
    }
    return out.items;
}
