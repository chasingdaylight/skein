//! Attributes with several values.

// req: schema.attribute-lists
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const coverage_command = @import("../../commands/coverage.zig");
const trace_command = @import("../../commands/trace.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

test "an attribute with several values: in a marker, in front matter, in a profile" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[[sources]]\npath = \"requirements\"\nkind = \"items\"\ntype = \"swe\"\n");
    try write(tmp.dir, ".skein/types/swe.toml", "[attributes.classes]\nvalues = [\"A\", \"B\", \"C\", \"D\"]\nlist = true\n\n[attributes.authority]\n");
    try write(tmp.dir, ".skein/links/complies-with.toml", "to = [\"swe\"]\nexpected = true\n");
    try write(tmp.dir, ".skein/profiles/class-c.toml", "[where]\nclasses = \"C\"\n");
    try write(tmp.dir, "spec/npr.md",
        \\%swe[swe.one classes=A,B,C] For A to C.
        \\
        \\%swe[swe.two classes=A classes=B] For A and B, given key by key.
        \\
    );
    try write(tmp.dir, "requirements/swe.three.md", "+++\nid = \"swe.three\"\nclasses = [\"C\", \"D\"]\n+++\n\nFor C and D.\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems (3 items");
    // class C: swe.one and swe.three
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = root }, .profile = "class-c" })).text, "complies-with links to swe items: 0 of 2 (0%)\n  without:\n    swe.one\n    swe.three\n");
    try expectContains((try trace_command.run(testing.io, a, .{ .common = .{ .root = root }, .id = "swe.two" })).text, "  classes = A, B\n");
    const json = (try trace_command.run(testing.io, a, .{ .common = .{ .root = root }, .id = "swe.one", .json = true })).text;
    try expectContains(json, "\"classes\": [\n");

    // each value is held to the values the attribute allows; a single one is still one
    try write(tmp.dir, "spec/npr.md", "%swe[swe.one classes=A,E] Wrong.\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "swe.one: 'E' is not a value of 'classes'");
    try write(tmp.dir, "spec/npr.md", "%swe[swe.one authority=x,y] Wrong.\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "swe.one: 'authority' takes one value");
}
