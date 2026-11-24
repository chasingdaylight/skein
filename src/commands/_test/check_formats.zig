//! `skein check --format github|gitlab`: the problems for a CI system to
//! show on the lines of a change.

// req: check.formats
const std = @import("std");
const testing = std.testing;

const check_command = @import("../check.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

test "problems as GitHub annotations and as a GitLab Code Quality report" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
    try write(tmp.dir, ".skein/types/rule.toml", "");
    try write(tmp.dir, "spec/lex.md", "%rule[lex.a] Refers to %[lex.none], 100% sure.\n");
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    const github = try check_command.runFormatted(testing.io, a, .{ .common = .{ .root = root }, .format = .github });
    try testing.expectEqual(.problems, github.status);
    try testing.expect(github.to_stdout);
    try testing.expectEqualStrings("::error file=spec/lex.md,line=1,col=24,title=skein::lex.a: the text refers to 'lex.none', and there is no such item\n", github.text);

    const gitlab = try check_command.runFormatted(testing.io, a, .{ .common = .{ .root = root }, .format = .gitlab });
    const report = try std.json.parseFromSliceLeaky(std.json.Value, a, gitlab.text, .{});
    const finding = report.array.items[0].object;
    try testing.expectEqualStrings("major", finding.get("severity").?.string);
    try testing.expectEqualStrings("spec/lex.md", finding.get("location").?.object.get("path").?.string);
    try testing.expectEqual(1, finding.get("location").?.object.get("lines").?.object.get("begin").?.integer);
    try testing.expectEqual(32, finding.get("fingerprint").?.string.len);

    // nothing wrong: an empty report, and the job goes on
    try write(tmp.dir, "spec/lex.md", "%rule[lex.a] Fine.\n");
    const clean = try check_command.runFormatted(testing.io, a, .{ .common = .{ .root = root }, .format = .gitlab });
    try testing.expectEqual(.ok, clean.status);
    try testing.expectEqualStrings("[]\n", clean.text);
}
