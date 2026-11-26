//! A project as it was at an earlier commit: its `.skein/` and its
//! sources, taken out of git into a directory of their own.

const std = @import("std");
const Io = std.Io;

const Graph = @import("graph/Graph.zig");
const Project = @import("Project.zig");
const Report = @import("Report.zig");
const git = @import("git.zig");

pub const Error = error{
    /// git is not there, or this is no git repository
    NoGit,
    /// git knows no commit by that name
    UnknownRevision,
    /// what git gave could not be unpacked
    SnapshotFailed,
} || std.mem.Allocator.Error;

/// What the message of a baseline's tag starts with (`skein baseline`)
pub const baseline_mark = "skein baseline";

pub const Baseline = struct { name: []const u8, date: []const u8 };

/// The baselines, oldest first: the tags whose message starts with the
/// mark; none when there is no git
pub fn baselines(io: Io, arena: std.mem.Allocator, root: Io.Dir) std.mem.Allocator.Error![]const Baseline {
    var out: std.ArrayList(Baseline) = .empty;
    const refs = try git.output(io, arena, root, &.{ "for-each-ref", "--sort=creatordate", "--format=%(refname:short)%09%(creatordate:short)%09%(contents:subject)", "refs/tags" }) orelse return out.items;
    var lines = std.mem.splitScalar(u8, refs, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, std.mem.trimEnd(u8, line, "\r"), '\t');
        const name = fields.next() orelse continue;
        const date = fields.next() orelse continue;
        const subject = fields.next() orelse continue;
        if (std.mem.startsWith(u8, subject, baseline_mark ++ " ")) try out.append(arena, .{ .name = name, .date = date });
    }
    return out.items;
}

/// The newest baseline; null when there is none or no git
pub fn lastBaseline(io: Io, arena: std.mem.Allocator, root: Io.Dir) std.mem.Allocator.Error!?[]const u8 {
    const all = try baselines(io, arena, root);
    return if (all.len > 0) all[all.len - 1].name else null;
}

pub const Snapshot = struct {
    io: Io,
    /// where the files are
    dir: Io.Dir,
    /// its parent and its name there, to remove it
    parent: Io.Dir,
    name: []const u8,
    /// where the files are, as an absolute path
    path: []const u8 = "",
    /// the commit, in full
    commit: []const u8,
    project: Project,
    graph: Graph,

    /// Removes the files
    pub fn deinit(self: *Snapshot) void {
        self.dir.close(self.io);
        self.parent.deleteTree(self.io, self.name) catch {};
        self.parent.close(self.io);
    }
};

/// The project of the repository `root` at the commit `revision` (a
/// hash, a tag, a branch, `HEAD~2`). A commit without a `.skein/` gives
/// an empty project. What is wrong with the old project is not reported:
/// it is history.
pub fn snapshot(io: Io, arena: std.mem.Allocator, root: Io.Dir, revision: []const u8) Error!Snapshot {
    // inside git's own directory: never tracked, and there whenever git is
    return snapshotIn(io, arena, root, revision, try Io.Dir.path.join(arena, &.{ try gitDir(io, arena, root), "skein-snapshots" }));
}

/// The absolute path of the git directory of the repository `root` is in
pub fn gitDir(io: Io, arena: std.mem.Allocator, root: Io.Dir) Error![]const u8 {
    return trimmed(try git.output(io, arena, root, &.{ "rev-parse", "--absolute-git-dir" }) orelse return error.NoGit);
}

/// As `snapshot`, with the files unpacked under `scratch` (an absolute
/// path), so that another repository's own directory is left alone
pub fn snapshotIn(io: Io, arena: std.mem.Allocator, root: Io.Dir, revision: []const u8, scratch: []const u8) Error!Snapshot {
    _ = try gitDir(io, arena, root);
    const spec = try arena.print("{s}^{{commit}}", .{revision});
    const commit = trimmed(try git.output(io, arena, root, &.{ "rev-parse", "--verify", "--quiet", spec }) orelse return error.UnknownRevision);

    var parent = Io.Dir.cwd().createDirPathOpen(io, scratch, .{}) catch return error.SnapshotFailed;
    errdefer parent.close(io);
    parent.deleteTree(io, commit) catch {};
    var dir = parent.createDirPathOpen(io, commit, .{}) catch return error.SnapshotFailed;
    errdefer dir.close(io);

    var out: Snapshot = .{ .io = io, .dir = dir, .parent = parent, .name = commit, .path = try Io.Dir.path.join(arena, &.{ scratch, commit }), .commit = commit, .project = .{}, .graph = .{} };
    if (!try extract(io, arena, root, dir, commit, &.{Project.dir_name})) return out;

    var ignored: Report = .{ .arena = arena };
    out.project = try Project.load(io, arena, dir, &ignored);
    var paths: std.ArrayList([]const u8) = .empty;
    for (out.project.sources) |source| {
        // a path that is not in the commit would make git refuse them all
        const listed = try git.output(io, arena, root, &.{ "ls-tree", "-d", "--name-only", commit, "--", source.path }) orelse continue;
        if (trimmed(listed).len > 0) try paths.append(arena, source.path);
    }
    // and the files that cite items, for what coverage was then
    for (out.project.citations) |c| {
        const listed = try git.output(io, arena, root, &.{ "ls-tree", "--name-only", commit, "--", c.path }) orelse continue;
        if (trimmed(listed).len == 0) continue;
        for (paths.items) |p| {
            if (std.mem.eql(u8, p, c.path)) break;
        } else try paths.append(arena, c.path);
    }
    if (paths.items.len > 0) _ = try extract(io, arena, root, dir, commit, paths.items);
    out.graph = try Graph.load(io, arena, dir, &out.project, &ignored);
    return out;
}

/// Unpacks `paths` of `commit` into `dir`; false when the commit has none
/// of them
fn extract(io: Io, arena: std.mem.Allocator, root: Io.Dir, dir: Io.Dir, commit: []const u8, paths: []const []const u8) Error!bool {
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(arena, &.{ "archive", "--format=tar", commit, "--" });
    try args.appendSlice(arena, paths);
    const tar = try git.output(io, arena, root, args.items) orelse return false;
    var reader: Io.Reader = .fixed(tar);
    std.tar.extract(io, dir, &reader, .{ .mode_mode = .ignore }) catch return error.SnapshotFailed;
    return true;
}

fn trimmed(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}
