//! Jama Connect's items kept to the items (#251), for a project whose truth
//! is Skein: an item of a type `.skein/jama.toml` names gets a Jama item of
//! the type it gives (`POST items`), with its title as the name and its text
//! as the description, and is recorded in the map; one whose Jama item says
//! otherwise has it brought back (`PATCH items/ID`, JSON Patch), and is
//! reported, since someone changed it in Jama. A removed item's Jama item is
//! reported, not deleted. Each link of a type the configuration names
//! becomes a relationship between the two Jama items (`POST relationships`);
//! one in Jama that Skein has no link for is reported. Git stays the truth.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const config = @import("jama_config.zig");
const jama = @import("jama.zig");
const requirements = @import("gitlab_requirements.zig");
const text = @import("jama_text.zig");

pub const Wanted = struct {
    item: *const Graph.Item,
    /// the Jama item type
    type_id: i64,
    /// removed: its Jama item is reported
    removed: bool,
};

pub const Kind = enum { created, updated, removed, same };

pub const Done = struct { id: []const u8, kind: Kind, jama: i64 };

pub const Relationship = struct {
    from: []const u8,
    to: []const u8,
    link: []const u8,
    /// added: made in Jama; only_in_jama: Jama has it, Skein has no such link
    kind: enum { added, only_in_jama },
};

pub const Outcome = union(enum) {
    done: struct { actions: []const Done, relationships: []const Relationship, entries: []const config.Entry },
    failed: []const u8,
};

/// Brings the Jama project of `c` to `wanted`, from the map `entries`; with
/// `dry_run`, only says what it would do
pub fn publish(arena: std.mem.Allocator, client: *const jama.Client, c: config.Config, wanted: []const Wanted, entries: []const config.Entry, dry_run: bool) !Outcome {
    var map: std.StringArrayHashMapUnmanaged(i64) = .empty;
    for (entries) |e| try map.put(arena, e.id, e.jama);
    var actions: std.ArrayList(Done) = .empty;
    for (wanted) |w| {
        const name = try requirements.title(arena, w.item);
        const description = try text.html(arena, w.item.text);
        if (map.get(w.item.id)) |id| {
            const now = switch (try client.get(try arena.print("items/{d}", .{id}))) {
                .found => |v| v,
                .missing => return .{ .failed = try arena.print("{s}: Jama has no item {d}; take it out of {s}", .{ w.item.id, id, config.map_file }) },
                .failed => |why| return .{ .failed = try arena.print("{s}: {s}", .{ w.item.id, why }) },
            };
            var kind: Kind = .same;
            if (w.removed) {
                kind = .removed;
            } else {
                const now_name = jama.string(jama.field(now, &.{ "fields", "name" })) orelse "";
                const now_text = jama.string(jama.field(now, &.{ "fields", "description" })) orelse "";
                if (!std.mem.eql(u8, now_name, name) or !std.mem.eql(u8, try text.plain(arena, now_text), try text.plain(arena, description))) kind = .updated;
            }
            if (kind == .updated and !dry_run) {
                const patch = try arena.print("[{{\"op\":\"replace\",\"path\":\"/fields/name\",\"value\":{f}}},{{\"op\":\"replace\",\"path\":\"/fields/description\",\"value\":{f}}}]", .{ std.json.fmt(name, .{}), std.json.fmt(description, .{}) });
                switch (try client.send(.PATCH, try arena.print("items/{d}", .{id}), patch)) {
                    .body => {},
                    .missing => return .{ .failed = try arena.print("{s}: Jama has no item {d}", .{ w.item.id, id }) },
                    .unreachable_ => |why| return .{ .failed = try arena.print("{s}: {s}", .{ w.item.id, why }) },
                }
            }
            try actions.append(arena, .{ .id = w.item.id, .kind = kind, .jama = id });
            continue;
        }
        if (w.removed) continue;
        if (dry_run) {
            try actions.append(arena, .{ .id = w.item.id, .kind = .created, .jama = 0 });
            continue;
        }
        const location = if (c.parent) |p| try arena.print("{{\"item\":{d}}}", .{p}) else try arena.print("{{\"project\":{d}}}", .{c.project});
        const body = try arena.print("{{\"project\":{d},\"itemType\":{d},\"location\":{{\"parent\":{s}}},\"fields\":{{\"name\":{f},\"description\":{f}}}}}", .{ c.project, w.type_id, location, std.json.fmt(name, .{}), std.json.fmt(description, .{}) });
        const id = switch (try client.created("items", body)) {
            .found => |n| n,
            .missing => return .{ .failed = "Jama has no such project" },
            .failed => |why| return .{ .failed = try arena.print("{s}: {s}", .{ w.item.id, why }) },
        };
        try map.put(arena, w.item.id, id);
        try actions.append(arena, .{ .id = w.item.id, .kind = .created, .jama = id });
    }

    const relationships = switch (try links(arena, client, c, wanted, &map, dry_run)) {
        .done => |r| r,
        .failed => |why| return .{ .failed = why },
    };
    var out: std.ArrayList(config.Entry) = .empty;
    for (map.keys(), map.values()) |id, j| try out.append(arena, .{ .id = id, .jama = j });
    return .{ .done = .{ .actions = actions.items, .relationships = relationships, .entries = out.items } };
}

