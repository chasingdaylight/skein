//! The review records of a project: for each reviewed link, the
//! fingerprint its target had when the link was last reviewed. They are
//! kept under `.skein/reviews/`, one file per document or directory of
//! item files, one sorted line per link:
//!
//!     "t.lex.comment".verifies."lex.comment.line" = "9f2c..."
//!
//! skein writes these files; no one edits them by hand.

const std = @import("std");
const Io = std.Io;

const Graph = @import("Graph.zig");
const Item = @import("Item.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const fingerprint = @import("fingerprint.zig");
const toml = @import("../toml.zig");

const Reviews = @This();

pub const dir = Project.dir_name ++ "/reviews";

/// by `key`
records: std.array_hash_map.String([]const u8) = .empty,

fn key(arena: std.mem.Allocator, from: []const u8, link_type: []const u8, target: []const u8) ![]const u8 {
    return arena.print("{s}\n{s}\n{s}", .{ from, link_type, target });
}

/// The fingerprint recorded for the link; null when it was never reviewed
pub fn get(self: *const Reviews, arena: std.mem.Allocator, from: []const u8, link_type: []const u8, target: []const u8) !?[]const u8 {
    return self.records.get(try key(arena, from, link_type, target));
}

pub fn put(self: *Reviews, arena: std.mem.Allocator, from: []const u8, link_type: []const u8, target: []const u8, fp: []const u8) !void {
    try self.records.put(arena, try key(arena, from, link_type, target), try arena.dupe(u8, fp));
}

/// The file that holds the records of the links of `item`: named after
/// its document, or after the directory of its item file
pub fn fileOf(arena: std.mem.Allocator, item: *const Item) ![]const u8 {
    const subject = if (item.in_document) item.file else Io.Dir.path.dirnamePosix(item.file) orelse "_";
    return arena.print("{s}/{s}.toml", .{ dir, subject });
}

/// Reads every record under `.skein/reviews/`. Files that cannot be read
/// are reported.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, report: *Report) std.mem.Allocator.Error!Reviews {
    var out: Reviews = .{};
    var d = root.openDir(io, dir, .{ .iterate = true }) catch return out;
    defer d.close(io);
    var walker = try d.walk(arena);
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".toml")) continue;
        const path = try arena.print("{s}/{s}", .{ dir, entry.path });
        std.mem.replaceScalar(u8, path, '\\', '/');
        const text = d.readFileAlloc(io, entry.path, arena, .limited(1 << 26)) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.add(path, 0, 0, "cannot read the file ({s})", .{@errorName(e)});
                continue;
            },
        };
        var diag: toml.Diagnostic = .{};
        const table = toml.parse(arena, text, &diag) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidToml => {
                try report.add(path, diag.line, diag.column, "{s}", .{diag.message});
                continue;
            },
        };
        out.read(arena, table) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NotRecords => try report.add(path, 0, 0, "this is no file of review records; skein writes them, with 'skein review'", .{}),
        };
    }
    return out;
}

fn read(self: *Reviews, arena: std.mem.Allocator, table: *const toml.Table) !void {
    for (table.keys()) |from| {
        const by_type = table.get(from).?;
        if (by_type != .table) return error.NotRecords;
        for (by_type.table.keys()) |link_type| {
            const by_target = by_type.table.get(link_type).?;
            if (by_target != .table) return error.NotRecords;
            for (by_target.table.keys()) |target| {
                const fp = by_target.table.get(target).?;
                if (fp != .string) return error.NotRecords;
                try self.put(arena, from, link_type, target, fp.string);
            }
        }
    }
}

/// What a reviewed link is, held against its record
pub const State = enum { reviewed, never_reviewed, suspect };

/// The state of every reviewed link of `graph` whose target exists
pub fn stateOf(self: *const Reviews, arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph, item: *const Item, link: Item.Link) !?State {
    const link_type = schema.linkType(link.type_name) orelse return null;
    if (!link_type.review) return null;
    const target = graph.find(link.target) orelse return null;
    const target_type = schema.itemType(target.type_name) orelse return null;
    const recorded = try self.get(arena, item.id, link.type_name, link.target) orelse return .never_reviewed;
    const now = try fingerprint.of(arena, target, target_type);
    return if (std.mem.eql(u8, recorded, &now)) .reviewed else .suspect;
}

/// Reports the reviewed links that were never reviewed, and the suspect
/// ones: those whose target has changed since.
pub fn check(self: *const Reviews, arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph, report: *Report) std.mem.Allocator.Error!void {
    for (graph.items) |*item| {
        for (item.links) |link| {
            const state = try self.stateOf(arena, schema, graph, item, link) orelse continue;
            const line = if (link.line > 0) link.line else item.line;
            switch (state) {
                .reviewed => {},
                .never_reviewed => try report.add(item.file, line, 1, "{s}: {s}: the link to '{s}' was never reviewed ('skein review {s}')", .{ item.id, link.type_name, link.target, item.id }),
                .suspect => try report.add(item.file, line, 1, "{s}: {s}: '{s}' has changed since the link was reviewed ('skein review {s}')", .{ item.id, link.type_name, link.target, item.id }),
            }
        }
    }
}

/// Writes the record files named in `files` again, from the records held:
/// those of links that still exist, sorted. A file left without records
/// is deleted.
pub fn write(self: *const Reviews, io: Io, arena: std.mem.Allocator, root: Io.Dir, schema: *const Schema, graph: *const Graph, files: []const []const u8) !void {
    for (files) |file| {
        var lines: std.ArrayList([]const u8) = .empty;
        for (graph.items) |*item| {
            if (!std.mem.eql(u8, try fileOf(arena, item), file)) continue;
            for (item.links) |link| {
                const link_type = schema.linkType(link.type_name) orelse continue;
                if (!link_type.review) continue;
                const fp = try self.get(arena, item.id, link.type_name, link.target) orelse continue;
                try lines.append(arena, try arena.print("\"{s}\".{s}.\"{s}\" = \"{s}\"\n", .{ item.id, link.type_name, link.target, fp }));
            }
        }
        if (lines.items.len == 0) {
            root.deleteFile(io, file) catch {};
            continue;
        }
        std.mem.sort([]const u8, lines.items, {}, struct {
            fn lt(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lt);
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(arena, "# Review records, written by skein. Do not edit: use 'skein review'.\n");
        for (lines.items, 0..) |line, i| {
            // one link given twice is one record
            if (i > 0 and std.mem.eql(u8, line, lines.items[i - 1])) continue;
            try text.appendSlice(arena, line);
        }
        if (Io.Dir.path.dirnamePosix(file)) |parent| try root.createDirPath(io, parent);
        try root.writeFile(io, .{ .sub_path = file, .data = text.items });
    }
}

test {
    _ = fingerprint;
    _ = @import("_test/reviews.zig");
}
