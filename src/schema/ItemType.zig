//! One kind of item, as `.skein/types/<name>.toml` declares it.

const std = @import("std");

const Reader = @import("Reader.zig");
const names = @import("names.zig");

const ItemType = @This();

name: []const u8,
description: []const u8 = "",
id: IdScheme = .hierarchical,
/// empty when items of the type have no category
categories: []const []const u8 = &.{},
statuses: []const []const u8 = &default_statuses,
/// the status of a removed item, whose ID stays taken; null when the
/// type's statuses have none
tombstone: ?[]const u8 = "removed",
/// the verification methods an item of the type may name
verification: []const []const u8 = &.{},
attributes: []const Attribute = &.{},

pub const default_statuses = [_][]const u8{ "draft", "approved", "deprecated", "removed" };

pub const IdScheme = union(enum) {
    /// `lex.comment.line`
    hierarchical,
    /// `SRS-012`
    numbered: Numbered,

    pub const Numbered = struct { prefix: []const u8, digits: u8 = 3 };
};

pub const Attribute = struct {
    name: []const u8,
    kind: Kind = .string,
    /// the values a string attribute may take; empty when any
    values: []const []const u8 = &.{},
    required: bool = false,
    /// whether a change to it changes the item's fingerprint
    normative: bool = false,

    pub const Kind = enum { string, integer, boolean, date };
};

/// The type that the table of `r` declares; problems go to its report.
pub fn read(r: Reader, name: []const u8) Reader.Error!ItemType {
    try r.known(&.{ "description", "id", "prefix", "digits", "categories", "statuses", "tombstone", "verification", "attributes" });
    var out: ItemType = .{ .name = name };
    out.description = try r.string("description") orelse "";
    out.categories = try r.strings("categories");
    out.verification = try r.strings("verification");

    const statuses = try r.strings("statuses");
    if (statuses.len > 0) out.statuses = statuses;
    if (try r.string("tombstone")) |t| out.tombstone = t;
    if (out.tombstone) |t| {
        if (!names.contains(out.statuses, t)) {
            // the default, with statuses that have no "removed", means none
            if (r.table.get("tombstone") != null) try r.complain("tombstone", "'{s}' is not one of the statuses", .{t});
            out.tombstone = null;
        }
    }

    const scheme = try r.string("id") orelse "hierarchical";
    if (std.mem.eql(u8, scheme, "numbered")) {
        var numbered: IdScheme.Numbered = .{ .prefix = try r.string("prefix") orelse "" };
        if (numbered.prefix.len == 0) try r.complain("prefix", "a type with numbered IDs needs a prefix", .{});
        if (try r.integer("digits")) |d| {
            if (d < 1 or d > 9) try r.complain("digits", "expected 1 to 9", .{}) else numbered.digits = @intCast(d);
        }
        out.id = .{ .numbered = numbered };
    } else if (std.mem.eql(u8, scheme, "hierarchical")) {
        if (r.table.get("prefix") != null) try r.complain("prefix", "only a type with numbered IDs has a prefix", .{});
        if (r.table.get("digits") != null) try r.complain("digits", "only a type with numbered IDs has digits", .{});
    } else try r.complain("id", "expected \"hierarchical\" or \"numbered\"", .{});

    if (try r.child("attributes")) |attrs| {
        var list: std.ArrayList(Attribute) = .empty;
        for (attrs.table.keys()) |attr_name| {
            if (!names.valid(attr_name)) try attrs.complain(attr_name, "{s}", .{names.rule});
            const a = try attrs.child(attr_name) orelse continue;
            try list.append(r.arena, try readAttribute(a, attr_name));
        }
        out.attributes = list.items;
    }
    return out;
}

fn readAttribute(r: Reader, name: []const u8) Reader.Error!Attribute {
    try r.known(&.{ "type", "values", "required", "normative" });
    var out: Attribute = .{ .name = name };
    if (try r.string("type")) |t| {
        out.kind = std.meta.stringToEnum(Attribute.Kind, t) orelse blk: {
            try r.complain("type", "expected \"string\", \"integer\", \"boolean\" or \"date\"", .{});
            break :blk .string;
        };
    }
    out.values = try r.strings("values");
    if (out.values.len > 0 and out.kind != .string) try r.complain("values", "only a string attribute lists its values", .{});
    out.required = try r.boolean("required", false);
    out.normative = try r.boolean("normative", false);
    return out;
}

pub fn attribute(self: *const ItemType, name: []const u8) ?*const Attribute {
    for (self.attributes) |*a| {
        if (std.mem.eql(u8, a.name, name)) return a;
    }
    return null;
}

/// Whether `id` is spelled as the type's IDs are
pub fn idMatches(self: *const ItemType, id: []const u8) bool {
    switch (self.id) {
        .hierarchical => {
            var parts = std.mem.splitScalar(u8, id, '.');
            while (parts.next()) |part| {
                if (part.len == 0) return false;
                for (part) |c| {
                    if (!std.ascii.isLower(c) and !std.ascii.isDigit(c) and c != '_' and c != '-') return false;
                }
            }
            return true;
        },
        .numbered => |n| {
            if (!std.mem.startsWith(u8, id, n.prefix)) return false;
            const rest = id[n.prefix.len..];
            if (rest.len < 1 + @as(usize, n.digits) or rest[0] != '-') return false;
            for (rest[1..]) |c| {
                if (!std.ascii.isDigit(c)) return false;
            }
            return true;
        },
    }
}

test "IDs are matched against the type's scheme" {
    const rule: ItemType = .{ .name = "rule" };
    try std.testing.expect(rule.idMatches("lex.comment.line"));
    try std.testing.expect(rule.idMatches("expr"));
    try std.testing.expect(rule.idMatches("expr.as-narrow.rule_2"));
    try std.testing.expect(!rule.idMatches("lex..line"));
    try std.testing.expect(!rule.idMatches("Lex.line"));
    try std.testing.expect(!rule.idMatches(""));
    try std.testing.expect(!rule.idMatches("lex line"));

    const srs: ItemType = .{ .name = "srs", .id = .{ .numbered = .{ .prefix = "SRS" } } };
    try std.testing.expect(srs.idMatches("SRS-012"));
    try std.testing.expect(srs.idMatches("SRS-1234"));
    try std.testing.expect(!srs.idMatches("SRS-12"));
    try std.testing.expect(!srs.idMatches("SRS012"));
    try std.testing.expect(!srs.idMatches("SYS-012"));
    try std.testing.expect(!srs.idMatches("SRS-01a"));
}
