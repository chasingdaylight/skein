//! `skein new TYPE [ID]`: a new item of a type. A numbered type gives it
//! the next free number; a hierarchical one needs the ID. Where the type
//! has a source of item files, the item's file is written there, with
//! its front matter and no text yet. Otherwise the marker to start the
//! paragraph or list entry with is printed.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Project = @import("../Project.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.New) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();

    const item_type = ws.project.schema.itemType(options.type_name) orelse return misuse(arena, "there is no item type '{s}'", .{options.type_name});
    const id = if (options.id) |given| given else switch (item_type.id) {
        .numbered => |n| try nextFree(arena, &ws, item_type.name, n),
        .hierarchical => return misuse(arena, "a '{s}' has IDs joined by dots: name the new one (skein new {s} ID)", .{ item_type.name, item_type.name }),
    };
    if (!item_type.idMatches(id)) return misuse(arena, "'{s}' is not spelled as the IDs of a '{s}' are", .{ id, item_type.name });
    if (ws.graph.find(id) != null) return misuse(arena, "the ID '{s}' is taken", .{id});

    const source = switch (try sourceFor(arena, &ws.project, item_type.name, options.to)) {
        .found => |s| s,
        .none => return .{ .text = try arena.print("%{s}[{s}]\n", .{ item_type.name, id }) },
        .refused => |why| return .{ .text = why, .status = .misuse },
    };
    if (source.read_only) return misuse(arena, "'{s}' is a read-only source", .{source.path});
    const file = try arena.print("{s}/{s}.md", .{ source.path, id });
    var front: std.ArrayList(u8) = .empty;
    try front.print(arena, "+++\nid = \"{s}\"\n", .{id});
    // a source that gives the type needs it not repeated
    if (source.item_type == null or !std.mem.eql(u8, source.item_type.?, item_type.name)) try front.print(arena, "type = \"{s}\"\n", .{item_type.name});
    try front.appendSlice(arena, "+++\n\n");
    if (ws.root.access(io, file, .{})) |_| return misuse(arena, "there is a file '{s}' already", .{file}) else |_| {}
    try ws.root.createDirPath(io, source.path);
    try ws.root.writeFile(io, .{ .sub_path = file, .data = front.items });
    return .{ .text = try arena.print("{s}\n", .{file}) };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

/// The next number of a numbered type: one more than the highest used,
/// removed items included, with at least the type's digits
fn nextFree(arena: std.mem.Allocator, ws: *const Workspace, type_name: []const u8, n: Schema.ItemType.IdScheme.Numbered) ![]const u8 {
    var highest: u64 = 0;
    for (ws.graph.items) |item| {
        if (!std.mem.eql(u8, item.type_name, type_name)) continue;
        const head = n.prefix.len + n.separator.len;
        if (item.id.len <= head) continue;
        const number = std.fmt.parseInt(u64, item.id[head..], 10) catch continue;
        highest = @max(highest, number);
    }
    const digits = try arena.print("{d}", .{highest + 1});
    const padding = if (digits.len < n.digits) n.digits - digits.len else 0;
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "{s}{s}", .{ n.prefix, n.separator });
    try out.appendNTimes(arena, '0', padding);
    try out.appendSlice(arena, digits);
    return out.items;
}

const Source = union(enum) {
    found: Project.Source,
    /// the type is written in documents
    none,
    /// a message for standard error
    refused: []const u8,
};

/// The source of item files the new item goes to: the one `to` names,
/// else the one source of item files of the type
fn sourceFor(arena: std.mem.Allocator, project: *const Project, type_name: []const u8, to: ?[]const u8) !Source {
    if (to) |dir| {
        for (project.sources) |s| {
            if (s.kind == .items and std.mem.eql(u8, s.path, dir)) return .{ .found = s };
        }
        return .{ .refused = try arena.print("skein: '{s}' is not a source of item files in .skein/config.toml\n", .{dir}) };
    }
    var found: ?Project.Source = null;
    for (project.sources) |s| {
        if (s.kind != .items) continue;
        const t = s.item_type orelse continue;
        if (!std.mem.eql(u8, t, type_name)) continue;
        if (found != null) return .{ .refused = try arena.print("skein: a '{s}' has more than one source of item files: say which, with --to DIR\n", .{type_name}) };
        found = s;
    }
    return if (found) |s| .{ .found = s } else .none;
}

test {
    _ = @import("_test/new.zig");
}
