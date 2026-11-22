//! After a move between forges: a reference with the former forge's number
//! resolves through the map, with a warning; one that the map does not have
//! is reported; and `rewrite-refs` writes the new numbers.

// req: forge.moved
const std = @import("std");
const testing = std.testing;

const Forge = @import("../Forge.zig");
const check_command = @import("../../commands/check.zig");
const checks = @import("../checks.zig");
const git_program = @import("../../git.zig");
const github = @import("../github.zig");
const rewrite_command = @import("../../commands/rewrite_refs.zig");

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

/// group/project as the test has it: #7 and #9 exist
fn fake(_: std.Io, _: std.mem.Allocator, _: *const Forge, r: Forge.Ref) anyerror!github.Answer {
    return switch (r.number) {
        7, 9 => .{ .found = .{ .title = "There", .open = true, .pull = false } },
        else => .missing,
    };
}

test "references to a former forge resolve through the map, and are rewritten" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "init", "--quiet" });
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[forge]\nkind = \"gitlab\"\nrepository = \"group/project\"\nformerly = [\"github:example/spec\"]\n");
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, ".skein/links/tracked-by.toml", "");
    try write(tmp.dir, ".skein/forge-map.toml", "\"github:example/spec#24\" = \"gitlab:group/project#7\"\n");
    try write(tmp.dir, "spec/lex.md",
        \\%rule[lex.a tracked-by=#24] Old number, and the forge's own #9: see %[#9].
        \\
        \\%rule[lex.b tracked-by=github:example/spec#24] Written with the forge.
        \\
        \\%rule[lex.c tracked-by=github:example/spec#99] Not in the map.
        \\
    );
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const saved = checks.lookup;
    defer checks.lookup = saved;
    checks.lookup = fake;

    const out = (try check_command.run(testing.io, a, .{ .root = root })).text;
    // #24 is the former forge's, now #7, and it exists there
    try expectContains(out, "'#24', the number github:example/spec gave, which is #7 here now");
    try expectContains(out, "'github:example/spec#24', the number github:example/spec gave, which is #7 here now");
    // one the map does not have cannot be found
    try expectContains(out, "lex.c: tracked-by: the link points to 'github:example/spec#99', and github:example/spec has no such issue or pull request");
    try expectContains(out, "skein: 1 problem, 2 warnings");

    // the numbers are written, in the places that are references, and nowhere else
    const said = (try rewrite_command.run(testing.io, a, .{ .common = .{ .root = root } })).text;
    try expectContains(said, "spec/lex.md: 1 reference");
    const lex = try tmp.dir.readFileAlloc(testing.io, "spec/lex.md", a, .limited(1 << 16));
    try expectContains(lex, "%rule[lex.a tracked-by=#7] Old number, and the forge's own #9: see %[#9].");
    try expectContains(lex, "tracked-by=github:example/spec#24]");

    // a project that declares no former forge is refused
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[forge]\nkind = \"gitlab\"\nrepository = \"group/project\"\n");
    try testing.expectEqual(.misuse, (try rewrite_command.run(testing.io, a, .{ .common = .{ .root = root } })).status);
}
