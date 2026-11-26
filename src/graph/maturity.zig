//! Documents held to the maturity expected at the project's milestone:
//! a controlled document whose front matter names an item (`item`) and a
//! maturity (`maturity`) is warned of when it is below the item's value of
//! the attribute the milestone names (`[maturity] milestone = "pdr"`), in
//! the order the configuration gives (`order = ["D", "P", "B", "U", "F"]`).
//! And the gates of the milestone (`[maturity.gates.pdr]`): the share of
//! undecided items (`tbd`, at most) and of items changed since the last
//! baseline (`volatility`, under), as the handbook's review checklists ask.

const std = @import("std");
const Io = std.Io;

const Control = @import("../render/control.zig");
const Graph = @import("Graph.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const changes = @import("changes.zig");
const files = @import("../files.zig");
const history = @import("../history.zig");

pub fn check(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, report: *Report) !void {
    try documents(io, arena, root, project, graph, report);
    const m = try measure(io, arena, root, project, graph) orelse return;
    const g = m.gate;
    if (g.tbd) |most| if (m.tbd * 100 > @as(usize, @intCast(most)) * m.items) {
        try report.warn(Project.config_file, 0, 0, "at {s}, {d} of the {d} items ({d}%) are undecided ({s}); the gate is at most {d}%", .{ g.milestone, m.tbd, m.items, percent(m.tbd, m.items), try std.mem.join(arena, ", ", project.maturity.tbd), most });
    };
    if (g.volatility) |under| if (m.baseline) |b| if (m.changed * 100 >= @as(usize, @intCast(under)) * m.baseline_items and m.changed > 0) {
        try report.warn(Project.config_file, 0, 0, "at {s}, {d} of the {d} items of baseline {s} ({d}%) were added, changed or removed since; the gate is under {d}%", .{ g.milestone, m.changed, m.baseline_items, b, percent(m.changed, m.baseline_items), under });
    };
}

/// The numbers the gate of the project's milestone is about
pub const Measured = struct {
    gate: Project.Maturity.Gate,
    /// the items of the types that can be undecided, not removed ones
    items: usize,
    /// of them, those that are undecided
    tbd: usize,
    /// the last baseline; null when there is none (or no git)
    baseline: ?[]const u8 = null,
    /// such items there, and how many were added, changed or removed since
    baseline_items: usize = 0,
    changed: usize = 0,
};

/// What the gate of the milestone is about; null when it has no gate
pub fn measure(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph) !?Measured {
    const m = project.maturity;
    const g = m.gate() orelse return null;
    var out: Measured = .{ .gate = g, .items = 0, .tbd = 0 };
    for (graph.items) |*item| {
        const t = project.schema.itemType(item.type_name) orelse continue;
        if (!counted(m, t) or item.isTombstone(t)) continue;
        out.items += 1;
        for (m.tbd) |s| if (std.mem.eql(u8, item.effectiveStatus(t), s)) {
            out.tbd += 1;
            break;
        };
    }
    if (g.volatility == null) return out;
    const b = try history.lastBaseline(io, arena, root) orelse return out;
    var old = history.snapshot(io, arena, root, b) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return out,
    };
    defer old.deinit();
    out.baseline = b;
    for (old.graph.items) |*item| {
        const t = old.project.schema.itemType(item.type_name) orelse continue;
        if (counted(m, t) and !item.isTombstone(t)) out.baseline_items += 1;
    }
    const found = try changes.compute(arena, .{ .graph = &old.graph, .schema = &old.project.schema }, .{ .graph = graph, .schema = &project.schema });
    for (found) |c| {
        const t = project.schema.itemType(c.type_name) orelse old.project.schema.itemType(c.type_name) orelse continue;
        if (counted(m, t) and (c.kind == .added or c.matters())) out.changed += 1;
    }
    return out;
}

/// Whether the items of `t` are counted: it has an undecided status
fn counted(m: Project.Maturity, t: *const @import("../schema/Schema.zig").ItemType) bool {
    for (m.tbd) |s| for (t.statuses) |have| if (std.mem.eql(u8, s, have)) return true;
    return false;
}

pub fn percent(part: usize, whole: usize) usize {
    if (whole == 0) return 0;
    return (part * 100 + whole / 2) / whole;
}

/// Documents below the maturity their item expects at the milestone
fn documents(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, report: *Report) !void {
    const m = project.maturity;
    const milestone = m.milestone orelse return;
    if (m.order.len == 0) return;
    for (project.sources) |source| {
        const found = files.list(io, arena, root, source.path, &.{".md"}) catch continue;
        for (found) |file| {
            const text = root.readFileAlloc(io, file, arena, .limited(1 << 26)) catch continue;
            const doc = try Control.documentOf(arena, file, text) orelse continue;
            if (doc.item.len == 0) continue;
            const item = graph.find(doc.item) orelse {
                try report.warn(file, 1, 1, "document {s} is item '{s}', and there is no such item", .{ doc.id, doc.item });
                continue;
            };
            const expected = item.attribute(milestone) orelse continue;
            const want = m.rank(expected) orelse continue;
            if (doc.maturity.len == 0) {
                try report.warn(file, 1, 1, "document {s} gives no maturity; at {s}, {s} is expected to be at {s}", .{ doc.id, milestone, item.id, expected });
                continue;
            }
            const have = m.rank(doc.maturity) orelse {
                try report.warn(file, 1, 1, "document {s}: '{s}' is not a maturity ({s})", .{ doc.id, doc.maturity, try std.mem.join(arena, ", ", m.order) });
                continue;
            };
            if (have < want) try report.warn(file, 1, 1, "document {s} is at {s}; at {s}, {s} is expected to be at {s}", .{ doc.id, doc.maturity, milestone, item.id, expected });
        }
    }
}
