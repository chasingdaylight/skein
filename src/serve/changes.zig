//! The git side of `skein serve`'s saves (serve/Workflow.zig): the branch
//! checked out, a commit of the files a save wrote, and the changes there
//! are, each a branch `edit/NAME` (serve/worktrees.zig).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Workflow = @import("Workflow.zig");
const git = @import("../git.zig");

pub const Done = union(enum) {
    /// what was done, to say
    ok: []const u8,
    failed: []const u8,
};

/// The branch checked out; null when none is (a detached HEAD), there is
/// no git, or git ignores the project's directory (the repository is
/// another's, as a test's directory in a build cache)
pub fn current(io: Io, a: Allocator, root: Io.Dir) Allocator.Error!?[]const u8 {
    if (try ignored(io, a, root)) return null;
    const out = try git.output(io, a, root, &.{ "symbolic-ref", "--quiet", "--short", "HEAD" }) orelse return null;
    const name = std.mem.trim(u8, out, " \r\n");
    return if (name.len > 0) name else null;
}

/// Whether git ignores the directory `root`: its repository is another's
pub fn ignored(io: Io, a: Allocator, root: Io.Dir) Allocator.Error!bool {
    return try git.run(io, a, root, &.{ "check-ignore", "-q", "." }) == .ok;
}

/// The name of the change checked out, when one is
pub fn changeOf(branch: ?[]const u8) ?[]const u8 {
    const b = branch orelse return null;
    return if (std.mem.startsWith(u8, b, Workflow.change_prefix)) b[Workflow.change_prefix.len..] else null;
}

pub const Change = struct { name: []const u8, commits: usize };

/// The changes there are, with how many commits each has that `target` has not
pub fn list(io: Io, a: Allocator, root: Io.Dir, target: []const u8) Allocator.Error![]const Change {
    var out: std.ArrayList(Change) = .empty;
    const refs = try git.output(io, a, root, &.{ "for-each-ref", "--format=%(refname:short)", "refs/heads/" ++ Workflow.change_prefix }) orelse return out.items;
    var lines = std.mem.tokenizeAny(u8, refs, "\r\n");
    while (lines.next()) |branch| {
        const count = try git.output(io, a, root, &.{ "rev-list", "--count", try a.print("{s}..{s}", .{ target, branch }) }) orelse "0";
        try out.append(a, .{ .name = branch[Workflow.change_prefix.len..], .commits = std.fmt.parseInt(usize, std.mem.trim(u8, count, " \r\n"), 10) catch 0 });
    }
    return out.items;
}

/// Commits `files` alone, with `message`, as `author` when given (`Name <email>`)
pub fn commit(io: Io, a: Allocator, root: Io.Dir, files: []const []const u8, message: []const u8, author: ?[]const u8) Allocator.Error!Done {
    // a save that changed nothing has nothing to commit
    var status: std.ArrayList([]const u8) = .empty;
    try status.appendSlice(a, &.{ "status", "--porcelain", "--" });
    try status.appendSlice(a, files);
    if (try git.output(io, a, root, status.items)) |out| if (std.mem.trim(u8, out, " \r\n").len == 0) return .{ .ok = "nothing changed" };
    var add: std.ArrayList([]const u8) = .empty;
    try add.appendSlice(a, &.{ "add", "--" });
    try add.appendSlice(a, files);
    switch (try git.run(io, a, root, add.items)) {
        .ok => {},
        .failed => |why| return .{ .failed = why },
    }
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(a, &.{ "commit", "--quiet", "-m", message });
    if (author) |who| try args.append(a, try a.print("--author={s}", .{who}));
    try args.append(a, "--");
    try args.appendSlice(a, files);
    return switch (try git.run(io, a, root, args.items)) {
        .ok => .{ .ok = try a.print("committed: {s}", .{message}) },
        .failed => |why| .{ .failed = why },
    };
}

/// The branch the change `name` goes to, as recorded when it was started
pub fn targetOf(io: Io, a: Allocator, root: Io.Dir, name: []const u8) Allocator.Error!?[]const u8 {
    const out = try git.output(io, a, root, &.{ "config", try a.print("branch.{s}.skein-target", .{try branchOf(a, name)}) }) orelse return null;
    const t = std.mem.trim(u8, out, " \r\n");
    return if (t.len > 0) t else null;
}

/// The branch of the change `name`
pub fn branchOf(a: Allocator, name: []const u8) ![]const u8 {
    return a.print("{s}{s}", .{ Workflow.change_prefix, name });
}
