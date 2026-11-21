//! Coverage: of the items that should be linked to or cited, how many
//! are. What should be is what the schema marks `expected = true`: a link
//! type (every item of its `to` types should be pointed to by one) or a
//! citation set (every item of its `to` types should be cited by it).
//! Removed items are never counted.

const std = @import("std");

const Graph = @import("Graph.zig");
const Item = @import("Item.zig");
const Project = @import("../Project.zig");
const Schema = @import("../schema/Schema.zig");

pub const Error = std.mem.Allocator.Error;

/// One thing expected of the items of one type
pub const Expectation = struct {
    kind: Kind,
    /// the link type or the citation set
    name: []const u8,
    item_type: []const u8,
    total: usize = 0,
    covered: usize = 0,
    /// the same per category, when the type has categories
    categories: []const Category = &.{},
    /// the items that are not covered, in order
    uncovered: []const []const u8 = &.{},

    pub const Kind = enum { link, citation };
};

pub const Category = struct {
    name: []const u8,
    total: usize = 0,
    covered: usize = 0,
};

/// Whether `item` is in `profile`: it passes every condition the profile
/// gives
pub fn inProfile(profile: *const Schema.Profile, item: *const Item, item_type: *const Schema.ItemType) bool {
    const names = Schema.names;
    if (profile.types.len > 0 and !names.contains(profile.types, item.type_name)) return false;
    if (profile.categories.len > 0 and !names.contains(profile.categories, item.category orelse "")) return false;
    if (profile.statuses.len > 0 and !names.contains(profile.statuses, item.effectiveStatus(item_type))) return false;
    for (profile.where) |condition| {
        if (!names.contains(condition.values, item.attribute(condition.attribute) orelse "")) return false;
    }
    return true;
}

/// Every expectation of the project, counted over its items, or over
/// those of `profile` when one is given. In the order of the schema:
/// link types, then citation sets, each by item type.
pub fn compute(
    arena: std.mem.Allocator,
    project: *const Project,
    graph: *const Graph,
    citations: *const Graph.Citations,
    profile: ?*const Schema.Profile,
) Error![]const Expectation {
    var out: std.ArrayList(Expectation) = .empty;
    for (project.schema.links) |link_type| {
        if (!link_type.expected) continue;
        for (project.schema.types) |*item_type| {
            if (link_type.to.len > 0 and !Schema.names.contains(link_type.to, item_type.name)) continue;
            try out.append(arena, try count(arena, .link, link_type.name, item_type, graph, citations, profile));
        }
    }
    for (project.citations) |set| {
        if (!set.expected) continue;
        for (project.schema.types) |*item_type| {
            if (set.to.len > 0 and !Schema.names.contains(set.to, item_type.name)) continue;
            try out.append(arena, try count(arena, .citation, set.name, item_type, graph, citations, profile));
        }
    }
    return out.items;
}

fn count(
    arena: std.mem.Allocator,
    kind: Expectation.Kind,
    name: []const u8,
    item_type: *const Schema.ItemType,
    graph: *const Graph,
    citations: *const Graph.Citations,
    profile: ?*const Schema.Profile,
) Error!Expectation {
    var out: Expectation = .{ .kind = kind, .name = name, .item_type = item_type.name };
    const categories = try arena.alloc(Category, item_type.categories.len);
    for (categories, item_type.categories) |*c, category_name| c.* = .{ .name = category_name };
    var uncovered: std.ArrayList([]const u8) = .empty;

    for (graph.items) |*item| {
        if (!std.mem.eql(u8, item.type_name, item_type.name) or item.isTombstone(item_type)) continue;
        if (profile) |p| {
            if (!inProfile(p, item, item_type)) continue;
        }
        const covered = switch (kind) {
            .link => hasIncoming(graph, item.id, name),
            .citation => hasCitation(citations, item.id, name),
        };
        out.total += 1;
        if (covered) out.covered += 1 else try uncovered.append(arena, item.id);
        for (categories) |*c| {
            if (!std.mem.eql(u8, c.name, item.category orelse "")) continue;
            c.total += 1;
            if (covered) c.covered += 1;
        }
    }
    out.categories = categories;
    out.uncovered = uncovered.items;
    return out;
}

fn hasIncoming(graph: *const Graph, id: []const u8, link_type: []const u8) bool {
    for (graph.items) |item| {
        for (item.links) |link| {
            if (std.mem.eql(u8, link.target, id) and std.mem.eql(u8, link.type_name, link_type)) return true;
        }
    }
    return false;
}

fn hasCitation(citations: *const Graph.Citations, id: []const u8, set: []const u8) bool {
    for (citations.all) |c| {
        if (std.mem.eql(u8, c.target, id) and std.mem.eql(u8, c.set, set)) return true;
    }
    return false;
}

test {
    _ = @import("_test/coverage.zig");
}
