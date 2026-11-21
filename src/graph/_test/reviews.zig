//! Review records: suspect links, and the files the records are kept in.

// req: review.per-link-type, review.state, review.commands, review.records, review.records.stale
// req: principle.plain-text
const std = @import("std");
const testing = std.testing;

const Graph = @import("../Graph.zig");
const Project = @import("../../Project.zig");
const Report = @import("../../Report.zig");
const Reviews = @import("../Reviews.zig");
const cli = @import("../../cli.zig");
const check_command = @import("../../commands/check.zig");
const review_command = @import("../../commands/review.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

/// A project with reviewed `verifies` links from tests to rules, and
/// `refines` links between requirements kept as item files
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
    );
    try write(dir, ".skein/types/rule.toml", "");
    try write(dir, ".skein/types/test.toml", "");
    try write(dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\n");
    try write(dir, ".skein/links/verifies.toml", "from = [\"test\"]\nto = [\"rule\"]\nreview = true\n");
    try write(dir, ".skein/links/refines.toml", "review = true\n");
    try write(dir, ".skein/links/see.toml", "");
    try write(dir, "spec/lex.md",
        \\rule[lex.comment]
        \\A comment starts with `//`.
        \\
        \\rule[lex.token]
        \\A token is a unit of the text.
    );
    try write(dir, "spec/tests.md",
        \\test[t.comment] verifies=lex.comment,lex.token see=lex.token
        \\Checks comments.
        \\
        \\test[t.token] verifies=lex.token
        \\Checks tokens.
    );
    try write(dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\n+++\nOne.\n");
    try write(dir, "requirements/SRS-002.md", "+++\nid = \"SRS-002\"\nrefines = \"SRS-001\"\n+++\nTwo.\n");
}

const Run = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8,

    fn init(self: *Run) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        self.root = try self.tmp.dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    fn deinit(self: *Run) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn check(self: *Run) ![]const u8 {
        return (try check_command.run(testing.io, self.arena.allocator(), .{ .root = self.root })).text;
    }

    fn review(self: *Run, direction: review_command.Direction, ids: []const []const u8) ![]const u8 {
        const options: cli.Review = .{ .common = .{ .root = self.root }, .ids = ids, .all = ids.len == 0 };
        return (try review_command.run(testing.io, self.arena.allocator(), options, direction)).text;
    }

    fn read(self: *Run, path: []const u8) ![]const u8 {
        return self.tmp.dir.readFileAlloc(testing.io, path, self.arena.allocator(), .limited(1 << 20));
    }
};

test "links of a reviewed kind are reported until they are reviewed" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try project(run.tmp.dir);

    // `see` links are not of a reviewed kind
    try testing.expectEqualStrings(
        \\requirements/SRS-002.md:1:1: error: SRS-002: refines: the link to 'SRS-001' was never reviewed ('skein review SRS-002')
        \\spec/tests.md:1:1: error: t.comment: verifies: the link to 'lex.comment' was never reviewed ('skein review t.comment')
        \\spec/tests.md:1:1: error: t.comment: verifies: the link to 'lex.token' was never reviewed ('skein review t.comment')
        \\spec/tests.md:4:1: error: t.token: verifies: the link to 'lex.token' was never reviewed ('skein review t.token')
        \\skein: 4 problems
        \\
    , try run.check());

    try testing.expectEqualStrings("skein: 2 links recorded as reviewed\n", try run.review(.from, &.{"t.comment"}));
    try testing.expectEqualStrings("skein: 2 links recorded as reviewed\n", try run.review(.from, &.{}));
    try testing.expectEqualStrings("skein: 0 links recorded as reviewed\n", try run.review(.from, &.{}));
    try testing.expectEqualStrings("skein: example: no problems (6 items of 3 types, 3 link types, 0 profiles, 0 citations)\n", try run.check());
}

