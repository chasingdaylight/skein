//! skein's requests for the planning views of an editor:
//!
//! - `skein/schedule`: the work items as `skein schedule` schedules them,
//!   with their links, assignees and statuses, and the calendar
//! - `skein/plan` (`{ "id": ID, "start": DATE }`, `"finish"` or
//!   `"status"`): what a drag in a view changes, written into the item's
//!   marker or front matter; then the stored schedule is written again, as
//!   `skein schedule` writes it. A float item given a start becomes fixed.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Calendar = @import("../planning/Calendar.zig");
const Item = @import("../graph/Item.zig");
const Report = @import("../Report.zig");
const Resources = @import("../planning/Resources.zig");
const Schema = @import("../schema/Schema.zig");
const Server = @import("Server.zig");
const Work = @import("../planning/Work.zig");
const Workspace = @import("../commands/Workspace.zig");
const attribute = @import("../edit/attribute.zig");
const day = @import("../planning/day.zig");
const generated = @import("../render/generated.zig");
const protocol = @import("protocol.zig");
const schedule = @import("../planning/schedule.zig");
const schedule_command = @import("../commands/schedule.zig");

const Entry = struct {
    id: []const u8,
    type: []const u8,
    title: []const u8,
    status: []const u8,
    uri: []const u8,
    line: usize,
    start: ?[]const u8 = null,
    finish: ?[]const u8 = null,
    duration: ?u32 = null,
    mode: []const u8,
    source: []const u8,
    slack: ?u32 = null,
    critical: bool,
    milestone: bool,
    after: []const []const u8,
    parents: []const []const u8,
    assignees: []const []const u8,
};

fn calendarOf(s: *Server, a: Allocator, ws: *const Workspace) Allocator.Error!*const Calendar {
    var ignored: Report = .{ .arena = a };
    const c = try a.create(Calendar);
    c.* = if (try Resources.load(s.io, a, ws.root, &ignored)) |r| r.calendar else .every_day;
    return c;
}

pub fn scheduleOf(s: *Server, a: Allocator, id: json.Value) Server.Error!void {
    var ws = s.open(a) orelse return s.respond(a, id, null);
    defer ws.close();
    if (!ws.items_read) return s.respond(a, id, null);
    const calendar = try calendarOf(s, a, &ws);
    const works = try Work.collect(a, &ws.project.schema, &ws.graph);
    var out: std.ArrayList(Entry) = .empty;
    var statuses: std.ArrayList([]const u8) = .empty;
    for (try schedule.compute(a, works, calendar)) |*e| {
        const item = e.work.item;
        const t = ws.project.schema.itemType(item.type_name).?;
        for (t.statuses) |st| {
            if (t.tombstone != null and std.mem.eql(u8, st, t.tombstone.?)) continue;
            if (!Schema.names.contains(statuses.items, st)) try statuses.append(a, st);
        }
        try out.append(a, .{
            .id = item.id,
            .type = item.type_name,
            .title = firstLine(item.text),
            .status = item.effectiveStatus(t),
            .uri = try s.uriOf(a, &ws, item.file),
            .line = if (item.line > 0) item.line - 1 else 0,
            .start = if (e.start) |d| try a.dupe(u8, &day.format(d)) else null,
            .finish = if (e.finish) |d| try a.dupe(u8, &day.format(d)) else null,
            .duration = e.work.duration,
            .mode = @tagName(e.mode),
            .source = @tagName(e.source),
            .slack = e.slack,
            .critical = e.critical(),
            .milestone = e.work.duration != null and e.work.duration.? == 0,
            .after = e.work.after,
            .parents = e.work.parents,
            .assignees = e.work.assignees,
        });
    }
    var holidays: std.ArrayList([]const u8) = .empty;
    for (calendar.holidays) |h| try holidays.append(a, try a.dupe(u8, &day.format(h)));
    try s.respond(a, id, .{ .items = out.items, .statuses = statuses.items, .workdays = calendar.workdays, .holidays = holidays.items });
}

fn firstLine(text: []const u8) []const u8 {
    const p = generated.firstParagraph(text);
    return p[0 .. std.mem.findScalar(u8, p, '\n') orelse p.len];
}

const PlanParams = struct {
    id: []const u8,
    start: ?[]const u8 = null,
    finish: ?[]const u8 = null,
    status: ?[]const u8 = null,
};

