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
    if (try viaGh(io, arena, forge, r)) |answer| return answer;
    return viaHttps(io, arena, forge, r);
}

/// Through `gh api`; null when `gh` is not installed
fn viaGh(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref) !?Answer {
    const path = try arena.print("repos/{s}/issues/{d}", .{ r.repository, r.number });
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
    if (result.term.success()) return if (parse(arena, result.stdout)) |issue| .{ .found = issue } else .{ .unreachable_ = "gh gave an answer skein cannot read" };
    if (std.mem.find(u8, result.stderr, "Not Found") != null or std.mem.find(u8, result.stdout, "Not Found") != null) return .missing;
    return .{ .unreachable_ = try arena.print("gh: {s}", .{std.mem.trim(u8, result.stderr, " \r\n")}) };
}

/// Through GitHub's API, over HTTPS
fn viaHttps(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref) !Answer {
    const base = if (forge.url) |u| try arena.print("{s}/api/v3", .{u}) else "https://api.github.com";
    const url = try arena.print("{s}/repos/{s}/issues/{d}", .{ base, r.repository, r.number });
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
        .ok => if (parse(arena, body.written())) |issue| .{ .found = issue } else .{ .unreachable_ = "GitHub gave an answer skein cannot read" },
        .not_found, .gone => .missing,
        else => .{ .unreachable_ = try arena.print("GitHub answered {d}", .{@backingInt(result.status)}) },
    };
}

/// An issue as GitHub's API gives it: its title, its state, and whether
/// it is a pull request
pub fn parse(arena: std.mem.Allocator, json: []const u8) ?Issue {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{}) catch return null;
    if (v != .object) return null;
    const title = v.object.get("title") orelse return null;
    const state = v.object.get("state") orelse return null;
    if (title != .string or state != .string) return null;
    return .{ .title = title.string, .open = std.mem.eql(u8, state.string, "open"), .pull = v.object.get("pull_request") != null };
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
