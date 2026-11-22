//! A what-if plan's overlay on what the forge holds: only the fields where
//! the plan deviates, each with the upstream value it was based on, kept in
//! `.skein/overlay.toml` (copy on write: everything else still comes from
//! the forge). One sorted line per issue and field:
//!
//!     "example/plan#12".assignees = { base = "ann", value = "bob" }
//!
//! `skein overlay` writes it, `check` reports a line whose upstream value
//! has changed since, and `skein apply` writes it to the forge and takes it
//! out.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Forge = @import("Forge.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const github = @import("github.zig");
const record_files = @import("../graph/record_files.zig");
const toml = @import("../toml.zig");
const write = @import("../toml/write.zig");

const Overlay = @This();

pub const file = Project.dir_name ++ "/overlay.toml";
const header = "# A what-if plan's deviations from the forge, written by skein. Do not edit: use 'skein overlay'.\n";

entries: std.ArrayList(Entry) = .empty,

/// What a plan can change of an issue on GitHub
pub const Field = enum { assignees, milestone, state };

pub const Entry = struct {
    /// `owner/repo#12`
    issue: []const u8,
    field: Field,
    /// what the forge said when the deviation was made
    base: []const u8,
    value: []const u8,
};

/// `target` (`#12`, `owner/repo#12`) as `owner/repo#12`; null when it names no issue
pub fn canonical(arena: Allocator, forge: *const Forge, target: []const u8) Allocator.Error!?[]const u8 {
    const r = forge.ref(target) orelse return null;
    return try arena.print("{s}#{d}", .{ r.repository, r.number });
}

pub fn load(io: Io, arena: Allocator, root: Io.Dir, report: *Report) Allocator.Error!Overlay {
    var out: Overlay = .{};
    const text = root.readFileAlloc(io, file, arena, .limited(1 << 24)) catch return out;
    var diag: toml.Diagnostic = .{};
    const table = toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => {
            try report.add(file, diag.line, diag.column, "{s}", .{diag.message});
            return out;
        },
    };
    out.read(arena, table) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.NotRecords => try report.add(file, 0, 0, "this is no overlay; skein writes it, with 'skein overlay'", .{}),
    };
    return out;
}

fn read(self: *Overlay, arena: Allocator, table: *const toml.Table) !void {
    for (table.keys()) |issue| {
        const fields = table.get(issue).?;
        if (fields != .table) return error.NotRecords;
        for (fields.table.keys()) |name| {
            const field = std.meta.stringToEnum(Field, name) orelse return error.NotRecords;
            const v = fields.table.get(name).?;
            if (v != .table) return error.NotRecords;
            const base = v.table.get("base") orelse return error.NotRecords;
            const value = v.table.get("value") orelse return error.NotRecords;
            if (base != .string or value != .string) return error.NotRecords;
            try self.entries.append(arena, .{ .issue = issue, .field = field, .base = base.string, .value = value.string });
        }
    }
}

pub fn get(self: *const Overlay, issue: []const u8, field: Field) ?*const Entry {
    for (self.entries.items) |*e| if (e.field == field and std.mem.eql(u8, e.issue, issue)) return e;
    return null;
}

/// Records a deviation, in place of one of the same issue and field
pub fn set(self: *Overlay, arena: Allocator, issue: []const u8, field: Field, base: []const u8, value: []const u8) Allocator.Error!void {
    for (self.entries.items) |*e| {
        if (e.field != field or !std.mem.eql(u8, e.issue, issue)) continue;
        e.base = base;
        e.value = value;
        return;
    }
    try self.entries.append(arena, .{ .issue = issue, .field = field, .base = base, .value = value });
}

/// Takes a deviation out; whether there was one
pub fn remove(self: *Overlay, issue: []const u8, field: Field) bool {
    for (self.entries.items, 0..) |e, i| {
        if (e.field == field and std.mem.eql(u8, e.issue, issue)) {
            _ = self.entries.orderedRemove(i);
            return true;
        }
    }
    return false;
}

/// Writes the file; with no deviations it is deleted
pub fn save(self: *const Overlay, io: Io, arena: Allocator, root: Io.Dir) !void {
    var lines: std.ArrayList([]const u8) = .empty;
    for (self.entries.items) |e| {
        try lines.append(arena, try arena.print("\"{s}\".{t} = {{ base = {s}, value = {s} }}\n", .{ try record_files.escape(arena, e.issue), e.field, try write.string(arena, e.base), try write.string(arena, e.value) }));
    }
    try record_files.write(io, arena, root, file, header, lines.items);
}

/// The value of `field` of an issue as the forge gives it, in the form an
/// overlay keeps it: assignees sorted and joined by commas, the title of the
/// milestone (empty for none), `open` or `closed`
pub fn upstream(arena: Allocator, issue: github.Issue, field: Field) Allocator.Error![]const u8 {
    return switch (field) {
        .assignees => try normalize(arena, issue.assignees),
        .milestone => issue.milestone orelse "",
        .state => if (issue.open) "open" else "closed",
    };
}

/// `logins` sorted and joined by commas
pub fn normalize(arena: Allocator, logins: []const []const u8) Allocator.Error![]const u8 {
    const sorted = try arena.dupe([]const u8, logins);
    std.mem.sort([]const u8, sorted, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return std.mem.join(arena, ",", sorted);
}

/// `text` (logins separated by commas or spaces) as a list, in the form `normalize` gives
pub fn parseLogins(arena: Allocator, text: []const u8) Allocator.Error![]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, ", ");
    while (it.next()) |w| try list.append(arena, w);
    return normalize(arena, list.items);
}

const testing = std.testing;

test "deviations are written as sorted lines and read back" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var o: Overlay = .{};
    try o.set(a, "example/plan#12", .state, "open", "closed");
    try o.set(a, "example/plan#12", .assignees, "ann", "bob,carol");
    try o.set(a, "example/plan#12", .state, "open", "closed");
    try o.save(testing.io, a, tmp.dir);
    var report: Report = .{ .arena = a };
    const again = try load(testing.io, a, tmp.dir, &report);
    try testing.expect(report.ok());
    try testing.expectEqual(2, again.entries.items.len);
    try testing.expectEqualStrings("bob,carol", again.get("example/plan#12", .assignees).?.value);
    try testing.expectEqual(null, again.get("example/plan#13", .state));
    var changed = again;
    try testing.expect(changed.remove("example/plan#12", .state));
    try testing.expect(!changed.remove("example/plan#12", .state));
    try testing.expectEqualStrings("a,b", try parseLogins(a, "b, a"));
}
