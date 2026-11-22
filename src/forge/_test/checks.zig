//! References to issues and pull requests, checked against a forge that
//! the test stands in for.

// req: forge.refs, forge.check, forge.offline
const std = @import("std");
const testing = std.testing;

const Forge = @import("../Forge.zig");
const check_command = @import("../../commands/check.zig");
const checks = @import("../checks.zig");
const git_program = @import("../../git.zig");
const github = @import("../github.zig");

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

/// The forge as the test has it: #1 open, #2 closed, other/repo#4 open,
/// and the rest missing; or unreachable altogether
var reachable = true;
var asked: usize = 0;

fn fake(_: std.Io, _: std.mem.Allocator, _: *const Forge, r: Forge.Ref) anyerror!github.Answer {
    asked += 1;
    if (!reachable) return .{ .unreachable_ = "no network" };
    if (std.mem.eql(u8, r.repository, "other/repo")) return if (r.number == 4) .{ .found = .{ .title = "Elsewhere", .open = true, .pull = false } } else .missing;
    return switch (r.number) {
        1 => .{ .found = .{ .title = "Open one", .open = true, .pull = false } },
        2 => .{ .found = .{ .title = "Done", .open = false, .pull = true } },
        else => .missing,
    };
}

test "issues and pull requests are checked against the forge, and cached" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    _ = try git_program.output(testing.io, a, tmp.dir, &.{ "init", "--quiet" });
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[forge]\nrepository = \"example/spec\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, ".skein/links/tracked-by.toml", "open = true\n");
    try write(tmp.dir, ".skein/links/introduced-by.toml", "");
    try write(tmp.dir, "spec/lex.md",
        \\%rule[lex.a tracked-by=#1 introduced-by=#2] See %[other/repo#4] and %[#7].
        \\
        \\%rule[lex.b tracked-by=#2] Closed, and required open.
        \\
        \\Narrative about %[#1].
        \\
    );
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    const saved = checks.lookup;
    defer checks.lookup = saved;
    checks.lookup = fake;
    reachable = true;
    asked = 0;

    const online = (try check_command.run(testing.io, a, .{ .root = root })).text;
    try expectContains(online, "spec/lex.md:1:");
    try expectContains(online, "lex.a: the text refers to '#7', and example/spec has no such issue or pull request");
    try expectContains(online, "spec/lex.md:3:1: error: lex.b: tracked-by: the link points to '#2', which is closed");
    try expectContains(online, "skein: 2 problems");
    // each issue once: #1, #2, other/repo#4, #7
    try testing.expectEqual(4, asked);

    // the forge cannot be reached: what it said last is used
    reachable = false;
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "skein: 2 problems");
    // offline, nothing is asked
    asked = 0;
    try expectContains((try check_command.run(testing.io, a, .{ .root = root, .offline = true })).text, "skein: 2 problems");
    try testing.expectEqual(0, asked);

    // with nothing cached and no forge, they are not checked: a warning
    try tmp.dir.deleteTree(testing.io, ".git/skein/forge");
    const blind = (try check_command.run(testing.io, a, .{ .root = root })).text;
    try expectContains(blind, ".skein/config.toml: warning: forge: 6 references to issues and pull requests are not checked: no network");
    try expectContains(blind, "no problems, 1 warning");
}

test "without a forge, references to issues are accepted unchecked" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, "spec/lex.md", "%rule[lex.a] See %[#7].\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try expectContains((try check_command.run(testing.io, a, .{ .root = root })).text, "no problems (1 items");
}
