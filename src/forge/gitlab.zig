//! What GitLab says of an issue or a merge request. skein asks the `glab`
//! program when it is installed, so that its sign-in is used; otherwise it
//! calls GitLab's API itself, with a token from `GITLAB_TOKEN` when one is
//! set (public projects need none). The answers are the same types as
//! GitHub's: `github.Issue`, `github.Answer`.

// cspell:ignore Fproject Fsub
const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const env = @import("../env.zig");
const github = @import("github.zig");
const pulls = @import("pulls.zig");
const tool = @import("tool.zig");

/// `group/project` as one path segment: `group%2Fproject`
fn project(arena: std.mem.Allocator, repository: []const u8) ![]const u8 {
    return std.mem.replaceOwned(u8, arena, repository, "/", "%2F");
}

/// What the forge says of issue `r`
pub fn lookup(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref) !github.Answer {
    return switch (try api(io, arena, forge, try arena.print("projects/{s}/issues/{d}", .{ try project(arena, r.repository), r.number }))) {
        .body => |json| if (parse(arena, json)) |issue| .{ .found = issue } else .{ .unreachable_ = "the forge gave an answer skein cannot read" },
        .missing => .missing,
        .unreachable_ => |why| .{ .unreachable_ = why },
    };
}

/// GET `path` (`projects/...`) of the forge's REST API: through `glab api`
/// when it is installed, else over HTTPS
pub fn api(io: Io, arena: std.mem.Allocator, forge: *const Forge, path: []const u8) !github.Reply {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ "glab", "api", path });
    if (try tool.cli(io, arena, argv.items, forge.url)) |reply| return reply;
    const base = forge.url orelse try arena.print("https://{s}", .{forge.host()});
    var headers: std.ArrayList(std.http.Header) = .empty;
    try headers.append(arena, .{ .name = "User-Agent", .value = "skein" });
    if (env.get("GITLAB_TOKEN")) |token| try headers.append(arena, .{ .name = "PRIVATE-TOKEN", .value = token });
    return tool.https(io, arena, try arena.print("{s}/api/v4/{s}", .{ base, path }), headers.items, forge.host(), "GitLab");
}

/// An issue as GitLab's API gives it. `opened` is open; `assignees` are
/// usernames; a milestone has a `title` and a `due_date` (`2027-03-12`).
pub fn parse(arena: std.mem.Allocator, json: []const u8) ?github.Issue {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{}) catch return null;
    if (v != .object) return null;
    const title = v.object.get("title") orelse return null;
    const state = v.object.get("state") orelse return null;
    if (title != .string or state != .string) return null;
    var out: github.Issue = .{ .title = title.string, .open = std.mem.eql(u8, state.string, "opened"), .pull = false };
    if (v.object.get("assignees")) |list| if (list == .array) {
        var logins: std.ArrayList([]const u8) = .empty;
        for (list.array.items) |a| {
            const login = if (a == .object) a.object.get("username") else null;
            if (login != null and login.? == .string) logins.append(arena, login.?.string) catch return null;
        }
        out.assignees = logins.items;
    };
    if (v.object.get("milestone")) |m| if (m == .object) {
        if (m.object.get("title")) |t| if (t == .string) {
            out.milestone = t.string;
        };
        if (m.object.get("due_date")) |d| if (d == .string and d.string.len >= 10) {
            out.due = d.string[0..10];
        };
    };
    return out;
}

