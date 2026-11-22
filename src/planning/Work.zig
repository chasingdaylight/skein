//! A work item: an item of a type with `[planning]`, with the values of
//! its planning roles and its links that plan (predecessors, parent).
//!
//! In a planning repository (`[planning] span`) the work items of the
//! repositories it declares are among them, each known by the name of its
//! repository and its ID there (`compiler:t.parser`), and a link to such an
//! item orders work across repositories.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Network = @import("../network/Network.zig");
const Planning = @import("../schema/Planning.zig");
const Project = @import("../Project.zig");
const Schema = @import("../schema/Schema.zig");
const Calendar = @import("Calendar.zig");
const day = @import("day.zig");

const Work = @This();

item: *const Item,
/// what names it: its ID, or `repository:ID` for an item of another repository
id: []const u8,
/// the repository it is in, when not this one
repo: ?[]const u8 = null,
start: ?day.Day = null,
finish: ?day.Day = null,
duration: ?u32 = null,
/// the effort expected, in days
estimate: ?u32 = null,
lag: u32 = 0,
/// handles of the people who do it
assignees: []const []const u8 = &.{},
/// what it belongs to: the value of its `milestone` role
milestone: ?[]const u8 = null,
/// the issue on the forge that it is (`#12`)
issue: ?[]const u8 = null,
/// whether it is finished: its status is a finished one, or its issue is closed
done: bool = false,
/// when the forge says it is due: its issue's milestone's due day
forge_due: ?day.Day = null,
/// what the item writes that the forge says otherwise of: "assignees"
conflict: ?[]const u8 = null,
/// as written; null when the item names none (`mode`)
written_mode: ?[]const u8 = null,
/// the items it follows (its predecessors), by `id`
after: []const []const u8 = &.{},
/// the work items it is part of, by `id`
parents: []const []const u8 = &.{},

/// Its mode: as written, else fixed with a start and float without
pub fn mode(self: *const Work) ?Planning.Mode {
    if (self.written_mode) |m| return std.meta.stringToEnum(Planning.Mode, m);
    return if (self.start != null) .fixed else .float;
}

/// Whether its length is known: a duration, or a start and a finish
pub fn hasLength(self: *const Work) bool {
    return self.duration != null or (self.start != null and self.finish != null);
}

/// Its last day: as written, else from its start and duration; null when
/// neither is known
pub fn lastDay(self: *const Work, calendar: *const Calendar) ?day.Day {
    if (self.finish) |f| return f;
    const start = self.start orelse return null;
    return calendar.finishOf(start, self.duration orelse return null);
}

const Edges = std.StringHashMapUnmanaged(std.ArrayList([]const u8));

/// The work items of `graph`, in its order, with their planning links
pub fn collect(arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph) std.mem.Allocator.Error![]Work {
    var out: std.ArrayList(Work) = .empty;
    var after: Edges = .empty;
    try gather(arena, &out, &after, schema, graph, null, null);
    return withPredecessors(&out, &after);
}

/// As `collect`; and in a planning repository, the work items of the
/// repositories it declares too
pub fn collectAll(arena: std.mem.Allocator, project: *const Project, graph: *const Graph) std.mem.Allocator.Error![]Work {
    const network = graph.others orelse return collect(arena, &project.schema, graph);
    if (!project.planning_span) return collect(arena, &project.schema, graph);
    var out: std.ArrayList(Work) = .empty;
    var after: Edges = .empty;
    try gather(arena, &out, &after, &project.schema, graph, null, network);
    for (network.members) |*m| {
        if (m.unavailable != null) continue;
        try gather(arena, &out, &after, &m.project.schema, &m.graph, m.repository.name, network);
    }
    return withPredecessors(&out, &after);
}

fn withPredecessors(out: *std.ArrayList(Work), after: *const Edges) []Work {
    for (out.items) |*w| {
        if (after.get(w.id)) |l| w.after = l.items;
    }
    return out.items;
}

fn qualify(arena: std.mem.Allocator, repo: ?[]const u8, id: []const u8) std.mem.Allocator.Error![]const u8 {
    const name = repo orelse return id;
    return arena.print("{s}:{s}", .{ name, id });
}

