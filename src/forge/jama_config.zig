//! What `skein jama` is told of the Jama Connect project, in
//! `.skein/jama.toml`, written by hand:
//!
//!     url = "https://example.jamacloud.com"
//!     project = 42
//!     parent = 1201            # where new items go; the project's root when left out
//!
//!     [types]                  # the Jama item type of each Skein type published
//!     requirement = 89
//!
//!     [links]                  # the relationship type of each link type
//!     derives = 4              # from the link's source to its target
//!     verifies = { type = 5, reverse = true }   # from its target to its source
//!
//! and the Jama item of each Skein item, in `.skein/jama-map.toml`, which
//! skein writes and the project commits.

const std = @import("std");
const Io = std.Io;

const toml = @import("../toml.zig");
const write = @import("../toml/write.zig");

pub const config_file = ".skein/jama.toml";
pub const map_file = ".skein/jama-map.toml";

pub const Link = struct { name: []const u8, type: i64, reverse: bool = false };
pub const Type = struct { name: []const u8, id: i64 };

pub const Config = struct {
    url: ?[]const u8 = null,
    project: i64,
    parent: ?i64 = null,
    types: []const Type = &.{},
    links: []const Link = &.{},

    pub fn typeId(self: Config, name: []const u8) ?i64 {
        for (self.types) |t| if (std.mem.eql(u8, t.name, name)) return t.id;
        return null;
    }

    pub fn link(self: Config, name: []const u8) ?Link {
        for (self.links) |l| if (std.mem.eql(u8, l.name, name)) return l;
        return null;
    }
};

pub const Loaded = union(enum) { ok: Config, missing, failed: []const u8 };

pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir) !Loaded {
    const text = root.readFileAlloc(io, config_file, arena, .limited(1 << 20)) catch return .missing;
    return parse(arena, text);
}

pub fn parse(arena: std.mem.Allocator, text: []const u8) !Loaded {
    var diag: toml.Diagnostic = .{};
    const t = toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => return .{ .failed = try arena.print("{s}:{d}:{d}: {s}", .{ config_file, diag.line, diag.column, diag.message }) },
    };
    for (t.keys()) |k| {
        if (!contains(&.{ "url", "project", "parent", "types", "links" }, k)) return .{ .failed = try arena.print("{s}: '{s}' is not a key skein knows (url, project, parent, types, links)", .{ config_file, k }) };
    }
    var c: Config = .{ .project = undefined };
    if (t.get("url")) |v| c.url = if (v == .string) v.string else return wrong(arena, "url", "a string");
    const project = t.get("project") orelse return .{ .failed = try arena.print("{s}: give the Jama project's id, project = 42", .{config_file}) };
    c.project = if (project == .integer) project.integer else return wrong(arena, "project", "a number");
    if (t.get("parent")) |v| c.parent = if (v == .integer) v.integer else return wrong(arena, "parent", "a number");
    var types: std.ArrayList(Type) = .empty;
    if (t.get("types")) |v| {
        if (v != .table) return wrong(arena, "types", "a table of item types and ids");
        for (v.table.keys()) |k| {
            const id = v.table.get(k).?;
            if (id != .integer) return wrong(arena, try arena.print("types.{s}", .{k}), "a number");
            try types.append(arena, .{ .name = k, .id = id.integer });
        }
    }
    c.types = types.items;
    var links: std.ArrayList(Link) = .empty;
    if (t.get("links")) |v| {
        if (v != .table) return wrong(arena, "links", "a table of link types and relationship types");
        for (v.table.keys()) |k| {
            const l = v.table.get(k).?;
            switch (l) {
                .integer => |n| try links.append(arena, .{ .name = k, .type = n }),
                .table => |lt| {
                    const n = lt.get("type") orelse return wrong(arena, try arena.print("links.{s}", .{k}), "a number, or { type = N, reverse = true }");
                    if (n != .integer) return wrong(arena, try arena.print("links.{s}.type", .{k}), "a number");
                    const r = lt.get("reverse") orelse toml.Value{ .boolean = false };
                    if (r != .boolean) return wrong(arena, try arena.print("links.{s}.reverse", .{k}), "true or false");
                    try links.append(arena, .{ .name = k, .type = n.integer, .reverse = r.boolean });
                },
                else => return wrong(arena, try arena.print("links.{s}", .{k}), "a number, or { type = N, reverse = true }"),
            }
        }
    }
    c.links = links.items;
    return .{ .ok = c };
}

fn wrong(arena: std.mem.Allocator, key: []const u8, what: []const u8) !Loaded {
    return .{ .failed = try arena.print("{s}: {s} is to be {s}", .{ config_file, key, what }) };
}

pub const Entry = struct { id: []const u8, jama: i64 };

pub fn loadMap(io: Io, arena: std.mem.Allocator, root: Io.Dir) ![]const Entry {
    var out: std.ArrayList(Entry) = .empty;
    const text = root.readFileAlloc(io, map_file, arena, .limited(1 << 24)) catch return out.items;
    var diag: toml.Diagnostic = .{};
    const t = toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => return out.items,
    };
    for (t.keys()) |id| {
        const v = t.get(id) orelse continue;
        if (v == .integer and v.integer > 0) try out.append(arena, .{ .id = id, .jama = v.integer });
    }
    return out.items;
}

/// Writes the map, in the order of the Jama ids
pub fn saveMap(io: Io, arena: std.mem.Allocator, root: Io.Dir, entries: []const Entry) !void {
    const sorted = try arena.dupe(Entry, entries);
    std.mem.sort(Entry, sorted, {}, byJama);
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(arena, "# The Jama Connect item of each item: written by skein jama, committed.\n");
    for (sorted) |e| try text.print(arena, "{s} = {d}\n", .{ try write.string(arena, e.id), e.jama });
    try root.writeFile(io, .{ .sub_path = map_file, .data = text.items });
}

fn byJama(_: void, a: Entry, b: Entry) bool {
    return a.jama < b.jama;
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, s)) return true;
    return false;
}

test "the configuration, and its mistakes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const c = (try parse(a, "url = \"https://x.jamacloud.com\"\nproject = 42\nparent = 7\n[types]\nrequirement = 89\n[links]\nderives = 4\nverifies = { type = 5, reverse = true }\n")).ok;
    try std.testing.expectEqual(42, c.project);
    try std.testing.expectEqual(89, c.typeId("requirement").?);
    try std.testing.expect(c.link("verifies").?.reverse);
    try std.testing.expect(!c.link("derives").?.reverse);
    try std.testing.expectEqualStrings(".skein/jama.toml: give the Jama project's id, project = 42", (try parse(a, "url = \"x\"\n")).failed);
    try std.testing.expectEqualStrings(".skein/jama.toml: 'projet' is not a key skein knows (url, project, parent, types, links)", (try parse(a, "projet = 1\n")).failed);
    try std.testing.expectEqualStrings(".skein/jama.toml: types.requirement is to be a number", (try parse(a, "project = 1\n[types]\nrequirement = \"REQ\"\n")).failed);
}
