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

pub const Snapshot = struct {
    io: Io,
    /// where the files are
    dir: Io.Dir,
    /// its parent and its name there, to remove it
    parent: Io.Dir,
    name: []const u8,
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
    const git_dir = trimmed(try git.output(io, arena, root, &.{ "rev-parse", "--absolute-git-dir" }) orelse return error.NoGit);
    const spec = try arena.print("{s}^{{commit}}", .{revision});
    const commit = trimmed(try git.output(io, arena, root, &.{ "rev-parse", "--verify", "--quiet", spec }) orelse return error.UnknownRevision);

    // inside git's own directory: never tracked, and there whenever git is
    var parent = Io.Dir.cwd().createDirPathOpen(io, try Io.Dir.path.join(arena, &.{ git_dir, "skein-snapshots" }), .{}) catch return error.SnapshotFailed;
    errdefer parent.close(io);
    parent.deleteTree(io, commit) catch {};
    var dir = parent.createDirPathOpen(io, commit, .{}) catch return error.SnapshotFailed;
    errdefer dir.close(io);

    var out: Snapshot = .{ .io = io, .dir = dir, .parent = parent, .name = commit, .commit = commit, .project = .{}, .graph = .{} };
    if (!try extract(io, arena, root, dir, commit, &.{Project.dir_name})) return out;

    var ignored: Report = .{ .arena = arena };
    out.project = try Project.load(io, arena, dir, &ignored);
    var paths: std.ArrayList([]const u8) = .empty;
    for (out.project.sources) |source| {
        // a path that is not in the commit would make git refuse them all
        const listed = try git.output(io, arena, root, &.{ "ls-tree", "-d", "--name-only", commit, "--", source.path }) orelse continue;
        if (trimmed(listed).len > 0) try paths.append(arena, source.path);
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
