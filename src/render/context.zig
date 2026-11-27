//! What rendering a project's documents draws on, as `skein render` and the
//! language server's preview (`skein/render`) both build it: the item
//! sources, test results, what the forge said of issues, document control
//! and the schedule.

const std = @import("std");
const Io = std.Io;

const Control = @import("control.zig");
const Results = @import("../results/Results.zig");
const measures = @import("measures.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("../commands/Workspace.zig");
const files = @import("../files.zig");
const forge = @import("../forge/checks.zig");
const markdown = @import("markdown.zig");
const plan = @import("plan.zig");

pub const Options = struct {
    profile: ?*const Schema.Profile = null,
    /// results files besides the project's own, and what produced them
    results: Results.Given = .{},
    /// read the forge's issues from the cache only
    offline: bool = false,
    /// read document control from git
    control: bool = true,
};

/// The context; results that cannot be read are in the report of `ws`
pub fn build(io: Io, arena: std.mem.Allocator, ws: *Workspace, options: Options) !markdown.Context {
    var item_sources: std.ArrayList([]const u8) = .empty;
    for (ws.project.sources) |source| {
        if (source.kind == .items) try item_sources.append(arena, source.path);
    }
    const results = try arena.create(Results);
    results.* = try Results.load(io, arena, ws.root, &ws.project, &ws.graph, options.results, &ws.report);
    const idx = try arena.create(Results.Index);
    idx.* = try results.index(arena, &ws.graph, &ws.citations);
    const known = try forge.learn(io, arena, ws.root, &ws.project, &ws.graph, options.offline);
    const issues = if (known) |k| blk: {
        const p = try arena.create(@TypeOf(k));
        p.* = k;
        break :blk p;
    } else null;
    var control: ?*const Control = null;
    if (options.control) {
        // document control, from git: every file of every source
        var all_files: std.ArrayList([]const u8) = .empty;
        for (ws.project.sources) |source| {
            const found = files.list(io, arena, ws.root, source.path, &.{".md"}) catch continue;
            try all_files.appendSlice(arena, found);
        }
        const c = try arena.create(Control);
        c.* = try Control.load(io, arena, ws.root, &ws.project, all_files.items);
        control = c;
    }
    return .{
        .arena = arena,
        .graph = &ws.graph,
        .schema = &ws.project.schema,
        .item_sources = item_sources.items,
        .project = &ws.project,
        .citations = &ws.citations,
        .profile = options.profile,
        .results = if (results.all.len > 0) .{ .results = results, .index = idx } else null,
        .issues = issues,
        .control = control,
        .planning = try plan.load(io, arena, ws, options.offline),
        .history = blk: {
            const h = try arena.create(measures.History);
            h.* = .{ .io = io, .arena = arena, .ws = ws };
            break :blk h;
        },
    };
}