const Triple = struct { from: i64, to: i64, type: i64 };

/// The relationships the links of `wanted` call for, made where Jama has
/// none, and those Jama has between mapped items that no link calls for
fn links(arena: std.mem.Allocator, client: *const jama.Client, c: config.Config, wanted: []const Wanted, map: *const std.StringArrayHashMapUnmanaged(i64), dry_run: bool) !union(enum) { done: []const Relationship, failed: []const u8 } {
    var out: std.ArrayList(Relationship) = .empty;
    if (c.links.len == 0 or map.count() == 0) return .{ .done = out.items };
    var have: std.AutoHashMapUnmanaged(Triple, void) = .empty;
    const existing = switch (try client.getAll(try arena.print("relationships?project={d}", .{c.project}))) {
        .found => |l| l,
        .missing => return .{ .failed = "Jama has no such project" },
        .failed => |why| return .{ .failed = why },
    };
    for (existing) |r| {
        const t: Triple = .{
            .from = jama.integer(jama.field(r, &.{"fromItem"})) orelse continue,
            .to = jama.integer(jama.field(r, &.{"toItem"})) orelse continue,
            .type = jama.integer(jama.field(r, &.{"relationshipType"})) orelse continue,
        };
        try have.put(arena, t, {});
    }
    var called: std.AutoHashMapUnmanaged(Triple, void) = .empty;
    for (wanted) |w| {
        if (w.removed) continue;
        const source = map.get(w.item.id) orelse continue;
        for (w.item.links) |l| {
            const kind = c.link(l.type_name) orelse continue;
            const target = map.get(l.target) orelse continue;
            const t: Triple = if (kind.reverse) .{ .from = target, .to = source, .type = kind.type } else .{ .from = source, .to = target, .type = kind.type };
            try called.put(arena, t, {});
            if (have.contains(t)) continue;
            if (!dry_run) {
                const body = try arena.print("{{\"fromItem\":{d},\"toItem\":{d},\"relationshipType\":{d}}}", .{ t.from, t.to, t.type });
                switch (try client.created("relationships", body)) {
                    .found => {},
                    .missing => return .{ .failed = "Jama has no relationships to add to" },
                    .failed => |why| return .{ .failed = try arena.print("{s} {s} {s}: {s}", .{ w.item.id, l.type_name, l.target, why }) },
                }
            }
            try have.put(arena, t, {});
            try out.append(arena, .{ .from = w.item.id, .to = l.target, .link = l.type_name, .kind = .added });
        }
    }
    // in Jama, between items of the map, of a type the configuration names
    var ids: std.AutoHashMapUnmanaged(i64, []const u8) = .empty;
    for (map.keys(), map.values()) |id, j| try ids.put(arena, j, id);
    for (existing) |r| {
        const t: Triple = .{
            .from = jama.integer(jama.field(r, &.{"fromItem"})) orelse continue,
            .to = jama.integer(jama.field(r, &.{"toItem"})) orelse continue,
            .type = jama.integer(jama.field(r, &.{"relationshipType"})) orelse continue,
        };
        if (called.contains(t)) continue;
        const kind = for (c.links) |l| {
            if (l.type == t.type) break l;
        } else continue;
        const from = ids.get(t.from) orelse continue;
        const to = ids.get(t.to) orelse continue;
        try out.append(arena, if (kind.reverse)
            .{ .from = to, .to = from, .link = kind.name, .kind = .only_in_jama }
        else
            .{ .from = from, .to = to, .link = kind.name, .kind = .only_in_jama });
    }
    return .{ .done = out.items };
}
