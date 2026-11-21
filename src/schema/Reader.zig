//! Reads typed values out of one TOML table, reporting what is of the
//! wrong kind and the keys it does not know.

const std = @import("std");

const Report = @import("../Report.zig");
const toml = @import("../toml.zig");

const Reader = @This();

pub const Error = std.mem.Allocator.Error;

report: *Report,
arena: std.mem.Allocator,
file: []const u8,
/// the keys leading to `table` ("attributes.priority"), for messages
path: []const u8 = "",
table: *const toml.Table,

/// Reports a problem with `key` of this table
pub fn complain(self: Reader, key: []const u8, comptime fmt: []const u8, args: anytype) Error!void {
    const message = try self.arena.print(fmt, args);
    const sep = if (self.path.len > 0 and key.len > 0) "." else "";
    try self.report.add(self.file, 0, 0, "{s}{s}{s}: {s}", .{ self.path, sep, key, message });
}

pub fn string(self: Reader, key: []const u8) Error!?[]const u8 {
    const v = self.table.get(key) orelse return null;
    if (v == .string) return v.string;
    try self.complain(key, "expected a string", .{});
    return null;
}

pub fn boolean(self: Reader, key: []const u8, default: bool) Error!bool {
    const v = self.table.get(key) orelse return default;
    if (v == .boolean) return v.boolean;
    try self.complain(key, "expected true or false", .{});
    return default;
}

pub fn integer(self: Reader, key: []const u8) Error!?i64 {
    const v = self.table.get(key) orelse return null;
    if (v == .integer) return v.integer;
    try self.complain(key, "expected an integer", .{});
    return null;
}

/// An array of strings; empty when the key is absent
pub fn strings(self: Reader, key: []const u8) Error![]const []const u8 {
    const v = self.table.get(key) orelse return &.{};
    if (v != .array) {
        try self.complain(key, "expected an array of strings", .{});
        return &.{};
    }
    var out: std.ArrayList([]const u8) = .empty;
    for (v.array.values()) |item| {
        if (item != .string) {
            try self.complain(key, "expected an array of strings", .{});
            return &.{};
        }
        try out.append(self.arena, item.string);
    }
    return out.items;
}

/// A reader of the table at `key`; null when the key is absent
pub fn child(self: Reader, key: []const u8) Error!?Reader {
    const v = self.table.get(key) orelse return null;
    if (v != .table) {
        try self.complain(key, "expected a table", .{});
        return null;
    }
    return try self.descend(key, v.table);
}

/// Readers of the tables in the array at `key` (`[[key]]`)
pub fn children(self: Reader, key: []const u8) Error![]const Reader {
    const v = self.table.get(key) orelse return &.{};
    if (v != .array) {
        try self.complain(key, "expected an array of tables", .{});
        return &.{};
    }
    var out: std.ArrayList(Reader) = .empty;
    for (v.array.values(), 0..) |item, i| {
        if (item != .table) {
            try self.complain(key, "expected an array of tables", .{});
            return &.{};
        }
        const name = try self.arena.print("{s}[{d}]", .{ key, i + 1 });
        try out.append(self.arena, try self.descend(name, item.table));
    }
    return out.items;
}

fn descend(self: Reader, key: []const u8, table: *const toml.Table) Error!Reader {
    var sub = self;
    sub.table = table;
    sub.path = if (self.path.len == 0) key else try self.arena.print("{s}.{s}", .{ self.path, key });
    return sub;
}

/// Reports every key of the table that is not one of `keys`: a misspelled
/// key must not be ignored in silence
pub fn known(self: Reader, keys: []const []const u8) Error!void {
    next: for (self.table.keys()) |key| {
        for (keys) |k| {
            if (std.mem.eql(u8, key, k)) continue :next;
        }
        try self.complain(key, "unknown key", .{});
    }
}
