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
    /// the template that brings it along (`[[includes]]`); null for one the
    /// project names
    brought_by: ?[]const u8 = null,
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
        if (try build(r, n.name, n.given, null)) |use| try out.append(r.arena, use);
    }
    // the templates they bring along (`[[includes]]`), each with the options of
    // the same names as the template that brings it; the ones a project names
    // itself keep its options
    var i: usize = 0;
    while (i < out.items.len) : (i += 1) {
        const use = out.items[i];
        const info = try Template.info(r.arena, use.name);
        for (info.includes) |inc| {
            if (!inc.applies(use.options)) continue;
            const present = for (out.items) |u| {
                if (std.mem.eql(u8, u.name, inc.template)) break true;
            } else false;
            if (present) continue;
            const wanted = try Template.info(r.arena, inc.template);
            var given: std.ArrayList(Template.Value) = .empty;
            for (wanted.options) |o| for (use.options) |val| if (std.mem.eql(u8, val.name, o.name)) {
                try given.append(r.arena, val);
                break;
            };
            if (try build(r, inc.template, given.items, use.name)) |b| try out.append(r.arena, b);
        }
    }
    return out.items;
}

/// The template `name` with the options `given`, checked against what it
/// declares, its defaults and what its values set; null, with the mistakes
/// reported, when they do not fit. `by` is the template that brings it.
fn build(r: Reader, name: []const u8, given: []const Template.Value, by: ?[]const u8) Reader.Error!?Use {
    if (!Template.exists(name)) {
        try r.complain("template", "skein has no template '{s}' ('skein template list' names them)", .{name});
        return null;
    }
    const info = try Template.info(r.arena, name);
    var options: std.ArrayList(Template.Value) = .empty;
    var ok = true;
    for (given) |g| {
        const declared = for (info.options) |o| {
            if (std.mem.eql(u8, o.name, g.name)) break o;
        } else {
            try r.complain("template", "the template '{s}' has no option '{s}'", .{ name, g.name });
            ok = false;
            continue;
        };
        if (declared.values.len > 0 and !contains(declared.values, g.value)) {
            try r.complain("template", "'{s}' is not a value of the option '{s}' of '{s}': {s}", .{ g.value, g.name, name, try std.mem.join(r.arena, ", ", declared.values) });
            ok = false;
        }
        try options.append(r.arena, g);
    }
    for (info.options) |o| {
        const is_given = for (given) |g| {
            if (std.mem.eql(u8, g.name, o.name)) break true;
        } else false;
        if (is_given) continue;
        if (o.default) |d| try options.append(r.arena, .{ .name = o.name, .value = d }) else {
            if (by) |b| {
                try r.complain("template", "the template '{s}', which '{s}' brings along, needs the option '{s}': {s}; give it in [template.\"{s}\"]", .{ name, b, o.name, o.description, name });
            } else try r.complain("template", "the template '{s}' needs the option '{s}': {s}", .{ name, o.name, o.description });
            ok = false;
        }
    }
    // what the values chosen set besides
    const chosen = options.items.len;
    for (0..chosen) |i| {
        const g = options.items[i];
        const declared = for (info.options) |o| {
            if (std.mem.eql(u8, o.name, g.name)) break o;
        } else continue;
        try options.appendSlice(r.arena, declared.setBy(g.value));
    }
    if (!ok) return null;
    return .{ .name = name, .options = options.items, .brought_by = by };
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, s)) return true;
    return false;
}