/// Writes `changes` to issue `r`, through `glab` (which holds the sign-in);
/// null when it was written, else why not. `body_path` is a file skein may
/// write the request in.
pub fn update(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref, changes: github.Changes, body_path: []const u8) !?[]const u8 {
    const proj = try project(arena, r.repository);
    var body: std.ArrayList(u8) = .empty;
    try body.append(arena, '{');
    var first = true;
    if (changes.assignees) |logins| {
        try body.appendSlice(arena, "\"assignee_ids\":[");
        for (logins, 0..) |l, i| {
            const id = try userId(io, arena, forge, l) orelse return try arena.print("the forge has no user '{s}'", .{l});
            try body.print(arena, "{s}{d}", .{ if (i > 0) "," else "", id });
        }
        try body.append(arena, ']');
        first = false;
    }
    if (changes.milestone) |title| {
        if (!first) try body.append(arena, ',');
        first = false;
        if (title.len == 0) {
            try body.appendSlice(arena, "\"milestone_id\":0");
        } else {
            const id = try milestoneId(io, arena, forge, proj, title) orelse
                return try arena.print("the forge has no milestone '{s}' in {s}", .{ title, r.repository });
            try body.print(arena, "\"milestone_id\":{d}", .{id});
        }
    }
    if (changes.state) |state| {
        if (!first) try body.append(arena, ',');
        try body.print(arena, "\"state_event\":\"{s}\"", .{if (std.mem.eql(u8, state, "closed")) "close" else "reopen"});
    }
    try body.append(arena, '}');
    if (Io.Dir.path.dirname(body_path)) |d| Io.Dir.cwd().createDirPath(io, d) catch {};
    Io.Dir.cwd().writeFile(io, .{ .sub_path = body_path, .data = body.items }) catch return "the request could not be written";
    defer Io.Dir.cwd().deleteFile(io, body_path) catch {};

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ "glab", "api", "--method", "PUT", try arena.print("projects/{s}/issues/{d}", .{ proj, r.number }), "--input", body_path, "-H", "Content-Type: application/json" });
    const reply = (try tool.cli(io, arena, argv.items, forge.url)) orelse return "glab is not installed: writing to the forge needs it, signed in";
    return switch (reply) {
        .body => null,
        .missing => "the forge has no such issue",
        .unreachable_ => |why| why,
    };
}

/// Sends `json` to `path` of the forge's REST API, through `glab`
pub fn send(io: Io, arena: std.mem.Allocator, forge: *const Forge, method: []const u8, path: []const u8, json: []const u8, body_path: []const u8) !github.Reply {
    return tool.send(io, arena, "glab", null, forge.url, &.{"Content-Type: application/json"}, method, path, json, body_path);
}

/// The id of the user `username`
fn userId(io: Io, arena: std.mem.Allocator, forge: *const Forge, username: []const u8) !?u64 {
    return firstId(try api(io, arena, forge, try arena.print("users?username={s}", .{username})));
}

/// The id of the milestone titled `title` of the project `proj`
fn milestoneId(io: Io, arena: std.mem.Allocator, forge: *const Forge, proj: []const u8, title: []const u8) !?u64 {
    const encoded = try std.mem.replaceOwned(u8, arena, title, " ", "%20");
    return firstId(try api(io, arena, forge, try arena.print("projects/{s}/milestones?title={s}", .{ proj, encoded })));
}

fn firstId(reply: github.Reply) ?u64 {
    const text = switch (reply) {
        .body => |t| t,
        else => return null,
    };
    var buffer: [1 << 16]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);
    const v = std.json.parseFromSliceLeaky(std.json.Value, fba.allocator(), text, .{}) catch return null;
    if (v != .array or v.array.items.len == 0) return null;
    const first = v.array.items[0];
    if (first != .object) return null;
    const id = first.object.get("id") orelse return null;
    return if (id == .integer and id.integer >= 0) @intCast(id.integer) else null;
}

/// What the forge says of merge request `number` of the project's
/// repository, with who approved it
pub fn pull(io: Io, arena: std.mem.Allocator, forge: *const Forge, number: u64) !pulls.Got {
    const proj = try project(arena, forge.repository);
    const json = switch (try api(io, arena, forge, try arena.print("projects/{s}/merge_requests/{d}", .{ proj, number }))) {
        .body => |b| b,
        .missing => return .missing,
        .unreachable_ => |why| return .{ .unreachable_ = why },
    };
    const approvals = switch (try api(io, arena, forge, try arena.print("projects/{s}/merge_requests/{d}/approvals", .{ proj, number }))) {
        .body => |b| b,
        .missing => "{}",
        .unreachable_ => |why| return .{ .unreachable_ = why },
    };
    return .{ .pull = parsePull(arena, json, approvals) orelse return .{ .unreachable_ = "the forge gave an answer skein cannot read" } };
}

