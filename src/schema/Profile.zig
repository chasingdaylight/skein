//! A named selection of items, as `.skein/profiles/<name>.toml` declares
//! it. An item is in the profile when it passes every condition given.

const std = @import("std");

const Reader = @import("Reader.zig");

const Profile = @This();

name: []const u8,
description: []const u8 = "",
/// item types; empty when any
types: []const []const u8 = &.{},
/// categories; empty when any
categories: []const []const u8 = &.{},
/// statuses; empty when any
statuses: []const []const u8 = &.{},
/// attributes that must have one of the values listed
where: []const Condition = &.{},

pub const Condition = struct {
    attribute: []const u8,
    values: []const []const u8,
};

/// The profile that the table of `r` declares; problems go to its report.
pub fn read(r: Reader, name: []const u8) Reader.Error!Profile {
    try r.known(&.{ "description", "types", "categories", "statuses", "where" });
    var out: Profile = .{
        .name = name,
        .description = try r.string("description") orelse "",
        .types = try r.strings("types"),
        .categories = try r.strings("categories"),
        .statuses = try r.strings("statuses"),
    };
    if (try r.child("where")) |where| {
        var list: std.ArrayList(Condition) = .empty;
        for (where.table.keys()) |attribute| {
            // one value or several: `stage = "s0"`, `stage = ["s0", "s1"]`
            const v = where.table.get(attribute).?;
            const values: []const []const u8 = if (v == .string) blk: {
                const one = try r.arena.alloc([]const u8, 1);
                one[0] = v.string;
                break :blk one;
            } else try where.strings(attribute);
            if (values.len == 0) {
                if (v == .array) try where.complain(attribute, "expected at least one value", .{});
                continue;
            }
            try list.append(r.arena, .{ .attribute = attribute, .values = values });
        }
        out.where = list.items;
    }
    return out;
}
