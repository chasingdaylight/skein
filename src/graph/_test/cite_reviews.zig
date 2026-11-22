//! Reviewed citations: a test that cites a rule is sent back for review
//! when the rule changes, as a link of a reviewed type is.

// req: citations.review
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const cli = @import("../../cli.zig");
const review_command = @import("../../commands/review.zig");

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

test "a citation is reviewed, and suspect once the rule it cites has changed" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml",
        \\[[sources]]
        \\path = "spec"
        \\
        \\[[citations]]
        \\name = "test"
        \\path = "tests"
        \\files = [".zig"]
        \\marker = "// spec:"
        \\review = true
        \\
        \\[[citations]]
        \\name = "code"
        \\path = "src"
        \\files = [".zig"]
        \\marker = "// impl:"
        \\
    );
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, "spec/lex.md", "%rule[lex.a] A comment ends at the end of the line.\n");
    try write(tmp.dir, "tests/t.zig", "// spec: lex.a\n");
    try write(tmp.dir, "src/impl.zig", "// impl: lex.a\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const check = struct {
        fn run(al: std.mem.Allocator, r: []const u8) ![]const u8 {
            return (try check_command.run(testing.io, al, .{ .root = r })).text;
        }
    }.run;
    const review = struct {
        fn run(al: std.mem.Allocator, r: []const u8, direction: review_command.Direction, ids: []const []const u8) ![]const u8 {
            const options: cli.Review = .{ .common = .{ .root = r }, .ids = ids };
            return (try review_command.run(testing.io, al, options, direction)).text;
        }
    }.run;

    // only the set that asks for reviews is reported, and not the citation of the other
    const first = try check(a, root);
    try expectContains(first, "tests/t.zig:1:10: error: the citation of 'lex.a' was never reviewed ('skein review tests/t.zig')");
    try testing.expect(std.mem.find(u8, first, "src/impl.zig") == null);

    // reviewed by the file that cites
    try testing.expectEqualStrings("skein: 0 links and 1 citation recorded as reviewed\n", try review(a, root, .from, &.{"tests/t.zig"}));
    try expectContains(try check(a, root), "no problems");
    const records = try tmp.dir.readFileAlloc(testing.io, ".skein/reviews/citations/tests/t.zig.toml", a, .limited(1 << 16));
    try expectContains(records, "\"tests/t.zig\".\"cite:test\".\"lex.a\" = \"");

    // the rule changes: the test is to be looked at again
    try write(tmp.dir, "spec/lex.md", "%rule[lex.a] A comment ends at the end of the line, or of the file.\n");
    try expectContains(try check(a, root), "tests/t.zig:1:10: error: 'lex.a' has changed since the citation was reviewed ('skein clear lex.a')");

    // cleared by the item that changed
    try testing.expectEqualStrings("skein: 0 links and 1 citation recorded as reviewed\n", try review(a, root, .to, &.{"lex.a"}));
    try expectContains(try check(a, root), "no problems");

    // something that is neither an item nor a citing file is refused
    try expectContains(try review(a, root, .from, &.{"nothing.zig"}), "there is no item 'nothing.zig'");
}
