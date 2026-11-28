//! The places a project's files are read from by `check`, `render` and the
//! editing requests: `.skein/`, the Markdown of each source (and, for the
//! site, the pictures and other files beside it), each citation set's files
//! by their endings (with its directory files), and the results. `skein
//! serve` watches them (serve/stamp.zig), and the static site's edit mode
//! carries them (render/edit_mode.zig), not the rest of the repository
//! (#304).

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Citations = @import("graph/Citations.zig");
const Project = @import("Project.zig");
const files = @import("files.zig");

/// A directory or a file, from the project's root, and the endings of the
/// files read there; none: every file
pub const Place = struct { path: []const u8, endings: []const []const u8 = &.{} };

/// What the places are for: the files `check` reads, or those the site is
/// rendered from, which are also every other file of a source
pub const For = enum { check, site };

/// The places of `project`
pub fn of(arena: Allocator, project: *const Project, purpose: For) Allocator.Error![]const Place {
    var out: std.ArrayList(Place) = .empty;
    try out.append(arena, .{ .path = Project.dir_name });
    for (project.sources) |s| try out.append(arena, .{ .path = s.path, .endings = if (purpose == .check) &.{".md"} else &.{} });
    for (project.citations) |c| {
        const endings = try arena.alloc([]const u8, c.files.len + 1);
        @memcpy(endings[0..c.files.len], c.files);
        endings[c.files.len] = Citations.directory_file;
        try out.append(arena, .{ .path = c.path, .endings = endings });
    }
    for (project.results) |r| try out.append(arena, .{ .path = r });
    return out.items;
}

/// The files of `places` under `root`, each once, in their order; a place
/// that is a file is itself, and one that cannot be read has none
pub fn list(io: Io, arena: Allocator, root: Io.Dir, places: []const Place) Allocator.Error![]const []const u8 {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var out: std.ArrayList([]const u8) = .empty;
    for (places) |place| {
        const endings: []const []const u8 = if (place.endings.len > 0) place.endings else &.{""};
        const found: []const []const u8 = files.list(io, arena, root, place.path, endings) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            // a results file, not a directory; or nothing there
            else => if (root.access(io, place.path, .{})) |_| &.{place.path} else |_| &.{},
        };
        for (found) |file| {
            if ((try seen.getOrPut(arena, file)).found_existing) continue;
            try out.append(arena, file);
        }
    }
    return out.items;
}

test {
    _ = @import("_test/places.zig");
}
