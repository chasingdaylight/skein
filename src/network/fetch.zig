//! Repositories declared by a `url`: fetched with git into a cache of
//! their own, a bare repository under this repository's git directory
//! (`.git/skein/repositories/<name>.git`), never committed. Offline, only
//! what the cache holds is used.

const std = @import("std");
const Io = std.Io;

const git = @import("../git.zig");

/// How long a fetch may show no progress before it is given up
pub const idle_seconds = 30;

/// Where the last tip that `--current` read is kept in a cache
pub const current_ref = "refs/skein/current";

/// The cache of the repository `name`, made when it is not there yet;
/// null when it cannot be made
pub fn cache(io: Io, arena: std.mem.Allocator, git_dir: []const u8, name: []const u8) !?Io.Dir {
    const path = try Io.Dir.path.join(arena, &.{ git_dir, "skein", "repositories", try arena.print("{s}.git", .{name}) });
    if (Io.Dir.cwd().openDir(io, path, .{})) |dir| return dir else |_| {}
    var dir = Io.Dir.cwd().createDirPathOpen(io, path, .{}) catch return null;
    if (try git.output(io, arena, dir, &.{ "init", "--bare", "--quiet" }) == null) {
        dir.close(io);
        return null;
    }
    return dir;
}

/// Whether the cache has `commit` (in full), fetching it from `url` when
/// it does not and `offline` is false
pub fn commit(io: Io, arena: std.mem.Allocator, dir: Io.Dir, url: []const u8, hash: []const u8, offline: bool) !bool {
    if (try has(io, arena, dir, hash)) return true;
    if (offline) return false;
    // a server may refuse a commit asked for by its hash alone
    if (try git.remote(io, arena, dir, &.{ "fetch", "--quiet", url, hash }, idle_seconds) != null and try has(io, arena, dir, hash)) return true;
    _ = try git.remote(io, arena, dir, &.{ "fetch", "--quiet", url, "+refs/heads/*:refs/skein/heads/*", "+refs/tags/*:refs/skein/tags/*" }, idle_seconds);
    return has(io, arena, dir, hash);
}

/// The commit at the tip of `ref` (a branch or a tag; the default branch
/// when null) of `url`; offline, the tip last fetched. Null when it is
/// not known.
pub fn tip(io: Io, arena: std.mem.Allocator, dir: Io.Dir, url: []const u8, ref: ?[]const u8, offline: bool) !?[]const u8 {
    if (!offline) {
        const spec = try arena.print("+{s}:{s}", .{ ref orelse "HEAD", current_ref });
        _ = try git.remote(io, arena, dir, &.{ "fetch", "--quiet", url, spec }, idle_seconds);
    }
    const out = try git.output(io, arena, dir, &.{ "rev-parse", "--verify", "--quiet", current_ref ++ "^{commit}" }) orelse return null;
    return std.mem.trim(u8, out, " \r\n");
}

/// Whether `rev` looks like a whole commit hash rather than a name
pub fn isHash(rev: []const u8) bool {
    if (rev.len != 40 and rev.len != 64) return false;
    for (rev) |c| if (!std.ascii.isHex(c)) return false;
    return true;
}

fn has(io: Io, arena: std.mem.Allocator, dir: Io.Dir, hash: []const u8) !bool {
    return try git.output(io, arena, dir, &.{ "cat-file", "-e", try arena.print("{s}^{{commit}}", .{hash}) }) != null;
}
