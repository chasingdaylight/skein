//! Approvals: who approved which item, when, and what the item said then
//! (its fingerprint). They are kept in git, under `.skein/approvals/`
//! (record_files.zig), one line per item and approver:
//!
//!     "SRS-012"."A. Reviewer" = { on = 2027-03-01, fingerprint = "9f2c..." }
//!
//! An approval is current while the item still says what it said; a
//! change to the item leaves the record, which then shows what was
//! approved, and the item is no longer approved.

const std = @import("std");
const Io = std.Io;

const Graph = @import("Graph.zig");
const Item = @import("Item.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const fingerprint = @import("fingerprint.zig");
const record_files = @import("record_files.zig");
const toml = @import("../toml.zig");

const Approvals = @This();

pub const dir = Project.dir_name ++ "/approvals";
const header = "# Approvals, written by skein. Do not edit: use 'skein approve'.\n";

all: std.ArrayList(Approval) = .empty,

pub const Approval = struct {
    item: []const u8,
    by: []const u8,
    on: toml.Date,
    fingerprint: []const u8,
};

/// The approvals of `id`, in the order of their approvers
pub fn of(self: *const Approvals, arena: std.mem.Allocator, id: []const u8) std.mem.Allocator.Error![]const Approval {
    var out: std.ArrayList(Approval) = .empty;
    for (self.all.items) |a| {
        if (std.mem.eql(u8, a.item, id)) try out.append(arena, a);
    }
    std.mem.sort(Approval, out.items, {}, struct {
        fn lt(_: void, a: Approval, b: Approval) bool {
            return std.mem.lessThan(u8, a.by, b.by);
        }
    }.lt);
    return out.items;
}

/// Whether `approval` is of the item as it is now
pub fn isCurrent(arena: std.mem.Allocator, approval: Approval, item: *const Item, item_type: *const Schema.ItemType) std.mem.Allocator.Error!bool {
    return std.mem.eql(u8, approval.fingerprint, &try fingerprint.of(arena, item, item_type));
}

/// Records that `by` approved `item` as it is now, on `on`, in place of
/// an earlier approval by the same person
pub fn put(self: *Approvals, arena: std.mem.Allocator, item: *const Item, item_type: *const Schema.ItemType, by: []const u8, on: toml.Date) std.mem.Allocator.Error!void {
    const fp = try arena.dupe(u8, &try fingerprint.of(arena, item, item_type));
    for (self.all.items) |*a| {
        if (!std.mem.eql(u8, a.item, item.id) or !std.mem.eql(u8, a.by, by)) continue;
        a.on = on;
        a.fingerprint = fp;
        return;
    }
    try self.all.append(arena, .{ .item = item.id, .by = by, .on = on, .fingerprint = fp });
}

pub fn fileOf(arena: std.mem.Allocator, item: *const Item) ![]const u8 {
    return record_files.fileOf(arena, dir, item);
}

/// Reads every approval under `.skein/approvals/`. Files that cannot be
/// read are reported.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, report: *Report) std.mem.Allocator.Error!Approvals {
    var out: Approvals = .{};
    for (try record_files.load(io, arena, root, dir, report)) |file| {
        out.read(arena, file.table) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NotRecords => try report.add(file.path, 0, 0, "this is no file of approvals; skein writes them, with 'skein approve'", .{}),
        };
    }
    return out;
}

fn read(self: *Approvals, arena: std.mem.Allocator, table: *const toml.Table) !void {
    for (table.keys()) |item| {
        const by_approver = table.get(item).?;
        if (by_approver != .table) return error.NotRecords;
        for (by_approver.table.keys()) |by| {
            const record = by_approver.table.get(by).?;
            if (record != .table) return error.NotRecords;
            const on = record.table.get("on") orelse return error.NotRecords;
            const fp = record.table.get("fingerprint") orelse return error.NotRecords;
            if (on != .datetime or on.datetime.date == null or fp != .string) return error.NotRecords;
            try self.all.append(arena, .{ .item = item, .by = by, .on = on.datetime.date.?, .fingerprint = fp.string });
        }
    }
}

/// Reports the items whose status needs an approval (their type's
/// `approval` statuses) and that have none of what they say now.
pub fn check(self: *const Approvals, arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph, report: *Report) std.mem.Allocator.Error!void {
    for (graph.items) |*item| {
        const item_type = schema.itemType(item.type_name) orelse continue;
        const status = item.effectiveStatus(item_type);
        if (!Schema.names.contains(item_type.approval, status)) continue;
        const approvals = try self.of(arena, item.id);
        var current = false;
        for (approvals) |a| {
            if (try isCurrent(arena, a, item, item_type)) current = true;
        }
        if (current) continue;
        if (approvals.len == 0) {
            try report.add(item.file, item.line, 1, "{s}: the status '{s}' needs an approval, and the item has none ('skein approve {s}')", .{ item.id, status, item.id });
        } else {
            try report.add(item.file, item.line, 1, "{s}: the item has changed since {s} approved it, and the status '{s}' needs an approval ('skein approve {s}')", .{ item.id, approvals[0].by, status, item.id });
        }
    }
}

/// Writes the approval files named in `files` again, from the approvals
/// held: those of items that still exist.
pub fn write(self: *const Approvals, io: Io, arena: std.mem.Allocator, root: Io.Dir, graph: *const Graph, files: []const []const u8) !void {
    for (files) |file| {
        var lines: std.ArrayList([]const u8) = .empty;
        // by approval, not by item: there are far fewer
        for (self.all.items) |a| {
            const item = graph.find(a.item) orelse continue;
            if (!std.mem.eql(u8, try fileOf(arena, item), file)) continue;
            try lines.append(arena, try arena.print("\"{s}\".\"{s}\" = {{ on = {d:0>4}-{d:0>2}-{d:0>2}, fingerprint = \"{s}\" }}\n", .{
                item.id, try record_files.escape(arena, a.by), a.on.year, a.on.month, a.on.day, a.fingerprint,
            }));
        }
        try record_files.write(io, arena, root, file, header, lines.items);
    }
}

test {
    _ = @import("_test/approvals.zig");
}
