//! Writes JSON, indented by two spaces, the same bytes for the same calls.

const std = @import("std");

const Json = @This();

pub const Error = std.mem.Allocator.Error;

arena: std.mem.Allocator,
out: std.ArrayList(u8) = .empty,
/// for each open object or array: whether it has a member yet
open: std.ArrayList(bool) = .empty,
/// a key was written, and its value comes next
after_key: bool = false,

/// What was written, with a line end
pub fn finish(self: *Json) Error![]const u8 {
    try self.out.append(self.arena, '\n');
    return self.out.items;
}

pub fn beginObject(self: *Json) Error!void {
    try self.begin('{');
}

pub fn endObject(self: *Json) Error!void {
    try self.end('}');
}

pub fn beginArray(self: *Json) Error!void {
    try self.begin('[');
}

pub fn endArray(self: *Json) Error!void {
    try self.end(']');
}

/// The key of the next value, in an object
pub fn key(self: *Json, name: []const u8) Error!void {
    try self.separate();
    try self.quoted(name);
    try self.out.appendSlice(self.arena, ": ");
    self.after_key = true;
}

pub fn string(self: *Json, value: []const u8) Error!void {
    try self.separate();
    try self.quoted(value);
}

/// A string, or null
pub fn optional(self: *Json, value: ?[]const u8) Error!void {
    if (value) |v| return self.string(v);
    try self.separate();
    try self.out.appendSlice(self.arena, "null");
}

pub fn integer(self: *Json, value: i64) Error!void {
    try self.separate();
    try self.out.print(self.arena, "{d}", .{value});
}

/// A number with one decimal: hours
pub fn tenths(self: *Json, value: f64) Error!void {
    try self.separate();
    try self.out.print(self.arena, "{d:.1}", .{value});
}

pub fn boolean(self: *Json, value: bool) Error!void {
    try self.separate();
    try self.out.appendSlice(self.arena, if (value) "true" else "false");
}

/// An array of strings
pub fn strings(self: *Json, values: []const []const u8) Error!void {
    try self.beginArray();
    for (values) |v| try self.string(v);
    try self.endArray();
}

fn begin(self: *Json, bracket: u8) Error!void {
    try self.separate();
    try self.out.append(self.arena, bracket);
    try self.open.append(self.arena, false);
}

fn end(self: *Json, bracket: u8) Error!void {
    const had_members = self.open.pop().?;
    if (had_members) try self.newline();
    try self.out.append(self.arena, bracket);
}

/// What comes before a member: a comma after the one before, and a new line
fn separate(self: *Json) Error!void {
    if (self.after_key) {
        self.after_key = false;
        return;
    }
    if (self.open.items.len == 0) return;
    const had_members = &self.open.items[self.open.items.len - 1];
    if (had_members.*) try self.out.append(self.arena, ',');
    had_members.* = true;
    try self.newline();
}

fn newline(self: *Json) Error!void {
    try self.out.append(self.arena, '\n');
    try self.out.appendNTimes(self.arena, ' ', self.open.items.len * 2);
}

fn quoted(self: *Json, s: []const u8) Error!void {
    try self.out.append(self.arena, '"');
    for (s) |c| switch (c) {
        '"' => try self.out.appendSlice(self.arena, "\\\""),
        '\\' => try self.out.appendSlice(self.arena, "\\\\"),
        '\n' => try self.out.appendSlice(self.arena, "\\n"),
        '\r' => try self.out.appendSlice(self.arena, "\\r"),
        '\t' => try self.out.appendSlice(self.arena, "\\t"),
        0...8, 11, 12, 14...0x1f => try self.out.print(self.arena, "\\u{x:0>4}", .{c}),
        else => try self.out.append(self.arena, c),
    };
    try self.out.append(self.arena, '"');
}

// req: export.json, principle.deterministic
test "objects, arrays and values, indented" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var j: Json = .{ .arena = arena.allocator() };
    try j.beginObject();
    try j.key("id");
    try j.string("lex.comment");
    try j.key("category");
    try j.optional(null);
    try j.key("line");
    try j.integer(5);
    try j.key("removed");
    try j.boolean(false);
    try j.key("links");
    try j.beginArray();
    try j.beginObject();
    try j.key("target");
    try j.string("a \"quoted\" \\ word\n\ttab\x01");
    try j.endObject();
    try j.endArray();
    try j.key("none");
    try j.strings(&.{});
    try j.key("empty");
    try j.beginObject();
    try j.endObject();
    try j.endObject();
    try std.testing.expectEqualStrings(
        \\{
        \\  "id": "lex.comment",
        \\  "category": null,
        \\  "line": 5,
        \\  "removed": false,
        \\  "links": [
        \\    {
        \\      "target": "a \"quoted\" \\ word\n\ttab\u0001"
        \\    }
        \\  ],
        \\  "none": [],
        \\  "empty": {}
        \\}
        \\
    , try j.finish());
}
