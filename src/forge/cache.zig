//! What the forge last said of each issue and pull request, kept under
//! this repository's git directory (`.git/skein/forge/`), never committed:
//! for `--offline`, and when the forge cannot be reached.

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const github = @import("github.zig");

fn path(arena: std.mem.Allocator, git_dir: []const u8, forge: *const Forge, r: Forge.Ref) ![]const u8 {
    return Io.Dir.path.join(arena, &.{ git_dir, "skein", "forge", forge.host(), r.repository, try arena.print("{d}.json", .{r.number}) });
}

/// What the cache holds of `r`; null when it holds nothing
pub fn get(io: Io, arena: std.mem.Allocator, git_dir: []const u8, forge: *const Forge, r: Forge.Ref) !?github.Answer {
    const p = try path(arena, git_dir, forge, r);
    const text = Io.Dir.cwd().readFileAlloc(io, p, arena, .limited(1 << 20)) catch return null;
    if (std.mem.eql(u8, std.mem.trim(u8, text, " \r\n"), "missing")) return .missing;
    const issue = github.parse(arena, text) orelse return null;
    return .{ .found = issue };
}

/// Keeps what the forge said of `r`; a cache that cannot be written is
/// done without
pub fn put(io: Io, arena: std.mem.Allocator, git_dir: []const u8, forge: *const Forge, r: Forge.Ref, answer: github.Answer) !void {
    const text = switch (answer) {
        .found => |i| try issueJson(arena, i),
        .missing => "missing\n",
        .unreachable_ => return,
    };
    const p = try path(arena, git_dir, forge, r);
    if (Io.Dir.path.dirname(p)) |d| Io.Dir.cwd().createDirPath(io, d) catch return;
    Io.Dir.cwd().writeFile(io, .{ .sub_path = p, .data = text }) catch {};
}

/// The issue as GitHub's API gives it, so that `github.parse` reads it back
fn issueJson(arena: std.mem.Allocator, i: github.Issue) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "{{\"title\": {s}, \"state\": \"{s}\"", .{ try jsonString(arena, i.title), if (i.open) "open" else "closed" });
    if (i.pull) try out.appendSlice(arena, ", \"pull_request\": {}");
    try out.appendSlice(arena, ", \"assignees\": [");
    for (i.assignees, 0..) |login, n| try out.print(arena, "{s}{{\"login\": {s}}}", .{ if (n > 0) ", " else "", try jsonString(arena, login) });
    try out.append(arena, ']');
    if (i.milestone) |m| {
        try out.print(arena, ", \"milestone\": {{\"title\": {s}", .{try jsonString(arena, m)});
        if (i.due) |d| try out.print(arena, ", \"due_on\": \"{s}T00:00:00Z\"", .{d});
        try out.append(arena, '}');
    }
    try out.appendSlice(arena, "}\n");
    return out.items;
}

fn jsonString(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.append(arena, '"');
    for (s) |c| switch (c) {
        '"' => try out.appendSlice(arena, "\\\""),
        '\\' => try out.appendSlice(arena, "\\\\"),
        '\n' => try out.appendSlice(arena, "\\n"),
        0...9, 11...0x1f => try out.print(arena, "\\u{x:0>4}", .{c}),
        else => try out.append(arena, c),
    };
    try out.append(arena, '"');
    return out.items;
}
