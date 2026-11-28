//! What `skein serve` looks at to know the files changed.

// req: serve.site
const std = @import("std");
const testing = std.testing;

const stamp = @import("../stamp.zig");
const places = @import("../../places.zig");

test "the stamp changes with a file, and not otherwise" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = testing.io;
    try tmp.dir.createDirPath(io, ".skein");
    try tmp.dir.createDirPath(io, ".git");
    try tmp.dir.writeFile(io, .{ .sub_path = ".skein/config.toml", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "a.md", .data = "one" });
    const first = try stamp.of(io, testing.allocator, tmp.dir, null);
    try testing.expectEqualStrings(&first, &(try stamp.of(io, testing.allocator, tmp.dir, null)));
    try tmp.dir.writeFile(io, .{ .sub_path = ".git/index", .data = "x" });
    try testing.expectEqualStrings(&first, &(try stamp.of(io, testing.allocator, tmp.dir, null)));
    try tmp.dir.writeFile(io, .{ .sub_path = "a.md", .data = "three" });
    const second = try stamp.of(io, testing.allocator, tmp.dir, null);
    try testing.expect(!std.mem.eql(u8, &first, &second));
    try tmp.dir.writeFile(io, .{ .sub_path = ".skein/config.toml", .data = "[project]\n" });
    try testing.expect(!std.mem.eql(u8, &second, &(try stamp.of(io, testing.allocator, tmp.dir, null))));
}

test "with the project's places, only the files it reads count" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const io = testing.io;
    const dir = tmp.dir;
    try dir.createDirPath(io, ".skein");
    try dir.createDirPath(io, "spec");
    try dir.createDirPath(io, "build");
    try dir.writeFile(io, .{ .sub_path = ".skein/config.toml", .data = "" });
    try dir.writeFile(io, .{ .sub_path = "spec/a.md", .data = "one" });
    try dir.writeFile(io, .{ .sub_path = "build/out.txt", .data = "1" });
    const read = [_]places.Place{ .{ .path = ".skein" }, .{ .path = "spec", .endings = &.{".md"} } };
    const first = try stamp.of(io, testing.allocator, dir, &read);
    // a file the project does not read
    try dir.writeFile(io, .{ .sub_path = "build/out.txt", .data = "22" });
    try dir.writeFile(io, .{ .sub_path = "spec/picture.png", .data = "png" });
    try testing.expectEqualStrings(&first, &(try stamp.of(io, testing.allocator, dir, &read)));
    // and one it does: a new document
    try dir.writeFile(io, .{ .sub_path = "spec/b.md", .data = "two" });
    try testing.expect(!std.mem.eql(u8, &first, &(try stamp.of(io, testing.allocator, dir, &read))));
}
