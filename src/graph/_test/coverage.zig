//! Coverage and profiles, on a project on disk.

// req: coverage.expected, coverage.profile, coverage.reports, coverage.parts
const std = @import("std");
const testing = std.testing;

const coverage_command = @import("../../commands/coverage.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn project(dir: std.Io.Dir) !void {
    try write(dir, ".skein/config.toml",
        \\[project]
        \\name = "example"
        \\[[sources]]
        \\path = "spec"
        \\[[citations]]
        \\name = "test"
        \\path = "tests"
        \\files = [".zig"]
        \\marker = "// spec:"
        \\to = ["rule"]
        \\expected = true
    );
    try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\", \"legality\"]\n[attributes.stage]\n");
    try write(dir, ".skein/types/term.toml", "");
    try write(dir, ".skein/types/case.toml", "");
    try write(dir, ".skein/links/verifies.toml", "from = [\"case\"]\nto = [\"rule\"]\nexpected = true\n");
    try write(dir, ".skein/links/see.toml", "");
    try write(dir, ".skein/profiles/s0.toml", "types = [\"rule\"]\n[where]\nstage = \"s0\"\n");
    try write(dir, "spec/lex.md",
        \\%rule[lex.a syntax stage=s0]
        \\Linked and cited.
        \\
        \\%rule[lex.b syntax stage=s0]
        \\Linked only.
        \\
        \\%rule[lex.c legality stage=s1]
        \\Neither.
        \\
        \\%rule[lex.d legality stage=s0]
        \\Cited only.
        \\
        \\%rule[lex.old removed]
        \\
        \\%term[lex.term]
        \\Not a rule: nothing is expected of it.
        \\
        \\%case[c.one verifies=lex.a,lex.b see=lex.c]
        \\A case.
    );
    try write(dir, "tests/a.zig", "// spec: lex.a, lex.d\n");
}

fn run(a: std.mem.Allocator, dir: std.Io.Dir, profile: ?[]const u8, json: bool) ![]const u8 {
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const out = try coverage_command.run(testing.io, a, .{ .common = .{ .root = root }, .profile = profile, .json = json });
    return out.text;
}

test "links and citations that are expected are counted, by category" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    // `see` is not expected, the removed rule is not counted, a term is not a rule
    try testing.expectEqualStrings(
        \\Coverage of example
        \\
        \\verifies links to rule items: 2 of 4 (50%)
        \\  syntax: 2 of 2 (100%)
        \\  legality: 0 of 2 (0%)
        \\  without:
        \\    lex.c
        \\    lex.d
        \\
        \\test citations of rule items: 2 of 4 (50%)
        \\  syntax: 1 of 2 (50%)
        \\  legality: 1 of 2 (50%)
        \\  without:
        \\    lex.b
        \\    lex.c
        \\
    , try run(arena.allocator(), tmp.dir, null, false));
}

test "a profile narrows what is counted" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    try testing.expectEqualStrings(
        \\Coverage of example, profile s0
        \\
        \\verifies links to rule items: 2 of 3 (66%)
        \\  syntax: 2 of 2 (100%)
        \\  legality: 0 of 1 (0%)
        \\  without:
        \\    lex.d
        \\
        \\test citations of rule items: 2 of 3 (66%)
        \\  syntax: 1 of 2 (50%)
        \\  legality: 1 of 1 (100%)
        \\  without:
        \\    lex.b
        \\
    , try run(arena.allocator(), tmp.dir, "s0", false));
    try testing.expectEqualStrings("skein: there is no profile 'nope'\n", try run(arena.allocator(), tmp.dir, "nope", false));
}

test "coverage as JSON" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    const text = try run(arena.allocator(), tmp.dir, "s0", true);
    try testing.expect(std.mem.startsWith(u8, text,
        \\{
        \\  "profile": "s0",
        \\  "expectations": [
        \\    {
        \\      "kind": "link",
        \\      "name": "verifies",
        \\      "type": "rule",
        \\      "total": 3,
        \\      "covered": 2,
        \\      "categories": [
        \\        {
        \\          "category": "syntax",
        \\          "total": 2,
        \\          "covered": 2
        \\        },
    ));
    try testing.expect(std.mem.find(u8, text, "\"uncovered\": [\n        \"lex.d\"\n      ]") != null);
}

test "an item is covered when each of its parts is" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    try write(tmp.dir, "spec/lex.md",
        \\%rule[all syntax] Each part is cited, one through its own parts:
        \\
        \\- %rule[.a syntax] Cited.
        \\- %rule[.b syntax] Covered by its parts:
        \\  - %rule[.x syntax] Cited.
        \\  - %term[.note] A term: citations are not expected of it.
        \\  - %rule[.old removed]
        \\
        \\%rule[some syntax] One part is not cited:
        \\
        \\- %rule[.a syntax] Cited.
        \\- %rule[.b syntax] Not cited.
        \\
        \\%rule[itself syntax] Cited itself, and its part is not:
        \\
        \\- %rule[.a syntax] Not cited.
        \\
        \\%rule[terms syntax] No part that a citation is expected of:
        \\
        \\- %term[.t] A term.
    );
    try write(tmp.dir, "tests/a.zig", "// spec: all.a, all.b.x, some.a, itself\n");
    const text = try run(arena.allocator(), tmp.dir, null, false);
    const citations = text[std.mem.find(u8, text, "test citations").?..];
    try testing.expectEqualStrings(
        \\test citations of rule items: 6 of 10 (60%)
        \\  syntax: 6 of 10 (60%)
        \\  without:
        \\    some
        \\    some.b
        \\    itself.a
        \\    terms
        \\
    , citations);
}

test "a project that expects nothing says so" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[project]\nname = \"bare\"\n");
    try testing.expectEqualStrings(
        \\Coverage of bare
        \\
        \\Nothing is expected: no link type and no citation set has 'expected = true'.
        \\
    , try run(arena.allocator(), tmp.dir, null, false));
}
