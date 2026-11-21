//! Collects what a marker or front matter says about one item.

const std = @import("std");

const Item = @import("Item.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const references = @import("../markdown/references.zig");

const Builder = @This();

pub const Error = std.mem.Allocator.Error;

arena: std.mem.Allocator,
schema: *const Schema,
report: *Report,
item: Item,
attributes: std.ArrayList(Item.Attribute) = .empty,
links: std.ArrayList(Item.Link) = .empty,
refs: std.ArrayList(Item.Reference) = .empty,
/// the pieces of the item's own text, in order
pieces: std.ArrayList([]const u8) = .empty,
parts: std.ArrayList([]const u8) = .empty,

/// Where a piece of text stands in its file
pub const Place = struct {
    /// the file's line of the piece's first line
    line: u32,
    /// the columns before the piece on its first line
    first_col: u32 = 0,
    /// the columns taken off every line of the piece
    dedent: u32 = 0,
};

/// Takes `key = values`: the status, the verification method, links when
/// `key` is a link type, an attribute otherwise. `line` is 0 when unknown.
pub fn set(self: *Builder, key: []const u8, values: []const []const u8, line: u32) Error!void {
    const file = self.item.file;
    if (self.schema.linkType(key) != null) {
        for (values) |target| try self.links.append(self.arena, .{ .type_name = key, .target = target, .line = line });
        return;
    }
    if (values.len != 1) {
        return self.report.add(file, line, 1, "{s}: '{s}' takes one value", .{ self.item.id, key });
    }
    const value = values[0];
    if (std.mem.eql(u8, key, "status")) {
        self.item.status = value;
    } else if (std.mem.eql(u8, key, "verification")) {
        self.item.verification = value;
    } else if (std.mem.eql(u8, key, "category")) {
        self.item.category = value;
    } else {
        for (self.attributes.items) |a| {
            if (std.mem.eql(u8, a.name, key)) {
                return self.report.add(file, line, 1, "{s}: '{s}' is given twice", .{ self.item.id, key });
            }
        }
        try self.attributes.append(self.arena, .{ .name = key, .value = value, .line = line });
    }
}

/// Adds a piece to the item's own text, and the references in it
pub fn addText(self: *Builder, piece: []const u8, place: Place) Error!void {
    try self.pieces.append(self.arena, piece);
    for (try references.find(self.arena, piece)) |r| {
        const at = references.position(piece, r.offset);
        try self.refs.append(self.arena, .{
            .target = r.target,
            .line = place.line + at.line - 1,
            .column = at.column + place.dedent + (if (at.line == 1) place.first_col else 0),
        });
    }
}

/// Makes the item `id` a part of this one
pub fn addPart(self: *Builder, id: []const u8) Error!void {
    try self.parts.append(self.arena, id);
}

pub fn finish(self: *Builder) Error!Item {
    self.item.attributes = self.attributes.items;
    self.item.links = self.links.items;
    self.item.references = self.refs.items;
    self.item.text = if (self.pieces.items.len == 1) self.pieces.items[0] else try std.mem.join(self.arena, "\n\n", self.pieces.items);
    self.item.parts = self.parts.items;
    return self.item;
}
