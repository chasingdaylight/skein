//! `skein examples --out DIR`: each tested example, the items of a type
//! with `[example]`, written as a file of its own for the project's test
//! driver, named after its ID with its language's extension, and an index
//! of them, `examples.json`. skein runs none of them.

const std = @import("std");
const Io = std.Io;

const Example = @import("../schema/Example.zig");
const Item = @import("../graph/Item.zig");
const Json = @import("../output/Json.zig");
const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const fence = @import("../markdown.zig").fence;

pub const index_file = "examples.json";

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Examples) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();

    var out = Io.Dir.cwd().createDirPathOpen(io, options.out, .{}) catch |e|
        return misuse(arena, "cannot make '{s}' ({s})", .{ options.out, @errorName(e) });
    defer out.close(io);

    var j: Json = .{ .arena = arena };
    try j.beginArray();
    var count: usize = 0;
    for (ws.graph.items) |*item| {
        const item_type = ws.project.schema.itemType(item.type_name) orelse continue;
        const ex = item_type.example orelse continue;
        if (item.isTombstone(item_type)) continue;
        const info = fence.read(item.text) orelse continue;
        const name = try arena.print("{s}.{s}", .{ item.id, ex.extensionOf(info.language) });
        out.writeFile(io, .{ .sub_path = name, .data = info.code }) catch |e|
            return misuse(arena, "cannot write '{s}' ({s})", .{ name, @errorName(e) });
        var shows: std.ArrayList([]const u8) = .empty;
        for (item.links) |link| {
            if (ex.link == null or std.mem.eql(u8, link.type_name, ex.link.?)) try shows.append(arena, link.target);
        }
        const rejected = if (item.category) |c| std.mem.eql(u8, c, ex.rejects) else false;
        try j.beginObject();
        try j.key("id");
        try j.string(item.id);
        try j.key("file");
        try j.string(name);
        try j.key("language");
        try j.string(info.language);
        try j.key("expect");
        try j.string(if (rejected) "reject" else "accept");
        try j.key("shows");
        try j.strings(shows.items);
        try j.key("source");
        try j.string(item.file);
        try j.key("line");
        try j.integer(item.line);
        try j.key("messages");
        try j.strings(try messages(arena, item, ex));
        try j.endObject();
        count += 1;
    }
    try j.endArray();
    out.writeFile(io, .{ .sub_path = index_file, .data = try j.finish() }) catch |e|
        return misuse(arena, "cannot write '{s}' ({s})", .{ index_file, @errorName(e) });
    return .{ .text = try arena.print("skein: wrote {d} example{s} and {s} to {s}\n", .{ count, if (count == 1) "" else "s", index_file, options.out }) };
}

/// The messages the example must give: the values of the type's `message`
/// attribute, none when it has none
fn messages(arena: std.mem.Allocator, item: *const Item, ex: Example) ![]const []const u8 {
    const name = ex.message orelse return &.{};
    for (item.attributes) |a| {
        if (!std.mem.eql(u8, a.name, name)) continue;
        if (a.values.len > 0) return a.values;
        return try arena.dupe([]const u8, &.{a.value});
    }
    return &.{};
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

test {
    _ = @import("_test/examples.zig");
}
