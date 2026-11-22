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

/// How many of the items that name one verification method are verified
pub const ByMethod = struct {
    method: []const u8,
    total: usize = 0,
    verified: usize = 0,
    unverified: []const []const u8 = &.{},
};

/// Of the items that name a verification method, how many are verified as
/// their method requires: `test` by a passing result of a test, in any
/// implementation; any other method (analysis, inspection, demonstration)
/// by a passing result that a person recorded and that is not stale. In
/// the order the methods are first named.
pub fn byMethod(arena: std.mem.Allocator, results: *const Results, idx: *const Results.Index, project: *const Project, graph: *const Graph, profile: ?*const Schema.Profile) ![]const ByMethod {
    var out: std.ArrayList(ByMethod) = .empty;
    var unverified: std.ArrayList(std.ArrayList([]const u8)) = .empty;
    const implementations = try results.implementations(arena);
    for (graph.items) |*item| {
        const method = item.verification orelse continue;
        const item_type = project.schema.itemType(item.type_name) orelse continue;
        if (item.isTombstone(item_type)) continue;
        if (profile) |p| if (!coverage.inProfile(p, item, item_type)) continue;
        const at = for (out.items, 0..) |m, i| {
            if (std.mem.eql(u8, m.method, method)) break i;
        } else blk: {
            try out.append(arena, .{ .method = method });
            try unverified.append(arena, .empty);
            break :blk out.items.len - 1;
        };
        out.items[at].total += 1;
        const verified = if (std.mem.eql(u8, method, "test")) for (implementations) |impl| {
            if (results.verdict(idx, item.id, impl) == .passed) break true;
        } else false else recorded(results, idx, item.id);
        if (verified) out.items[at].verified += 1 else try unverified.items[at].append(arena, item.id);
    }
    for (out.items, unverified.items) |*m, list| m.unverified = list.items;
    return out.items;
}

/// Whether a person recorded a passing result of `id`
fn recorded(results: *const Results, idx: *const Results.Index, id: []const u8) bool {
    const list = idx.by_item.get(id) orelse return false;
    for (list.items) |i| {
        const r = results.all[i];
        if (r.by != null and r.outcome == .pass) return true;
    }
    return false;
}

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
