//! `skein approve --from-pull-request`, on a repository made for the test
//! and a forge the test stands in for.

// req: forge.approvals, forge.adapter
const std = @import("std");
const testing = std.testing;

const Forge = @import("../Forge.zig");
const approve_command = @import("../../commands/approve.zig");
const git_program = @import("../../git.zig");
const github = @import("../github.zig");
const pulls = @import("../pulls.zig");
const trace_command = @import("../../commands/trace.zig");

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

var base: []const u8 = "";
var merge: []const u8 = "";

fn fake(_: std.Io, arena: std.mem.Allocator, _: *const Forge, path: []const u8) anyerror!github.Reply {
    if (std.mem.endsWith(u8, path, "pulls/5")) return .{ .body = try arena.print("{{\"merged_at\": \"2026-11-21T20:15:00Z\", \"merge_commit_sha\": \"{s}\", \"base\": {{\"sha\": \"{s}\"}}}}", .{ merge, base }) };
    if (std.mem.endsWith(u8, path, "pulls/5/reviews?per_page=100")) return .{ .body = "[{\"user\": {\"login\": \"ann\"}, \"state\": \"APPROVED\"}, {\"user\": {\"login\": \"bob\"}, \"state\": \"COMMENTED\"}]" };
    if (std.mem.endsWith(u8, path, "pulls/6")) return .{ .body = "{\"merged_at\": null, \"merge_commit_sha\": null, \"base\": {\"sha\": \"x\"}}" };
    if (std.mem.endsWith(u8, path, "pulls/6/reviews?per_page=100")) return .{ .body = "[]" };
    return .missing;
}

fn commit(a: std.mem.Allocator, dir: std.Io.Dir) ![]const u8 {
    _ = try git_program.output(testing.io, a, dir, &.{ "add", "--all" });
    _ = try git_program.output(testing.io, a, dir, &.{ "-c", "user.name=Tester", "-c", "user.email=tester@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "change" });
    return std.mem.trim(u8, (try git_program.output(testing.io, a, dir, &.{ "rev-parse", "HEAD" })).?, " \r\n");
}

test "a merged pull request's approvals are recorded for what it changed" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "init", "--quiet" });
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[forge]\nrepository = \"example/spec\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, "spec/lex.md", "%rule[lex.a] First.\n\n%rule[lex.c] Unchanged.\n");
    base = try commit(a, tmp.dir);
    try write(tmp.dir, "spec/lex.md", "%rule[lex.a] First, changed.\n\n%rule[lex.b] Added.\n\n%rule[lex.c] Unchanged.\n");
    merge = try commit(a, tmp.dir);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    const saved = pulls.call;
    defer pulls.call = saved;
    pulls.call = fake;
    const out = try approve_command.run(testing.io, a, .{ .common = .{ .root = root }, .ids = &.{}, .from_pull_request = 5 });
    try testing.expectEqualStrings("skein: pull request 5, merged 2026-11-21: 2 items approved by ann\n", out.text);
    try expectContains((try trace_command.run(testing.io, a, .{ .common = .{ .root = root }, .id = "lex.b" })).text, "Approved by:\n  ann on 2026-11-21\n");
    const c = (try trace_command.run(testing.io, a, .{ .common = .{ .root = root }, .id = "lex.c" })).text;
    try testing.expect(std.mem.find(u8, c, "Approved by") == null);

    const unmerged = try approve_command.run(testing.io, a, .{ .common = .{ .root = root }, .ids = &.{}, .from_pull_request = 6 });
    try testing.expectEqualStrings("skein: pull request 6 is not merged\n", unmerged.text);
    const missing = try approve_command.run(testing.io, a, .{ .common = .{ .root = root }, .ids = &.{}, .from_pull_request = 7 });
    try testing.expectEqualStrings("skein: example/spec has no pull request 7\n", missing.text);
}
