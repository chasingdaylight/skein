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
const fetch = @import("../network/fetch.zig");
const git = @import("../git.zig");
const history = @import("../history.zig");
const identity = @import("../network/identity.zig");
const record = @import("../network/record.zig");
const Report = @import("../Report.zig");

/// What pinning one repository gives: its entry, and what it says of its own network
const Pinned = struct { entry: record.Entry, source: identity.Source };

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

    const old = (try record.read(io, arena, ws.root, &ws.report)).entries;
    var entries: std.ArrayList(record.Entry) = .empty;
    var sources: std.ArrayList(identity.Source) = .empty;
    var out: std.ArrayList(u8) = .empty;
    for (repositories) |repository| {
        const named = if (options.name) |name| std.mem.eql(u8, name, repository.name) else true;
        if (repository.path) |path| if (try Network.submoduleCommit(io, arena, ws.root, path)) |c| {
            // git records it; what it says of its network still counts
            if (named) try out.print(arena, "{s}: a submodule, recorded by git at {s}\n", .{ repository.name, c[0..@min(c.len, 12)] });
            if (ws.network.member(repository.name)) |m| try sources.append(arena, .{ .name = m.repository.name, .id = m.project.id, .record = m.recorded });
            continue;
        };
        if (!named) {
            if (record.find(old, repository.name)) |e| try entries.append(arena, e);
            if (ws.network.member(repository.name)) |m| if (m.unavailable == null) try sources.append(arena, .{ .name = m.repository.name, .id = m.project.id, .record = m.recorded });
            continue;
        }
        const pinned = try pinOne(io, arena, &ws, repository, options.revision, git_dir, options.common.offline, record.find(old, repository.name), &out) orelse continue;
        try entries.append(arena, pinned.entry);
        try sources.append(arena, pinned.source);
    }
    const reached = try identity.reached(arena, &ws.project, sources.items, &ws.report);
    if (!ws.report.ok()) return ws.problems();
    ws.root.writeFile(io, .{ .sub_path = record.file, .data = try record.render(arena, .{ .entries = entries.items, .reached = reached }) }) catch |e|
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
    git_dir: []const u8,
    offline: bool,
    before: ?record.Entry,
    out: *std.ArrayList(u8),
) !?Pinned {
    const name = repository.name;
    const where_from = repository.path orelse repository.url.?;
    var o = switch (try Network.origin(io, arena, ws.root_path, git_dir, repository)) {
        .ok => |o| o,
        .failed => |why| {
            try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: {s}", .{ name, why });
            return null;
        },
    };
    defer o.dir.close(io);
    const dir = o.dir;
    if (o.fetched) {
        // what to read is fetched first: a commit by its hash, else a branch or tag
        const url = repository.url.?;
        const given = revision orelse repository.ref;
        const ok = if (given != null and fetch.isHash(given.?)) try fetch.commit(io, arena, dir, url, given.?, offline) else try fetch.tip(io, arena, dir, url, given, offline) != null;
        if (!ok) {
            try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: {s}", .{ name, try Network.notFetched(arena, repository, offline, if (given != null and fetch.isHash(given.?)) given else null) });
            return null;
        }
    } else if (revision == null) {
        const status = try git.output(io, arena, dir, &.{ "status", "--porcelain" }) orelse "";
        if (std.mem.trim(u8, status, " \r\n").len > 0) {
            try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: '{s}' has changes that are not committed; commit them, or name the commit to pin", .{ name, where_from });
            return null;
        }
    }
    // in a cache, a branch or tag fetched is read from where `tip` put it
    const read_at = if (o.fetched and !(revision != null and fetch.isHash(revision.?))) fetch.current_ref else revision orelse "HEAD";
    const where = try Io.Dir.path.join(arena, &.{ git_dir, "skein", "snapshots", name });
    var snap = history.snapshotIn(io, arena, dir, read_at, where) catch |e| {
        switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NoGit => try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: '{s}' is not a git repository", .{ name, where_from }),
            error.UnknownRevision => try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: there is no commit '{s}' in '{s}'", .{ name, revision orelse "HEAD", where_from }),
            error.SnapshotFailed => try ws.report.add(Project.config_file, 0, 0, "repositories: {s}: its files could not be unpacked", .{name}),
        }
        return null;
    };
    defer snap.deinit();
    var ignored: Report = .{ .arena = arena };
    const entry: Pinned = .{
        .entry = .{ .name = name, .commit = snap.commit, .fingerprint = try Network.ofProject(arena, &snap.graph, &snap.project.schema), .id = snap.project.id },
        .source = .{ .name = name, .id = snap.project.id, .record = try record.read(io, arena, snap.dir, &ignored) },
    };
    const short = snap.commit[0..12];

    const was = before orelse {
        try out.print(arena, "{s}: pinned at {s} ({d} items)\n", .{ name, short, snap.graph.items.len });
        return entry;
    };
    if (std.mem.eql(u8, was.commit, snap.commit)) {
        try out.print(arena, "{s}: still at {s}\n", .{ name, short });
        return entry;
    }
    if (o.fetched) _ = try fetch.commit(io, arena, dir, repository.url.?, was.commit, offline);
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
