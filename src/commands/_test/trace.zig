//! `skein trace`, on a project on disk.

const std = @import("std");
const testing = std.testing;

const cli = @import("../../cli.zig");
const review = @import("../review.zig");
const trace = @import("../trace.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn project(dir: std.Io.Dir) !void {
    try write(dir, ".skein/config.toml",
        \\[[sources]]
        \\path = "spec"
        \\[[citations]]
        \\name = "test"
        \\path = "tests"
        \\files = [".zig"]
        \\marker = "// spec:"
    );
    try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\"]\n[attributes.stage]\n");
    try write(dir, ".skein/types/term.toml", "");
    try write(dir, ".skein/types/case.toml", "");
    try write(dir, ".skein/links/verifies.toml", "review = true\n");
    try write(dir, ".skein/links/see.toml", "");
    try write(dir, "spec/lex.md",
        \\term[lex.token]
        \\A token.
        \\
        \\rule[lex.comment] syntax stage=s0 see=lex.token
        \\A comment is not a [[lex.token]].
        \\
        \\case[c.comment] verifies=lex.comment
        \\Checks [[lex.comment]].
        \\
        \\case[c.other] verifies=lex.comment
        \\Checks more.
    );
    try write(dir, "tests/comment.zig", "// spec: lex.comment\n");
}

test "an item as text: itself, its links both ways, references, citations, above and below" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    _ = try review.run(testing.io, a, .{ .common = .{ .root = root }, .ids = &.{"c.comment"} }, .from);

    const out = try trace.run(testing.io, a, .{ .common = .{ .root = root }, .id = "lex.comment" });
    try testing.expectEqual(.ok, out.status);
    // the fingerprint is the item's own; its value is not the point here
    const fp_at = std.mem.find(u8, out.text, "fingerprint ").? + "fingerprint ".len;
    const shown = try std.mem.concat(a, u8, &.{ out.text[0..fp_at], "(...)", out.text[fp_at + 32 ..] });
    try testing.expectEqualStrings(
        \\lex.comment  (rule, syntax, draft)
        \\  spec/lex.md:4
        \\  fingerprint (...)
        \\  stage = s0
        \\
        \\Links to:
        \\  see lex.token (term)
        \\
        \\Linked from:
        \\  verifies c.comment (case)  [reviewed]
        \\  verifies c.other (case)  [never reviewed]
        \\
        \\Refers to: lex.token
        \\
        \\Referred to by: c.comment
        \\
        \\Cited by:
        \\  test  tests/comment.zig:1
        \\
        \\Above (all it rests on): lex.token
        \\
        \\Below (all that rests on it): c.comment, c.other
        \\
    , shown);
}

test "an item as JSON" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    const out = try trace.run(testing.io, a, .{ .common = .{ .root = root }, .id = "c.comment", .json = true });
    const fp_at = std.mem.find(u8, out.text, "\"fingerprint\": \"").? + "\"fingerprint\": \"".len;
    const shown = try std.mem.concat(a, u8, &.{ out.text[0..fp_at], "(...)", out.text[fp_at + 32 ..] });
    try testing.expectEqualStrings(
        \\{
        \\  "item": {
        \\    "id": "c.comment",
        \\    "type": "case",
        \\    "category": null,
        \\    "status": "draft",
        \\    "removed": false,
        \\    "verification": null,
        \\    "file": "spec/lex.md",
        \\    "line": 7,
        \\    "fingerprint": "(...)",
        \\    "attributes": {},
        \\    "links": [
        \\      {
        \\        "type": "verifies",
        \\        "target": "lex.comment",
        \\        "review": "never reviewed"
        \\      }
        \\    ],
        \\    "linked_from": [],
        \\    "references": [
        \\      "lex.comment"
        \\    ],
        \\    "referenced_from": [],
        \\    "citations": [],
        \\    "text": "Checks [[lex.comment]]."
        \\  },
        \\  "above": [
        \\    "lex.comment",
        \\    "lex.token"
        \\  ],
        \\  "below": []
        \\}
        \\
    , shown);
}

test "an item that does not exist" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const out = try trace.run(testing.io, a, .{ .common = .{ .root = root }, .id = "no.such" });
    try testing.expectEqual(.misuse, out.status);
    try testing.expectEqualStrings("skein: there is no item 'no.such'\n", out.text);
}

test "trace on the command line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = (try cli.parse(a, &.{ "trace", "--json", "a.b" })).trace;
    try testing.expectEqualStrings("a.b", t.id);
    try testing.expect(t.json);
    try testing.expectEqualStrings("trace takes one item", (try cli.parse(a, &.{"trace"})).misuse);
    try testing.expectEqualStrings("--json goes with trace and coverage", (try cli.parse(a, &.{ "check", "--json" })).misuse);
}