/// A merge request and its approvals as GitLab's API gives them
pub fn parsePull(arena: std.mem.Allocator, pull_json: []const u8, approvals_json: []const u8) ?pulls.Pull {
    const p = std.json.parseFromSliceLeaky(std.json.Value, arena, pull_json, .{}) catch return null;
    if (p != .object) return null;
    const refs = p.object.get("diff_refs") orelse return null;
    if (refs != .object) return null;
    const base = refs.object.get("base_sha") orelse return null;
    if (base != .string) return null;
    const merged = p.object.get("merged_at");
    const merged_on: ?[]const u8 = if (merged) |m| (if (m == .string and m.string.len >= 10) m.string[0..10] else null) else null;
    const merge = p.object.get("merge_commit_sha");

    const a = std.json.parseFromSliceLeaky(std.json.Value, arena, approvals_json, .{}) catch return null;
    var approvers: std.ArrayList([]const u8) = .empty;
    if (a == .object) if (a.object.get("approved_by")) |list| if (list == .array) {
        for (list.array.items) |entry| {
            const user = if (entry == .object) entry.object.get("user") else null;
            const name = if (user != null and user.? == .object) user.?.object.get("username") else null;
            if (name != null and name.? == .string) approvers.append(arena, name.?.string) catch return null;
        }
    };
    std.mem.sort([]const u8, approvers.items, {}, struct {
        fn lt(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.lessThan(u8, x, y);
        }
    }.lt);
    return .{
        .merged_on = merged_on,
        .base = base.string,
        .merge = if (merge) |m| (if (m == .string) m.string else null) else null,
        .approvers = approvers.items,
    };
}

// req: forge.gitlab
test "an issue as GitLab's API gives it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const issue = parse(a, "{\"iid\": 4, \"title\": \"Parse\", \"state\": \"opened\", \"assignees\": [{\"username\": \"ann\"}, {\"username\": \"bob\"}], \"milestone\": {\"title\": \"v1\", \"due_date\": \"2027-03-12\"}}").?;
    try std.testing.expectEqualStrings("Parse", issue.title);
    try std.testing.expect(issue.open);
    try std.testing.expect(!issue.pull);
    try std.testing.expectEqualStrings("bob", issue.assignees[1]);
    try std.testing.expectEqualStrings("v1", issue.milestone.?);
    try std.testing.expectEqualStrings("2027-03-12", issue.due.?);
    const closed = parse(a, "{\"title\": \"T\", \"state\": \"closed\", \"milestone\": null}").?;
    try std.testing.expect(!closed.open);
    try std.testing.expectEqual(null, closed.milestone);
    try std.testing.expectEqual(null, parse(a, "not json"));
}

test "who approved a merge request" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const merged = parsePull(arena.allocator(),
        \\{"merged_at": "2026-11-21T20:15:00.000Z", "merge_commit_sha": "m1", "diff_refs": {"base_sha": "b1"}}
    ,
        \\{"approved_by": [{"user": {"username": "carol"}}, {"user": {"username": "ann"}}]}
    ).?;
    try std.testing.expectEqualStrings("2026-11-21", merged.merged_on.?);
    try std.testing.expectEqualStrings("b1", merged.base);
    try std.testing.expectEqualStrings("m1", merged.merge.?);
    try std.testing.expectEqualStrings("ann", merged.approvers[0]);
    try std.testing.expectEqualStrings("carol", merged.approvers[1]);
}

test "a project path as one segment" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("group%2Fsub%2Fproject", try project(arena.allocator(), "group/sub/project"));
}
