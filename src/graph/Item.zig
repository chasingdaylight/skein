//! One item, as its file or its marker gives it.

const std = @import("std");

const Schema = @import("../schema/Schema.zig");

const Item = @This();

id: []const u8,
type_name: []const u8,
/// as written; null when the item names none (`effectiveStatus`)
status: ?[]const u8 = null,
category: ?[]const u8 = null,
/// the verification method the item names
verification: ?[]const u8 = null,
attributes: []const Attribute = &.{},
links: []const Link = &.{},
references: []const Reference = &.{},
/// the item's Markdown; empty for a removed item
text: []const u8 = "",
/// from the project's root, with forward slashes
file: []const u8,
/// where the item is declared: its marker, or 1 for an item file
line: u32,
/// whether the item is a paragraph of a document, not a file of its own
in_document: bool = true,

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
    /// 0 when the place is not known (front matter)
    line: u32 = 0,
};

pub const Link = struct {
    type_name: []const u8,
    target: []const u8,
    line: u32 = 0,
};

/// A reference to another item in the item's text
pub const Reference = struct {
    target: []const u8,
    line: u32,
    column: u32,
};

/// The item's status: the one it names, else the first of its type's
pub fn effectiveStatus(self: *const Item, item_type: *const Schema.ItemType) []const u8 {
    return self.status orelse item_type.statuses[0];
}

/// Whether the item is removed: its ID stays taken and nothing may point to it
pub fn isTombstone(self: *const Item, item_type: *const Schema.ItemType) bool {
    const tombstone = item_type.tombstone orelse return false;
    return std.mem.eql(u8, self.effectiveStatus(item_type), tombstone);
}

pub fn attribute(self: *const Item, name: []const u8) ?[]const u8 {
    for (self.attributes) |a| {
        if (std.mem.eql(u8, a.name, name)) return a.value;
    }
    return null;
}
