//! Each change of `skein serve` (a branch `edit/NAME`) in a git worktree of
//! its own, under the repository's git directory (`skein/changes/NAME`), so
//! that several people's changes are edited at once and the checkout that
//! serves stays on the branch changes go to (#281).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Workflow = @import("Workflow.zig");
const changes = @import("changes.zig");
const git = @import("../git.zig");

const Done = changes.Done;

/// Where the change `name` is worked on: its worktree, and the project in it
/// (the project's directory may be below the repository's top)
pub const Place = struct { worktree: []const u8, project: []const u8 };

/// The place of the change `name`, for the project at `root`
pub fn place(io: Io, a: Allocator, root: Io.Dir, name: []const u8) Allocator.Error!?Place {
    const common_out = try git.output(io, a, root, &.{ "rev-parse", "--path-format=absolute", "--git-common-dir" }) orelse return null;
    const common = std.mem.trim(u8, common_out, " \r\n");
    const prefix_out = try git.output(io, a, root, &.{ "rev-parse", "--show-prefix" }) orelse return null;
    const prefix = std.mem.trimEnd(u8, std.mem.trim(u8, prefix_out, " \r\n"), "/");
    const worktree = try Io.Dir.path.join(a, &.{ common, "skein", "changes", name });
    return .{ .worktree = worktree, .project = if (prefix.len > 0) try Io.Dir.path.join(a, &.{ worktree, prefix }) else worktree };
}

/// Starts the change `name` from `target`, in a worktree of its own
pub fn start(io: Io, a: Allocator, root: Io.Dir, target: []const u8, name: []const u8) Allocator.Error!Done {
    if (!Workflow.validName(name)) return .{ .failed = "a change is named in lowercase letters, digits and dashes, as fix-lexing" };
    const p = try place(io, a, root, name) orelse return .{ .failed = "the project is not in a git checkout" };
    const branch = try changes.branchOf(a, name);
    switch (try git.run(io, a, root, &.{ "worktree", "add", "--quiet", "-b", branch, p.worktree, target })) {
        .ok => {},
        .failed => |why| return .{ .failed = why },
    }
    // where it goes, for a `skein serve` that opens it later
    _ = try git.run(io, a, root, &.{ "config", try a.print("branch.{s}.skein-target", .{branch}), target });
    return .{ .ok = try a.print("started the change {s}", .{name}) };
}

/// The change `name` in its worktree, made again when it is not there (a
/// change proposed, or started elsewhere); its project's directory
pub fn open(io: Io, a: Allocator, root: Io.Dir, name: []const u8) Allocator.Error!union(enum) { ok: []const u8, failed: []const u8 } {
    const p = try place(io, a, root, name) orelse return .{ .failed = "the project is not in a git checkout" };
    if (Io.Dir.cwd().access(io, p.worktree, .{})) |_| return .{ .ok = p.project } else |_| {}
    switch (try git.run(io, a, root, &.{ "worktree", "add", "--quiet", p.worktree, try changes.branchOf(a, name) })) {
        .ok => return .{ .ok = p.project },
        .failed => |why| return .{ .failed = why },
    }
}

/// Takes the change's worktree away; its branch stays
pub fn close(io: Io, a: Allocator, root: Io.Dir, name: []const u8) Allocator.Error!void {
    const p = try place(io, a, root, name) orelse return;
    _ = try git.run(io, a, root, &.{ "worktree", "remove", "--force", p.worktree });
}

/// Merges the change `name` into `target`, which the checkout at `root` is
/// on, and deletes it
pub fn merge(io: Io, a: Allocator, root: Io.Dir, target: []const u8, name: []const u8) Allocator.Error!Done {
    const on = try changes.current(io, a, root) orelse return .{ .failed = "the project is not in a git checkout" };
    if (!std.mem.eql(u8, on, target)) return .{ .failed = try a.print("the checkout that serves is on {s}, and changes go to {s}: nothing was merged", .{ on, target }) };
    const branch = try changes.branchOf(a, name);
    switch (try git.run(io, a, root, &.{ "merge", "--quiet", "--no-ff", "-m", try a.print("Merge change {s}", .{name}), branch })) {
        .ok => {},
        .failed => |why| {
            _ = try git.run(io, a, root, &.{ "merge", "--abort" });
            return .{ .failed = try a.print("the change {s} does not merge into {s} cleanly; nothing was merged ({s})", .{ name, target, why }) };
        },
    }
    try close(io, a, root, name);
    _ = try git.run(io, a, root, &.{ "branch", "--quiet", "-d", branch });
    return .{ .ok = try a.print("merged the change {s} into {s}", .{ name, target }) };
}

/// Deletes the change `name`, unmerged
pub fn abandon(io: Io, a: Allocator, root: Io.Dir, name: []const u8) Allocator.Error!Done {
    try close(io, a, root, name);
    return switch (try git.run(io, a, root, &.{ "branch", "--quiet", "-D", try changes.branchOf(a, name) })) {
        .ok => .{ .ok = try a.print("abandoned the change {s}", .{name}) },
        .failed => |why| .{ .failed = why },
    };
}

/// Brings `target` up to its upstream before a change starts from it,
/// when it has one; why it could not, or null
pub fn pull(io: Io, a: Allocator, root: Io.Dir, target: []const u8) Allocator.Error!?[]const u8 {
    if (try git.output(io, a, root, &.{ "rev-parse", "--abbrev-ref", try a.print("{s}@{{upstream}}", .{target}) }) == null) return null;
    const on = try changes.current(io, a, root) orelse return null;
    if (!std.mem.eql(u8, on, target)) return null;
    return switch (try git.run(io, a, root, &.{ "-c", "credential.interactive=never", "pull", "--quiet", "--ff-only" })) {
        .ok => null,
        .failed => |why| why,
    };
}

/// Pushes `target` to its upstream after a merge or commit, when it has
/// one; why it could not, or null
pub fn push(io: Io, a: Allocator, root: Io.Dir, target: []const u8) Allocator.Error!?[]const u8 {
    if (try git.output(io, a, root, &.{ "rev-parse", "--abbrev-ref", try a.print("{s}@{{upstream}}", .{target}) }) == null) return null;
    return switch (try git.run(io, a, root, &.{ "-c", "credential.interactive=never", "push", "--quiet" })) {
        .ok => null,
        .failed => |why| why,
    };
}
