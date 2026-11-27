//! The templates built into skein (`templates/` of its repository): what
//! each holds, and the options it takes.

const std = @import("std");

const embedded = @import("templates");
const toml = @import("../toml.zig");

pub const File = embedded.File;

/// The names of the templates, in the order of their files
pub fn names(arena: std.mem.Allocator) std.mem.Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (embedded.files) |f| {
        for (out.items) |n| {
            if (std.mem.eql(u8, n, f.template)) break;
        } else try out.append(arena, f.template);
    }
    return out.items;
}

pub fn exists(name: []const u8) bool {
    for (embedded.files) |f| if (std.mem.eql(u8, f.template, name)) return true;
    return false;
}

/// The files of the template `name` whose paths start with `prefix`
pub fn filesOf(arena: std.mem.Allocator, name: []const u8, prefix: []const u8) std.mem.Allocator.Error![]const File {
    var out: std.ArrayList(File) = .empty;
    for (embedded.files) |f| {
        if (std.mem.eql(u8, f.template, name) and std.mem.startsWith(u8, f.path, prefix)) try out.append(arena, f);
    }
    return out.items;
}

pub const Option = struct {
    name: []const u8,
    description: []const u8 = "",
    /// the values it may take; any when empty
    values: []const []const u8 = &.{},
    /// when the project gives none; null when it must give one
    default: ?[]const u8 = null,
    /// what each value sets besides: `[options.class.sets.A]` gives the
    /// values a project of class A has (`trace_design = "true"`)
    sets: []const Sets = &.{},

    pub const Sets = struct { value: []const u8, values: []const Value };

    /// The values `value` of this option sets
    pub fn setBy(self: Option, value: []const u8) []const Value {
        for (self.sets) |s| if (std.mem.eql(u8, s.value, value)) return s.values;
        return &.{};
    }
};

pub const Info = struct {
    description: []const u8 = "",
    options: []const Option = &.{},
    /// the templates it brings along (`[[includes]]`), as the standards it
    /// defers to are part of what a project under it delivers
    includes: []const Include = &.{},
};

/// A template another brings along: always, or when its option `option`
/// has one of `values`
pub const Include = struct {
    template: []const u8,
    option: ?[]const u8 = null,
    values: []const []const u8 = &.{},
    /// why, for `skein template show`: the requirement that defers to it
    because: []const u8 = "",

    /// Whether the options `given` bring it
    pub fn applies(self: Include, given: []const Value) bool {
        const name = self.option orelse return true;
        for (given) |g| if (std.mem.eql(u8, g.name, name)) {
            for (self.values) |v| if (std.mem.eql(u8, v, g.value)) return true;
            return false;
        };
        return false;
    }
};

/// What the template's `template.toml` says of it
pub fn info(arena: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error!Info {
    const files = try filesOf(arena, name, "template.toml");
    if (files.len == 0) return .{};
    var diag: toml.Diagnostic = .{};
    const table = toml.parse(arena, files[0].data, &diag) catch return .{};
    var out: Info = .{};
    if (table.get("description")) |d| if (d == .string) {
        out.description = d.string;
    };
    if (table.get("options")) |o| if (o == .table) {
        var list: std.ArrayList(Option) = .empty;
        for (o.table.keys()) |key| {
            const t = o.table.get(key).?;
            if (t != .table) continue;
            var opt: Option = .{ .name = key };
            if (t.table.get("description")) |v| if (v == .string) {
                opt.description = v.string;
            };
            if (t.table.get("default")) |v| if (v == .string) {
                opt.default = v.string;
            };
            if (t.table.get("values")) |v| if (v == .array) {
                var values: std.ArrayList([]const u8) = .empty;
                for (v.array.values()) |s| if (s == .string) try values.append(arena, s.string);
                opt.values = values.items;
            };
            if (t.table.get("sets")) |v| if (v == .table) {
                var sets: std.ArrayList(Option.Sets) = .empty;
                for (v.table.keys()) |value| {
                    const set = v.table.get(value).?;
                    if (set != .table) continue;
                    var values: std.ArrayList(Value) = .empty;
                    for (set.table.keys()) |set_name| {
                        const s = set.table.get(set_name).?;
                        if (s == .string) try values.append(arena, .{ .name = set_name, .value = s.string });
                    }
                    try sets.append(arena, .{ .value = value, .values = values.items });
                }
                opt.sets = sets.items;
            };
            try list.append(arena, opt);
        }
        out.options = list.items;
    };
    if (table.get("includes")) |inc| if (inc == .array) {
        var list: std.ArrayList(Include) = .empty;
        for (inc.array.values()) |e| {
            if (e != .table) continue;
            const t = e.table.get("template") orelse continue;
            if (t != .string) continue;
            var one: Include = .{ .template = t.string };
            if (e.table.get("option")) |o| if (o == .string) {
                one.option = o.string;
            };
            if (e.table.get("because")) |b| if (b == .string) {
                one.because = b.string;
            };
            if (e.table.get("values")) |v| if (v == .array) {
                var values: std.ArrayList([]const u8) = .empty;
                for (v.array.values()) |s| if (s == .string) try values.append(arena, s.string);
                one.values = values.items;
            };
            try list.append(arena, one);
        }
        out.includes = list.items;
    };
    return out;
}

/// `text` with each `{{option}}` written as the value given for it
pub fn substitute(arena: std.mem.Allocator, text: []const u8, values: []const Value) std.mem.Allocator.Error![]const u8 {
    if (std.mem.find(u8, text, "{{") == null) return text;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (std.mem.findPos(u8, text, i, "{{")) |open| {
        const close = std.mem.findPos(u8, text, open, "}}") orelse break;
        try out.appendSlice(arena, text[i..open]);
        const key = std.mem.trim(u8, text[open + 2 .. close], " ");
        const value = for (values) |v| {
            if (std.mem.eql(u8, v.name, key)) break v.value;
        } else text[open .. close + 2];
        try out.appendSlice(arena, value);
        i = close + 2;
    }
    try out.appendSlice(arena, text[i..]);
    return out.items;
}

/// An option as a project gives it
pub const Value = struct { name: []const u8, value: []const u8 };

test "options are written into a template's files" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("classes = \"C\"\nkeep {{other}}", try substitute(a, "classes = \"{{ class }}\"\nkeep {{other}}", &.{.{ .name = "class", .value = "C" }}));
    try std.testing.expect(exists("langspec"));
    try std.testing.expect(!exists("nowhere"));
}

test {
    _ = @import("_test/index.zig");
}
