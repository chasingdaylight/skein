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
    /// the role it was given in, where the type names roles
    as: ?[]const u8 = null,
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
pub fn isCurrent(arena: std.mem.Allocator, graph: *const Graph, schema: *const Schema, approval: Approval, item: *const Item) std.mem.Allocator.Error!bool {
    return std.mem.eql(u8, approval.fingerprint, &try fingerprint.of(arena, graph, schema, item));
}

/// Records that `by` approved `item` as it is now, on `on`, in place of
/// an earlier approval by the same person
pub fn put(self: *Approvals, arena: std.mem.Allocator, graph: *const Graph, schema: *const Schema, item: *const Item, by: []const u8, on: toml.Date, as: ?[]const u8) std.mem.Allocator.Error!void {
    const fp = try arena.dupe(u8, &try fingerprint.of(arena, graph, schema, item));
    for (self.all.items) |*a| {
        if (!std.mem.eql(u8, a.item, item.id) or !std.mem.eql(u8, a.by, by)) continue;
        a.on = on;
        a.fingerprint = fp;
        a.as = as;
        return;
    }
    try self.all.append(arena, .{ .item = item.id, .by = by, .on = on, .fingerprint = fp, .as = as });
}

/// Who may approve items of `item_type` in `role` (null for the plain
/// approval of a type with no roles); empty when anyone may
pub fn approversOf(item_type: *const Schema.ItemType, role: ?[]const u8) []const []const u8 {
    if (role) |r| for (item_type.role_approvers) |ra| {
        if (std.mem.eql(u8, ra.role, r)) return ra.people;
    };
    return item_type.approvers;
}

/// Whether `approval` counts: it was given by someone who may approve
pub fn counts(item_type: *const Schema.ItemType, approval: Approval) bool {
    const who = approversOf(item_type, approval.as);
    return who.len == 0 or Schema.names.contains(who, approval.by);
}

/// How a reviewer's approval of an item of `item_type` is recorded
pub const Basis = union(enum) {
    /// the plain approval of a type with no roles
    plain,
    /// in this role
    role: []const u8,
    /// the reviewer may not approve it
    none,
};

/// How `by` approves items of `item_type`: plainly, in the first role the
/// type lets them act in, or not at all
pub fn basisOf(item_type: *const Schema.ItemType, by: []const u8) Basis {
    if (item_type.approval_roles.len == 0) {
        const who = item_type.approvers;
        return if (who.len == 0 or Schema.names.contains(who, by)) .plain else .none;
    }
    for (item_type.approval_roles) |role| {
        for (item_type.role_approvers) |ra| {
            if (std.mem.eql(u8, ra.role, role) and Schema.names.contains(ra.people, by)) return .{ .role = role };
        }
    }
    return .none;
}

/// The roles of `item_type` that have no current approval of `item`
pub fn missingRoles(self: *const Approvals, arena: std.mem.Allocator, graph: *const Graph, schema: *const Schema, item_type: *const Schema.ItemType, item: *const Item) std.mem.Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    const approvals = try self.of(arena, item.id);
    for (item_type.approval_roles) |role| {
        const has = for (approvals) |a| {
            if (a.as != null and std.mem.eql(u8, a.as.?, role) and counts(item_type, a) and try isCurrent(arena, graph, schema, a, item)) break true;
        } else false;
        if (!has) try out.append(arena, role);
    }
    return out.items;
}

