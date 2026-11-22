//! Document control, from git: when each file last changed, by whom and
//! in which commit; the baselines; and each document's identifier and
//! revision, from its TOML front matter (`document`, `revision`). A
//! controlled document gets a table under its title and a change record
//! at its end; an item file, when it last changed.

const std = @import("std");
const Io = std.Io;

const Forge = @import("../forge/Forge.zig");
const Graph = @import("../graph/Graph.zig");
const Project = @import("../Project.zig");
const baseline = @import("../commands/baseline.zig");
const changes = @import("../graph/changes.zig");
const git = @import("../git.zig");
const history = @import("../history.zig");
const toml = @import("../toml.zig");

const Control = @This();

/// by file: its last change
last: std.array_hash_map.String(Change) = .empty,
/// oldest first
baselines: []const Baseline = &.{},
/// the controlled documents, in order of file
documents: []const Document = &.{},
forge: ?Forge = null,

pub const Change = struct { date: []const u8, author: []const u8, commit: []const u8 };

pub const Baseline = struct {
    name: []const u8,
    date: []const u8,
    /// the message given to `skein baseline`, its first line
    message: []const u8,
    /// the project at it
    graph: Graph,
};

pub const Document = struct {
    file: []const u8,
    id: []const u8,
    revision: []const u8,
    /// its first heading of level 1
    title: []const u8,
};

/// What git knows of `files` (documents and item files, from the root);
/// empty when the project is not in a git repository
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, files: []const []const u8) !Control {
    var out: Control = .{ .forge = project.forge };
    // one walk of the log: the first time a file is named is its last change
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(arena, &.{ "log", "--format=@%H%x09%an%x09%ad", "--date=short", "--name-only", "--" });
    try args.appendSlice(arena, files);
    const log = try git.output(io, arena, root, args.items) orelse return out;
    var current: ?Change = null;
    var lines = std.mem.splitScalar(u8, log, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        if (line[0] == '@') {
            var f = std.mem.splitScalar(u8, line[1..], '\t');
            current = .{ .commit = f.next() orelse continue, .author = f.next() orelse "", .date = f.next() orelse "" };
            continue;
        }
        const c = current orelse continue;
        const entry = try out.last.getOrPut(arena, line);
        if (!entry.found_existing) entry.value_ptr.* = c;
    }

    // the controlled documents
    var docs: std.ArrayList(Document) = .empty;
    for (files) |file| {
        const text = root.readFileAlloc(io, file, arena, .limited(1 << 26)) catch continue;
        if (try documentOf(arena, file, text)) |d| try docs.append(arena, d);
    }
    out.documents = docs.items;
    if (docs.items.len == 0) return out;

    // the baselines, each read once
    const refs = try git.output(io, arena, root, &.{ "for-each-ref", "--sort=creatordate", "--format=%(refname:short)%09%(creatordate:short)%09%(contents:subject)%09%(contents:body)", "refs/tags" }) orelse "";
    var found: std.ArrayList(Baseline) = .empty;
    var tags = std.mem.splitScalar(u8, refs, '\n');
    while (tags.next()) |raw| {
        var f = std.mem.splitScalar(u8, std.mem.trimEnd(u8, raw, "\r"), '\t');
        const name = f.next() orelse continue;
        const date = f.next() orelse continue;
        const subject = f.next() orelse continue;
        if (!std.mem.startsWith(u8, subject, baseline.mark ++ " ")) continue;
        const body = std.mem.trim(u8, f.rest(), " \r\n");
        const first = std.mem.trim(u8, body[0 .. std.mem.findScalar(u8, body, '\n') orelse body.len], " \r");
        var snap = history.snapshot(io, arena, root, name) catch continue;
        defer snap.deinit();
        try found.append(arena, .{ .name = name, .date = date, .message = first, .graph = snap.graph });
    }
    out.baselines = found.items;
    return out;
}

/// The identifier and revision a document's TOML front matter gives; null
/// for a document without them
pub fn documentOf(arena: std.mem.Allocator, file: []const u8, text: []const u8) !?Document {
    if (!std.mem.startsWith(u8, text, "+++")) return null;
    const after = std.mem.findScalar(u8, text, '\n') orelse return null;
    const close = std.mem.find(u8, text[after..], "\n+++") orelse return null;
    var diag: toml.Diagnostic = .{};
    const front = toml.parse(arena, text[after + 1 .. after + close + 1], &diag) catch return null;
    const id = front.get("document") orelse return null;
    if (id != .string) return null;
    const revision: []const u8 = if (front.get("revision")) |r| (if (r == .string) r.string else "") else "";
    var title: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "# ")) {
            title = std.mem.trim(u8, line[2..], " \r");
            break;
        }
    }
    return .{ .file = file, .id = id.string, .revision = revision, .title = title };
}

pub fn document(self: *const Control, file: []const u8) ?Document {
    for (self.documents) |d| if (std.mem.eql(u8, d.file, file)) return d;
    return null;
}

/// "2026-11-21, by A. Author, in [1a2b3c4](...)"; empty when unknown
pub fn changed(self: *const Control, arena: std.mem.Allocator, file: []const u8) ![]const u8 {
    const c = self.last.get(file) orelse return "";
    return arena.print("{s}, by {s}, in {s}", .{ c.date, c.author, try self.commitLink(arena, c.commit) });
}

fn commitLink(self: *const Control, arena: std.mem.Allocator, commit: []const u8) ![]const u8 {
    const short = commit[0..@min(commit.len, 7)];
    const f = self.forge orelse return arena.print("`{s}`", .{short});
    const base = f.url orelse try arena.print("https://{s}", .{f.host()});
    return arena.print("[`{s}`]({s}/{s}/commit/{s})", .{ short, base, f.repository, commit });
}

/// The control table of a document, for under its title
pub fn table(self: *const Control, arena: std.mem.Allocator, d: Document) ![]const u8 {
    return arena.print("\n| Document | Revision | Last changed |\n| --- | --- | --- |\n| {s} | {s} | {s} |\n", .{ d.id, d.revision, try self.changed(arena, d.file) });
}

/// The change record of a document: each baseline in which its items
/// changed, with how many were added, changed and removed since the one
/// before; nothing without baselines
pub fn record(self: *const Control, arena: std.mem.Allocator, project: *const Project, file: []const u8) ![]const u8 {
    if (self.baselines.len == 0) return "";
    var out: std.ArrayList(u8) = .empty;
    const empty: Graph = .{};
    for (self.baselines, 0..) |b, i| {
        const before = if (i == 0) &empty else &self.baselines[i - 1].graph;
        var counts = [_]usize{ 0, 0, 0 };
        for (try changes.compute(arena, .{ .graph = before, .schema = &project.schema }, .{ .graph = &b.graph, .schema = &project.schema })) |c| {
            if (!std.mem.eql(u8, c.file, file)) continue;
            if (c.kind == .changed and !c.matters()) continue;
            counts[@backingInt(c.kind)] += 1;
        }
        if (counts[0] + counts[1] + counts[2] == 0) continue;
        try out.print(arena, "| {s} | {s} | {s} | {d} | {d} | {d} |\n", .{ b.name, b.date, b.message, counts[0], counts[2], counts[1] });
    }
    if (out.items.len == 0) return "";
    return arena.print("\n## Change record\n\n| Baseline | Date | Message | Added | Changed | Removed |\n| --- | --- | --- | ---: | ---: | ---: |\n{s}", .{out.items});
}
