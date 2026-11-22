//! What GitHub says of an issue or a pull request. skein asks the `gh`
//! program when it is installed, so that its sign-in is used; otherwise it
//! calls GitHub's API itself, with a token from `GH_TOKEN` or
//! `GITHUB_TOKEN` when one is set (public repositories need none).

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const env = @import("../env.zig");

/// How long `gh` may take to answer
pub const idle_seconds = 30;

pub const Issue = struct {
    title: []const u8,
    open: bool,
    /// whether it is a pull request
    pull: bool,
    /// the logins it is assigned to
    assignees: []const []const u8 = &.{},
    /// the title of its milestone, and when it is due (`YYYY-MM-DD`)
    milestone: ?[]const u8 = null,
    due: ?[]const u8 = null,
};

pub const Answer = union(enum) {
    found: Issue,
    /// the forge says there is no such issue or pull request
    missing,
    /// the forge could not be asked, or did not answer: why
    unreachable_: []const u8,
};

/// What the forge says of `r`
pub fn lookup(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref) !Answer {
    return switch (try api(io, arena, forge, try arena.print("repos/{s}/issues/{d}", .{ r.repository, r.number }))) {
        .body => |json| if (parse(arena, json)) |issue| .{ .found = issue } else .{ .unreachable_ = "the forge gave an answer skein cannot read" },
        .missing => .missing,
        .unreachable_ => |why| .{ .unreachable_ = why },
    };
}

/// What a request of GitHub's REST API gives
pub const Reply = union(enum) {
    /// the JSON it answered with
    body: []const u8,
    /// there is no such thing
    missing,
    /// it could not be asked, or did not answer: why
    unreachable_: []const u8,
};

/// GET `path` (`repos/owner/repo/...`) of the forge's REST API: through
/// `gh api` when it is installed, else over HTTPS
pub fn api(io: Io, arena: std.mem.Allocator, forge: *const Forge, path: []const u8) !Reply {
    if (try viaGh(io, arena, forge, path)) |reply| return reply;
    return viaHttps(io, arena, forge, path);
}

/// Through `gh api`; null when `gh` is not installed
fn viaGh(io: Io, arena: std.mem.Allocator, forge: *const Forge, path: []const u8) !?Reply {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ "gh", "api", path });
    if (forge.url != null) try argv.appendSlice(arena, &.{ "--hostname", forge.host() });
    const result = std.process.run(arena, io, .{
        .argv = argv.items,
        .stdout_limit = .limited(1 << 22),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(idle_seconds), .clock = .awake } },
    }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return null,
        error.Timeout => return .{ .unreachable_ = "gh did not answer in time" },
        else => return .{ .unreachable_ = try arena.print("gh could not be run ({t})", .{e}) },
    };
    if (result.term.success()) return .{ .body = result.stdout };
    if (std.mem.find(u8, result.stderr, "Not Found") != null or std.mem.find(u8, result.stdout, "Not Found") != null) return .missing;
    return .{ .unreachable_ = try arena.print("gh: {s}", .{std.mem.trim(u8, result.stderr, " \r\n")}) };
}

/// Through GitHub's API, over HTTPS
fn viaHttps(io: Io, arena: std.mem.Allocator, forge: *const Forge, path: []const u8) !Reply {
    const base = if (forge.url) |u| try arena.print("{s}/api/v3", .{u}) else "https://api.github.com";
    const url = try arena.print("{s}/{s}", .{ base, path });
    var client: std.http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();
    var body: Io.Writer.Allocating = .init(arena);
    var headers: std.ArrayList(std.http.Header) = .empty;
    try headers.append(arena, .{ .name = "Accept", .value = "application/vnd.github+json" });
    try headers.append(arena, .{ .name = "User-Agent", .value = "skein" });
    if (env.get("GH_TOKEN") orelse env.get("GITHUB_TOKEN")) |token| {
        try headers.append(arena, .{ .name = "Authorization", .value = try arena.print("Bearer {s}", .{token}) });
    }
    const result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &body.writer,
        .privileged_headers = headers.items,
    }) catch |e| return .{ .unreachable_ = try arena.print("{s} could not be reached ({t})", .{ forge.host(), e }) };
    return switch (result.status) {
        .ok => .{ .body = body.written() },
        .not_found, .gone => .missing,
        else => .{ .unreachable_ = try arena.print("GitHub answered {d}", .{@backingInt(result.status)}) },
    };
}

/// What `skein apply` writes to an issue
pub const Changes = struct {
    /// the logins it is to be assigned to
    assignees: ?[]const []const u8 = null,
    /// the title of its milestone; empty for none
    milestone: ?[]const u8 = null,
    /// `open` or `closed`
    state: ?[]const u8 = null,
};

