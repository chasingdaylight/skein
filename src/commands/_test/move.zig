//! `skein move`, on a project on disk.

// req: move.everywhere, move.parts, move.records, move.refusals, move.item-files
const std = @import("std");
const testing = std.testing;

const approve = @import("../approve.zig");
const check_command = @import("../check.zig");
const move_command = @import("../move.zig");
const review_command = @import("../review.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn read(a: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) ![]const u8 {
    return dir.readFileAlloc(testing.io, path, a, .limited(1 << 20));
}

const lex =
    \\# Lexical structure
    \\
    \\Narrative about %[lex.token the token].
    \\
    \\%rule[lex.token syntax approved] A token, as %[SRS-001] asks.
    \\
    \\%rule[lex.keywords syntax] The keywords are %[lex.token tokens]:
    \\
    \\- %rule[.as syntax] `as`
    \\- %rule[lex.keywords.fn syntax] `fn`, see %[lex.keywords.as].
    \\- %rule[lex.other syntax] one named apart
    \\
    \\%case[c.one verifies=lex.token,lex.keywords.as] Checks `lex.token` in code, and lex.token in prose.
    \\
;

fn project(dir: std.Io.Dir) !void {
    try write(dir, ".skein/config.toml",
        \\[project]
        \\name = "example"
        \\[[sources]]
        \\path = "spec"
        \\[[sources]]
        \\path = "requirements"
        \\kind = "items"
        \\type = "srs"
        \\[[citations]]
        \\name = "test"
        \\path = "tests"
        \\files = [".zig"]
        \\marker = "// spec:"
    );
    try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\"]\napproval = [\"approved\"]\n");
    try write(dir, ".skein/types/case.toml", "");
    try write(dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\n");
    try write(dir, ".skein/links/verifies.toml", "from = [\"case\"]\nreview = true\n");
    try write(dir, ".skein/links/refines.toml", "from = [\"srs\"]\n");
    try write(dir, "spec/lex.md", lex);
    try write(dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\n+++\n\nTokens exist.\n");
    try write(dir, "requirements/SRS-002.md", "+++\nid = \"SRS-002\"\nrefines = [\"SRS-001\"]\n+++\n\nMore of %[SRS-001].\n");
    try write(dir, "tests/a.zig", "// spec: lex.token, lex.keywords.as. A sentence.\nconst lex_token = 1;\n");
    try write(dir, "tests/.skein-cites", "# all of these\nlex.keywords\nlex.token\n");
}

const Run = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8,

    fn init(self: *Run) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        try project(self.tmp.dir);
        self.root = try self.tmp.dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    fn deinit(self: *Run) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn move(self: *Run, old: []const u8, new: []const u8) ![]const u8 {
        return (try move_command.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.root }, .old = old, .new = new })).text;
    }

    /// Reviews every link and approves the rule that needs it, so that `check` is clean
    fn settle(self: *Run) !void {
        const a = self.arena.allocator();
        _ = try review_command.run(testing.io, a, .{ .common = .{ .root = self.root }, .all = true }, .from);
        _ = try approve.run(testing.io, a, .{ .common = .{ .root = self.root }, .ids = &.{"lex.token"}, .by = "A. Reviewer", .on = "2027-03-01" });
    }

    fn check(self: *Run) ![]const u8 {
        return (try check_command.run(testing.io, self.arena.allocator(), .{ .root = self.root })).text;
    }

    fn file(self: *Run, path: []const u8) ![]const u8 {
        return read(self.arena.allocator(), self.tmp.dir, path);
    }
};

test "an ID is renamed in markers, references, links and citations" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try testing.expectEqualStrings("skein: lex.token is now lex.lexeme: 8 places in 3 files\n", try run.move("lex.token", "lex.lexeme"));

    try testing.expectEqualStrings(
        \\# Lexical structure
        \\
        \\Narrative about %[lex.lexeme the token].
        \\
        \\%rule[lex.lexeme syntax approved] A token, as %[SRS-001] asks.
        \\
        \\%rule[lex.keywords syntax] The keywords are %[lex.lexeme tokens]:
        \\
        \\- %rule[.as syntax] `as`
        \\- %rule[lex.keywords.fn syntax] `fn`, see %[lex.keywords.as].
        \\- %rule[lex.other syntax] one named apart
        \\
        \\%case[c.one verifies=lex.lexeme,lex.keywords.as] Checks `lex.lexeme` in code, and lex.lexeme in prose.
        \\
    , try run.file("spec/lex.md"));
    // only the lines that cite: the code below them is not touched
    try testing.expectEqualStrings("// spec: lex.lexeme, lex.keywords.as. A sentence.\nconst lex_token = 1;\n", try run.file("tests/a.zig"));
    try testing.expectEqualStrings("# all of these\nlex.keywords\nlex.lexeme\n", try run.file("tests/.skein-cites"));
}

