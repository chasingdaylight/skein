//! The people who do the work, as `.skein/resources.toml` lists them, and
//! the project's calendar:
//!
//!     [calendar]
//!     workdays = ["mon", "tue", "wed", "thu", "fri"]
//!     hours = 8
//!     holidays = [2027-12-24, 2027-12-31]
//!
//!     [people.ann]
//!     name = "Ann Example"
//!     share = 0.8                  # of full time; or `hours = 32` a week
//!     absent = [2027-04-02, [2027-03-08, 2027-03-12]]
//!     workdays = ["mon", "tue", "wed", "thu"]
//!
//! People are named by a handle the project chooses, which work items
//! give as their assignees.

const std = @import("std");
const Io = std.Io;

const Calendar = @import("Calendar.zig");
const Project = @import("../Project.zig");
const Reader = @import("../schema/Reader.zig");
const Workspace = @import("../commands/Workspace.zig");
const Report = @import("../Report.zig");
const toml = @import("../toml.zig");
const day = @import("day.zig");

const Resources = @This();

pub const file = Project.dir_name ++ "/resources.toml";

/// the project's calendar: every day, without a `[calendar]`
calendar: Calendar = .every_day,
people: []const Person = &.{},

pub const Person = struct {
    handle: []const u8,
    name: []const u8 = "",
    /// of full time: the hours of the calendar's working days
    share: f64 = 1,
    /// hours a week, in place of a share
    weekly_hours: ?f64 = null,
    /// the project's, with the person's own week and absences
    calendar: Calendar,
    /// where the person is declared
    line: u32 = 0,

    /// The hours the person can work on `d`
    pub fn capacity(self: *const Person, d: day.Day) f64 {
        if (!self.calendar.isWorking(d)) return 0;
        if (self.weekly_hours) |h| {
            var week: f64 = 0;
            for (self.calendar.workdays) |w| if (w) {
                week += 1;
            };
            return if (week == 0) 0 else h / week;
        }
        return self.share * self.calendar.hours;
    }
};

pub fn person(self: *const Resources, handle: []const u8) ?*const Person {
    for (self.people) |*p| if (std.mem.eql(u8, p.handle, handle)) return p;
    return null;
}

/// The resources of the project; null when it has no resources file
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, report: *Report) std.mem.Allocator.Error!?Resources {
    root.access(io, file, .{}) catch return null;
    const table = try Project.readToml(io, arena, root, file, report) orelse return .{};
    return try fromTable(arena, table, file, report);
}

/// The resources of the project `ws`: its own file, else those of its
/// planning repository (`[planning] repository`), which shares its people
/// and calendar; null when neither has any
pub fn of(io: Io, arena: std.mem.Allocator, ws: *const Workspace, report: *Report) std.mem.Allocator.Error!?Resources {
    if (try load(io, arena, ws.root, report)) |own| return own;
    const name = ws.project.planning_repository orelse return null;
    const member = ws.network.member(name) orelse return null;
    const text = member.resources orelse return null;
    // what is wrong with the planning repository's file is for its own `check`
    var diag: toml.Diagnostic = .{};
    const table = toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => return null,
    };
    var ignored: Report = .{ .arena = arena };
    return try fromTable(arena, table, try arena.print("{s}:{s}", .{ name, file }), &ignored);
}

/// The resources a table of `path` says
fn fromTable(arena: std.mem.Allocator, table: *const toml.Table, path: []const u8, report: *Report) std.mem.Allocator.Error!Resources {
    const r: Reader = .{ .report = report, .arena = arena, .file = path, .table = table };
    try r.known(&.{ "calendar", "people" });
    var out: Resources = .{};
    if (try r.child("calendar")) |c| {
        try c.known(&.{ "workdays", "hours", "holidays" });
        out.calendar = .{ .workdays = try workdays(c) orelse weekdays, .hours = try number(c, "hours") orelse 8 };
        out.calendar.holidays = try days(c, "holidays");
    }
    var people: std.ArrayList(Person) = .empty;
    if (try r.child("people")) |list| {
        for (list.table.keys()) |handle| {
            const p = try list.child(handle) orelse continue;
            try p.known(&.{ "name", "share", "hours", "absent", "workdays" });
            var cal = out.calendar;
            if (try workdays(p)) |w| cal.workdays = w;
            cal.absences = try ranges(p, "absent");
            const share = try number(p, "share");
            const hours = try number(p, "hours");
            if (share != null and hours != null) try p.complain("hours", "give a share or hours a week, not both", .{});
            try people.append(arena, .{
                .handle = handle,
                .name = try p.string("name") orelse "",
                .share = share orelse 1,
                .weekly_hours = if (share == null) hours else null,
                .calendar = cal,
                .line = list.table.placeOf(handle).line,
            });
        }
    }
    out.people = people.items;
    return out;
}

const weekdays: [7]bool = .{ true, true, true, true, true, false, false };
const day_names = [_][]const u8{ "mon", "tue", "wed", "thu", "fri", "sat", "sun" };

fn workdays(r: Reader) Reader.Error!?[7]bool {
    if (r.table.get("workdays") == null) return null;
    var out: [7]bool = @splat(false);
    for (try r.strings("workdays")) |name| {
        const i = for (day_names, 0..) |d, i| {
            if (std.mem.eql(u8, d, name)) break i;
        } else {
            try r.complain("workdays", "'{s}' is no day: mon, tue, wed, thu, fri, sat or sun", .{name});
            continue;
        };
        out[i] = true;
    }
    return out;
}

/// A number, integer or not; null when absent
fn number(r: Reader, key: []const u8) Reader.Error!?f64 {
    const v = r.table.get(key) orelse return null;
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => {
            try r.complain(key, "expected a number", .{});
            return null;
        },
    };
}

fn dateOf(v: toml.Value) ?day.Day {
    if (v != .datetime or v.datetime.time != null) return null;
    const d = v.datetime.date orelse return null;
    return day.fromCivil(d.year, d.month, d.day);
}

/// An array of dates
fn days(r: Reader, key: []const u8) Reader.Error![]const day.Day {
    const v = r.table.get(key) orelse return &.{};
    var out: std.ArrayList(day.Day) = .empty;
    if (v != .array) {
        try r.complain(key, "expected an array of dates, like 2027-12-24", .{});
        return &.{};
    }
    for (v.array.values()) |item| {
        try out.append(r.arena, dateOf(item) orelse {
            try r.complain(key, "expected an array of dates, like 2027-12-24", .{});
            return &.{};
        });
    }
    return out.items;
}

/// An array of dates and of `[first, last]` pairs of dates
fn ranges(r: Reader, key: []const u8) Reader.Error![]const Calendar.Range {
    const v = r.table.get(key) orelse return &.{};
    const message = "expected an array of dates and of [first, last] pairs of dates";
    var out: std.ArrayList(Calendar.Range) = .empty;
    if (v != .array) {
        try r.complain(key, message, .{});
        return &.{};
    }
    for (v.array.values()) |item| {
        if (dateOf(item)) |d| {
            try out.append(r.arena, .{ .first = d, .last = d });
            continue;
        }
        const pair = if (item == .array and item.array.values().len == 2) item.array.values() else {
            try r.complain(key, message, .{});
            return &.{};
        };
        const first = dateOf(pair[0]);
        const last = dateOf(pair[1]);
        if (first == null or last == null or last.? < first.?) {
            try r.complain(key, message, .{});
            return &.{};
        }
        try out.append(r.arena, .{ .first = first.?, .last = last.? });
    }
    return out.items;
}
