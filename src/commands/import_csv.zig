//! `skein import csv FILE --type TYPE --to DIR`: each row of a CSV file
//! becomes an item file in DIR. For requirements that arrive from a
//! spreadsheet or a DOORS export, and for an external standard.
//!
//! The first row names the columns. The ID is the column `id` (or the
//! one `--id-column` names), the text the column `text` (or
//! `--text-column`). A column named `status`, `category` or
//! `verification`, or after a link type, is that; every other column is
//! an attribute. Empty cells are left out.
//!
//! When the project has no item type TYPE, one is made, with an
//! attribute for each such column and the ID scheme the IDs show. DIR
//! is added to the project's sources unless it is one.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");
const csv = @import("../import/csv.zig");
const write = @import("../toml/write.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Import) !Workspace.Outcome {
    const type_name = options.item_type orelse return fail(arena, "import csv: name the item type with --type", .{});
    const to = std.mem.trimEnd(u8, options.to orelse return fail(arena, "import csv: name the directory for the items with --to", .{}), "/");
    if (!Schema.names.valid(type_name)) return fail(arena, "'{s}' cannot be an item type: {s}", .{ type_name, Schema.names.rule });

    const root_path = try Project.findRoot(io, arena, options.common.root) orelse
        Io.Dir.cwd().realPathFileAlloc(io, options.common.root, arena) catch return fail(arena, "cannot find the directory '{s}'", .{options.common.root});
    var root = try Io.Dir.cwd().openDir(io, root_path, .{});
    defer root.close(io);
    var report: Report = .{ .arena = arena };
    const project = try Project.load(io, arena, root, &report);

    const file = options.paths[0];
    const text = root.readFileAlloc(io, file, arena, .limited(1 << 28)) catch return fail(arena, "cannot read '{s}'", .{file});
    const rows = csv.parse(arena, text) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnclosedQuote => return fail(arena, "{s}: a quoted field is never closed", .{file}),
    };
    if (rows.len < 2) return fail(arena, "{s}: no rows after the one that names the columns", .{file});

    // the columns
    var keys: std.ArrayList([]const u8) = .empty;
    for (rows[0]) |header| try keys.append(arena, try keyOf(arena, header));
    const id_column = columnOf(keys.items, try keyOf(arena, options.id_column orelse "id")) orelse
        return fail(arena, "{s}: there is no column '{s}' for the IDs (--id-column names another)", .{ file, options.id_column orelse "id" });
    const text_column = columnOf(keys.items, try keyOf(arena, options.text_column orelse "text")) orelse
        return fail(arena, "{s}: there is no column '{s}' for the text (--text-column names another)", .{ file, options.text_column orelse "text" });
    for (keys.items, 0..) |key, i| {
        if (i == id_column or i == text_column) continue;
        if (key.len == 0) return fail(arena, "{s}: column {d} has no name", .{ file, i + 1 });
        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "type")) {
            return fail(arena, "{s}: a column cannot be called '{s}'; skein reads that key itself", .{ file, key });
        }
        if (columnOf(keys.items[0..i], key) != null) return fail(arena, "{s}: two columns are called '{s}'", .{ file, key });
    }

    // every row must be an item before anything is written
    var ids: std.ArrayList([]const u8) = .empty;
    for (rows[1..], 2..) |row, line| {
        const id = if (id_column < row.len) std.mem.trim(u8, row[id_column], " \t") else "";
        if (id.len == 0) return fail(arena, "{s}: row {d} has no ID", .{ file, line });
        for (id) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '-' and c != '_') return fail(arena, "{s}: row {d}: '{s}' cannot be an ID: letters, digits, '.', '-' and '_'", .{ file, line, id });
        }
        if (Schema.names.contains(ids.items, id)) return fail(arena, "{s}: row {d}: the ID '{s}' is in the file twice", .{ file, line, id });
        try ids.append(arena, id);
    }
    var dir = root.createDirPathOpen(io, to, .{}) catch return fail(arena, "cannot make the directory '{s}'", .{to});
    defer dir.close(io);
    if (!options.replace) for (ids.items) |id| {
        const name = try arena.print("{s}.md", .{id});
        if (dir.access(io, name, .{})) |_| return fail(arena, "{s}/{s} is there already (--replace writes over it)", .{ to, name }) else |_| {}
    };

    // the item type, when the project has none of the name
    if (project.schema.itemType(type_name) == null) {
        const scheme = schemeOf(arena, ids.items) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NoScheme => return fail(arena, "the IDs follow no one scheme (like SRS-012, or like lex.comment.line); make the item type '{s}' first", .{type_name}),
        };
        var type_text: std.ArrayList(u8) = .empty;
        try type_text.appendSlice(arena, scheme);
        for (keys.items, 0..) |key, i| {
            if (i == id_column or i == text_column) continue;
            if (Schema.names.contains(&Schema.names.reserved, key) or project.schema.linkType(key) != null) continue;
            try type_text.print(arena, "\n[attributes.{s}]\n", .{key});
        }
        try root.createDirPath(io, Project.dir_name ++ "/types");
        try root.writeFile(io, .{ .sub_path = try arena.print("{s}/types/{s}.toml", .{ Project.dir_name, type_name }), .data = type_text.items });
    }

    // the items
    for (rows[1..], ids.items) |row, id| {
        var out: std.ArrayList(u8) = .empty;
        try out.print(arena, "+++\nid = {s}\n", .{try write.string(arena, id)});
        for (keys.items, 0..) |key, i| {
            if (i == id_column or i == text_column or i >= row.len) continue;
            const value = std.mem.trim(u8, row[i], " \t\n");
            if (value.len == 0) continue;
            if (project.schema.linkType(key) != null) {
                var targets: std.ArrayList([]const u8) = .empty;
                var parts = std.mem.tokenizeAny(u8, value, ",; \t\n");
                while (parts.next()) |target| try targets.append(arena, target);
                try out.print(arena, "{s} = {s}\n", .{ key, try write.strings(arena, targets.items) });
            } else try out.print(arena, "{s} = {s}\n", .{ key, try write.string(arena, value) });
        }
        const body = if (text_column < row.len) std.mem.trim(u8, row[text_column], " \t\n") else "";
        try out.print(arena, "+++\n\n{s}\n", .{body});
        try dir.writeFile(io, .{ .sub_path = try arena.print("{s}.md", .{id}), .data = out.items });
    }

    // the source
    const is_source = for (project.sources) |source| {
        if (std.mem.eql(u8, source.path, to)) break true;
    } else false;
    if (!is_source) {
        const before = root.readFileAlloc(io, Project.config_file, arena, .limited(1 << 24)) catch "";
        const gap: []const u8 = if (before.len == 0 or std.mem.endsWith(u8, before, "\n\n")) "" else if (std.mem.endsWith(u8, before, "\n")) "\n" else "\n\n";
        try root.createDirPath(io, Project.dir_name);
        try root.writeFile(io, .{
            .sub_path = Project.config_file,
            .data = try arena.print("{s}{s}[[sources]]\npath = \"{s}\"\nkind = \"items\"\ntype = \"{s}\"\n", .{ before, gap, to, type_name }),
        });
    }
    const n = ids.items.len;
    return .{ .text = try arena.print("skein: imported {d} item{s} of type {s} into {s}\n       Run 'skein check'.\n", .{ n, if (n == 1) "" else "s", type_name, to }) };
}

