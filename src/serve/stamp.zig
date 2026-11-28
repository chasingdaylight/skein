//! What `skein serve` looks at to know the files changed: a hash of the
//! path, size and modification time of each file the project reads
//! (places.zig), or, before the project is known, of each file under its
//! root, without git's own files and the directories `files.list` skips.

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const files = @import("../files.zig");
const places_ = @import("../places.zig");

/// The stamp of the files of `places` under `root`, or of all its files
/// when `places` is null, in hexadecimal
pub fn of(io: Io, gpa: std.mem.Allocator, root: Io.Dir, places: ?[]const places_.Place) ![16]u8 {
    var hash: std.hash.Wyhash = .init(0);
    if (places) |given| {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        for (try places_.list(io, arena.allocator(), root, given)) |file| {
            const st = root.statFile(io, file, .{}) catch continue;
            add(&hash, file, st);
        }
    } else try all(io, gpa, root, &hash);
    var out: [16]u8 = undefined;
    _ = std.mem.print(&out, "{x:0>16}", .{hash.final()}) catch unreachable;
    return out;
}

fn add(hash: *std.hash.Wyhash, path: []const u8, st: Io.File.Stat) void {
    hash.update(path);
    hash.update(std.mem.asBytes(&st.size));
    hash.update(std.mem.asBytes(&st.mtime.nanoseconds));
}

/// Every file under `root`, as the stamp of a project not read yet
fn all(io: Io, gpa: std.mem.Allocator, root: Io.Dir, hash: *std.hash.Wyhash) !void {
    var d = try root.openDir(io, ".", .{ .iterate = true });
    defer d.close(io);
    var walker = try d.walkSelectively(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (entered(entry.basename)) try walker.enter(io, entry);
            continue;
        }
        if (entry.kind != .file) continue;
        const st = entry.dir.statFile(io, entry.basename, .{}) catch continue;
        // forward slashes, as the places' files are written
        const path = try gpa.dupe(u8, entry.path);
        defer gpa.free(path);
        std.mem.replaceScalar(u8, path, '\\', '/');
        add(hash, path, st);
    }
}

/// Whether a directory's files are looked at: those of the project's own
/// directory, and none hidden or of a build or cache
fn entered(name: []const u8) bool {
    return std.mem.eql(u8, name, Project.dir_name) or !files.skip(name);
}

test {
    _ = @import("_test/stamp.zig");
}
