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

/// Sets the item's text, whose first line is line `first_line` of the
/// file, and finds the references in it
pub fn setText(self: *Builder, text: []const u8, first_line: u32) Error!void {
    self.item.text = text;
    var refs: std.ArrayList(Item.Reference) = .empty;
    for (try references.find(self.arena, text)) |r| {
        const at = references.position(text, r.offset);
        try refs.append(self.arena, .{ .target = r.target, .line = first_line + at.line - 1, .column = at.column });
    }
    self.item.references = refs.items;
}

pub fn finish(self: *Builder) Item {
    self.item.attributes = self.attributes.items;
    self.item.links = self.links.items;
    return self.item;
}
