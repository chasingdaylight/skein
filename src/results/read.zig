//! Reading results files: TOML (`[[result]]` tables), JSON (an array of
//! objects, or an object with a `result` array) and YAML (a `result:` list
//! of mappings, or a list), told apart by the extension. Each result is
//! read into its fields, by name, whatever the format.

const std = @import("std");

const toml = @import("../toml.zig");
const yaml = @import("../import/doorstop/yaml.zig");

pub const Error = error{ BadResults, UnknownFormat } || std.mem.Allocator.Error;

/// One result as written: its fields as text, and its lists (`items`,
/// `fingerprints`) as lists
pub const Record = struct {
    fields: std.array_hash_map.String([]const u8) = .empty,
    lists: std.array_hash_map.String([]const []const u8) = .empty,

    pub fn get(self: *const Record, key: []const u8) ?[]const u8 {
        return self.fields.get(key);
    }

    /// The list `key`; empty when there is none
    pub fn list(self: *const Record, key: []const u8) []const []const u8 {
        return self.lists.get(key) orelse &.{};
    }
};

pub const Format = enum { toml, json, yaml };

/// The format of the file `path`, by its extension
pub fn formatOf(path: []const u8) ?Format {
    if (std.ascii.endsWithIgnoreCase(path, ".toml")) return .toml;
    if (std.ascii.endsWithIgnoreCase(path, ".json")) return .json;
    if (std.ascii.endsWithIgnoreCase(path, ".yaml") or std.ascii.endsWithIgnoreCase(path, ".yml")) return .yaml;
    return null;
}

/// The results in `text`, a file of `format`. `why` says what is wrong
/// on `error.BadResults`.
pub fn records(arena: std.mem.Allocator, format: Format, text: []const u8, why: *[]const u8) Error![]const Record {
    return switch (format) {
        .toml => fromToml(arena, text, why),
        .json => fromJson(arena, text, why),
        .yaml => fromYaml(arena, text, why),
    };
}

fn fromToml(arena: std.mem.Allocator, text: []const u8, why: *[]const u8) Error![]const Record {
    var diag: toml.Diagnostic = .{};
    const table = toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => {
            why.* = try arena.print("{d}:{d}: {s}", .{ diag.line, diag.column, diag.message });
            return error.BadResults;
        },
    };
    const list = table.get("result") orelse return &.{};
    if (list != .array) return bad(why, "'result' is not an array of tables ([[result]])");
    var out: std.ArrayList(Record) = .empty;
    for (list.array.values()) |v| {
        if (v != .table) return bad(why, "'result' is not an array of tables ([[result]])");
        var r: Record = .{};
        for (v.table.keys()) |k| {
            const value = v.table.get(k).?;
            if (value == .array) {
                try r.lists.put(arena, k, try tomlStrings(arena, value) orelse return bad(why, "a list of a result is not an array of strings"));
                continue;
            }
            try r.fields.put(arena, k, try tomlText(arena, value) orelse return bad(why, "a field of a result is not a string, a number, a boolean or a date"));
        }
        try out.append(arena, r);
    }
    return out.items;
}

fn tomlText(arena: std.mem.Allocator, v: toml.Value) Error!?[]const u8 {
    return switch (v) {
        .string => |s| s,
        .integer => |i| try arena.print("{d}", .{i}),
        .boolean => |b| if (b) "true" else "false",
        .datetime => |dt| if (dt.date) |d| try arena.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day }) else null,
        else => null,
    };
}

fn tomlStrings(arena: std.mem.Allocator, v: toml.Value) Error!?[]const []const u8 {
    if (v != .array) return null;
    var out: std.ArrayList([]const u8) = .empty;
    for (v.array.values()) |s| {
        if (s != .string) return null;
        try out.append(arena, s.string);
    }
    return out.items;
}

