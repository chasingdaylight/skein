//! A git repository made for a test: a small project, committed, and
//! `skein baseline` run in it.

const std = @import("std");
const testing = std.testing;

const baseline_command = @import("../baseline.zig");
const git_program = @import("../../git.zig");

const Repo = @This();

arena: std.heap.ArenaAllocator,
tmp: testing.TmpDir,
root: []const u8,

pub fn init(self: *Repo) !void {
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

pub fn deinit(self: *Repo) void {
    self.tmp.cleanup();
    self.arena.deinit();
}

pub fn git(self: *Repo, args: []const []const u8) !void {
    if (try git_program.output(testing.io, self.arena.allocator(), self.tmp.dir, args) == null) return error.GitFailed;
}

pub fn gitOutput(self: *Repo, args: []const []const u8) ![]const u8 {
    return try git_program.output(testing.io, self.arena.allocator(), self.tmp.dir, args) orelse error.GitFailed;
}

pub fn write(self: *Repo, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try self.tmp.dir.createDirPath(testing.io, parent);
    try self.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

pub fn commit(self: *Repo, message: []const u8) !void {
    try self.git(&.{ "add", "--all" });
    try self.git(&.{ "-c", "user.name=Tester", "-c", "user.email=tester@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", message });
}

pub fn baseline(self: *Repo, name: ?[]const u8, message: ?[]const u8) !struct { text: []const u8, ok: bool } {
    // the tag is made by git as the user: give the test one
    try self.git(&.{ "config", "user.name", "Tester" });
    try self.git(&.{ "config", "user.email", "tester@example.invalid" });
    const out = try baseline_command.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.root }, .name = name, .message = message });
    return .{ .text = out.text, .ok = out.status == .ok };
}
