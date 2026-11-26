//! What Forgejo (Codeberg, or a server of one's own) says of an issue or a
//! pull request, through its API (`/api/v1`, Gitea's), over HTTPS, with a
//! token from `FORGEJO_TOKEN` when one is set: public repositories need
//! none to be read, writing needs one. Forgejo has no program that holds a
//! sign-in as `gh` and `glab` do. Its issues, pull requests and reviews are
//! GitHub's shape, so the answers are read as GitHub's (`github.parse`,
//! `pulls.parse`).

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const env = @import("../env.zig");
const github = @import("github.zig");
const tool = @import("tool.zig");

/// What the forge says of issue `r`
pub fn lookup(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref) !github.Answer {
    return switch (try api(io, arena, forge, try arena.print("repos/{s}/issues/{d}", .{ r.repository, r.number }))) {
        .body => |json| if (github.parse(arena, json)) |issue| .{ .found = issue } else .{ .unreachable_ = "the forge gave an answer skein cannot read" },
        .missing => .missing,
        .unreachable_ => |why| .{ .unreachable_ = why },
    };
}

/// GET `path` (`repos/...`) of the forge's API
pub fn api(io: Io, arena: std.mem.Allocator, forge: *const Forge, path: []const u8) anyerror!github.Reply {
    return tool.https(io, arena, try url(arena, forge, path), try headers(arena), forge.host(), "Forgejo");
}

/// Sends `json` with `method` to `path` of the forge's API; `body_path` is
/// not needed, since the request goes over HTTPS
pub fn send(io: Io, arena: std.mem.Allocator, forge: *const Forge, method: []const u8, path: []const u8, json: []const u8, body_path: []const u8) !github.Reply {
    _ = body_path;
    if (env.get("FORGEJO_TOKEN") == null) return .{ .unreachable_ = "writing to Forgejo needs a token in FORGEJO_TOKEN" };
    const m = std.meta.stringToEnum(std.http.Method, method) orelse return .{ .unreachable_ = try arena.print("'{s}' is no HTTP method", .{method}) };
    return tool.httpsSend(io, arena, m, try url(arena, forge, path), try headers(arena), json, forge.host(), "Forgejo");
}

/// Writes `changes` to issue `r`; null when it was written, else why not
pub fn update(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref, changes: github.Changes, body_path: []const u8) !?[]const u8 {
    const body = switch (try changesJson(io, arena, forge, r, changes)) {
        .ok => |b| b,
        .failed => |why| return why,
    };
    return switch (try send(io, arena, forge, "PATCH", try arena.print("repos/{s}/issues/{d}", .{ r.repository, r.number }), body, body_path)) {
        .body => null,
        .missing => "the forge has no such issue",
        .unreachable_ => |why| why,
    };
}

/// The request of `changes`: `assignees` by login, `milestone` by id (0
/// for none), `state`; or why it cannot be made
fn changesJson(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref, changes: github.Changes) !union(enum) { ok: []const u8, failed: []const u8 } {
    var body: std.ArrayList(u8) = .empty;
    try body.append(arena, '{');
    var first = true;
    if (changes.assignees) |logins| {
        try body.appendSlice(arena, "\"assignees\":[");
        for (logins, 0..) |l, i| try body.print(arena, "{s}{f}", .{ if (i > 0) "," else "", std.json.fmt(l, .{}) });
        try body.append(arena, ']');
        first = false;
    }
    if (changes.milestone) |title| {
        if (!first) try body.append(arena, ',');
        first = false;
        if (title.len == 0) {
            try body.appendSlice(arena, "\"milestone\":0");
        } else {
            const id = try milestoneId(io, arena, forge, r.repository, title) orelse
                return .{ .failed = try arena.print("the forge has no milestone '{s}' in {s}", .{ title, r.repository }) };
            try body.print(arena, "\"milestone\":{d}", .{id});
        }
    }
    if (changes.state) |state| {
        if (!first) try body.append(arena, ',');
        try body.print(arena, "\"state\":\"{s}\"", .{if (std.mem.eql(u8, state, "closed")) "closed" else "open"});
    }
    try body.append(arena, '}');
    return .{ .ok = body.items };
}

/// The id of the milestone titled `title` of `repository`
fn milestoneId(io: Io, arena: std.mem.Allocator, forge: *const Forge, repository: []const u8, title: []const u8) !?u64 {
    const encoded = try std.mem.replaceOwned(u8, arena, title, " ", "%20");
    const text = switch (try api(io, arena, forge, try arena.print("repos/{s}/milestones?state=all&name={s}", .{ repository, encoded }))) {
        .body => |t| t,
        else => return null,
    };
    return milestoneIn(arena, text, title);
}

/// The id of the milestone titled `title` in a list of them
pub fn milestoneIn(arena: std.mem.Allocator, json: []const u8, title: []const u8) ?u64 {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{}) catch return null;
    if (v != .array) return null;
    for (v.array.items) |m| {
        if (m != .object) continue;
        const t = m.object.get("title") orelse continue;
        const id = m.object.get("id") orelse continue;
        if (t == .string and std.mem.eql(u8, t.string, title) and id == .integer and id.integer >= 0) return @intCast(id.integer);
    }
    return null;
}

fn url(arena: std.mem.Allocator, forge: *const Forge, path: []const u8) ![]const u8 {
    const base = forge.url orelse try arena.print("https://{s}", .{forge.host()});
    return arena.print("{s}/api/v1/{s}", .{ base, path });
}

fn headers(arena: std.mem.Allocator) ![]const std.http.Header {
    var out: std.ArrayList(std.http.Header) = .empty;
    try out.append(arena, .{ .name = "User-Agent", .value = "skein" });
    try out.append(arena, .{ .name = "Accept", .value = "application/json" });
    if (env.get("FORGEJO_TOKEN")) |token| try out.append(arena, .{ .name = "Authorization", .value = try arena.print("token {s}", .{token}) });
    return out.items;
}

// req: forge.forgejo
test "an issue as Forgejo's API gives it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const issue = github.parse(a, "{\"number\": 4, \"title\": \"Parse\", \"state\": \"open\", \"pull_request\": null, \"assignees\": [{\"login\": \"ann\"}], \"milestone\": {\"id\": 3, \"title\": \"v1\", \"due_on\": \"2027-03-12T00:00:00Z\"}}").?;
    try std.testing.expectEqualStrings("Parse", issue.title);
    try std.testing.expect(issue.open);
    try std.testing.expect(!issue.pull);
    try std.testing.expectEqualStrings("ann", issue.assignees[0]);
    try std.testing.expectEqualStrings("2027-03-12", issue.due.?);
    const pr = github.parse(a, "{\"title\": \"T\", \"state\": \"closed\", \"pull_request\": {\"merged\": true}, \"assignees\": null}").?;
    try std.testing.expect(pr.pull);
    try std.testing.expectEqual(3, milestoneIn(a, "[{\"id\": 2, \"title\": \"v0\"}, {\"id\": 3, \"title\": \"v1\"}]", "v1").?);
    try std.testing.expectEqual(null, milestoneIn(a, "[]", "v1"));
}

test "the address of the API" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const codeberg: Forge = .{ .kind = .forgejo, .repository = "owner/repo" };
    try std.testing.expectEqualStrings("https://codeberg.org/api/v1/repos/owner/repo/issues/3", try url(arena.allocator(), &codeberg, "repos/owner/repo/issues/3"));
    const own: Forge = .{ .kind = .forgejo, .repository = "o/r", .url = "https://git.example.com" };
    try std.testing.expectEqualStrings("https://git.example.com/api/v1/x", try url(arena.allocator(), &own, "x"));
}
