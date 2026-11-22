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
/// the statuses an item may have only while it is approved as it is
approval: []const []const u8 = &.{},
/// the roles that must each approve it, for those statuses; none when any
/// one approval will do
approval_roles: []const []const u8 = &.{},
attributes: []const Attribute = &.{},
/// when the type's items are tested examples: how
example: ?Example = null,
/// which attribute holds each planning role; null for a type that is not work
planning: ?Planning = null,

pub const Example = @import("Example.zig");
pub const Planning = @import("Planning.zig");

pub const default_statuses = [_][]const u8{ "draft", "approved", "deprecated", "removed" };

pub const IdScheme = union(enum) {
    /// `lex.comment.line`
    hierarchical,
    /// `SRS-012`
    numbered: Numbered,

    pub const Numbered = struct {
        prefix: []const u8,
        digits: u8 = 3,
        /// between the prefix and the number: "-", or nothing
        separator: []const u8 = "-",
        /// whether a name may stand in the number's place: `SRS-PURPOSE`
        names: bool = false,
    };
};

pub const Attribute = struct {
    name: []const u8,
    kind: Kind = .string,
    /// the values a string attribute may take; empty when any
    values: []const []const u8 = &.{},
    required: bool = false,
    /// whether a change to it changes the item's fingerprint
    normative: bool = false,
    /// whether it holds several values: `classes=A,B,C`
    list: bool = false,

    pub const Kind = enum { string, integer, boolean, date };
};

/// The type that the table of `r` declares; problems go to its report.
pub fn read(r: Reader, name: []const u8) Reader.Error!ItemType {
    try r.known(&.{ "description", "id", "prefix", "digits", "separator", "names", "categories", "statuses", "tombstone", "verification", "approval", "attributes", "example", "planning" });
    var out: ItemType = .{ .name = name };
    out.description = try r.string("description") orelse "";
    out.categories = try r.strings("categories");
    out.verification = try r.strings("verification");
    // `approval = [statuses]`, or `[approval]` with `statuses` and the `roles` that approve
    if (r.table.get("approval")) |v| if (v == .table) {
        const t = (try r.child("approval")).?;
        try t.known(&.{ "statuses", "roles" });
        out.approval = try t.strings("statuses");
        out.approval_roles = try t.strings("roles");
    } else {
        out.approval = try r.strings("approval");
    };

    const statuses = try r.strings("statuses");
    if (statuses.len > 0) out.statuses = statuses;
    if (try r.string("tombstone")) |t| out.tombstone = t;
    for (out.approval) |s| {
        if (!names.contains(out.statuses, s)) try r.complain("approval", "'{s}' is not one of the statuses", .{s});
    }
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
        if (try r.string("separator")) |s| numbered.separator = s;
        numbered.names = try r.boolean("names", false);
        out.id = .{ .numbered = numbered };
    } else if (std.mem.eql(u8, scheme, "hierarchical")) {
        if (r.table.get("prefix") != null) try r.complain("prefix", "only a type with numbered IDs has a prefix", .{});
        if (r.table.get("digits") != null) try r.complain("digits", "only a type with numbered IDs has digits", .{});
        if (r.table.get("separator") != null) try r.complain("separator", "only a type with numbered IDs has a separator", .{});
        if (r.table.get("names") != null) try r.complain("names", "only a type with numbered IDs has names", .{});
    } else try r.complain("id", "expected \"hierarchical\" or \"numbered\"", .{});

    if (try r.child("attributes")) |attrs| {
        var list: std.ArrayList(Attribute) = .empty;
        for (attrs.table.keys()) |attr_name| {
            if (!names.valid(attr_name)) try attrs.complain(attr_name, "{s}", .{names.rule});
            if (names.contains(&names.reserved, attr_name)) try attrs.complain(attr_name, "skein reads this key itself, so no attribute can have the name", .{});
            const a = try attrs.child(attr_name) orelse continue;
            try list.append(r.arena, try readAttribute(a, attr_name));
        }
        out.attributes = list.items;
    }
    if (try r.child("example")) |e| {
        out.example = try Example.read(e);
        if (out.categories.len > 0 and !names.contains(out.categories, out.example.?.rejects)) try e.complain("rejects", "'{s}' is not one of the categories", .{out.example.?.rejects});
    }
    if (try r.child("planning")) |p| out.planning = try Planning.read(p, out.attributes);
    return out;
}

fn readAttribute(r: Reader, name: []const u8) Reader.Error!Attribute {
    try r.known(&.{ "type", "values", "required", "normative", "list" });
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
    out.list = try r.boolean("list", false);
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
            const after = id[n.prefix.len..];
            if (!std.mem.startsWith(u8, after, n.separator)) return false;
            var rest = after[n.separator.len..];
            // a part's name after the number: `SWE-134.a`
            if (std.mem.findScalar(u8, rest, '.')) |dot| {
                var parts = std.mem.splitScalar(u8, rest[dot + 1 ..], '.');
                while (parts.next()) |part| {
                    if (part.len == 0) return false;
                    for (part) |c| if (!std.ascii.isLower(c) and !std.ascii.isDigit(c) and c != '_' and c != '-') return false;
                }
                rest = rest[0..dot];
            }
            if (rest.len == 0) return false;
            var digits = true;
            for (rest) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
                if (!std.ascii.isDigit(c)) digits = false;
            }
            // a number, or a name where the type allows names
            return if (digits) rest.len >= @as(usize, n.digits) else n.names;
        },
    }
}

// req: schema.item-type
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
    // a part of a numbered item extends its number
    try std.testing.expect(srs.idMatches("SRS-012.a"));
    try std.testing.expect(srs.idMatches("SRS-012.b.2"));
    try std.testing.expect(!srs.idMatches("SRS-012."));
    try std.testing.expect(!srs.idMatches("SRS-012.A"));
    try std.testing.expect(!srs.idMatches("SRS-.a"));
}

test "numbered IDs with another separator, or none" {
    const req: ItemType = .{ .name = "req", .id = .{ .numbered = .{ .prefix = "REQ", .separator = "" } } };
    try std.testing.expect(req.idMatches("REQ001"));
    try std.testing.expect(!req.idMatches("REQ-001"));
    try std.testing.expect(!req.idMatches("REQ01"));
    const hlr: ItemType = .{ .name = "hlr", .id = .{ .numbered = .{ .prefix = "HLR", .separator = "_", .digits = 2 } } };
    try std.testing.expect(hlr.idMatches("HLR_07"));
    try std.testing.expect(!hlr.idMatches("HLR07"));
}

test "numbered IDs with names in the number's place" {
    const plain: ItemType = .{ .name = "srs", .id = .{ .numbered = .{ .prefix = "SRS" } } };
    try std.testing.expect(!plain.idMatches("SRS-PURPOSE"));
    const named: ItemType = .{ .name = "srs", .id = .{ .numbered = .{ .prefix = "SRS", .names = true } } };
    try std.testing.expect(named.idMatches("SRS-PURPOSE"));
    try std.testing.expect(named.idMatches("SRS-012"));
    try std.testing.expect(!named.idMatches("SRS-12"));
    try std.testing.expect(!named.idMatches("SRS-"));
    try std.testing.expect(!named.idMatches("SRS-TWO WORDS"));
}
