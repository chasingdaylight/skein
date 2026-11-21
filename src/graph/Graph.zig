//! A project's items, and how to find one by its ID.

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const documents = @import("documents.zig");
const files = @import("../files.zig");
const item_file = @import("item_file.zig");
pub const Item = @import("Item.zig");
pub const Mention = documents.Mention;
pub const checks = @import("checks.zig");
pub const Reviews = @import("Reviews.zig");
pub const Citations = @import("Citations.zig");
pub const Approvals = @import("Approvals.zig");

const Graph = @This();

/// in the order of the sources, the files (by path) and the lines
items: []const Item = &.{},
by_id: std.array_hash_map.String(usize) = .empty,
/// by target: the links that point to it, in the order of the items
incoming: std.array_hash_map.String(std.ArrayList(Incoming)) = .empty,
/// by target: the IDs of the items whose text refers to it, each once
referrers: std.array_hash_map.String(std.ArrayList([]const u8)) = .empty,

/// the references to items in narrative text, in the order read
mentions: []const Mention = &.{},

/// A link, with the item it is a link of
pub const Incoming = struct {
    from: *const Item,
    link: Item.Link,
};

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
    for (items) |*item| {
        for (item.links) |link| {
            const entry = try out.incoming.getOrPut(arena, link.target);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(arena, .{ .from = item, .link = link });
        }
        for (item.references) |r| {
            const entry = try out.referrers.getOrPut(arena, r.target);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            const ids = entry.value_ptr.items;
            if (ids.len == 0 or !std.mem.eql(u8, ids[ids.len - 1], item.id)) try entry.value_ptr.append(arena, item.id);
        }
    }
    return out;
}

/// Reads the items of every source of `project` under `root`. Mistakes
/// go to `report`, and what could be read is still returned.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, report: *Report) std.mem.Allocator.Error!Graph {
    var items: std.ArrayList(Item) = .empty;
    var mentions: std.ArrayList(Mention) = .empty;
    for (project.sources) |source| {
        const paths = files.list(io, arena, root, source.path, &.{".md"}) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.add(Project.config_file, 0, 0, "sources: cannot read the directory '{s}' ({s})", .{ source.path, @errorName(e) });
                continue;
            },
        };
        for (paths) |file| {
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
                .documents => try documents.read(arena, &project.schema, report, file, text, &items, &mentions),
                .items => if (try item_file.read(arena, &project.schema, report, file, text, source.item_type)) |item| {
                    try items.append(arena, item);
                },
            }
        }
    }
    var out = try init(arena, items.items, report);
    out.mentions = mentions.items;
    return out;
}

test {
    _ = @import("_test/read.zig");
    _ = @import("_test/parts.zig");
    _ = @import("_test/checks.zig");
    _ = @import("_test/load.zig");
    _ = Reviews;
    _ = Citations;
    _ = Approvals;
    _ = files;
}
