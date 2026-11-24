//! `skein link FROM TYPE TO`: adds a link of a type from one item to
//! another, in the marker or the front matter of FROM, refusing what
//! `check` would report.

const std = @import("std");
const Io = std.Io;

const Marker = @import("../markdown/Marker.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Link) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    const schema = &ws.project.schema;

    const item = ws.graph.find(options.from) orelse return misuse(arena, "there is no item '{s}'", .{options.from});
    const link_type = schema.linkType(options.type_name) orelse return misuse(arena, "there is no link type '{s}'", .{options.type_name});
    if (link_type.from.len > 0 and !Schema.names.contains(link_type.from, item.type_name)) {
        return misuse(arena, "a '{s}' cannot have a '{s}' link", .{ item.type_name, link_type.name });
    }
    // an item of another repository is not checked, as `check` does not
    if (std.mem.findScalar(u8, options.to, ':') == null) {
        const target = ws.graph.find(options.to) orelse return misuse(arena, "there is no item '{s}'", .{options.to});
        if (std.mem.eql(u8, target.id, item.id)) return misuse(arena, "an item cannot link to itself", .{});
        if (link_type.to.len > 0 and !Schema.names.contains(link_type.to, target.type_name)) {
            return misuse(arena, "'{s}' is a '{s}', which a '{s}' link cannot point to", .{ target.id, target.type_name, link_type.name });
        }
        if (schema.itemType(target.type_name)) |t| {
            if (target.isTombstone(t)) return misuse(arena, "'{s}' is removed", .{target.id});
        }
    }
    for (item.links) |l| {
        if (std.mem.eql(u8, l.type_name, link_type.name) and std.mem.eql(u8, l.target, options.to)) {
            return misuse(arena, "{s} has this link already", .{item.id});
        }
    }

    if (ws.project.readOnlySource(item.file)) |s| return misuse(arena, "{s} is in the read-only source '{s}'", .{ item.id, s.path });
    const text = try ws.root.readFileAlloc(io, item.file, arena, .limited(1 << 26));
    const edited = (if (item.in_document)
        try inMarker(arena, text, item.line, link_type.name, options.to)
    else
        try inFrontMatter(arena, text, link_type.name, options.to)) orelse
        return misuse(arena, "{s}: the {s} links are written in a way skein does not change; add the link by hand", .{ item.file, link_type.name });
    try ws.root.writeFile(io, .{ .sub_path = item.file, .data = edited });
    return .{ .text = try arena.print("skein: {s} {s} {s}\n", .{ item.id, link_type.name, options.to }) };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

/// `text` with the link added to the marker on line `number` (1-based):
/// to the values of the key when it has some, else as a new `key=value`
/// before the closing bracket
fn inMarker(arena: std.mem.Allocator, text: []const u8, number: u32, key: []const u8, target: []const u8) !?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: u32 = 1;
    var done = false;
    while (lines.next()) |line| : (n += 1) {
        if (n > 1) try out.append(arena, '\n');
        if (n != number) {
            try out.appendSlice(arena, line);
            continue;
        }
        const start = Marker.startIn(line) orelse return null;
        const end = start + Marker.extent(line[start..]);
        if (end == 0 or line[end - 1] != ']') return null;
        const marker = line[start..end];
        const field = try arena.print(" {s}=", .{key});
        if (std.mem.find(u8, marker, field)) |at| {
            var value_end = at + field.len;
            while (value_end < marker.len - 1 and marker[value_end] != ' ') value_end += 1;
            try out.print(arena, "{s}{s},{s}{s}", .{ line[0 .. start + value_end], "", target, line[start + value_end ..] });
        } else {
            try out.print(arena, "{s}{s}{s}{s}", .{ line[0 .. end - 1], field, target, line[end - 1 ..] });
        }
        done = true;
    }
    return if (done) out.items else null;
}

/// `text`, an item file, with the link added to its front matter: to the
/// key's array or string when it is on one line, else as a new key after
/// the ID, where it cannot fall into a table
fn inFrontMatter(arena: std.mem.Allocator, text: []const u8, key: []const u8, target: []const u8) !?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: usize = 0;
    var in_front = false;
    var added = false;
    var id_line: ?usize = null;
    var kept: std.ArrayList([]const u8) = .empty;
    while (lines.next()) |line| : (n += 1) {
        const bare = std.mem.trimEnd(u8, line, " \t\r");
        const cr = if (std.mem.endsWith(u8, line, "\r")) "\r" else "";
        if (n == 0) {
            if (!std.mem.eql(u8, bare, "+++")) return null;
            in_front = true;
            try kept.append(arena, line);
            continue;
        }
        if (in_front and std.mem.eql(u8, bare, "+++")) in_front = false;
        if (in_front and !added) {
            if (std.mem.startsWith(u8, std.mem.trimStart(u8, bare, " \t"), "id ") or std.mem.startsWith(u8, std.mem.trimStart(u8, bare, " \t"), "id=")) id_line = kept.items.len;
            if (keyOf(bare)) |k| if (std.mem.eql(u8, k, key)) {
                const value = std.mem.trim(u8, bare[std.mem.findScalar(u8, bare, '=').? + 1 ..], " \t");
                const prefix = bare[0 .. std.mem.findScalar(u8, bare, '=').? + 1];
                if (value.len >= 2 and value[0] == '[' and value[value.len - 1] == ']') {
                    const inner = std.mem.trim(u8, value[1 .. value.len - 1], " \t");
                    const joined = if (inner.len == 0) try arena.print("\"{s}\"", .{target}) else try arena.print("{s}, \"{s}\"", .{ inner, target });
                    try kept.append(arena, try arena.print("{s} [{s}]{s}", .{ prefix, joined, cr }));
                } else if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                    try kept.append(arena, try arena.print("{s} [{s}, \"{s}\"]{s}", .{ prefix, value, target, cr }));
                } else return null;
                added = true;
                continue;
            };
        }
        try kept.append(arena, line);
    }
    if (!added) {
        const at = id_line orelse return null;
        const cr = if (std.mem.endsWith(u8, kept.items[at], "\r")) "\r" else "";
        try kept.insert(arena, at + 1, try arena.print("{s} = [\"{s}\"]{s}", .{ key, target, cr }));
    }
    for (kept.items, 0..) |line, i| {
        if (i > 0) try out.append(arena, '\n');
        try out.appendSlice(arena, line);
    }
    return out.items;
}

/// The key of a line `key = value` of TOML, without quotes
fn keyOf(line: []const u8) ?[]const u8 {
    const eq = std.mem.findScalar(u8, line, '=') orelse return null;
    const key = std.mem.trim(u8, line[0..eq], " \t");
    if (key.len == 0 or key[0] == '[' or key[0] == '#') return null;
    return std.mem.trim(u8, key, "\"");
}

test {
    _ = @import("_test/link.zig");
}
