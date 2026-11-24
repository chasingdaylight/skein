//! A read-only source: the editing commands leave it alone.

// req: standards.read-only
const std = @import("std");
const testing = std.testing;

const check_command = @import("../check.zig");
const link_command = @import("../link.zig");
const move_command = @import("../move.zig");
const new_command = @import("../new.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

test "move, link and new refuse to change a read-only source; check reads it as any other" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[project]\nname = \"example\"\n[[sources]]\npath = \"standard\"\nkind = \"items\"\ntype = \"std\"\nread_only = true\n[[sources]]\npath = \"spec\"\n");
    try write(dir, ".skein/types/std.toml", "id = \"numbered\"\nprefix = \"STD\"\n");
    try write(dir, ".skein/types/rule.toml", "");
    try write(dir, ".skein/links/complies-with.toml", "from = [\"rule\"]\nto = [\"std\"]\n");
    try write(dir, ".skein/links/see.toml", "");
    try write(dir, "standard/STD-001.md", "+++\nid = \"STD-001\"\n+++\n\nThe software shall be tested; see %[STD-002].\n");
    try write(dir, "standard/STD-002.md", "+++\nid = \"STD-002\"\n+++\n\nTests shall be kept.\n");
    try write(dir, "spec/lex.md", "%rule[lex.a complies-with=STD-001] A.\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const common: @import("../../cli.zig").Common = .{ .root = root };

    try testing.expectEqualStrings("skein: example: no problems (3 items of 2 types, 2 link types, 0 profiles, 0 citations)\n", (try check_command.run(testing.io, a, common)).text);
    // a rename of an item that the standard refers to would change the standard
    try testing.expectEqualStrings("skein: the rename would change standard/STD-001.md, which is in the read-only source 'standard'\n", (try move_command.run(testing.io, a, .{ .common = common, .old = "STD-002", .new = "STD-020" })).text);
    try testing.expectEqualStrings("skein: STD-001 is in the read-only source 'standard'\n", (try link_command.run(testing.io, a, .{ .common = common, .from = "STD-001", .type_name = "see", .to = "STD-002" })).text);
    try testing.expectEqualStrings("skein: 'standard' is a read-only source\n", (try new_command.run(testing.io, a, .{ .common = common, .type_name = "std" })).text);
    // the project's own items are still edited, and their links to the standard
    try testing.expectEqualStrings("skein: lex.a is now lex.b: 1 place in 1 file\n", (try move_command.run(testing.io, a, .{ .common = common, .old = "lex.a", .new = "lex.b" })).text);
    try testing.expectEqualStrings("skein: lex.b complies-with STD-002\n", (try link_command.run(testing.io, a, .{ .common = common, .from = "lex.b", .type_name = "complies-with", .to = "STD-002" })).text);
}
