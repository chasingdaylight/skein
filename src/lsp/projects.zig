//! The projects the language server serves. At the start, those of the
//! editor's folders: the project a folder is in, and the projects inside
//! it, to a few levels down. After that, each file's own project, the
//! nearest `.skein/` above it, whether or not it was found at the start.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Project = @import("../Project.zig");
const files = @import("../files.zig");

/// How deep below a folder a `.skein/` is looked for
pub const max_depth = 4;
/// The most directories looked into below one folder
const max_dirs = 20_000;

/// The roots of the projects of `folders`, without repeats, appended to
/// `out` (each owned by `gpa`): a folder's own project first, then those
/// inside it in order
pub fn discover(io: Io, gpa: Allocator, folders: []const []const u8, out: *std.ArrayList([]u8)) Allocator.Error!void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for (folders) |folder| {
        if (Project.findRoot(io, arena, folder) catch null) |root| try add(gpa, out, root);
        var inside: std.ArrayList([]const u8) = .empty;
        nested(io, arena, folder, &inside) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            // a folder that cannot be read has no projects to offer
            else => {},
        };
        std.mem.sort([]const u8, inside.items, {}, lessThan);
        for (inside.items) |root| try add(gpa, out, root);
    }
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Appends `root` to `out` unless it is there
pub fn add(gpa: Allocator, out: *std.ArrayList([]u8), root: []const u8) Allocator.Error!void {
    for (out.items) |r| if (std.mem.eql(u8, r, root)) return;
    const copy = try gpa.dupe(u8, root);
    errdefer gpa.free(copy);
    try out.append(gpa, copy);
}

/// The directories below `folder` that hold a `.skein/` directory
fn nested(io: Io, arena: Allocator, folder: []const u8, out: *std.ArrayList([]const u8)) !void {
    var dir = try Io.Dir.cwd().openDir(io, folder, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walkSelectively(arena);
    defer walker.deinit();
    var seen: usize = 0;
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .directory) continue;
        if (std.mem.eql(u8, entry.basename, Project.dir_name)) {
            // the directory the entry is in, below the folder
            const parent = entry.path[0 .. entry.path.len - entry.basename.len];
            if (parent.len > 0) {
                const joined = try Io.Dir.path.join(arena, &.{ folder, parent[0 .. parent.len - 1] });
                // as findRoot writes it, so that a project is not listed twice
                try out.append(arena, Io.Dir.cwd().realPathFileAlloc(io, joined, arena) catch joined);
            }
            continue;
        }
        if (files.skip(entry.basename) or entry.depth() >= max_depth or seen >= max_dirs) continue;
        seen += 1;
        walker.enter(io, entry) catch continue;
    }
}

/// The root of the project the file or directory `path` is in, the nearest
/// `.skein/` above it; null when there is none
pub fn rootOf(io: Io, arena: Allocator, path: []const u8) ?[]const u8 {
    return Project.findRoot(io, arena, path) catch null;
}

test {
    _ = @import("_test/projects.zig");
}