/// With roles that approve in order: the first current approval given
/// before a role before it approved what the item says now; null when none was
pub fn outOfOrder(self: *const Approvals, arena: std.mem.Allocator, graph: *const Graph, schema: *const Schema, item_type: *const Schema.ItemType, item: *const Item) std.mem.Allocator.Error!?[]const u8 {
    const approvals = try self.of(arena, item.id);
    var earliest: std.ArrayList(?toml.Date) = .empty;
    for (item_type.approval_roles) |role| {
        var first: ?toml.Date = null;
        for (approvals) |a| {
            if (a.as == null or !std.mem.eql(u8, a.as.?, role) or !counts(item_type, a) or !try isCurrent(arena, graph, schema, a, item)) continue;
            if (first == null or before(a.on, first.?)) first = a.on;
        }
        try earliest.append(arena, first);
    }
    for (item_type.approval_roles, earliest.items, 0..) |role, on, i| {
        const this = on orelse continue;
        for (item_type.approval_roles[0..i], earliest.items[0..i]) |prior, prior_on| {
            if (prior_on == null) return try arena.print("approved as {s} before it was as {s}, whose approval comes first", .{ role, prior });
            if (before(this, prior_on.?)) return try arena.print("approved as {s} on {d:0>4}-{d:0>2}-{d:0>2}, before it was as {s}, whose approval comes first", .{ role, this.year, this.month, this.day, prior });
        }
    }
    return null;
}

fn before(a: toml.Date, b: toml.Date) bool {
    if (a.year != b.year) return a.year < b.year;
    if (a.month != b.month) return a.month < b.month;
    return a.day < b.day;
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
            const as: ?[]const u8 = if (record.table.get("as")) |v| (if (v == .string) v.string else return error.NotRecords) else null;
            try self.all.append(arena, .{ .item = item, .by = by, .on = on.datetime.date.?, .fingerprint = fp.string, .as = as });
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
        // every role the type names must have approved it as it is
        if (item_type.approval_roles.len > 0) {
            if (item_type.approval_in_order) if (try self.outOfOrder(arena, graph, schema, item_type, item)) |why| {
                try report.add(item.file, item.line, 1, "{s}: {s}", .{ item.id, why });
                continue;
            };
            const missing = try self.missingRoles(arena, graph, schema, item_type, item);
            if (missing.len > 0) try report.add(item.file, item.line, 1, "{s}: the status '{s}' needs an approval of what the item says now as {s} ('skein approve {s} --as ROLE')", .{ item.id, status, try std.mem.join(arena, ", ", missing), item.id });
            continue;
        }
        const approvals = try self.of(arena, item.id);
        var current = false;
        var unauthorized: ?Approval = null;
        for (approvals) |a| {
            if (!try isCurrent(arena, graph, schema, a, item)) continue;
            if (counts(item_type, a)) current = true else unauthorized = a;
        }
        if (current) continue;
        if (unauthorized) |a| {
            try report.add(item.file, item.line, 1, "{s}: the status '{s}' needs an approval by {s}; {s} approved it, who may not ('skein approve {s}')", .{ item.id, status, try std.mem.join(arena, ", ", item_type.approvers), a.by, item.id });
        } else if (approvals.len == 0) {
            try report.add(item.file, item.line, 1, "{s}: the status '{s}' needs an approval, and the item has none ('skein approve {s}')", .{ item.id, status, item.id });
        } else {
            try report.add(item.file, item.line, 1, "{s}: the item has changed since {s} approved it, and the status '{s}' needs an approval ('skein approve {s}')", .{ item.id, approvals[0].by, status, item.id });
        }
    }
}

/// The line that records `a`, of the item `id`, as the files hold it
pub fn recordLine(arena: std.mem.Allocator, id: []const u8, a: Approval) std.mem.Allocator.Error![]const u8 {
    const as = if (a.as) |r| try arena.print(", as = \"{s}\"", .{try record_files.escape(arena, r)}) else "";
    return arena.print("\"{s}\".\"{s}\" = {{ on = {d:0>4}-{d:0>2}-{d:0>2}, fingerprint = \"{s}\"{s} }}", .{
        id, try record_files.escape(arena, a.by), a.on.year, a.on.month, a.on.day, a.fingerprint, as,
    });
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
            try lines.append(arena, try arena.print("{s}\n", .{try recordLine(arena, item.id, a)}));
        }
        try record_files.write(io, arena, root, file, header, lines.items);
    }
}

test {
    _ = @import("_test/approvals.zig");
    _ = @import("_test/roles.zig");
    _ = @import("_test/approvers.zig");
    _ = @import("_test/signatures.zig");
    _ = @import("signatures.zig");
}