fn fail(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

/// A column's name as a key: lowercase, with '-' for what a name cannot hold
fn keyOf(arena: std.mem.Allocator, header: []const u8) ![]const u8 {
    const key = try std.ascii.allocLowerString(arena, std.mem.trim(u8, header, " \t"));
    for (key) |*c| {
        if (!std.ascii.isLower(c.*) and !std.ascii.isDigit(c.*) and c.* != '_') c.* = '-';
    }
    return key;
}

fn columnOf(keys: []const []const u8, key: []const u8) ?usize {
    for (keys, 0..) |k, i| {
        if (std.mem.eql(u8, k, key)) return i;
    }
    return null;
}

/// The lines of an item type that say how `ids` are spelled: numbered
/// (one prefix and separator, then digits) or hierarchical
fn schemeOf(arena: std.mem.Allocator, ids: []const []const u8) ![]const u8 {
    var prefix: []const u8 = "";
    var separator: []const u8 = "";
    var digits: usize = std.math.maxInt(usize);
    const numbered = for (ids, 0..) |id, i| {
        var letters: usize = 0;
        while (letters < id.len and std.ascii.isAlphabetic(id[letters])) letters += 1;
        var number = letters;
        if (number < id.len and (id[number] == '-' or id[number] == '_')) number += 1;
        const rest = id[number..];
        if (letters == 0 or rest.len == 0) break false;
        for (rest) |c| {
            if (!std.ascii.isDigit(c)) break;
        } else {
            if (i == 0) {
                prefix = id[0..letters];
                separator = id[letters..number];
            } else if (!std.mem.eql(u8, prefix, id[0..letters]) or !std.mem.eql(u8, separator, id[letters..number])) break false;
            digits = @min(digits, rest.len);
            continue;
        }
        break false;
    } else true;
    if (numbered) {
        return arena.print("id = \"numbered\"\nprefix = {s}\ndigits = {d}\nseparator = {s}\n", .{ try write.string(arena, prefix), @min(digits, 9), try write.string(arena, separator) });
    }
    const hierarchical: Schema.ItemType = .{ .name = "x" };
    for (ids) |id| {
        if (!hierarchical.idMatches(id)) return error.NoScheme;
    }
    return "";
}

test {
    _ = csv;
    _ = @import("_test/import_csv.zig");
}
