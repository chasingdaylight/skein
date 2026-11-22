//! Time spent on work items: who, on which day, how many hours, and a note,
//! kept in git under `.skein/time/` (record_files.zig), one line per item,
//! person and day:
//!
//!     "t.parser"."ann"."2027-03-02" = { hours = 3.5, note = "first pass" }
//!
//! skein writes them (`skein time`). Reports set what was spent against the
//! estimate of each item, in the hours of the project's calendar.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Work = @import("Work.zig");
const day = @import("day.zig");
const record_files = @import("../graph/record_files.zig");
const toml = @import("../toml.zig");

const Time = @This();

pub const dir = Project.dir_name ++ "/time";
const header = "# Time spent on work items, written by skein. Do not edit: use 'skein time'.\n";

all: std.ArrayList(Entry) = .empty,

pub const Entry = struct {
    item: []const u8,
    by: []const u8,
    /// `YYYY-MM-DD`
    on: []const u8,
    hours: f64,
    note: ?[]const u8 = null,
    /// the file it is in
    file: []const u8,
};

/// The most hours one person can log for an item on one day
pub const max_hours_a_day = 24;

/// Reads every record under `.skein/time/`; files that cannot be read are reported
pub fn load(io: Io, arena: Allocator, root: Io.Dir, report: *Report) Allocator.Error!Time {
    var out: Time = .{};
    for (try record_files.load(io, arena, root, dir, report)) |file| {
        out.read(arena, file.path, file.table) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NotRecords => try report.add(file.path, 0, 0, "this is no file of time spent; skein writes them, with 'skein time'", .{}),
        };
    }
    return out;
}

fn read(self: *Time, arena: Allocator, path: []const u8, table: *const toml.Table) !void {
    for (table.keys()) |item| {
        const by_person = table.get(item).?;
        if (by_person != .table) return error.NotRecords;
        for (by_person.table.keys()) |by| {
            const days = by_person.table.get(by).?;
            if (days != .table) return error.NotRecords;
            for (days.table.keys()) |on| {
                const record = days.table.get(on).?;
                if (record != .table or day.parse(on) == null) return error.NotRecords;
                const hours = record.table.get("hours") orelse return error.NotRecords;
                const h: f64 = switch (hours) {
                    .float => |f| f,
                    .integer => |i| @floatFromInt(i),
                    else => return error.NotRecords,
                };
                const note: ?[]const u8 = if (record.table.get("note")) |n| (if (n == .string) n.string else return error.NotRecords) else null;
                try self.all.append(arena, .{ .item = item, .by = by, .on = on, .hours = h, .note = note, .file = path });
            }
        }
    }
}

/// The file that holds the records of `item` (a work item of the graph)
pub fn fileOf(arena: Allocator, item: *const @import("../graph/Item.zig")) ![]const u8 {
    return record_files.fileOf(arena, dir, item);
}

/// Adds `hours` by `by` on `on` to `item`'s day, and writes the file; the
/// hours of the day so far, or why it was refused
pub fn log(self: *Time, io: Io, arena: Allocator, root: Io.Dir, file: []const u8, item: []const u8, by: []const u8, on: []const u8, hours: f64, note: ?[]const u8) !union(enum) { total: f64, refused: []const u8 } {
    var total = hours;
    var found = false;
    for (self.all.items) |*e| {
        if (!std.mem.eql(u8, e.item, item) or !std.mem.eql(u8, e.by, by) or !std.mem.eql(u8, e.on, on)) continue;
        total += e.hours;
        if (total > max_hours_a_day) return .{ .refused = try arena.print("that makes {d} hours on {s}, and a day has {d}", .{ total, on, @as(u32, max_hours_a_day) }) };
        e.hours = rounded(total);
        if (note) |n| e.note = n;
        found = true;
    }
    if (!found) try self.all.append(arena, .{ .item = item, .by = by, .on = on, .hours = rounded(hours), .note = note, .file = file });
    var lines: std.ArrayList([]const u8) = .empty;
    for (self.all.items) |e| {
        if (!std.mem.eql(u8, e.file, file)) continue;
        try lines.append(arena, try line(arena, e));
    }
    try record_files.write(io, arena, root, file, header, lines.items);
    return .{ .total = rounded(total) };
}