/// Adds the work items of `graph` (of the repository `repo`, null for this
/// one) to `out`, and their links to `after` and their `parents`. A link of
/// this repository to an item of another that `network` resolves orders
/// work across them.
fn gather(arena: std.mem.Allocator, out: *std.ArrayList(Work), after: *Edges, schema: *const Schema, graph: *const Graph, repo: ?[]const u8, network: ?*const Network) std.mem.Allocator.Error!void {
    const first = out.items.len;
    for (graph.items) |*item| {
        const t = schema.itemType(item.type_name) orelse continue;
        const p = t.planning orelse continue;
        if (item.isTombstone(t)) continue;
        var w: Work = .{ .item = item, .id = try qualify(arena, repo, item.id), .repo = repo };
        if (p.attribute(.start)) |a| w.start = if (item.attribute(a)) |v| day.parse(v) else null;
        if (p.attribute(.finish)) |a| w.finish = if (item.attribute(a)) |v| day.parse(v) else null;
        if (p.attribute(.duration)) |a| w.duration = if (item.attribute(a)) |v| std.fmt.parseInt(u32, v, 10) catch null else null;
        if (p.attribute(.estimate)) |a| w.estimate = if (item.attribute(a)) |v| std.fmt.parseInt(u32, v, 10) catch null else null;
        if (p.attribute(.lag)) |a| w.lag = if (item.attribute(a)) |v| std.fmt.parseInt(u32, v, 10) catch 0 else 0;
        if (p.attribute(.assignees)) |a| for (item.attributes) |attr| {
            if (!std.mem.eql(u8, attr.name, a)) continue;
            w.assignees = if (attr.values.len > 0) attr.values else try arena.dupe([]const u8, &.{attr.value});
        };
        if (p.attribute(.mode)) |a| w.written_mode = item.attribute(a);
        if (p.attribute(.milestone)) |a| if (item.attribute(a)) |m| {
            // a milestone of another repository's own is named with its repository
            w.milestone = if (repo != null and std.mem.findScalar(u8, m, ':') == null) try qualify(arena, repo, m) else m;
        };
        if (p.attribute(.issue)) |a| w.issue = item.attribute(a);
        w.done = Schema.names.contains(p.doneStatuses(t.statuses, t.tombstone), item.effectiveStatus(t));
        try out.append(arena, w);
    }
    // links: `a precedes b` makes a a predecessor of b; `a parent b` makes b a parent of a
    for (out.items[first..]) |*w| {
        var parents: std.ArrayList([]const u8) = .empty;
        for (w.item.links) |link| {
            const role = (schema.linkType(link.type_name) orelse continue).planning orelse continue;
            const target = (try targetOf(arena, graph, repo, network, link.target)) orelse continue;
            switch (role) {
                .precedes => {
                    const e = try after.getOrPut(arena, target);
                    if (!e.found_existing) e.value_ptr.* = .empty;
                    try e.value_ptr.append(arena, w.id);
                },
                .parent => try parents.append(arena, target),
                .blocks => {},
            }
        }
        w.parents = parents.items;
    }
}

/// What a link's target names among the work items: its `id` here, or, for
/// an item of another repository (`name:id`) of this repository's network,
/// that
fn targetOf(arena: std.mem.Allocator, graph: *const Graph, repo: ?[]const u8, network: ?*const Network, target: []const u8) std.mem.Allocator.Error!?[]const u8 {
    if (graph.find(target) orelse graph.formerly(target)) |found| return try qualify(arena, repo, found.id);
    // only this repository's links to others place work across them
    if (repo != null) return null;
    const n = network orelse return null;
    if (Network.split(target) == null) return null;
    return switch (n.resolve(target)) {
        .item => |f| try qualify(arena, f.member.repository.name, f.item.id),
        else => null,
    };
}

/// The work item `id` among `works`
pub fn find(works: []const Work, id: []const u8) ?*const Work {
    for (works) |*w| if (std.mem.eql(u8, w.id, id)) return w;
    return null;
}
