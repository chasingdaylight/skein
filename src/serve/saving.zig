//! How `skein serve`'s saves reach git, as the project chose
//! (serve/Workflow.zig): before a save, whether it may go ahead where the
//! checkout is; after it, the commit of what it wrote; and the requests
//! that start, check out, merge, propose or abandon a change.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Site = @import("Site.zig");
const Workflow = @import("Workflow.zig");
const Workspace = @import("../commands/Workspace.zig");
const changes = @import("changes.zig");

pub const State = struct {
    mode: Workflow.Save,
    /// the branch changes go to; null when it cannot be told
    target: ?[]const u8,
    /// the branch checked out; null without git
    branch: ?[]const u8,
    /// the change checked out
    change: ?[]const u8,
    changes: []const changes.Change,
    /// whether a change can be proposed: the project names its forge
    forge: bool,
};

pub fn state(arena: Allocator, s: *Site, ws: *Workspace) !State {
    const w = ws.project.workflow;
    const branch = try changes.current(s.io, arena, ws.root);
    const target = w.branch orelse if (s.start_branch) |b| (if (changes.changeOf(b)) |c| try changes.targetOf(s.io, arena, ws.root, c) else b) else null;
    return .{
        .mode = w.mode(ws.project.forge != null),
        .target = target,
        .branch = branch,
        .change = changes.changeOf(branch),
        .changes = if (target) |t| try changes.list(s.io, arena, ws.root, t) else &.{},
        .forge = ws.project.forge != null,
    };
}

pub const Refusal = struct {
    message: []const u8,
    /// a change must be started first; the page offers to
    needs_change: bool = false,
};

/// Why a save may not go ahead with the checkout as it is; null when it may.
/// Without git, a save is written and not committed.
pub fn before(arena: Allocator, st: State) !?Refusal {
    const branch = st.branch orelse return null;
    const target = st.target orelse return .{ .message = "skein serve: say which branch changes go to, as [serve] branch = \"dev\" in .skein/config.toml" };
    switch (st.mode) {
        .commit => if (!std.mem.eql(u8, branch, target)) return .{ .message = try arena.print("skein serve: saves are committed to {s}, and the checkout is on {s}", .{ target, branch }) },
        .branch, .@"pull-request" => if (st.change == null) return .{ .message = try arena.print("skein serve: a save goes into a change, which is merged into {s} after; start one", .{target}), .needs_change = true },
    }
    return null;
}

/// Commits `files`, which a save wrote, with `message`; why it could not
/// be, or null. Nothing is committed without git.
pub fn after(arena: Allocator, s: *Site, ws: *Workspace, st: State, files: []const []const u8, message: []const u8) !?[]const u8 {
    if (st.branch == null) return null;
    return switch (try changes.commit(s.io, arena, ws.root, files, message, null)) {
        .ok => null,
        .failed => |why| try arena.print("saved, and not committed: {s}", .{why}),
    };
}

/// `POST change` (`{action, name}`): `start` a change, `open` one (none:
/// the branch changes go to), `merge` it, `propose` it, `abandon` it
pub fn change(arena: Allocator, s: *Site, ws: *Workspace, value: json.Value) !changes.Done {
    const st = try state(arena, s, ws);
    if (st.branch == null) return .{ .failed = "skein serve: the project is not in a git checkout" };
    const target = st.target orelse return .{ .failed = "skein serve: say which branch changes go to, as [serve] branch = \"dev\" in .skein/config.toml" };
    const action = field(value, "action");
    const name = field(value, "name");
    const eql = std.mem.eql;
    if (eql(u8, action, "start")) return changes.start(s.io, arena, ws.root, target, name);
    if (eql(u8, action, "open")) return changes.checkOut(s.io, arena, ws.root, target, if (name.len > 0) name else null);
    if (name.len == 0) return .{ .failed = "skein serve: which change?" };
    if (eql(u8, action, "abandon")) return changes.abandon(s.io, arena, ws.root, target, name);
    if (eql(u8, action, "merge")) {
        if (st.mode == .@"pull-request") return .{ .failed = "skein serve: this project's changes are merged on the forge: propose it" };
        return changes.merge(s.io, arena, ws.root, target, name);
    }
    if (eql(u8, action, "propose")) {
        const forge = ws.project.forge orelse return .{ .failed = "skein serve: the project names no forge to propose it on" };
        if (s.options.common.offline) return .{ .failed = "skein serve: proposing needs the forge: not with --offline" };
        return changes.propose(s.io, arena, ws.root, &forge, target, name);
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