test "records are kept by document and by directory of item files, sorted" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try project(run.tmp.dir);
    _ = try run.review(.from, &.{});

    const by_document = try run.read(".skein/reviews/spec/tests.md.toml");
    var lines = std.mem.splitScalar(u8, by_document, '\n');
    try testing.expectEqualStrings("# Review records, written by skein. Do not edit: use 'skein review'.", lines.next().?);
    try testing.expect(std.mem.startsWith(u8, lines.next().?, "\"t.comment\".verifies.\"lex.comment\" = \""));
    try testing.expect(std.mem.startsWith(u8, lines.next().?, "\"t.comment\".verifies.\"lex.token\" = \""));
    try testing.expect(std.mem.startsWith(u8, lines.next().?, "\"t.token\".verifies.\"lex.token\" = \""));
    try testing.expectEqualStrings("", lines.next().?);
    try testing.expectEqual(null, lines.next());

    const by_directory = try run.read(".skein/reviews/requirements.toml");
    try testing.expect(std.mem.find(u8, by_directory, "\"SRS-002\".refines.\"SRS-001\" = \"") != null);
    // a document without reviewed links has no file
    try testing.expectError(error.FileNotFound, run.read(".skein/reviews/spec/lex.md.toml"));
}

test "a link is suspect when its target changes, and not when it is only laid out anew" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try project(run.tmp.dir);
    _ = try run.review(.from, &.{});

    try write(run.tmp.dir, "spec/lex.md", "rule[lex.comment]\r\nA comment   starts\r\nwith `//`.\r\n\r\nrule[lex.token]\r\nA token is a unit of the text.\r\n");
    try testing.expect(std.mem.startsWith(u8, try run.check(), "skein: example: no problems"));

    try write(run.tmp.dir, "spec/lex.md", "rule[lex.comment]\nA comment starts with `//`.\n\nrule[lex.token]\nA token is the smallest unit of the text.\n");
    try testing.expectEqualStrings(
        \\spec/tests.md:1:1: error: t.comment: verifies: 'lex.token' has changed since the link was reviewed ('skein review t.comment')
        \\spec/tests.md:4:1: error: t.token: verifies: 'lex.token' has changed since the link was reviewed ('skein review t.token')
        \\skein: 2 problems
        \\
    , try run.check());

    // the item that changed is named: everything that points to it is cleared
    try testing.expectEqualStrings("skein: 2 links recorded as reviewed\n", try run.review(.to, &.{"lex.token"}));
    try testing.expect(std.mem.startsWith(u8, try run.check(), "skein: example: no problems"));
}

test "a record of a link that is gone goes when its file is written again" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try project(run.tmp.dir);
    _ = try run.review(.from, &.{});

    try write(run.tmp.dir, "spec/tests.md", "test[t.comment] verifies=lex.comment\nChecks comments.\n\ntest[t.new] verifies=lex.token\nNew.\n");
    try testing.expectEqualStrings("skein: 1 link recorded as reviewed\n", try run.review(.from, &.{"t.new"}));
    const records = try run.read(".skein/reviews/spec/tests.md.toml");
    try testing.expect(std.mem.find(u8, records, "\"t.token\"") == null);
    try testing.expect(std.mem.find(u8, records, "\"t.comment\".verifies.\"lex.token\"") == null);
    try testing.expect(std.mem.find(u8, records, "\"t.comment\".verifies.\"lex.comment\"") != null);
    try testing.expect(std.mem.find(u8, records, "\"t.new\".verifies.\"lex.token\"") != null);
}

test "an item that does not exist, and a records file that is not one" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try project(run.tmp.dir);
    try testing.expectEqualStrings("skein: there is no item 'no.such'\n", try run.review(.from, &.{"no.such"}));

    try write(run.tmp.dir, ".skein/reviews/spec/tests.md.toml", "something = 1\n");
    const text = try run.check();
    try testing.expect(std.mem.find(u8, text, ".skein/reviews/spec/tests.md.toml: error: this is no file of review records") != null);
}
