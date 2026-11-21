//! A project's items, and how to find one by its ID.

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const documents = @import("documents.zig");
const item_file = @import("item_file.zig");
pub const Item = @import("Item.zig");
pub const checks = @import("checks.zig");

const Graph = @This();

/// in the order of the sources, the files (by path) and the lines
items: []const Item = &.{},
by_id: std.array_hash_map.String(usize) = .empty,

pub fn find(self: *const Graph, id: []const u8) ?*const Item {
    const i = self.by_id.get(id) orelse return null;
    return &self.items[i];
}

/// The graph of `items`. An ID used twice is reported, and found as its
/// first use.
pub fn init(arena: std.mem.Allocator, items: []const Item, report: *Report) std.mem.Allocator.Error!Graph {
    var out: Graph = .{ .items = items };
    for (items, 0..) |item, i| {
        const entry = try out.by_id.getOrPut(arena, item.id);
        if (entry.found_existing) {
            const first = items[entry.value_ptr.*];
            try report.add(item.file, item.line, 1, "{s}: the ID is already used at {s}:{d}", .{ item.id, first.file, first.line });
        } else entry.value_ptr.* = i;
    }
    return out;
}

/// Reads the items of every source of `project` under `root`. Mistakes
/// go to `report`, and what could be read is still returned.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, report: *Report) std.mem.Allocator.Error!Graph {
    var items: std.ArrayList(Item) = .empty;
    for (project.sources) |source| {
        const files = listMarkdown(io, arena, root, source.path) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.add(Project.config_file, 0, 0, "sources: cannot read the directory '{s}' ({s})", .{ source.path, @errorName(e) });
                continue;
            },
        };
        for (files) |file| {
            const text = root.readFileAlloc(io, file, arena, .limited(1 << 26)) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    try report.add(file, 0, 0, "cannot read the file ({s})", .{@errorName(e)});
                    continue;
                },
            };
            if (!std.unicode.utf8ValidateSlice(text)) {
                try report.add(file, 0, 0, "the file is not valid UTF-8", .{});
                continue;
            }
            switch (source.kind) {
                .documents => try documents.read(arena, &project.schema, report, file, text, &items),
                .items => if (try item_file.read(arena, &project.schema, report, file, text, source.item_type)) |item| {
                    try items.append(arena, item);
                },
            }
        }
    }
    return init(arena, items.items, report);
}

/// The Markdown files under `dir` (a path from `root`), as paths from
/// `root` with forward slashes, in order
fn listMarkdown(io: Io, arena: std.mem.Allocator, root: Io.Dir, dir: []const u8) ![]const []const u8 {
    var d = try root.openDir(io, dir, .{ .iterate = true });
    defer d.close(io);
    var walker = try d.walk(arena);
    defer walker.deinit();
    var out: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.ascii.endsWithIgnoreCase(entry.path, ".md")) continue;
        const path = try arena.print("{s}/{s}", .{ dir, entry.path });
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

test {
    _ = @import("_test/read.zig");
    _ = @import("_test/checks.zig");
    _ = @import("_test/load.zig");
}
