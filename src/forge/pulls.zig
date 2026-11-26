//! A merged pull request, as the forge gives it: when it was merged, the
//! commits it was merged from and into, and who approved it in review.

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const github = @import("github.zig");
const forgejo = @import("forgejo.zig");
const gitlab = @import("gitlab.zig");

/// How the forge's API is asked: the forge itself, or something else in tests
pub var call: *const fn (Io, std.mem.Allocator, *const Forge, []const u8) anyerror!github.Reply = github.api;
pub var forgejo_call: *const fn (Io, std.mem.Allocator, *const Forge, []const u8) anyerror!github.Reply = forgejo.api;

pub const Pull = struct {
    /// `YYYY-MM-DD`; null when it is not merged
    merged_on: ?[]const u8,
    /// the commit of the base branch it started from
    base: []const u8,
    /// the commit its merge made
    merge: ?[]const u8,
    /// the reviewers whose last review approved it, in order
    approvers: []const []const u8,
};

pub const Got = union(enum) {
    pull: Pull,
    missing,
    unreachable_: []const u8,
};

/// What the forge says of pull request `number` of the project's repository
pub fn get(io: Io, arena: std.mem.Allocator, forge: *const Forge, number: u64) !Got {
    // Forgejo's pull requests and reviews are GitHub's shape, from its own API
    const ask = switch (forge.kind) {
        .github => call,
        .gitlab => return gitlab.pull(io, arena, forge, number),
        .forgejo => forgejo_call,
    };
    const head = try ask(io, arena, forge, try arena.print("repos/{s}/pulls/{d}", .{ forge.repository, number }));
    const json = switch (head) {
        .body => |b| b,
        .missing => return .missing,
        .unreachable_ => |why| return .{ .unreachable_ = why },
    };
    const reviews = switch (try ask(io, arena, forge, try arena.print("repos/{s}/pulls/{d}/reviews?per_page=100", .{ forge.repository, number }))) {
        .body => |b| b,
        .missing => "[]",
        .unreachable_ => |why| return .{ .unreachable_ = why },
    };
    return .{ .pull = parse(arena, json, reviews) orelse return .{ .unreachable_ = "the forge gave an answer skein cannot read" } };
}

/// A pull request and its reviews as GitHub's API gives them. A reviewer
/// approved when the last of their reviews that approved or asked for
/// changes approved; comments alone count for neither.
pub fn parse(arena: std.mem.Allocator, pull_json: []const u8, reviews_json: []const u8) ?Pull {
    const p = std.json.parseFromSliceLeaky(std.json.Value, arena, pull_json, .{}) catch return null;
    if (p != .object) return null;
    const base = p.object.get("base") orelse return null;
    if (base != .object) return null;
    const base_sha = base.object.get("sha") orelse return null;
    if (base_sha != .string) return null;
    const merged = p.object.get("merged_at");
    const merged_on: ?[]const u8 = if (merged) |m| (if (m == .string and m.string.len >= 10) m.string[0..10] else null) else null;
    const merge = p.object.get("merge_commit_sha");

    const r = std.json.parseFromSliceLeaky(std.json.Value, arena, reviews_json, .{}) catch return null;
    if (r != .array) return null;
    var last: std.array_hash_map.String(bool) = .empty;
    for (r.array.items) |review| {
        if (review != .object) continue;
        const user = review.object.get("user") orelse continue;
        if (user != .object) continue;
        const login = user.object.get("login") orelse continue;
        const state = review.object.get("state") orelse continue;
        if (login != .string or state != .string) continue;
        // Forgejo's: `REQUEST_CHANGES`, and `dismissed` on the review
        const dismissed = review.object.get("dismissed");
        if (dismissed != null and dismissed.? == .bool and dismissed.?.bool) {
            last.put(arena, login.string, false) catch return null;
        } else if (std.mem.eql(u8, state.string, "APPROVED")) {
            last.put(arena, login.string, true) catch return null;
        } else if (std.mem.eql(u8, state.string, "CHANGES_REQUESTED") or std.mem.eql(u8, state.string, "REQUEST_CHANGES") or std.mem.eql(u8, state.string, "DISMISSED")) {
            last.put(arena, login.string, false) catch return null;
        }
    }
    var approvers: std.ArrayList([]const u8) = .empty;
    for (last.keys(), last.values()) |login, approved| {
        if (approved) approvers.append(arena, login) catch return null;
    }
    std.mem.sort([]const u8, approvers.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return .{
        .merged_on = merged_on,
        .base = base_sha.string,
        .merge = if (merge) |m| (if (m == .string) m.string else null) else null,
        .approvers = approvers.items,
    };
}

// req: forge.forgejo
test "who approved a pull request on Forgejo, whose reviews say it otherwise" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const pull = parse(arena.allocator(),
        \\{"merged_at": "2026-11-21T20:15:00+01:00", "merge_commit_sha": "m1", "base": {"sha": "b1"}, "pull_request": null}
    ,
        \\[{"user": {"login": "carol"}, "state": "APPROVED", "dismissed": false},
        \\ {"user": {"login": "dave"}, "state": "APPROVED", "dismissed": true},
        \\ {"user": {"login": "ann"}, "state": "APPROVED"},
        \\ {"user": {"login": "ann"}, "state": "REQUEST_CHANGES"}]
    ).?;
    try std.testing.expectEqual(1, pull.approvers.len);
    try std.testing.expectEqualStrings("carol", pull.approvers[0]);
}

test "who approved a pull request, by their last review" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pull = parse(a,
        \\{"merged_at": "2026-11-21T20:15:00Z", "merge_commit_sha": "m1", "base": {"sha": "b1"}}
    ,
        \\[{"user": {"login": "carol"}, "state": "APPROVED"},
        \\ {"user": {"login": "dave"}, "state": "APPROVED"},
        \\ {"user": {"login": "dave"}, "state": "CHANGES_REQUESTED"},
        \\ {"user": {"login": "ann"}, "state": "CHANGES_REQUESTED"},
        \\ {"user": {"login": "ann"}, "state": "APPROVED"},
        \\ {"user": {"login": "ann"}, "state": "COMMENTED"}]
    ).?;
    try std.testing.expectEqualStrings("2026-11-21", pull.merged_on.?);
    try std.testing.expectEqualStrings("b1", pull.base);
    try std.testing.expectEqualStrings("m1", pull.merge.?);
    try std.testing.expectEqual(2, pull.approvers.len);
    try std.testing.expectEqualStrings("ann", pull.approvers[0]);
    try std.testing.expectEqualStrings("carol", pull.approvers[1]);
}
