//! A work item: an item of a type with `[planning]`, with the values of
//! its planning roles and its links that plan (predecessors, parent).

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Schema = @import("../schema/Schema.zig");
const Planning = @import("../schema/Planning.zig");
const Calendar = @import("Calendar.zig");
const day = @import("day.zig");

const Work = @This();

item: *const Item,
start: ?day.Day = null,
finish: ?day.Day = null,
duration: ?u32 = null,
/// the effort expected, in days
estimate: ?u32 = null,
lag: u32 = 0,
/// handles of the people who do it
assignees: []const []const u8 = &.{},
/// as written; null when the item names none (`mode`)
written_mode: ?[]const u8 = null,
/// the items it follows (its predecessors), by ID
after: []const []const u8 = &.{},
/// the work items it is part of, by ID
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

/// The work items of `graph`, in its order, with their planning links
pub fn collect(arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph) std.mem.Allocator.Error![]Work {
    var out: std.ArrayList(Work) = .empty;
    for (graph.items) |*item| {
        const t = schema.itemType(item.type_name) orelse continue;
        const p = t.planning orelse continue;
        if (item.isTombstone(t)) continue;
        var w: Work = .{ .item = item };
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
        try out.append(arena, w);
    }
    // links: `a precedes b` makes a a predecessor of b; `a parent b` makes b a parent of a
    var after: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty;
    for (out.items) |*w| {
        var parents: std.ArrayList([]const u8) = .empty;
        for (w.item.links) |link| {
            const role = (schema.linkType(link.type_name) orelse continue).planning orelse continue;
            const target = (graph.find(link.target) orelse graph.formerly(link.target) orelse continue).id;
            switch (role) {
                .precedes => {
                    const e = try after.getOrPut(arena, target);
                    if (!e.found_existing) e.value_ptr.* = .empty;
                    try e.value_ptr.append(arena, w.item.id);
                },
                .parent => try parents.append(arena, target),
                .blocks => {},
            }
        }
        w.parents = parents.items;
    }
    for (out.items) |*w| {
        if (after.get(w.item.id)) |l| w.after = l.items;
    }
    return out.items;
}

/// The work item `id` among `works`
pub fn find(works: []Work, id: []const u8) ?*Work {
    for (works) |*w| if (std.mem.eql(u8, w.item.id, id)) return w;
    return null;
}