test "the parts whose IDs continue the old ID follow it" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try testing.expectEqualStrings("skein: lex.keywords is now lex.kw, with 2 parts: 6 places in 3 files\n", try run.move("lex.keywords", "lex.kw"));
    const spec = try run.file("spec/lex.md");
    // the part named by a leading dot needs no change; the one named in full is renamed
    try testing.expect(std.mem.find(u8, spec, "%rule[lex.kw syntax] The keywords are") != null);
    try testing.expect(std.mem.find(u8, spec, "- %rule[.as syntax] `as`\n") != null);
    try testing.expect(std.mem.find(u8, spec, "- %rule[lex.kw.fn syntax] `fn`, see %[lex.kw.as].") != null);
    // a part with a name of its own stays as it is
    try testing.expect(std.mem.find(u8, spec, "- %rule[lex.other syntax]") != null);
    try testing.expect(std.mem.find(u8, spec, "verifies=lex.token,lex.kw.as]") != null);
    try testing.expectEqualStrings("// spec: lex.token, lex.kw.as. A sentence.\nconst lex_token = 1;\n", try run.file("tests/a.zig"));
    try testing.expectEqualStrings("# all of these\nlex.kw\nlex.token\n", try run.file("tests/.skein-cites"));
}

test "a part named by a leading dot keeps the dot, or is named in full" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try run.settle();
    _ = try run.move("lex.keywords.as", "lex.keywords.cast");
    var spec = try run.file("spec/lex.md");
    try testing.expect(std.mem.find(u8, spec, "- %rule[.cast syntax] `as`\n") != null);
    try testing.expect(std.mem.find(u8, spec, "see %[lex.keywords.cast].") != null);

    _ = try run.move("lex.keywords.cast", "lex.conversion");
    spec = try run.file("spec/lex.md");
    try testing.expect(std.mem.find(u8, spec, "- %rule[lex.conversion syntax] `as`\n") != null);
    try testing.expect(std.mem.startsWith(u8, try run.check(), "skein: example: no problems"));
}

test "an item file follows its ID, and so do the links to it" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try run.settle();
    _ = try run.move("SRS-001", "SRS-100");
    try testing.expectEqualStrings("+++\nid = \"SRS-100\"\n+++\n\nTokens exist.\n", try run.file("requirements/SRS-100.md"));
    try testing.expectError(error.FileNotFound, run.file("requirements/SRS-001.md"));
    try testing.expectEqualStrings("+++\nid = \"SRS-002\"\nrefines = [\"SRS-100\"]\n+++\n\nMore of %[SRS-100].\n", try run.file("requirements/SRS-002.md"));
    try testing.expect(std.mem.find(u8, try run.file("spec/lex.md"), "A token, as %[SRS-100] asks.") != null);
    try testing.expect(std.mem.startsWith(u8, try run.check(), "skein: example: no problems"));
}

test "reviews and approvals that were current stay current" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    const a = run.arena.allocator();
    _ = try review_command.run(testing.io, a, .{ .common = .{ .root = run.root }, .all = true }, .from);
    _ = try approve.run(testing.io, a, .{ .common = .{ .root = run.root }, .ids = &.{"lex.token"}, .by = "A. Reviewer", .on = "2027-03-01" });
    try testing.expect(std.mem.startsWith(u8, try run.check(), "skein: example: no problems"));

    // the rule that is approved is renamed, and so is a rule that the text of a reviewed target names
    _ = try run.move("lex.token", "lex.lexeme");
    _ = try run.move("lex.keywords.as", "lex.keywords.cast");
    try testing.expect(std.mem.startsWith(u8, try run.check(), "skein: example: no problems"));

    const reviews = try run.file(".skein/reviews/spec/lex.md.toml");
    try testing.expect(std.mem.find(u8, reviews, "\"c.one\".verifies.\"lex.lexeme\" = \"") != null);
    try testing.expect(std.mem.find(u8, reviews, "\"c.one\".verifies.\"lex.keywords.cast\" = \"") != null);
    try testing.expect(std.mem.find(u8, reviews, "lex.token") == null);
    const approvals = try run.file(".skein/approvals/spec/lex.md.toml");
    try testing.expect(std.mem.find(u8, approvals, "\"lex.lexeme\".\"A. Reviewer\" = { on = 2027-03-01, fingerprint = \"") != null);
}

test "what cannot be done is refused, and nothing is changed" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try testing.expectEqualStrings("skein: there is no item 'lex.nope'\n", try run.move("lex.nope", "lex.x"));
    try testing.expectEqualStrings("skein: the ID 'lex.other' is taken\n", try run.move("lex.token", "lex.other"));
    try testing.expectEqualStrings("skein: 'Lex Token' is not spelled as the IDs of a 'rule' are\n", try run.move("lex.token", "Lex Token"));
    try testing.expectEqualStrings("skein: 'SRS-1x' is not spelled as the IDs of a 'srs' are\n", try run.move("SRS-001", "SRS-1x"));
    try testing.expectEqualStrings("skein: 'lex.token' is its ID already\n", try run.move("lex.token", "lex.token"));
    // a part's new ID is taken
    try write(run.tmp.dir, "spec/more.md", "%rule[lex.kw.as syntax] Taken.\n");
    try testing.expectEqualStrings("skein: the ID 'lex.kw.as' is taken\n", try run.move("lex.keywords", "lex.kw"));
    try testing.expectEqualStrings(lex, try run.file("spec/lex.md"));
}
