//! `skein baseline`, on a git repository made for the test.

// req: baseline.tag, baseline.refusals, baseline.list
const std = @import("std");
const testing = std.testing;

const baseline_command = @import("../baseline.zig");
const git_program = @import("../../git.zig");

const Repo = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8,

    fn init(self: *Repo) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        self.root = try self.tmp.dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
        try self.git(&.{ "init", "--quiet" });
        try self.write(".skein/config.toml", "[project]\nname = \"example\"\n[[sources]]\npath = \"spec\"\n[[citations]]\nname = \"test\"\npath = \"tests\"\nfiles = [\".zig\"]\nmarker = \"// spec:\"\nexpected = true\n");
        try self.write(".skein/types/rule.toml", "");
        try self.write("spec/lex.md", "%rule[lex.a] A.\n\n%rule[lex.b] B.\n");
        try self.write("tests/a.zig", "// spec: lex.a\n");
        try self.commit("first");
    }

    fn deinit(self: *Repo) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn git(self: *Repo, args: []const []const u8) !void {
        if (try git_program.output(testing.io, self.arena.allocator(), self.tmp.dir, args) == null) return error.GitFailed;
    }

    fn gitOutput(self: *Repo, args: []const []const u8) ![]const u8 {
        return try git_program.output(testing.io, self.arena.allocator(), self.tmp.dir, args) orelse error.GitFailed;
    }

    fn write(self: *Repo, path: []const u8, data: []const u8) !void {
        if (std.Io.Dir.path.dirname(path)) |parent| try self.tmp.dir.createDirPath(testing.io, parent);
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
    }

    fn commit(self: *Repo, message: []const u8) !void {
        try self.git(&.{ "add", "--all" });
        try self.git(&.{ "-c", "user.name=Tester", "-c", "user.email=tester@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", message });
    }

    fn baseline(self: *Repo, name: ?[]const u8, message: ?[]const u8) !struct { text: []const u8, ok: bool } {
        // the tag is made by git as the user: give the test one
        try self.git(&.{ "config", "user.name", "Tester" });
        try self.git(&.{ "config", "user.email", "tester@example.invalid" });
        const out = try baseline_command.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.root }, .name = name, .message = message });
        return .{ .text = out.text, .ok = out.status == .ok };
    }
};

test "a baseline is an annotated tag that says what the project held" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();

    try testing.expectEqualStrings("skein: there is no baseline yet\n", (try repo.baseline(null, null)).text);
    const made = try repo.baseline("v1.0", "The first release.");
    try testing.expect(made.ok);
    const short = std.mem.trim(u8, try repo.gitOutput(&.{ "rev-parse", "--short", "HEAD" }), " \r\n");
    try testing.expectEqualStrings(try a.print("skein: baseline v1.0 at {s}; share it with: git push origin v1.0\n", .{short}), made.text);
    const message = try repo.gitOutput(&.{ "tag", "--list", "--format=%(contents)", "v1.0" });
    try testing.expectEqualStrings("skein baseline v1.0\n\nThe first release.\n\nexample: 2 items\ntest citations of rule items: 1 of 2", std.mem.trimEnd(u8, message, "\r\n"));

    // an ordinary tag is not a baseline
    try repo.git(&.{ "tag", "other" });
    const listed = (try repo.baseline(null, null)).text;
    try testing.expect(std.mem.startsWith(u8, listed, "v1.0  "));
    try testing.expect(std.mem.find(u8, listed, "other") == null);
}

test "a baseline is refused for uncommitted changes, problems, and a taken name" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();

    try testing.expectEqualStrings("skein: '-x' cannot be the name of a tag\n", (try repo.baseline("-x", null)).text);
    try repo.write("spec/lex.md", "%rule[lex.a] A, changed.\n\n%rule[lex.b] B.\n");
    try testing.expectEqualStrings("skein: there are changes that are not committed; a baseline is of what is committed\n", (try repo.baseline("v1", null)).text);
    try repo.write("spec/lex.md", "%rule[lex.a] A, see %[lex.nope].\n\n%rule[lex.b] B.\n");
    try repo.commit("a problem");
    const refused = try repo.baseline("v1", null);
    try testing.expect(!refused.ok);
    try testing.expect(std.mem.endsWith(u8, refused.text, "skein: a baseline is of a project without problems\n"));
    try repo.write("spec/lex.md", "%rule[lex.a] A.\n\n%rule[lex.b] B.\n");
    try repo.commit("mended");
    try testing.expect((try repo.baseline("v1", null)).ok);
    try testing.expectEqualStrings("skein: there is a tag 'v1' already\n", (try repo.baseline("v1", null)).text);
}
