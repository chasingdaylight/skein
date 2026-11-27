//! What `skein serve` looks at to know the files changed: a hash of the
//! path, size and modification time of each file of the project, without
//! git's own files and the directories `files.list` skips.

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");

/// The stamp of the files under `root`, in hexadecimal
pub fn of(io: Io, gpa: std.mem.Allocator, root: Io.Dir) ![16]u8 {
    var hash: std.hash.Wyhash = .init(0);
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
        hash.update(entry.path);
        hash.update(std.mem.asBytes(&st.size));
        hash.update(std.mem.asBytes(&st.mtime.nanoseconds));
    }
    var out: [16]u8 = undefined;
    _ = std.mem.print(&out, "{x:0>16}", .{hash.final()}) catch unreachable;
    return out;
}

/// Whether a directory's files are looked at: those of the project's own
/// directory, and none hidden or of a build or cache
fn entered(name: []const u8) bool {
    if (std.mem.eql(u8, name, Project.dir_name)) return true;
    if (name.len > 0 and name[0] == '.') return false;
    for ([_][]const u8{ "zig-out", "zig-pkg", "node_modules" }) |s| {
        if (std.mem.eql(u8, name, s)) return false;
    }
    return true;
}

test "the stamp changes with a file, and not otherwise" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    try tmp.dir.createDirPath(io, ".skein");
    try tmp.dir.createDirPath(io, ".git");
    try tmp.dir.writeFile(io, .{ .sub_path = ".skein/config.toml", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "a.md", .data = "one" });
    const first = try of(io, std.testing.allocator, tmp.dir);
    try std.testing.expectEqualStrings(&first, &(try of(io, std.testing.allocator, tmp.dir)));
    try tmp.dir.writeFile(io, .{ .sub_path = ".git/index", .data = "x" });
    try std.testing.expectEqualStrings(&first, &(try of(io, std.testing.allocator, tmp.dir)));
    try tmp.dir.writeFile(io, .{ .sub_path = "a.md", .data = "three" });
    const second = try of(io, std.testing.allocator, tmp.dir);
    try std.testing.expect(!std.mem.eql(u8, &first, &second));
    try tmp.dir.writeFile(io, .{ .sub_path = ".skein/config.toml", .data = "[project]\n" });
    try std.testing.expect(!std.mem.eql(u8, &second, &(try of(io, std.testing.allocator, tmp.dir))));
}
