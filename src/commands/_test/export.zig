//! `skein export`, on a project on disk.

// req: export.json, export.csv, export.profile
const std = @import("std");
const testing = std.testing;

const exporter = @import("../export.zig");

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
    );
    try write(dir, ".skein/types/rule.toml", "description = \"A rule\"\ncategories = [\"syntax\"]\n[attributes.stage]\n");
    try write(dir, ".skein/types/case.toml", "[attributes.runner]\n");
    try write(dir, ".skein/links/verifies.toml", "from = [\"case\"]\nreview = true\n");
    try write(dir, ".skein/profiles/s0.toml", "[where]\nstage = \"s0\"\n");
    try write(dir, "spec/lex.md",
        \\rule[lex.comment] syntax stage=s0
        \\A comment starts with `//`, and ends
        \\with the "line".
        \\
        \\rule[lex.token] syntax stage=s1
        \\A token.
        \\
        \\case[c.comment] verifies=lex.comment,no.such runner=unit
        \\Checks comments.
    );
    try write(dir, "tests/a.zig", "// spec: lex.comment, lex.token\n");
}

fn run(a: std.mem.Allocator, dir: std.Io.Dir, what: exporter.What, profile: ?[]const u8) ![]const u8 {
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    return (try exporter.run(testing.io, a, .{ .common = .{ .root = root }, .what = what, .profile = profile })).text;
}

/// `text` with every fingerprint (32 hexadecimal characters) replaced
fn withoutFingerprints(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        var n: usize = 0;
        while (i + n < text.len and std.ascii.isHex(text[i + n])) n += 1;
        if (n == 32) {
            try out.appendSlice(a, "FP");
            i += n;
        } else {
            try out.appendSlice(a, text[i .. i + @max(n, 1)]);
            i += @max(n, 1);
        }
    }
    return out.items;
}

test "items as CSV: one column per attribute, and the text" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    try testing.expectEqualStrings(
        "id,type,category,status,verification,file,line,fingerprint,runner,stage,text\n" ++
            "lex.comment,rule,syntax,draft,,spec/lex.md,1,FP,,s0,\"A comment starts with `//`, and ends\nwith the \"\"line\"\".\"\n" ++
            "lex.token,rule,syntax,draft,,spec/lex.md,5,FP,,s1,A token.\n" ++
            "c.comment,case,,draft,,spec/lex.md,8,FP,unit,,Checks comments.\n",
        try withoutFingerprints(a, try run(a, tmp.dir, .items, null)),
    );
}

test "links and citations as CSV" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    try testing.expectEqualStrings(
        \\from,from_type,link,to,to_type,review
        \\c.comment,case,verifies,lex.comment,rule,never reviewed
        \\c.comment,case,verifies,no.such,,
        \\
    , try run(a, tmp.dir, .links, null));
    try testing.expectEqualStrings(
        \\set,file,line,item,item_type
        \\test,tests/a.zig,1,lex.comment,rule
        \\test,tests/a.zig,1,lex.token,rule
        \\
    , try run(a, tmp.dir, .citations, null));
}

test "a profile narrows every export" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    const items = try run(a, tmp.dir, .items, "s0");
    try testing.expect(std.mem.find(u8, items, "lex.comment,") != null);
    try testing.expect(std.mem.find(u8, items, "lex.token,") == null);
    try testing.expectEqualStrings(
        \\set,file,line,item,item_type
        \\test,tests/a.zig,1,lex.comment,rule
        \\
    , try run(a, tmp.dir, .citations, "s0"));
    try testing.expectEqualStrings("skein: there is no profile 'nope'\n", try run(a, tmp.dir, .json, "nope"));
}

test "everything as JSON" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    const text = try run(a, tmp.dir, .json, "s0");
    try testing.expect(std.mem.startsWith(u8, text,
        \\{
        \\  "project": "example",
        \\  "profile": "s0",
        \\  "types": [
        \\    {
        \\      "name": "case",
        \\      "description": "",
        \\      "categories": [],
        \\      "statuses": [
        \\        "draft",
        \\        "approved",
        \\        "deprecated",
        \\        "removed"
        \\      ]
        \\    },
    ));
    try testing.expect(std.mem.find(u8, text, "\"link_types\": [\n    {\n      \"name\": \"verifies\",") != null);
    try testing.expect(std.mem.find(u8, text, "\"id\": \"lex.comment\"") != null);
    try testing.expect(std.mem.find(u8, text, "\"id\": \"lex.token\"") == null);
    try testing.expect(std.mem.find(u8, text, "\"text\": \"A comment starts with `//`, and ends\\nwith the \\\"line\\\".\"") != null);
    try testing.expect(std.mem.endsWith(u8, text, "  ]\n}\n"));
}
