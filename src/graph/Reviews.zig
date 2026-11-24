//! The review records of a project: for each reviewed link, the
//! fingerprint its target had when the link was last reviewed. They are
//! kept under `.skein/reviews/` (record_files.zig), one line per link:
//!
//!     "t.lex.comment".verifies."lex.comment.line" = "9f2c..."

const std = @import("std");
const Io = std.Io;

const Citations = @import("Citations.zig");
const Graph = @import("Graph.zig");
const Item = @import("Item.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const fingerprint = @import("fingerprint.zig");
const record_files = @import("record_files.zig");
const toml = @import("../toml.zig");

const Reviews = @This();

pub const dir = Project.dir_name ++ "/reviews";
const header = "# Review records, written by skein. Do not edit: use 'skein review'.\n";

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

/// The file that holds the records of the links of `item`
pub fn fileOf(arena: std.mem.Allocator, item: *const Item) ![]const u8 {
    return record_files.fileOf(arena, dir, item);
}

/// Reads every record under `.skein/reviews/`. Files that cannot be read
/// are reported.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, report: *Report) std.mem.Allocator.Error!Reviews {
    var out: Reviews = .{};
    for (try record_files.load(io, arena, root, dir, report)) |file| {
        out.read(arena, file.table) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NotRecords => try report.add(file.path, 0, 0, "this is no file of review records; skein writes them, with 'skein review'", .{}),
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

/// The state of a link of `item`; null when its type is not reviewed or
/// its target does not exist
pub fn stateOf(self: *const Reviews, arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph, item: *const Item, link: Item.Link) !?State {
    const link_type = schema.linkType(link.type_name) orelse return null;
    if (!link_type.review) return null;
    const now = try targetFingerprint(arena, schema, graph, link.target) orelse return null;
    const recorded = try self.get(arena, item.id, link.type_name, link.target) orelse return .never_reviewed;
    return if (std.mem.eql(u8, recorded, &now)) .reviewed else .suspect;
}

/// The fingerprint of the item `id` names, in this repository or another;
/// null when there is none, or its type is unknown
pub fn targetFingerprint(arena: std.mem.Allocator, schema: *const Schema, graph: *const Graph, id: []const u8) !?fingerprint.Fingerprint {
    const t = graph.target(schema, id) orelse return null;
    if (t.schema.itemType(t.item.type_name) == null) return null;
    return try fingerprint.of(arena, t.graph, t.schema, t.item);
}

/// The link type a citation of `set` is recorded under: no link type has a colon
fn citationLink(arena: std.mem.Allocator, set: []const u8) ![]const u8 {
    return arena.print("cite:{s}", .{set});
}

/// The file that holds the records of the citations in `file`
pub fn citationFileOf(arena: std.mem.Allocator, file: []const u8) ![]const u8 {
    return arena.print("{s}/citations/{s}.toml", .{ dir, file });
}

/// What a citation is, held against its record; null when its citation set is
/// not reviewed or the item it names does not exist
pub fn citationState(self: *const Reviews, arena: std.mem.Allocator, project: *const Project, graph: *const Graph, c: Citations.Citation) !?State {
    const set = project.citationSet(c.set) orelse return null;
    if (!set.review) return null;
    const now = try targetFingerprint(arena, &project.schema, graph, c.target) orelse return null;
    const recorded = try self.get(arena, c.file, try citationLink(arena, c.set), c.target) orelse return .never_reviewed;
    return if (std.mem.eql(u8, recorded, &now)) .reviewed else .suspect;
}

/// Records that the citation `c` was reviewed against the item as it is now
pub fn putCitation(self: *Reviews, arena: std.mem.Allocator, c: Citations.Citation, fp: []const u8) !void {
    try self.put(arena, c.file, try citationLink(arena, c.set), c.target, fp);
}

/// Reports the citations of reviewed sets that were never reviewed, and the
/// suspect ones: those whose item has changed since.
pub fn checkCitations(self: *const Reviews, arena: std.mem.Allocator, project: *const Project, graph: *const Graph, citations: *const Citations, report: *Report) std.mem.Allocator.Error!void {
    for (citations.all) |c| {
        const state = try self.citationState(arena, project, graph, c) orelse continue;
        switch (state) {
            .reviewed => {},
            .never_reviewed => try report.add(c.file, c.line, c.column, "the citation of '{s}' was never reviewed ('skein review {s}')", .{ c.target, c.file }),
            .suspect => try report.add(c.file, c.line, c.column, "'{s}' has changed since the citation was reviewed ('skein clear {s}')", .{ c.target, c.target }),
        }
    }
}

/// Writes the record files named in `files` again, from the records held of
/// the citations that still exist
pub fn writeCitations(self: *const Reviews, io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, citations: *const Citations, files: []const []const u8) !void {
    var buckets: std.array_hash_map.String(std.ArrayList([]const u8)) = .empty;
    for (files) |file| try buckets.put(arena, file, .empty);
    for (citations.all) |c| {
        const set = project.citationSet(c.set) orelse continue;
        if (!set.review) continue;
        const lines = buckets.getPtr(try citationFileOf(arena, c.file)) orelse continue;
        const fp = try self.get(arena, c.file, try citationLink(arena, c.set), c.target) orelse continue;
        try lines.append(arena, try arena.print("\"{s}\".\"{s}\".\"{s}\" = \"{s}\"\n", .{ try record_files.escape(arena, c.file), try citationLink(arena, c.set), c.target, fp }));
    }
    for (buckets.keys(), buckets.values()) |file, *lines| try record_files.write(io, arena, root, file, header, lines.items);
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
/// those of links that still exist. A file left without records is deleted.
pub fn write(self: *const Reviews, io: Io, arena: std.mem.Allocator, root: Io.Dir, schema: *const Schema, graph: *const Graph, files: []const []const u8) !void {
    var buckets: std.array_hash_map.String(std.ArrayList([]const u8)) = .empty;
    for (files) |file| try buckets.put(arena, file, .empty);
    for (graph.items) |*item| {
        // an item without links has no file to be in
        if (item.links.len == 0) continue;
        const lines = buckets.getPtr(try fileOf(arena, item)) orelse continue;
        for (item.links) |link| {
            const link_type = schema.linkType(link.type_name) orelse continue;
            if (!link_type.review) continue;
            const fp = try self.get(arena, item.id, link.type_name, link.target) orelse continue;
            try lines.append(arena, try arena.print("\"{s}\".{s}.\"{s}\" = \"{s}\"\n", .{ item.id, link.type_name, link.target, fp }));
        }
    }
    for (buckets.keys(), buckets.values()) |file, *lines| try record_files.write(io, arena, root, file, header, lines.items);
}

test {
    _ = fingerprint;
    _ = @import("_test/reviews.zig");
    _ = @import("_test/cite_reviews.zig");
}
