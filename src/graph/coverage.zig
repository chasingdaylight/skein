//! Coverage: of the items that should be linked to or cited, how many
//! are. What should be is what the schema marks `expected = true`: a link
//! type (every item of its `to` types should be pointed to by one) or a
//! citation set (every item of its `to` types should be cited by it).
//! Removed items are never counted. An item with parts is also covered
//! when every one of its parts is.

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
    /// the items a waiver excuses: in neither count
    waived: []const []const u8 = &.{},

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
        const has = for (condition.values) |v| {
            if (item.hasValue(condition.attribute, v)) break true;
        } else false;
        if (!has) return false;
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
            try out.append(arena, try count(arena, .link, link_type.name, item_type, link_type.to, &project.schema, graph, citations, profile));
        }
    }
    for (project.citations) |set| {
        if (!set.expected) continue;
        for (project.schema.types) |*item_type| {
            if (set.to.len > 0 and !Schema.names.contains(set.to, item_type.name)) continue;
            try out.append(arena, try count(arena, .citation, set.name, item_type, set.to, &project.schema, graph, citations, profile));
        }
    }
    return out.items;
}

fn count(
    arena: std.mem.Allocator,
    kind: Expectation.Kind,
    name: []const u8,
    item_type: *const Schema.ItemType,
    to: []const []const u8,
    schema: *const Schema,
    graph: *const Graph,
    citations: *const Graph.Citations,
    profile: ?*const Schema.Profile,
) Error!Expectation {
    var out: Expectation = .{ .kind = kind, .name = name, .item_type = item_type.name };
    const categories = try arena.alloc(Category, item_type.categories.len);
    for (categories, item_type.categories) |*c, category_name| c.* = .{ .name = category_name };
    var uncovered: std.ArrayList([]const u8) = .empty;
    var waived: std.ArrayList([]const u8) = .empty;

    for (graph.items) |*item| {
        if (!std.mem.eql(u8, item.type_name, item_type.name) or item.isTombstone(item_type)) continue;
        if (profile) |p| {
            if (!inProfile(p, item, item_type)) continue;
        }
        // waived: neither covered nor not
        if (kind == .link and excusedBy(schema, graph, item.id, name) != null) {
            try waived.append(arena, item.id);
            continue;
        }
        const covered = isCovered(.{ .kind = kind, .name = name, .to = to, .schema = schema, .graph = graph, .citations = citations }, item);
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
    out.waived = waived.items;
    return out;
}

/// One expectation, as `isCovered` needs it
const Wanted = struct {
    kind: Expectation.Kind,
    name: []const u8,
    /// the item types it is expected of; all when empty
    to: []const []const u8,
    schema: *const Schema,
    graph: *const Graph,
    citations: *const Graph.Citations,
};

/// Whether `item` is covered: it is linked to or cited itself, or it has
/// parts the expectation applies to and each of them is covered. Removed
/// parts do not count.
fn isCovered(wanted: Wanted, item: *const Item) bool {
    const direct = switch (wanted.kind) {
        .link => hasIncoming(wanted.schema, wanted.graph, item.id, wanted.name),
        .citation => hasCitation(wanted.citations, item.id, wanted.name),
    };
    if (direct) return true;
    var counted: usize = 0;
    for (item.parts) |id| {
        const part = wanted.graph.find(id) orelse continue;
        const part_type = wanted.schema.itemType(part.type_name) orelse continue;
        if (part.isTombstone(part_type)) continue;
        if (wanted.to.len > 0 and !Schema.names.contains(wanted.to, part.type_name)) continue;
        if (!isCovered(wanted, part)) return false;
        counted += 1;
    }
    return counted > 0;
}

/// Whether `id` has a link of `link_type` pointing to it, or one of a type
/// that counts as it, from a waiver in force
fn hasIncoming(schema: *const Schema, graph: *const Graph, id: []const u8, link_type: []const u8) bool {
    const list = graph.incoming.get(id) orelse return false;
    for (list.items) |in| {
        if (std.mem.eql(u8, in.link.type_name, link_type)) return true;
        const t = schema.linkType(in.link.type_name) orelse continue;
        const as = t.counts_as orelse continue;
        if (std.mem.eql(u8, as, link_type) and inForce(schema, in.from)) return true;
    }
    return false;
}

/// The item that excuses `id` from the expectation of `link_type`, by a
/// link of a type that `excuses` it; null when none does
pub fn excusedBy(schema: *const Schema, graph: *const Graph, id: []const u8, link_type: []const u8) ?*const Item {
    const list = graph.incoming.get(id) orelse return null;
    for (list.items) |in| {
        const t = schema.linkType(in.link.type_name) orelse continue;
        const excuses = t.excuses orelse continue;
        if (std.mem.eql(u8, excuses, link_type) and inForce(schema, in.from)) return in.from;
    }
    return null;
}

/// Whether a waiver counts: not removed, and approved when its type asks
/// for approval (a status that needs one, which `check` holds it to)
fn inForce(schema: *const Schema, waiver: *const Item) bool {
    const t = schema.itemType(waiver.type_name) orelse return false;
    if (waiver.isTombstone(t)) return false;
    return t.approval.len == 0 or Schema.names.contains(t.approval, waiver.effectiveStatus(t));
}

fn hasCitation(citations: *const Graph.Citations, id: []const u8, set: []const u8) bool {
    const list = citations.by_target.get(id) orelse return false;
    for (list.items) |c| {
        if (std.mem.eql(u8, c.set, set)) return true;
    }
    return false;
}

test {
    _ = @import("_test/coverage.zig");
    _ = @import("_test/waivers.zig");
    _ = @import("_test/lists.zig");
}
