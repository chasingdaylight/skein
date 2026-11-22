//! `skein pin [NAME [REV]]`: records, in `.skein/network.toml`, the commit
//! of each other repository (or of the one named) that the project's
//! items are checked against: the commit given, or the one its checkout
//! has checked out. Says what changed there since the commit pinned
//! before, and which of those items the project refers to.

const std = @import("std");
const Io = std.Io;

const Graph = @import("../graph/Graph.zig");
const Network = @import("../network/Network.zig");
const Project = @import("../Project.zig");
const Workspace = @import("Workspace.zig");
const changes = @import("../graph/changes.zig");
const cli = @import("../cli.zig");
const git = @import("../git.zig");
const history = @import("../history.zig");
const record = @import("../network/record.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Pin) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    // a record that no longer matches is what pinning mends
    ws.report.problems.clearRetainingCapacity();
    const repositories = ws.project.repositories;
    if (repositories.len == 0) return misuse(arena, "the project declares no other repositories ([[repositories]] in {s})", .{Project.config_file});
    if (options.name) |name| {
        for (repositories) |r| {
            if (std.mem.eql(u8, r.name, name)) break;
        } else return misuse(arena, "the project declares no repository '{s}'", .{name});
    }
    const git_dir = history.gitDir(io, arena, ws.root) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return misuse(arena, "pinning needs the project to be in a git repository", .{}),
    };
    const scratch = try Io.Dir.path.join(arena, &.{ git_dir, "skein", "snapshots" });

    const old = try record.read(io, arena, ws.root, &ws.report);
    var entries: std.ArrayList(record.Entry) = .empty;
    try entries.appendSlice(arena, old);
    var out: std.ArrayList(u8) = .empty;
    for (repositories) |repository| {
        if (options.name) |name| if (!std.mem.eql(u8, name, repository.name)) continue;
        const entry = try pinOne(io, arena, &ws, repository, options.revision, scratch, record.find(old, repository.name), &out) orelse continue;
        for (entries.items) |*e| {
            if (std.mem.eql(u8, e.name, entry.name)) {
                e.* = entry;
                break;
            }
        } else try entries.append(arena, entry);
    }
    if (!ws.report.ok()) return ws.problems();
    ws.root.writeFile(io, .{ .sub_path = record.file, .data = try record.render(arena, entries.items) }) catch |e|
        return misuse(arena, "cannot write {s} ({s})", .{ record.file, @errorName(e) });
    try out.print(arena, "skein: wrote {s}\n", .{record.file});
    return .{ .text = out.items };
}

/// The new entry of `repository`, after saying what changed since `before`;
/// null, with the reason reported, when it cannot be pinned
fn pinOne(
    io: Io,
    arena: std.mem.Allocator,
    ws: *Workspace,
    repository: Project.Repository,
    revision: ?[]const u8,
    scratch: []const u8,
    before: ?record.Entry,
    out: *std.ArrayList(u8),
) !?record.Entry {
    const name = repository.name;
    const path = repository.path orelse {
        try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: a repository with a url is not fetched yet; give the path of a checkout", .{name});
        return null;
    };
    var dir = Io.Dir.cwd().openDir(io, try Io.Dir.path.join(arena, &.{ ws.root_path, path }), .{}) catch {
        try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: there is no checkout at '{s}'", .{ name, path });
        return null;
    };
    defer dir.close(io);
    if (revision == null) {
        const status = try git.output(io, arena, dir, &.{ "status", "--porcelain" }) orelse "";
        if (std.mem.trim(u8, status, " \r\n").len > 0) {
            try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: '{s}' has changes that are not committed; commit them, or name the commit to pin", .{ name, path });
            return null;
        }
    }
    const where = try Io.Dir.path.join(arena, &.{ scratch, name });
    var snap = history.snapshotIn(io, arena, dir, revision orelse "HEAD", where) catch |e| {
        switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NoGit => try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: '{s}' is not a git repository", .{ name, path }),
            error.UnknownRevision => try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: there is no commit '{s}' in '{s}'", .{ name, revision orelse "HEAD", path }),
            error.SnapshotFailed => try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: its files could not be unpacked", .{name}),
        }
        return null;
    };
    defer snap.deinit();
    const entry: record.Entry = .{ .name = name, .commit = snap.commit, .fingerprint = try Network.ofProject(arena, &snap.graph, &snap.project.schema) };
    const short = snap.commit[0..12];

    const was = before orelse {
        try out.print(arena, "{s}: pinned at {s} ({d} items)\n", .{ name, short, snap.graph.items.len });
        return entry;
    };
    if (std.mem.eql(u8, was.commit, snap.commit)) {
        try out.print(arena, "{s}: still at {s}\n", .{ name, short });
        return entry;
    }
    var prior = history.snapshotIn(io, arena, dir, was.commit, where) catch {
        try out.print(arena, "{s}: {s} to {s}; the commit pinned before is not in its checkout, so what changed is not known\n", .{ name, was.commit[0..@min(was.commit.len, 12)], short });
        return entry;
    };
    defer prior.deinit();
    const changed = try changes.compute(arena, .{ .graph = &prior.graph, .schema = &prior.project.schema }, .{ .graph = &snap.graph, .schema = &snap.project.schema });
    var counts = [_]usize{ 0, 0, 0 };
    for (changed) |c| counts[@backingInt(c.kind)] += 1;
    try out.print(arena, "{s}: {s} to {s}: {d} added, {d} removed, {d} changed\n", .{ name, prior.commit[0..12], short, counts[0], counts[1], counts[2] });
    for (changed) |c| {
        if (!c.matters()) continue;
        const target = try arena.print("{s}:{s}", .{ name, c.id });
        const users = try referrers(arena, &ws.graph, target);
        if (users.len == 0) continue;
        try out.print(arena, "  {s} is {s}; referred to by {s}\n", .{ target, if (c.kind == .removed) "removed" else "changed", users });
    }
    return entry;
}

/// The items of `graph` that link or refer to `target`, joined by ", "
fn referrers(arena: std.mem.Allocator, graph: *const Graph, target: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (graph.items) |*item| {
        const refers = for (item.links) |l| {
            if (std.mem.eql(u8, l.target, target)) break true;
        } else for (item.references) |r| {
            if (std.mem.eql(u8, r.target, target)) break true;
        } else false;
        if (!refers) continue;
        if (out.items.len > 0) try out.appendSlice(arena, ", ");
        try out.appendSlice(arena, item.id);
    }
    return out.items;
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}
