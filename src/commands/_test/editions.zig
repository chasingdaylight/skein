//! `skein render --editions`, on a git repository made for the test: each
//! baseline rendered beside the files as they are, and the page that lists
//! them.

// req: render.editions
const std = @import("std");
const testing = std.testing;

const Repo = @import("Repo.zig");
const render_command = @import("../render.zig");

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

test "the baselines rendered beside the files as they are" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    try testing.expect((try repo.baseline("v1", null)).ok);
    try repo.write("spec/lex.md", "%rule[lex.a] A, as it is now.\n\n%rule[lex.b] B.\n");
    try repo.commit("second");
    try testing.expect((try repo.baseline("v2", null)).ok);
    try repo.write("spec/lex.md", "%rule[lex.a] A, not yet committed.\n\n%rule[lex.b] B.\n");

    const out_dir = try std.Io.Dir.path.join(a, &.{ repo.root, "site" });
    const done = try render_command.run(testing.io, a, .{ .common = .{ .root = repo.root }, .out = out_dir, .editions = true });
    try testing.expectEqual(.ok, done.status);
    try expectContains(done.text, "2 editions listed in");
    const read = struct {
        fn f(r: *Repo, path: []const u8) ![]const u8 {
            return r.tmp.dir.readFileAlloc(testing.io, path, r.arena.allocator(), .limited(1 << 16));
        }
    }.f;
    try expectContains(try read(&repo, "site/spec/lex.md"), "A, not yet committed.");
    try expectContains(try read(&repo, "site/editions/v1/spec/lex.md"), "A.");
    try expectContains(try read(&repo, "site/editions/v2/spec/lex.md"), "A, as it is now.");
    const index = try read(&repo, "site/editions/index.md");
    try expectContains(index, "- [Current](../): the files as they are now\n- [v2](v2/): baseline of ");
    try expectContains(index, "- [v1](v1/): baseline of ");

    const html_dir = try std.Io.Dir.path.join(a, &.{ repo.root, "html" });
    _ = try render_command.run(testing.io, a, .{ .common = .{ .root = repo.root }, .out = html_dir, .format = .html, .editions = true });
    try expectContains(try read(&repo, "html/editions/index.html"), "<li><a href=\"v2/index.html\">v2</a>");
}