pub fn plan(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    const p = Server.parse(PlanParams, a, params) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein/plan: no id");
    var ws = s.open(a) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: no project");
    defer ws.close();
    if (!ws.items_read) return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: the project has problems that stop it being read");
    const item = ws.graph.find(p.id) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: there is no item '{s}'", .{p.id}));
    const t = ws.project.schema.itemType(item.type_name).?;
    const roles = t.planning orelse return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: {s} is no work item", .{item.id}));
    if (ws.project.readOnlySource(item.file)) |src| return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: {s} is in the read-only source '{s}'", .{ item.id, src.path }));
    if (s.docs.get(try s.uriOf(a, &ws, item.file))) |shown| {
        const on_disk = ws.root.readFileAlloc(s.io, item.file, a, .limited(1 << 26)) catch "";
        if (!std.mem.eql(u8, on_disk, shown)) return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: save {s} first: the change is made in the file", .{item.file}));
    }
    const calendar = try calendarOf(s, a, &ws);
    const works = try Work.collect(a, &ws.project.schema, &ws.graph);
    const w = Work.find(works, item.id) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: {s} is removed", .{item.id}));
    var edit: Edit = .{ .s = s, .a = a, .ws = &ws, .item = item };

    if (p.start) |text| {
        const start = day.parse(text) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: '{s}' is no date", .{text}));
        const key = roles.attribute(.start) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: a '{s}' has no start", .{t.name}));
        try edit.set(key, text, .date);
        // a float item placed by hand is fixed from then on
        if (roles.attribute(.mode)) |m| if (w.mode() != .fixed) try edit.set(m, "fixed", .string);
        // a finish written with the duration moves with the start
        if (w.finish != null and w.duration != null) if (roles.attribute(.finish)) |f| try edit.set(f, &day.format(calendar.finishOf(start, w.duration.?)), .date);
    }
    if (p.finish) |text| {
        const finish = day.parse(text) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: '{s}' is no date", .{text}));
        const start = (if (p.start) |st| day.parse(st) else null) orelse w.start orelse
            (try currentStart(a, works, calendar, item.id)) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: {s} has no start", .{item.id}));
        if (finish < start) return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: the finish is before the start");
        if (roles.attribute(.duration)) |d| try edit.set(d, try a.print("{d}", .{calendar.workingDays(start, finish)}), .integer);
        if (roles.attribute(.finish)) |f| if (w.finish != null or roles.attribute(.duration) == null) try edit.set(f, text, .date);
    }
    if (p.status) |status| {
        if (!Schema.names.contains(t.statuses, status)) return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: '{s}' is not a status of a '{s}'", .{ status, t.name }));
        try edit.status(status);
    }
    if (edit.failed) |message| return s.respondError(a, id, protocol.error_codes.invalid_params, message);
    // the stored schedule follows the change
    _ = schedule_command.run(s.io, a, .{ .common = .{ .root = ws.root_path } }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {},
    };
    try s.respond(a, id, .{ .changed = edit.changed });
    try s.publishAll(a);
}

/// The start the schedule gives an item now
fn currentStart(a: Allocator, works: []Work, calendar: *const Calendar, item_id: []const u8) Allocator.Error!?day.Day {
    for (try schedule.compute(a, works, calendar)) |e| {
        if (std.mem.eql(u8, e.work.item.id, item_id)) return e.start;
    }
    return null;
}

/// The changes to one item's file, made one after another
const Edit = struct {
    s: *Server,
    a: Allocator,
    ws: *const Workspace,
    item: *const Item,
    changed: usize = 0,
    failed: ?[]const u8 = null,

    const Kind = enum { date, integer, string };

    fn set(self: *Edit, key: []const u8, value: []const u8, kind: Kind) Allocator.Error!void {
        if (self.failed != null) return;
        const text = self.read() orelse return;
        const toml_value = if (kind == .string) try self.a.print("\"{s}\"", .{value}) else value;
        const edited = if (self.item.in_document) try attribute.marker(self.a, text, self.item.line, key, value) else try attribute.frontMatter(self.a, text, key, toml_value);
        try self.write(edited, key);
    }

    fn status(self: *Edit, value: []const u8) Allocator.Error!void {
        if (self.failed != null) return;
        const text = self.read() orelse return;
        const edited = if (self.item.in_document) try attribute.markerWord(self.a, text, self.item.line, self.item.status, value) else try attribute.frontMatter(self.a, text, "status", try self.a.print("\"{s}\"", .{value}));
        try self.write(edited, "status");
    }

    fn read(self: *Edit) ?[]const u8 {
        return self.ws.root.readFileAlloc(self.s.io, self.item.file, self.a, .limited(1 << 26)) catch {
            self.failed = "skein: the item's file cannot be read";
            return null;
        };
    }

    fn write(self: *Edit, edited: ?[]const u8, key: []const u8) Allocator.Error!void {
        const data = edited orelse {
            self.failed = try self.a.print("skein: {s}: the {s} is written in a way skein does not change; change it by hand", .{ self.item.file, key });
            return;
        };
        self.ws.root.writeFile(self.s.io, .{ .sub_path = self.item.file, .data = data }) catch {
            self.failed = try self.a.print("skein: {s} cannot be written", .{self.item.file});
            return;
        };
        self.changed += 1;
    }
};
