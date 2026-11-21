//! What changed between two states of a project's items, and what the
//! changes reach.

const std = @import("std");

const Graph = @import("Graph.zig");
const Item = @import("Item.zig");
const Schema = @import("../schema/Schema.zig");
const fingerprint = @import("fingerprint.zig");
const walk = @import("walk.zig");

pub const Error = std.mem.Allocator.Error;

/// One state of the project: its items and the schema they are read by
pub const Side = struct {
    graph: *const Graph,
    schema: *const Schema,
};

pub const Change = struct {
    id: []const u8,
    kind: Kind,
    type_name: []const u8,
    /// changed: what about the item is different, in words
    what: []const []const u8 = &.{},
    /// changed: whether what the item says is different (its fingerprint)
    content: bool = false,
    /// where the item is now; for a removed item, where it was
    file: []const u8,
    line: u32,

    pub const Kind = enum { added, removed, changed };

    /// Whether what rests on the item may need another look
    pub fn matters(self: Change) bool {
        return self.kind == .removed or (self.kind == .changed and self.content);
    }
};

/// The changes from `old` to `new`: added, then removed, then changed,
/// each in the order of the items. An item that became a tombstone is
/// removed; one that exists on only one side is added or removed.
pub fn compute(arena: std.mem.Allocator, old: Side, new: Side) Error![]const Change {
    var added: std.ArrayList(Change) = .empty;
    var removed: std.ArrayList(Change) = .empty;
    var changed: std.ArrayList(Change) = .empty;

    for (new.graph.items) |*item| {
        if (new.graph.find(item.id) != item) continue; // an ID used twice: its first use counts
        const gone_now = isGone(item, new.schema);
        const before = old.graph.find(item.id);
        const gone_before = if (before) |b| isGone(b, old.schema) else true;
        const change: Change = .{ .id = item.id, .kind = .changed, .type_name = item.type_name, .file = item.file, .line = item.line };
        if (gone_before and !gone_now) {
            var c = change;
            c.kind = .added;
            try added.append(arena, c);
        } else if (!gone_before and gone_now) {
            var c = change;
            c.kind = .removed;
            try removed.append(arena, c);
        } else if (!gone_before and !gone_now) {
            var c = change;
            c.what = try differences(arena, before.?, old, item, new, &c.content);
            if (c.what.len > 0) try changed.append(arena, c);
        }
    }
    for (old.graph.items) |*item| {
        if (old.graph.find(item.id) != item) continue;
        if (isGone(item, old.schema) or new.graph.find(item.id) != null) continue;
        try removed.append(arena, .{ .id = item.id, .kind = .removed, .type_name = item.type_name, .file = item.file, .line = item.line });
    }

    var out: std.ArrayList(Change) = .empty;
    try out.appendSlice(arena, added.items);
    try out.appendSlice(arena, removed.items);
    try out.appendSlice(arena, changed.items);
    return out.items;
}

fn isGone(item: *const Item, schema: *const Schema) bool {
    const item_type = schema.itemType(item.type_name) orelse return false;
    return item.isTombstone(item_type);
}

/// What is different about an item, in words; sets `content` when its
/// fingerprint is
fn differences(arena: std.mem.Allocator, a: *const Item, old: Side, b: *const Item, new: Side, content: *bool) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    const a_type = old.schema.itemType(a.type_name);
    const b_type = new.schema.itemType(b.type_name);
    if (!std.mem.eql(u8, a.type_name, b.type_name)) {
        try out.append(arena, try arena.print("type: {s} -> {s}", .{ a.type_name, b.type_name }));
    }
    if (a_type != null and b_type != null) {
        const fa = try fingerprint.of(arena, old.graph, old.schema, a);
        const fb = try fingerprint.of(arena, new.graph, new.schema, b);
        if (!std.mem.eql(u8, &fa, &fb)) {
            content.* = true;
            try out.append(arena, "content");
        }
        const sa = a.effectiveStatus(a_type.?);
        const sb = b.effectiveStatus(b_type.?);
        if (!std.mem.eql(u8, sa, sb)) try out.append(arena, try arena.print("status: {s} -> {s}", .{ sa, sb }));
    }
    if (!sameLinks(a, b)) try out.append(arena, "links");
    if (!sameAttributes(a, b)) try out.append(arena, "attributes");
    if (!std.mem.eql(u8, a.verification orelse "", b.verification orelse "")) try out.append(arena, "verification");
    return out.items;
}

fn sameLinks(a: *const Item, b: *const Item) bool {
    return hasLinksOf(a, b) and hasLinksOf(b, a);
}

fn hasLinksOf(a: *const Item, b: *const Item) bool {
    next: for (b.links) |want| {
        for (a.links) |have| {
            if (std.mem.eql(u8, have.type_name, want.type_name) and std.mem.eql(u8, have.target, want.target)) continue :next;
        }
        return false;
    }
    return true;
}

fn sameAttributes(a: *const Item, b: *const Item) bool {
    if (a.attributes.len != b.attributes.len) return false;
    for (a.attributes) |attr| {
        const other = b.attribute(attr.name) orelse return false;
        if (!std.mem.eql(u8, attr.value, other)) return false;
    }
    return true;
}

/// An item that may need another look, and the changed item that makes it so
pub const Reached = struct {
    item: *const Item,
    /// the changed or removed item it rests on, nearest first
    because: []const u8,
    /// whether it only refers to it in its text, with no link
    by_reference: bool = false,
};

/// The items of `graph` that rest on a change that matters: everything
/// below it, and the items whose text refers to it. Each item once, and
/// not the changed items themselves.
pub fn reached(arena: std.mem.Allocator, graph: *const Graph, changes: []const Change) Error![]const Reached {
    var seen: std.array_hash_map.String(void) = .empty;
    for (changes) |c| try seen.put(arena, c.id, {});
    var out: std.ArrayList(Reached) = .empty;
    for (changes) |c| {
        if (!c.matters()) continue;
        for (try walk.reach(arena, graph, c.id, .below)) |id| {
            if ((try seen.getOrPut(arena, id)).found_existing) continue;
            try out.append(arena, .{ .item = graph.find(id).?, .because = c.id });
        }
        for (try walk.referencedBy(arena, graph, c.id)) |id| {
            if ((try seen.getOrPut(arena, id)).found_existing) continue;
            try out.append(arena, .{ .item = graph.find(id).?, .because = c.id, .by_reference = true });
        }
    }
    return out.items;
}
