//! Measurements over the history of the project (#104), as a document
//! asks for them:
//!
//!     ```skein
//!     history [type=TYPE]
//!     ```
//!
//! At each baseline and now: how many items there are (of TYPE, or all,
//! removed ones left out) and how many have each status, and the coverage
//! of each expectation, as Mermaid `xychart` diagrams with a table of the
//! numbers under them. A baseline is read from the files of its commit, as
//! `skein diff` reads one; its numbers are read once per rendering.

// cspell:ignore xychart
const std = @import("std");
const Io = std.Io;

const Graph = @import("../graph/Graph.zig");
const Project = @import("../Project.zig");
const Workspace = @import("../commands/Workspace.zig");
const coverage = @import("../graph/coverage.zig");
const generated = @import("generated.zig");
const history = @import("../history.zig");

const Error = generated.Error;

/// The numbers of one state of the project
pub const Point = struct {
    /// the baseline, or "now"
    name: []const u8,
    date: []const u8,
    items: []const Counted = &.{},
    expectations: []const coverage.Expectation = &.{},
};

/// Of one item type: its items, and how many have each status
pub const Counted = struct {
    type_name: []const u8,
    total: usize,
    statuses: []const Status,
};

pub const Status = struct { name: []const u8, n: usize };

/// The baselines' numbers, read when a document first asks for them
pub const History = struct {
    io: Io,
    arena: std.mem.Allocator,
    ws: *Workspace,
    cached: ?[]const Point = null,

    pub fn points(self: *History) Error![]const Point {
        if (self.cached) |c| return c;
        var out: std.ArrayList(Point) = .empty;
        for (try history.baselines(self.io, self.arena, self.ws.root)) |b| {
            var snap = history.snapshot(self.io, self.arena, self.ws.root, b.name) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            };
            defer snap.deinit();
            var old = switch (Workspace.open(self.io, self.arena, .{ .root = snap.path, .offline = true }) catch continue) {
                .ok => |w| w,
                .failed => continue,
            };
            defer old.close();
            try out.append(self.arena, try measure(self.arena, b.name, b.date, &old.project, &old.graph, &old.citations));
        }
        try out.append(self.arena, try measure(self.arena, "now", "", &self.ws.project, &self.ws.graph, &self.ws.citations));
        self.cached = out.items;
        return out.items;
    }
};

pub fn measure(arena: std.mem.Allocator, name: []const u8, date: []const u8, project: *const Project, graph: *const Graph, citations: *const Graph.Citations) Error!Point {
    var counted: std.ArrayList(Counted) = .empty;
    for (project.schema.types) |*t| {
        const statuses = try arena.alloc(Status, t.statuses.len);
        for (t.statuses, statuses) |s, *c| c.* = .{ .name = s, .n = 0 };
        var total: usize = 0;
        for (graph.items) |*item| {
            if (!std.mem.eql(u8, item.type_name, t.name) or item.isTombstone(t)) continue;
            total += 1;
            const s = item.effectiveStatus(t);
            for (statuses) |*c| if (std.mem.eql(u8, c.name, s)) {
                c.n += 1;
                break;
            };
        }
        try counted.append(arena, .{ .type_name = t.name, .total = total, .statuses = statuses });
    }
    return .{ .name = name, .date = date, .items = counted.items, .expectations = try coverage.compute(arena, project, graph, citations, null) };
}

