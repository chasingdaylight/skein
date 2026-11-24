//! A project's schema: its item types, link types and profiles, each
//! ordered by name.

const std = @import("std");

const Report = @import("../Report.zig");
pub const ItemType = @import("ItemType.zig");
pub const LinkType = @import("LinkType.zig");
pub const Profile = @import("Profile.zig");
pub const Reader = @import("Reader.zig");
pub const names = @import("names.zig");

const Schema = @This();

types: []const ItemType = &.{},
links: []const LinkType = &.{},
profiles: []const Profile = &.{},

pub fn itemType(self: *const Schema, name: []const u8) ?*const ItemType {
    for (self.types) |*t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}

pub fn linkType(self: *const Schema, name: []const u8) ?*const LinkType {
    for (self.links) |*l| {
        if (std.mem.eql(u8, l.name, name)) return l;
    }
    return null;
}

pub fn profile(self: *const Schema, name: []const u8) ?*const Profile {
    for (self.profiles) |*p| {
        if (std.mem.eql(u8, p.name, name)) return p;
    }
    return null;
}

/// Reports what the parts of the schema say about each other that is not
/// so: a link or a profile naming an item type that does not exist, a
/// profile naming a category or status no type has. `dir` is the path of
/// `.skein/`, for the file names in the report.
pub fn validate(self: *const Schema, report: *Report, dir: []const u8) std.mem.Allocator.Error!void {
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    for (self.links) |l| {
        if (!names.contains(&names.reserved, l.name)) continue;
        const file = std.mem.print(&buf, "{s}/links/{s}.toml", .{ dir, l.name }) catch dir;
        try report.add(file, 0, 0, "skein reads the key '{s}' itself, so no link type can have the name", .{l.name});
    }
    for (self.types) |t| {
        const file = std.mem.print(&buf, "{s}/types/{s}.toml", .{ dir, t.name }) catch dir;
        for (t.attributes) |a| {
            if (self.linkType(a.name) != null) try report.add(file, 0, 0, "attributes.{s}: a link type has this name, so no attribute can", .{a.name});
        }
        if (t.example) |e| if (e.link) |l| {
            if (self.linkType(l) == null) try report.add(file, 0, 0, "example.link: there is no link type '{s}'", .{l});
        };
    }
    for (self.links) |l| {
        const file = std.mem.print(&buf, "{s}/links/{s}.toml", .{ dir, l.name }) catch dir;
        if (l.counts_as != null and l.excuses != null) try report.add(file, 0, 0, "a link type counts as another or excuses from it, not both", .{});
        if (l.expected_of.profile) |p| if (self.profile(p) == null) try report.add(file, 0, 0, "expected: there is no profile '{s}'", .{p});
        for ([_]?[]const u8{ l.counts_as, l.excuses }) |other| {
            const name = other orelse continue;
            if (self.linkType(name) == null) try report.add(file, 0, 0, "there is no link type '{s}'", .{name});
        }
        for (l.from) |t| {
            if (self.itemType(t) == null) try report.add(file, 0, 0, "from: there is no item type '{s}'", .{t});
        }
        for (l.to) |t| {
            if (self.itemType(t) == null) try report.add(file, 0, 0, "to: there is no item type '{s}'", .{t});
        }
    }
    for (self.profiles) |p| {
        const file = std.mem.print(&buf, "{s}/profiles/{s}.toml", .{ dir, p.name }) catch dir;
        for (p.types) |t| {
            if (self.itemType(t) == null) try report.add(file, 0, 0, "types: there is no item type '{s}'", .{t});
        }
        for (p.categories) |c| {
            if (!self.anyType(p, c, .category)) try report.add(file, 0, 0, "categories: no item type of the profile has the category '{s}'", .{c});
        }
        for (p.statuses) |s| {
            if (!self.anyType(p, s, .status)) try report.add(file, 0, 0, "statuses: no item type of the profile has the status '{s}'", .{s});
        }
        for (p.where) |w| {
            if (!self.anyType(p, w.attribute, .attribute)) try report.add(file, 0, 0, "where: no item type of the profile has the attribute '{s}'", .{w.attribute});
        }
    }
}

/// Whether one of the item types `p` selects from has `name` as `what`
fn anyType(self: *const Schema, p: Profile, name: []const u8, what: enum { category, status, attribute }) bool {
    for (self.types) |*t| {
        if (p.types.len > 0 and !names.contains(p.types, t.name)) continue;
        const has = switch (what) {
            .category => names.contains(t.categories, name),
            .status => names.contains(t.statuses, name),
            .attribute => t.attribute(name) != null,
        };
        if (has) return true;
    }
    return false;
}

test {
    _ = ItemType;
    _ = names;
    _ = @import("_test/read.zig");
}
