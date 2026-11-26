//! An element of an XML document: its name, attributes and content.

const std = @import("std");

const Element = @This();

/// as written, with its prefix: `xhtml:div`
name: []const u8,
attributes: []const Attribute = &.{},
/// child elements and text, in order
content: []const Node = &.{},
/// where it starts, 1-based
line: u32 = 1,

pub const Attribute = struct { name: []const u8, value: []const u8 };

pub const Node = union(enum) {
    element: *const Element,
    text: []const u8,
};

/// The name without its prefix
pub fn local(name: []const u8) []const u8 {
    const colon = std.mem.findScalar(u8, name, ':') orelse return name;
    return name[colon + 1 ..];
}

/// Whether the element's name, without its prefix, is `name`
pub fn is(self: *const Element, name: []const u8) bool {
    return std.mem.eql(u8, local(self.name), name);
}

/// The value of the attribute `name`, compared without prefixes
pub fn attribute(self: *const Element, name: []const u8) ?[]const u8 {
    for (self.attributes) |a| {
        if (std.mem.eql(u8, local(a.name), name)) return a.value;
    }
    return null;
}

/// The first child element called `name` (without prefixes)
pub fn child(self: *const Element, name: []const u8) ?*const Element {
    for (self.content) |n| switch (n) {
        .element => |e| if (e.is(name)) return e,
        .text => {},
    };
    return null;
}

/// The child elements called `name` (without prefixes), in order
pub fn children(self: *const Element, arena: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const *const Element {
    var out: std.ArrayList(*const Element) = .empty;
    for (self.content) |n| switch (n) {
        .element => |e| if (e.is(name)) try out.append(arena, e),
        .text => {},
    };
    return out.items;
}

/// All the text inside the element, its children's too, in order
pub fn text(self: *const Element, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    if (self.content.len == 1 and self.content[0] == .text) return self.content[0].text;
    var out: std.ArrayList(u8) = .empty;
    try self.appendText(arena, &out);
    return out.items;
}

fn appendText(self: *const Element, arena: std.mem.Allocator, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    for (self.content) |n| switch (n) {
        .element => |e| try e.appendText(arena, out),
        .text => |t| try out.appendSlice(arena, t),
    };
}