fn rounded(h: f64) f64 {
    return @round(h * 100) / 100;
}

fn line(arena: Allocator, e: Entry) ![]const u8 {
    const write = @import("../toml/write.zig");
    const note = if (e.note) |n| try arena.print(", note = {s}", .{try write.string(arena, std.mem.trim(u8, n, " \t\r\n"))}) else "";
    return arena.print("\"{s}\".\"{s}\".\"{s}\" = {{ hours = {d}{s} }}\n", .{ try record_files.escape(arena, e.item), try record_files.escape(arena, e.by), e.on, e.hours, note });
}

/// One work item's estimate and what has been spent on it
pub const Row = struct {
    work: *const Work,
    /// in hours; null when it has no estimate
    estimate: ?f64,
    spent: f64,
    /// who spent it, in order of the first entry
    by: []const By,

    pub const By = struct { name: []const u8, hours: f64 };
};

/// A row for each work item that has an estimate or time spent
pub fn summarize(arena: Allocator, works: []const Work, entries: []const Entry, hours_a_day: f64) Allocator.Error![]const Row {
    var out: std.ArrayList(Row) = .empty;
    for (works) |*w| {
        var spent: f64 = 0;
        var by: std.ArrayList(Row.By) = .empty;
        for (entries) |e| {
            // time is logged in this repository, on its own items
            if (w.repo != null or !std.mem.eql(u8, e.item, w.item.id)) continue;
            spent += e.hours;
            const who = for (by.items) |*b| {
                if (std.mem.eql(u8, b.name, e.by)) break b;
            } else blk: {
                try by.append(arena, .{ .name = e.by, .hours = 0 });
                break :blk &by.items[by.items.len - 1];
            };
            who.hours += e.hours;
        }
        const estimate: ?f64 = if (w.estimate) |d| @as(f64, @floatFromInt(d)) * hours_a_day else null;
        if (estimate == null and by.items.len == 0) continue;
        try out.append(arena, .{ .work = w, .estimate = estimate, .spent = rounded(spent), .by = by.items });
    }
    return out.items;
}

/// Reports time spent on what is no work item, and hours that cannot be
pub fn check(self: *const Time, works: []const Work, report: *Report) Allocator.Error!void {
    for (self.all.items) |e| {
        if (Work.find(works, e.item) == null) {
            try report.add(e.file, 0, 0, "time of {s} on {s}: '{s}' is no work item", .{ e.by, e.on, e.item });
        }
        if (e.hours <= 0 or e.hours > max_hours_a_day) {
            try report.add(e.file, 0, 0, "time of {s} on {s} on '{s}': {d} hours is not between 0 and {d}", .{ e.by, e.on, e.item, e.hours, @as(u32, max_hours_a_day) });
        }
    }
}

const testing = std.testing;

test "hours are added to the day, rounded, and written as one sorted line each" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var time: Time = .{};
    const first = try time.log(testing.io, a, tmp.dir, ".skein/time/plan.md.toml", "t.a", "ann", "2027-03-02", 1.1, "start");
    try testing.expectEqual(1.1, first.total);
    const second = try time.log(testing.io, a, tmp.dir, ".skein/time/plan.md.toml", "t.a", "ann", "2027-03-02", 2.2, null);
    try testing.expectEqual(3.3, second.total);
    _ = try time.log(testing.io, a, tmp.dir, ".skein/time/plan.md.toml", "t.a", "bob", "2027-03-01", 4, null);
    const refused = try time.log(testing.io, a, tmp.dir, ".skein/time/plan.md.toml", "t.a", "ann", "2027-03-02", 22, null);
    try testing.expect(refused == .refused);
    var report: Report = .{ .arena = a };
    const again = try load(testing.io, a, tmp.dir, &report);
    try testing.expect(report.ok());
    try testing.expectEqual(2, again.all.items.len);
    // by item, person and day, as the lines are sorted
    try testing.expectEqualStrings("ann", again.all.items[0].by);
    try testing.expectEqual(3.3, again.all.items[0].hours);
    try testing.expectEqualStrings("start", again.all.items[0].note.?);
    try testing.expectEqualStrings("bob", again.all.items[1].by);
}
