//! Expectations that apply to some of the items only.

// req: coverage.expected-of
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const coverage_command = @import("../../commands/coverage.zig");

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

test "an expectation of the items a condition or a profile selects" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, ".skein/types/srs.toml", "verification = [\"test\", \"inspection\"]\n\n[attributes.classes]\nlist = true\n");
    try write(tmp.dir, ".skein/types/procedure.toml", "");
    try write(tmp.dir, ".skein/types/design.toml", "");
    try write(tmp.dir, ".skein/profiles/class-a-to-c.toml", "[where]\nclasses = [\"A\", \"B\", \"C\"]\n");
    // a test procedure is expected only of what is verified by test
    try write(tmp.dir, ".skein/links/verifies.toml", "from = [\"procedure\"]\nto = [\"srs\"]\nexpected = { where = { verification = \"test\" } }\n");
    // a design only of the classes that need one traced
    try write(tmp.dir, ".skein/links/implements.toml", "from = [\"design\"]\nto = [\"srs\"]\nexpected = { profile = \"class-a-to-c\" }\n");
    try write(tmp.dir, "spec/srs.md",
        \\%srs[srs.one verification=test classes=C] Tested, class C.
        \\
        \\%srs[srs.two verification=inspection classes=D] Inspected, class D.
        \\
        \\%srs[srs.three verification=test classes=D] Tested, class D.
        \\
        \\%procedure[tp.one verifies=srs.one] A procedure.
        \\
    );
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems (4 items");
    const out = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(out, "verifies links to srs items: 1 of 2 (50%)\n  without:\n    srs.three\n");
    try expectContains(out, "implements links to srs items: 0 of 1 (0%)\n  without:\n    srs.one\n");

    try write(tmp.dir, ".skein/links/implements.toml", "from = [\"design\"]\nto = [\"srs\"]\nexpected = { profile = \"nowhere\" }\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, ".skein/links/implements.toml: error: expected: there is no profile 'nowhere'");
}
