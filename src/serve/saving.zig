//! How `skein serve`'s saves reach git, as the project chose
//! (serve/Workflow.zig): before a save, whether it may go ahead where the
//! person works; after it, the commit of what it wrote, as them; and the
//! requests that start, open, leave, merge, propose or abandon a change,
//! each in a worktree of its own (serve/worktrees.zig).

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Context = @import("Context.zig");
const Workflow = @import("Workflow.zig");
const Workspace = @import("../commands/Workspace.zig");
const changes = @import("changes.zig");
const propose = @import("propose.zig");
const worktrees = @import("worktrees.zig");

pub const State = struct {
    mode: Workflow.Save,
    /// the branch changes go to; null when it cannot be told
    target: ?[]const u8,
    /// the branch the checkout that serves is on; null without git
    branch: ?[]const u8,
    /// the change this person has open
    change: ?[]const u8,
    changes: []const changes.Change,
    /// whether a change can be proposed: the project names its forge
    forge: bool,
    /// who saves, when people sign in
    user: ?[]const u8,
};

/// `ws` is the project of the checkout that serves
pub fn state(arena: Allocator, c: *Context, ws: *const Workspace) !State {
    const w = ws.project.workflow;
    const io = c.main.io;
    const branch = try changes.current(io, arena, c.main.root);
    const start = c.main.start_branch;
    const target = w.branch orelse if (start) |b| (if (changes.changeOf(b)) |n| try changes.targetOf(io, arena, c.main.root, n) else b) else null;
    return .{
        .mode = w.mode(ws.project.forge != null),
        .target = target,
        .branch = branch,
        .change = c.people.changeOf(c.login()),
        .changes = if (target != null and branch != null) try changes.list(io, arena, c.main.root, target.?) else &.{},
        .forge = ws.project.forge != null,
        .user = if (c.user) |u| u.login else null,
    };
}

pub const Refusal = struct {
    message: []const u8,
    /// a change must be started first; the page offers to
    needs_change: bool = false,
};

/// Why a save may not go ahead; null when it may. Without git, a save is
/// written and not committed.
pub fn before(arena: Allocator, st: State) !?Refusal {
    const branch = st.branch orelse return null;
    const target = st.target orelse return .{ .message = "skein serve: say which branch changes go to, as [serve] branch = \"dev\" in .skein/config.toml" };
    switch (st.mode) {
        .commit => if (!std.mem.eql(u8, branch, target)) return .{ .message = try arena.print("skein serve: saves are committed to {s}, and the checkout that serves is on {s}", .{ target, branch }) },
        .branch, .@"pull-request" => if (st.change == null) return .{ .message = try arena.print("skein serve: a save goes into a change, which is merged into {s} after; start one", .{target}), .needs_change = true },
    }
    return null;
}

/// Commits `files`, which a save wrote where the person works, with
/// `message`, as them; with `commit`, pushes the branch when it has an
/// upstream. Why something could not be done, or null.
pub fn after(arena: Allocator, c: *Context, st: State, files: []const []const u8, message: []const u8) !?[]const u8 {
    if (st.branch == null) return null;
    const author = if (c.user) |u| try u.author(arena) else null;
    switch (try changes.commit(c.site.io, arena, c.site.root, files, message, author)) {
        .ok => {},
        .failed => |why| return try arena.print("saved, and not committed: {s}", .{why}),
    }
    if (st.mode == .commit) if (try worktrees.push(c.main.io, arena, c.main.root, st.target.?)) |why| return try arena.print("committed, and not pushed: {s}", .{why});
    return null;
}

/// `POST change` (`{action, name}`): `start` a change, `open` one (none:
/// leave it), `merge` it, `propose` it, `abandon` it. `ws` is the project
/// of the checkout that serves.
pub fn change(arena: Allocator, c: *Context, ws: *const Workspace, value: json.Value) !changes.Done {
    const st = try state(arena, c, ws);
    if (st.branch == null) return .{ .failed = "skein serve: the project is not in a git checkout" };
    const target = st.target orelse return .{ .failed = "skein serve: say which branch changes go to, as [serve] branch = \"dev\" in .skein/config.toml" };
    const io = c.main.io;
    const root = c.main.root;
    const action = field(value, "action");
    const name = field(value, "name");
    const eql = std.mem.eql;
    if (eql(u8, action, "start")) {
        if (try worktrees.pull(io, arena, root, target)) |why| return .{ .failed = try arena.print("{s} could not be brought up to date first: {s}", .{ target, why }) };
        const done = try worktrees.start(io, arena, root, target, name);
        if (done == .ok) try c.people.setChange(c.login(), name);
        return done;
    }
    if (eql(u8, action, "open")) {
        if (name.len == 0) {
            try c.people.setChange(c.login(), null);
            return .{ .ok = try arena.print("back on {s}", .{target}) };
        }
        return switch (try worktrees.open(io, arena, root, name)) {
            .ok => blk: {
                try c.people.setChange(c.login(), name);
                break :blk .{ .ok = try arena.print("opened the change {s}", .{name}) };
            },
            .failed => |why| .{ .failed = why },
        };
    }
    if (name.len == 0) return .{ .failed = "skein serve: which change?" };
    // its site lets go of its worktree before the worktree is taken away
    c.sites.drop(name);
    if (eql(u8, action, "abandon")) {
        c.people.closeChange(name);
        return worktrees.abandon(io, arena, root, name);
    }
    if (eql(u8, action, "merge")) {
        if (st.mode == .@"pull-request") return .{ .failed = "skein serve: this project's changes are merged on the forge: propose it" };
        const done = try worktrees.merge(io, arena, root, target, name);
        if (done == .failed) return done;
        c.people.closeChange(name);
        if (try worktrees.push(io, arena, root, target)) |why| return .{ .ok = try arena.print("{s}, and not pushed: {s}", .{ done.ok, why }) };
        return done;
    }
    if (eql(u8, action, "propose")) {
        const forge = ws.project.forge orelse return .{ .failed = "skein serve: the project names no forge to propose it on" };
        if (c.main.options.common.offline) return .{ .failed = "skein serve: proposing needs the forge: not with --offline" };
        const done = try propose.propose(io, arena, root, &forge, target, name);
        if (done == .ok) c.people.closeChange(name);
        return done;
    }
    return .{ .failed = "skein serve: no such action" };
}

fn field(v: json.Value, key: []const u8) []const u8 {
    if (v != .object) return "";
    const x = v.object.get(key) orelse return "";
    return if (x == .string) x.string else "";
}

test {
    _ = @import("_test/saving.zig");
}
