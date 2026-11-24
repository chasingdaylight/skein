//! What coding agents are told of skein: the section `skein agents` and
//! `skein init` write into the agent instructions, and the skill file.

// req: agents.instructions
const std = @import("std");
const testing = std.testing;

const agents = @import("../agents.zig");
const init_command = @import("../init.zig");
const instructions = @import("../../agents/instructions.zig");

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

test "skein agents: a section of CLAUDE.md, written again in place, and a skill file" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[[citations]]\nname = \"test\"\npath = \"tests\"\nfiles = [\".zig\"]\nmarker = \"// spec:\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "description = \"A rule of the language\"\ncategories = [\"syntax\"]\n");
    try write(tmp.dir, ".skein/links/verifies.toml", "to = [\"rule\"]\n");
    try write(tmp.dir, "CLAUDE.md", "# Project\r\n\r\nOur notes.\r\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    const said = (try agents.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try testing.expectEqualStrings("skein: wrote what agents should know of skein into CLAUDE.md\n", said);
    const first = try tmp.dir.readFileAlloc(testing.io, "CLAUDE.md", a, .limited(1 << 16));
    // the file's own text and line ends are kept
    try expectContains(first, "# Project\r\n\r\nOur notes.\r\n\r\n" ++ instructions.begin ++ "\r\n");
    try expectContains(first, "- `rule`: A rule of the language; categories `syntax`; statuses `draft`, `approved`, `deprecated`, `removed`.\r\n");
    try expectContains(first, "- `verifies` to `rule`.\r\n");
    try expectContains(first, "- `test`: files under `tests/` ending in `.zig`, `// spec: ID, ID`.\r\n");
    try expectContains(first, "run `skein check`");

    // after a change to the schema, written again in place
    try write(tmp.dir, ".skein/types/term.toml", "");
    _ = try agents.run(testing.io, a, .{ .common = .{ .root = root } });
    const again = try tmp.dir.readFileAlloc(testing.io, "CLAUDE.md", a, .limited(1 << 16));
    try testing.expectEqual(1, std.mem.count(u8, again, instructions.begin));
    try expectContains(again, "- `term`;");

    _ = try agents.run(testing.io, a, .{ .common = .{ .root = root }, .skill = true });
    const skill = try tmp.dir.readFileAlloc(testing.io, instructions.skill_file, a, .limited(1 << 16));
    try testing.expect(std.mem.startsWith(u8, skill, "---\nname: skein\ndescription: "));
    try expectContains(skill, "## skein\n");
}

test "skein init writes AGENTS.md" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const said = (try init_command.run(testing.io, a, .{ .root = root, .templates = &.{"langspec"} })).text;
    try expectContains(said, "; AGENTS.md tells coding agents about Skein\n");
    try expectContains(try tmp.dir.readFileAlloc(testing.io, "AGENTS.md", a, .limited(1 << 16)), instructions.begin);
}