/// Writes `changes` to the issue `r`, through `gh` (which holds the
/// sign-in); null when it was written, else why not. `body_path` is a file
/// skein may write the request in.
pub fn update(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref, changes: Changes, body_path: []const u8) !?[]const u8 {
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
            try body.appendSlice(arena, "\"milestone\":null");
        } else {
            const number = try milestoneNumber(io, arena, forge, r.repository, title) orelse
                return try arena.print("the forge has no milestone '{s}' in {s}", .{ title, r.repository });
            try body.print(arena, "\"milestone\":{d}", .{number});
        }
    }
    if (changes.state) |state| {
        if (!first) try body.append(arena, ',');
        try body.print(arena, "\"state\":{f}", .{std.json.fmt(state, .{})});
    }
    try body.append(arena, '}');
    if (Io.Dir.path.dirname(body_path)) |d| Io.Dir.cwd().createDirPath(io, d) catch {};
    Io.Dir.cwd().writeFile(io, .{ .sub_path = body_path, .data = body.items }) catch return "the request could not be written";
    defer Io.Dir.cwd().deleteFile(io, body_path) catch {};

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ "gh", "api", "--method", "PATCH", try arena.print("repos/{s}/issues/{d}", .{ r.repository, r.number }), "--input", body_path });
    if (forge.url != null) try argv.appendSlice(arena, &.{ "--hostname", forge.host() });
    const result = std.process.run(arena, io, .{
        .argv = argv.items,
        .stdout_limit = .limited(1 << 22),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(idle_seconds), .clock = .awake } },
    }) catch |e| return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        error.FileNotFound => "gh is not installed: writing to the forge needs it, signed in",
        else => try arena.print("gh could not be run ({t})", .{e}),
    };
    if (result.term.success()) return null;
    return try arena.print("gh: {s}", .{std.mem.trim(u8, result.stderr, " \r\n")});
}

/// The number of the milestone titled `title` of `repository`
fn milestoneNumber(io: Io, arena: std.mem.Allocator, forge: *const Forge, repository: []const u8, title: []const u8) !?u64 {
    const reply = try api(io, arena, forge, try arena.print("repos/{s}/milestones?state=all&per_page=100", .{repository}));
    const text = switch (reply) {
        .body => |t| t,
        else => return null,
    };
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{}) catch return null;
    if (v != .array) return null;
    for (v.array.items) |m| {
        if (m != .object) continue;
        const t = m.object.get("title") orelse continue;
        const n = m.object.get("number") orelse continue;
        if (t == .string and n == .integer and std.mem.eql(u8, t.string, title)) return @intCast(n.integer);
    }
    return null;
}

/// An issue as GitHub's API gives it: its title, its state, and whether
/// it is a pull request
pub fn parse(arena: std.mem.Allocator, json: []const u8) ?Issue {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{}) catch return null;
    if (v != .object) return null;
    const title = v.object.get("title") orelse return null;
    const state = v.object.get("state") orelse return null;
    if (title != .string or state != .string) return null;
    var out: Issue = .{ .title = title.string, .open = std.mem.eql(u8, state.string, "open"), .pull = v.object.get("pull_request") != null };
    if (v.object.get("assignees")) |list| if (list == .array) {
        var logins: std.ArrayList([]const u8) = .empty;
        for (list.array.items) |a| {
            const login = if (a == .object) a.object.get("login") else null;
            if (login != null and login.? == .string) logins.append(arena, login.?.string) catch return null;
        }
        out.assignees = logins.items;
    };
    if (v.object.get("milestone")) |m| if (m == .object) {
        if (m.object.get("title")) |t| if (t == .string) {
            out.milestone = t.string;
        };
        // `2027-03-12T07:00:00Z`: its day
        if (m.object.get("due_on")) |d| if (d == .string and d.string.len >= 10) {
            out.due = d.string[0..10];
        };
    };
    return out;
}

test "an issue as GitHub's API gives it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const issue = parse(arena.allocator(), "{\"number\": 97, \"title\": \"Proposal 0000\", \"state\": \"closed\", \"pull_request\": {\"url\": \"x\"}}").?;
    try std.testing.expectEqualStrings("Proposal 0000", issue.title);
    try std.testing.expect(!issue.open);
    try std.testing.expect(issue.pull);
    try std.testing.expectEqual(null, parse(arena.allocator(), "not json"));
}

test "the planning fields of an issue: assignees, milestone and its due day" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const issue = parse(arena.allocator(), "{\"title\": \"T\", \"state\": \"open\", \"assignees\": [{\"login\": \"ann\"}, {\"login\": \"bob\"}], \"milestone\": {\"title\": \"v1\", \"due_on\": \"2027-03-12T07:00:00Z\"}}").?;
    try std.testing.expectEqual(2, issue.assignees.len);
    try std.testing.expectEqualStrings("bob", issue.assignees[1]);
    try std.testing.expectEqualStrings("v1", issue.milestone.?);
    try std.testing.expectEqualStrings("2027-03-12", issue.due.?);
    const bare = parse(arena.allocator(), "{\"title\": \"T\", \"state\": \"open\", \"milestone\": null}").?;
    try std.testing.expectEqual(0, bare.assignees.len);
    try std.testing.expectEqual(null, bare.milestone);
}
