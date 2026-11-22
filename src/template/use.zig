//! The templates a project uses, as `template` in `.skein/config.toml`
//! names them:
//!
//!     template = "langspec"
//!     template = ["langspec", "npr7150.2d"]
//!
//!     [template.npr]
//!     name = "npr7150.2d"
//!     class = "C"
//!
//! The table form gives a template's options; its key names it when it
//! gives no `name`.

const std = @import("std");

const Reader = @import("../schema/Reader.zig");
const Template = @import("Template.zig");

pub const Use = struct {
    name: []const u8,
    /// every option of the template, given or by default
    options: []const Template.Value = &.{},
};

/// The templates `r`, the configuration's root table, names, with their
/// options checked against what the templates declare. Mistakes are
/// reported, and those templates left out.
pub fn readAll(r: Reader) Reader.Error![]const Use {
    const v = r.table.get("template") orelse return &.{};
    var named: std.ArrayList(struct { name: []const u8, given: []const Template.Value }) = .empty;
    switch (v) {
        .string => |s| try named.append(r.arena, .{ .name = s, .given = &.{} }),
        .array => for (try r.strings("template")) |s| try named.append(r.arena, .{ .name = s, .given = &.{} }),
        .table => {
            const t = (try r.child("template")).?;
            for (t.table.keys()) |key| {
                const entry = t.table.get(key).?;
                if (entry != .table) {
                    try t.complain(key, "a template is a table with its name and its options", .{});
                    continue;
                }
                var given: std.ArrayList(Template.Value) = .empty;
                var name: []const u8 = key;
                for (entry.table.keys()) |option| {
                    const value: []const u8 = switch (entry.table.get(option).?) {
                        .string => |s| s,
                        .boolean => |b| if (b) "true" else "false",
                        .integer => |i| try r.arena.print("{d}", .{i}),
                        else => {
                            try t.complain(key, "the option '{s}' is to be a string, a number or true or false", .{option});
                            continue;
                        },
                    };
                    if (std.mem.eql(u8, option, "name")) name = value else try given.append(r.arena, .{ .name = option, .value = value });
                }
                try named.append(r.arena, .{ .name = name, .given = given.items });
            }
        },
        else => {
            try r.complain("template", "expected a name, a list of names, or tables of templates", .{});
            return &.{};
        },
    }

    var out: std.ArrayList(Use) = .empty;
    for (named.items) |n| {
        if (!Template.exists(n.name)) {
            try r.complain("template", "skein has no template '{s}' ('skein template list' names them)", .{n.name});
            continue;
        }
        const info = try Template.info(r.arena, n.name);
        var options: std.ArrayList(Template.Value) = .empty;
        var ok = true;
        for (n.given) |g| {
            const declared = for (info.options) |o| {
                if (std.mem.eql(u8, o.name, g.name)) break o;
            } else {
                try r.complain("template", "the template '{s}' has no option '{s}'", .{ n.name, g.name });
                ok = false;
                continue;
            };
            if (declared.values.len > 0 and !contains(declared.values, g.value)) {
                try r.complain("template", "'{s}' is not a value of the option '{s}' of '{s}': {s}", .{ g.value, g.name, n.name, try std.mem.join(r.arena, ", ", declared.values) });
                ok = false;
            }
            try options.append(r.arena, g);
        }
        for (info.options) |o| {
            const given = for (n.given) |g| {
                if (std.mem.eql(u8, g.name, o.name)) break true;
            } else false;
            if (given) continue;
            if (o.default) |d| try options.append(r.arena, .{ .name = o.name, .value = d }) else {
                try r.complain("template", "the template '{s}' needs the option '{s}': {s}", .{ n.name, o.name, o.description });
                ok = false;
            }
        }
        // what the values chosen set besides
        const chosen = options.items.len;
        for (0..chosen) |i| {
            const given = options.items[i];
            const declared = for (info.options) |o| {
                if (std.mem.eql(u8, o.name, given.name)) break o;
            } else continue;
            try options.appendSlice(r.arena, declared.setBy(given.value));
        }
        if (ok) try out.append(r.arena, .{ .name = n.name, .options = options.items });
    }
    return out.items;
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, s)) return true;
    return false;
}
