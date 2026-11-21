//! Finding a project's files.

const std = @import("std");
const Io = std.Io;

/// Directories that hold no sources: build outputs and caches. Directories
/// whose names start with a dot are not entered either.
const skipped = [_][]const u8{ "zig-out", "zig-pkg", "node_modules" };

/// The files under `dir` (a path from `root`) whose names end in one of
/// `suffixes`, as paths from `root` with forward slashes, in order.
pub fn list(io: Io, arena: std.mem.Allocator, root: Io.Dir, dir: []const u8, suffixes: []const []const u8) ![]const []const u8 {
    var d = try root.openDir(io, dir, .{ .iterate = true });
    defer d.close(io);
    var walker = try d.walkSelectively(arena);
    defer walker.deinit();
    var out: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (!skip(entry.basename)) try walker.enter(io, entry);
            continue;
        }
        if (entry.kind != .file or !endsWithAny(entry.basename, suffixes)) continue;
        const path = if (std.mem.eql(u8, dir, ".")) try arena.dupe(u8, entry.path) else try arena.print("{s}/{s}", .{ dir, entry.path });
        std.mem.replaceScalar(u8, path, '\\', '/');
        try out.append(arena, path);
    }
    std.mem.sort([]const u8, out.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return out.items;
}

fn skip(name: []const u8) bool {
    if (name.len > 0 and name[0] == '.') return true;
    for (skipped) |s| {
        if (std.mem.eql(u8, name, s)) return true;
    }
    return false;
}

fn endsWithAny(name: []const u8, suffixes: []const []const u8) bool {
    for (suffixes) |s| {
        if (std.ascii.endsWithIgnoreCase(name, s)) return true;
    }
    return false;
}

// req: items.sources
const testing = std.testing;

test "files are listed in order, without caches and hidden directories" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = testing.io;
    for ([_][]const u8{ "src/b", "src/.cache", "src/zig-out", "other" }) |path| try tmp.dir.createDirPath(io, path);
    for ([_][]const u8{ "src/z.zig", "src/b/a.ZIG", "src/b/notes.md", "src/.cache/x.zig", "src/zig-out/y.zig", "other/o.zig", "top.c" }) |path| {
        try tmp.dir.writeFile(io, .{ .sub_path = path, .data = "" });
    }
    const in_src = try list(io, arena.allocator(), tmp.dir, "src", &.{".zig"});
    try testing.expectEqual(2, in_src.len);
    try testing.expectEqualStrings("src/b/a.ZIG", in_src[0]);
    try testing.expectEqualStrings("src/z.zig", in_src[1]);

    const everywhere = try list(io, arena.allocator(), tmp.dir, ".", &.{ ".zig", ".c" });
    try testing.expectEqual(4, everywhere.len);
    try testing.expectEqualStrings("other/o.zig", everywhere[0]);
    try testing.expectEqualStrings("top.c", everywhere[3]);
}
