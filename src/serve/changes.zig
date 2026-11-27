//! The git side of `skein serve`'s saves (serve/Workflow.zig): a commit of
//! the files a save wrote, and the changes, each a branch `edit/NAME`,
//! started from the branch changes go to, merged into it, or proposed as
//! a pull request on the forge.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Forge = @import("../forge/Forge.zig");
const Workflow = @import("Workflow.zig");
const adapter = @import("../forge/adapter.zig");
const git = @import("../git.zig");
const github = @import("../forge/github.zig");
const history = @import("../history.zig");

pub const Done = union(enum) {
    /// what was done, to say
    ok: []const u8,
    failed: []const u8,
};

/// The branch checked out; null when none is (a detached HEAD), there is
/// no git, or git ignores the project's directory (the repository is
/// another's, as a test's directory in a build cache)
pub fn current(io: Io, a: Allocator, root: Io.Dir) Allocator.Error!?[]const u8 {
    switch (try git.run(io, a, root, &.{ "check-ignore", "-q", "." })) {
        .ok => return null,
        .failed => {},
    }
    const out = try git.output(io, a, root, &.{ "symbolic-ref", "--quiet", "--short", "HEAD" }) orelse return null;
    const name = std.mem.trim(u8, out, " \r\n");
    return if (name.len > 0) name else null;
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

/// Starts the change `name` from `target`, and checks it out
pub fn start(io: Io, a: Allocator, root: Io.Dir, target: []const u8, name: []const u8) Allocator.Error!Done {
    if (!Workflow.validName(name)) return .{ .failed = "a change is named in lowercase letters, digits and dashes, as fix-lexing" };
    const branch = try branchOf(a, name);
    switch (try git.run(io, a, root, &.{ "switch", "--quiet", "-c", branch, target })) {
        .ok => {},
        .failed => |why| return .{ .failed = why },
    }
    // where it goes, for a `skein serve` started on it later
    _ = try git.run(io, a, root, &.{ "config", try a.print("branch.{s}.skein-target", .{branch}), target });
    return .{ .ok = try a.print("started the change {s}", .{name}) };
}

/// The branch the change `name` goes to, as recorded when it was started
pub fn targetOf(io: Io, a: Allocator, root: Io.Dir, name: []const u8) Allocator.Error!?[]const u8 {
    const out = try git.output(io, a, root, &.{ "config", try a.print("branch.{s}.skein-target", .{try branchOf(a, name)}) }) orelse return null;
    const t = std.mem.trim(u8, out, " \r\n");
    return if (t.len > 0) t else null;
}

/// Checks out the change `name`, or `target` when it is null
pub fn checkOut(io: Io, a: Allocator, root: Io.Dir, target: []const u8, name: ?[]const u8) Allocator.Error!Done {
    const branch = if (name) |n| try branchOf(a, n) else target;
    return run(io, a, root, &.{ "switch", "--quiet", branch }, try a.print("on {s}", .{branch}));
}

/// Merges the change `name` into `target`, and deletes its branch
pub fn merge(io: Io, a: Allocator, root: Io.Dir, target: []const u8, name: []const u8) Allocator.Error!Done {
    const branch = try branchOf(a, name);
    switch (try git.run(io, a, root, &.{ "switch", "--quiet", target })) {
        .ok => {},
        .failed => |why| return .{ .failed = why },
    }
    switch (try git.run(io, a, root, &.{ "merge", "--quiet", "--no-ff", "-m", try a.print("Merge change {s}", .{name}), branch })) {
        .ok => {},
        .failed => |why| {
            _ = try git.run(io, a, root, &.{ "merge", "--abort" });
            return .{ .failed = try a.print("the change {s} does not merge into {s} cleanly; nothing was merged ({s})", .{ name, target, why }) };
        },
    }
    return run(io, a, root, &.{ "branch", "--quiet", "-d", branch }, try a.print("merged the change {s} into {s}", .{ name, target }));
}

/// Deletes the change `name`, unmerged, after checking out `target`
pub fn abandon(io: Io, a: Allocator, root: Io.Dir, target: []const u8, name: []const u8) Allocator.Error!Done {
    switch (try git.run(io, a, root, &.{ "switch", "--quiet", target })) {
        .ok => {},
        .failed => |why| return .{ .failed = why },
    }
    return run(io, a, root, &.{ "branch", "--quiet", "-D", try branchOf(a, name) }, try a.print("abandoned the change {s}", .{name}));
}

/// Pushes the change `name` and proposes it on `forge` as a pull request
/// into `target`, then checks out `target`; says the pull request's address
pub fn propose(io: Io, a: Allocator, root: Io.Dir, forge: *const Forge, target: []const u8, name: []const u8) !Done {
    const branch = try branchOf(a, name);
    switch (try git.run(io, a, root, &.{ "-c", "credential.interactive=never", "push", "--quiet", "-u", "origin", branch })) {
        .ok => {},
        .failed => |why| return .{ .failed = try a.print("the change could not be pushed: {s}", .{why}) },
    }
    const title = try a.print("Change {s}", .{name});
    const body = "Proposed from skein serve.";
    const path, const json = switch (forge.kind) {
        .github, .forgejo => .{ try a.print("repos/{s}/pulls", .{forge.repository}), try a.print("{{\"title\":{f},\"head\":{f},\"base\":{f},\"body\":{f}}}", .{ fmt(title), fmt(branch), fmt(target), fmt(body) }) },
        .gitlab => .{ try a.print("projects/{s}/merge_requests", .{try gitlabProject(a, forge.repository)}), try a.print("{{\"title\":{f},\"source_branch\":{f},\"target_branch\":{f},\"description\":{f}}}", .{ fmt(title), fmt(branch), fmt(target), fmt(body) }) },
    };
    const git_dir = history.gitDir(io, a, root) catch return .{ .failed = "this is no git repository" };
    const body_path = try Io.Dir.path.join(a, &.{ git_dir, "skein", "forge", "pull.json" });
    const reply = try adapter.send(io, a, forge, "POST", path, json, body_path);
    const url = switch (reply) {
        .body => |b| addressIn(a, b) orelse "",
        .missing => return .{ .failed = "the forge has no such repository" },
        .unreachable_ => |why| return .{ .failed = try a.print("the change was pushed, and the pull request could not be opened: {s}", .{why}) },
    };
    _ = try git.run(io, a, root, &.{ "switch", "--quiet", target });
    return .{ .ok = try a.print("proposed the change {s}: {s}", .{ name, url }) };
}

fn fmt(s: []const u8) std.json.Formatter([]const u8) {
    return std.json.fmt(s, .{});
}

/// `owner/repo` as GitLab's API names a project
fn gitlabProject(a: Allocator, repository: []const u8) ![]const u8 {
    return std.mem.replaceOwned(u8, a, repository, "/", "%2F");
}

/// The web address of a pull request, from the forge's answer
fn addressIn(a: Allocator, body: []const u8) ?[]const u8 {
    const v = std.json.parseFromSliceLeaky(std.json.Value, a, body, .{}) catch return null;
    if (v != .object) return null;
    for ([_][]const u8{ "html_url", "web_url" }) |k| {
        if (v.object.get(k)) |u| if (u == .string) return u.string;
    }
    return null;
}

fn branchOf(a: Allocator, name: []const u8) ![]const u8 {
    return a.print("{s}{s}", .{ Workflow.change_prefix, name });
}

fn run(io: Io, a: Allocator, root: Io.Dir, args: []const []const u8, said: []const u8) Allocator.Error!Done {
    return switch (try git.run(io, a, root, args)) {
        .ok => .{ .ok = said },
        .failed => |why| .{ .failed = why },
    };
}

test {
    _ = github;
}
