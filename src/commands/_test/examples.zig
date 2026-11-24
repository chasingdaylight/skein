//! Tested examples: code blocks marked on their opening line, read as
//! items, counted by coverage, and written out by `skein examples`.

// req: examples.marked, examples.parts, examples.coverage, examples.command, items.marker.repeated
const std = @import("std");
const testing = std.testing;

const check_command = @import("../check.zig");
const coverage_command = @import("../coverage.zig");
const examples_command = @import("../examples.zig");
const render_command = @import("../render.zig");

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

const spec =
    \\# Lexing
    \\
    \\%rule[lex.comment syntax] A comment runs to the end of the line.
    \\
    \\```cesium %example
    \\// fine
    \\```
    \\
    \\```cesium %example[.open rejects]
    \\/* open
    \\```
    \\
    \\Narrative, then an example of its own.
    \\
    \\```cesium %example[ex.both shows=lex.comment shows=lex.token]
    \\x // y
    \\```
    \\
    \\```zig
    \\const plain = "not an example";
    \\```
    \\
    \\%rule[lex.token syntax] A token.
    \\
;

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8,

    fn init(self: *Fixture) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        const dir = self.tmp.dir;
        try write(dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
        try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\"]\n");
        try write(dir, ".skein/types/example.toml",
            \\categories = ["accepts", "rejects"]
            \\
            \\[example]
            \\link = "shows"
            \\
            \\[example.extensions]
            \\cesium = ".csm"
            \\
        );
        try write(dir, ".skein/links/shows.toml", "from = [\"example\"]\nto = [\"rule\"]\nexpected = true\n");
        try write(dir, "spec/lex.md", spec);
        self.root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    fn deinit(self: *Fixture) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }
};

test "examples are items: parts of the item they are in, or on their own" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const a = f.arena.allocator();
    try expectContains((try check_command.run(testing.io, a, .{ .root = f.root })).text, "no problems (5 items");
    // the parts show their whole, and the one on its own shows two rules
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = f.root } })).text, "2 of 2 (100%)");

    const out_dir = try std.Io.Dir.path.join(a, &.{ f.root, "out" });
    const written = try examples_command.run(testing.io, a, .{ .common = .{ .root = f.root }, .out = out_dir });
    try testing.expectEqualStrings(try a.print("skein: wrote 3 examples and examples.json to {s}\n", .{out_dir}), written.text);
    const read = struct {
        fn file(dir: std.Io.Dir, al: std.mem.Allocator, path: []const u8) ![]const u8 {
            return dir.readFileAlloc(testing.io, path, al, .limited(1 << 16));
        }
    }.file;
    try testing.expectEqualStrings("// fine\n", try read(f.tmp.dir, a, "out/lex.comment.example-1.csm"));
    try testing.expectEqualStrings("/* open\n", try read(f.tmp.dir, a, "out/lex.comment.open.csm"));
    const index = try read(f.tmp.dir, a, "out/examples.json");
    try expectContains(index, "\"id\": \"lex.comment.open\",\n    \"file\": \"lex.comment.open.csm\",\n    \"language\": \"cesium\",\n    \"expect\": \"reject\",\n    \"shows\": [\n      \"lex.comment\"\n    ],\n    \"source\": \"spec/lex.md\",\n    \"line\": 9");
    try expectContains(index, "\"shows\": [\n      \"lex.comment\",\n      \"lex.token\"\n    ]");
}

// req: render.markdown.markers
test "an example renders as its label, then its fence with the language alone" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const a = f.arena.allocator();
    const out_dir = try std.Io.Dir.path.join(a, &.{ f.root, "site" });
    _ = try render_command.run(testing.io, a, .{ .common = .{ .root = f.root }, .out = out_dir });
    const page = try f.tmp.dir.readFileAlloc(testing.io, "site/spec/lex.md", a, .limited(1 << 16));
    try expectContains(page, "<a id=\"lex.comment.example-1\"></a>**[lex.comment.example-1](#lex.comment.example-1)**\n```cesium\n// fine\n```");
    try expectContains(page, "<a id=\"lex.comment.open\"></a>**[lex.comment.open](#lex.comment.open)** *(rejects)*\n```cesium\n/* open\n```");
    try expectContains(page, "**[ex.both](#ex.both)**\n```cesium\nx // y");
    try expectContains(page, "```zig\nconst plain");
}

test "what cannot be an example is reported" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const a = f.arena.allocator();
    try write(f.tmp.dir, "spec/bad.md",
        \\Narrative.
        \\
        \\```cesium %example
        \\no item to belong to
        \\```
        \\
        \\```cesium %rule[lex.x syntax]
        \\a rule is no example
        \\```
        \\
    );
    const out = (try check_command.run(testing.io, a, .{ .root = f.root })).text;
    try expectContains(out, "spec/bad.md:3:1: error: an example outside an item needs an ID: %example[ID]");
    try expectContains(out, "spec/bad.md:7:1: error: a 'rule' cannot be a code block: only an item type with [example] can");
}
