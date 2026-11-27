//! What skein asks of the `git` program. skein reads a project's files
//! itself; it runs git only for what git alone knows: who the user is,
//! and what a file said at an earlier commit.

const std = @import("std");
const Io = std.Io;

/// What `git ARGS...` prints, run in `dir`; null when git is not there
/// or fails
pub fn output(io: Io, arena: std.mem.Allocator, dir: Io.Dir, args: []const []const u8) std.mem.Allocator.Error!?[]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, "git");
    try argv.appendSlice(arena, args);
    const result = std.process.run(arena, io, .{
        .argv = argv.items,
        .cwd = .{ .dir = dir },
        .stdout_limit = .limited(1 << 28),
    }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    if (!result.term.success()) return null;
    return result.stdout;
}

pub const Ran = union(enum) {
    ok: []const u8,
    /// what git said went wrong
    failed: []const u8,
};

/// `git ARGS...` run in `dir`: what it prints, or what it says went wrong
pub fn run(io: Io, arena: std.mem.Allocator, dir: Io.Dir, args: []const []const u8) std.mem.Allocator.Error!Ran {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, "git");
    try argv.appendSlice(arena, args);
    const result = std.process.run(arena, io, .{
        .argv = argv.items,
        .cwd = .{ .dir = dir },
        .stdout_limit = .limited(1 << 28),
    }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .failed = try arena.print("git could not be run ({t})", .{e}) },
    };
    if (result.term.success()) return .{ .ok = result.stdout };
    const why = std.mem.trim(u8, if (result.stderr.len > 0) result.stderr else result.stdout, " \r\n");
    return .{ .failed = try arena.print("git {s}: {s}", .{ args[0], why }) };
}

/// As `output`, for a command that talks to another machine (`fetch`):
/// stopped, and null, when it shows no progress for `idle_seconds`. It is
/// given `--progress`, so that a slow answer is told from none.
pub fn remote(io: Io, arena: std.mem.Allocator, dir: Io.Dir, args: []const []const u8, idle_seconds: i64) std.mem.Allocator.Error!?[]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    // never wait for a password typed at a terminal: fail instead
    try argv.appendSlice(arena, &.{ "git", "-c", "credential.interactive=never" });
    try argv.appendSlice(arena, args);
    try argv.append(arena, "--progress");
    const result = std.process.run(arena, io, .{
        .argv = argv.items,
        .cwd = .{ .dir = dir },
        .stdout_limit = .limited(1 << 28),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(idle_seconds), .clock = .awake } },
    }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    if (!result.term.success()) return null;
    return result.stdout;
}

/// The name git signs the user's commits with
pub fn userName(io: Io, arena: std.mem.Allocator, dir: Io.Dir) std.mem.Allocator.Error!?[]const u8 {
    const out = try output(io, arena, dir, &.{ "config", "user.name" }) orelse return null;
    const name = std.mem.trim(u8, out, " \t\r\n");
    return if (name.len > 0) name else null;
}
