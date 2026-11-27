// cspell:ignore Fspec
//! A change of `skein serve` proposed on the forge (`save = "pull-request"`):
//! its branch pushed, a pull request opened into the branch changes go to
//! (GitHub's and Forgejo's `pulls`, GitLab's `merge_requests`), and its
//! worktree taken away; the branch stays until the forge merges it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Forge = @import("../forge/Forge.zig");
const adapter = @import("../forge/adapter.zig");
const changes = @import("changes.zig");
const git = @import("../git.zig");
const history = @import("../history.zig");
const worktrees = @import("worktrees.zig");

/// Says the pull request's address
pub fn propose(io: Io, a: Allocator, root: Io.Dir, forge: *const Forge, target: []const u8, name: []const u8) !changes.Done {
    const branch = try changes.branchOf(a, name);
    switch (try git.run(io, a, root, &.{ "-c", "credential.interactive=never", "push", "--quiet", "-u", "origin", branch })) {
        .ok => {},
        .failed => |why| return .{ .failed = try a.print("the change could not be pushed: {s}", .{why}) },
    }
    const path, const json = try request(a, forge, target, name);
    const git_dir = history.gitDir(io, a, root) catch return .{ .failed = "this is no git repository" };
    const body_path = try Io.Dir.path.join(a, &.{ git_dir, "skein", "forge", "pull.json" });
    const url = switch (try adapter.send(io, a, forge, "POST", path, json, body_path)) {
        .body => |b| addressIn(a, b) orelse "",
        .missing => return .{ .failed = "the forge has no such repository" },
        .unreachable_ => |why| return .{ .failed = try a.print("the change was pushed, and the pull request could not be opened: {s}", .{why}) },
    };
    try worktrees.close(io, a, root, name);
    return .{ .ok = try a.print("proposed the change {s}: {s}", .{ name, url }) };
}

/// The path and body of the request that opens the pull request
pub fn request(a: Allocator, forge: *const Forge, target: []const u8, name: []const u8) !struct { []const u8, []const u8 } {
    const branch = try changes.branchOf(a, name);
    const title = try a.print("Change {s}", .{name});
    const body = "Proposed from skein serve.";
    return switch (forge.kind) {
        .github, .forgejo => .{ try a.print("repos/{s}/pulls", .{forge.repository}), try a.print("{{\"title\":{f},\"head\":{f},\"base\":{f},\"body\":{f}}}", .{ fmt(title), fmt(branch), fmt(target), fmt(body) }) },
        .gitlab => .{ try a.print("projects/{s}/merge_requests", .{try std.mem.replaceOwned(u8, a, forge.repository, "/", "%2F")}), try a.print("{{\"title\":{f},\"source_branch\":{f},\"target_branch\":{f},\"description\":{f}}}", .{ fmt(title), fmt(branch), fmt(target), fmt(body) }) },
    };
}

fn fmt(s: []const u8) std.json.Formatter([]const u8) {
    return std.json.fmt(s, .{});
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

test "the request that opens a pull request, on each forge" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const gh = try request(a, &.{ .kind = .github, .repository = "example/spec" }, "dev", "fix-lexing");
    try std.testing.expectEqualStrings("repos/example/spec/pulls", gh[0]);
    try std.testing.expectEqualStrings("{\"title\":\"Change fix-lexing\",\"head\":\"edit/fix-lexing\",\"base\":\"dev\",\"body\":\"Proposed from skein serve.\"}", gh[1]);
    const gl = try request(a, &.{ .kind = .gitlab, .repository = "group/spec" }, "main", "x");
    try std.testing.expectEqualStrings("projects/group%2Fspec/merge_requests", gl[0]);
    try std.testing.expectEqualStrings("{\"title\":\"Change x\",\"source_branch\":\"edit/x\",\"target_branch\":\"main\",\"description\":\"Proposed from skein serve.\"}", gl[1]);
    try std.testing.expectEqualStrings("https://github.com/example/spec/pull/3", addressIn(a, "{\"html_url\":\"https://github.com/example/spec/pull/3\"}").?);
}