fn fromJson(arena: std.mem.Allocator, text: []const u8, why: *[]const u8) Error![]const Record {
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{}) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return bad(why, "this is not JSON"),
    };
    const list = switch (root) {
        .array => |a| a.items,
        .object => |o| if (o.get("result")) |r| (if (r == .array) r.array.items else return bad(why, "'result' is not an array")) else return &.{},
        else => return bad(why, "expected an array of results, or an object with a 'result' array"),
    };
    var out: std.ArrayList(Record) = .empty;
    for (list) |v| {
        if (v != .object) return bad(why, "a result is not an object");
        var r: Record = .{};
        var it = v.object.iterator();
        while (it.next()) |e| {
            const k = e.key_ptr.*;
            if (e.value_ptr.* == .array) {
                var items: std.ArrayList([]const u8) = .empty;
                for (e.value_ptr.array.items) |s| {
                    if (s != .string) return bad(why, "a list of a result is not an array of strings");
                    try items.append(arena, s.string);
                }
                try r.lists.put(arena, k, items.items);
                continue;
            }
            const value: []const u8 = switch (e.value_ptr.*) {
                .string => |s| s,
                .integer => |i| try arena.print("{d}", .{i}),
                .bool => |b| if (b) "true" else "false",
                .number_string => |s| s,
                else => return bad(why, "a field of a result is not a string, a number or a boolean"),
            };
            try r.fields.put(arena, k, value);
        }
        try out.append(arena, r);
    }
    return out.items;
}

fn fromYaml(arena: std.mem.Allocator, text: []const u8, why: *[]const u8) Error![]const Record {
    var line: u32 = 0;
    const root = yaml.parse(arena, text, &line) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedYaml => {
            why.* = try arena.print("{d}: YAML that skein does not read", .{line});
            return error.BadResults;
        },
    };
    const list = switch (root) {
        .list => |l| l,
        .map => if (root.get("result")) |r| (if (r == .list) r.list else return bad(why, "'result' is not a list")) else return &.{},
        .scalar => |s| if (s.len == 0) return &.{} else return bad(why, "expected a list of results, or a mapping with a 'result' list"),
    };
    var out: std.ArrayList(Record) = .empty;
    for (list) |v| {
        if (v != .map) return bad(why, "a result is not a mapping");
        var r: Record = .{};
        for (v.map) |e| {
            if (e.value == .list) {
                var items: std.ArrayList([]const u8) = .empty;
                for (e.value.list) |s| {
                    if (s != .scalar) return bad(why, "a list of a result is not a list of single values");
                    try items.append(arena, s.scalar);
                }
                try r.lists.put(arena, e.key, items.items);
                continue;
            }
            if (e.value != .scalar) return bad(why, "a field of a result is not a single value");
            try r.fields.put(arena, e.key, e.value.scalar);
        }
        try out.append(arena, r);
    }
    return out.items;
}

fn bad(why: *[]const u8, message: []const u8) error{BadResults} {
    why.* = message;
    return error.BadResults;
}

// req: results.formats
test "the same results in TOML, JSON and YAML" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var why: []const u8 = "";
    const texts = [_]struct { Format, []const u8 }{
        .{ .toml, "[[result]]\ntest = \"lexer: line comment\"\nfile = \"tests/lex.zig\"\nresult = \"pass\"\n\n[[result]]\nitem = \"tp.one\"\nresult = \"fail\"\ndate = 2026-11-21\nitems = [\"a\", \"b\"]\n" },
        .{ .json, "[{\"test\": \"lexer: line comment\", \"file\": \"tests/lex.zig\", \"result\": \"pass\"}, {\"item\": \"tp.one\", \"result\": \"fail\", \"date\": \"2026-11-21\", \"items\": [\"a\", \"b\"]}]" },
        .{ .yaml, "result:\n  - test: \"lexer: line comment\"\n    file: tests/lex.zig\n    result: pass\n  - item: tp.one\n    result: fail\n    date: 2026-11-21\n    items:\n      - a\n      - b\n" },
    };
    for (texts) |t| {
        const rs = try records(a, t[0], t[1], &why);
        try std.testing.expectEqual(2, rs.len);
        try std.testing.expectEqualStrings("lexer: line comment", rs[0].get("test").?);
        try std.testing.expectEqualStrings("tests/lex.zig", rs[0].get("file").?);
        try std.testing.expectEqualStrings("fail", rs[1].get("result").?);
        try std.testing.expectEqualStrings("2026-11-21", rs[1].get("date").?);
        try std.testing.expectEqualStrings("b", rs[1].list("items")[1]);
    }
    try std.testing.expectError(error.BadResults, records(a, .json, "{\"result\": 3}", &why));
    try std.testing.expectEqual(.yaml, formatOf("run.yml").?);
    try std.testing.expectEqual(null, formatOf("run.xml"));
}
