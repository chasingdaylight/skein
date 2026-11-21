//! `skein diff` and `skein impact`, on a git repository made for the test.

const std = @import("std");
const testing = std.testing;

const diff = @import("../diff.zig");
const git_program = @import("../../git.zig");
const review = @import("../review.zig");

const Repo = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8,

    fn init(self: *Repo) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        self.root = try self.tmp.dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
        try self.git(&.{ "init", "--quiet" });
    }

    fn deinit(self: *Repo) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn git(self: *Repo, args: []const []const u8) !void {
        if (try git_program.output(testing.io, self.arena.allocator(), self.tmp.dir, args) == null) return error.GitFailed;
    }

    fn write(self: *Repo, path: []const u8, data: []const u8) !void {
        if (std.Io.Dir.path.dirname(path)) |parent| try self.tmp.dir.createDirPath(testing.io, parent);
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
    }

    fn commit(self: *Repo, message: []const u8) !void {
        try self.git(&.{ "add", "--all" });
        try self.git(&.{ "-c", "user.name=Tester", "-c", "user.email=tester@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", message });
    }

    fn run(self: *Repo, options: struct { revisions: []const []const u8 = &.{}, impact: bool = false, json: bool = false, markdown: bool = false }) ![]const u8 {
        const out = try diff.run(testing.io, self.arena.allocator(), .{
            .common = .{ .root = self.root },
            .revisions = options.revisions,
            .impact = options.impact,
            .json = options.json,
            .markdown = options.markdown,
        });
        return out.text;
    }

    /// The project as first committed
    fn first(self: *Repo) !void {
        try self.write(".skein/config.toml",
            \\[[sources]]
            \\path = "spec"
            \\[[citations]]
            \\name = "test"
            \\path = "tests"
            \\files = [".zig"]
            \\marker = "// spec:"
        );
        try self.write(".skein/types/rule.toml", "[attributes.note]\n");
        try self.write(".skein/types/case.toml", "");
        try self.write(".skein/links/verifies.toml", "review = true\n");
        try self.write("spec/lex.md",
            \\rule[lex.comment]
            \\A comment starts with `//`.
            \\
            \\rule[lex.token]
            \\A token is a unit of the text.
            \\
            \\rule[lex.space] status=approved note=old
            \\White space separates tokens; see [[lex.token]].
            \\
            \\rule[lex.gone]
            \\To be removed.
            \\
            \\case[c.token] verifies=lex.token
            \\Checks tokens.
            \\
            \\case[c.deep] verifies=c.token
            \\Rests on the case above.
        );
        try self.write("tests/token.zig", "// spec: lex.token\n");
        _ = try review.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.root }, .all = true }, .from);
        try self.commit("first");
    }

    /// The same, changed: a rule's text, another's status and note, one
    /// removed (as a tombstone), one added, one only laid out anew
    fn second(self: *Repo) !void {
        try self.write("spec/lex.md",
            \\rule[lex.comment]
            \\A comment   starts
            \\with `//`.
            \\
            \\rule[lex.token]
            \\A token is the smallest unit of the text.
            \\
            \\rule[lex.space] status=deprecated note=new
            \\White space separates tokens; see [[lex.token]].
            \\
            \\rule[lex.gone] status=removed
            \\
            \\rule[lex.new]
            \\A new rule.
            \\
            \\case[c.token] verifies=lex.token
            \\Checks tokens.
            \\
            \\case[c.deep] verifies=c.token
            \\Rests on the case above.
        );
    }
};

test "what changed since the last commit" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    try repo.first();
    try testing.expectEqualStrings(
        \\Changes from HEAD to the working tree
        \\
        \\No item was added, removed or changed.
        \\
    , try repo.run(.{}));

    try repo.second();
    try testing.expectEqualStrings(
        \\Changes from HEAD to the working tree
        \\
        \\Added (1):
        \\  lex.new  (rule)  spec/lex.md:13
        \\
        \\Removed (1):
        \\  lex.gone  (rule)
        \\
        \\Changed (2):
        \\  lex.token  (rule)  content  spec/lex.md:5
        \\  lex.space  (rule)  status: approved -> deprecated, attributes  spec/lex.md:8
        \\
    , try repo.run(.{}));
}

test "what the changes reach" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    try repo.first();
    try repo.second();
    try testing.expectEqualStrings(
        \\Impact of the changes from HEAD to the working tree
        \\
        \\Added (1):
        \\  lex.new  (rule)  spec/lex.md:13
        \\
        \\Removed (1):
        \\  lex.gone  (rule)
        \\
        \\Changed (2):
        \\  lex.token  (rule)  content  spec/lex.md:5
        \\  lex.space  (rule)  status: approved -> deprecated, attributes  spec/lex.md:8
        \\
        \\Look again at (2):
        \\  c.token  (case)  rests on lex.token  spec/lex.md:16
        \\  c.deep  (case)  rests on lex.token  spec/lex.md:19
        \\
        \\Links now suspect (1):
        \\  c.token  verifies lex.token
        \\
        \\Cited in (1):
        \\  tests/token.zig:1  (test)  lex.token
        \\
    , try repo.run(.{ .impact = true }));
}

test "between two commits, as Markdown and as JSON" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    try repo.first();
    try repo.second();
    try repo.commit("second");
    try repo.write("spec/lex.md", "rule[only.this]\nThe working tree is not looked at.\n");

    try testing.expectEqualStrings(
        \\## Changes from HEAD~1 to HEAD
        \\
        \\### Added (1)
        \\
        \\- `lex.new`  (rule)  spec/lex.md:13
        \\
        \\### Removed (1)
        \\
        \\- `lex.gone`  (rule)
        \\
        \\### Changed (2)
        \\
        \\- `lex.token`  (rule)  content  spec/lex.md:5
        \\- `lex.space`  (rule)  status: approved -> deprecated, attributes  spec/lex.md:8
        \\
    , try repo.run(.{ .revisions = &.{ "HEAD~1", "HEAD" }, .markdown = true }));

    const json = try repo.run(.{ .revisions = &.{ "HEAD~1", "HEAD" }, .json = true });
    try testing.expect(std.mem.startsWith(u8, json,
        \\{
        \\  "from": "HEAD~1",
        \\  "to": "HEAD",
        \\  "changes": [
        \\    {
        \\      "id": "lex.new",
        \\      "change": "added",
        \\      "type": "rule",
        \\      "what": [],
        \\      "file": "spec/lex.md",
        \\      "line": 13
        \\    },
    ));
    // the same commit on both sides: nothing changed
    try testing.expect(std.mem.find(u8, try repo.run(.{ .revisions = &.{ "HEAD", "HEAD" } }), "No item was added") != null);
}

test "a commit from before the project was one, and a commit that is none" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    try repo.write("readme.md", "Not yet a project.\n");
    try repo.commit("before");
    try repo.first();
    const text = try repo.run(.{ .revisions = &.{"HEAD~1"} });
    try testing.expect(std.mem.find(u8, text, "Added (6):") != null);
    try testing.expectEqualStrings("skein: git knows no commit 'no-such-tag'\n", try repo.run(.{ .revisions = &.{"no-such-tag"} }));
}