pub fn render(ctx: generated.Context, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    const h = ctx.history orelse return a.print("> **skein:** the history is not drawn here\n", .{});
    var only: ?[]const u8 = null;
    for (args) |word| {
        if (std.mem.startsWith(u8, word, "type=")) {
            only = word["type=".len..];
            if (ctx.project.schema.itemType(only.?) == null) return a.print("> **skein:** there is no item type '{s}'\n", .{only.?});
        } else return a.print("> **skein:** history takes type=TYPE, not '{s}'\n", .{word});
    }
    const points = try h.points();
    var out: std.ArrayList(u8) = .empty;

    // the items: a line per type, or per status of the one type
    try out.appendSlice(a, "```mermaid\nxychart-beta\n  title \"Items\"\n  x-axis [");
    try labels(a, &out, points);
    var top: usize = 1;
    for (points) |p| for (p.items) |c| if (wanted(only, c.type_name)) {
        top = @max(top, c.total);
    };
    try out.print(a, "]\n  y-axis \"Items\" 0 --> {d}\n", .{top});
    var lines: std.ArrayList([]const u8) = .empty;
    if (only) |t| {
        for (ctx.project.schema.itemType(t).?.statuses) |s| {
            try lines.append(a, s);
            try out.appendSlice(a, "  line [");
            for (points, 0..) |p, i| try out.print(a, "{s}{d}", .{ if (i > 0) ", " else "", statusCount(p, t, s) });
            try out.appendSlice(a, "]\n");
        }
    } else for (ctx.project.schema.types) |t| {
        try lines.append(a, t.name);
        try out.appendSlice(a, "  line [");
        for (points, 0..) |p, i| try out.print(a, "{s}{d}", .{ if (i > 0) ", " else "", typeTotal(p, t.name) });
        try out.appendSlice(a, "]\n");
    }
    try out.print(a, "```\n\nThe lines, in order: {s}.\n\n", .{try std.mem.join(a, ", ", lines.items)});

    // coverage, in percent, a line per expectation
    const now = points[points.len - 1];
    var shown: std.ArrayList(coverage.Expectation) = .empty;
    for (now.expectations) |e| if (wanted(only, e.item_type)) try shown.append(a, e);
    if (shown.items.len > 0) {
        try out.appendSlice(a, "```mermaid\nxychart-beta\n  title \"Coverage\"\n  x-axis [");
        try labels(a, &out, points);
        try out.appendSlice(a, "]\n  y-axis \"Percent\" 0 --> 100\n");
        for (shown.items) |e| {
            try out.appendSlice(a, "  line [");
            for (points, 0..) |p, i| try out.print(a, "{s}{d}", .{ if (i > 0) ", " else "", percent(p, e) });
            try out.appendSlice(a, "]\n");
        }
        try out.appendSlice(a, "```\n\nThe lines, in order: ");
        for (shown.items, 0..) |e, i| try out.print(a, "{s}{s} of {s}", .{ if (i > 0) ", " else "", e.name, e.item_type });
        try out.appendSlice(a, ".\n\n");
    }

    // the numbers
    try out.appendSlice(a, "| Edition | Date | Items |");
    for (shown.items) |e| try out.print(a, " {s} of {s} |", .{ e.name, e.item_type });
    try out.appendSlice(a, "\n| --- | --- | ---: |");
    for (shown.items) |_| try out.appendSlice(a, " ---: |");
    try out.append(a, '\n');
    for (points) |p| {
        var total: usize = 0;
        for (p.items) |c| if (wanted(only, c.type_name)) {
            total += c.total;
        };
        try out.print(a, "| {s} | {s} | {d} |", .{ p.name, p.date, total });
        for (shown.items) |e| try out.print(a, " {d}% |", .{percent(p, e)});
        try out.append(a, '\n');
    }
    return out.items;
}

fn wanted(only: ?[]const u8, type_name: []const u8) bool {
    const t = only orelse return true;
    return std.mem.eql(u8, t, type_name);
}

fn labels(a: std.mem.Allocator, out: *std.ArrayList(u8), points: []const Point) Error!void {
    for (points, 0..) |p, i| try out.print(a, "{s}\"{s}\"", .{ if (i > 0) ", " else "", p.name });
}

fn typeTotal(p: Point, type_name: []const u8) usize {
    for (p.items) |c| if (std.mem.eql(u8, c.type_name, type_name)) return c.total;
    return 0;
}

fn statusCount(p: Point, type_name: []const u8, status: []const u8) usize {
    for (p.items) |c| if (std.mem.eql(u8, c.type_name, type_name)) {
        for (c.statuses) |s| if (std.mem.eql(u8, s.name, status)) return s.n;
    };
    return 0;
}

/// The coverage of the expectation like `e` at `p`, in whole percent
fn percent(p: Point, e: coverage.Expectation) usize {
    for (p.expectations) |x| {
        if (x.kind != e.kind or !std.mem.eql(u8, x.name, e.name) or !std.mem.eql(u8, x.item_type, e.item_type)) continue;
        if (x.total == 0) return 0;
        return (x.covered * 100 + x.total / 2) / x.total;
    }
    return 0;
}
