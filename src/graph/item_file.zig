//! A file that is one item: TOML front matter, then the item's text.

const std = @import("std");

const Builder = @import("Builder.zig");
const Item = @import("Item.zig");
const markdown = @import("../markdown.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const toml = @import("../toml.zig");

/// The item that `source` (the file `file`) is; null, with the reason
/// reported, when it is none. `default_type` is the type of an item that
/// names none.
pub fn read(
    arena: std.mem.Allocator,
    schema: *const Schema,
    report: *Report,
    file: []const u8,
    source: []const u8,
    default_type: ?[]const u8,
) std.mem.Allocator.Error!?Item {
    const blocks = try markdown.scan(arena, source);
    if (blocks.len == 0 or blocks[0].kind != .front_matter) {
        // a file without front matter is no item: a readme, notes
        if (std.mem.startsWith(u8, source, "+++")) try report.add(file, 1, 1, "the front matter is not closed by a +++ line", .{});
        return null;
    }
    var diag: toml.Diagnostic = .{};
    const table = toml.parse(arena, blocks[0].text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => {
            try report.add(file, diag.line, diag.column, "{s}", .{diag.message});
            return null;
        },
    };

    const id = try stringOf(report, file, table, "id") orelse {
        try report.add(file, 1, 1, "the front matter has no id", .{});
        return null;
    };
    const type_name = try stringOf(report, file, table, "type") orelse default_type orelse {
        try report.add(file, 1, 1, "{s}: the front matter has no type, and its source gives none", .{id});
        return null;
    };
    var b: Builder = .{
        .arena = arena,
        .schema = schema,
        .report = report,
        .item = .{ .id = id, .type_name = type_name, .file = file, .line = 1, .in_document = false },
    };
    for (table.keys()) |key| {
        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "type")) continue;
        const values = try valuesOf(arena, table.get(key).?) orelse {
            try report.add(file, 1, 1, "{s}: '{s}' must be a string, a number, true or false, a date, or an array of strings", .{ id, key });
            continue;
        };
        try b.set(key, values, 0);
    }
    if (blocks.len > 1) {
        const first = blocks[1];
        const start = @intFromPtr(first.text.ptr) - @intFromPtr(source.ptr);
        const last = blocks[blocks.len - 1];
        const end = @intFromPtr(last.text.ptr) - @intFromPtr(source.ptr) + last.text.len;
        try b.addText(source[start..end], .{ .line = first.first_line });
    } else if (schema.itemType(type_name)) |item_type| {
        if (!b.item.isTombstone(item_type)) try report.add(file, 1, 1, "{s}: the item has no text", .{id});
    }
    return try b.finish();
}

fn stringOf(report: *Report, file: []const u8, table: *const toml.Table, key: []const u8) !?[]const u8 {
    const v = table.get(key) orelse return null;
    if (v == .string and v.string.len > 0) return v.string;
    try report.add(file, 1, 1, "'{s}' must be a string", .{key});
    return null;
}

/// A front matter value as the words a marker would give; null for a
/// value that has no such form
fn valuesOf(arena: std.mem.Allocator, v: toml.Value) std.mem.Allocator.Error!?[]const []const u8 {
    if (v == .array) {
        var out: std.ArrayList([]const u8) = .empty;
        for (v.array.values()) |item| {
            if (item != .string) return null;
            try out.append(arena, item.string);
        }
        return out.items;
    }
    const one = try arena.alloc([]const u8, 1);
    one[0] = switch (v) {
        .string => |s| s,
        .integer => |n| try arena.print("{d}", .{n}),
        .boolean => |b| if (b) "true" else "false",
        .datetime => |dt| blk: {
            // attributes hold dates; a time has no attribute kind
            const d = dt.date orelse return null;
            if (dt.time != null) return null;
            break :blk try arena.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day });
        },
        .float, .table, .array => return null,
    };
    return one;
}
